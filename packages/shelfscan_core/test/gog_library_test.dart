/// What a GOG Galaxy library row is allowed to become, and what it is not
/// (T-0177).
///
/// **No payload here is anyone's real library.** The schema was read off a
/// Galaxy database during development; that database is an inventory of
/// purchases and is private, and neither it nor any count taken of it is
/// published. The titles below are invented and the product ids are GOG's own
/// public store ids, quoted in doc/measurements.md, "The exact join".
///
/// The declines carry more weight than the happy path, because a substantial
/// part of what the vendor calls an owned release is not a game: DLC, releases
/// the Galaxy client itself hides, and releases from a different store. A
/// reader that emitted them would put rows in front of the user for things
/// they cannot export, on the one path that is supposed to need no correcting.
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

const _source = GogLibrarySource();

/// One row as the shell hands it over: the four keys the SQL selects.
SourceEntry _row(
  Map<String, Object?> row, {
  String? name,
}) =>
    SourceEntry(
      name: name ?? row['releaseKey'] as String? ?? '?',
      container: GogLibrarySource.databaseName,
      content: jsonEncode(row),
    );

const _owned = {
  'releaseKey': 'gog_1100000013',
  'title': 'Harbour of Tin',
  'isDlc': 0,
  'isVisibleInLibrary': 1,
};

void main() {
  group('the happy path', () {
    test('an owned release becomes one row with T-0157\'s namespaced id', () {
      final reading = _source.read(_row(_owned));
      expect(reading.declined, isEmpty);
      final detection = reading.items.single;
      expect(detection.rawTitle, 'Harbour of Tin');
      expect(detection.sourceId, 'gog:1100000013');
      expect(detection.origin, DetectionOrigin.metadata);
      expect(detection.platformHint, GogMetadataSource.platformHint);
      expect(detection.sourceEntry, 'gog_1100000013');
    });

    test('the id is the release key\'s, never the entry name\'s', () {
      // T-0157's rule on its file name, restated for a row: the two agree only
      // because the shell puts them there, and a join must not be retargetable
      // by a shell that names an entry differently.
      final reading = _source.read(_row(_owned, name: 'gog_9999999999'));
      expect(reading.items.single.sourceId, 'gog:1100000013');
    });

    test('a title with surrounding whitespace is trimmed', () {
      final reading = _source.read(_row({..._owned, 'title': '  Harbour of Tin '}));
      expect(reading.items.single.rawTitle, 'Harbour of Tin');
    });

    test('a non-ASCII title survives unchanged', () {
      final reading = _source.read(_row({..._owned, 'title': 'Brütal Fjord ⅩⅤ'}));
      expect(reading.items.single.rawTitle, 'Brütal Fjord ⅩⅤ');
    });

    test('the hint reaches PlatformIds as PC, not as a store name', () {
      // T-0156's table, tied to rather than restated (T-0157 does the same):
      // a store name reaches no entry and the row resolves to nothing.
      expect(platformIds[GogLibrarySource.databaseName], isNull);
      expect(platformIds[GogMetadataSource.platformHint], {6});
    });

    test('the hint is not confiscated by Detection.fromJson', () {
      final detection = _source.read(_row(_owned)).items.single;
      final round = Detection.fromJson(jsonDecode(jsonEncode(detection.toJson())));
      expect(round.platformHint, 'PC');
      expect(round.discardedPlatformHint, isNull);
      expect(round.sourceId, 'gog:1100000013');
    });
  });

  group('the three filters between an owned release and a game', () {
    test('a DLC row is declined by name', () {
      final reading = _source.read(_row({..._owned, 'isDlc': 1}));
      expect(reading.items, isEmpty);
      expect(reading.declined.single.reason, GogLibrarySource.dlcNotAGame);
    });

    test('a row Galaxy hides is declined by name', () {
      final reading = _source.read(_row({..._owned, 'isVisibleInLibrary': 0}));
      expect(reading.items, isEmpty);
      expect(reading.declined.single.reason, GogLibrarySource.hiddenInLibrary);
    });

    test('another store\'s release is declined by name', () {
      // Galaxy 2.0 keeps connected stores' releases in the same table, and
      // those have no GOG product id for T-0159 to join on. Such a release
      // stays in the library after its store is disconnected, so the filter
      // must not be made conditional on a live connection; where no store is
      // connected the path is simply unexercised.
      for (final key in ['xboxone_1234567', 'steam_400', 'generic_9', 'epic_x']) {
        final reading = _source.read(_row({..._owned, 'releaseKey': key}));
        expect(reading.items, isEmpty, reason: key);
        expect(reading.declined.single.reason, GogLibrarySource.notGogProduct,
            reason: key);
      }
    });

    test('absent is absent: null flags are a visible game', () {
      // Both columns are `INTEGER NULL` in the vendor's own schema, and a null
      // is not an assertion that the row is a hidden DLC (T-0157).
      final reading = _source.read(_row({
        'releaseKey': 'gog_1100000013',
        'title': 'Harbour of Tin',
        'isDlc': null,
        'isVisibleInLibrary': null,
      }));
      expect(reading.items, hasLength(1));
    });

    test('a shell handing over real booleans is understood too', () {
      expect(_source.read(_row({..._owned, 'isDlc': true})).declined.single.reason,
          GogLibrarySource.dlcNotAGame);
      expect(
          _source
              .read(_row({..._owned, 'isVisibleInLibrary': false}))
              .declined
              .single
              .reason,
          GogLibrarySource.hiddenInLibrary);
    });
  });

  group('an unrecognised shape is declined, never guessed at', () {
    final cases = <String, (SourceEntry, String)>{
      'no content at all': (
        const SourceEntry(name: 'gog_1'),
        GogLibrarySource.notJson
      ),
      'not JSON': (
        const SourceEntry(name: 'gog_1', content: '{oops'),
        GogLibrarySource.notJson
      ),
      'an outer array': (
        const SourceEntry(name: 'gog_1', content: '[]'),
        GogLibrarySource.notAnObject
      ),
      'a bare null': (
        const SourceEntry(name: 'gog_1', content: 'null'),
        GogLibrarySource.notAnObject
      ),
      'a bare string': (
        const SourceEntry(name: 'gog_1', content: '"gog_1"'),
        GogLibrarySource.notAnObject
      ),
      'no releaseKey': (
        SourceEntry(name: 'gog_1', content: jsonEncode({'title': 'x'})),
        GogLibrarySource.noReleaseKey
      ),
      'a numeric releaseKey': (
        SourceEntry(
            name: 'gog_1', content: jsonEncode({'releaseKey': 1100000013})),
        GogLibrarySource.noReleaseKey
      ),
      'an empty releaseKey': (
        SourceEntry(name: 'gog_1', content: jsonEncode({'releaseKey': '  '})),
        GogLibrarySource.noReleaseKey
      ),
      'a release key with no id': (
        SourceEntry(name: 'gog_', content: jsonEncode({'releaseKey': 'gog_'})),
        GogLibrarySource.notGogProduct
      ),
      'a non-numeric gog id': (
        SourceEntry(
            name: 'gog_x', content: jsonEncode({'releaseKey': 'gog_abc'})),
        GogLibrarySource.notGogProduct
      ),
      'no title': (
        SourceEntry(
            name: 'gog_1',
            content: jsonEncode({'releaseKey': 'gog_1100000013'})),
        GogLibrarySource.noTitle
      ),
      'a numeric title': (
        SourceEntry(
            name: 'gog_1',
            content:
                jsonEncode({'releaseKey': 'gog_1100000013', 'title': 2077})),
        GogLibrarySource.noTitle
      ),
      'a whitespace title': (
        SourceEntry(
            name: 'gog_1',
            content:
                jsonEncode({'releaseKey': 'gog_1100000013', 'title': '   '})),
        GogLibrarySource.noTitle
      ),
    };

    cases.forEach((name, expected) {
      test(name, () {
        final reading = _source.read(expected.$1);
        expect(reading.items, isEmpty);
        expect(reading.declined.single.reason, expected.$2);
        expect(reading.declined.single.name, expected.$1.name);
      });
    });

    test('every reason is a constant, carrying no id and no title', () {
      // `Orchestrator` groups its skip warnings by the exact reason string, so
      // a reason carrying a per-row value prints one line per row -- the shape
      // T-0144 removed. Declines are a large minority of a real library, so
      // this is not academic.
      for (final reason in [
        GogLibrarySource.notJson,
        GogLibrarySource.notAnObject,
        GogLibrarySource.noReleaseKey,
        GogLibrarySource.noTitle,
        GogLibrarySource.notGogProduct,
        GogLibrarySource.dlcNotAGame,
        GogLibrarySource.hiddenInLibrary,
      ]) {
        expect(reason, isNot(matches(RegExp(r'\d{4}'))), reason: reason);
        expect(reason, isNot(contains('Harbour')), reason: reason);
      }
    });
  });

  group('a library, through the pipeline', () {
    test('the games survive, the rest are named, and no vision worker exists',
        () async {
      // `resolveOnly` holds no vision provider object at all, so a library
      // scan provably cannot make a vision call; `SkipResolver` refuses
      // network I/O on top. Nothing here opens the database either -- the
      // rows arrive as text, which is the whole platform boundary.
      final warnings = <String>[];
      final document =
          await Orchestrator.resolveOnly(resolverWorker: SkipResolver())
              .runScan(
        const [],
        sources: [
          SourceRun(_source, [
            _row(_owned),
            _row(
                {..._owned, 'releaseKey': 'gog_1100000027', 'title': 'Second Game'}),
            _row({..._owned, 'releaseKey': 'gog_1100000039', 'isDlc': 1}),
            _row({
              ..._owned,
              'releaseKey': 'gog_1100000040',
              'isVisibleInLibrary': 0
            }),
            _row({..._owned, 'releaseKey': 'xboxone_9000'}),
          ])
        ],
        progress: ScanProgress(onWarning: (w) => warnings.add(w.message)),
      );

      expect([for (final game in document.games) game.detection.rawTitle],
          ['Harbour of Tin', 'Second Game']);
      expect({for (final entry in document.declinedEntries) entry.name},
          {'gog_1100000039', 'gog_1100000040', 'xboxone_9000'});
      expect(warnings, hasLength(3),
          reason: 'one warning per reason, not one per row');
    });
  });

  group('the join path T-0159 built is actually reached', () {
    test('a library row queries external_games on its own product id', () async {
      // The criterion this task has to meet: an owned-but-uninstalled row must
      // land on the same exact join an installed one does. The uid asserted
      // here is the one the release key carried, so a source that lost the id
      // between the two would fail this and not the shape tests above.
      final calls = <String>[];
      final transport = MockClient((request) async {
        if (request.url.host == 'id.twitch.tv') {
          return http.Response(
              jsonEncode({'access_token': 'stub', 'expires_in': 3600}), 200);
        }
        if (request.url.path.endsWith('/external_games')) {
          calls.add(request.body);
          return http.Response(
              jsonEncode([
                {
                  'id': 1100000026,
                  'uid': '1100000013',
                  'game': {
                    'id': 1100000019,
                    'name': 'Harbour of Tin',
                    'platforms': [
                      {'id': 6, 'name': 'PC (Microsoft Windows)'}
                    ],
                  },
                }
              ]),
              200);
        }
        return http.Response(jsonEncode([]), 200);
      });

      final detection = _source.read(_row(_owned)).items.single;
      final resolved = await ResolverWorker(IgdbClient(
              clientId: 'stub', clientSecret: 'stub', client: transport))
          .process(detection);

      expect(calls.single, contains('external_game_source = 5'));
      expect(calls.single, contains('uid = "1100000013"'));
      expect(resolved.best?.igdbId, 1100000019);
      expect(resolved.best?.platformId, 6);
    });
  });

  group('the platform boundary', () {
    test('nothing under lib/ imports dart:io', () {
      // T-0157's guard, re-asserted here because this task is the one with a
      // reason to break it: reading SQLite is a filesystem act, and the whole
      // design is that it happens in the shells. If this fails, the reader has
      // migrated into core and the pipeline no longer runs on Android.
      final offenders = [
        for (final file in Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart')))
          if (RegExp("^\\s*import\\s+['\"]dart:io['\"]", multiLine: true)
              .hasMatch(file.readAsStringSync()))
            file.path,
      ];
      expect(offenders, isEmpty);
    });

    test('nothing under lib/ imports dart:ffi either', () {
      // New with this task. The SQLite read is `dart:ffi` against the engine
      // Windows already ships (decision 0001); `dart:ffi` is not
      // `dart:io`, so T-0157's guard would not have caught it moving in here,
      // and it would break a web build of core as surely as `dart:io` breaks
      // the boundary.
      final offenders = [
        for (final file in Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart')))
          if (RegExp("^\\s*import\\s+['\"]dart:ffi['\"]", multiLine: true)
              .hasMatch(file.readAsStringSync()))
            file.path,
      ];
      expect(offenders, isEmpty);
    });

    test('shelfscan_core still declares http and nothing else', () {
      // The dependency question this task existed to answer, pinned so the
      // answer cannot be quietly reversed: reading SQLite added no package.
      final declared = <String>[];
      var inRuntime = false;
      for (final line in File('pubspec.yaml').readAsLinesSync()) {
        if (RegExp(r'^\w').hasMatch(line)) inRuntime = line.startsWith('dependencies:');
        if (inRuntime && RegExp(r'^  \w').hasMatch(line)) {
          declared.add(line.trim().split(':').first);
        }
      }
      expect(declared, ['http']);
    });
  });
}
