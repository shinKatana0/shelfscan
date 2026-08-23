/// Guards the `alternative_names.name` field filter (T-0094).
///
/// IGDB holds `そらのは０ 約束の丘 Director's Cut` as alternative name 1100000021 of
/// game 1100000020, and `search` returns **0 rows** for that exact stored string --
/// the probe is recorded on [IgdbClient.search]. A `where ... ~ *"..."*` on the
/// field is a different mechanism and returns the game.
///
/// What has to hold together:
///   1. the filter fires only where `search` returned nothing at all;
///   2. its substring answer is used only when one row *is* the spine, so a
///      loose match costs the row nothing and it walks the ladder;
///   3. what it does return faces identity, not similarity, before `best`.
///
/// The payloads are the live responses of 2026-08-15, cut to the fields
/// [IgdbClient] reads, and the titles are this task's own rows and no more
/// (decision 0004, "no review document is committed").
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

/// The spelling that carries the printed 0, as T-0065 recorded this spine.
const _spine = "そらのは０ 約束の丘 DIRECTOR'S CUT";
const _needle = "そらのは０ 約束の丘 director's cut";

/// The spelling `CONTROL-HIRES` produces today -- three runs on 2026-08-15,
/// 1 first ask and 2 repeats, none of them carrying the 0 the case prints.
const _partialSpine = "そらのは 約束の丘 DIRECTOR'S CUT";
const _partialNeedle = "そらのは 約束の丘 director's cut";

/// Game 1100000020 as the field filter returns it, live.
const _emberZeroDirectorsCut = [
  {
    'id': 1100000020,
    'name': "Path of Ember 0: Director's Cut",
    'alternative_names': [
      {'name': '星之碎片０約定之地 導演剪輯版'},
      {'name': "そらのは０ 約束の丘 Director's Cut"},
      {'name': "Path of Ember 0: The Hill of Promise Director's Cut"},
    ],
    'platforms': [
      {'id': 508, 'name': 'Nintendo Switch 2'},
      {'id': 167, 'name': 'PlayStation 5'},
    ],
  },
];

/// What `search "そらのは"` answers under the shipped `PS2` hint -- the ladder's
/// whole yield for these spines (T-0029: every one of the cases is Switch 2).
const _emberOnPs2 = [
  {
    'id': 1100000023,
    'name': 'Path of Ember',
    'alternative_names': [
      {'name': 'そらのは'},
    ],
    'platforms': [
      {'id': 8, 'name': 'PlayStation 2'},
    ],
  },
];

/// A substring sweep: `~ *"そらのは"*` returns 12 games live, none of them this
/// spine. Three are enough to show what the caller does with them.
const _sweep = [
  {
    'id': 1100000023,
    'name': 'Path of Ember',
    'alternative_names': [
      {'name': 'そらのは'},
    ],
    'platforms': [
      {'id': 508, 'name': 'Nintendo Switch 2'},
    ],
  },
  {
    'id': 1100000024,
    'name': 'Path of Ember 1&2 HD Edition',
    'alternative_names': [
      {'name': 'そらのは1&2 HD EDITION'},
    ],
    'platforms': [
      {'id': 508, 'name': 'Nintendo Switch 2'},
    ],
  },
  {
    'id': 1100000025,
    'name': 'City of Wars Powered by Path of Ember',
    'alternative_names': [
      {'name': 'City of Wars Powered by そらのは'},
    ],
    'platforms': [
      {'id': 508, 'name': 'Nintendo Switch 2'},
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

/// Answers `search` terms from [searches] and field-filter needles from
/// [byAlternativeName], recording every request in order. Anything not listed
/// returns zero rows.
///
/// Bytes rather than `http.Response(String, ...)`, which encodes latin1 and
/// throws on そ.
({IgdbClient client, List<String> asked}) _spyIgdb({
  Map<String, List<Map<String, Object?>>> searches = const {},
  Map<String, List<Map<String, Object?>>> byAlternativeName = const {},
}) {
  final asked = <String>[];
  final transport = MockClient((request) async {
    if (request.url.host == 'id.twitch.tv') {
      return http.Response(
          jsonEncode({'access_token': 'stub-token', 'expires_in': 3600}), 200);
    }
    final term = RegExp(r'search "([^"]*)"').firstMatch(request.body);
    final pattern = RegExp(r'alternative_names\.name ~ \*"([^"]*)"\*')
        .firstMatch(request.body);
    final List<Map<String, Object?>> rows;
    if (term != null) {
      asked.add('search ${term.group(1)}');
      rows = searches[term.group(1)] ?? const [];
    } else {
      asked.add('alt ${pattern!.group(1)}');
      rows = byAlternativeName[pattern.group(1)] ?? const [];
    }
    return http.Response.bytes(
      utf8.encode(jsonEncode(rows)),
      200,
      headers: {'content-type': 'application/json'},
    );
  });
  return (
    client:
        IgdbClient(clientId: 'stub', clientSecret: 'stub', client: transport),
    asked: asked,
  );
}

/// Captures the one body [IgdbClient] sends, for the query-shape assertions.
Future<String?> _bodyOf(
    Future<void> Function(IgdbClient client) ask) async {
  String? body;
  final transport = MockClient((request) async {
    if (request.url.host == 'id.twitch.tv') {
      return http.Response(
          jsonEncode({'access_token': 't', 'expires_in': 3600}), 200);
    }
    body = request.body;
    return http.Response('[]', 200);
  });
  await ask(IgdbClient(clientId: 'a', clientSecret: 'b', client: transport));
  return body;
}

void main() {
  group('the query IGDB is sent', () {
    test('filters on the field and on the platform in one where', () async {
      final body = await _bodyOf((client) =>
          client.searchAlternativeNames('そらのは 真', platformHint: 'SWITCH'));

      expect(
          body,
          contains('where alternative_names.name ~ *"そらのは 真"* & '
              'platforms = (130,508);'));
      expect(body, isNot(contains('search ')));
    });

    test('strips the pattern syntax a spine read could carry', () async {
      final body =
          await _bodyOf((client) => client.searchAlternativeNames('a "b" *c*'));

      expect(body, contains('~ *"a b c"*'));
    });

    test('a read that is nothing but pattern syntax asks nothing at all',
        () async {
      final igdb = _spyIgdb();

      expect(await igdb.client.searchAlternativeNames('**'), isEmpty);
      expect(igdb.asked, isEmpty,
          reason: 'an empty needle matches every game IGDB has');
    });
  });

  group('when search finds the title', () {
    test('the field filter is never asked', () async {
      final igdb = _spyIgdb(searches: {_needle: _emberZeroDirectorsCut});
      final resolved = await ResolverWorker(igdb.client)
          .process(_detection(_spine, hint: 'SWITCH2'));

      expect(igdb.asked, ['search $_needle']);
      expect(resolved.best?.externalId, 'igdb:1100000020');
    });
  });

  group('when search finds nothing and the filter finds the spine', () {
    test('it answers before the ladder is walked', () async {
      final igdb = _spyIgdb(
        searches: {'そらのは': _emberOnPs2},
        byAlternativeName: {_needle: _emberZeroDirectorsCut},
      );
      final resolved = await ResolverWorker(igdb.client)
          .process(_detection(_spine, hint: 'SWITCH2'));

      expect(igdb.asked, ['search $_needle', 'alt $_needle'],
          reason: 'one extra request, and no rung of the ladder');
      expect(resolved.best?.externalId, 'igdb:1100000020');
      expect(resolved.best!.score, 1.0);
      expect(resolved.best!.matchedAlternativeName,
          "そらのは０ 約束の丘 Director's Cut");
    });

    test('the shipped PS2 hint refuses it, and that is T-0029', () async {
      // The filter carries the platform clause, so under `PS2` IGDB has
      // nothing to return for a Switch 2 / PS5 game and the row falls through
      // to the ladder exactly as it does today.
      final igdb = _spyIgdb(searches: {'そらのは': _emberOnPs2});
      final resolved = await ResolverWorker(igdb.client)
          .process(_detection(_partialSpine, hint: 'PS2'));

      expect(igdb.asked, [
        'search $_partialNeedle',
        'alt $_partialNeedle',
        'search そらのは 約束の丘',
        'search そらのは',
      ]);
      expect(resolved.candidates.single.title, 'Path of Ember');
      expect(resolved.best, isNull);
    });
  });

  group('when the filter finds something that is not the spine', () {
    test('a near miss is thrown away as readily as a sweep', () async {
      // The read this shelf produces today drops the printed 0, so it is 0.955
      // against the stored name rather than 1.000. Handed the right game
      // anyway, the rule discards it and the row walks the ladder: the
      // filter's whole entitlement is identity.
      //
      // Live the needle does not get that far, because `~` folds case and not
      // width -- see [IgdbClient.searchAlternativeNames].
      final igdb = _spyIgdb(
        searches: {'そらのは': _emberOnPs2},
        byAlternativeName: {_partialNeedle: _emberZeroDirectorsCut},
      );
      final resolved = await ResolverWorker(igdb.client)
          .process(_detection(_partialSpine, hint: 'SWITCH2'));

      expect(igdb.asked, hasLength(4));
      expect(resolved.candidates, isEmpty);
      expect(resolved.best, isNull);
    });

    test('a sweep contributes nothing and the ladder runs', () async {
      final igdb = _spyIgdb(
        searches: {'そらのは': _emberOnPs2},
        byAlternativeName: {_partialNeedle: _sweep},
      );
      final resolved = await ResolverWorker(igdb.client)
          .process(_detection(_partialSpine, hint: 'PS2'));

      expect(igdb.asked, hasLength(4));
      expect(resolved.candidates.single.title, 'Path of Ember',
          reason: 'the three swept rows contribute nothing, right or wrong');
      expect(resolved.best, isNull);
    });

    test('a title IGDB holds no Japanese name for costs one request more '
        'than the ladder alone', () async {
      // True 2 is the other half of the filing and no query shape reaches
      // it: of the 12 games carrying a Japanese `そらのは` alternative name,
      // this is not one -- IGDB has only Chinese ones for it.
      final igdb = _spyIgdb();
      final resolved = await ResolverWorker(igdb.client)
          .process(_detection('そらのは 真2', hint: 'PS2'));

      expect(
          igdb.asked, ['search そらのは 真2', 'alt そらのは 真2', 'search そらのは']);
      expect(resolved.candidates, isEmpty);
    });
  });
}
