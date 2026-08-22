/// Guards the desktop entry on the platform gate (T-0156).
///
/// Every hint in `platformIds` before this one is read off a case by the
/// vision model. These three are written by a source that has no photograph:
/// a GoG install (T-0157) or an installer filename (T-0158). The row that
/// carries no hint at all falls through T-0002's gate unfiltered, and a hint
/// the table cannot turn into ids makes `platformAgreement` answer `mismatch`,
/// which `ResolverWorker._best` refuses outright -- so what a PC source emits
/// decides whether its rows resolve at all, and the spellings below are the
/// contract between that source and this table.
///
/// The numbers here were taken by replaying one live IGDB answer per title
/// through the real resolver under each candidate mapping, 2026-08-16;
/// doc/measurements.md, "The tie nobody could see", holds the tables.
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
const _ps5 = (167, 'PlayStation 5');

Map<String, dynamic> _game(int id, String name, List<(int, String)> platforms,
        {List<String> alternativeNames = const []}) =>
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

/// The bodies [IgdbClient] sent, so the `where` clause is asserted as it ships
/// rather than inferred from the rows that came back.
final _bodies = <String>[];

ResolverWorker _resolver(List<Map<String, dynamic>> games) {
  final transport = MockClient((request) async {
    if (request.url.host == 'id.twitch.tv') {
      return http.Response(
          jsonEncode({'access_token': 'stub-token', 'expires_in': 3600}), 200);
    }
    _bodies.add(request.body);
    return http.Response(jsonEncode(games), 200);
  });
  return ResolverWorker(
      IgdbClient(clientId: 'stub', clientSecret: 'stub', client: transport));
}

Future<ResolvedGame> _resolve(
  List<Map<String, dynamic>> games, {
  required String title,
  String? hint = 'PC',
}) =>
    _resolver(games).process(Detection(
      rawTitle: title,
      platformHint: hint,
      mediaType: MediaType.unknown,
      confidence: 1.0,
      sourcePhoto: '',
    ));

void main() {
  setUp(_bodies.clear);

  group('the spellings a PC source may emit', () {
    test('all three reach IGDB platform 6', () {
      expect(platformIds['PC'], {6});
      expect(platformIds['WINDOWS'], {6});
      expect(platformIds['PCWINDOWS'], {6});
    });

    test('a store name is not one of them', () {
      // The second failure this task exists for: an unmapped hint runs the
      // query unfiltered and is then compared against the platform NAME, and
      // "GOG" is a word no platform name contains -- so every candidate the
      // row has comes back `mismatch` and `best` refuses all of them.
      expect(platformIds['GOG'], isNull);
      expect(
          platformAgreement('GOG',
              platformId: _pc.$1, platformName: _pc.$2),
          PlatformAgreement.mismatch);
    });
  });

  group('platformAgreement under a desktop hint', () {
    PlatformAgreement against(String hint, (int, String) platform) =>
        platformAgreement(hint,
            platformId: platform.$1, platformName: platform.$2);

    test('Windows agrees, the rest of the desktop does not', () {
      expect(against('PC', _pc), PlatformAgreement.match);
      expect(against('pc', _pc), PlatformAgreement.match);
      expect(against('WINDOWS', _pc), PlatformAgreement.match);
      expect(against('PC WINDOWS', _pc), PlatformAgreement.match);
      expect(against('PC', _linux), PlatformAgreement.mismatch);
      expect(against('PC', _mac), PlatformAgreement.mismatch);
      expect(against('PC', _dos), PlatformAgreement.mismatch);
      expect(against('PC', _ps5), PlatformAgreement.mismatch);
    });

    test('a console hint still refuses a Windows row', () {
      // The direction that was already broken: `Nebulae Drift -> PC` is one of
      // T-0008's eleven confident false positives.
      expect(against('SWITCH', _pc), PlatformAgreement.mismatch);
      expect(against('NINTENDO', _pc), PlatformAgreement.mismatch);
    });
  });

  group('one id, not a set', () {
    final crossListed = [
      _game(1, 'Sundrop Hollow', [_pc, _linux, _mac]),
    ];

    test('the query asks for 6 alone', () async {
      await _resolve(crossListed, title: 'sundrop hollow');
      expect(_bodies.single, contains('where platforms = (6);'));
    });

    test('a game on Windows, Linux and Mac is one candidate and a match',
        () async {
      // The whole of the decision, in one row. Under `{6,3,14}` this game
      // arrives three times at one score differing only in platform id, which
      // is the tie `_best` refuses: measured 1 auto-match of 8 against 8 of 8,
      // and 0 of the 8 titles was reachable on Linux or Mac but not on
      // Windows. `{6,13}` behaves the same on the DOS-era set: 1 of 6 against
      // 5 of 6.
      final resolved = await _resolve(crossListed, title: 'sundrop hollow');
      expect(resolved.candidates, hasLength(1));
      expect(resolved.candidates.single.platformId, 6);
      expect(resolved.best?.title, 'Sundrop Hollow');
    });

    test('what the narrow mapping costs is a title Windows does not carry',
        () async {
      // Mire II, the one of 6 DOS-era classics IGDB does not also list on 6:
      // the query never asks for 13, so the row reaches review with no
      // candidates at all rather than with sunk ones.
      final resolved = await _resolve(
          [_game(2, 'Mire II: The Founding of a Kingdom', [_dos])],
          title: 'mire ii the founding of a kingdom');
      expect(resolved.candidates, isEmpty);
      expect(resolved.best, isNull);
    });
  });

  group('the two rules written against consoles, under a PC hint', () {
    test('the tie rule fires on one platform since T-0165', () async {
      // T-0156 measured this the other way: `_best` refused a tie only between
      // candidates on DIFFERENT platform ids, so a single-id hint left every
      // surviving row on 6, and some of the replayed titles auto-matched one
      // of two games at the identical top score. The rule now refuses a same-platform
      // tie unless the two carry the same release year; the mechanics and the
      // console cost are in `same_platform_tie_test.dart`.
      final resolved = await _resolve([
        _game(3, 'Regent of Aurex', [_pc]),
        _game(4, 'Regent of Aurex', [_pc]),
      ], title: 'regent of aurex');
      expect(resolved.candidates.map((c) => c.score), everyElement(1.0));
      expect(resolved.best, isNull);
    });

    test('an installer version number is refused twice over', () async {
      // T-0158's hazard, priced here: a filename carries `1.6.15` where a
      // spine carries nothing, and `volumeNumbersAgree` reads those digits as
      // volume markers. It is not the binding gate -- on every replayed
      // title the score fell below minAutoScore first (0.455 to 0.806) -- so
      // a parser that leaves the version in loses the auto-match whatever this
      // rule does.
      expect(volumeNumbersAgree('sundrop hollow 1.6.15', 'Sundrop Hollow'),
          isFalse);
      final resolved = await _resolve(
          [_game(5, 'Sundrop Hollow', [_pc])], title: 'sundrop hollow 1.6.15');
      expect(resolved.best, isNull);
      expect(resolved.candidates.single.score, lessThan(0.85));
    });

    test('the same title without the version auto-matches', () async {
      final resolved =
          await _resolve([_game(5, 'Sundrop Hollow', [_pc])],
              title: 'sundrop hollow');
      expect(resolved.best?.igdbId, 5);
    });
  });
}
