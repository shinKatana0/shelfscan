/// What the screen says when the chosen target carries none of the marked
/// rows -- one test per target, each asserting the whole sentence (T-0462).
///
/// Whole and not `textContaining('Nothing to export')`, which is what the two
/// existing assertions of this branch use: the defect was a true-sounding
/// sentence about the wrong target, and a substring finder passes it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelfscan_app/export_saver.dart';
import 'package:shelfscan_app/screens/review_screen.dart';
import 'package:shelfscan_core/shelfscan_core.dart';

/// Records instead of saving, so a test that reaches the backend by mistake
/// says so rather than opening a dialog.
class _FakeSaver extends ExportSaver {
  final List<String> saved = [];

  @override
  Future<SaveOutcome> save({
    required String suggestedName,
    required String extension,
    required String content,
  }) async {
    saved.add(suggestedName);
    return const SaveOutcome.savedToFile(r'C:\out\shelf.bin');
  }
}

ResolvedGame _row(String rawTitle, {Candidate? best}) => ResolvedGame(
      detection: Detection(
        rawTitle: rawTitle,
        mediaType: MediaType.disc,
        confidence: 1.0,
        sourcePhoto: 'shelf1.jpg',
        platformHint: 'PS4',
        workKind: WorkKind.game,
      ),
      best: best,
      candidates: const [],
      status: ReviewStatus.approved,
    );

Candidate _match() => Candidate(
      externalId: 'igdb:41',
      title: 'Harrowgate Mire',
      platformId: 410,
      platformName: 'PlayStation 4',
      score: 0.9,
    );

Future<void> _pump(
        WidgetTester tester, ReviewDocument doc, ExportSaver saver) =>
    tester.pumpWidget(MaterialApp(
      home: ReviewScreen(document: doc, saver: saver, photos: const []),
    ));

ReviewDocument _doc(List<ResolvedGame> games) => ReviewDocument(
      version: 1,
      created: '2026-08-13T00:00:00Z',
      photos: const ['shelf1.jpg'],
      games: games,
      unreadable: const [],
    );

/// Bottom bar -> target sheet -> past the drop warning, which every case here
/// raises: a target that carries nothing carries nothing of something.
Future<void> _export(WidgetTester tester, String target) async {
  await tester.tap(find.byKey(const Key('export-primary')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key('export-sheet-$target')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('export-drop-confirm')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('tonkatsu says the rows have no match, because its items are ids',
      (tester) async {
    final saver = _FakeSaver();
    await _pump(tester, _doc([_row('HARROWGATE MIRE')]), saver);

    await _export(tester, 'tonkatsu');

    expect(saver.saved, isEmpty);
    expect(find.text('Nothing to export: no approved item has a resolved '
        'match.'), findsOneWidget);
  });

  testWidgets('csv names the title as well as the match, because it needs '
      'either', (tester) async {
    final saver = _FakeSaver();
    // Blank after trimming and nothing matched: the only row csv refuses.
    await _pump(tester, _doc([_row('   ')]), saver);

    await _export(tester, 'csv');

    expect(saver.saved, isEmpty);
    expect(find.text('Nothing to export: no approved item has a title or a '
        'match for csv to write.'), findsOneWidget);
  });

  testWidgets('cards says the rows were carried, not that they were unmatched',
      (tester) async {
    final saver = _FakeSaver();
    // The inverse case: a matched row is exactly what `.xcoll` takes, so the
    // target whose subject is the leftovers has none.
    await _pump(tester, _doc([_row('HARROWGATE MIRE', best: _match())]), saver);

    await _export(tester, 'tonkatsu-cards');

    expect(saver.saved, isEmpty);
    expect(
        find.text('Nothing to export: no approved item was left over for '
            'cards -- export .xcoll instead.'),
        findsOneWidget);
    // The sentence it used to say, and the one it must not: on this document
    // every row HAS a match.
    expect(find.textContaining('no approved item has a resolved match'),
        findsNothing);
  });
}
