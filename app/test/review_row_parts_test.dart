/// The review screen's answer to "this box maps to several" (T-0163), and to
/// the kind correction decision 0015 makes the mitigation for a silent wrong
/// inference.
///
/// Three things are pinned, and the third is the one that is not merely
/// cosmetic. That a box says so and can be expanded into rows that export
/// separately. That the kind is readable on every row and changeable on every
/// row. And that changing it CLEARS the match rather than writing a new word
/// beside the old one -- a corrected kind is a different catalogue, and a
/// relabel would buy a right word and a wrong match.
///
/// No network: the screen is given no resolver, and nothing here constructs a
/// client. Every fixture is invented, catalogue ids included -- this project
/// has called no catalogue that answers per season, so a real id would be a
/// claim nobody has measured.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelfscan_app/export_saver.dart';
import 'package:shelfscan_app/screens/review_screen.dart';
import 'package:shelfscan_core/shelfscan_core.dart';

class FakeExportSaver extends ExportSaver {
  final List<({String suggestedName, String extension, String content})> calls =
      [];

  @override
  Future<SaveOutcome> save({
    required String suggestedName,
    required String extension,
    required String content,
  }) async {
    calls.add((
      suggestedName: suggestedName,
      extension: extension,
      content: content
    ));
    return const SaveOutcome.savedToFile(r'C:\out\shelf.csv');
  }
}

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

ResolvedGame _row(
  String rawTitle, {
  WorkKind workKind = WorkKind.game,
  List<CatalogueEntry> parts = const [],
  Candidate? best,
  ReviewStatus status = ReviewStatus.pending,
}) =>
    ResolvedGame(
      detection: Detection(
        rawTitle: rawTitle,
        mediaType: MediaType.disc,
        confidence: 1.0,
        sourcePhoto: 'shelf1.jpg',
        platformHint: 'PS4',
        workKind: workKind,
      ),
      best: best,
      parts: parts,
      status: status,
    );

ReviewDocument _doc(List<ResolvedGame> games) => ReviewDocument(
      version: 1,
      created: '2026-01-01T00:00:00Z',
      photos: const ['shelf1.jpg'],
      games: games,
    );

Future<void> _pump(WidgetTester tester, ReviewDocument doc,
        [ExportSaver? saver]) =>
    tester.pumpWidget(MaterialApp(
      home: ReviewScreen(
          document: doc, saver: saver ?? FakeExportSaver(), keyless: true),
    ));

Future<void> _openSheet(WidgetTester tester, String rawTitle) async {
  await tester.tap(find.text(rawTitle));
  await tester.pumpAndSettle();
}

Future<void> _tapExport(WidgetTester tester, String target) async {
  await tester.tap(find.byKey(const Key('export-primary')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key('export-sheet-$target')));
  await tester.pumpAndSettle();
}

void main() {
  group('a row that maps to several', () {
    testWidgets('says so, and an ordinary row does not', (tester) async {
      await _pump(
          tester,
          _doc([
            _row('LANTERN COAST BOX',
                workKind: WorkKind.animation, parts: _seasons.toList()),
            _row('HOLLOW PINE 2'),
          ]));

      expect(find.textContaining('maps to 3 entries -- tap to expand'),
          findsOneWidget);
    });

    testWidgets('offers the expansion in its sheet, naming the parts',
        (tester) async {
      await _pump(
          tester,
          _doc([
            _row('LANTERN COAST BOX',
                workKind: WorkKind.animation, parts: _seasons.toList()),
          ]));
      await _openSheet(tester, 'LANTERN COAST BOX');

      expect(find.text('Expand into 3 items'), findsOneWidget);
      expect(
          find.textContaining('This box maps to 3 catalogue entries'),
          findsOneWidget);
      // The ordinal is the catalogue's, and it is shown because the person
      // deciding is matching the list against what is printed on the box.
      expect(find.textContaining('1. Lantern Coast Chronicle'), findsOneWidget);
    });

    testWidgets('expanding replaces the one row with N, in its place',
        (tester) async {
      final doc = _doc([
        _row('LANTERN COAST BOX',
            workKind: WorkKind.animation, parts: _seasons.toList()),
        _row('HOLLOW PINE 2'),
      ]);
      await _pump(tester, doc);
      await _openSheet(tester, 'LANTERN COAST BOX');
      await tester.tap(find.byKey(const Key('expand-parts')));
      await tester.pumpAndSettle();

      expect(doc.games, hasLength(4));
      expect([for (final game in doc.games) game.detection.rawTitle], [
        'Lantern Coast Chronicle',
        'Lantern Coast Chronicle: Ebb',
        'Lantern Coast Chronicle: Flood',
        'HOLLOW PINE 2',
      ]);
      expect(find.text('LANTERN COAST BOX'), findsNothing);
      expect(find.text('Lantern Coast Chronicle: Flood'), findsOneWidget);
      // Each is now one thing, so none of them still offers to expand.
      expect(find.textContaining('tap to expand'), findsNothing);
    });

    testWidgets('each expanded part exports on its own identity',
        (tester) async {
      final doc = _doc([
        _row('LANTERN COAST BOX',
            workKind: WorkKind.animation, parts: _seasons.toList()),
      ]);
      final saver = FakeExportSaver();
      await _pump(tester, doc, saver);
      await _openSheet(tester, 'LANTERN COAST BOX');
      await tester.tap(find.byKey(const Key('expand-parts')));
      await tester.pumpAndSettle();

      for (var i = 0; i < 3; i++) {
        await tester.tap(find.descendant(
            of: find.byKey(Key('review-row-$i')),
            matching: find.byIcon(Icons.check_circle)));
        await tester.pumpAndSettle();
      }
      expect(find.text('Review (3/3 to export)'), findsOneWidget);

      await _tapExport(tester, 'csv');

      final csv = saver.calls.single.content;
      expect(csv, contains('Lantern Coast Chronicle,'));
      expect(csv, contains('Lantern Coast Chronicle: Ebb,'));
      expect(csv, contains('Lantern Coast Chronicle: Flood,'));
      expect(csv, isNot(contains('LANTERN COAST BOX')));
    });
  });

  group('the kind is visible and correctable', () {
    testWidgets('a row states a kind that is not the default', (tester) async {
      await _pump(tester,
          _doc([_row('LANTERN COAST', workKind: WorkKind.animation)]));

      // The label, and never the wire value: `animation` is the word the
      // export file uses and the row is read by the person holding the box.
      expect(find.textContaining('Anime'), findsOneWidget);
      expect(find.textContaining('animation'), findsNothing);
    });

    testWidgets('a game row stays quiet, as every document so far is games',
        (tester) async {
      await _pump(tester, _doc([_row('HOLLOW PINE 2')]));

      // Silent on the row and readable in the sheet: the same rule
      // `Detection.toJson` writes `work_kind` by.
      expect(find.textContaining('Game'), findsNothing);
      await _openSheet(tester, 'HOLLOW PINE 2');
      expect(find.text('Kind of work'), findsOneWidget);
      expect(find.text('Game'), findsOneWidget);
      expect(find.text('Film'), findsOneWidget);
      expect(find.text('Anime'), findsOneWidget);
    });

    testWidgets('the sheet marks the kind the row is currently on',
        (tester) async {
      await _pump(tester,
          _doc([_row('LANTERN COAST', workKind: WorkKind.animation)]));
      await _openSheet(tester, 'LANTERN COAST');

      Icon iconOf(String kind) => tester.widget<Icon>(find.descendant(
          of: find.byKey(Key('work-kind-$kind')), matching: find.byType(Icon)));
      expect(iconOf('animation').icon, Icons.radio_button_checked);
      expect(iconOf('game').icon, Icons.radio_button_unchecked);
    });

    testWidgets('changing it clears the match and marks the row for a new one',
        (tester) async {
      final doc = _doc([
        _row('LANTERN COAST',
            best: Candidate(
              externalId: 'igdb:510003',
              title: 'Lantern Coast Chronicle',
              platformId: 6,
              platformName: 'PC (Microsoft Windows)',
              score: 0.95,
            ),
            status: ReviewStatus.approved),
      ]);
      await _pump(tester, doc);
      expect(find.text('Lantern Coast Chronicle'), findsOneWidget);

      await _openSheet(tester, 'Lantern Coast Chronicle');
      await tester.tap(find.byKey(const Key('work-kind-animation')));
      await tester.pumpAndSettle();

      final row = doc.games.single;
      expect(row.detection.workKind, WorkKind.animation);
      // Not a relabel: the match it had was against the wrong catalogue.
      expect(row.best, isNull);
      expect(row.needsReresolution, isTrue);
      expect(row.status, ReviewStatus.pending);

      // And the screen says both, so a match that just disappeared is
      // explained rather than merely gone.
      expect(find.text('Lantern Coast Chronicle'), findsNothing);
      expect(find.text('LANTERN COAST'), findsOneWidget);
      expect(find.textContaining('kind corrected -- will be looked up again'),
          findsOneWidget);
      expect(find.textContaining('Anime'), findsOneWidget);
    });

    testWidgets('choosing the kind it already has keeps the match',
        (tester) async {
      final doc = _doc([
        _row('HOLLOW PINE 2',
            best: Candidate(
              externalId: 'igdb:510004',
              title: 'Hollow Pine 2',
              platformId: 167,
              platformName: 'PlayStation 5',
              score: 0.99,
            ),
            status: ReviewStatus.approved),
      ]);
      await _pump(tester, doc);
      await _openSheet(tester, 'Hollow Pine 2');
      await tester.tap(find.byKey(const Key('work-kind-game')));
      await tester.pumpAndSettle();

      expect(doc.games.single.best, isNotNull);
      expect(doc.games.single.needsReresolution, isFalse);
      expect(doc.games.single.status, ReviewStatus.approved);
    });
  });
}
