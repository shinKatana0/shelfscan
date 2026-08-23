/// A row that maps to several catalogue entries, and a kind you can correct
/// (T-0163, decision 0015).
///
/// The unit question this pins was the owner's to answer and they answered it
/// "ask at review": a box set of three seasons is one object on a shelf and
/// three entries in a catalogue, so the row stays the box, carries what it
/// maps to, and the person holding the box decides. What is pinned here is
/// that the two relations do not collapse into one -- candidates compete and
/// parts coexist -- and that a corrected kind clears the match it invalidates
/// instead of sitting beside it.
///
/// Every fixture is invented, including the catalogue ids: nothing here has
/// called a catalogue, and a real id would be a claim this repository has not
/// measured.
library;

import 'dart:convert';

import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

const _seasons = [
  CatalogueEntry(
      title: 'Lantern Coast Chronicle', ref: 'anilist:70001', ordinal: 1),
  CatalogueEntry(
      title: 'Lantern Coast Chronicle: Ebb', ref: 'anilist:70002', ordinal: 2),
  CatalogueEntry(
      title: 'Lantern Coast Chronicle: Flood',
      ref: 'anilist:70003',
      ordinal: 3),
];

Detection _detection({WorkKind workKind = WorkKind.animation}) => Detection(
      rawTitle: 'LANTERN COAST CHRONICLE COMPLETE BOX',
      mediaType: MediaType.disc,
      confidence: 0.8,
      sourcePhoto: 'shelf_b.jpg',
      platformHint: null,
      workKind: workKind,
    );

ResolvedGame _box() =>
    ResolvedGame(detection: _detection(), parts: _seasons.toList());

ReviewDocument _document(List<ResolvedGame> games) => ReviewDocument(
      version: 1,
      created: '2026-01-01T00:00:00Z',
      photos: const ['shelf_b.jpg'],
      games: games.toList(),
    );

void main() {
  group('parts are not candidates', () {
    test('a row with no parts is one thing and offers nothing', () {
      final row = ResolvedGame(detection: _detection());
      expect(row.parts, isEmpty);
      expect(row.mapsToSeveral, isFalse);
      expect(row.expandParts(), [same(row)]);
    });

    test('one part is still one thing -- expansion is idempotent', () {
      final row =
          ResolvedGame(detection: _detection(), parts: [_seasons.first]);
      expect(row.mapsToSeveral, isFalse);
      expect(row.expandParts(), [same(row)]);
    });

    test('candidates and parts are separate lists on the same row', () {
      final row = ResolvedGame(
        detection: _detection(),
        candidates: [
          Candidate(
            igdbId: 510001,
            title: 'Lantern Coast Chronicle',
            platformId: 6,
            platformName: 'PC (Microsoft Windows)',
            score: 0.71,
          ),
        ],
        parts: _seasons.toList(),
      );
      // The point of the separation: a scored guess at what the row is, and
      // the entries the row maps to, are both present and neither is the
      // other. Picking the candidate would discard nothing here, because
      // there is nothing in `parts` competing with it.
      expect(row.candidates, hasLength(1));
      expect(row.parts, hasLength(3));
    });
  });

  group('expanding a box', () {
    test('gives one row per part, each carrying its own entry', () {
      final rows = _box().expandParts();
      expect(rows, hasLength(3));
      expect([for (final row in rows) row.detection.rawTitle], [
        'Lantern Coast Chronicle',
        'Lantern Coast Chronicle: Ebb',
        'Lantern Coast Chronicle: Flood',
      ]);
      expect([for (final row in rows) row.parts.single.ref],
          ['anilist:70001', 'anilist:70002', 'anilist:70003']);
      // None of them offers to expand again.
      expect(rows.every((row) => row.mapsToSeveral), isFalse);
      expect(rows.expand((row) => row.expandParts()), hasLength(3));
    });

    test('a part inherits the provenance but not the box match', () {
      final box = _box()
        ..best = Candidate(
          igdbId: 510002,
          title: 'Lantern Coast Chronicle Complete Box',
          platformId: 6,
          platformName: 'PC (Microsoft Windows)',
          score: 0.9,
        )
        ..status = ReviewStatus.approved;
      for (final row in box.expandParts()) {
        // Inheriting it would export all three parts as the same item.
        expect(row.best, isNull);
        expect(row.candidates, isEmpty);
        expect(row.status, ReviewStatus.pending);
        // The part was read off the photograph the box was read off, so it
        // groups under it on the review screen and carries the same
        // provenance into the csv export.
        expect(row.detection.sourcePhoto, 'shelf_b.jpg');
        expect(row.detection.workKind, WorkKind.animation);
      }
    });

    test('correcting one part cannot move its siblings', () {
      final rows = _box().expandParts();
      rows.first.correctWorkKind(WorkKind.game);
      expect(rows.first.detection.workKind, WorkKind.game);
      expect(rows[1].detection.workKind, WorkKind.animation);
      expect(rows[2].detection.workKind, WorkKind.animation);
    });

    test('each part exports on its own identity', () {
      final rows = _box().expandParts();
      for (final row in rows) {
        row.status = ReviewStatus.approved;
      }
      final csv = CsvExporter().export(_document(rows));
      expect(csv, contains('Lantern Coast Chronicle,'));
      expect(csv, contains('Lantern Coast Chronicle: Ebb,'));
      expect(csv, contains('Lantern Coast Chronicle: Flood,'));
      // Three rows plus the header: the box became three items, not one.
      expect(const LineSplitter().convert(csv).where((l) => l.isNotEmpty),
          hasLength(4));
    });

    test('.xcoll still refuses a part, because a part has no IGDB id', () {
      // Stated rather than worked around. The entries came from a catalogue
      // this project cannot yet call, so nothing has given these rows the
      // id `.xcoll` carries -- and the existing degradation is the honest
      // answer until the catalogue seam lands.
      final rows = _box().expandParts();
      for (final row in rows) {
        row.status = ReviewStatus.approved;
        expect(TonkatsuExporter().canExport(row), isFalse);
      }
    });
  });

  group('correcting the kind re-routes rather than relabels', () {
    ResolvedGame matchedRow() => ResolvedGame(
          detection: _detection(workKind: WorkKind.game),
          best: Candidate(
            igdbId: 510003,
            title: 'Lantern Coast Chronicle',
            platformId: 6,
            platformName: 'PC (Microsoft Windows)',
            score: 0.95,
          ),
          status: ReviewStatus.approved,
        );

    test('the stale match goes and the row is marked as owed a lookup', () {
      final row = matchedRow()..correctWorkKind(WorkKind.animation);
      expect(row.detection.workKind, WorkKind.animation);
      // The whole point: a right word beside a wrong match is the failure
      // the correction exists to prevent (decision 0015).
      expect(row.best, isNull);
      expect(row.needsReresolution, isTrue);
      expect(row.status, ReviewStatus.pending);
    });

    test('correcting to the kind it already has changes nothing', () {
      final row = matchedRow()..correctWorkKind(WorkKind.game);
      expect(row.best, isNotNull);
      expect(row.needsReresolution, isFalse);
      expect(row.status, ReviewStatus.approved);
    });
  });

  group('the document carries both, and only when there is something to say',
      () {
    test('a row that maps to one thing writes neither key', () {
      final json = ResolvedGame(detection: _detection()).toJson();
      expect(json.containsKey('parts'), isFalse);
      expect(json.containsKey('needs_reresolution'), isFalse);
    });

    test('parts and the mark survive a round trip', () {
      final before = _box()..correctWorkKind(WorkKind.game);
      final after = ReviewDocument.parse(
          jsonEncode(_document([before]).toJson()))
        .games
        .single;
      expect(after.parts, hasLength(3));
      expect([for (final part in after.parts) part.ref],
          ['anilist:70001', 'anilist:70002', 'anilist:70003']);
      expect([for (final part in after.parts) part.ordinal], [1, 2, 3]);
      expect(after.needsReresolution, isTrue);
      expect(after.mapsToSeveral, isTrue);
    });

    test('an entry with no ordinal writes none and reads back null', () {
      final row = ResolvedGame(
        detection: _detection(),
        parts: const [
          CatalogueEntry(title: 'Lantern Coast Chronicle', ref: 'anilist:70004'),
          CatalogueEntry(title: 'Lantern Coast Shorts', ref: 'anilist:70005'),
        ],
      );
      expect(row.toJson()['parts'], [
        {'title': 'Lantern Coast Chronicle', 'ref': 'anilist:70004'},
        {'title': 'Lantern Coast Shorts', 'ref': 'anilist:70005'},
      ]);
      final after =
          ReviewDocument.parse(jsonEncode(_document([row]).toJson()))
              .games
              .single;
      expect(after.parts.first.ordinal, isNull);
    });

    test('a malformed entry names where it is', () {
      expect(
        () => ReviewDocument.parse(jsonEncode({
          'version': 1,
          'created': '2026-01-01T00:00:00Z',
          'photos': <String>[],
          'games': [
            {
              'detection': {'raw_title': 'BOX'},
              'parts': [
                {'title': 'Lantern Coast Chronicle', 'ref': 12345},
              ],
            },
          ],
        })),
        throwsA(isA<ReviewFormatException>().having(
            (e) => e.toString(), 'message', contains('games[0].parts[0].ref'))),
      );
    });
  });
}
