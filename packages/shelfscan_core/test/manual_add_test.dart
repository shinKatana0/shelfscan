/// Manual add of items the vision stage never saw (T-0012).
///
/// doc/measurements.md records logo-only spines (Nocturne 5 Gold) and, since
/// T-0011, spines reported as unreadable, as "handled by manual add at
/// review". This pins down the three pieces that handling rests on:
///   1. a detection knows whether a human or the model produced it, and a
///      `review.json` written before that field existed still parses;
///   2. a hand-written entry -- title only, no photo, no candidates -- goes
///      through `resolve` exactly like a vision detection;
///   3. an approved item with no IGDB match reaches csv but never `.xcoll`;
///   4. the photo the human was looking at while typing is recorded, and is
///      kept apart from the photo an item was READ off (T-0052).
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

/// A review document as written BEFORE this change: no `origin` key
/// anywhere, exactly as T-0011 left the format.
final _legacyReviewJson = <String, dynamic>{
  'version': 1,
  'created': '2026-08-13T17:25:31.019438Z',
  'photos': ['shelf_a.jpg'],
  'games': [
    {
      'detection': {
        'raw_title': 'COBALT CHIME',
        'platform_hint': 'Switch',
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
  'unreadable': [
    {'source_photo': 'shelf_a.jpg', 'script': 'japanese', 'reason': null},
  ],
};

/// The minimum a human has to type into `games` by hand, as documented in
/// the CLI usage header: a title and an origin. No source photo, no
/// confidence, no `best`, no `candidates`, no `status`.
final _handWrittenEntry = <String, dynamic>{
  'detection': {
    'raw_title': 'Nocturne 5 Gold',
    'platform_hint': 'PS4',
    'media_type': 'disc',
    'origin': 'manual',
  },
};

const _igdbHits = <String, String>{
  'nocturne 5 gold': '''
[{"id": 1100000015, "name": "Nocturne 5 Gold",
  "platforms": [{"id": 48, "name": "PlayStation 4"}]}]''',
  'cobalt chime': '''
[{"id": 1100000047, "name": "Cobalt Chime",
  "platforms": [{"id": 130, "name": "Nintendo Switch"}]}]''',
};

/// Stubbed IGDB: real client code, canned HTTP underneath. There are no IGDB
/// credentials in this environment, so "resolved on creation" is only ever
/// covered against this stub -- never against the live service.
({IgdbClient client, List<String> queries}) _stubIgdb() {
  final queries = <String>[];
  final http.Client transport = MockClient((request) async {
    if (request.url.host == 'id.twitch.tv') {
      return http.Response(
          jsonEncode({'access_token': 'stub-token', 'expires_in': 3600}), 200);
    }
    final body = request.body;
    final query = RegExp(r'search "([^"]*)"').firstMatch(body)?.group(1) ?? '';
    queries.add(query);
    return http.Response(_igdbHits[query] ?? '[]', 200);
  });
  return (
    client:
        IgdbClient(clientId: 'stub', clientSecret: 'stub', client: transport),
    queries: queries,
  );
}

Candidate _match(int id, String title, int platformId, String platformName) =>
    Candidate(
      igdbId: id,
      title: title,
      platformId: platformId,
      platformName: platformName,
      score: 1.0,
    );

ReviewDocument _doc(List<ResolvedGame> games) => ReviewDocument(
      version: 1,
      created: '2026-08-13T00:00:00Z',
      photos: const ['shelf_a.jpg'],
      games: games,
    );

void main() {
  group('detection origin', () {
    test('defaults to vision and round-trips through JSON', () {
      final vision = Detection(
        rawTitle: 'MOOR',
        mediaType: MediaType.disc,
        confidence: 1.0,
        sourcePhoto: 'shelf_a.jpg',
      );
      expect(vision.origin, DetectionOrigin.vision);
      expect(vision.isManual, isFalse);
      expect(vision.toJson()['origin'], 'vision');

      final manual = Detection.manual(
        rawTitle: 'Nocturne 5 Gold',
        platformHint: 'PS4',
        mediaType: MediaType.disc,
      );
      expect(manual.isManual, isTrue);
      expect(manual.sourcePhoto, isEmpty,
          reason: 'a manual entry was read off no photo');
      expect(manual.confidence, 1.0,
          reason: 'a typed title is ground truth, not an estimate');

      final reparsed = Detection.fromJson(
          jsonDecode(jsonEncode(manual.toJson())) as Map<String, dynamic>);
      expect(reparsed.origin, DetectionOrigin.manual);
      expect(reparsed.toJson(), manual.toJson());
    });

    test('a review.json written before this field still parses, as vision',
        () {
      final doc = ReviewDocument.fromJson(
          jsonDecode(jsonEncode(_legacyReviewJson)) as Map<String, dynamic>);

      expect(doc.games.single.detection.origin, DetectionOrigin.vision);
      expect(doc.games.single.detection.rawTitle, 'COBALT CHIME');
      // The rest of the document is untouched by the new field.
      expect(doc.version, 1, reason: 'an additive field needs no version bump');
      expect(doc.unreadable, hasLength(1));
      expect(doc.unreadableByPhoto, {'shelf_a.jpg': 1});
    });

    test('an unknown origin string degrades to vision rather than throwing',
        () {
      final d = Detection.fromJson(
          <String, dynamic>{'raw_title': 'X', 'origin': 'telepathy'});
      expect(d.origin, DetectionOrigin.vision);
    });
  });

  group('the photo a manual entry was typed from (T-0052)', () {
    test('is recorded without claiming the item was read off it', () {
      final manual = Detection.manual(
        rawTitle: 'Nocturne 5 Gold',
        addedFromPhoto: 'shelf_a.jpg',
      );

      expect(manual.addedFromPhoto, 'shelf_a.jpg');
      expect(manual.sourcePhoto, isEmpty,
          reason: 'the human read the shelf, the model read nothing');
      expect(manual.photoContext, 'shelf_a.jpg',
          reason: 'which is still enough to file it under that shelf');
      expect(manual.origin, DetectionOrigin.manual,
          reason: 'the two rows now share a photo name; origin is what '
              'still tells a typed row from a read one');

      final reparsed = Detection.fromJson(
          jsonDecode(jsonEncode(manual.toJson())) as Map<String, dynamic>);
      expect(reparsed.addedFromPhoto, 'shelf_a.jpg');
      expect(reparsed.toJson(), manual.toJson());
    });

    test('is absent, not empty, when nothing was in view', () {
      for (final typed in ['', '   ', null]) {
        expect(
            Detection.manual(rawTitle: 'X', addedFromPhoto: typed)
                .addedFromPhoto,
            isNull);
      }
      expect(Detection.manual(rawTitle: 'X').photoContext, isEmpty);
      // A vision detection never carries one: it has a real source photo.
      final vision = Detection(
        rawTitle: 'MOOR',
        mediaType: MediaType.disc,
        confidence: 1.0,
        sourcePhoto: 'shelf_a.jpg',
      );
      expect(vision.addedFromPhoto, isNull);
      expect(vision.photoContext, 'shelf_a.jpg');
    });

    test('a review.json written before the field still reads correctly', () {
      final doc = ReviewDocument.fromJson(
          jsonDecode(jsonEncode(_legacyReviewJson)) as Map<String, dynamic>);

      expect(doc.version, 1, reason: 'an additive field needs no version bump');
      expect(doc.games.single.detection.addedFromPhoto, isNull);
      expect(doc.games.single.detection.photoContext, 'shelf_a.jpg',
          reason: 'an old vision row groups exactly as it did before');
      expect(doc.games.single.detection.rawTitle, 'COBALT CHIME');
      expect(doc.unreadableByPhoto, {'shelf_a.jpg': 1});

      // The hand-written minimum is unchanged too: still title + origin.
      final typed = ResolvedGame.fromJson(
          jsonDecode(jsonEncode(_handWrittenEntry)) as Map<String, dynamic>);
      expect(typed.detection.addedFromPhoto, isNull);
      expect(typed.detection.photoContext, isEmpty);
    });

    test('a wrong-typed value is named rather than silently ignored', () {
      expect(
        () => Detection.fromJson(<String, dynamic>{
          'raw_title': 'X',
          'added_from_photo': 3,
        }, path: 'games[0].detection'),
        throwsA(isA<ReviewFormatException>().having((e) => e.toString(), 'says '
            'where and what',
            contains('games[0].detection.added_from_photo'))),
      );
    });

    test('a source photo beats a typed-from note when a hand edit sets both',
        () {
      final both = Detection.fromJson(<String, dynamic>{
        'raw_title': 'MOOR',
        'source_photo': 'shelf_a.jpg',
        'added_from_photo': 'shelf_b.jpg',
        'origin': 'manual',
      });
      expect(both.photoContext, 'shelf_a.jpg');
    });

    test('a titleless typed row still blames no photo for it (T-0035)', () {
      // The heal drops the row into `unreadable`, which is what the model
      // PERCEIVED; a human's blank row is not a spine anybody saw, so the
      // photo they were looking at must not inherit the count.
      final doc = ReviewDocument.fromJson(<String, dynamic>{
        ..._legacyReviewJson,
        'games': [
          {
            'detection': {
              'raw_title': '  ',
              'origin': 'manual',
              'added_from_photo': 'shelf_a.jpg',
            }
          }
        ],
      });

      expect(doc.games, isEmpty);
      expect(doc.unreadable, hasLength(2));
      expect(doc.unreadableByPhoto, {'shelf_a.jpg': 1, '': 1},
          reason: 'the healed row is counted against no photo');
    });
  });

  group('hand-written entry through `shelfscan resolve`', () {
    test('parses with nothing but a title and an origin', () {
      final game = ResolvedGame.fromJson(
          jsonDecode(jsonEncode(_handWrittenEntry)) as Map<String, dynamic>);

      expect(game.detection.rawTitle, 'Nocturne 5 Gold');
      expect(game.detection.origin, DetectionOrigin.manual);
      expect(game.detection.sourcePhoto, isEmpty);
      expect(game.detection.confidence, 0.0);
      expect(game.best, isNull);
      expect(game.candidates, isEmpty);
      expect(game.status, ReviewStatus.pending);
    });

    test('is resolved exactly like a vision detection', () async {
      final doc = ReviewDocument.fromJson(jsonDecode(jsonEncode({
        ..._legacyReviewJson,
        'games': [..._legacyReviewJson['games'] as List, _handWrittenEntry],
      })) as Map<String, dynamic>);

      final igdb = _stubIgdb();
      final resolved = await Orchestrator.resolveOnly(
        resolverWorker: ResolverWorker(igdb.client),
      ).runResolve([for (final g in doc.games) g.detection]);

      expect(igdb.queries, containsAll(['cobalt chime', 'nocturne 5 gold']),
          reason: 'the manual entry is queried like any other detection');

      final nocturne =
          resolved.firstWhere((g) => g.detection.rawTitle == 'Nocturne 5 Gold');
      expect(nocturne.best?.igdbId, 1100000015);
      expect(nocturne.best?.platformId, 48,
          reason: 'the typed platform hint constrains the search');
      expect(nocturne.candidates, isNotEmpty);
      // The origin survives the round trip through the resolve stage.
      expect(nocturne.detection.origin, DetectionOrigin.manual);
      expect(nocturne.detection.sourcePhoto, isEmpty);
    });

    test('without IGDB credentials it stays pending and does not error',
        () async {
      final entry = ResolvedGame.fromJson(
          jsonDecode(jsonEncode(_handWrittenEntry)) as Map<String, dynamic>);
      final resolved = await Orchestrator.resolveOnly(
        resolverWorker: SkipResolver(),
      ).runResolve([entry.detection]);

      expect(resolved.single.best, isNull);
      expect(resolved.single.candidates, isEmpty);
      expect(resolved.single.status, ReviewStatus.pending);
      expect(resolved.single.detection.origin, DetectionOrigin.manual);
    });
  });

  group('export semantics for an item with no match', () {
    late ResolvedGame manual;
    late ResolvedGame matched;
    late ReviewDocument doc;

    setUp(() {
      manual = ResolvedGame(
        detection: Detection.manual(
          rawTitle: 'Nocturne 5 Gold',
          platformHint: 'PS4',
          mediaType: MediaType.disc,
        ),
        status: ReviewStatus.approved,
      );
      matched = ResolvedGame(
        detection: Detection(
          rawTitle: 'MOOR',
          mediaType: MediaType.disc,
          confidence: 1.0,
          sourcePhoto: 'shelf_a.jpg',
        ),
        best: _match(7, 'MOOR', 48, 'PlayStation 4'),
        status: ReviewStatus.approved,
      );
      doc = _doc([manual, matched]);
    });

    test('csv carries it, using the detection title and platform hint', () {
      final rows = const LineSplitter()
          .convert(CsvExporter().export(doc))
          .where((l) => l.isNotEmpty)
          .toList();

      expect(rows, hasLength(3), reason: 'header + both approved items');
      expect(rows[0], 'title,platform,media_type,igdb_id,source_photo');
      // No IGDB id and no source photo, and the platform is the typed hint.
      expect(rows[1], 'Nocturne 5 Gold,PS4,disc,,');
      expect(rows[2], 'MOOR,PlayStation 4,disc,7,shelf_a.jpg');
    });

    test('csv leaves source_photo empty even for an item typed from a photo',
        () {
      // The reason `added_from_photo` is a second field and not a widened
      // `source_photo` (T-0052): this column is provenance published to a
      // reader that has no `origin` column to qualify it with, so filling it
      // in here would assert the model read a title it never saw.
      final typed = ResolvedGame(
        detection: Detection.manual(
          rawTitle: 'Nocturne 5 Gold',
          platformHint: 'PS4',
          mediaType: MediaType.disc,
          addedFromPhoto: 'shelf_a.jpg',
        ),
        status: ReviewStatus.approved,
      );
      final rows = const LineSplitter()
          .convert(CsvExporter().export(_doc([typed])))
          .where((l) => l.isNotEmpty)
          .toList();

      expect(rows[0], 'title,platform,media_type,igdb_id,source_photo');
      expect(rows[1], 'Nocturne 5 Gold,PS4,disc,,');
      // ... and no new column appeared: the exporters did not have to change.
      expect(rows[1].split(',').length, 5);
    });

    test('csv still prefers the resolved title over the raw one', () {
      final noisy = ResolvedGame(
        detection: Detection(
          rawTitle: 'DUSKHOLLOWE',
          mediaType: MediaType.disc,
          confidence: 1.0,
          sourcePhoto: 'shelf_a.jpg',
          platformHint: 'PS4',
        ),
        best: _match(1, 'Duskhollow', 48, 'PlayStation 4'),
        status: ReviewStatus.approved,
      );
      final csv = CsvExporter().export(_doc([noisy]));
      expect(csv, contains('Duskhollow,PlayStation 4'));
      expect(csv, isNot(contains('DUSKHOLLOWE,')));
    });

    test('.xcoll still excludes every item without a match', () {
      final xcoll =
          jsonDecode(TonkatsuExporter().export(doc)) as Map<String, dynamic>;
      final items = xcoll['items'] as List<dynamic>;

      expect(items, hasLength(1));
      expect((items.single as Map<String, dynamic>)['external_id'], 7);
      expect(TonkatsuExporter().canExport(manual), isFalse);
      expect(CsvExporter().canExport(manual), isTrue);
    });

    test('review status still gates csv: only approved/edited get out', () {
      for (final status in [ReviewStatus.pending, ReviewStatus.rejected]) {
        manual.status = status;
        expect(CsvExporter().export(doc), isNot(contains('Nocturne 5 Gold')),
            reason: 'a $status item must not be exported');
      }
      manual.status = ReviewStatus.edited;
      expect(CsvExporter().export(doc), contains('Nocturne 5 Gold'));
    });

    test('an empty title is refused even by csv', () {
      final blank = ResolvedGame(
        detection: Detection.manual(rawTitle: '   '),
        status: ReviewStatus.approved,
      );
      expect(CsvExporter().canExport(blank), isFalse);
      expect(CsvExporter().select(_doc([blank])), isEmpty);
    });

    test('a title with a comma or a quote is still escaped', () {
      final tricky = ResolvedGame(
        detection: Detection.manual(
            rawTitle: 'Path of Ember 0, "Special"', platformHint: 'PS4'),
        status: ReviewStatus.approved,
      );
      expect(CsvExporter().export(_doc([tricky])),
          contains('"Path of Ember 0, ""Special""",PS4,unknown,,'));
    });
  });
}
