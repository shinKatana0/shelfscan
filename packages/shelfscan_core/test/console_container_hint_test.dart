/// What a console container's hint is worth once it reaches the gate (T-0168).
///
/// `filename_source_test.dart` pins which hint each container earns. This file
/// is the other half and the one the decision rests on: the hint driven
/// through the **real** `ResolverWorker` and `IgdbClient`, so the claim is
/// "this row resolves" rather than "this string is in a table".
///
/// No network and no key: the transport is a `MockClient` answering with rows
/// shaped like IGDB's, and the client's own platform filter then runs on them
/// exactly as it does live. What is NOT measured here is how many of real
/// titles IGDB lists on both Switch bands -- that is a live figure and
/// doc/measurements.md, "The tie nobody could see", measured it on 2026-08-16.
/// What is measured here is what happens to a row in each of those cases,
/// which is offline and was not pinned anywhere before.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

const _switch1 = (130, 'Nintendo Switch');
const _switch2 = (508, 'Nintendo Switch 2');

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

/// One entry through the whole source and the whole resolver, which is the
/// point: the hint under test is the one `FilenameSource` actually writes.
Future<ResolvedGame> _run(String entryName, List<Map<String, dynamic>> games,
    {String? container}) {
  final detection = const FilenameSource()
      .read(SourceEntry(name: entryName, container: container))
      .items
      .single;
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
  // One game on both Switch bands, which is the shape the union exists for and
  // the shape it pays for. T-0165 re-measured the price live on 2026-08-16:
  // the tie rule refuses real rows, and today nearly every one of them would
  // otherwise auto-match to the WRONG band rather than the right one -- the
  // inverse of what T-0023 measured, because IGDB's ordering flipped and
  // nothing in this repository moved.
  final onBothBands = [
    _game(1022, 'Sample Game A', [_switch1, _switch2], year: 2017),
  ];

  group('a Switch container, before and after', () {
    test('the PC hint left the row with nothing at all', () async {
      // The state this task changed, driven rather than described. The hint
      // narrows the IGDB query to platform 6, a Switch-only game is listed on
      // no such platform, and the row reaches review with no candidate to
      // pick -- which is the failure T-0156 named and T-0113 priced.
      final resolved = await _run('Sample Game A', onBothBands);
      expect(resolved.detection.platformHint, filenamePlatformHint);
      expect(resolved.best, isNull);
      expect(resolved.candidates, isEmpty);
    });

    test('the SWITCH hint reaches both bands and refuses to choose', () async {
      final resolved = await _run('Sample Game A [NSP]', onBothBands);
      expect(resolved.detection.platformHint, 'SWITCH');
      // Two candidates where `PC` had none: the union is what makes the game
      // reachable at all.
      expect(resolved.candidates.map((c) => c.platformId), [130, 508]);
      expect(resolved.candidates.map((c) => c.score), everyElement(1.0));
      // And no auto-match, because the two differ only by console. That is
      // T-0023's clause, untouched by T-0165 -- the release-year exemption
      // applies to two rows on ONE platform, and these are on two.
      expect(resolved.best, isNull);
    });

    test('the band, if a name could ever print it, is the whole difference',
        () async {
      // Not a proposal: no `.nsp` prints a band and T-0074 measured thirteen
      // prompt wordings failing to read one off a case. It is the measurement
      // of what the union costs -- one tap at review, on a game the desktop
      // hint could not have shown the human at all.
      final resolved = await _run('Sample Game A [NSP]', onBothBands);
      final scored = resolved.candidates
          .where((c) => platformIds['SWITCH2']!.contains(c.platformId));
      expect(scored, hasLength(1));
      expect(resolved.best, isNull);
    });

    test('a band-exclusive title is what the union buys', () async {
      // The other side of the same trade, and the reason `SWITCH` is not
      // narrowed to 130: IGDB lists Solar Pilgrim VII Resurge on 508 and not
      // on 130 (igdb.dart, live 2026-08-15), so a Switch-1 filter answers a
      // real Switch game with zero rows.
      final resolved = await _run('Sample Game S.xci', [
        _game(3011, 'Sample Game S', [_switch2], year: 2025),
      ]);
      expect(resolved.best?.platformId, 508);
      expect(resolved.best?.igdbId, 3011);
    });
  });

  group('the source year cannot pay for the union', () {
    test('because the tied rows sit on two platforms', () async {
      // The one thing that looked as though it might. T-0165 found no source
      // with a year to give and T-0171 wired one in; this source is that
      // source -- it is the only one in the product that parses a year. It
      // still cannot separate a cross-band tie, by construction: the tie-break
      // fires only where the tied rows share a platform, because where they do
      // not it is the console the human has to decide and a year cannot answer
      // that.
      final resolved =
          await _run('Sample Game A (2017) [NSP]', onBothBands);
      expect(resolved.detection.sourceYear, 2017);
      expect(resolved.detection.platformHint, 'SWITCH');
      expect(resolved.best, isNull);
    });

    test('and it does pay where a container names one platform', () async {
      // The mirror, so the refusal above reads as a property of the union and
      // not of this source: a `.gba` names exactly one id, the two rows then
      // tie on it, and the year the name printed picks the one it names.
      final resolved = await _run('Sample Game U (2004).gba', [
        _game(41, 'Sample Game U', [(24, 'Game Boy Advance')], year: 2004),
        _game(42, 'Sample Game U', [(24, 'Game Boy Advance')], year: 2011),
      ]);
      expect(resolved.detection.platformHint, 'GBA');
      expect(resolved.best?.igdbId, 41);
    });
  });

  test('an unnameable container reaches the resolver as no row at all',
      () async {
    // The result the brief asked to be stated rather than worked around. A
    // `.pkg` is a PlayStation package across PS3, PS4 and Vita and a `.chd` is
    // not a PlayStation format at all; either hint would come back `mismatch`
    // on every candidate, and the row would be strictly worse than absent.
    for (final name in ['Sample Game H.pkg', 'Sample Game I.chd']) {
      final reading = const FilenameSource().read(SourceEntry(name: name));
      expect(reading.items, isEmpty, reason: name);
      expect(reading.declined.single.reason, DeclineReason.notAPcInstaller,
          reason: name);
    }
  });
}
