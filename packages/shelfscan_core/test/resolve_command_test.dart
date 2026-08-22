/// Guards the resolve-only re-run behind `shelfscan resolve` (T-0008).
///
/// The measurement of the resolver's match rate has to be repeatable after
/// a scorer change, so re-resolving an existing review document must:
///   1. never touch a vision provider (no cost, no model non-determinism);
///   2. carry every detection through byte-for-byte;
///   3. replace `best`/`candidates` with freshly computed ones.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

/// A review document as written by an earlier `scan`: real detections, and
/// a stale resolution (an approved wrong match) that the re-run must drop.
final _fixtureReviewJson = <String, dynamic>{
  'version': 1,
  'created': '2026-08-13T17:25:31.019438Z',
  'photos': ['shelf_a.jpg', 'shelf_b.jpg'],
  'games': [
    {
      'detection': {
        'raw_title': 'CROWN OF TIDEFALL',
        'platform_hint': 'PS5',
        'media_type': 'disc',
        'confidence': 1.0,
        'source_photo': 'shelf_b.jpg',
        'notes': 'spine only',
      },
      'best': {
        'igdb_id': 999,
        'title': 'Stale Wrong Match',
        'platform_id': 167,
        'platform_name': 'PlayStation 5',
        'score': 0.99,
      },
      'candidates': [
        {
          'igdb_id': 999,
          'title': 'Stale Wrong Match',
          'platform_id': 167,
          'platform_name': 'PlayStation 5',
          'score': 0.99,
        }
      ],
      'status': 'approved',
    },
    {
      'detection': {
        'raw_title': 'COBALT CHIME',
        'platform_hint': null,
        'media_type': 'cartridge',
        'confidence': 1.0,
        'source_photo': 'shelf_a.jpg',
        'notes': null,
      },
      'best': null,
      'candidates': <dynamic>[],
      'status': 'pending',
    },
  ],
};

/// Canned IGDB responses per search query, keyed by the query text the
/// resolver sends. Anything unlisted comes back as no hits.
const _igdbHits = <String, String>{
  'crown of tidefall': '''
[{"id": 1100000048, "name": "Crown of Tidefall",
  "platforms": [{"id": 167, "name": "PlayStation 5"},
                {"id": 48, "name": "PlayStation 4"}]}]''',
  'cobalt chime': '''
[{"id": 1100000047, "name": "Cobalt Chime",
  "platforms": [{"id": 130, "name": "Nintendo Switch"}]}]''',
};

/// Stubbed [IgdbClient]: real client code, canned HTTP underneath, so the
/// OAuth handshake and the query building stay exercised.
({IgdbClient client, List<String> queries}) _stubIgdb() {
  final queries = <String>[];
  final http.Client transport = MockClient((request) async {
    if (request.url.host == 'id.twitch.tv') {
      return http.Response(
          jsonEncode({'access_token': 'stub-token', 'expires_in': 3600}), 200);
    }
    final body = request.body;
    queries.add(body);
    final query = RegExp(r'search "([^"]*)"').firstMatch(body)?.group(1) ?? '';
    return http.Response(_igdbHits[query] ?? '[]', 200);
  });
  return (
    client: IgdbClient(
        clientId: 'stub', clientSecret: 'stub', client: transport),
    queries: queries,
  );
}

/// Fails loudly if the resolve path ever reaches a vision model.
class _ForbiddenVisionProvider implements VisionProvider {
  var calls = 0;

  @override
  Future<PhotoAnalysis> analyze(PhotoInput photo) async {
    calls += 1;
    throw StateError('resolve must not call the vision provider');
  }
}

void main() {
  group('runResolve over an existing review document', () {
    late ReviewDocument input;
    late _ForbiddenVisionProvider vision;
    late List<String> igdbRequests;
    late List<ResolvedGame> resolved;

    setUp(() async {
      input = ReviewDocument.fromJson(
          jsonDecode(jsonEncode(_fixtureReviewJson)) as Map<String, dynamic>);
      vision = _ForbiddenVisionProvider();
      final igdb = _stubIgdb();
      igdbRequests = igdb.queries;

      resolved = await Orchestrator(
        visionWorker: VisionWorker(vision),
        resolverWorker: ResolverWorker(igdb.client),
      ).runResolve([for (final game in input.games) game.detection]);
    });

    test('makes no vision calls', () {
      expect(vision.calls, 0);
      expect(igdbRequests, hasLength(2),
          reason: 'one IGDB query per detection');
    });

    test('returns the same detections, unchanged', () {
      expect(resolved, hasLength(input.games.length));
      final before = {
        for (final game in input.games)
          game.detection.rawTitle: game.detection.toJson()
      };
      final after = {
        for (final game in resolved)
          game.detection.rawTitle: game.detection.toJson()
      };
      expect(after, before);
    });

    test('replaces best and candidates with fresh matches', () {
      final tidefall = resolved
          .firstWhere((g) => g.detection.rawTitle == 'CROWN OF TIDEFALL');

      // The stale approved match is gone, not merged with the new one.
      expect(tidefall.candidates.map((c) => c.igdbId), isNot(contains(999)));
      expect(tidefall.best?.igdbId, 1100000048);
      expect(tidefall.best?.platformId, 167,
          reason: 'the PS5 hint must constrain the platform');
      expect(tidefall.best?.score, 1.0);

      final cobalt =
          resolved.firstWhere((g) => g.detection.rawTitle == 'COBALT CHIME');
      expect(cobalt.best?.igdbId, 1100000047);
      expect(cobalt.candidates, hasLength(1));
    });

    test('resets review status: a new match invalidates an old approval', () {
      expect(resolved.map((g) => g.status),
          everyElement(ReviewStatus.pending));
    });

    test('unmatched detections keep an empty, honest result', () async {
      final igdb = _stubIgdb();
      final orphan = Detection(
        rawTitle: 'UNREADABLE SPINE',
        mediaType: MediaType.unknown,
        confidence: 0.2,
        sourcePhoto: 'shelf_a.jpg',
      );
      final out = await Orchestrator(
        visionWorker: VisionWorker(_ForbiddenVisionProvider()),
        resolverWorker: ResolverWorker(igdb.client),
      ).runResolve([orphan]);

      expect(out.single.best, isNull);
      expect(out.single.candidates, isEmpty);
    });
  });

  group('Orchestrator.resolveOnly', () {
    test('carries no vision worker at all', () {
      final orchestrator = Orchestrator.resolveOnly(
          resolverWorker: ResolverWorker(_stubIgdb().client));
      expect(orchestrator.visionWorker, isNull);
    });

    test('refuses to run a scan instead of silently doing nothing', () {
      final orchestrator = Orchestrator.resolveOnly(
          resolverWorker: ResolverWorker(_stubIgdb().client));
      expect(
        () => orchestrator.runScan(
            [PhotoInput(name: 'shelf_a.jpg', bytes: Uint8List(0))]),
        throwsA(isA<StateError>()),
      );
    });
  });
}
