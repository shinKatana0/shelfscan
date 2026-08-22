/// Guards the volume-number gate (T-0100).
///
/// Two Japanese siblings straddle [minAutoScore] in the wrong order -- 0.857
/// for the wrong game, 0.852 for a right one -- so no threshold separates them
/// and the separating fact is not a score. These tests pin what is, and pin
/// the two rows the gate must not touch.
///
/// The shelf was photographed during development and is not published, and the
/// titles below are substituted for the ones that were on it. **The scores are
/// the measured ones**: they were recorded 2026-08-15 against live IGDB
/// responses for a real title, and the substitutions were chosen to preserve
/// the string lengths the scorer reads, so every figure here still pins what
/// was measured rather than what was invented. A substitution that moved one of
/// them would have been refused instead (T-0234).
///
/// The payloads keep the shape of those responses, cut to the fields
/// [IgdbClient] reads and to this task's own rows (the bounded-fixture ceiling,
/// decision 0004).
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

/// `search "<title>"` under `where platforms = (130,508)`, live; the term was
/// the real title and is not published.
const _emberOnSwitch = [
  {
    'id': 1100000004,
    'name': 'Path of Ember: True 3 & Grey Ties',
    'alternative_names': [
      {'name': 'そらのは 真3 / そらのは3別伝 Grey Ties'},
    ],
    'platforms': [
      {'id': 508, 'name': 'Nintendo Switch 2'},
    ],
  },
  {
    'id': 1100000003,
    'name': 'Path of Ember: True',
    // The leading space is IGDB's own, on the alternative name this row stands
    // in for; the id is withheld because it would resolve the substituted
    // title (T-0095).
    'alternative_names': [
      {'name': ' そらのは 真'},
    ],
    'platforms': [
      {'id': 508, 'name': 'Nintendo Switch 2'},
    ],
  },
];

/// The same relation in Latin, from `CONTROL-LOWRES`: a `MOONLIGHT` spine and
/// the sequel IGDB offers for it.
const _moonlight = [
  {
    'id': 1100000005,
    'name': 'Moonlight 2',
    'platforms': [
      {'id': 130, 'name': 'Nintendo Switch'},
    ],
  },
];

Detection _detection(String title, {String? hint}) => Detection(
      rawTitle: title,
      platformHint: hint,
      mediaType: MediaType.cartridge,
      confidence: 1.0,
      sourcePhoto: 'shelf.jpg',
    );

/// Bytes under IGDB's own content type, because `http.Response(String, ...)`
/// encodes latin1 and throws on そ.
IgdbClient _igdb(Map<String, List<Map<String, Object?>>> byTerm) => IgdbClient(
      clientId: 'stub',
      clientSecret: 'stub',
      client: MockClient((request) async {
        if (request.url.host == 'id.twitch.tv') {
          return http.Response(
              jsonEncode({'access_token': 'stub', 'expires_in': 3600}), 200);
        }
        // T-0094's field filter carries no `search` term and, on every title
        // here, no answer either.
        final term = RegExp(r'search "([^"]*)"').firstMatch(request.body);
        final rows =
            term == null ? const [] : byTerm[term.group(1)!] ?? const [];
        return http.Response.bytes(
          utf8.encode(jsonEncode(rows)),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

void main() {
  group('volumeNumbersAgree', () {
    test('a trailing volume number is a different game', () {
      expect(volumeNumbersAgree('そらのは 真2', ' そらのは 真'), isFalse);
      expect(volumeNumbersAgree('MOONLIGHT', 'Moonlight 2'), isFalse);
    });

    test('the same numbers in the same order are one game', () {
      expect(
        volumeNumbersAgree('そらのは 真3 そらのは3 別伝 Grey Tides',
            'そらのは 真3 / そらのは3別伝 Grey Ties'),
        isTrue,
      );
      expect(volumeNumbersAgree('COMICS WEAVER-MAN 2', "Comics' Weaver-Man 2"),
          isTrue);
    });

    test('order and count are part of the claim', () {
      // Measured on `CONTROL-HIRES`: a `CHRONOS 3 REMADE` spine is offered DLC
      // sets carrying a second number, 0.356 and 0.364. Nothing rides on the
      // score there; this is what says they are not the same item.
      expect(
          volumeNumbersAgree(
              'CHRONOS 3 REMADE', 'Chronos 3 Remade: Nocturne 5 Gold EX BGM Set'),
          isFalse);
      expect(volumeNumbersAgree('Starweave Chronicles 2 3', 'Starweave 3 2'),
          isFalse);
    });

    test('full-width and half-width digits are one volume', () {
      // A first ask reads this spine そらのは０ and a repeat そらのは0
      // (T-0065); the volume is the same either way.
      expect(volumeNumbersAgree('そらのは０ 約束の丘', 'そらのは0 約束の丘'), isTrue);
    });

    test('a title without numbers agrees with a name without numbers', () {
      expect(volumeNumbersAgree('HARBOUR STARBURST', 'Harbour Starburst'),
          isTrue);
    });

    test('roman numerals are left to the score, and it holds them', () {
      // Arabic only (T-0059's i/v/x/l/c/d/m problem). It costs nothing on the
      // control set: `FALCON'S CREED II` auto-matches at 1.000 against IGDB's
      // own roman spelling, and the arabic spelling below belongs to a
      // different candidate that scores 0.531.
      expect(volumeNumbersAgree("FALCON'S CREED II", "Falcon's Creed II"),
          isTrue);
      expect(
          volumeNumbersAgree(
              "FALCON'S CREED II", "Falcon's Creed 2: Deluxe Edition"),
          isFalse);
    });
  });

  group('the wrong sibling', () {
    test('does not auto-match even when IGDB answers the title itself',
        () async {
      // The state T-0100 was filed to survive: one indexing change on IGDB's
      // side takes this row off the retry path, and 0.857 clears
      // [minAutoScore] with the hint naming a single console, so the identity
      // bar is not there to refuse it.
      final resolved = await ResolverWorker(_igdb({'そらのは 真2': _emberOnSwitch}))
          .process(_detection('そらのは 真2', hint: 'SWITCH2'));

      expect(resolved.best, isNull);
      expect(resolved.candidates.first.igdbId, 1100000003);
      expect(resolved.candidates.first.score, closeTo(0.857, 0.001));
      expect(resolved.candidates.first.score, greaterThan(minAutoScore));
    });

    test('is still shown to the human, first, as the nearest thing IGDB holds',
        () async {
      // IGDB holds no Japanese name for True 2 (T-0094), so the sibling is
      // the whole of what the review screen can offer. Refusing it as an
      // auto-match is not a reason to hide it (T-0002).
      final resolved = await ResolverWorker(_igdb({'そらのは': _emberOnSwitch}))
          .process(_detection('そらのは 真2', hint: 'SWITCH2'));

      expect(resolved.candidates.map((c) => c.igdbId), [1100000003, 1100000004]);
      expect(resolved.best, isNull);
    });
  });

  group('what the gate must not touch', () {
    test('the right sibling, whose numbers agree, keeps the ordinary threshold',
        () async {
      // 0.852, below the 0.857 the wrong sibling scores: the pair is why no
      // threshold works. On a full-title hit this auto-matches and the gate is
      // silent, so what refuses it on the retry path is T-0065's identity bar
      // and nothing added here.
      final igdb = _igdb({'そらのは 真3 そらのは3 別伝 grey tides': _emberOnSwitch});
      final resolved = await ResolverWorker(igdb)
          .process(_detection('そらのは 真3 そらのは3 別伝 Grey Tides', hint: 'SWITCH2'));

      expect(resolved.best?.igdbId, 1100000004);
      expect(resolved.best!.score, closeTo(0.852, 0.001));
    });

    test('identity, which implies agreement and cannot be narrowed', () async {
      final resolved = await ResolverWorker(_igdb({'そらのは': _emberOnSwitch}))
          .process(_detection('そらのは 真', hint: 'SWITCH2'));

      expect(resolved.best?.igdbId, 1100000003);
      expect(resolved.best!.score, 1.0);
    });
  });

  test('the same relation in Latin is refused by the score alone', () async {
    // Which is why this has never been visible before: `MOONLIGHT` against
    // `Moonlight 2` is 0.818 -- the identical claim, one volume number apart,
    // and it lands below [minAutoScore] only because the title is 9 characters
    // and そらのは 真 is 6.
    final resolved = await ResolverWorker(_igdb({'moonlight': _moonlight}))
        .process(_detection('MOONLIGHT', hint: 'SWITCH'));

    expect(resolved.candidates.single.score, closeTo(0.818, 0.001));
    expect(resolved.candidates.single.score, lessThan(minAutoScore));
    expect(resolved.best, isNull);
  });
}
