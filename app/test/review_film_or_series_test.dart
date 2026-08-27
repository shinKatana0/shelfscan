/// The extra question, and the rows that are never asked it (T-0368).
///
/// The owner ruled that the person decides at review and just has to decide a
/// bit more for anime -- the same answer they gave about the row unit for a
/// box: the party holding the object decides. Tonkatsu states film-or-series
/// for an anime in `platform_id`, so `.xcoll` cannot take such a row until
/// somebody answers, and this screen is where the somebody is.
///
/// **Half of what is pinned here is the negative half, and it is the half the
/// requirement was written around.** A game row and a film row answer nothing
/// new: their sheet is the three kinds it has always been, with no fourth
/// control and no new sentence, and their row text does not move. A screen
/// that asked everybody about series to serve anime would tax the common path
/// for the rare one, which is the opposite of what T-0311, T-0313, T-0317,
/// T-0337 and T-0340 each spent a task doing.
///
/// The row's own clause did not change by one character either. `not in
/// .xcoll -- film or series?` was written by T-0290 for a question nothing
/// could answer; the row was tappable all along, so what this task added is
/// the answer behind the tap and not a word in front of it.
///
/// No network: the screen is given no resolver. Every fixture is invented.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelfscan_app/export_saver.dart';
import 'package:shelfscan_app/screens/review_screen.dart';
import 'package:shelfscan_core/shelfscan_core.dart';

class _Saver extends ExportSaver {
  @override
  Future<SaveOutcome> save({
    required String suggestedName,
    required String extension,
    required String content,
  }) async =>
      const SaveOutcome.savedToFile(r'C:\out\shelf.csv');
}

ResolvedGame _row(
  String rawTitle, {
  WorkKind workKind = WorkKind.game,
  Candidate? best,
  List<Candidate> candidates = const [],
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
      status: ReviewStatus.pending,
    );

Candidate _tmdb(int id, String title) => Candidate(
      externalId: 'tmdb:$id',
      title: title,
      platformId: null,
      platformName: null,
      score: 0.93,
    );

ReviewDocument _doc(List<ResolvedGame> games) => ReviewDocument(
      version: 1,
      created: '2026-08-24T00:00:00Z',
      photos: const ['shelf1.jpg'],
      games: games,
    );

Future<void> _pump(WidgetTester tester, ReviewDocument doc,
        {bool keyless = false}) =>
    tester.pumpWidget(MaterialApp(
      home: ReviewScreen(document: doc, saver: _Saver(), keyless: keyless),
    ));

Future<void> _openSheet(WidgetTester tester, String text) async {
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

IconData _mark(WidgetTester tester, String key) => tester
    .widget<Icon>(find.descendant(
        of: find.byKey(Key('work-kind-$key')), matching: find.byType(Icon)))
    .icon!;

void main() {
  group('the rows that are asked nothing new', () {
    testWidgets('a game row keeps the three kinds and gains no control',
        (tester) async {
      await _pump(tester, _doc([_row('HOLLOW PINE 2')]));
      await _openSheet(tester, 'HOLLOW PINE 2');

      expect(find.text('Kind of work'), findsOneWidget);
      expect(find.text('Game'), findsOneWidget);
      expect(find.text('Film'), findsOneWidget);
      expect(find.text('Anime'), findsOneWidget);
      // The whole of the "must not happen", in the negative, which is the
      // only direction that can catch it: nothing about series reaches a
      // sheet that is not an anime's.
      expect(find.text('Film or series'), findsNothing);
      expect(find.byKey(const Key('work-kind-animationFilm')), findsNothing);
      expect(find.byKey(const Key('work-kind-animationSeries')), findsNothing);
    });

    testWidgets('a film row is asked nothing new either', (tester) async {
      await _pump(
          tester, _doc([_row('PALE ANCHOR', workKind: WorkKind.movie)]));
      await _openSheet(tester, 'PALE ANCHOR');

      expect(find.text('Film or series'), findsNothing);
      expect(find.byKey(const Key('work-kind-animationSeries')), findsNothing);
    });

    testWidgets('and no row of either kind gains text', (tester) async {
      await _pump(
          tester,
          _doc([
            _row('HOLLOW PINE 2'),
            _row('PALE ANCHOR',
                workKind: WorkKind.movie, best: _tmdb(770010, 'Pale Anchor')),
          ]));

      expect(find.textContaining('series'), findsNothing);
      expect(find.textContaining('Anime'), findsNothing);
    });
  });

  group('the question, on the row that is asked it', () {
    testWidgets('an anime sheet offers film and series, neither marked yet',
        (tester) async {
      await _pump(tester,
          _doc([_row('TIDEWRACK LAMENT', workKind: WorkKind.animation)]));
      await _openSheet(tester, 'TIDEWRACK LAMENT');

      expect(find.text('Film or series'), findsOneWidget);
      // Nothing marked is the honest rendering of a question nobody has
      // answered. A default here would be the `0` the exporter refuses to
      // write, one screen earlier.
      expect(_mark(tester, 'animationFilm'), Icons.radio_button_unchecked);
      expect(_mark(tester, 'animationSeries'), Icons.radio_button_unchecked);
    });

    testWidgets('answering it sets the kind', (tester) async {
      final doc =
          _doc([_row('TIDEWRACK LAMENT', workKind: WorkKind.animation)]);
      await _pump(tester, doc);
      await _openSheet(tester, 'TIDEWRACK LAMENT');
      await tester.tap(find.byKey(const Key('work-kind-animationSeries')));
      await tester.pumpAndSettle();

      expect(doc.games.single.detection.workKind, WorkKind.animationSeries);
      // The label and never the wire value: `animation` is Tonkatsu's word
      // for the file and nobody's word for the thing on the shelf.
      expect(find.textContaining('Anime series'), findsOneWidget);
      expect(find.textContaining('animation'), findsNothing);
    });

    testWidgets('an answered row marks its answer, and still reads as Anime',
        (tester) async {
      await _pump(
          tester,
          _doc([
            _row('TIDEWRACK LAMENT', workKind: WorkKind.animationSeries)
          ]));
      await _openSheet(tester, 'TIDEWRACK LAMENT');

      expect(_mark(tester, 'animationSeries'), Icons.radio_button_checked);
      expect(_mark(tester, 'animationFilm'), Icons.radio_button_unchecked);
      // The kind list is the three it always was, and the refinement marks
      // the group it refines rather than leaving it blank.
      expect(_mark(tester, 'animation'), Icons.radio_button_checked);
      expect(_mark(tester, 'game'), Icons.radio_button_unchecked);
    });

    testWidgets('tapping Anime on an answered row throws nothing away',
        (tester) async {
      // The failure this guards is silent and expensive: the kind tile pops
      // the GROUP, so without the guard an answered row would be walked back
      // to the unanswered kind and lose its match, on a tap that looks like
      // tapping the value the row is already on.
      final doc = _doc([
        _row('TIDEWRACK LAMENT',
            workKind: WorkKind.animationSeries,
            best: _tmdb(770001, 'Tidewrack Lament')),
      ]);
      await _pump(tester, doc);
      await _openSheet(tester, 'Tidewrack Lament');
      await tester.tap(find.byKey(const Key('work-kind-animation')));
      await tester.pumpAndSettle();

      final row = doc.games.single;
      expect(row.detection.workKind, WorkKind.animationSeries);
      expect(row.best, isNotNull);
      expect(row.needsReresolution, isFalse);
    });

    testWidgets('changing the answer clears the match, as any kind does',
        (tester) async {
      // Two different TMDB searches, so a match taken under one is not an
      // answer under the other -- and the row explains the match that
      // disappeared rather than merely losing it.
      final doc = _doc([
        _row('TIDEWRACK LAMENT',
            workKind: WorkKind.animationSeries,
            best: _tmdb(770001, 'Tidewrack Lament')),
      ]);
      await _pump(tester, doc);
      await _openSheet(tester, 'Tidewrack Lament');
      await tester.tap(find.byKey(const Key('work-kind-animationFilm')));
      await tester.pumpAndSettle();

      expect(doc.games.single.best, isNull);
      expect(find.textContaining('kind corrected -- nothing looks it up'),
          findsOneWidget);
    });
  });

  group('what the row says about it', () {
    testWidgets('an unanswered anime row still asks the question',
        (tester) async {
      await _pump(
          tester,
          _doc([
            _row('TIDEWRACK LAMENT',
                workKind: WorkKind.animation,
                best: _tmdb(770001, 'Tidewrack Lament')),
          ]));

      expect(find.textContaining('not in .xcoll -- film or series?'),
          findsOneWidget);
      expect(find.textContaining('tap to pick a match'), findsNothing);
    });

    testWidgets('an answered, matched anime row says nothing at all',
        (tester) async {
      // The row exports now, so every one of the three refusal clauses is
      // wrong about it. This is what the coupled exporter change buys, seen
      // from the screen.
      await _pump(
          tester,
          _doc([
            _row('TIDEWRACK LAMENT',
                workKind: WorkKind.animationSeries,
                best: _tmdb(770001, 'Tidewrack Lament')),
          ]));

      expect(find.textContaining('not in .xcoll'), findsNothing);
    });

    testWidgets('an answered anime row with no match asks for the tap',
        (tester) async {
      // It is refused for the ordinary reason now, so it takes the ordinary
      // clause -- and the one candidate on it is one `.xcoll` would take.
      await _pump(
          tester,
          _doc([
            _row('TIDEWRACK LAMENT',
                workKind: WorkKind.animationSeries,
                candidates: [_tmdb(770002, 'Tidewrack Lament')]),
          ]));

      expect(find.textContaining('not in .xcoll -- tap to pick a match'),
          findsOneWidget);
      expect(find.textContaining('film or series?'), findsNothing);
    });
  });
}
