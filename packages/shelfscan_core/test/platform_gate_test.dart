/// Guards the platform gate on `best` (T-0002).
///
/// Measured in T-0008 over the real detections of a whole run: the string
/// metric caused no miss at all, while all but one of that run's confident
/// false positives were the right game on the wrong console. `IgdbClient` emits
/// one hit per (game, platform) pair, so when the hint cannot be turned into a
/// platform id the
/// query runs unfiltered and a dozen rows tie at 1.000 -- `best` was then
/// whichever IGDB happened to list first.
///
/// Three things have to hold together, and each is easy to undo alone:
///   1. a candidate contradicting the hint is refused as `best`;
///   2. it is refused, not deleted -- the reviewer still sees it;
///   3. a hint too coarse to separate two tied platforms decides nothing.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

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

ResolverWorker _resolver(List<Map<String, dynamic>> games) {
  final transport = MockClient((request) async {
    if (request.url.host == 'id.twitch.tv') {
      return http.Response(
          jsonEncode({'access_token': 'stub-token', 'expires_in': 3600}), 200);
    }
    return http.Response(jsonEncode(games), 200);
  });
  return ResolverWorker(
      IgdbClient(clientId: 'stub', clientSecret: 'stub', client: transport));
}

Future<ResolvedGame> _resolve(
  List<Map<String, dynamic>> games, {
  required String title,
  String? hint,
}) =>
    _resolver(games).process(Detection(
      rawTitle: title,
      platformHint: hint,
      mediaType: MediaType.cartridge,
      confidence: 1.0,
      sourcePhoto: 'shelf.jpg',
    ));

const _switch = (130, 'Nintendo Switch');
const _switch2 = (508, 'Nintendo Switch 2');
const _xbox = (169, 'Xbox Series X|S');
const _ps4 = (48, 'PlayStation 4');

void main() {
  group('platformAgreement', () {
    PlatformAgreement against(String? hint, (int, String) platform) =>
        platformAgreement(hint,
            platformId: platform.$1, platformName: platform.$2);

    test('a hint IGDB knows ids for is compared by those ids', () {
      expect(against('SWITCH', _switch), PlatformAgreement.match);
      expect(against('nintendo switch', _switch), PlatformAgreement.match);
      expect(against('PS4', _switch), PlatformAgreement.mismatch);
    });

    test('a Switch-family hint agrees with both consoles (T-0023)', () {
      // The model answers SWITCH off a Switch 2 band as readily as off a
      // Switch 1 one -- some of the Switch-hinted hi-res detections, checked
      // against the photograph. Sinking the 508 row would put every Switch 2
      // exclusive out of reach of `best`, because a mismatch is refused there.
      expect(against('SWITCH', _switch2), PlatformAgreement.match);
      expect(against('NINTENDO SWITCH', _switch2), PlatformAgreement.match);
      expect(against('SWITCH', _xbox), PlatformAgreement.mismatch);
    });

    test('the bare manufacturer wordmark matches its whole family', () {
      // "NINTENDO" is left unmapped on purpose (it is equally an NES, an N64
      // and a Wii), and an unmapped hint is what dropped the query filter for
      // a whole run. Falling back to the platform name narrows without
      // pretending to pick a console.
      expect(against('NINTENDO', _switch), PlatformAgreement.match);
      expect(against('NINTENDO', _switch2), PlatformAgreement.match);
      expect(against('NINTENDO', _xbox), PlatformAgreement.mismatch);
      expect(against('NINTENDO', (34, 'Android')), PlatformAgreement.mismatch);
      // Measured on the MOONLIGHT + MOONLIGHT 2 row: IGDB names the console
      // "Wii U", with no manufacturer in it, so a NINTENDO hint sinks a Wii U
      // candidate below the Switch one. Under-matching, in the direction that
      // costs a rank rather than an item.
      expect(against('NINTENDO', (41, 'Wii U')), PlatformAgreement.mismatch);
    });

    test('the band spelling names one console, not the family', () {
      // The half a Switch-family hint cannot express. The model does not
      // produce this today (every Nintendo spine answered SWITCH), so this
      // is what a prompt that read the printed `2` would buy -- more rows
      // auto-matched correctly than as it ships, with the same 0 wrong.
      expect(against('NINTENDO SWITCH 2', _switch2), PlatformAgreement.match);
      expect(against('NINTENDO SWITCH 2', _switch), PlatformAgreement.mismatch);
      expect(against('SWITCH 2', _switch2), PlatformAgreement.match);
    });

    test('a hint that was never read claims nothing', () {
      for (final hint in [null, '', '   ']) {
        expect(against(hint, _switch), PlatformAgreement.unknown);
        expect(against(hint, _xbox), PlatformAgreement.unknown);
      }
    });
  });

  group('best is gated on the platform', () {
    test('a candidate contradicting the hint is refused, not deleted',
        () async {
      // Run A's Nocturne 5 Gold: 1.000 on six consoles, best was the Xbox row.
      final resolved = await _resolve(
        [
          _game(1, 'Nocturne 5 Gold', [_xbox, _ps4]),
        ],
        title: 'NOCTURNE 5 GOLD',
        hint: 'NINTENDO',
      );
      expect(resolved.best, isNull);
      expect(resolved.candidates, hasLength(2));
      expect(resolved.candidates.first.score, 1.0);
    });

    test('the agreeing row is promoted into the reviewer take(5)', () async {
      // The half a threshold cannot reach: in 5 of T-0008's 10 platform false
      // positives the correct row was outside take(5), so the review screen
      // could not fix them either.
      final resolved = await _resolve(
        [
          _game(1, 'Nocturne 5 Gold', [
            _xbox,
            _ps4,
            (6, 'PC (Microsoft Windows)'),
            (167, 'PlayStation 5'),
            (49, 'Xbox One'),
            _switch,
          ]),
        ],
        title: 'NOCTURNE 5 GOLD',
        hint: 'NINTENDO',
      );
      expect(resolved.best?.platformId, _switch.$1);
      expect(resolved.candidates.first.platformId, _switch.$1);
      expect(resolved.candidates, hasLength(5));
    });

    test('a hint too coarse to separate two tied platforms decides nothing',
        () async {
      // A Switch-family title scores 1.000 on both Switch and Switch 2
      // under a NINTENDO hint; the sort picks the Switch 2 row, which was
      // right on a minority of that group.
      final resolved = await _resolve(
        [
          _game(1, 'Harbour Starburst', [_switch2, _switch]),
        ],
        title: 'HARBOUR STARBURST',
        hint: 'NINTENDO',
      );
      expect(resolved.best, isNull);
      expect(resolved.candidates.map((c) => c.platformId),
          containsAll([_switch.$1, _switch2.$1]));
    });

    test('a tie the hint does separate still auto-matches', () async {
      final resolved = await _resolve(
        [
          _game(1, 'Old Dusk Reckonings', [(34, 'Android'), _switch]),
        ],
        title: 'OLD DUSK RECKONINGS',
        hint: 'SWITCH',
      );
      expect(resolved.best?.platformId, _switch.$1);
    });

    test('a lower-scoring agreeing row does not beat the threshold', () async {
      // The gate reorders; it does not lower the bar. minAutoScore is
      // unchanged because the scores it sorts have no gap to move it into.
      final resolved = await _resolve(
        [
          _game(1, 'Moonlight 2', [_switch]),
        ],
        title: 'MOONLIGHT + MOONLIGHT 2',
        hint: 'NINTENDO',
      );
      expect(minAutoScore, 0.85);
      expect(resolved.best, isNull);
      expect(resolved.candidates.single.score, lessThan(minAutoScore));
    });
  });

  group('the states the gate must not break', () {
    test('a detection with no platform hint still auto-matches', () async {
      // The state T-0001 measured. An absent hint is
      // not a contradiction: nothing is gated, and a candidate no other
      // platform ties with is still the answer.
      final resolved = await _resolve(
        [
          _game(1, 'Duskhollow', [_ps4]),
        ],
        title: 'Duskhollow',
      );
      expect(resolved.best?.platformId, _ps4.$1);
    });

    test('without a hint a cross-platform tie is still refused', () async {
      // Measured with the hints stripped from every hi-res detection: the
      // rule refuses every wrong-console auto-match -- a console title
      // answered as PC, and the others like it -- and costs correct ones
      // that are coin tosses of the same kind.
      final resolved = await _resolve(
        [
          _game(1, 'Nebulae Drift', [(6, 'PC (Microsoft Windows)'), _switch]),
        ],
        title: 'Nebulae Drift',
      );
      expect(resolved.best, isNull);
      expect(resolved.candidates, hasLength(2));
      expect(resolved.candidates.first.score, 1.0);
    });

    test('a wrong but mapped hint gives up the match rather than fake one',
        () async {
      // The Path of Ember spines answer PS2 off a Switch 2 case (T-0029): the
      // query is constrained to a platform the game is not on, IGDB returns
      // nothing, and the row reaches review empty. A miss survives review; a
      // confident wrong id does not.
      final resolved = await _resolve(
        [
          _game(1, 'Path of Ember: Ashes!', [_switch]),
        ],
        title: 'PATH OF EMBER ASHES',
        hint: 'PS2',
      );
      expect(resolved.best, isNull);
      expect(resolved.candidates, isEmpty);
    });

    test('a resolver with no candidates at all is unchanged', () async {
      final resolved = await _resolve(const [],
          title: 'SOLAR PILGRIM XII THE CINDER AGE', hint: 'SWITCH');
      expect(resolved.best, isNull);
      expect(resolved.candidates, isEmpty);
    });
  });

  group('a Switch-family hint reaches both consoles (T-0023)', () {
    Future<String> queryFor(String? hint) async {
      final bodies = <String>[];
      final transport = MockClient((request) async {
        if (request.url.host == 'id.twitch.tv') {
          return http.Response(
              jsonEncode({'access_token': 'stub', 'expires_in': 3600}), 200);
        }
        bodies.add(request.body);
        return http.Response('[]', 200);
      });
      await IgdbClient(clientId: 'stub', clientSecret: 'stub', client: transport)
          .search('Harbour Starburst', platformHint: hint);
      return bodies.single;
    }

    test('the filter names both ids as a union', () async {
      // `(a,b)` is a union, measured live 2026-08-15: it returns a game listed
      // on 508 alone. `[a,b]` and `{a,b}` are exact-set matches and return 0
      // rows for both Solar Pilgrim VII titles.
      expect(await queryFor('SWITCH'),
          contains('where platforms = (130,508);'));
      expect(await queryFor('NINTENDO SWITCH'), await queryFor('SWITCH'));
    });

    test('a one-console hint still names one id', () async {
      expect(await queryFor('PS5'), contains('where platforms = (167);'));
      expect(await queryFor('SWITCH 2'), contains('where platforms = (508);'));
    });

    test('a Switch 2 exclusive auto-matches off a SWITCH hint', () async {
      // The bug this task was filed for: constrained to 130 alone, IGDB
      // returned 0 rows for `solar pilgrim vii resurge` and `solar pilgrim vii
      // remake interbloom`, so the human got "no candidates" instead of the
      // one candidate they could have picked.
      final resolved = await _resolve(
        [
          _game(1, 'Solar Pilgrim VII Resurge', [_switch2]),
        ],
        title: 'SOLAR PILGRIM VII RESURGE',
        hint: 'SWITCH',
      );
      expect(resolved.best?.platformId, _switch2.$1);
    });

    test('a console outside the family is still dropped from the hits',
        () async {
      // The union widens the filter by exactly one console. IGDB answers with
      // every platform of a matched game, so the pair filter is what keeps a
      // PS5 row out of a Switch reviewer's list.
      final resolved = await _resolve(
        [
          _game(1, 'Solar Pilgrim VII Resurge',
              [(167, 'PlayStation 5'), _switch2, _xbox]),
        ],
        title: 'SOLAR PILGRIM VII RESURGE',
        hint: 'SWITCH',
      );
      expect(resolved.candidates.map((c) => c.platformId), [_switch2.$1]);
    });

    test('a game IGDB lists on both consoles decides nothing', () async {
      // What the union costs, and it is the tie rule rather than the filter:
      // rows that auto-matched correctly on 130 alone now tie 1.000 across
      // 130 and 508 and go to review -- Switch 1 back-catalogue titles, and
      // the others like them on the same photograph. A Switch 2 title has
      // the same shape, so the shape cannot be used to pick a side.
      final resolved = await _resolve(
        [
          _game(1, 'Harbour Starburst', [_switch2, _switch]),
        ],
        title: 'HARBOUR STARBURST',
        hint: 'SWITCH',
      );
      expect(resolved.best, isNull);
      expect(resolved.candidates.map((c) => c.platformId),
          containsAll([_switch.$1, _switch2.$1]));
    });
  });
}
