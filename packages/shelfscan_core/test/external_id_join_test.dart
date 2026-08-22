/// The exact join: a store's own product id against IGDB's `external_games`,
/// instead of the title being matched as a string (T-0159).
///
/// The premise was verified live 2026-08-16 before any of this was written --
/// `external_game_sources` answers **`5 GOG`** among 22 sources, and a GOG row
/// carries the store product id as `uid`. The figures quoted in the tests below
/// come from 480 real GoG product ids taken from GOG's own public store
/// catalogue; doc/measurements.md, "The exact join", has the whole measurement.
///
/// What these tests are actually for is the two things a live run cannot pin:
/// that the join runs **instead of** the search, and that a uid IGDB does not
/// know reaches the ordinary resolver rather than a dead end.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

const _pc = (6, 'PC (Microsoft Windows)');
const _linux = (3, 'Linux');
const _mac = (14, 'Mac');
const _dos = (13, 'DOS');
const _switch1 = (130, 'Nintendo Switch');
const _switch2 = (508, 'Nintendo Switch 2');

Map<String, dynamic> _game(
  int id,
  String name,
  List<(int, String)> platforms, {
  List<String> alternativeNames = const [],
}) =>
    {
      'id': id,
      'name': name,
      if (alternativeNames.isNotEmpty)
        'alternative_names': [
          for (final alternative in alternativeNames) {'name': alternative},
        ],
      'platforms': [
        for (final (platformId, platformName) in platforms)
          {'id': platformId, 'name': platformName},
      ],
    };

/// One `external_games` row, shaped as IGDB returns it: the uid, the expanded
/// game, and **no `platform` of its own** -- absent on all 394 rows measured.
Map<String, dynamic> _external(String uid, Map<String, dynamic> game) =>
    {'id': 1100000026, 'uid': uid, 'game': game};

/// Every request body the run sent, by endpoint, so a test can assert which
/// endpoint was asked as well as what came back.
class _Calls {
  final external = <String>[];
  final games = <String>[];
}

({Future<ResolvedGame> resolved, _Calls calls}) _run(
  Detection detection, {
  List<Map<String, dynamic>> externalRows = const [],
  List<Map<String, dynamic>> searchGames = const [],
}) {
  final calls = _Calls();
  final transport = MockClient((request) async {
    if (request.url.host == 'id.twitch.tv') {
      return http.Response(
          jsonEncode({'access_token': 'stub-token', 'expires_in': 3600}), 200);
    }
    if (request.url.path.endsWith('/external_games')) {
      calls.external.add(request.body);
      return http.Response(jsonEncode(externalRows), 200);
    }
    calls.games.add(request.body);
    return http.Response(jsonEncode(searchGames), 200);
  });
  final resolved = ResolverWorker(
          IgdbClient(clientId: 'stub', clientSecret: 'stub', client: transport))
      .process(detection);
  return (resolved: resolved, calls: calls);
}

Detection _gogInstall(String title, {String? sourceId = 'gog:1100000022'}) =>
    Detection.fromSource(
      rawTitle: title,
      origin: DetectionOrigin.metadata,
      sourceEntry: 'goggame-1100000022.info',
      sourceId: sourceId,
      platformHint: GogMetadataSource.platformHint,
    );

void main() {
  group('the premise, as it is queried', () {
    test('GOG is source 5 and the uid goes into the where clause verbatim',
        () async {
      final run = _run(
        _gogInstall('Kaldreth: Book II', sourceId: 'gog:1100000013'),
        externalRows: [
          _external('1100000013', _game(1100000019, 'Kaldreth: Book II', [_pc])),
        ],
      );
      await run.resolved;
      expect(run.calls.external.single, contains('external_game_source = 5'));
      expect(run.calls.external.single, contains('uid = "1100000013"'));
      // The platform the .xcoll row needs is not on this endpoint, so the
      // game's own platforms have to be expanded in the same request.
      expect(run.calls.external.single, contains('game.platforms.id'));
      // No platform filter: a DOS-era GoG release is not listed on 6 and the
      // join must still find it.
      expect(run.calls.external.single, isNot(contains('platforms = (')));
    });

    test('a uid carrying a quote cannot end the pattern', () async {
      final run = _run(_gogInstall('x', sourceId: 'gog:12"34'));
      await run.resolved;
      expect(run.calls.external.single, contains('uid = "1234"'));
    });
  });

  group('the join runs first, instead of the search', () {
    test('a gog: id auto-matches on the joined game and IGDB is never searched',
        () async {
      final run = _run(
        _gogInstall('Kaldreth: Book II', sourceId: 'gog:1100000013'),
        externalRows: [
          _external('1100000013',
              _game(1100000019, 'Kaldreth: Book II', [_linux, _pc, _mac])),
        ],
      );
      final resolved = await run.resolved;
      expect(resolved.best, isNotNull);
      expect(resolved.best!.igdbId, 1100000019);
      expect(resolved.best!.title, 'Kaldreth: Book II');
      expect(resolved.best!.platformId, 6);
      expect(resolved.best!.score, 1.0);
      expect(run.calls.games, isEmpty, reason: 'the search was not needed');
      expect(run.calls.external, hasLength(1));
    });

    test('the whole resolve costs one request', () async {
      // The alternative-name filter and `shortenedQueries`' ladder are what a
      // row that joins never reaches; the count is how that is checked.
      final run = _run(
        _gogInstall('Lane Runner: APEX', sourceId: 'gog:1100000030'),
        externalRows: [
          _external('1100000030', _game(1100000031, 'Lane Runner: APEX', [_pc])),
        ],
      );
      await run.resolved;
      expect(run.calls.external.length + run.calls.games.length, 1);
    });

    test('none of the fuzzy gates apply -- a title that fails every one of '
        'them still joins', () async {
      // `regent of aurex 2` against `Regent of Aurex` is refused twice on the
      // string path: below minAutoScore, and volumeNumbersAgree disagrees.
      final run = _run(
        _gogInstall('Regent of Aurex 2', sourceId: 'gog:1100000032'),
        externalRows: [
          _external('1100000032', _game(1100000058, 'Regent of Aurex', [_pc])),
        ],
      );
      final resolved = await run.resolved;
      expect(resolved.best?.igdbId, 67);
      expect(resolved.best?.title, 'Regent of Aurex');
    });

    test('a title with nothing in common with the canonical name still joins',
        () async {
      final run = _run(
        _gogInstall('setup_the_game', sourceId: 'gog:1100000033'),
        externalRows: [
          _external('1100000033',
              _game(1100000034, 'Herald of Frost and Flame III: Complete', [_pc])),
        ],
      );
      final resolved = await run.resolved;
      expect(resolved.best?.igdbId, 1100000034);
    });
  });

  group('the fallback is the ordinary resolver, not a dead end', () {
    test('a uid IGDB does not know is resolved by title, and the row is the '
        'one the product would have produced without the join', () async {
      final run = _run(
        _gogInstall('Ivor Lane', sourceId: 'gog:9999999999'),
        externalRows: const [],
        searchGames: [_game(1100000031, 'Ivor Lane', [_pc])],
      );
      final resolved = await run.resolved;
      expect(run.calls.external, hasLength(1));
      expect(run.calls.games, hasLength(1),
          reason: 'the search ran after the join answered nothing');
      expect(run.calls.games.single, contains('search "ivor lane"'));
      expect(run.calls.games.single, contains('platforms = (6)'),
          reason: 'the ordinary path still applies the PC platform gate');
      expect(resolved.best?.igdbId, 1100000031);
      expect(resolved.best?.platformId, 6);
      expect(resolved.best?.score, 1.0);
    });

    test('the fallback is reached on the row itself, not merely survived',
        () async {
      // The same detection resolved with the join answering nothing must give
      // the same row as one carrying no sourceId at all.
      final joined = _run(
        _gogInstall('Ivor Lane', sourceId: 'gog:9999999999'),
        searchGames: [_game(1100000031, 'Ivor Lane', [_pc])],
      );
      final plain = _run(
        _gogInstall('Ivor Lane', sourceId: null),
        searchGames: [_game(1100000031, 'Ivor Lane', [_pc])],
      );
      expect(jsonEncode((await joined.resolved).best!.toJson()),
          jsonEncode((await plain.resolved).best!.toJson()));
    });

    test('a game IGDB lists on no platform at all falls back rather than '
        'resolving to a row with no platform', () async {
      // 4 of the 394 joined games measured; the library is a real one, not
      // published, and the rows are not named.
      final run = _run(
        _gogInstall('Wispkins', sourceId: 'gog:1100000035'),
        externalRows: [
          _external('1100000035', _game(500001, 'Wispkins', const [])),
        ],
        searchGames: const [],
      );
      final resolved = await run.resolved;
      expect(run.calls.games, isNotEmpty);
      expect(resolved.best, isNull);
      expect(resolved.candidates, isEmpty);
    });

    test('a namespace IGDB has no source for costs no request', () async {
      final run = _run(
        Detection.fromSource(
          rawTitle: 'Ivor Lane',
          origin: DetectionOrigin.metadata,
          sourceEntry: 'whatever',
          sourceId: 'itch:12345',
          platformHint: 'PC',
        ),
        searchGames: [_game(1100000031, 'Ivor Lane', [_pc])],
      );
      final resolved = await run.resolved;
      expect(run.calls.external, isEmpty);
      expect(run.calls.games, hasLength(1));
      expect(resolved.best?.igdbId, 1100000031);
    });

    test('a sourceId with no namespace at all falls back', () async {
      final run = _run(
        _gogInstall('Ivor Lane', sourceId: '1100000022'),
        searchGames: [_game(1100000031, 'Ivor Lane', [_pc])],
      );
      await run.resolved;
      expect(run.calls.external, isEmpty);
      expect(run.calls.games, hasLength(1));
    });
  });

  group('platformId for a multi-platform game', () {
    test('the hint picks it: 270 of the 394 joined games are on more than one',
        () async {
      final run = _run(
        _gogInstall('Ashvane', sourceId: 'gog:1100000036'),
        externalRows: [
          _external(
              '1100000036',
              _game(1100000034, 'Ashvane',
                  [(48, 'PlayStation 4'), _linux, _pc, _mac, _switch1])),
        ],
      );
      final resolved = await run.resolved;
      expect(resolved.best?.platformId, 6);
      expect(resolved.candidates.map((c) => c.platformId), [6],
          reason: 'a Windows install offers no console row to mis-pick');
    });

    test('a game the hint finds on nothing keeps the game and refuses the '
        'platform', () async {
      // Runecrag Lord: 15, 26, 63, 13, 16, 25 and no 6. Claiming Windows here
      // would assert a release IGDB does not record.
      final run = _run(
        _gogInstall('Runecrag Lord', sourceId: 'gog:1100000037'),
        externalRows: [
          _external(
              '1100000037',
              _game(500002, 'Runecrag Lord', [
                (16, 'Amiga'),
                _dos,
                (26, 'ZX Spectrum'),
              ])),
        ],
      );
      final resolved = await run.resolved;
      expect(resolved.best, isNull);
      expect(run.calls.games, isEmpty,
          reason: 'the game was found; only the platform is open');
      expect(resolved.candidates.map((c) => c.igdbId), everyElement(500002));
      expect(resolved.candidates.map((c) => c.platformId), [13, 16, 26],
          reason: 'sorted by id -- IGDB\'s own order is not stable');
    });

    test('a hint mapping to two ids refuses when the game is on both',
        () async {
      final run = _run(
        Detection.fromSource(
          rawTitle: 'Some Port',
          origin: DetectionOrigin.metadata,
          sourceEntry: 'goggame-1.info',
          sourceId: 'gog:1',
          platformHint: 'SWITCH',
        ),
        externalRows: [
          _external('1', _game(7, 'Some Port', [_switch2, _switch1])),
        ],
      );
      final resolved = await run.resolved;
      expect(resolved.best, isNull);
      expect(resolved.candidates.map((c) => c.platformId), [130, 508]);
    });

    test('two IGDB games under one uid are not guessed between', () async {
      // 0 of 394 measured, so this is the shape the join is entitled to skip
      // the tie rule *because* it does not have -- pinned so a change in
      // IGDB's data cannot make it an auto-match silently.
      final run = _run(
        _gogInstall('Moor', sourceId: 'gog:1100000002'),
        externalRows: [
          _external('1100000002', _game(1100000011, 'Moor', [_pc])),
          _external('1100000002', _game(1234, 'The Ultimate Moor', [_pc])),
        ],
      );
      final resolved = await run.resolved;
      expect(resolved.best, isNull);
      expect(resolved.candidates, hasLength(2));
    });

    test('at most five candidates reach review, as everywhere else', () async {
      final run = _run(
        _gogInstall('Vast Warrenway', sourceId: 'gog:1100000038'),
        externalRows: [
          _external(
              '1100000038',
              _game(500003, 'Vast Warrenway', [
                (162, 'Oculus VR'),
                (386, 'Meta Quest 2'),
                (390, 'PlayStation VR2'),
                (161, 'Windows Mixed Reality'),
                (165, 'PlayStation VR'),
                (163, 'SteamVR'),
                (385, 'Oculus Rift'),
                (384, 'Oculus Quest'),
              ])),
        ],
      );
      final resolved = await run.resolved;
      expect(resolved.best, isNull);
      expect(resolved.candidates, hasLength(5));
      expect(resolved.candidates.first.platformId, 161);
    });
  });

  group('T-0165\'s collisions, which the join does not have', () {
    // Measured live 2026-08-16 through this same code, join against title, on
    // the identical raw title and the real GoG product ids:
    //
    //   "MOOR"            gog:1100000027  join -> 1100000012 The Ultimate Moor (1995)
    //   "MOOR"            gog:1100000039  join ->  1100000011 Moor (2016)
    //   "Regent of Aurex" gog:1100000028  join -> 1100000058 Regent of Aurex (1993)
    //   "Regent of Aurex" gog:1100000040  join -> 1100000009 Regent of Aurex (2016)
    //
    // and the title path answers **NONE, 5 candidates, on all four** -- the
    // same-platform tie rule refusing exactly what T-0165 built it to refuse.
    // So the join is not a cheaper route to the same row here; it is four rows
    // the product cannot auto-match at all, and the release year the tie rule
    // turns on is what the two ids already say.
    test('one raw title, two product ids, two different games', () async {
      final ultimate = _run(
        _gogInstall('MOOR', sourceId: 'gog:1100000027'),
        externalRows: [
          _external('1100000027', _game(1100000012, 'The Ultimate Moor', [_pc])),
        ],
      );
      final reboot = _run(
        _gogInstall('MOOR', sourceId: 'gog:1100000039'),
        externalRows: [
          _external('1100000039', _game(1100000011, 'Moor', [_pc])),
        ],
      );
      expect((await ultimate.resolved).best?.igdbId, 1100000012);
      expect((await reboot.resolved).best?.igdbId, 1100000011);
    });

    test('the same, for the two Regent of Aurex releases', () async {
      final original = _run(
        _gogInstall('Regent of Aurex', sourceId: 'gog:1100000028'),
        externalRows: [
          _external('1100000028', _game(1100000058, 'Regent of Aurex', [_pc])),
        ],
      );
      final remake = _run(
        _gogInstall('Regent of Aurex', sourceId: 'gog:1100000040'),
        externalRows: [
          _external('1100000040', _game(1100000009, 'Regent of Aurex', [_pc])),
        ],
      );
      expect((await original.resolved).best?.igdbId, 67);
      expect((await remake.resolved).best?.igdbId, 1100000009);
    });

    test('the third collision has no GOG row and stays the tie rule\'s',
        () async {
      // Cabalists: IGDB holds no external_games GOG row for either the 1993
      // game or the 2012 one, so this row is one of the 18% and reaches the
      // string path exactly as it does today.
      final run = _run(
        _gogInstall('Cabalists', sourceId: 'gog:1100000041'),
        externalRows: const [],
        searchGames: [
          _game(1100000059, 'Cabalists', [_pc]),
          _game(1100000010, 'Cabalists', [_pc]),
        ],
      );
      final resolved = await run.resolved;
      expect(run.calls.games, hasLength(1));
      expect(resolved.best, isNull, reason: 'the T-0165 tie rule still fires');
      expect(resolved.candidates, hasLength(2));
    });
  });

  group('a row with no sourceId is untouched', () {
    test('a photograph row never asks external_games', () async {
      final run = _run(
        Detection(
          rawTitle: 'ivor lane',
          platformHint: 'PC',
          mediaType: MediaType.disc,
          confidence: 1.0,
          sourcePhoto: 'IMG.jpg',
        ),
        searchGames: [_game(1100000031, 'Ivor Lane', [_pc])],
      );
      final resolved = await run.resolved;
      expect(run.calls.external, isEmpty);
      expect(run.calls.games, hasLength(1));
      expect(resolved.best?.igdbId, 1100000031);
    });
  });
}
