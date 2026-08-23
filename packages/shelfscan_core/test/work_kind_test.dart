/// The kind of work is a property of the row (T-0279, decision 0015).
///
/// Four things are pinned here. That a row carries its own kind, defaulting
/// to the value the exporter used to hardcode, so nothing an existing document
/// writes moves. That the kind and the CARRIER stay apart, though `media_type`
/// is the wire name of both -- Tonkatsu's field for the kind, this project's
/// CSV column for the carrier. One word for two concepts is what decision 0015
/// separates, and a half-applied separation would leave exactly the working
/// lookup key that hides it.
///
/// And two that arrived with T-0290, both about the same confusion one level
/// down: the exported spelling of each kind, against the table read off
/// Tonkatsu's own collections, now that a Dart identifier is no longer that
/// spelling; and that the one kind whose `platform_id` this pipeline cannot
/// answer is refused by the target rather than filled in with a plausible
/// number.
library;

import 'dart:convert';
import 'dart:io';

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
      sourcePhoto: 'shelf_a.jpg',
      platformHint: 'PS5',
      workKind: workKind ?? WorkKind.game,
    );

ResolvedGame _row({WorkKind? workKind, MediaType mediaType = MediaType.disc}) {
  // A film's id is TMDB's and a game's is IGDB's. The namespace has to agree
  // with what the kind implies or `.xcoll` declines the row, which is decision
  // 0016's check and not an incidental property of this fixture.
  final film = workKind == WorkKind.movie;
  return ResolvedGame(
    detection: _detection(workKind: workKind, mediaType: mediaType),
    best: Candidate(
      externalId: film ? 'tmdb:424242' : 'igdb:424242',
      title: 'Hollowmere: The Tide Clerk',
      platformId: film ? null : 167,
      platformName: film ? null : 'PlayStation 5',
      score: 1.0,
    ),
    status: ReviewStatus.approved,
  );
}

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

  group('the wire value is not the identifier', () {
    // The table is Tonkatsu's, read off its published collections (T-0162),
    // and this is the whole of what the export contract is. Written as a map
    // over `values` rather than three separate expectations so that a fourth
    // kind fails here until someone has looked its spelling up.
    test('every kind spells media_type the way Tonkatsu does', () {
      expect({for (final kind in WorkKind.values) kind: kind.wire}, {
        WorkKind.game: 'game',
        WorkKind.movie: 'movie',
        WorkKind.animation: 'animation',
      });
    });

    test('and shows a person a different word', () {
      expect({for (final kind in WorkKind.values) kind: kind.label}, {
        WorkKind.game: 'Game',
        WorkKind.movie: 'Film',
        WorkKind.animation: 'Anime',
      });
      for (final kind in WorkKind.values) {
        expect(kind.label, isNot(kind.wire), reason: 'a label is not a value');
      }
    });

    // The defect this whole task is: `TonkatsuExporter` wrote `workKind.name`,
    // so the identifier WAS the wire value and a rename edited an exported
    // file. `film` was caught before it shipped and `anime` was not. Cheap to
    // reintroduce -- `.name` is the obvious thing to reach for on an enum --
    // and invisible in a diff, since the two spellings agree today.
    test('nothing in lib/ writes an identifier into a file', () {
      // Comment lines are dropped first, and that is not a convenience: the
      // paragraph in `models.dart` explaining the defect quotes it, so the
      // first run of this test found its own subject.
      List<String> codeNaming(String needle) => [
            for (final file in Directory('lib')
                .listSync(recursive: true)
                .whereType<File>()
                .where((f) => f.path.endsWith('.dart')))
              if (file
                  .readAsLinesSync()
                  .where((l) => !l.trimLeft().startsWith('//'))
                  .any((l) => l.contains(needle)))
                file.path,
          ];

      expect(codeNaming('workKind.name'), isEmpty,
          reason: 'the wire value is WorkKind.wire and nothing else');

      // The other direction, because a scan that cannot match anything
      // reports zero just as confidently as a clean tree: the two writers
      // this rule exists for must both be found by the same pass.
      expect(codeNaming('workKind.wire'), hasLength(2));
    });
  });

  group('a non-default kind reaches the file', () {
    test('the exported item carries it', () {
      expect(_items(_document([_row(workKind: WorkKind.movie)])).single,
          containsPair('media_type', 'movie'));
    });

    test('one document can hold both kinds, which is the point of the row', () {
      final items =
          _items(_document([_row(), _row(workKind: WorkKind.movie)]));
      expect(
          [for (final i in items) (i as Map)['media_type']], ['game', 'movie']);
    });

    test('it survives a review.json round trip', () {
      final written = _detection(workKind: WorkKind.movie).toJson();
      expect(written['work_kind'], 'movie');
      expect(Detection.fromJson(written).workKind, WorkKind.movie);
    });
  });

  group('an animation row is declined rather than guessed at', () {
    test('.xcoll refuses it however well it matched', () {
      final row = _row(workKind: WorkKind.animation);
      expect(row.best, isNotNull);
      expect(TonkatsuExporter().canExport(row), isFalse);
      expect(_items(_document([row, _row()])), hasLength(1));
    });

    test('no item of it carries a 0 or a 1 anybody invented', () {
      final items = _items(_document([_row(workKind: WorkKind.animation)]));
      expect(items, isEmpty);
    });

    test('csv still carries it, so the row is not lost', () {
      final doc = _document([_row(workKind: WorkKind.animation)]);
      expect(CsvExporter().select(doc), hasLength(1));
    });

    test('the review.json round trip is unaffected: only the target refuses',
        () {
      final written = _detection(workKind: WorkKind.animation).toJson();
      expect(written['work_kind'], 'animation');
      expect(Detection.fromJson(written).workKind, WorkKind.animation);
    });
  });

  group('the kind and the carrier are not the same field', () {
    test('one row, both targets, two different answers under one wire name',
        () {
      final doc = _document(
          [_row(workKind: WorkKind.movie, mediaType: MediaType.cartridge)]);

      expect(_items(doc).single, containsPair('media_type', 'movie'));

      final csv = CsvExporter().export(doc).split('\r\n');
      final columns = csv[0].split(',');
      expect(csv[1].split(',')[columns.indexOf('media_type')], 'cartridge');
    });

    test('neither field can be parsed out of the other one', () {
      final row = Detection.fromJson({
        'raw_title': 'HOLLOWMERE: THE TIDE CLERK',
        'media_type': 'cartridge',
        'work_kind': 'animation',
      });
      expect(row.mediaType, MediaType.cartridge);
      expect(row.workKind, WorkKind.animation);
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
