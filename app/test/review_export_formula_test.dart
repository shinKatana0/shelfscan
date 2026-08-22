/// The app's half of the warning at the point of export (T-0187).
///
/// The CLI prints a note after `Exported N of M`; the app's export ends in a
/// save dialog or a share sheet, so it says the same thing on the SnackBar
/// that already reports the outcome, with the cell names behind an action.
/// Nothing here opens a real dialog: the screen takes an [ExportSaver] and
/// this file injects a fake, the same seam `review_screen_test.dart` uses.
///
/// The silence is pinned as hard as the warning. An ordinary export must be
/// exactly what it was before this task -- a warning that fires always is one
/// people learn to ignore.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelfscan_app/export_saver.dart';
import 'package:shelfscan_app/screens/review_screen.dart';
import 'package:shelfscan_core/shelfscan_core.dart';

class _FakeSaver extends ExportSaver {
  _FakeSaver({this.outcome = const SaveOutcome.savedToFile(r'C:\out\shelf.csv')});

  final SaveOutcome outcome;
  final List<String> contents = [];

  @override
  Future<SaveOutcome> save({
    required String suggestedName,
    required String extension,
    required String content,
  }) async {
    contents.add(content);
    return outcome;
  }
}

/// A row off a games folder: `source_entry` is the name on disk, unedited,
/// which is the column T-0185 measured the ordinary case into.
ResolvedGame _fromFolder(String title, String entry) => ResolvedGame(
      detection: Detection(
        rawTitle: title,
        mediaType: MediaType.unknown,
        confidence: 1.0,
        sourcePhoto: '',
        sourceEntry: entry,
        origin: DetectionOrigin.filename,
      ),
      status: ReviewStatus.approved,
    );

ReviewDocument _doc(List<ResolvedGame> games) => ReviewDocument(
      version: 1,
      created: '2026-08-13T00:00:00Z',
      photos: const [],
      games: games,
    );

Future<void> _pump(WidgetTester tester, ReviewDocument doc, ExportSaver saver) =>
    tester.pumpWidget(MaterialApp(
      home: ReviewScreen(document: doc, saver: saver),
    ));

Future<void> _tapExport(WidgetTester tester, String target) async {
  await tester.tap(find.byKey(const Key('export-primary')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key('export-sheet-$target')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a saved csv with a formula cell says so, and counts it',
      (tester) async {
    final doc = _doc([
      _fromFolder('Duskhollow', 'Duskhollow'),
      _fromFolder('Tactics', '-Tactics'),
    ]);
    await _pump(tester, doc, _FakeSaver());

    await _tapExport(tester, 'csv');

    expect(
        find.textContaining(r'Saved 2 items to C:\out\shelf.csv'), findsOneWidget);
    expect(find.textContaining('1 cell begins with =, +, - or @'), findsOneWidget);
    expect(find.textContaining('a spreadsheet reads as a formula'),
        findsOneWidget);
    expect(find.byKey(const Key('export-formula-cells')), findsOneWidget);
  });

  testWidgets('the action names the cell and gives a remedy that exists',
      (tester) async {
    final doc = _doc([_fromFolder('Tactics', '-Tactics')]);
    await _pump(tester, doc, _FakeSaver());
    await _tapExport(tester, 'csv');

    await tester.tap(find.byKey(const Key('export-formula-cells')));
    await tester.pumpAndSettle();

    expect(find.text('A spreadsheet reads these cells as formulas'),
        findsOneWidget);
    expect(find.textContaining('source_entry: -Tactics'), findsOneWidget);
    // The remedy README gives, and the reason it is a remedy: the documented
    // consumer evaluates nothing.
    expect(find.textContaining('An import dialog is not affected'),
        findsOneWidget);
    expect(find.textContaining('columns set to Text'), findsOneWidget);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('A spreadsheet reads these cells as formulas'),
        findsNothing);
  });

  testWidgets('an ordinary export is exactly what it was', (tester) async {
    final doc = _doc([
      _fromFolder('Duskhollow', 'Duskhollow'),
      _fromFolder('Frost Wake', 'Frost Wake'),
    ]);
    await _pump(tester, doc, _FakeSaver());

    await _tapExport(tester, 'csv');

    expect(find.text(r'Saved 2 items to C:\out\shelf.csv'), findsOneWidget);
    expect(find.textContaining('formula'), findsNothing);
    expect(find.byKey(const Key('export-formula-cells')), findsNothing);
  });

  testWidgets('a cancelled export says nothing about the file it did not write',
      (tester) async {
    final doc = _doc([_fromFolder('Tactics', '-Tactics')]);
    final saver = _FakeSaver(outcome: const SaveOutcome.cancelled());
    await _pump(tester, doc, saver);

    await _tapExport(tester, 'csv');

    expect(find.text('Export cancelled.'), findsOneWidget);
    expect(find.textContaining('formula'), findsNothing);
  });

  testWidgets('a shared file reports it too -- Android has no path to name',
      (tester) async {
    final doc = _doc([_fromFolder('Tactics', '-Tactics')]);
    await _pump(tester, doc, _FakeSaver(outcome: const SaveOutcome.shared('/tmp/x')));

    await _tapExport(tester, 'csv');

    expect(find.textContaining('Shared 1 item as shelf.csv'), findsOneWidget);
    expect(find.textContaining('1 cell begins with'), findsOneWidget);
  });

  testWidgets('the same rows exported to .xcoll say nothing', (tester) async {
    final doc = _doc([
      ResolvedGame(
        detection: Detection(
          rawTitle: 'Tactics',
          mediaType: MediaType.unknown,
          confidence: 1.0,
          sourcePhoto: '',
          sourceEntry: '-Tactics',
          origin: DetectionOrigin.filename,
        ),
        best: Candidate(
          igdbId: 7,
          title: 'Tactics',
          platformId: 6,
          platformName: 'PC (Microsoft Windows)',
          score: 1.0,
        ),
        status: ReviewStatus.approved,
      ),
    ]);
    await _pump(tester, doc, _FakeSaver());

    await _tapExport(tester, 'tonkatsu');

    expect(find.text(r'Saved 1 item to C:\out\shelf.csv'), findsOneWidget);
    expect(find.textContaining('formula'), findsNothing);
  });
}
