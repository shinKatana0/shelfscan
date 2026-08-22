/// GOG Galaxy's local library database, read in the shell (T-0177).
///
/// `shelfscan_core` may not open a file and may not gain a dependency, so the
/// SQLite half lives here and hands [GogLibrarySource] the same thing T-0157's
/// source gets: text. The app carries a second copy of this file for the same
/// reason `heic_wic.dart` exists -- a shell capability cannot be shared through
/// core without putting `dart:ffi` in `lib/`, and a test now fails if it ever
/// is.
///
/// **No package.** `dart:ffi` is in the SDK and Windows has shipped the SQLite
/// engine itself since 1803: `C:\Windows\System32\winsqlite3.dll`, 3.51.1 when
/// this was measured. So the whole feature costs zero pub packages, zero
/// bytes in the Android APK and no build step -- the alternatives are priced in
/// decision 0001 (T-0177). Not `package:ffi` either: the allocator is
/// `sqlite3_malloc` out of the library already open, which is why nothing here
/// needs one.
///
/// **The file is owned by a running application and is in WAL mode**, so how it
/// is opened is not a detail. Measured 2026-08-16, hashing all three of
/// `.db`/`-wal`/`-shm` before and after:
///
/// | open | sees the WAL | touches the original |
/// | --- | --- | --- |
/// | `mode=ro` | yes | **yes** -- `-shm` mtime moves, taking read locks |
/// | `mode=ro&immutable=1` | **no** -- reports `journal_mode delete` | no |
/// | copy `.db` + `-wal`, open the copy | yes | no |
///
/// The third is what this does, and the second is the trap. **`immutable=1`
/// makes SQLite ignore the write-ahead log**, so a Galaxy that has written
/// since its last checkpoint answers *fewer rows than the database holds* --
/// no error, no warning, nothing the caller can inspect. Confirmed by running
/// both opens against a live file: `GamePieces` came back short under
/// `immutable=1` and complete under `mode=ro`, and the difference was exactly
/// what the log carried. `mode=ro` is complete but takes locks in a file
/// another process owns. Copying costs one 3 MB read and is the only one that
/// is both.
///
/// The short answer landed on game-piece cache rather than on the library
/// table, so **the consequence was not observed on the library table**. The
/// mechanism is measured; the loss to this feature is not, and it would be
/// whatever the log happens to hold when a scan runs.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:shelfscan_core/shelfscan_core.dart';

/// Galaxy's own default. Overridable because the client's `config.json` can
/// move the *games* elsewhere, and because nothing should hard-fail on a path.
const galaxyDatabasePath =
    r'C:\ProgramData\GOG.com\Galaxy\storage\galaxy-2.0.db';

/// The library could not be read, and why -- always for a reason the owner can
/// act on. Absence, corruption and a rebuild are normal states here, not edge
/// cases: Galaxy rebuilds a corrupt database on next launch and leaves the old
/// one beside it as `galaxy.db.corrupt`, so either file may be missing or stale
/// at any moment.
class GalaxyLibraryException implements Exception {
  GalaxyLibraryException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// One read of the library: the rows, and how old they are.
class GalaxyLibrary {
  GalaxyLibrary({
    required this.entries,
    required this.asOf,
    required this.schemaVersion,
  });

  /// One entry per library row, for [GogLibrarySource].
  final List<SourceEntry> entries;

  /// **The last time Galaxy wrote the database, which is the only date in it.**
  /// `GamePieceCacheUpdateDates` is the table that would say when the account
  /// was last synced and it is empty; `LimitedDetails.stored_at` likewise. So
  /// this is a modification time, not a sync time, and it is an upper bound:
  /// the library is at best this fresh and may be older.
  ///
  /// Taken as the later of the `.db` and its `-wal`. Under WAL mode the main
  /// file is only stamped at a checkpoint, so on a running Galaxy it lags the
  /// log by however long since the last one -- measured 10 minutes behind on
  /// a real file while Galaxy was writing (14:51:31 against 15:01:16).
  final DateTime asOf;

  /// `PRAGMA user_version`, 40 when this was written. The vendor's own schema
  /// marker and the cheapest way to notice they have moved it.
  final int schemaVersion;
}

/// The schema version this reader was written against and verified on.
const galaxySchemaVersion = 40;

/// Why the owner should not read the row count as "my account".
String galaxyStalenessNote(GalaxyLibrary library) =>
    'GOG Galaxy library as of ${library.asOf.toLocal()} -- this is a local '
    'cache of the last sync, not a live read of the account: a game bought '
    'since then is missing and one removed since may still be listed. '
    'Nothing was read from gog.com and no credential was used.';

/// The query, and the whole of what this reader relies on.
///
/// Three tables carry the library and one carries the title. Every other table
/// in the file is treated as absent -- including `InstalledProducts` and
/// `InstalledBaseProducts`, for which **no populated sample was available to
/// read the schema off**, so reading them would be code written against a
/// guess.
///
/// `GamePieces.value` is a JSON blob and the title is `{"title": "..."}` inside
/// it. Every library row measured carried exactly one such piece, so the join
/// returned one row per release -- but that is an observation about one
/// install and not a constraint the vendor declares, so the join is not left
/// resting on it. A release carrying two title pieces comes back as two
/// entries under the same `releaseKey`, and neither is lost quietly: identical
/// titles are one row after stage 2's dedupe, differing ones are two rows in
/// front of the reviewer. What cannot happen is a title being silently
/// replaced by another piece's.
///
/// `title` and not `originalTitle`: the two were equal on every row measured,
/// and `title` is the one the client would show if they ever differ.
const galaxyLibrarySql = '''
SELECT lr.releaseKey,
       gp.value,
       rp.isDlc,
       rp.isVisibleInLibrary
FROM LibraryReleases lr
JOIN LicensedReleases lic ON lic.libraryId = lr.id AND lic.isOwned = 1
JOIN GamePieceTypes t ON t.type = 'title'
JOIN GamePieces gp ON gp.releaseKey = lr.releaseKey AND gp.gamePieceTypeId = t.id
LEFT JOIN ReleaseProperties rp ON rp.releaseKey = lr.releaseKey
''';

/// Turns one query row into the JSON [GogLibrarySource] parses.
///
/// Shared with the app's copy of this reader through the source's own tests
/// rather than through code, which is the cost of the boundary; the shape is
/// four keys and is asserted on both sides.
String galaxyRowToJson(
  String releaseKey,
  String titlePieceJson,
  int? isDlc,
  int? isVisibleInLibrary,
) {
  String? title;
  try {
    final decoded = jsonDecode(titlePieceJson);
    if (decoded is Map && decoded['title'] is String) {
      title = decoded['title'] as String;
    }
  } on FormatException {
    // Left null: the source declines a row with no title by name, which is the
    // reporting path, rather than this layer inventing one or dropping the row.
  }
  return jsonEncode({
    'releaseKey': releaseKey,
    if (title != null) 'title': title,
    'isDlc': isDlc,
    'isVisibleInLibrary': isVisibleInLibrary,
  });
}

/// Reads [path] and returns the library, or throws [GalaxyLibraryException].
GalaxyLibrary readGalaxyLibrary({String path = galaxyDatabasePath}) {
  if (!Platform.isWindows) {
    throw GalaxyLibraryException(
        'The GOG Galaxy library database is Windows-only (Galaxy does not run '
        'on ${Platform.operatingSystem})');
  }
  final file = File(path);
  if (!file.existsSync()) {
    throw GalaxyLibraryException(
        'No GOG Galaxy library database at $path. Galaxy rebuilds it on next '
        'launch if it was lost; install or run Galaxy once, or pass the path '
        'if it lives elsewhere.');
  }
  var asOf = file.lastModifiedSync();
  final liveLog = File('$path-wal');
  if (liveLog.existsSync()) {
    final logged = liveLog.lastModifiedSync();
    if (logged.isAfter(asOf)) asOf = logged;
  }

  final work = Directory.systemTemp.createTempSync('shelfscan_galaxy');
  try {
    // Copy-then-read, for the reason in this file's header. Twice at most: the
    // source is being written while it is copied, so a copy can catch a
    // checkpoint mid-flight. SQLite discards log frames that fail their own
    // checksums, which degrades to an older consistent view rather than a
    // wrong one, but a torn main file it cannot -- hence the check and the one
    // retry, rather than trusting a copy that came back bad.
    final copy = '${work.path}${Platform.pathSeparator}galaxy.db';
    var db = _copyAndOpen(file, path, copy);
    if (db == null) {
      db = _copyAndOpen(file, path, copy);
      if (db == null) {
        throw GalaxyLibraryException(
            'The GOG Galaxy database at $path failed SQLite\'s integrity check '
            'twice. If Galaxy is running, close it and scan again; if it is '
            'not, the file is corrupt -- Galaxy rebuilds it on next launch and '
            'leaves the old one as galaxy.db.corrupt.');
      }
    }
    try {
      final version = db.scalarInt('PRAGMA user_version') ?? 0;
      final rows = db.query(galaxyLibrarySql);
      if (rows.isEmpty) {
        // Zero rows out of a database that exists is a failure, not an empty
        // library -- a schema that moved answers exactly this way, and a
        // silent empty result is the defect class decision 0012 names.
        throw GalaxyLibraryException(
            'The GOG Galaxy database at $path returned no library rows. Either '
            'no GOG account is signed in to Galaxy on this machine, or the '
            'schema has changed (this reader was written against PRAGMA '
            'user_version $galaxySchemaVersion, found $version).');
      }
      return GalaxyLibrary(
        asOf: asOf,
        schemaVersion: version,
        entries: [
          for (final row in rows)
            SourceEntry(
              name: row[0] as String? ?? '?',
              container: GogLibrarySource.databaseName,
              content: galaxyRowToJson(
                row[0] as String? ?? '',
                row[1] as String? ?? '',
                row[2] as int?,
                row[3] as int?,
              ),
            ),
        ],
      );
    } finally {
      db.close();
    }
  } on _SqliteException catch (e) {
    throw GalaxyLibraryException(
        'The GOG Galaxy database at $path could not be read: $e. GOG does not '
        'document this schema and does not know this reader exists, so an '
        'update of theirs can move it; the file may also be corrupt (Galaxy '
        'leaves a galaxy.db.corrupt beside it and rebuilds).');
  } finally {
    try {
      work.deleteSync(recursive: true);
    } on FileSystemException {
      // A temp copy left behind is not worth failing a scan over.
    }
  }
}

/// Copies the database and its log, opens the copy, and returns it only if
/// SQLite agrees the copy is intact; null means "try again".
_Sqlite? _copyAndOpen(File file, String path, String copy) {
  for (final leftover in [File(copy), File('$copy-wal'), File('$copy-shm')]) {
    if (leftover.existsSync()) leftover.deleteSync();
  }
  file.copySync(copy);
  // The `-wal` comes too, or the newest rows are silently missing -- whatever
  // Galaxy has written since its last checkpoint.
  final wal = File('$path-wal');
  if (wal.existsSync()) wal.copySync('$copy-wal');

  final db = _Sqlite.open(copy);
  final check = db.query('PRAGMA quick_check');
  final ok = check.isNotEmpty && check.first.isNotEmpty && check.first.first == 'ok';
  if (ok) return db;
  db.close();
  return null;
}

// ---------------------------------------------------------------------------
// The engine. Windows ships SQLite as `winsqlite3.dll` and has since 1803, so
// nothing is bundled and no package is added. Microsoft documents it as a
// component for Windows' own use rather than as a public API, which is the one
// caveat on this route: `sqlite3.dll` beside the executable wins if present, so
// a future build can ship its own without this file changing.

class _SqliteException implements Exception {
  _SqliteException(this.message);
  final String message;
  @override
  String toString() => message;
}

const _openReadonly = 0x00000001;
const _row = 100;
const _done = 101;
const _ok = 0;

final DynamicLibrary _lib = _openLibrary();

DynamicLibrary _openLibrary() {
  for (final name in ['sqlite3.dll', 'winsqlite3.dll']) {
    final DynamicLibrary library;
    try {
      library = DynamicLibrary.open(name);
    } on ArgumentError {
      continue;
    }
    // An engine built with SQLITE_OMIT_AUTOINIT takes the whole process down
    // on the first sqlite3_malloc -- no exception, no message, the host just
    // exits (GitHub runner, 2026-08-18). Windows' own winsqlite3.dll
    // auto-initialises, so it shows only where a sqlite3.dll wins the search.
    final initialize =
        library.lookupFunction<Int32 Function(), int Function()>(
            'sqlite3_initialize');
    final code = initialize();
    // A library that loaded and refused to initialise is a broken engine, not
    // an absent one, so this does not fall through to the next candidate.
    if (code != _ok) {
      throw _SqliteException(
          'the SQLite engine in $name did not initialise '
          '(sqlite3_initialize -> $code)');
    }
    return library;
  }
  throw _SqliteException(
      'no SQLite engine: neither sqlite3.dll nor winsqlite3.dll could be '
      'loaded (winsqlite3.dll ships with Windows 10 1803 and later)');
}

final _open = _lib.lookupFunction<
    Int32 Function(Pointer<Uint8>, Pointer<Pointer<Void>>, Int32, Pointer<Void>),
    int Function(Pointer<Uint8>, Pointer<Pointer<Void>>, int,
        Pointer<Void>)>('sqlite3_open_v2');

final _closeV2 = _lib.lookupFunction<Int32 Function(Pointer<Void>),
    int Function(Pointer<Void>)>('sqlite3_close_v2');

final _prepare = _lib.lookupFunction<
    Int32 Function(Pointer<Void>, Pointer<Uint8>, Int32, Pointer<Pointer<Void>>,
        Pointer<Pointer<Uint8>>),
    int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Pointer<Void>>,
        Pointer<Pointer<Uint8>>)>('sqlite3_prepare_v2');

final _step = _lib.lookupFunction<Int32 Function(Pointer<Void>),
    int Function(Pointer<Void>)>('sqlite3_step');

final _finalize = _lib.lookupFunction<Int32 Function(Pointer<Void>),
    int Function(Pointer<Void>)>('sqlite3_finalize');

final _columnCount = _lib.lookupFunction<Int32 Function(Pointer<Void>),
    int Function(Pointer<Void>)>('sqlite3_column_count');

final _columnType = _lib.lookupFunction<Int32 Function(Pointer<Void>, Int32),
    int Function(Pointer<Void>, int)>('sqlite3_column_type');

final _columnText = _lib.lookupFunction<
    Pointer<Uint8> Function(Pointer<Void>, Int32),
    Pointer<Uint8> Function(Pointer<Void>, int)>('sqlite3_column_text');

final _columnInt = _lib.lookupFunction<Int64 Function(Pointer<Void>, Int32),
    int Function(Pointer<Void>, int)>('sqlite3_column_int64');

final _errmsg = _lib.lookupFunction<Pointer<Uint8> Function(Pointer<Void>),
    Pointer<Uint8> Function(Pointer<Void>)>('sqlite3_errmsg');

/// The allocator, taken from the library already open rather than from
/// `package:ffi` -- one fewer dependency for six lines.
final _malloc = _lib.lookupFunction<Pointer<Uint8> Function(Int32),
    Pointer<Uint8> Function(int)>('sqlite3_malloc');

final _free = _lib.lookupFunction<Void Function(Pointer<Uint8>),
    void Function(Pointer<Uint8>)>('sqlite3_free');

/// SQLite column type 5.
const _columnTypeNull = 5;

Pointer<Uint8> _toC(String value) {
  final bytes = utf8.encode(value);
  final pointer = _malloc(bytes.length + 1);
  if (pointer == nullptr) throw _SqliteException('out of memory');
  pointer.asTypedList(bytes.length + 1)
    ..setRange(0, bytes.length, bytes)
    ..[bytes.length] = 0;
  return pointer;
}

String _fromC(Pointer<Uint8> pointer) {
  if (pointer == nullptr) return '';
  var length = 0;
  while (pointer[length] != 0) {
    length++;
  }
  return utf8.decode(pointer.asTypedList(length), allowMalformed: true);
}

class _Sqlite {
  _Sqlite._(this._db);

  final Pointer<Void> _db;

  static _Sqlite open(String path) {
    final name = _toC(path);
    final out = _malloc(sizeOf<Pointer<Void>>()).cast<Pointer<Void>>();
    try {
      final code = _open(name, out, _openReadonly, nullptr);
      final handle = out.value;
      if (code != _ok) {
        final message = handle == nullptr ? 'code $code' : _fromC(_errmsg(handle));
        if (handle != nullptr) _closeV2(handle);
        throw _SqliteException('cannot open: $message');
      }
      return _Sqlite._(handle);
    } finally {
      _free(name);
      _free(out.cast());
    }
  }

  List<List<Object?>> query(String sql) {
    final text = _toC(sql);
    final out = _malloc(sizeOf<Pointer<Void>>()).cast<Pointer<Void>>();
    try {
      if (_prepare(_db, text, -1, out, nullptr) != _ok) {
        throw _SqliteException(_fromC(_errmsg(_db)));
      }
      final statement = out.value;
      try {
        final columns = _columnCount(statement);
        final rows = <List<Object?>>[];
        while (true) {
          final code = _step(statement);
          if (code == _done) break;
          if (code != _row) throw _SqliteException(_fromC(_errmsg(_db)));
          rows.add([
            for (var i = 0; i < columns; i++)
              switch (_columnType(statement, i)) {
                _columnTypeNull => null,
                1 => _columnInt(statement, i),
                _ => _fromC(_columnText(statement, i)),
              },
          ]);
        }
        return rows;
      } finally {
        _finalize(statement);
      }
    } finally {
      _free(text);
      _free(out.cast());
    }
  }

  int? scalarInt(String sql) {
    final rows = query(sql);
    final value = rows.isEmpty || rows.first.isEmpty ? null : rows.first.first;
    return value is int ? value : null;
  }

  void close() => _closeV2(_db);
}
