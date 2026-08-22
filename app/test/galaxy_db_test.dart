/// The app shell's read of GOG Galaxy's local library (T-0177).
///
/// Two things are pinned here that nothing else can pin. The first is that the
/// **three failure states are named rather than crashed on**: a
/// `galaxy.db.corrupt` sits beside the live file on a development machine, so
/// absence, corruption and a rebuild are normal states for this file and not
/// edge cases. The second is that this file and the CLI's copy of it **have
/// not drifted** -- they must be copies, because a `dart:ffi` import under
/// `packages/shelfscan_core/lib/` would break the platform boundary, and two
/// copies of a query are two chances to fix one of them.
///
/// Nothing here reads a real database. The rows it does read are ones it
/// wrote itself.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shelfscan_app/galaxy_db.dart';
import 'package:shelfscan_core/shelfscan_core.dart';

/// The CLI's copy, as text. Both shells live in one repository and the app's
/// tests already reach out of `app/` for `data/title_aliases.json`.
///
/// Newlines are folded to `\n`: the repository has no `.gitattributes`, so on
/// Windows git checks this file out with CRLF while the string literals
/// compared against it are LF. Without the fold the guard fails on a clean
/// checkout and reports drift that is not there (merge, 2026-08-16).
String _cliReader() =>
    File('../packages/shelfscan_core/bin/galaxy_db.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');

/// The app's own copy, as text. Read rather than imported: what is guarded
/// below is a private function that runs once per process, against whichever
/// engine that machine happens to load.
String _appReader() => File('lib/galaxy_db.dart').readAsStringSync();

void main() {
  group('the two shells have not drifted', () {
    test('the CLI copy declares the identical SQL', () {
      // A query that differs between the shells is a library that differs
      // between them, and nothing else in the build would say so.
      final cli = _cliReader();
      expect(cli, contains(galaxyLibrarySql.trim()));
    });

    test('the CLI copy is written against the same schema version', () {
      expect(_cliReader(),
          contains('const galaxySchemaVersion = $galaxySchemaVersion;'));
    });

    test('both shells point at the same default path', () {
      expect(_cliReader(), contains(galaxyDatabasePath));
    });

    test('both shells initialise the engine, and call what they look up', () {
      // sqlite3_malloc before sqlite3_initialize takes the whole process down
      // -- no exception, no message -- on an engine built with
      // SQLITE_OMIT_AUTOINIT, which is what a GitHub runner loads (T-0240).
      // A lookup that is never invoked is the defect, so what is asserted is
      // the call and not the symbol.
      final shells = {'app/lib': _appReader(), 'core/bin': _cliReader()};
      for (final shell in shells.entries) {
        // Whitespace flattened: the two files wrap this differently, and a
        // CRLF checkout would otherwise read as a missing call.
        final source = shell.value.replaceAll(RegExp(r'\s+'), ' ');
        final lookup = RegExp(
                r"""(\w+) = \w+\.lookupFunction<[^;]*'sqlite3_initialize'\);""")
            .firstMatch(source);
        expect(lookup, isNotNull,
            reason: '${shell.key} never looks up sqlite3_initialize');
        expect(source, contains('${lookup!.group(1)}();'),
            reason:
                '${shell.key} looks sqlite3_initialize up and never calls it');
      }
    });
  });

  group('the row the shell hands core', () {
    test('the four keys, and the title lifted out of the game piece', () {
      final row = jsonDecode(galaxyRowToJson(
          'gog_1100000013', jsonEncode({'title': 'Harbour of Tin'}), 0, 1));
      expect(row, {
        'releaseKey': 'gog_1100000013',
        'title': 'Harbour of Tin',
        'isDlc': 0,
        'isVisibleInLibrary': 1,
      });
    });

    test('an unparseable game piece leaves the title out, for the source to '
        'decline by name', () {
      final row = jsonDecode(galaxyRowToJson('gog_1', '{not json', null, null));
      expect(row.containsKey('title'), isFalse);
      // The pair that matters: this layer does not invent a title, and the
      // source then reports the row rather than dropping it silently.
      expect(const GogLibrarySource().read(SourceEntry(
              name: 'gog_1', content: jsonEncode(row))).declined.single.reason,
          GogLibrarySource.noTitle);
    });

    test('a row survives the whole shell-to-source hop with its product id',
        () {
      final entry = SourceEntry(
        name: 'gog_1100000013',
        container: GogLibrarySource.databaseName,
        content: galaxyRowToJson('gog_1100000013',
            jsonEncode({'title': 'Harbour of Tin'}), 0, 1),
      );
      expect(const GogLibrarySource().read(entry).items.single.sourceId,
          'gog:1100000013');
    });
  });

  group('absence, corruption and the wrong platform are named, not crashed on',
      () {
    test('a platform Galaxy does not run on is refused by name', () {
      expect(galaxyUnsupported('android'), contains('android'));
      expect(galaxyUnsupported('linux'), isNotNull);
      expect(galaxyUnsupported('windows'), isNull);
    });

    test('an absent database says so and says Galaxy rebuilds it', () {
      final missing =
          '${Directory.systemTemp.path}${Platform.pathSeparator}no-such-galaxy.db';
      expect(
          () => readGalaxyLibrarySync(path: missing),
          throwsA(isA<GalaxyLibraryException>()
              .having((e) => e.message, 'message', contains('rebuilds'))));
    }, testOn: 'windows');

    test('a corrupt file is a named failure, not a crash and not zero games',
        () {
      // The state this file has already been in on a development machine:
      // Galaxy left a galaxy.db.corrupt beside the live one.
      final dir = Directory.systemTemp.createTempSync('galaxy_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}${Platform.pathSeparator}galaxy-2.0.db';
      File(path).writeAsBytesSync(
          List<int>.generate(4096, (i) => (i * 31 + 7) % 256));
      expect(() => readGalaxyLibrarySync(path: path),
          throwsA(isA<GalaxyLibraryException>()));
    }, testOn: 'windows');

    test('a database with no library tables says the schema may have moved',
        () {
      // An empty file is a valid empty SQLite database, so this is the
      // schema-moved path exactly: the file opens, the query does not.
      final dir = Directory.systemTemp.createTempSync('galaxy_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}${Platform.pathSeparator}galaxy-2.0.db';
      File(path).writeAsBytesSync(const []);
      expect(
          () => readGalaxyLibrarySync(path: path),
          throwsA(isA<GalaxyLibraryException>()
              .having((e) => e.message, 'message', contains('schema'))));
    }, testOn: 'windows');

    test('the staleness note says cache, not account', () {
      final note = galaxyStalenessNote(GalaxyLibrary(
        entries: const [],
        asOf: DateTime(2026, 6, 30, 21, 24),
        schemaVersion: galaxySchemaVersion,
      ));
      expect(note, contains('cache'));
      expect(note, contains('not a live read of the account'));
    });
  });
}
