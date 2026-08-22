/// The four ids T-0168 refused to guess, and what each is worth once the gate
/// can honour it (T-0190).
///
/// The ids themselves are a live read and cannot be re-derived here; what this
/// file pins is the mapping they were put into and the behaviour that mapping
/// produces, driven through the **real** `ResolverWorker` and `IgdbClient` over
/// a `MockClient` so the client's own platform filter runs exactly as it does
/// live. No network, no key, no scan.
///
/// Read off IGDB's `platforms` endpoint on 2026-08-16, one request for the
/// whole 220-row listing: **37 Nintendo 3DS, 137 New Nintendo 3DS, 20 Nintendo
/// DS, 159 Nintendo DSi, 41 Wii U, 46 PlayStation Vita.** The listing holds no
/// second Wii U and no second Vita. Decision 0006 carries the rows as
/// returned and the live resolver figures behind the two unions.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

const _threeDs = (37, 'Nintendo 3DS');
const _newThreeDs = (137, 'New Nintendo 3DS');
const _ds = (20, 'Nintendo DS');
const _dsi = (159, 'Nintendo DSi');
const _wiiU = (41, 'Wii U');

Map<String, dynamic> _game(int id, String name, List<(int, String)> platforms) =>
    {
      'id': id,
      'name': name,
      'platforms': [
        for (final (platformId, platformName) in platforms)
          {'id': platformId, 'name': platformName},
      ],
    };

Future<ResolvedGame> _run(String entryName, List<Map<String, dynamic>> games) {
  final detection =
      const FilenameSource().read(SourceEntry(name: entryName)).items.single;
  final transport = MockClient((request) async {
    if (request.url.host == 'id.twitch.tv') {
      return http.Response(
          jsonEncode({'access_token': 'stub-token', 'expires_in': 3600}), 200);
    }
    return http.Response(jsonEncode(games), 200);
  });
  return ResolverWorker(
          IgdbClient(clientId: 'stub', clientSecret: 'stub', client: transport))
      .process(detection);
}

void main() {
  group('the four ids the containers were waiting on', () {
    test('each hint maps to what the live listing returned', () {
      expect(platformIds['3DS'], {37, 137});
      expect(platformIds['DS'], {20, 159});
      expect(platformIds['WIIU'], {41});
      expect(platformIds['VITA'], {46});
    });

    test('every container that names one console now emits its key', () {
      const expected = {
        '3ds': '3DS',
        'cia': '3DS',
        'nds': 'DS',
        'wud': 'WIIU',
        'wux': 'WIIU',
      };
      for (final entry in expected.entries) {
        final parse = parseGameFileName('Sample Game.${entry.key}');
        expect(parse.title, 'Sample Game', reason: entry.key);
        expect(parse.platformHint, entry.value, reason: entry.key);
      }
    });

    test('the five that span systems still decline', () {
      for (final ext in ['pkg', 'chd', 'cso', 'rvz', 'vpk']) {
        expect(parseGameFileName('Sample Game.$ext').declined,
            DeclineReason.notAPcInstaller,
            reason: ext);
      }
    });
  });

  group('the handheld unions, and what each side of the trade looks like', () {
    // The half `{20}` alone cannot reach. Live 2026-08-16: `flipnote studio`,
    // `x-scape`, `mighty milky way` and `dr mario express` are on 159 and not
    // on 20, and `DS` -> {20} answered all four with nothing or with junk --
    // 0 of 4 auto-matched against 4 of 4 under the union.
    // Named rather than substituted because they ARE the evidence: these are
    // catalogue rows carrying a claim about IGDB platform ids, not fixtures
    // standing in for a shelf. DSiWare was download-only and sat on none.
    test('a DSiWare title reaches the human at all', () async {
      final resolved = await _run('Sample Game O.nds', [
        _game(4001, 'Sample Game O', [_dsi]),
      ]);
      expect(resolved.detection.platformHint, 'DS');
      expect(resolved.best?.platformId, 159);
      expect(resolved.best?.igdbId, 4001);
    });

    // And the price, which is the T-0023 clause unchanged: two rows differing
    // only by console are a tie `_best` refuses. IGDB lists 40 of its 698 DSi
    // games on 20 as well (live 2026-08-16) -- 1.0% of that catalogue, where
    // a desktop game is on 6 and 3 and 14 as a matter of course, which is why
    // the same arithmetic that made `PC` a single id makes this a union.
    test('a title on both DS ids is a tap at review, not a guess', () async {
      final resolved = await _run('Sample Game O.nds', [
        _game(4002, 'Sample Game O', [_ds, _dsi]),
      ]);
      expect(resolved.candidates.map((c) => c.platformId), [20, 159]);
      expect(resolved.candidates.map((c) => c.score), everyElement(1.0));
      expect(resolved.best, isNull);
    });

    // The same shape one console over. `super nebulae` is the measured case:
    // its only 3DS-family listing is 137, so `{37}` answered it with five
    // wrong candidates and the union auto-matches it at 1.000.
    test('a New 3DS listing is reachable through the .cia hint', () async {
      final resolved = await _run('Sample Game N.cia', [
        _game(4003, 'Sample Game N', [_newThreeDs]),
      ]);
      expect(resolved.detection.platformHint, '3DS');
      expect(resolved.best?.platformId, 137);
    });

    test('and a title on both 3DS ids refuses, as the union requires',
        () async {
      final resolved = await _run('Sample Game M.3ds', [
        _game(4004, 'Sample Game M', [_threeDs, _newThreeDs]),
      ]);
      expect(resolved.candidates, hasLength(2));
      expect(resolved.best, isNull);
    });
  });

  group('the two single ids', () {
    test('a Wii U disc image auto-matches on 41', () async {
      final resolved = await _run('Sample Game P.wud', [
        _game(4005, 'Sample Game P', [_wiiU]),
      ]);
      expect(resolved.detection.platformHint, 'WIIU');
      expect(resolved.best?.platformId, 41);
    });

    // Vita has no container behind it -- `.pkg` spans PlayStation generations
    // and `.vpk` is also a Valve archive, so both decline on purpose. The key
    // is here for the vision path: without it `PS VITA`, the branding as a
    // case prints it, folds to {ps, vita}, which is not a subset of
    // {playstation, vita}, so `platformAgreement` refused EVERY candidate and
    // the row resolved to nothing (T-0156's failure, shipping).
    test('every spelling a Vita case prints agrees with platform 46', () {
      for (final hint in ['VITA', 'PS Vita', 'PlayStation Vita', 'psvita']) {
        expect(
            platformAgreement(hint,
                platformId: 46, platformName: 'PlayStation Vita'),
            PlatformAgreement.match,
            reason: hint);
      }
      expect(
          platformAgreement('PS Vita',
              platformId: 48, platformName: 'PlayStation 4'),
          PlatformAgreement.mismatch);
    });

    test('the .pkg and .vpk containers a Vita id does not rescue', () {
      expect(consolePlatformHints['pkg'], isNull);
      expect(consolePlatformHints['vpk'], isNull);
    });
  });
}
