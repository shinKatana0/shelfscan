/// GOG Galaxy's local library database, read in the app shell (T-0177).
///
/// **A deliberate copy of `packages/shelfscan_core/bin/galaxy_db.dart`.** The
/// two shells cannot share this through core: the read is `dart:ffi` and a
/// `dart:ffi` import under `lib/` breaks the platform boundary that lets this
/// pipeline run on Android, which is now pinned by a test in
/// `gog_library_test.dart`. `heic_wic.dart` is the same shape of duplication
/// for the same reason -- the CLI reaches WIC through PowerShell and this file
/// reaches it through COM. `galaxy_db_test.dart` compares the SQL and the
/// namespace against the CLI's copy so the two cannot drift in silence.
///
/// **No package is added for this.** `dart:ffi` is in the SDK and Windows has
/// shipped the SQLite engine itself since 1803 (`winsqlite3.dll`, 3.51.1 when
/// this was measured), so the Android build gains nothing to
/// download, nothing to compile and no bytes -- the alternatives, and what
/// they would have cost the APK, are argued in decision 0001 (T-0177). The
/// `ffi` package already in `pubspec.yaml` is `heic_wic.dart`'s allocator and
/// is not used here: `sqlite3_malloc` comes out of the library already open.
///
/// **Windows only, and that is not a limitation.** GOG Galaxy does not run on
/// Android, so there is no such file to read there; the refusal names the
/// platform rather than pretending to try, exactly as `heicDecodeUnsupported`
/// does.
///
/// Nothing here reaches gog.com. No login, no OAuth, no credential is read,
/// stored or needed -- the online library would need all four and is a
/// different task.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:shelfscan_core/shelfscan_core.dart';

const galaxyDatabasePath =
    r'C:\ProgramData\GOG.com\Galaxy\storage\galaxy-2.0.db';

/// The schema version this reader was written against and verified on
/// (`PRAGMA user_version`, 2026-08-16).
const galaxySchemaVersion = 40;

/// The query, and the whole of what this reader relies on. Identical to the
/// CLI's, by test.
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

  final List<SourceEntry> entries;

  /// The later of the database's and its write-ahead log's modification time.
  /// Nothing in the file dates the sync itself -- the two tables that would
  /// (`GamePieceCacheUpdateDates`, `LimitedDetails.stored_at`) are empty -- so
  /// this is an upper bound on freshness and not a sync time.
  final DateTime asOf;

  final int schemaVersion;
}

/// Why [operatingSystem] cannot read a GOG Galaxy library, or null when it can.
String? galaxyUnsupported(String operatingSystem) => operatingSystem == 'windows'
    ? null
    : 'GOG Galaxy does not run on $operatingSystem, so there is no local '
        'library database to read here';

/// What the user is told before they trust the row count.
String galaxyStalenessNote(GalaxyLibrary library) =>
    'GOG Galaxy library as of ${library.asOf.toLocal()} -- a local cache of '
    'the last sync, not a live read of the account: a game bought since then '
    'is missing and one removed since may still be listed.';

/// Turns one query row into the JSON [GogLibrarySource] parses.
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
    // Left null so the source declines the row by name, which is the reporting
    // path; this layer does not invent a title and does not drop the row.
  }
  return jsonEncode({
    'releaseKey': releaseKey,
    if (title != null) 'title': title,
    'isDlc': isDlc,
    'isVisibleInLibrary': isVisibleInLibrary,
  });
}

/// Reads [path] and returns the library, or throws [GalaxyLibraryException].
///
/// Off the UI isolate: the copy is 3 MB plus however large the write-ahead log
/// has grown, and a frame is 16 ms.
Future<GalaxyLibrary> readGalaxyLibrary({String path = galaxyDatabasePath}) {
  final unsupported = galaxyUnsupported(Platform.operatingSystem);
  if (unsupported != null) {
    return Future.error(GalaxyLibraryException(unsupported));
  }
  return Isolate.run(() => readGalaxyLibrarySync(path: path));
}

/// The read itself. Public so a test can drive it against a database it made.
GalaxyLibrary readGalaxyLibrarySync({String path = galaxyDatabasePath}) {
  final file = File(path);
  if (!file.existsSync()) {
    throw GalaxyLibraryException(
        'No GOG Galaxy library database at $path. Galaxy rebuilds it on next '
        'launch if it was lost; install or run Galaxy once.');
  }
  var asOf = file.lastModifiedSync();
  final liveLog = File('$path-wal');
  if (liveLog.existsSync()) {
    final logged = liveLog.lastModifiedSync();
    if (logged.isAfter(asOf)) asOf = logged;
  }

  final work = Directory.systemTemp.createTempSync('shelfscan_galaxy');
  try {
    // Copy-then-read. The file belongs to a running Galaxy and is in WAL mode:
    // `immutable=1` ignores the log, so it answers fewer rows than the database
    // holds and reports nothing (measured 2026-08-16 against a live file:
    // `GamePieces` short under `immutable=1`, complete under `mode=ro`), and
    // `mode=ro` writes to the `-shm` of a file another process owns. Copying
    // both is the only read that is complete and inert. Twice at most, because
    // the source is being written while it is copied.
    final copy = '${work.path}${Platform.pathSeparator}galaxy.db';
    var db = _copyAndOpen(file, path, copy) ?? _copyAndOpen(file, path, copy);
    if (db == null) {
      throw GalaxyLibraryException(
          'The GOG Galaxy database at $path failed SQLite\'s integrity check '
          'twice. If Galaxy is running, close it and try again; if it is not, '
          'the file is corrupt and Galaxy rebuilds it on next launch.');
    }
    try {
      final version = db.scalarInt('PRAGMA user_version') ?? 0;
      final rows = db.query(galaxyLibrarySql);
      if (rows.isEmpty) {
        // Zero rows out of a database that exists is a failure, not an empty
        // library: a schema that moved answers exactly this way, and a silent
        // empty result is the defect class decision 0012 names.
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
        'document this schema and does not know this reader exists, so one of '
        'their updates can move it.');
  } finally {
    try {
      work.deleteSync(recursive: true);
    } on FileSystemException {
      // A temp copy left behind is not worth failing a scan over.
    }
  }
}

_Sqlite? _copyAndOpen(File file, String path, String copy) {
  for (final leftover in [File(copy), File('$copy-wal'), File('$copy-shm')]) {
    if (leftover.existsSync()) leftover.deleteSync();
  }
  file.copySync(copy);
  final wal = File('$path-wal');
  if (wal.existsSync()) wal.copySync('$copy-wal');

  final db = _Sqlite.open(copy);
  final check = db.query('PRAGMA quick_check');
  final ok =
      check.isNotEmpty && check.first.isNotEmpty && check.first.first == 'ok';
  if (ok) return db;
  db.close();
  return null;
}

// ---------------------------------------------------------------------------
// The engine, over `dart:ffi`. `sqlite3.dll` beside the executable wins if a
// future build ships one; otherwise Windows' own, which Microsoft documents as
// a component for Windows' use rather than as a public API -- the one caveat
// on this route, and the reason the override is here rather than added later.

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
const _columnTypeNull = 5;
const _columnTypeInt = 1;

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
/// `package:ffi` -- which this app has, for `heic_wic.dart`, and which this
/// file deliberately does not reach for.
final _malloc = _lib.lookupFunction<Pointer<Uint8> Function(Int32),
    Pointer<Uint8> Function(int)>('sqlite3_malloc');

final _free = _lib.lookupFunction<Void Function(Pointer<Uint8>),
    void Function(Pointer<Uint8>)>('sqlite3_free');

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
        final message =
            handle == nullptr ? 'code $code' : _fromC(_errmsg(handle));
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
                _columnTypeInt => _columnInt(statement, i),
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
