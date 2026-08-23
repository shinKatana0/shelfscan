/// The tie `_best` could not see: two rows at the identical top score on ONE
/// platform (T-0165).
///
/// A hint that maps to a single id -- `PC` -> {6}, `PS4`, `PS5`, `SWITCH2` --
/// leaves every surviving row on that id, so T-0002's console clause can never
/// fire and IGDB's ordering decided between two different games. The rows
/// below are the ones measured live 2026-08-16 (doc/measurements.md, "The tie
/// nobody could see"): the three desktop collisions the rule now refuses, and
/// the console rows that
/// must keep auto-matching, which is what the release-year exemption is for.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

const _pc = (6, 'PC (Microsoft Windows)');
const _ps5 = (167, 'PlayStation 5');
const _switch1 = (130, 'Nintendo Switch');
const _switch2 = (508, 'Nintendo Switch 2');
const _xbox = (169, 'Xbox Series X|S');

Map<String, dynamic> _game(
  int id,
  String name,
  List<(int, String)> platforms, {
  int? year,
  List<String> alternativeNames = const [],
  int? releasedAt,
}) =>
    {
      'id': id,
      'name': name,
      if (alternativeNames.isNotEmpty)
        'alternative_names': [
          for (final alternative in alternativeNames) {'name': alternative},
        ],
      if (year != null)
        'first_release_date':
            DateTime.utc(year, 6, 1).millisecondsSinceEpoch ~/ 1000,
      if (releasedAt != null) 'first_release_date': releasedAt,
      'platforms': [
        for (final (platformId, platformName) in platforms)
          {'id': platformId, 'name': platformName},
      ],
    };

Future<ResolvedGame> _resolve(
  List<Map<String, dynamic>> games, {
  required String title,
  String? hint,
}) {
  final transport = MockClient((request) async {
    if (request.url.host == 'id.twitch.tv') {
      return http.Response(
          jsonEncode({'access_token': 'stub-token', 'expires_in': 3600}), 200);
    }
    return http.Response(jsonEncode(games), 200);
  });
  return ResolverWorker(
          IgdbClient(clientId: 'stub', clientSecret: 'stub', client: transport))
      .process(Detection(
    rawTitle: title,
    platformHint: hint,
    mediaType: MediaType.unknown,
    confidence: 1.0,
    sourcePhoto: '',
  ));
}

void main() {
  group('the three collisions measured under a single-id hint', () {
    test('two identically named games, 1993 and 2016, are not guessed between',
        () async {
      final resolved = await _resolve([
        _game(1100000058, 'Regent of Aurex', [_pc], year: 1993),
        _game(1100000009, 'Regent of Aurex', [_pc], year: 2016),
      ], title: 'regent of aurex', hint: 'PC');
      expect(resolved.best, isNull);
      // Refused, never hidden: both are still the reviewer's to pick from.
      expect(resolved.candidates.map((c) => c.externalId), ['igdb:1100000058', 'igdb:1100000009']);
      expect(resolved.candidates.map((c) => c.score), everyElement(1.0));
    });

    test('1993 and 2012 under one name, likewise', () async {
      final resolved = await _resolve([
        _game(1100000059, 'Cabalists', [_pc], year: 1993),
        _game(1100000010, 'Cabalists', [_pc], year: 2012),
      ], title: 'cabalists', hint: 'PC');
      expect(resolved.best, isNull);
    });

    test('a tie scored on an alternative name counts', () async {
      // The read matches one game's canonical name and the other's alternative
      // name, both at 1.000. Live 2026-08-16 the auto-match went to the 2016
      // reboot off a read that GoG writes for the 1993 game.
      final resolved = await _resolve([
        _game(1100000011, 'Moor', [_pc], year: 2016),
        _game(1100000012, 'The Ultimate Moor', [_pc],
            year: 1995, alternativeNames: ['Moor']),
      ], title: 'moor', hint: 'PC');
      expect(resolved.best, isNull);
      expect(resolved.candidates.map((c) => c.score), everyElement(1.0));
    });
  });

  group('one release under two entries still auto-matches', () {
    test('a game and its own collectors edition, same release day', () async {
      // The whole cost of refusing every same-platform tie, on the control
      // set: one row of each control set, this one.
      final released =
          DateTime.utc(2023, 6, 22).millisecondsSinceEpoch ~/ 1000;
      final resolved = await _resolve([
        _game(1100000049, 'Solar Pilgrim XVI', [_ps5], releasedAt: released),
        _game(1100000050, "Solar Pilgrim XVI: Collector's Edition", [_ps5],
            releasedAt: released, alternativeNames: ['Solar Pilgrim XVI']),
      ], title: 'solar pilgrim xvi', hint: 'PS5');
      expect(resolved.best?.externalId, 'igdb:1100000049');
    });

    test('two IGDB entries for one release, on a single-id console hint',
        () async {
      final resolved = await _resolve([
        _game(1100000051, 'Old Dusk Reckonings', [_switch2], year: 2023),
        _game(1100000052, 'Old Dusk Reckonings', [_switch2], year: 2023),
      ], title: 'old dusk reckonings', hint: 'SWITCH2');
      expect(resolved.best?.externalId, 'igdb:1100000051');
    });

    test('an unanswered year refuses, like any other unanswered question',
        () async {
      // A small fraction of the games one control run touches carry no
      // `first_release_date` at all.
      final resolved = await _resolve([
        _game(1, 'Cabalists', [_pc]),
        _game(2, 'Cabalists', [_pc]),
      ], title: 'cabalists', hint: 'PC');
      expect(resolved.best, isNull);
    });
  });

  group('the console clause is unchanged', () {
    test('one game on both Switch consoles is still refused, same year or not',
        () async {
      // T-0023's case: identical id, identical year, and the platform is
      // exactly what the human has to decide -- so the year must not exempt it.
      final resolved = await _resolve([
        _game(1100000053, 'Starweave Chronicles 2: Kaira - The Hidden Country',
            [_switch2, _switch1],
            year: 2018),
      ],
          title: 'starweave chronicles 2 kaira the hidden country',
          hint: 'SWITCH');
      expect(resolved.best, isNull);
      expect(resolved.candidates.map((c) => c.platformId), [508, 130]);
    });

    test('a candidate contradicting the hint makes nothing ambiguous',
        () async {
      // `NINTENDO` maps to no ids, so the query runs unfiltered and the Xbox
      // row arrives scoring the same. It sinks and is ignored here.
      final resolved = await _resolve([
        _game(1, 'Nebulae Drift', [_switch1], year: 2021),
        _game(2, 'Nebulae Drift', [_xbox], year: 2021),
      ], title: 'nebulae drift', hint: 'NINTENDO');
      expect(resolved.best?.platformId, 130);
    });
  });

  group('a year the source carries is refused two gates earlier', () {
    // Why the fix is on the candidate side: no *photograph* read carries a
    // year -- none on either control set -- because a spine does not
    // print one. T-0171 later gave a filename source's year a way through
    // (`Detection.sourceYear`), so a read that carries one now does reach the
    // tie rule, as a separate and narrower exemption; these assertions are
    // about the candidate side and are unaffected.
    final aurexPair = [
      _game(1100000058, 'Regent of Aurex', [_pc], year: 1993),
      _game(1100000009, 'Regent of Aurex', [_pc], year: 2016),
    ];

    test('the score falls below the threshold first', () async {
      final bare = await _resolve(aurexPair,
          title: 'regent of aurex 1993', hint: 'PC');
      expect(bare.candidates.first.score, closeTo(0.750, 0.001));
      final bracketed = await _resolve(aurexPair,
          title: 'regent of aurex (1993)', hint: 'PC');
      expect(bracketed.candidates.first.score, closeTo(0.682, 0.001));
      expect(bare.best, isNull);
      expect(bracketed.best, isNull);
    });

    test('and the volume gate refuses it as well', () {
      expect(volumeNumbersAgree('regent of aurex 1993', 'Regent of Aurex'),
          isFalse);
      // Which is why four-digit numbers cannot simply be exempted from that
      // key: on a sports title the number IS the volume.
      expect(volumeNumbersAgree('punter pfl 2004', 'Punter PFL 2004'), isTrue);
      expect(volumeNumbersAgree('punter pfl 2004', 'Punter PFL 2005'), isFalse);
    });
  });

  group('IgdbHit.releaseYear', () {
    test('reads the year in UTC, not in the machine timezone', () async {
      // Either end of a year is wrong by one in some timezone; the hit carries
      // the year IGDB's timestamp is in.
      for (final moment in [
        DateTime.utc(2016, 1, 1, 0, 30),
        DateTime.utc(2016, 12, 31, 23, 30),
      ]) {
        final resolved = await _resolve([
          _game(1, 'Regent of Aurex', [_pc],
              releasedAt: moment.millisecondsSinceEpoch ~/ 1000),
          _game(2, 'Regent of Aurex', [_pc],
              releasedAt:
                  DateTime.utc(2016, 6, 1).millisecondsSinceEpoch ~/ 1000),
        ], title: 'regent of aurex', hint: 'PC');
        expect(resolved.best?.externalId, 'igdb:1',
            reason: 'both games released in ${moment.toIso8601String()}\'s '
                'UTC year, so the tie is one release, not two');
      }
    });
  });
}
