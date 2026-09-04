/// The Custom Cards target: the partition it makes with `.xcoll`, and the
/// exact key set a card it writes can carry (T-0457).
///
/// **Why a key SET and not a field-by-field list.** The import schema upstream
/// accepts is long, and every field in it that this pipeline does not measure
/// is a field a writer could fill with a plausible default -- a `status`, a
/// `year` off a scene name, a local path in `cover`. A test that asserted each
/// written field is right would stay green through all of that. So the shape
/// of the assertion is the union of every key any export can emit, compared
/// against a literal four, plus the refused names enumerated and asserted
/// absent.
///
/// **The partition is the other half.** The two Tonkatsu targets divide the
/// approved rows between them: a row `.xcoll` can key on belongs there, and
/// this file is for the rest. Asserted over one mixed document rather than per
/// kind, because the property is about the pair of exporters and neither one
/// alone can state it.
///
/// Every fixture value is invented.
library;

import 'dart:convert';
import 'dart:io';

import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

import 'cli_snapshot.dart';

/// Invented ids. The platform id is plainly not one of the two a kind can
/// contribute to `.xcoll` (`0` and `1`).
const _igdbId = 610610;
const _tmdbId = 480480;
const _matchPlatformId = 3131;

/// A year a NAME carried, which is the only kind of year a row here can have
/// and the one `Detection.sourceYear` forbids exporting.
const _namedYear = 2019;

Candidate _match(
  String catalogue,
  int id, {
  String title = 'Mossgrave Ferry',
  int? platformId,
  String? platformName,
}) =>
    Candidate(
      externalId: '$catalogue:$id',
      title: title,
      score: 1.0,
      platformId: platformId,
      platformName: platformName,
    );

ResolvedGame _row(
  String rawTitle, {
  WorkKind kind = WorkKind.game,
  Candidate? best,
  String? platformHint,
  int? sourceYear,
  String? sourceEntry,
  ReviewStatus status = ReviewStatus.approved,
}) =>
    ResolvedGame(
      detection: Detection(
        rawTitle: rawTitle,
        mediaType: MediaType.disc,
        confidence: 0.8,
        sourcePhoto: sourceEntry == null ? 'shelf_c.jpg' : '',
        platformHint: platformHint,
        sourceEntry: sourceEntry,
        sourceYear: sourceYear,
        origin: sourceEntry == null
            ? DetectionOrigin.vision
            : DetectionOrigin.filename,
        workKind: kind,
      ),
      best: best,
      status: status,
    );

ReviewDocument _document(List<ResolvedGame> games) => ReviewDocument(
      version: 1,
      created: '2026-09-04T00:00:00.000Z',
      photos: const ['shelf_c.jpg'],
      games: games,
    );

List<Map<String, Object?>> _cards(ReviewDocument doc) => [
      for (final card
          in jsonDecode(TonkatsuCardsExporter().export(doc)) as List<dynamic>)
        (card as Map<String, dynamic>).cast<String, Object?>()
    ];

/// Every key any card this project writes may carry, and there is no fifth.
const _writtenKeys = {'title', 'type', 'alt_title', 'platform'};

/// The rest of the import schema (`CustomCardFields.ordered`, `release/0.44`),
/// which this target refuses. Enumerated by name rather than derived, so a key
/// that starts being written has to be deleted from here by hand.
const _refusedKeys = [
  'description',
  'year',
  'genres',
  'link',
  'cover',
  'format',
  'unit_total',
  'unit_group_total',
  'status',
  'rating',
  'comment',
  'rewatch_count',
  'started_at',
  'completed_at',
  'time_spent_minutes',
  'favorite',
  'current_episode',
  'current_season',
  'tags',
];

/// One row of every shape that reaches this target, so the key union below is
/// taken over the whole of what the writer can do rather than over one row.
List<ResolvedGame> _everyShape() => [
      // Nothing matched, and the spine named a console.
      _row('MOSSGRAVE FERRY', platformHint: 'PS4'),
      // Nothing matched and nothing hinted.
      _row('QUARRY OF BELLS'),
      // A match whose catalogue the kind does not imply, so `.xcoll` refuses
      // it and the raw title is no longer what the card is called.
      _row('ASHEN TALLY',
          best: _match(tmdbCatalogue, _tmdbId,
              title: 'Ashen Tally',
              platformId: _matchPlatformId,
              platformName: 'Fictional Console')),
      // A film, an unanswered animation and an anime, each carrying a hint the
      // card must not take.
      _row('PELLUCID HOURS', kind: WorkKind.movie, platformHint: 'PS4'),
      _row('TIDEGLASS', kind: WorkKind.animation, platformHint: 'PS4'),
      _row('HOLLOW LANTERN', kind: WorkKind.anime, platformHint: 'PS4'),
      // A name that carried a year where a title cannot be.
      _row('Quarry.of.Bells.$_namedYear.RePack',
          sourceEntry: 'Quarry.of.Bells.$_namedYear.RePack',
          sourceYear: _namedYear),
    ];

Future<ProcessResult> _runCli(List<String> args) => Process.run(
      Platform.resolvedExecutable,
      [cliSnapshot(), ...args],
      environment: {
        'IGDB_CLIENT_ID': '',
        'IGDB_CLIENT_SECRET': '',
        'SHELFSCAN_TMDB_TOKEN': '',
      },
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );

void main() {
  group('the registry carries a third target and both shells reach it', () {
    test('tonkatsu-cards is registered, writes json, and names itself', () {
      expect(exporters.keys, contains('tonkatsu-cards'));
      final exporter = exporters['tonkatsu-cards']!();
      expect(exporter, isA<TonkatsuCardsExporter>());
      expect(exporter.name, 'tonkatsu-cards');
      expect(exporter.extension, 'json');
    });

    test('the two that shipped keep their keys and their order', () {
      // The order is published -- the CLI's `Known:` line and the app's export
      // sheet both read it -- so this pins that a target was appended rather
      // than inserted.
      expect(exporters.keys.toList(), ['tonkatsu', 'csv', 'tonkatsu-cards']);
    });

    test('the file is a bare array, so there is no envelope to hold a clock',
        () {
      final text = TonkatsuCardsExporter()
          .export(_document([_row('MOSSGRAVE FERRY')]));
      expect(jsonDecode(text), isA<List<dynamic>>());
      expect(text, isNot(contains('created')));
      expect(text, isNot(contains('version')));
    });
  });

  group('the two Tonkatsu targets partition the approved rows', () {
    final xcoll = TonkatsuExporter();
    final cards = TonkatsuCardsExporter();

    /// One row of each shape the two targets have to divide between them.
    final mixed = <String, ResolvedGame>{
      'a matched game': _row('MOSSGRAVE FERRY',
          best: _match(igdbCatalogue, _igdbId,
              platformId: _matchPlatformId, platformName: 'Fictional Console')),
      'an unmatched game': _row('QUARRY OF BELLS', platformHint: 'PS4'),
      'a film with only an IGDB candidate': _row('PELLUCID HOURS',
          kind: WorkKind.movie,
          best: _match(igdbCatalogue, _igdbId, title: 'Pellucid Hours')),
      'an unanswered animation row':
          _row('TIDEGLASS', kind: WorkKind.animation),
      'an anime row': _row('HOLLOW LANTERN', kind: WorkKind.anime),
    };

    mixed.forEach((what, row) {
      test('exactly one of the two carries $what', () {
        expect([xcoll.canExport(row), cards.canExport(row)],
            anyOf(equals([true, false]), equals([false, true])),
            reason: 'both would export the row twice; neither would drop it');
      });
    });

    test('and over the whole document the two selections tile it', () {
      final doc = _document(mixed.values.toList());
      final inXcoll = xcoll.select(doc).toSet();
      final inCards = cards.select(doc).toSet();
      expect(inXcoll.intersection(inCards), isEmpty);
      expect(inXcoll.union(inCards), doc.games.toSet());
      // Not vacuous in either direction: each target actually took some.
      expect(inXcoll, isNotEmpty);
      expect(inCards, isNotEmpty);
    });

    test('a row with neither a match nor a title reaches no target at all', () {
      // The exception to the tiling above, and it is the row `review_screen`
      // already names as reaching no exporter: it can only come from a
      // hand-edited document.
      final row = _row('   ');
      expect(xcoll.canExport(row), isFalse);
      expect(cards.canExport(row), isFalse);
    });
  });

  group('type is WorkKind.wire, and every kind has to be a card type', () {
    test('every WorkKind writes a type this import accepts', () {
      for (final kind in WorkKind.values) {
        expect(TonkatsuCardsExporter.cardTypes, contains(kind.wire),
            reason: '${kind.key} writes media_type "${kind.wire}", which the '
                'Custom Cards import disqualifies with unknownType -- give '
                'the kind an accepted type or teach this target to decline '
                'it, but do not write the row');
      }
    });

    for (final kind in WorkKind.values) {
      test('an unmatched ${kind.key} row writes type ${kind.wire}', () {
        final card = _cards(_document([_row('MOSSGRAVE FERRY', kind: kind)]))
            .single;
        expect(card['type'], kind.wire);
        expect(card['title'], 'MOSSGRAVE FERRY');
      });
    }
  });

  group('the exact key set a card can carry', () {
    final cards = _cards(_document(_everyShape()));

    test('every shape that reaches the target produced a card', () {
      expect(cards, hasLength(_everyShape().length));
    });

    test('the union of every key written is exactly four', () {
      final keys = {for (final card in cards) ...card.keys};
      expect(keys, _writtenKeys);
    });

    test('title and type are on every card, and neither is empty', () {
      for (final card in cards) {
        expect(card['title'], isA<String>());
        expect(card['title'], isNotEmpty);
        expect(card['type'], isA<String>());
        expect(TonkatsuCardsExporter.cardTypes, contains(card['type']));
      }
    });

    for (final key in _refusedKeys) {
      test('no card carries $key', () {
        for (final card in cards) {
          expect(card.containsKey(key), isFalse);
        }
      });
    }

    test('alt_title appears only where the read title is not the card name',
        () {
      for (final card in cards) {
        expect(card['alt_title'], isNot(card['title']));
      }
      // The one row of the set whose match renamed it.
      final renamed =
          cards.singleWhere((card) => card['title'] == 'Ashen Tally');
      expect(renamed['alt_title'], 'ASHEN TALLY');
    });
  });

  group('cover is never written, whatever the row was read off', () {
    test('a document of rows read off photographs emits no cover key', () {
      final doc = _document([
        _row('MOSSGRAVE FERRY', platformHint: 'PS4'),
        _row('PELLUCID HOURS', kind: WorkKind.movie),
      ]);
      for (final card in _cards(doc)) {
        expect(card.containsKey('cover'), isFalse);
      }
    });

    test('and the photograph a row came off does not reach the file', () {
      // The field takes an http(s) URL and a local path is refused by the
      // importer anyway -- but the name of a file on the owner's disk must
      // not leave it whether or not the importer would have taken it.
      final doc = _document([_row('MOSSGRAVE FERRY')]);
      expect(doc.games.single.detection.sourcePhoto, 'shelf_c.jpg');
      expect(TonkatsuCardsExporter().export(doc), isNot(contains('shelf_c')));
    });
  });

  group('year is never written', () {
    final doc = _document([
      _row('Quarry.of.Bells.$_namedYear.RePack',
          sourceEntry: 'Quarry.of.Bells.$_namedYear.RePack',
          sourceYear: _namedYear),
    ]);

    test('a row carrying a sourceYear emits no year key', () {
      expect(doc.games.single.detection.sourceYear, _namedYear,
          reason: 'the fixture has to hold one for the assertion to bite');
      expect(_cards(doc).single.containsKey('year'), isFalse);
    });

    test('and the number does not reach the file through any other key', () {
      // It does survive inside the title, which is the name the source
      // printed and is what a card of an unresolved row is called.
      final card = _cards(doc).single;
      expect(card['title'], contains('$_namedYear'));
      expect(card.values.where((v) => v == _namedYear), isEmpty);
    });
  });

  group('platform is a game row\'s, and only where one was measured', () {
    String? platformOf(ResolvedGame row) =>
        _cards(_document([row])).single['platform'] as String?;

    test('an unmatched game writes the hint its spine gave it', () {
      expect(platformOf(_row('MOSSGRAVE FERRY', platformHint: 'PS4')), 'PS4');
    });

    test('a matched game writes the match, never the hint beside it', () {
      // The chain is CsvExporter's and not a `??` merge: the hint is reached
      // only when nothing matched.
      expect(
          platformOf(_row('MOSSGRAVE FERRY',
              platformHint: 'PS4',
              best: _match(tmdbCatalogue, _tmdbId,
                  platformId: _matchPlatformId,
                  platformName: 'Fictional Console'))),
          'Fictional Console');
    });

    test('a match that names no platform writes none, hint or no hint', () {
      final row = _row('MOSSGRAVE FERRY',
          platformHint: 'PS4', best: _match(tmdbCatalogue, _tmdbId));
      expect(row.detection.platformHint, 'PS4');
      expect(_cards(_document([row])).single.containsKey('platform'), isFalse);
    });

    test('a game with neither writes none', () {
      expect(_cards(_document([_row('QUARRY OF BELLS')]))
          .single
          .containsKey('platform'),
          isFalse);
    });

    for (final kind in WorkKind.values.where((k) => k != WorkKind.game)) {
      test('a ${kind.key} card carries no platform even with a hint', () {
        final row = _row('PELLUCID HOURS', kind: kind, platformHint: 'PS4');
        expect(row.detection.platformHint, 'PS4');
        expect(
            _cards(_document([row])).single.containsKey('platform'), isFalse);
      });
    }
  });

  group('one bad row must not cost the file', () {
    test('render skips what it cannot build and writes the rest', () {
      // A hand-built list, which is the case `Exporter.render`'s contract does
      // NOT cover: `export` only ever passes rows `canExport` accepted.
      final rows = [
        _row('   '),
        _row('MOSSGRAVE FERRY', platformHint: 'PS4'),
        _row('PELLUCID HOURS', kind: WorkKind.movie),
      ];
      final text = TonkatsuCardsExporter().render(rows);
      final written = (jsonDecode(text) as List<dynamic>)
          .map((card) => (card as Map<String, dynamic>)['title'])
          .toList();
      expect(written, ['MOSSGRAVE FERRY', 'PELLUCID HOURS']);
    });

    test('and throws on none of them', () {
      expect(() => TonkatsuCardsExporter().render([_row('')]), returnsNormally);
      expect(TonkatsuCardsExporter().render([_row('')]), '[]');
    });
  });

  group('the same document renders to the same bytes', () {
    test('twice over, because there is no clock and no counter in the file',
        () {
      final doc = _document(_everyShape());
      final exporter = TonkatsuCardsExporter();
      expect(exporter.export(doc), exporter.export(doc));
      // A second instance too: nothing accumulates on the exporter either.
      expect(TonkatsuCardsExporter().export(doc), exporter.export(doc));
    });
  });

  group('the CLI names the target and says why it left a row out', () {
    late String reviewPath;
    late String outPath;

    setUp(() {
      final dir = Directory.systemTemp.createTempSync('shelfscan_cards_');
      addTearDown(() {
        try {
          dir.deleteSync(recursive: true);
        } on FileSystemException {
          // A child process may still hold the directory on Windows.
        }
      });
      reviewPath = '${dir.path}/collection.review.json';
      outPath = '${dir.path}/cards.json';
      File(reviewPath).writeAsStringSync(jsonEncode(_document([
        _row('MOSSGRAVE FERRY',
            best: _match(igdbCatalogue, _igdbId,
                platformId: _matchPlatformId,
                platformName: 'Fictional Console')),
        _row('QUARRY OF BELLS', platformHint: 'PS4'),
      ]).toJson()));
    });

    test('tonkatsu-cards exports the unmatched row and explains the other',
        () async {
      final result = await _runCli(
          ['export', reviewPath, '--target', 'tonkatsu-cards', '-o', outPath]);

      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      expect(result.stdout, contains('Exported 1 of 2'));
      expect(
          result.stdout,
          contains('1 left out: the tonkatsu-cards target carries only what '
              '.xcoll cannot -- an item with a resolved match belongs in that '
              'file instead.'));
      final written = jsonDecode(File(outPath).readAsStringSync()) as List;
      expect(written.single, {
        'title': 'QUARRY OF BELLS',
        'type': 'game',
        'platform': 'PS4',
      });
    });

    test('and the sentence the other two targets print has not moved',
        () async {
      // Byte for byte: `doc/guide.md` and its two translations quote this
      // line, and `guide_transcript_test.dart` holds the guides to it.
      final result = await _runCli(
          ['export', reviewPath, '--target', 'tonkatsu', '-o', outPath]);

      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      expect(
          result.stdout,
          contains('1 left out: the tonkatsu target carries only items with '
              'a resolved IGDB match.'));
    });

    test('an unknown target still lists what is known, this one included',
        () async {
      final result = await _runCli(
          ['export', reviewPath, '--target', 'tonkatsu-box', '-o', outPath]);

      expect(result.exitCode, 2);
      expect(result.stderr,
          contains('Known: tonkatsu, csv, tonkatsu-cards'));
    });
  });

  /// T-0460. `parseJson` raises `CustomCardsParseErrorCode.emptyFile` on an
  /// empty array before it looks at a row (`release/0.44`), so `[]` is a
  /// whole-file failure upstream rather than an import of nothing: the person
  /// is handed a file the importer rejects with a message naming the wrong
  /// problem. The other two targets' empty forms are well-formed files and go
  /// on being written unchanged, which is the half of this that has to be
  /// pinned rather than argued.
  group('an empty file the importer would refuse is not written (T-0460)', () {
    late String reviewPath;
    late String outPath;
    late Directory dir;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('shelfscan_empty_');
      addTearDown(() {
        try {
          dir.deleteSync(recursive: true);
        } on FileSystemException {
          // A child process may still hold the directory on Windows.
        }
      });
      reviewPath = '${dir.path}/collection.review.json';
    });

    /// Nothing approved, so all three targets select nothing off the same
    /// document and the difference between them is theirs alone.
    void nothingApproved() {
      File(reviewPath).writeAsStringSync(jsonEncode(_document([
        _row('MOSSGRAVE FERRY', status: ReviewStatus.pending),
        _row('QUARRY OF BELLS', status: ReviewStatus.pending),
      ]).toJson()));
    }

    /// Rows a person approved that no catalogue answered: `.xcoll` selects
    /// none of them and the cards target selects all of them, which is the
    /// case where the empty `.xcoll` is written beside a full cards file.
    void approvedAndUnmatched() {
      File(reviewPath).writeAsStringSync(jsonEncode(_document([
        _row('MOSSGRAVE FERRY', platformHint: 'PS4'),
        _row('QUARRY OF BELLS'),
      ]).toJson()));
    }

    Future<ProcessResult> export(String target, String name) {
      outPath = '${dir.path}/$name';
      return _runCli(
          ['export', reviewPath, '--target', target, '-o', outPath]);
    }

    test('tonkatsu-cards writes no file, names the target and why; exit 0',
        () async {
      nothingApproved();
      final result = await export('tonkatsu-cards', 'cards.json');

      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      expect(
          result.stdout,
          contains('No file written: the tonkatsu-cards target carries 0 of '
              '0 approved game(s), and the import it is written for refuses a '
              'file with no items in it.'));
      // The assertion the whole task is for: the path is untouched, so
      // nothing is handed to an importer that would refuse it.
      expect(File(outPath).existsSync(), isFalse);
    });

    test('and equally when there are approved rows it carries none of',
        () async {
      // A shelf of matched rows: every one belongs in `.xcoll`, so this
      // target carries none and still writes nothing.
      File(reviewPath).writeAsStringSync(jsonEncode(_document([
        _row('MOSSGRAVE FERRY',
            best: _match(igdbCatalogue, _igdbId,
                platformId: _matchPlatformId,
                platformName: 'Fictional Console')),
      ]).toJson()));
      final result = await export('tonkatsu-cards', 'cards.json');

      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      expect(
          result.stdout,
          contains('No file written: the tonkatsu-cards target carries 0 of '
              '1 approved game(s)'));
      expect(File(outPath).existsSync(), isFalse);
      // The reason a row was left out is still the exporter's own sentence:
      // the guard replaces the file, not the narration.
      expect(
          result.stdout,
          contains('1 left out: the tonkatsu-cards target carries only what '
              '.xcoll cannot'));
    });

    test('.xcoll writes its empty collection, byte for byte', () async {
      nothingApproved();
      final result = await export('tonkatsu', 'shelf.xcoll');

      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      expect(result.stdout, contains('Exported 0 of 0 approved game(s) -> '));
      // Every byte of it, with only the clock blanked. An empty `items`
      // array is a well-formed collection and this file has always been
      // written; nothing in T-0460 may move a character of it.
      expect(_withoutCreated(File(outPath).readAsStringSync()), '''
{
  "version": 2,
  "format": "light",
  "name": "Shelf scan",
  "author": "shelfscan",
  "created": "<clock>",
  "description": "Generated by shelfscan",
  "items": []
}''');
    });

    test('.xcoll writes it beside a full cards file, on the same document',
        () async {
      approvedAndUnmatched();
      final xcoll = await export('tonkatsu', 'shelf.xcoll');
      final xcollPath = outPath;
      final cards = await export('tonkatsu-cards', 'cards.json');

      expect(xcoll.exitCode, 0, reason: '${xcoll.stdout}${xcoll.stderr}');
      expect(xcoll.stdout, contains('Exported 0 of 2 approved game(s) -> '));
      expect(_withoutCreated(File(xcollPath).readAsStringSync()),
          contains('"items": []'));
      expect(cards.stdout, contains('Exported 2 of 2 approved game(s) -> '));
      expect(jsonDecode(File(outPath).readAsStringSync()) as List,
          hasLength(2));
    });

    test('csv writes its header row, byte for byte', () async {
      nothingApproved();
      final result = await export('csv', 'shelf.csv');

      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      expect(result.stdout, contains('Exported 0 of 0 approved game(s) -> '));
      // The columns and the CRLF the reader of a CSV depends on, unchanged.
      expect(File(outPath).readAsStringSync(),
          'title,platform,media_type,external_id,source_photo\r\n');
    });
  });
}

/// A rendered `.xcoll` with the one run-local field replaced, so the rest of
/// the file can be compared as bytes.
String _withoutCreated(String xcoll) => xcoll.replaceAll(
    RegExp('"created": "[^"]*"'), '"created": "<clock>"');
