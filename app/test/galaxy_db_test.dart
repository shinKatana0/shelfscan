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

/// The CLI copy, named as a reader would type it from the repository root.
/// [_cliReader] reaches it from `app/`, which is where this suite runs.
const _cliPath = 'packages/shelfscan_core/bin/galaxy_db.dart';

/// The CLI's copy, as text -- both shells live in one repository, so the
/// other one is a relative path away.
///
/// Newlines are folded to `\n`: the repository has no `.gitattributes`, so on
/// Windows git checks this file out with CRLF while the string literals
/// compared against it are LF. Without the fold the guard fails on a clean
/// checkout and reports drift that is not there (merge, 2026-08-16).
String _cliReader() =>
    File('../$_cliPath').readAsStringSync().replaceAll('\r\n', '\n');

/// The app's own copy, as text. Read rather than imported: what is guarded
/// below is a private function that runs once per process, against whichever
/// engine that machine happens to load.
String _appReader() => File('lib/galaxy_db.dart').readAsStringSync();

/// The flattened source around [needle], so a failure can quote the shape that
/// is there instead of claiming the shape is absent (T-0321).
String _flattenedAround(String flattened, String needle) {
  final at = flattened.indexOf(needle);
  if (at < 0) return '(not present)';
  final from = at > 140 ? at - 140 : 0;
  var to = at + needle.length + 20;
  if (to > flattened.length) to = flattened.length;
  return '...${flattened.substring(from, to)}...';
}

/// The CLI's `const [name] = ...;`, so the three guards below quote the one
/// declaration they are about instead of answering with the whole file
/// (T-0325).
///
/// None of the three holds a `;` of its own, so the first one after the name
/// closes it. One that grew a statement would come back cut short -- which
/// the quoted region shows, rather than hiding behind a bare "not found".
String _cliDeclaration(String name) {
  final cli = _cliReader();
  final at = cli.indexOf('const $name =');
  if (at < 0) {
    fail('$_cliPath: a source scan for `const $name =` found nothing. The '
        'CLI copy no longer declares it under that name, so the two shells '
        'cannot be compared on it at all.');
  }
  final end = cli.indexOf(';', at);
  return cli.substring(at, end < 0 ? cli.length : end + 1);
}

/// What a `'''...'''` declaration holds between its quotes.
String _tripleQuoted(String declaration, String name) {
  final open = declaration.indexOf("'''");
  final close = declaration.lastIndexOf("'''");
  if (open < 0 || close <= open) {
    fail('$_cliPath: `const $name` is no longer a triple-quoted string, so '
        'there is nothing to compare the app copy against. What is '
        'declared:\n  $declaration');
  }
  return declaration.substring(open + 3, close);
}

/// [sql] as SQLite reads it: runs of whitespace folded to one space, ends
/// trimmed. Line breaks and indentation are how a file wraps a query, not
/// part of it.
String _asQuery(String sql) => sql.replaceAll(RegExp(r'\s+'), ' ').trim();

void main() {
  group('the two shells have not drifted', () {
    test('the CLI copy runs the identical query', () {
      // A query that differs between the shells is a library that differs
      // between them, and nothing else in the build would say so.
      //
      // Compared as SQL and not as text (T-0325). Byte-identity is what a
      // `contains()` of the whole ten-line string happened to do, not a
      // guarantee anything in the tree argues for, and it turns a re-indent
      // into a red test -- the query carries a 94-column JOIN, and wrapping
      // such a line by hand is what this project prescribes. What that gives
      // up: two copies may now differ in layout, visibly to anyone diffing
      // them, and this test will still call them the same query. Folding runs
      // of whitespace folds it inside a SQL string literal too; the only
      // literal here is `'title'` and it holds none.
      final cliSql = _tripleQuoted(
          _cliDeclaration('galaxyLibrarySql'), 'galaxyLibrarySql');
      if (_asQuery(cliSql) != _asQuery(galaxyLibrarySql)) {
        fail('$_cliPath: a source scan of the galaxyLibrarySql declaration '
            'found a query that is not the one app/lib declares. Runs of '
            'whitespace were folded on both sides first, so this is a '
            'difference in the SQL itself and not in how either file wraps '
            'it -- a column, a join or a condition has moved in one shell '
            'and not the other. What the CLI declares:\n  '
            '${_asQuery(cliSql)}\nWhat app/lib declares:\n  '
            '${_asQuery(galaxyLibrarySql)}');
      }
    });

    test('the CLI copy is written against the same schema version', () {
      // Two readers on different values refuse different databases: one shell
      // names a moved schema and the other reads it anyway.
      final declaration = _cliDeclaration('galaxySchemaVersion');
      final declared =
          RegExp(r'=\s*(\d+)\s*;').firstMatch(declaration)?.group(1);
      if (declared != '$galaxySchemaVersion') {
        fail('$_cliPath: a source scan of the galaxySchemaVersion '
            'declaration read ${declared ?? 'no integer at all'} where '
            'app/lib declares $galaxySchemaVersion. The two shells then '
            'disagree about which databases have a moved schema, and only '
            'one of them says so. The declaration:\n  $declaration');
      }
    });

    test('both shells point at the same default path', () {
      // A default that differs is one shell reading a database the other
      // does not, on the same machine and with nothing on screen to say so.
      final declaration = _cliDeclaration('galaxyDatabasePath');
      if (!declaration.contains(galaxyDatabasePath)) {
        fail('$_cliPath: a source scan of the galaxyDatabasePath declaration '
            "did not find app/lib's value inside it. What was looked for is "
            'that value as a literal substring, so a CLI copy spelling the '
            'same path with escapes instead of as a raw string fails here '
            'too; the declaration says which of the two this is:\n  '
            '$declaration');
      }
    });

    test('both shells initialise the engine, and call what they look up', () {
      // sqlite3_malloc before sqlite3_initialize takes the whole process down
      // -- no exception, no message -- on an engine built with
      // SQLITE_OMIT_AUTOINIT, which is what a GitHub runner loads (T-0240).
      // A lookup that is never invoked is the defect, so what is asserted is
      // the call and not the symbol.
      const symbol = 'sqlite3_initialize';
      final shells = {
        'app/lib/galaxy_db.dart': _appReader(),
        _cliPath: _cliReader(),
      };
      for (final shell in shells.entries) {
        // Whitespace flattened: the two files wrap this differently, and a
        // CRLF checkout would otherwise read as a missing call.
        final source = shell.value.replaceAll(RegExp(r'\s+'), ' ');
        // The optional space is a line break before the dot -- what a
        // hand-wrap of this line produces, and what the flatten turns into a
        // space. Admitted rather than reported as a missing binding (T-0321).
        final binding =
            RegExp(r"(\w+) = \w+ ?\.lookupFunction<[^;]*'" + symbol + r"'\);");
        final lookup = binding.firstMatch(source);
        if (lookup == null) {
          // A deleted binding and a moved line break send a reader to
          // opposite ends of the tree, so they do not share a sentence. The
          // discriminator is the quoted literal: the symbol also appears
          // unquoted in the failure message a few lines below the binding,
          // and a bare substring search cannot tell those apart (T-0321).
          fail(source.contains("'$symbol'")
              ? '${shell.key}: no binding of the shape ${binding.pattern} in '
                  "the whitespace-flattened source, but the literal '$symbol' "
                  'IS in the file. The lookup is written in a shape this guard '
                  'does not admit -- a line break has moved. Check the shape, '
                  'not the existence. What is there:\n  '
                  '${_flattenedAround(source, symbol)}'
              : "${shell.key}: no string literal '$symbol' occurs in this "
                  'file, so nothing looks the symbol up. The engine is never '
                  'initialised and the process dies without a message on a '
                  'SQLITE_OMIT_AUTOINIT build (T-0240).');
        }
        final name = lookup.group(1)!;
        // fail() rather than expect(): a matcher against `source` prints the
        // whole flattened file as its Actual and buries the one sentence that
        // says what is wrong (T-0321).
        if (!RegExp(r'(?<!\w)' + name + r' ?\(\);').hasMatch(source)) {
          fail('${shell.key} looks $symbol up and never calls it: the result '
              'is bound to `$name` and `$name();` never occurs.');
        }
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
