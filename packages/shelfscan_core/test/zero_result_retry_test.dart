/// Guards the zero-result retry (T-0065).
///
/// The そらのは spines and a Solar Pilgrim bundle -- the whole of
/// `CONTROL-HIRES`'s "no candidates at all" bucket -- reached the scorer with
/// nothing to score, because IGDB's `search` answers a long compound title
/// with zero rows while a leading fragment of it finds the game.
///
/// Three things have to hold together:
///   1. the retry fires only where the first query returned nothing;
///   2. it stops at the first shortened form IGDB answers;
///   3. what comes back cannot auto-match on similarity, only on identity.
///
/// The IGDB payloads below are the live responses, recorded 2026-08-15 and cut
/// down to the fields [IgdbClient] reads. The titles are this task's own
/// rows and no more -- the bounded-fixture ceiling `legal_marks_test.dart`
/// set (decision 0004, "no review document is committed").
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

/// `search "そらのは"` under `where platforms = (130,508)`, live.
const _emberOnSwitch = [
  {
    'id': 1100000004,
    'name': 'Path of Ember: True 3 & Grey Ties',
    'alternative_names': [
      {'name': 'Path of Ember: True 3 / Path of Ember 3 Betsuden: Grey Ties'},
      {'name': 'そらのは 真3 / そらのは3別伝 Grey Ties'},
    ],
    'platforms': [
      {'id': 508, 'name': 'Nintendo Switch 2'},
      {'id': 167, 'name': 'PlayStation 5'},
    ],
  },
  {
    'id': 1100000003,
    'name': 'Path of Ember: True',
    // The leading space is IGDB's, not a typo here; the alternative name's
    // id is withheld because it would resolve the substituted title (T-0095).
    'alternative_names': [
      {'name': 'Path of Ember: True'},
      {'name': ' そらのは 真'},
    ],
    'platforms': [
      {'id': 508, 'name': 'Nintendo Switch 2'},
      {'id': 130, 'name': 'Nintendo Switch'},
    ],
  },
];

/// The same query under `where platforms = (8)`, which is the filter the
/// shipped `PS2` hint builds -- a known misread of a console band, and not a
/// platform any of these rows is on (T-0029).
const _emberOnPs2 = [
  {
    'id': 1100000023,
    'name': 'Path of Ember',
    'alternative_names': [
      {'name': 'Path of Ember'},
      {'name': 'そらのは'},
    ],
    'platforms': [
      {'id': 8, 'name': 'PlayStation 2'},
    ],
  },
];

/// `search "solar pilgrim i-vi collection"` under the Switch union, live.
const _solarPilgrimCollection = [
  {
    'id': 1100000057,
    'name': 'Solar Pilgrim: Relic Remaster Collection',
    'alternative_names': [
      {'name': 'Solar Pilgrim I-VI Bundle'},
    ],
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

/// An IGDB stub answering each `search` term from [byTerm], and recording the
/// terms in order. Anything not listed returns zero rows, which is the case
/// this whole file is about.
///
/// The body is sent as bytes under IGDB's own `application/json` with no
/// charset, because that is what decides whether a Japanese alternative name
/// survives the trip: `http.Response(String, ...)` encodes latin1 and throws
/// on そ.
({IgdbClient client, List<String> searched}) _spyIgdb(
    Map<String, List<Map<String, Object?>>> byTerm) {
  final searched = <String>[];
  final transport = MockClient((request) async {
    if (request.url.host == 'id.twitch.tv') {
      return http.Response(
          jsonEncode({'access_token': 'stub-token', 'expires_in': 3600}), 200);
    }
    // T-0094's field filter sends a body with no `search` term. It sits
    // between the first query and the ladder, so it has to answer something
    // here; zero rows is what it answers live for every title in this file,
    // and leaving it out of [searched] keeps the counts below about the
    // ladder.
    final match = RegExp(r'search "([^"]*)"').firstMatch(request.body);
    if (match == null) {
      return http.Response.bytes(utf8.encode('[]'), 200,
          headers: {'content-type': 'application/json'});
    }
    final term = match.group(1)!;
    searched.add(term);
    return http.Response.bytes(
      utf8.encode(jsonEncode(byTerm[term] ?? const [])),
      200,
      headers: {'content-type': 'application/json'},
    );
  });
  return (
    client:
        IgdbClient(clientId: 'stub', clientSecret: 'stub', client: transport),
    searched: searched,
  );
}

void main() {
  group('shortenedQueries', () {
    test('halves the token count each time, longest form first', () {
      expect(
        shortenedQueries('そらのは 真3 そらのは3 別伝 grey tides'),
        ['そらのは 真3 そらのは', 'そらのは 真', 'そらのは'],
      );
    });

    test('starts a token at a digit, with or without a space before it', () {
      // The same shelf, two spellings: a repeat ask reads 真2, the first-ask
      // read in this task's filing was そらのは0. Split on whitespace alone,
      // that one has nothing shorter to try, and `そらのは0` returns 0 rows
      // live.
      expect(shortenedQueries('そらのは 真2'), ['そらのは']);
      expect(shortenedQueries('そらのは0 約束の丘'), ['そらのは']);
    });

    test('is not Japanese-only: the Latin bundle shortens the same way', () {
      expect(
        shortenedQueries('solar pilgrim i-vi collection edition anniversaire '
            '/ anniversary edition'),
        ['solar pilgrim i-vi collection', 'solar pilgrim', 'solar'],
      );
    });

    test('cuts the prefix out of the query, keeping its own punctuation', () {
      expect(
        shortenedQueries('solar pilgrim vii & solar pilgrim viii remastered '
            '- twin pack').first,
        'solar pilgrim vii & solar',
      );
    });

    test('has nothing to offer a one-token query', () {
      expect(shortenedQueries('そらのは'), isEmpty);
      expect(shortenedQueries(''), isEmpty);
    });
  });

  group('when the first query hits', () {
    test('no second request is made', () async {
      final igdb = _spyIgdb({'そらのは': _emberOnPs2});
      final resolved = await ResolverWorker(igdb.client)
          .process(_detection('そらのは', hint: 'PS2'));

      expect(igdb.searched, ['そらのは']);
      expect(resolved.candidates, hasLength(1));
    });

    test('a hit below the auto-match threshold still makes no second request',
        () async {
      final igdb = _spyIgdb({'そらのは 真': _emberOnPs2});
      await ResolverWorker(igdb.client)
          .process(_detection('そらのは 真', hint: 'PS2'));

      expect(igdb.searched, ['そらのは 真'],
          reason: 'zero rows is the trigger, not a weak match');
    });
  });

  group('when the first query returns nothing', () {
    test('the retry stops at the first shortened form IGDB answers', () async {
      final igdb = _spyIgdb({'そらのは': _emberOnPs2});
      final resolved = await ResolverWorker(igdb.client)
          .process(_detection('そらのは 真3 そらのは3 別伝 Grey Tides', hint: 'PS2'));

      expect(igdb.searched, [
        'そらのは 真3 そらのは3 別伝 grey tides',
        'そらのは 真3 そらのは',
        'そらのは 真',
        'そらのは',
      ]);
      expect(resolved.candidates.single.title, 'Path of Ember');
    });

    test('a row IGDB cannot find at any length costs the ladder and no more',
        () async {
      final igdb = _spyIgdb(const {});
      final resolved = await ResolverWorker(igdb.client)
          .process(_detection('そらのは 真2', hint: 'PS2'));

      expect(igdb.searched, ['そらのは 真2', 'そらのは']);
      expect(resolved.candidates, isEmpty);
      expect(resolved.best, isNull);
    });

    test('the Latin bundle finds its game too', () async {
      final igdb =
          _spyIgdb({'solar pilgrim i-vi collection': _solarPilgrimCollection});
      final resolved = await ResolverWorker(igdb.client).process(_detection(
          'SOLAR PILGRIM I-VI COLLECTION EDITION ANNIVERSAIRE / '
          'ANNIVERSARY EDITION',
          hint: 'SWITCH'));

      expect(igdb.searched, hasLength(2));
      expect(resolved.candidates.single.title,
          'Solar Pilgrim: Relic Remaster Collection');
      expect(resolved.best, isNull, reason: 'scores 0.375 against the spine');
    });
  });

  group('what a shortened query is allowed to auto-match', () {
    /// Hints hand-written to the band, as T-0023 measured them: the shipped
    /// `PS2` read makes every one of these a platform mismatch, which would
    /// hide the score rule behind the platform rule.
    Future<ResolvedGame> resolveOnSwitch(String title) =>
        ResolverWorker(_spyIgdb({'そらのは': _emberOnSwitch}).client)
            .process(_detection(title, hint: 'SWITCH'));

    test('not the wrong sibling, which lands one character away', () async {
      // 0.714 until T-0095 trimmed the candidate: the sibling was scored
      // against IGDB's ` そらのは 真` and paid for the leading space as well as
      // for the volume number. At 0.857 it clears `minAutoScore`, so the
      // identity gate is now the only thing refusing it.
      final resolved = await resolveOnSwitch('そらのは 真2');

      expect(resolved.best, isNull);
      expect(resolved.candidates.first.title, 'Path of Ember: True',
          reason: 'the spine is True 2, so this is the sibling');
      expect(resolved.candidates.first.score, closeTo(0.857, 0.001));
      expect(resolved.candidates.first.score, greaterThan(minAutoScore));
    });

    test('an exact Japanese name IGDB stores with a leading space', () async {
      // T-0095. The spine *is* the alternative name of game 1100000003; the
      // space is IGDB's. It scored 0.857 -- one character of seven -- so the
      // identity gate refused the row it exists to admit.
      final resolved = await resolveOnSwitch('そらのは 真');

      expect(resolved.candidates.first.igdbId, 1100000003);
      expect(resolved.candidates.first.score, 1.0);
      expect(resolved.candidates.first.matchedAlternativeName, ' そらのは 真',
          reason: 'the stored name is reported as stored, not as compared');
      expect(resolved.best, isNull,
          reason: 'IGDB lists 1100000003 on both Switch consoles and a family hint '
              'ties them, so identity gets the row past T-0065 and T-0002 '
              'still refuses it');
    });

    test('and auto-matches once the hint names one console', () async {
      final resolved =
          await ResolverWorker(_spyIgdb({'そらのは': _emberOnSwitch}).client)
              .process(_detection('そらのは 真', hint: 'SWITCH2'));

      expect(resolved.best?.igdbId, 1100000003);
      expect(resolved.best!.score, 1.0);
    });

    test('and not the right game either, when similarity is all it has',
        () async {
      // The price of the identity bar, stated: 0.852 is over `minAutoScore`
      // and it is the right game. It is also below the 0.857 the wrong sibling
      // above scores, so no threshold on this metric separates the two.
      final resolved =
          await resolveOnSwitch('そらのは 真3 そらのは3 別伝 Grey Tides');

      expect(resolved.candidates.first.title, 'Path of Ember: True 3 & Grey Ties');
      expect(resolved.candidates.first.score, closeTo(0.852, 0.001));
      expect(resolved.best, isNull);
    });

    test('a full-title query keeps the ordinary threshold', () async {
      // The gate is on the retry, not on the score: the same 0.852 shape
      // auto-matches when IGDB answered the title itself.
      final igdb =
          _spyIgdb({'そらのは 真3 そらのは3 別伝 grey tides': _emberOnSwitch});
      final resolved = await ResolverWorker(igdb.client)
          .process(_detection('そらのは 真3 そらのは3 別伝 Grey Tides', hint: 'SWITCH'));

      expect(igdb.searched, hasLength(1));
      expect(resolved.best?.title, 'Path of Ember: True 3 & Grey Ties');
      expect(resolved.best!.score, closeTo(0.852, 0.001));
    });

    test('an exact name, which is the door the bar leaves open', () async {
      // The shape that opens it is measured: IGDB holds
      // `そらのは０ 約束の丘 Director's Cut` as an alternative name of Path of Ember 0:
      // Director's Cut, and `search` returns zero rows for that string, for
      // its half-width spelling and for `そらのは０`. A name the catalogue has
      // and its own index will not hand back is exactly what a shortened
      // query is for -- and identity with it is a different claim from
      // resembling it.
      const emberZero = [
        {
          'id': 1100000020,
          'name': "Path of Ember 0: Director's Cut",
          'alternative_names': [
            {'name': "そらのは０ 約束の丘 Director's Cut"},
          ],
          'platforms': [
            {'id': 508, 'name': 'Nintendo Switch 2'},
          ],
        },
      ];
      final igdb = _spyIgdb({'そらのは０': emberZero});
      final resolved = await ResolverWorker(igdb.client).process(
          _detection("そらのは０ 約束の丘 Director's Cut", hint: 'SWITCH'));

      expect(igdb.searched, hasLength(3));
      expect(resolved.best?.igdbId, 1100000020);
      expect(resolved.best!.score, 1.0);
    });
  });
}
