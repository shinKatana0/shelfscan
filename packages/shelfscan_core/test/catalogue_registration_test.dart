/// What the CLI registers on the routing seam, and what a film row actually
/// does in a run that has no TMDB token (T-0308).
///
/// T-0162 built `CatalogueRouter` so that a shell registers an entry and no
/// production line moves, and then no shell registered one: `_makeResolver`
/// returned a single `ResolverWorker`, so a film row with IGDB credentials was
/// searched in the games catalogue. These tests are about the registration
/// rather than the seam -- `tmdb_and_routing_test.dart` owns the seam and the
/// client.
///
/// **Nothing here makes a request, so a green run says nothing about a film
/// resolving.** The branch that registers [TmdbResolverWorker] is asserted
/// structurally: that the environment variable reaches it, and that the film
/// kind is what it answers. T-0162's client has since been called against the
/// live service and films came back (`doc/measurements.md`, "TMDB's `year`
/// filters, and the first live film searches"), and none of that is what
/// these tests check. What registering it buys is that a film is put in front
/// of a film catalogue -- whether it is found there is the client's business.
///
/// **The keyless half is run end to end**, because it is the owner's
/// decision: with IGDB credentials and no TMDB token a film row keeps the
/// title read off its filename, asks IGDB nothing, exports to CSV and is
/// refused by `.xcoll`.
///
/// Every title, filename, id and credential below is invented.
library;

import 'dart:convert';

import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

import '../bin/shelfscan.dart' show resolverFor, tmdbTokenFrom;

const _igdb = {
  'IGDB_CLIENT_ID': 'twitch-id',
  'IGDB_CLIENT_SECRET': 'twitch-secret',
};

const _token = {tmdbTokenVariable: 'tmdb-not-a-token'};

/// Every IGDB search a run would have made, and no request off the machine.
class _CountingIgdb extends IgdbClient {
  _CountingIgdb() : super(clientId: 'twitch-id', clientSecret: 'twitch-secret');

  final searched = <String>[];

  @override
  Future<List<IgdbHit>> search(String query, {String? platformHint}) async {
    searched.add(query);
    return [
      IgdbHit(
        igdbId: 4,
        title: query,
        platformId: 48,
        platformName: 'PlayStation 4',
      ),
    ];
  }
}

Detection _film(String title) => Detection.fromSource(
      rawTitle: title,
      origin: DetectionOrigin.filename,
      sourceEntry: '$title.1987.1080p.mkv',
      workKind: WorkKind.movie,
    );

Detection _game(String title) => Detection.fromSource(
      rawTitle: title,
      origin: DetectionOrigin.filename,
      sourceEntry: '$title.exe',
    );

ReviewDocument _doc(List<ResolvedGame> games) => ReviewDocument(
      version: 1,
      created: '2026-01-01T00:00:00Z',
      photos: const [],
      games: games,
    );

CatalogueRouter _routerFor(Map<String, String> env,
        {Map<String, String>? aliases}) =>
    resolverFor(env, aliases: aliases) as CatalogueRouter;

void main() {
  group('what the CLI registers, per environment', () {
    test('nothing configured is still the shared SkipResolver', () {
      // Unchanged, and deliberately: with no catalogue to register there is
      // nothing for a router to route to, and this is the type the app takes
      // for the same run.
      expect(resolverFor(const {}), isA<SkipResolver>());
      expect(resolverFor(const {'IGDB_CLIENT_ID': 'twitch-id'}),
          isA<SkipResolver>());
    });

    test('IGDB credentials register the GAMES catalogue, not every kind', () {
      final router = _routerFor(_igdb);

      expect(router.catalogues.keys, [WorkKind.game]);
      expect(router.catalogues[WorkKind.game], isA<ResolverWorker>());
      // The half that is the whole defect: what answers a kind nobody
      // registered must not be the games catalogue.
      expect(router.fallback, isA<SkipResolver>());
      for (final kind in WorkKind.values.where((k) => k != WorkKind.game)) {
        expect(router.catalogues[kind], isNull);
      }
    });

    test('the token registers the film catalogue and moves nothing else', () {
      final router = _routerFor({..._igdb, ..._token});

      expect(router.catalogues[WorkKind.movie], isA<TmdbResolverWorker>());
      expect(router.catalogues[WorkKind.game], isA<ResolverWorker>());
      expect(router.fallback, isA<SkipResolver>());
    });

    test('a token with no IGDB credentials registers only TMDB kinds', () {
      final router = _routerFor(_token);

      expect(router.catalogues.keys,
          [WorkKind.movie, WorkKind.animationFilm, WorkKind.animationSeries]);
      expect(router.catalogues.containsKey(WorkKind.game), isFalse);
      expect(router.fallback, isA<SkipResolver>());
    });

    test('the token registers the two ANSWERED anime kinds as well (T-0369)',
        () {
      // The gap this task closed: T-0368 made an anime row answerable and
      // exportable, and no shell routed one anywhere, so every one of them
      // came back unmatched and `.xcoll` refused it by the base clause.
      final router = _routerFor({..._igdb, ..._token});

      expect(router.catalogues.keys, [
        WorkKind.game,
        WorkKind.movie,
        WorkKind.animationFilm,
        WorkKind.animationSeries,
      ]);
    });

    test('and each anime kind on the TMDB endpoint that answers IT', () {
      // The trap, as an assertion. Registering the film worker for a series
      // would answer a series with a MOVIE id -- same catalogue, same `tmdb:`
      // namespace, so decision 0016's check in `TonkatsuExporter` cannot see
      // it. What separates them is the endpoint.
      final router = _routerFor(_token);
      final film =
          router.catalogues[WorkKind.animationFilm]! as TmdbResolverWorker;
      final series =
          router.catalogues[WorkKind.animationSeries]! as TmdbResolverWorker;

      expect(film.search, TmdbSearch.movie);
      expect(series.search, TmdbSearch.series);
      // The film kind and the anime film kind are one worker, because an
      // anime film is a film in TMDB.
      expect(identical(router.catalogues[WorkKind.movie], film), isTrue);
    });

    test('the unanswered anime kind is registered in NO configuration', () {
      // `WorkKind.animation` is the film-or-series question still open. There
      // is no endpoint for "one of the two", and `TonkatsuExporter` refuses
      // the row for a reason a match would not change.
      const configurations = [
        <String, String>{},
        _igdb,
        _token,
        {..._igdb, ..._token},
      ];
      for (final env in configurations) {
        final resolver = resolverFor(env);
        if (resolver is! CatalogueRouter) continue;
        expect(resolver.catalogues.containsKey(WorkKind.animation), isFalse,
            reason: 'registered by $env');
      }
    });

    test('every registration is one the catalogue itself says it answers', () {
      // How this is established, rather than a statement that care was taken:
      // each catalogue declares `answers`, the shell never types a kind at
      // all -- `registrationsOf` derives the map -- and this walks what was
      // built and compares the two.
      final router = _routerFor({..._igdb, ..._token});

      for (final entry in router.catalogues.entries) {
        final catalogue = entry.value;
        expect(catalogue, isA<CatalogueWorker>(),
            reason: '${entry.key.key} is registered to something that states '
                'nothing about what it answers');
        expect((catalogue as CatalogueWorker).answers, contains(entry.key));
      }
    });

    test('one token, one client: the anime kinds add no credential', () {
      final router = _routerFor(_token);
      final workers = [
        for (final kind in [
          WorkKind.movie,
          WorkKind.animationFilm,
          WorkKind.animationSeries
        ])
          router.catalogues[kind]! as TmdbResolverWorker,
      ];

      expect(workers.map((w) => w.tmdb.token).toSet(),
          {'tmdb-not-a-token'});
      // One `TmdbClient` across all three, not three built from one string.
      expect(workers.map((w) => identityHashCode(w.tmdb)).toSet(),
          hasLength(1));
    });

    test('a set-but-empty token is an unset token', () {
      // The T-0080 rule, applied to the third credential rather than
      // rediscovered by it.
      expect(tmdbTokenFrom(const {tmdbTokenVariable: ''}), isNull);
      expect(tmdbTokenFrom(const {}), isNull);
      expect(tmdbTokenFrom(_token), 'tmdb-not-a-token');
      expect(_routerFor({..._igdb, tmdbTokenVariable: ''}).catalogues.keys,
          [WorkKind.game]);
    });

    test('the alias table goes to the catalogue the aliases are about', () {
      final games =
          _routerFor(_igdb, aliases: const {'biohazard': 'resident evil'})
              .catalogues[WorkKind.game]! as ResolverWorker;

      expect(games.aliases, containsPair('biohazard', 'resident evil'));
      expect(games.igdb.clientId, 'twitch-id');
    });
  });

  group('a film row in a keyed run is keyless -- the owner decision', () {
    // The shape `resolverFor` builds for a keyed run with no token, rebuilt
    // here with a counting client so the assertions below can be made without
    // a request leaving the machine. The first test is what ties the two
    // together.
    late _CountingIgdb igdb;
    late CatalogueRouter resolver;

    setUp(() {
      igdb = _CountingIgdb();
      resolver = CatalogueRouter(
        catalogues: {WorkKind.game: ResolverWorker(igdb)},
        fallback: SkipResolver(),
      );
    });

    test('and it is the shape the CLI actually builds', () {
      final built = _routerFor(_igdb);

      expect(built.catalogues.keys, resolver.catalogues.keys);
      expect(built.catalogues[WorkKind.game], isA<ResolverWorker>());
      expect(built.fallback.runtimeType, resolver.fallback.runtimeType);
    });

    test('the film keeps its filename title and IGDB is asked nothing',
        () async {
      final doc = await Orchestrator.resolveOnly(resolverWorker: resolver)
          .runResolve([_film('Pale Anchor'), _game('Nocturne 5 Gold')]);

      final film =
          doc.firstWhere((g) => g.detection.workKind == WorkKind.movie);
      expect(film.best, isNull);
      expect(film.candidates, isEmpty);
      expect(film.detection.rawTitle, 'Pale Anchor');

      // Both halves of the claim, out of one run: the film was never offered
      // to IGDB, and the game still was. The query is the normalised title,
      // which is what `ResolverWorker` searches on.
      expect(igdb.searched, ['nocturne 5 gold']);
    });

    test('CSV yes, on the title read off the filename', () async {
      final resolved = await resolver.process(_film('Pale Anchor'));
      resolved.status = ReviewStatus.approved;

      final csv = CsvExporter().export(_doc([resolved]));
      final header = csv.trim().split('\n').first.split(',');
      final cells = csv.trim().split('\n').last.split(',');

      expect(cells[header.indexOf('title')], 'Pale Anchor');
      expect(cells[header.indexOf('external_id')], isEmpty);
    });

    test('.xcoll no, and the row is refused rather than written empty',
        () async {
      final resolved = await resolver.process(_film('Pale Anchor'));
      resolved.status = ReviewStatus.approved;

      final exporter = TonkatsuExporter();
      expect(exporter.canExport(resolved), isFalse);

      final items =
          (jsonDecode(exporter.export(_doc([resolved]))) as Map)['items'];
      expect(items, isEmpty);
    });

    test('a game row in the same run is unchanged by any of this', () async {
      final resolved = await resolver.process(_game('Nocturne 5 Gold'));

      expect(resolved.best, isNotNull);
      expect(resolved.best!.externalId, 'igdb:4');
      expect(igdb.searched, ['nocturne 5 gold']);
    });
  });
}
