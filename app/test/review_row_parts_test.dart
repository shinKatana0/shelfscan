/// The review screen's answer to "this box maps to several" (T-0163), and to
/// the kind correction decision 0015 makes the mitigation for a silent wrong
/// inference.
///
/// Five things are pinned, and the last three are the ones that are not merely
/// cosmetic. That a box says so and can be expanded into rows that export
/// separately. That the kind is readable on every row and changeable on every
/// row. That changing it CLEARS the match rather than writing a new word
/// beside the old one -- a corrected kind is a different catalogue, and a
/// relabel would buy a right word and a wrong match. That neither the row
/// nor the sheet promises the lookup that would replace it, because there is
/// none: nothing reads `needsReresolution`, no screen re-runs the resolver
/// over an existing row, and the app writes no `review.json` for the CLI to
/// resolve (T-0311). And that the corrected row stops asking for a tap that
/// cannot move it: under a film kind `.xcoll` takes none of the candidates
/// the games catalogue left on the row, so the invitation was a second
/// promise the row could not keep (T-0313). Each of those three is pinned in
/// the negative too -- a promise is the one false statement no later moment
/// disproves.
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
  List<Candidate> candidates = const [],
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
      candidates: candidates,
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
        {ExportSaver? saver, bool keyless = true}) =>
    tester.pumpWidget(MaterialApp(
      home: ReviewScreen(
          document: doc, saver: saver ?? FakeExportSaver(), keyless: keyless),
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
      await _pump(tester, doc, saver: saver);
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
      expect(find.textContaining('kind corrected -- nothing looks it up'),
          findsOneWidget);
      expect(find.textContaining('Anime'), findsOneWidget);
      // The clause said `will be looked up again` until T-0311 and nothing
      // ever did (`needsReresolution` has no reader). Pinned in the negative
      // as well as the positive, because the defect is a promise: it reads
      // like the row is mid-flight, and no later moment disproves it.
      expect(find.textContaining('looked up again'), findsNothing);
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

    testWidgets('the sheet states the cost before the tap, not after',
        (tester) async {
      await _pump(tester, _doc([_row('HOLLOW PINE 2')]));
      await _openSheet(tester, 'HOLLOW PINE 2');

      // The one place a person reads about the correction BEFORE making it,
      // so it is where the whole cost belongs: the match goes and nothing
      // brings one back. It said `asks again` until T-0311, which invited
      // the tap on the strength of a lookup that does not exist.
      expect(
          find.textContaining(
              'clears the match, and nothing looks the row up again'),
          findsOneWidget);
      expect(find.textContaining('asks again'), findsNothing);
    });

    testWidgets('a keyed run says the same thing, beside what it cannot export',
        (tester) async {
      final doc = _doc([
        _row('HOLLOW PINE 2',
            best: Candidate(
              externalId: 'igdb:510005',
              title: 'Hollow Pine 2',
              platformId: 167,
              platformName: 'PlayStation 5',
              score: 0.99,
            ),
            status: ReviewStatus.approved),
      ]);
      await _pump(tester, doc, keyless: false);
      await _openSheet(tester, 'Hollow Pine 2');
      await tester.tap(find.byKey(const Key('work-kind-movie')));
      await tester.pumpAndSettle();

      // The run that HAD a lookup is the one where the promise was most
      // believable, and it is the case the keyless fixtures above cannot
      // reach: there the frame and the `.xcoll` clause are suppressed for the
      // whole run (T-0230), so this row carries the clause alone.
      expect(find.textContaining('kind corrected -- nothing looks it up'),
          findsOneWidget);
      expect(find.textContaining('looked up again'), findsNothing);
      expect(find.textContaining('not in .xcoll'), findsOneWidget);
    });

    // The second promise the same row used to make, and the one that survived
    // T-0311 (T-0313). The correction leaves the candidates the games
    // catalogue produced, and `.xcoll` will not take any of them under a film
    // kind -- so the row asked for a tap, the person gave it, and the row
    // came back saying exactly what it had said before. Pinned on the keyed
    // run for the reason above: it is the only mode where this clause shows
    // at all.
    testWidgets('a corrected film row asks for no tap, and says csv has it',
        (tester) async {
      final doc = _doc([
        _row('HARBOUR LANTERN',
            best: Candidate(
              externalId: 'igdb:510006',
              title: 'Harbour Lantern',
              platformId: 6,
              platformName: 'PC (Microsoft Windows)',
              score: 0.93,
            ),
            candidates: [
              Candidate(
                externalId: 'igdb:510006',
                title: 'Harbour Lantern',
                platformId: 6,
                platformName: 'PC (Microsoft Windows)',
                score: 0.93,
              ),
            ],
            status: ReviewStatus.approved),
      ]);
      await _pump(tester, doc, keyless: false);
      await _openSheet(tester, 'Harbour Lantern');
      await tester.tap(find.byKey(const Key('work-kind-movie')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Film'), findsOneWidget);
      expect(find.textContaining('not in .xcoll -- csv carries it'),
          findsOneWidget);
      // In the negative, because the defect was the invitation itself: the
      // row still holds the candidate it would have offered.
      expect(find.textContaining('tap to pick a match'), findsNothing);
      expect(doc.games.single.candidates, hasLength(1));
    });
  });
}
