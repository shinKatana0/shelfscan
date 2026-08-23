/// A row is identified by the catalogue that answered and that catalogue's id
/// (decision 0016).
///
/// `Candidate` was written when IGDB was the only catalogue this project could
/// ask, so a film's TMDB id travelled in a field called `igdbId` beside a
/// `platformId` of `0` invented to satisfy a required field. This pins the four
/// things that changed and, more importantly, the ones that did not.
///
/// **The load-bearing claim is that the rename reaches no exported file**, and
/// it is load-bearing because if it were wrong the change would be a format
/// migration wearing a rename's clothes. It holds for a reason `WorkKind` could
/// not use: the wire key was always a string literal at the (de)serialiser and
/// the CSV column a literal in a header constant, so the Dart identifier was
/// never the file format. T-0290 had to invent `WorkKind.wire` for exactly the
/// separation this type already had.
///
/// So the `.xcoll` item below is asserted at the byte level against what it was
/// before, and the CSV against what it was before plus the two changes decision
/// 0016 argues for and nothing else.
library;

import 'dart:convert';

import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

Detection _detection({
  String rawTitle = 'Lanternfall',
  String? platformHint = 'SWITCH',
  WorkKind workKind = WorkKind.game,
}) =>
    Detection(
      rawTitle: rawTitle,
      mediaType: MediaType.disc,
      confidence: 0.9,
      sourcePhoto: 'shelf_a.jpg',
      platformHint: platformHint,
      workKind: workKind,
    );

ReviewDocument _doc(List<ResolvedGame> games) => ReviewDocument(
      version: 1,
      created: '2026-08-23T00:00:00.000Z',
      photos: const [],
      games: games,
    );

/// The one game row every byte assertion below is taken on.
ResolvedGame _gameRow() => ResolvedGame(
      detection: _detection(),
      best: Candidate(
        externalId: 'igdb:1100000090',
        title: 'Lanternfall',
        platformId: 130,
        platformName: 'Nintendo Switch',
        score: 1.0,
      ),
      status: ReviewStatus.approved,
    );

Map<String, Object?> _item(ReviewDocument doc) =>
    ((jsonDecode(TonkatsuExporter().export(doc)) as Map)['items'] as List)
        .single as Map<String, Object?>;

void main() {
  group('the rename reaches no exported file', () {
    test('a game .xcoll item is byte-identical to what it was before', () {
      // Byte for byte the map T-0162 pinned, before `igdbId` was renamed and
      // before the platform became nullable: a bare integer under
      // `external_id`, with the catalogue implied by `media_type`. The
      // namespace is this project's vocabulary and is split off at the writer,
      // because the target's contract is the integer.
      expect(_item(_doc([_gameRow()])),
          {'media_type': 'game', 'external_id': 1100000090, 'platform_id': 130});
    });

    test('the CSV moves in exactly the two ways 0016 decided, and no others',
        () {
      // Before: `title,platform,media_type,igdb_id,source_photo` over
      //         `Lanternfall,Nintendo Switch,disc,1100000090,shelf_a.jpg`.
      // A column named for one catalogue carrying another's ids is the same
      // defect as the field it came from, one level out. Every other cell is
      // unmoved, which is the half worth asserting.
      expect(
        CsvExporter().export(_doc([_gameRow()])),
        'title,platform,media_type,external_id,source_photo\r\n'
        'Lanternfall,Nintendo Switch,disc,igdb:1100000090,shelf_a.jpg\r\n',
      );
    });
  });

  group('a document written before the namespace still loads', () {
    // The one widening read the change costs. There is no installed base to
    // build a seam over (decision 0014), so the read accepts the old shape and
    // nothing dual-writes.
    Candidate parse(Map<String, dynamic> json) => Candidate.fromJson(json);

    test('a bare igdb_id integer means igdb:<that integer>', () {
      final c = parse({
        'igdb_id': 1100000090,
        'title': 'Lanternfall',
        'platform_id': 130,
        'platform_name': 'Nintendo Switch',
        'score': 1.0,
      });
      expect(c.externalId, 'igdb:1100000090');
      expect(c.platformId, 130);
    });

    test('a document written now carries the namespaced value', () {
      expect(parse(_gameRow().best!.toJson()).externalId, 'igdb:1100000090');
    });

    test('a candidate carrying neither key is refused by name', () {
      expect(
        () => parse({'title': 'Lanternfall', 'score': 1.0}),
        throwsA(isA<ReviewFormatException>().having((e) => e.toString(),
            'message', contains('external_id'))),
      );
    });
  });

  group('a kind with no platform carries none', () {
    test('the keys are absent rather than 0 and empty', () {
      final film = Candidate(
        externalId: 'tmdb:1100000091',
        title: 'Harbour Lights',
        score: 1.0,
      );
      expect(film.toJson().containsKey('platform_id'), isFalse);
      expect(film.toJson().containsKey('platform_name'), isFalse);
      expect(film.platformId, isNull);
    });

    test('a game row still writes both, so its document does not move', () {
      final json = _gameRow().best!.toJson();
      expect(json['platform_id'], 130);
      expect(json['platform_name'], 'Nintendo Switch');
    });
  });

  group('the CSV platform column after a kind correction', () {
    // The behaviour change hiding in the nullable platform, and the reason it
    // is a test rather than a footnote. `best?.platformName ?? d.platformHint`
    // was right only by accident: a film's platform name was `''`, which is not
    // null and blocked the fallback. Under a nullable field the chain would
    // continue -- and `correctWorkKind` clears the match, NOT the detection, so
    // a row corrected from game to film keeps the console hint its spine gave
    // it. A console name in a film's platform column is data-shaped wrong.
    String platformCell(ReviewDocument doc) {
      final rows = CsvExporter().export(doc).trim().split('\r\n');
      return rows[1].split(',')[rows[0].split(',').indexOf('platform')];
    }

    ResolvedGame corrected() {
      final row = _gameRow();
      row.correctWorkKind(WorkKind.movie);
      // What a re-resolution against the film catalogue then puts back.
      row.best = Candidate(
        externalId: 'tmdb:1100000091',
        title: 'Harbour Lights',
        score: 1.0,
      );
      row.status = ReviewStatus.approved;
      return row;
    }

    test('the correction keeps the hint on the detection, which is the trap',
        () {
      final row = corrected();
      expect(row.detection.workKind, WorkKind.movie);
      expect(row.detection.platformHint, 'SWITCH');
    });

    test('the column is empty rather than the console the spine said', () {
      expect(platformCell(_doc([corrected()])), isEmpty);
    });

    test('an unmatched row still falls back to the hint, which is untouched',
        () {
      // The negative control for the rule above: the fallback exists for a row
      // nothing matched, where the guess is all there is, and it survives.
      final row = ResolvedGame(
        detection: _detection(rawTitle: 'Quarry Runner', platformHint: 'PS5'),
        status: ReviewStatus.approved,
      );
      expect(platformCell(_doc([row])), 'PS5');
    });
  });

  group('an exporter declines a row it cannot fill honestly', () {
    ResolvedGame film({required String externalId}) => ResolvedGame(
          detection: _detection(
              rawTitle: 'Harbour Lights',
              platformHint: null,
              workKind: WorkKind.movie),
          best: Candidate(
              externalId: externalId, title: 'Harbour Lights', score: 1.0),
          status: ReviewStatus.approved,
        );

    test('a film carrying a games-catalogue id is refused', () {
      // The defect T-0290 fixed by hand, made mechanical: `main` was writing a
      // games id into a film's item one field over. The catalogue the kind
      // implies and the catalogue that answered have to agree.
      final row = film(externalId: 'igdb:1100000090');
      expect(row.best, isNotNull);
      expect(TonkatsuExporter().canExport(row), isFalse);
    });

    test('the same row under its own catalogue exports', () {
      final row = film(externalId: 'tmdb:1100000091');
      expect(TonkatsuExporter().canExport(row), isTrue);
      expect(_item(_doc([row])),
          {'media_type': 'movie', 'external_id': 1100000091});
    });

    test('an id this target cannot carry as an integer is refused', () {
      expect(
          TonkatsuExporter().canExport(film(externalId: 'tmdb:tt0100150')),
          isFalse);
    });

    test('declining is per target: CSV carries what .xcoll refuses', () {
      // Decision 0016, and 0012 before it: a row .xcoll cannot key on is not a
      // row that failed. CSV is title text and takes it.
      final doc = _doc([film(externalId: 'igdb:1100000090')]);
      expect(TonkatsuExporter().select(doc), isEmpty);
      expect(CsvExporter().select(doc), hasLength(1));
    });
  });
}
