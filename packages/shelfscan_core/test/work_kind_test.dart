/// The kind of work is a property of the row (T-0279, decision 0015).
///
/// Two things are pinned here and the second is the reason the first is worth
/// pinning. That a row carries its own kind, defaulting to the value the
/// exporter used to hardcode, so nothing an existing document writes moves.
/// And that the kind and the CARRIER stay apart, though `media_type` is the
/// wire name of both -- Tonkatsu's field for the kind, this project's CSV
/// column for the carrier. One word for two concepts is what decision 0015
/// separates, and a half-applied separation would leave exactly the working
/// lookup key that hides it.
library;

import 'dart:convert';

import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

Detection _detection({
  WorkKind? workKind,
  MediaType mediaType = MediaType.disc,
}) =>
    Detection(
      rawTitle: 'HOLLOWMERE: THE TIDE CLERK',
      mediaType: mediaType,
      confidence: 0.9,
      sourcePhoto: 'shelf-a.jpg',
      platformHint: 'PS5',
      workKind: workKind ?? WorkKind.game,
    );

ResolvedGame _row({WorkKind? workKind, MediaType mediaType = MediaType.disc}) =>
    ResolvedGame(
      detection: _detection(workKind: workKind, mediaType: mediaType),
      best: Candidate(
        igdbId: 424242,
        title: 'Hollowmere: The Tide Clerk',
        platformId: 167,
        platformName: 'PlayStation 5',
        score: 1.0,
      ),
      status: ReviewStatus.approved,
    );

ReviewDocument _document(List<ResolvedGame> games) => ReviewDocument(
      version: 1,
      created: '2026-08-22T00:00:00.000Z',
      photos: const [],
      games: games,
    );

List<dynamic> _items(ReviewDocument doc) =>
    (jsonDecode(TonkatsuExporter().export(doc)) as Map<String, dynamic>)
        ['items'] as List<dynamic>;

void main() {
  group('the default is the literal the exporter used to hardcode', () {
    test('a row built without a kind is a game', () {
      expect(_detection().workKind, WorkKind.game);
    });

    test('the exported item still says game', () {
      expect(_items(_document([_row()])).single,
          containsPair('media_type', 'game'));
    });

    test('a document of games writes no work_kind at all', () {
      expect(_detection().toJson().containsKey('work_kind'), isFalse);
    });

    test('a document written before the field existed reads back as a game',
        () {
      final before = _detection().toJson()..remove('work_kind');
      expect(Detection.fromJson(before).workKind, WorkKind.game);
    });
  });

  group('a non-default kind reaches the file', () {
    test('the exported item carries it', () {
      expect(_items(_document([_row(workKind: WorkKind.anime)])).single,
          containsPair('media_type', 'anime'));
    });

    test('one document can hold both kinds, which is the point of the row', () {
      final items = _items(_document([_row(), _row(workKind: WorkKind.anime)]));
      expect([for (final i in items) (i as Map)['media_type']],
          ['game', 'anime']);
    });

    test('it survives a review.json round trip', () {
      final written = _detection(workKind: WorkKind.anime).toJson();
      expect(written['work_kind'], 'anime');
      expect(Detection.fromJson(written).workKind, WorkKind.anime);
    });
  });

  group('the kind and the carrier are not the same field', () {
    test('an anime on a disc exports the kind, not the carrier', () {
      final item = _items(_document(
          [_row(workKind: WorkKind.anime, mediaType: MediaType.disc)])).single;
      expect(item, containsPair('media_type', 'anime'));
    });

    test("the csv column of that name still answers the carrier", () {
      final csv = CsvExporter()
          .export(_document(
              [_row(workKind: WorkKind.anime, mediaType: MediaType.cartridge)]))
          .split('\r\n');
      final columns = csv[0].split(',');
      final values = csv[1].split(',');
      expect(values[columns.indexOf('media_type')], 'cartridge');
    });

    test('neither field can be parsed out of the other one', () {
      final row = Detection.fromJson({
        'raw_title': 'HOLLOWMERE: THE TIDE CLERK',
        'media_type': 'cartridge',
        'work_kind': 'anime',
      });
      expect(row.mediaType, MediaType.cartridge);
      expect(row.workKind, WorkKind.anime);
    });
  });

  group('an unrecognised kind is refused rather than answered', () {
    test('a typo in a hand-edited document names the field', () {
      expect(
        () => Detection.fromJson(
            {'raw_title': 'HOLLOWMERE', 'work_kind': 'anmie'},
            path: 'games[2].detection'),
        throwsA(isA<ReviewFormatException>().having((e) => e.toString(),
            'message', allOf(contains('games[2].detection.work_kind'),
                contains('anmie')))),
      );
    });

    test('a wrong-typed value is refused the same way', () {
      expect(
        () => Detection.fromJson({'raw_title': 'HOLLOWMERE', 'work_kind': 7}),
        throwsA(isA<ReviewFormatException>()),
      );
    });
  });
}
