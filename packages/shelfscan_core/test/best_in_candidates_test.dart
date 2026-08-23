/// The row's `best` is always one of the `candidates` shipped beside it
/// (T-0322).
///
/// `best` is drawn from the whole scored list and `candidates` is its first
/// five, so the two can disagree — but only through
/// `_separatedBySourceYear`, T-0171's tie-breaker, which searches every entry
/// tied at the top score rather than the window. The tied entries are
/// contiguous from index 0, so a tie more than five deep whose source year
/// names one at index 5 or beyond used to ship a `best` in no candidate list.
///
/// Every fixture here is invented — the titles, the catalogue ids and the
/// years. The platform ids are IGDB's own and are the vocabulary under test.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

const _pc = (6, 'PC (Microsoft Windows)');
const _ps4 = (48, 'PlayStation 4');
const _ps5 = (167, 'PlayStation 5');
const _xbox = (49, 'Xbox One');
const _linux = (3, 'Linux');
const _switch1 = (130, 'Nintendo Switch');

Map<String, dynamic> _game(int id, String name, List<(int, String)> platforms,
        {int? year}) =>
    {
      'id': id,
      'name': name,
      if (year != null)
        'first_release_date':
            DateTime.utc(year, 6, 1).millisecondsSinceEpoch ~/ 1000,
      'platforms': [
        for (final (platformId, platformName) in platforms)
          {'id': platformId, 'name': platformName},
      ],
    };

Future<ResolvedGame> _resolve(
    List<Map<String, dynamic>> games, Detection detection) {
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

Detection _named(String title, {required String hint, int? year}) =>
    Detection.fromSource(
      rawTitle: title,
      origin: DetectionOrigin.filename,
      sourceEntry: '$title.iso',
      platformHint: hint,
      sourceYear: year,
    );

/// The same key `_RowSheet._isBest` matches the pick against on the review
/// screen, so "in the list" here means what it means there.
bool _holds(List<Candidate> candidates, Candidate? best) =>
    best != null &&
    candidates.any((c) =>
        c.externalId == best.externalId && c.platformId == best.platformId);

/// Six identically named releases on one platform, distinct years, in the
/// order IGDB answers them. The last is the only one 2008 names.
List<Map<String, dynamic>> _sixDeepTie() => [
      _game(7101, 'Harrowgate Wardens', [_pc], year: 1991),
      _game(7102, 'Harrowgate Wardens', [_pc], year: 1994),
      _game(7103, 'Harrowgate Wardens', [_pc], year: 1997),
      _game(7104, 'Harrowgate Wardens', [_pc], year: 2001),
      _game(7105, 'Harrowgate Wardens', [_pc], year: 2004),
      _game(7106, 'Harrowgate Wardens', [_pc], year: 2008),
    ];

void main() {
  group('the tie deeper than the window', () {
    test('the year names a row the window cuts, and the row still ships it',
        () async {
      final resolved = await _resolve(_sixDeepTie(),
          _named('Harrowgate Wardens', hint: 'PC', year: 2008));

      // The tie-breaker reached past the window: this is the defect's own
      // shape, and the assertion below it is the fix.
      expect(resolved.best?.externalId, 'igdb:7106');
      expect(resolved.candidates.take(5).map((c) => c.externalId),
          isNot(contains('igdb:7106')),
          reason: 'the pick is outside the first five, which is the case');
      expect(_holds(resolved.candidates, resolved.best), isTrue,
          reason: 'the sheet has to be able to show the pick as chosen');
    });

    test('the window widens by exactly one and drops nothing', () async {
      final resolved = await _resolve(_sixDeepTie(),
          _named('Harrowgate Wardens', hint: 'PC', year: 2008));

      expect(resolved.candidates.map((c) => c.externalId), [
        'igdb:7101',
        'igdb:7102',
        'igdb:7103',
        'igdb:7104',
        'igdb:7105',
        'igdb:7106',
      ]);
    });

    test('a tie the year cannot settle is refused and the window stays five',
        () async {
      // Nothing carries 1988, so `_best` returns null exactly as before and
      // there is no pick to carry.
      final resolved = await _resolve(_sixDeepTie(),
          _named('Harrowgate Wardens', hint: 'PC', year: 1988));
      expect(resolved.best, isNull);
      expect(resolved.candidates, hasLength(5));
    });

    test('a pick already inside the window leaves the list untouched',
        () async {
      final resolved = await _resolve(_sixDeepTie(),
          _named('Harrowgate Wardens', hint: 'PC', year: 1991));
      expect(resolved.best?.externalId, 'igdb:7101');
      expect(resolved.candidates, hasLength(5));
      expect(_holds(resolved.candidates, resolved.best), isTrue);
    });

    test('a five-deep tie is the boundary and was never affected', () async {
      final resolved = await _resolve(_sixDeepTie().take(5).toList(),
          _named('Harrowgate Wardens', hint: 'PC', year: 2004));
      expect(resolved.best?.externalId, 'igdb:7105');
      expect(resolved.candidates, hasLength(5));
      expect(_holds(resolved.candidates, resolved.best), isTrue);
    });

    test('the ordinary path is unchanged: one hit, no tie', () async {
      final resolved = await _resolve(
          [_game(7110, 'Vellum Tide', [_pc], year: 2019)],
          _named('Vellum Tide', hint: 'PC', year: 2019));
      expect(resolved.best?.externalId, 'igdb:7110');
      expect(resolved.candidates.map((c) => c.externalId), ['igdb:7110']);
    });
  });

  group("T-0008's guarantee is untouched", () {
    // The hint is one [platformIds] cannot map, which is the case T-0008
    // measured: the query runs unfiltered and IGDB answers one hit per
    // (game, platform) pair. A hint it can map never gets here, because the
    // search itself has already dropped the other consoles.
    test('a contradicting candidate sinks, and the agreeing row is inside the '
        'window', () async {
      // The agreeing row answered last. Before the mismatch-last sort it was
      // outside the window in half of T-0008's platform false positives, so
      // the review screen could not fix them either.
      final resolved = await _resolve([
        _game(7201, 'Vellum Tide', [_xbox], year: 2019),
        _game(7202, 'Vellum Tide', [_ps4], year: 2019),
        _game(7203, 'Vellum Tide', [_ps5], year: 2019),
        _game(7204, 'Vellum Tide', [_pc], year: 2019),
        _game(7205, 'Vellum Tide', [_linux], year: 2019),
        _game(7206, 'Vellum Tide', [_switch1], year: 2019),
      ], _named('Vellum Tide', hint: 'NINTENDO', year: 2019));

      expect(resolved.best?.platformId, 130);
      expect(resolved.candidates.first.platformId, 130,
          reason: 'the agreeing row rose to the top of the window');
      expect(resolved.candidates, hasLength(5));
      expect(resolved.candidates.skip(1).map((c) => c.platformId),
          [49, 48, 167, 6],
          reason: 'the contradicting rows are beneath it, in order, kept');
      expect(_holds(resolved.candidates, resolved.best), isTrue);
    });

    test('the widened window carries the pick and nothing else', () async {
      // A tie deeper than the window with a contradicting row in the same
      // answer. `_separatedBySourceYear` only ever returns a non-mismatch
      // entry, so widening cannot promote a wrong-console row.
      final resolved = await _resolve([
        _game(7210, 'Vellum Tide', [_xbox], year: 2010),
        for (var i = 0; i < 6; i++)
          _game(7211 + i, 'Vellum Tide', [_switch1], year: 2011 + i),
      ], _named('Vellum Tide', hint: 'NINTENDO', year: 2016));

      expect(resolved.best?.externalId, 'igdb:7216');
      expect(resolved.candidates, hasLength(6));
      expect(resolved.candidates.every((c) => c.platformId == 130), isTrue,
          reason: 'the one row added is the pick, and the pick agrees');
      expect(resolved.candidates.last.externalId, 'igdb:7216');
    });

    test('a row that contradicts the hint is still never `best`', () async {
      final resolved = await _resolve([
        for (var i = 0; i < 6; i++)
          _game(7220 + i, 'Vellum Tide', [_xbox], year: 2010 + i),
      ], _named('Vellum Tide', hint: 'NINTENDO', year: 2015));
      expect(resolved.best, isNull);
      expect(resolved.candidates, hasLength(5),
          reason: 'no pick, so no widening');
    });
  });
}
