/// The TMDB client, the catalogue routing seam, and what a film exports as
/// (T-0162, decision 0015).
///
/// **Nothing here runs against the live TMDB service**, and no credential for
/// it exists on the machine these were written on. What they verify is the
/// request this build sends, the parsing of a response of TMDB's published
/// shape, and every decision made on top of that. The claim they do NOT make
/// is that TMDB answers this shape -- that is read off its API documentation
/// and needs a key to confirm. `doc/reports/T-0162.md` says so in full.
///
/// **One thing here IS measured, and it is the one these tests cannot show**
/// (T-0336): five live searches on 2026-08-23 established that TMDB's `year`
/// is a filter rather than a preference. A fake answers whatever it is told
/// to, so no test below can distinguish the two -- which is exactly how the
/// false claim in `tmdb.dart` survived. What the fakes pin is the behaviour
/// the measurement justifies: the retry without the year, and what a hit
/// arriving through it is allowed to be worth.
///
/// **Every title here is invented** (`doc/conventions.md` §3b), including the
/// TMDB ids, which are small integers chosen to be obviously synthetic.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

const _token = 'test-read-access-token';

/// A TMDB search response of the documented shape.
String _body(List<Map<String, Object?>> results) => jsonEncode({
      'page': 1,
      'results': results,
      'total_pages': 1,
      'total_results': results.length,
    });

Map<String, Object?> _film(int id, String title,
        {String? original, String? released}) =>
    {
      'id': id,
      'title': title,
      if (original != null) 'original_title': original,
      'release_date': released ?? '',
      'overview': 'synthetic fixture',
    };

/// The client, plus the requests it made.
({TmdbClient client, List<http.Request> sent}) _client(
    Future<http.Response> Function(http.Request) answer) {
  final sent = <http.Request>[];
  final transport = MockClient((request) async {
    sent.add(request);
    return answer(request);
  });
  return (
    client: TmdbClient(token: _token, client: transport),
    sent: sent
  );
}

Detection _filmRow(String title, {int? year}) => Detection.fromSource(
      rawTitle: title,
      origin: DetectionOrigin.filename,
      sourceEntry: '$title.mkv',
      workKind: WorkKind.movie,
      sourceYear: year,
    );

/// A minimal document. The four required fields are the document's own
/// contract and none of them is what any test here is about.
ReviewDocument _doc(List<ResolvedGame> games) => ReviewDocument(
      version: 1,
      created: '2026-01-01T00:00:00Z',
      photos: const [],
      games: games,
    );

void main() {
  group('the request this build sends', () {
    test('a search goes to the documented endpoint with the title', () async {
      final t = _client((_) async => http.Response(_body([]), 200));
      await t.client.searchMovie('Pale Anchor');

      final uri = t.sent.single.url;
      expect(uri.host, 'api.themoviedb.org');
      expect(uri.path, '/3/search/movie');
      expect(uri.queryParameters['query'], 'Pale Anchor');
      expect(uri.queryParameters['include_adult'], 'false');
    });

    test('a year filters the search when the filename carried one', () async {
      // "filters", not "narrows": measured live 2026-08-23 (T-0336). This
      // request is all the test can see; what the service does with the
      // parameter is why `TmdbResolverWorker` retries without it.
      final t = _client((_) async => http.Response(_body([]), 200));
      await t.client.searchMovie('Pale Anchor', year: 1987);
      expect(t.sent.single.url.queryParameters['year'], '1987');
    });

    test('and is absent, not empty, when it did not', () async {
      final t = _client((_) async => http.Response(_body([]), 200));
      await t.client.searchMovie('Pale Anchor');
      expect(t.sent.single.url.queryParameters.containsKey('year'), isFalse);
    });

    test('the credential travels in a header and never in the URL', () async {
      // The reason the client takes a read access token rather than the v3
      // api_key: a URL is the one thing an error or a log quotes by reflex.
      final t = _client((_) async => http.Response(_body([]), 200));
      await t.client.searchMovie('Pale Anchor');

      final request = t.sent.single;
      expect(request.headers['Authorization'], 'Bearer $_token');
      expect(request.url.toString(), isNot(contains(_token)));
      expect(request.url.query, isNot(contains('api_key')));
    });

    test('an empty title asks nothing at all', () async {
      final t = _client((_) async => http.Response(_body([]), 200));
      expect(await t.client.searchMovie('   '), isEmpty);
      expect(t.sent, isEmpty);
    });
  });

  group('the response this build reads', () {
    test('a result becomes a hit, with the year off release_date', () async {
      final t = _client((_) async => http.Response(
          _body([_film(11, 'Pale Anchor', released: '1987-04-02')]), 200));

      final hit = (await t.client.searchMovie('Pale Anchor')).single;
      expect(hit.tmdbId, 11);
      expect(hit.title, 'Pale Anchor');
      expect(hit.releaseYear, 1987);
      expect(hit.originalTitle, isNull);
    });

    test('an empty release_date is a null year, not a zero', () async {
      final t = _client((_) async =>
          http.Response(_body([_film(11, 'Pale Anchor', released: '')]), 200));
      expect((await t.client.searchMovie('Pale Anchor')).single.releaseYear,
          isNull);
    });

    test('an original title is kept only when it differs', () async {
      final t = _client((_) async => http.Response(
          _body([
            _film(11, 'Pale Anchor', original: 'Ankra Palo'),
            _film(12, 'Tidewrack', original: 'Tidewrack'),
          ]),
          200));

      final hits = await t.client.searchMovie('x');
      expect(hits[0].originalTitle, 'Ankra Palo');
      expect(hits[1].originalTitle, isNull);
    });

    test('one malformed result is skipped, not fatal to the search', () async {
      // A bad row degrades to no row; the run's own rule.
      final t = _client((_) async => http.Response(
          _body([
            {'id': 'not-an-int', 'title': 'Broken'},
            _film(11, 'Pale Anchor'),
          ]),
          200));

      final hits = await t.client.searchMovie('x');
      expect(hits.map((h) => h.tmdbId), [11]);
    });
  });

  group('what a failure says, and what it refuses to say', () {
    test('a 429 is retryable, because a rate limit passes', () async {
      final t = _client((_) async => http.Response('{}', 429));
      expect(t.client.searchMovie('x'),
          throwsA(isA<RetryableTmdbException>()));
    });

    test('a 401 names the variable and the token it wants', () async {
      final t = _client((_) async => http.Response('{}', 401));
      await expectLater(
          t.client.searchMovie('x'),
          throwsA(isA<TmdbApiException>().having((e) => e.message, 'message',
              allOf(contains(tmdbTokenVariable), contains('Read Access')))));
    });

    test('no failure message quotes the token or the body', () async {
      // `igdb.dart`'s rule carried over: this is a BYOK path, the likeliest
      // failure on it is a bad credential, and a service's error text is not
      // a place to find out what it decided to include.
      for (final status in [400, 401, 403, 404, 429, 500, 503]) {
        final t = _client(
            (_) async => http.Response('{"secret":"$_token"}', status));
        try {
          await t.client.searchMovie('Pale Anchor');
          fail('$status should have thrown');
        } on Exception catch (e) {
          expect('$e', isNot(contains(_token)), reason: '$status');
          expect('$e', isNot(contains('secret')), reason: '$status');
        }
      }
    });

    test('a host that never answers is an UnreachableEndpoint', () async {
      final t = _client((_) async => throw http.ClientException('no route'));
      await expectLater(
          t.client.searchMovie('x'),
          throwsA(isA<TmdbUnreachableException>()
              .having((e) => e.endpointIsUserSet, 'endpointIsUserSet', isFalse)));
    });
  });

  group('the film resolver', () {
    TmdbResolverWorker worker(List<Map<String, Object?>> results) =>
        TmdbResolverWorker(TmdbClient(
          token: _token,
          client: MockClient((_) async => http.Response(_body(results), 200)),
        ));

    test('an exact title auto-matches', () async {
      final resolved = await worker([
        _film(11, 'Pale Anchor', released: '1987-04-02'),
      ]).process(_filmRow('Pale Anchor', year: 1987));

      expect(resolved.best, isNotNull);
      expect(resolved.best!.externalId, 'tmdb:11');
      expect(resolved.best!.score, 1.0);
    });

    test('nothing found is an unmatched row, not a failure', () async {
      final resolved =
          await worker([]).process(_filmRow('Pale Anchor', year: 1987));
      expect(resolved.best, isNull);
      expect(resolved.candidates, isEmpty);
    });

    test('a weak match stays a candidate for the human', () async {
      final resolved = await worker([
        _film(11, 'Something Else Entirely', released: '1987-04-02'),
      ]).process(_filmRow('Pale Anchor', year: 1987));

      expect(resolved.best, isNull);
      expect(resolved.candidates, hasLength(1));
    });

    test('a tie the year cannot settle is refused', () async {
      // A remake shares its title with its original exactly. With no year on
      // the detection there is nothing to separate them, so neither wins.
      final resolved = await worker([
        _film(11, 'Pale Anchor', released: '1987-04-02'),
        _film(12, 'Pale Anchor', released: '2013-10-01'),
      ]).process(_filmRow('Pale Anchor'));

      expect(resolved.best, isNull);
      expect(resolved.candidates, hasLength(2));
    });

    test('a tie the year DOES settle is taken', () async {
      final resolved = await worker([
        _film(11, 'Pale Anchor', released: '1987-04-02'),
        _film(12, 'Pale Anchor', released: '2013-10-01'),
      ]).process(_filmRow('Pale Anchor', year: 2013));

      expect(resolved.best!.externalId, 'tmdb:12');
      expect(resolved.best!.releaseYear, 2013);
    });

    test('the original-language title can be what matched, and is shown',
        () async {
      final resolved = await worker([
        _film(11, 'The Pale Anchor', original: 'Ankra Palo', released: '1987-01-01'),
      ]).process(_filmRow('Ankra Palo', year: 1987));

      expect(resolved.best, isNotNull);
      expect(resolved.candidates.single.matchedAlternativeName, 'Ankra Palo');
    });

    test('a film candidate carries no platform', () async {
      final resolved = await worker([
        _film(11, 'Pale Anchor', released: '1987-04-02'),
      ]).process(_filmRow('Pale Anchor', year: 1987));

      expect(resolved.best!.platformName, isNull);
      expect(resolved.best!.platformId, isNull);
    });
  });

  /// The zero-result retry (T-0336), and what a hit reached through it is
  /// allowed to be worth.
  ///
  /// The measurement behind it is live and is not reproducible here: TMDB's
  /// `year` removes a film whose catalogued year is not the one asked for,
  /// rather than demoting it. What these fakes pin is everything downstream of
  /// that -- when the second request is made, that it changes nothing but the
  /// year, and which of its answers may become `best`.
  group('the yearless retry', () {
    /// A TMDB stub answering by the `year` the request carried, recording
    /// every URL. The `null` key is the yearless form; anything unlisted
    /// answers zero rows, which is the case this whole group is about.
    ({TmdbResolverWorker worker, List<Uri> asked}) spy(
        Map<int?, List<Map<String, Object?>>> byYear) {
      final asked = <Uri>[];
      final transport = MockClient((request) async {
        asked.add(request.url);
        final year = int.tryParse(request.url.queryParameters['year'] ?? '');
        return http.Response(_body(byYear[year] ?? const []), 200);
      });
      return (
        worker:
            TmdbResolverWorker(TmdbClient(token: _token, client: transport)),
        asked: asked,
      );
    }

    test('the narrow case still narrows: one request, and the year is in it',
        () async {
      final t = spy({
        1987: [_film(11, 'Pale Anchor', released: '1987-04-02')],
      });
      final resolved =
          await t.worker.process(_filmRow('Pale Anchor', year: 1987));

      expect(t.asked, hasLength(1), reason: 'the first query found the film');
      expect(t.asked.single.queryParameters['year'], '1987');
      expect(resolved.best!.externalId, 'tmdb:11');
      expect(resolved.best!.matchMethod, MatchMethod.fuzzy);
    });

    test('nothing found with a year is asked again without it', () async {
      final t = spy({
        null: [_film(11, 'Pale Anchor', released: '1979-05-25')],
      });
      final resolved =
          await t.worker.process(_filmRow('Pale Anchor', year: 1978));

      expect(t.asked, hasLength(2));
      expect(t.asked.first.queryParameters['year'], '1978');
      expect(t.asked.last.queryParameters.containsKey('year'), isFalse);
      // The one respect in which this is NOT IGDB's ladder: the title is not
      // shortened, cut or rewritten. Only the year goes.
      expect(t.asked.last.queryParameters['query'], 'Pale Anchor');
      expect(resolved.candidates, hasLength(1),
          reason: 'this row was an empty candidate list before the retry');
    });

    test('a row that carried no year has nothing to drop and asks once',
        () async {
      final t = spy(const {});
      final resolved = await t.worker.process(_filmRow('Pale Anchor'));

      expect(t.asked, hasLength(1));
      expect(resolved.candidates, isEmpty);
      expect(resolved.best, isNull);
    });

    test('a retry that finds nothing either costs the one extra request',
        () async {
      final t = spy(const {});
      final resolved =
          await t.worker.process(_filmRow('Pale Anchor', year: 1978));

      expect(t.asked, hasLength(2));
      expect(resolved.candidates, isEmpty);
      expect(resolved.best, isNull);
    });

    test('a single top scorer from the retry still auto-matches', () async {
      // The case the retry exists for: one film, one title, a filename year
      // one off the catalogued one. Refusing this would leave the row barely
      // better off than the silence the retry replaced.
      final t = spy({
        null: [
          _film(11, 'Pale Anchor', released: '1979-05-25'),
          _film(12, 'Pale Anchor Rising', released: '1990-01-01'),
        ],
      });
      final resolved =
          await t.worker.process(_filmRow('Pale Anchor', year: 1978));

      expect(resolved.best!.externalId, 'tmdb:11');
      expect(resolved.best!.score, 1.0);
      expect(resolved.best!.matchMethod, MatchMethod.yearlessRetry);
    });

    test('and every candidate carries the mark, not only the pick', () async {
      final t = spy({
        null: [
          _film(11, 'Pale Anchor', released: '1979-05-25'),
          _film(12, 'Pale Anchor Rising', released: '1990-01-01'),
        ],
      });
      final resolved =
          await t.worker.process(_filmRow('Pale Anchor', year: 1978));

      expect(resolved.candidates.map((c) => c.matchMethod),
          everyElement(MatchMethod.yearlessRetry));
    });

    test('a tie the year would have settled is refused once the year is gone',
        () async {
      // The trap this gate exists for. Three films share one title exactly,
      // so all three score 1.000 and the year is the only thing that could
      // separate them -- and the year is precisely what was just spent. One
      // of the three even carries the detection's year, which is what makes
      // this bite: without the withdrawal it would auto-match on a year TMDB
      // has already answered that no film of this title has.
      final t = spy({
        null: [
          _film(11, 'Pale Anchor', released: '1987-04-02'),
          _film(12, 'Pale Anchor', released: '2013-10-01'),
          _film(13, 'Pale Anchor', released: '1961-08-19'),
        ],
      });
      final resolved =
          await t.worker.process(_filmRow('Pale Anchor', year: 1987));

      expect(t.asked, hasLength(2));
      expect(resolved.best, isNull);
      expect(resolved.candidates, hasLength(3));
      expect(resolved.candidates.map((c) => c.matchMethod),
          everyElement(MatchMethod.yearlessRetry));
    });

    test('the same tie IS settled when the first query answered it', () async {
      // The control in the other direction: the gate is on the retry, not on
      // the shape of the answer. Identical rows, one request, year honoured.
      final t = spy({
        1987: [
          _film(11, 'Pale Anchor', released: '1987-04-02'),
          _film(12, 'Pale Anchor', released: '2013-10-01'),
          _film(13, 'Pale Anchor', released: '1961-08-19'),
        ],
      });
      final resolved =
          await t.worker.process(_filmRow('Pale Anchor', year: 1987));

      expect(t.asked, hasLength(1));
      expect(resolved.best!.externalId, 'tmdb:11');
      expect(resolved.best!.matchMethod, MatchMethod.fuzzy);
    });

    test('a weak retry hit is a candidate for the human, as it always was',
        () async {
      final t = spy({
        null: [_film(11, 'Something Else Entirely', released: '1979-01-01')],
      });
      final resolved =
          await t.worker.process(_filmRow('Pale Anchor', year: 1978));

      expect(resolved.best, isNull);
      expect(resolved.candidates.single.matchMethod,
          MatchMethod.yearlessRetry);
    });

    test('the score is untouched: both queries send the same title', () async {
      final film = [_film(11, 'Pale Anchor', released: '1979-05-25')];
      final viaRetry = await spy({null: film})
          .worker
          .process(_filmRow('Pale Anchor', year: 1978));
      final direct = await spy({1979: film})
          .worker
          .process(_filmRow('Pale Anchor', year: 1979));

      expect(viaRetry.candidates.single.score,
          direct.candidates.single.score,
          reason: 'the score measures two strings and the strings are equal; '
              'what differs is the evidence, and MatchMethod carries that');
    });
  });

  group('the routing seam', () {
    test('a row goes to the catalogue for ITS kind', () async {
      final router = CatalogueRouter(
        catalogues: {
          WorkKind.game: _Recording('igdb'),
          WorkKind.movie: _Recording('tmdb'),
        },
        fallback: _Recording('fallback'),
      );

      final game = await router.process(Detection.fromSource(
          rawTitle: 'Harbour Lantern',
          origin: DetectionOrigin.filename,
          sourceEntry: 'a.exe'));
      final film = await router.process(_filmRow('Pale Anchor'));

      expect(game.best!.title, 'igdb');
      expect(film.best!.title, 'tmdb');
    });

    test('two kinds in ONE run route apart, which a mode cannot do', () async {
      final router = CatalogueRouter(
        catalogues: {
          WorkKind.game: _Recording('igdb'),
          WorkKind.movie: _Recording('tmdb'),
        },
        fallback: _Recording('fallback'),
      );

      final rows = [
        Detection.fromSource(
            rawTitle: 'Harbour Lantern',
            origin: DetectionOrigin.filename,
            sourceEntry: 'a.exe'),
        _filmRow('Pale Anchor'),
      ];
      final answers = [for (final r in rows) (await router.process(r)).best!.title];

      expect(answers, ['igdb', 'tmdb']);
    });

    test('a THIRD catalogue is added without editing the router', () async {
      // The acceptance criterion, as an assertion. Anime is registered the
      // same way the other two are -- a map entry built by the shell -- and
      // no line of `CatalogueRouter` knows the kind exists.
      final router = CatalogueRouter(
        catalogues: {
          WorkKind.game: _Recording('igdb'),
          WorkKind.movie: _Recording('tmdb'),
          WorkKind.animation: _Recording('anilist'),
        },
        fallback: _Recording('fallback'),
      );

      final row = Detection.fromSource(
        rawTitle: 'Tidewrack Lament',
        origin: DetectionOrigin.filename,
        sourceEntry: 'a.mkv',
        workKind: WorkKind.animation,
      );
      expect((await router.process(row)).best!.title, 'anilist');
    });

    test('an unregistered kind goes to the fallback, not to IGDB', () async {
      final router = CatalogueRouter(
        catalogues: {WorkKind.game: _Recording('igdb')},
        fallback: _Recording('fallback'),
      );
      expect((await router.process(_filmRow('Pale Anchor'))).best!.title,
          'fallback');
    });

    test('the router itself reaches no network', () async {
      // It inherits SkipResolver's refusing client, so a routing bug cannot
      // quietly resolve a film against IGDB.
      final router = CatalogueRouter(
        catalogues: {WorkKind.movie: _Recording('tmdb')},
        fallback: SkipResolver(),
      );
      final resolved = await router.process(Detection.fromSource(
          rawTitle: 'Harbour Lantern',
          origin: DetectionOrigin.filename,
          sourceEntry: 'a.exe'));
      expect(resolved.best, isNull);
    });
  });

  group('what a film exports as', () {
    ResolvedGame resolved(WorkKind kind) => ResolvedGame(
          detection: Detection.fromSource(
            rawTitle: 'Pale Anchor',
            origin: DetectionOrigin.filename,
            sourceEntry: 'Pale.Anchor.1987.1080p.mkv',
            workKind: kind,
          ),
          best: Candidate(
            externalId: kind == WorkKind.movie ? 'tmdb:11' : 'igdb:11',
            title: 'Pale Anchor',
            platformId: kind == WorkKind.movie ? null : 167,
            platformName: kind == WorkKind.movie ? null : 'PS5',
            score: 1.0,
          ),
          status: ReviewStatus.approved,
        );

    Map<String, Object?> item(WorkKind kind) {
      final doc = _doc([resolved(kind)]);
      final rendered = jsonDecode(TonkatsuExporter().export(doc));
      return ((rendered as Map)['items'] as List).single as Map<String, Object?>;
    }

    test('media_type is Tonkatsu own word for a film, which is movie', () {
      // Verified against Tonkatsu's published collections, not chosen: its
      // movie file spells this `movie`, never `film`.
      expect(item(WorkKind.movie)['media_type'], 'movie');
    });

    test('a film item carries no platform_id key at all', () {
      // Also copied from those files: a movie item is exactly media_type plus
      // external_id, while a game item carries a third key.
      expect(item(WorkKind.movie).containsKey('platform_id'), isFalse);
      expect(item(WorkKind.game)['platform_id'], 167);
    });

    test('a game export is byte-identical to what it was before films', () {
      expect(item(WorkKind.game),
          {'media_type': 'game', 'external_id': 11, 'platform_id': 167});
    });

    test('the CSV platform column is empty for a film rather than invented',
        () {
      final csv = CsvExporter().export(_doc([resolved(WorkKind.movie)]));
      final header = csv.trim().split('\n').first.split(',');
      final cells = csv.trim().split('\n').last.split(',');

      expect(cells[header.indexOf('platform')], isEmpty);
      // And the column named `media_type` here is the CARRIER, not the kind --
      // the one collision decision 0015 could not remove, live in one file:
      // this cell says `unknown` on the same row whose `.xcoll` item says
      // `movie`.
      expect(cells[header.indexOf('media_type')], 'unknown');
    });
  });

  group('the review document carries the kind', () {
    test('a film row round-trips through review.json', () {
      final doc = _doc([
        ResolvedGame(
            detection: Detection.fromSource(
          rawTitle: 'Pale Anchor',
          origin: DetectionOrigin.filename,
          sourceEntry: 'Pale.Anchor.1987.1080p.mkv',
          workKind: WorkKind.movie,
        ))
      ]);

      final reparsed = ReviewDocument.fromJson(
          jsonDecode(jsonEncode(doc.toJson())) as Map<String, dynamic>);
      expect(reparsed.games.single.detection.workKind, WorkKind.movie);
    });

    test('an unrecognised kind is refused rather than degraded to game', () {
      // Decision 0015: answering `game` to a typo writes a claim about the
      // row that nobody made.
      expect(() => WorkKind.parse('film', 'detection.work_kind'),
          throwsA(isA<ReviewFormatException>()));
    });

    test('the refusal names every kind there is, including the new one', () {
      try {
        WorkKind.parse('film', 'detection.work_kind');
        fail('should have thrown');
      } on ReviewFormatException catch (e) {
        for (final kind in WorkKind.values) {
          expect('$e', contains(kind.name));
        }
      }
    });
  });
}

/// A catalogue that resolves nothing and reports which one it was.
///
/// The router's contract is "the right implementation was called", so the
/// implementations here are labels rather than resolvers -- a real client
/// would test the client instead.
class _Recording extends Worker<Detection, ResolvedGame> {
  _Recording(this.label);
  final String label;

  @override
  Future<ResolvedGame> process(Detection task) async => ResolvedGame(
        detection: task,
        best: Candidate(
          externalId: '$label:0',
          title: label,
          score: 1.0,
        ),
      );
}
