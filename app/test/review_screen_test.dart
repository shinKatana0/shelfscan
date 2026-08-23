/// Widget tests for the review screen.
///
/// No real save dialog or share sheet is ever opened: the screen takes an
/// [ExportSaver] and these tests inject a fake that records the call.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelfscan_app/export_saver.dart';
import 'package:shelfscan_app/main.dart' show appSeedColor;
import 'package:shelfscan_app/screens/review_screen.dart';
import 'package:shelfscan_core/shelfscan_core.dart';

/// A real 1x1 PNG. Decodable, so `Image.memory` never throws inside a test;
/// its size is irrelevant because nothing here asserts on pixels.
final _pixel = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQ'
    'DwAEhQGAhKmMIQAAAABJRU5ErkJggg==');

PhotoInput _photo(String name) => PhotoInput(name: name, bytes: _pixel);

class FakeExportSaver extends ExportSaver {
  FakeExportSaver({this.outcome = const SaveOutcome.savedToFile(r'C:\out\shelf.csv')});

  final SaveOutcome outcome;
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
    return outcome;
  }
}

Candidate _candidate(int id, String title,
        {String platform = 'PlayStation 4',
        double score = 0.7,
        String? matchedAlternativeName}) =>
    Candidate(
      externalId: 'igdb:$id',
      title: title,
      platformId: id * 10,
      platformName: platform,
      score: score,
      matchedAlternativeName: matchedAlternativeName,
    );

ResolvedGame _game(
  String rawTitle, {
  Candidate? best,
  List<Candidate> candidates = const [],
  ReviewStatus status = ReviewStatus.pending,
  String sourcePhoto = 'shelf1.jpg',
  WorkKind workKind = WorkKind.game,
}) =>
    ResolvedGame(
      detection: Detection(
        rawTitle: rawTitle,
        mediaType: MediaType.disc,
        confidence: 1.0,
        sourcePhoto: sourcePhoto,
        platformHint: 'PS4',
        workKind: workKind,
      ),
      best: best,
      candidates: candidates,
      status: status,
    );

ReviewDocument _doc(
  List<ResolvedGame> games, {
  List<UnreadSpineReport> unreadable = const [],
  List<String> photos = const ['shelf1.jpg'],
}) =>
    ReviewDocument(
      version: 1,
      created: '2026-08-13T00:00:00Z',
      photos: photos,
      games: games,
      unreadable: unreadable,
    );

/// Stands in for a configured IGDB. Extends [SkipResolver] so the inherited
/// refusing http client guarantees no network call can escape the test.
class FakeResolver extends SkipResolver {
  FakeResolver({this.candidates = const [], this.fails = false});

  final List<Candidate> candidates;
  final bool fails;
  final List<Detection> seen = [];

  @override
  int get maxRetries => 0; // no backoff sleeps inside a widget test

  @override
  Future<ResolvedGame> process(Detection task) async {
    seen.add(task);
    if (fails) throw StateError('IGDB is down');
    return ResolvedGame(
      detection: task,
      best: candidates.isEmpty ? null : candidates.first,
      candidates: candidates,
    );
  }
}

Future<void> _pump(
  WidgetTester tester,
  ReviewDocument doc,
  ExportSaver saver, {
  ResolverWorker? resolver,
  List<PhotoInput> photos = const [],
  ThemeData? theme,
  bool keyless = false,
}) async =>
    tester.pumpWidget(MaterialApp(
      theme: theme,
      home: ReviewScreen(
        document: doc,
        saver: saver,
        resolver: resolver,
        keyless: keyless,
        photos: photos,
      ),
    ));

/// Widen the test window past the [ReviewScreen] breakpoint for one test.
void _resize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

double _top(WidgetTester tester, String key) =>
    tester.getTopLeft(find.byKey(Key(key))).dy;

/// Which rows are framed, by their index in `document.games`.
List<int> _frames(WidgetTester tester) => tester
    .widgetList<DecoratedBox>(find.byType(DecoratedBox))
    .map((box) => (box.key as ValueKey<String>?)?.value)
    .whereType<String>()
    .where((key) => key.startsWith('unmatched-frame-'))
    .map((key) => int.parse(key.split('-').last))
    .toList()
  ..sort();

/// Every string the screen is rendering, in tree order.
List<String> _strings(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((text) => text.data ?? '')
    .toList();

/// Open the add dialog, fill it in, confirm.
Future<void> _addItem(
  WidgetTester tester, {
  required String title,
  String platform = '',
  String? mediaType,
  Key trigger = const Key('add-manual-item'),
}) async {
  await tester.tap(find.byKey(trigger));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('manual-title')), title);
  if (platform.isNotEmpty) {
    await tester.enterText(find.byKey(const Key('manual-platform')), platform);
  }
  if (mediaType != null) {
    await tester.tap(find.text(mediaType));
  }
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('manual-add')));
  await tester.pumpAndSettle();
}

/// Text inside the open dialog only -- the rows behind it carry the same
/// titles, so an unscoped finder cannot tell the two apart.
Finder _inDialog(String text) => find.descendant(
    of: find.byType(AlertDialog), matching: find.textContaining(text));

/// The one export route left after T-0118: the bottom bar's button, then the
/// target sheet. Requires something marked -- the button is disabled otherwise.
Future<void> _tapExport(WidgetTester tester, String target) async {
  await tester.tap(find.byKey(const Key('export-primary')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key('export-sheet-$target')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('tapping a row lists candidates with the current best marked',
      (tester) async {
    final best = _candidate(1, 'Duskhollow', score: 0.62);
    final doc = _doc([
      _game('DUSKHOLLOWE',
          best: best,
          candidates: [best, _candidate(2, 'Duskhollow: The Old Wardens')]),
    ]);
    await _pump(tester, doc, FakeExportSaver());

    await tester.tap(find.byKey(const Key('review-row-0')));
    await tester.pumpAndSettle();

    expect(find.text('Duskhollow: The Old Wardens'), findsOneWidget);
    expect(find.text('PlayStation 4 - score 62%'), findsOneWidget);
    // Per candidate rather than by counting radios across the sheet: since
    // T-0163 the sheet carries a second one-of-N group, for the kind of work,
    // so a bare count no longer says which candidate is marked -- which is
    // this test's actual claim.
    Icon iconOf(int id) => tester.widget<Icon>(find.descendant(
        of: find.byKey(Key('candidate-igdb:$id')),
        matching: find.byType(Icon)));
    expect(iconOf(1).icon, Icons.radio_button_checked);
    expect(iconOf(2).icon, Icons.radio_button_unchecked);
  });

  testWidgets('a refused platform hint is named on the row (T-0084)',
      (tester) async {
    // The row is unmatched with an empty platform either way; without this
    // it reads as a spine whose console branding was illegible, and the
    // string that caused it lives only in the review file.
    final doc = _doc([
      ResolvedGame(
        detection: Detection.fromJson(<String, dynamic>{
          'raw_title': 'HARBOUR STARBURST',
          'platform_hint': 'SWITCH2 | SWITCH',
          'source_photo': 'shelf1.jpg',
        }),
      ),
    ]);
    await _pump(tester, doc, FakeExportSaver());

    expect(find.textContaining('hint refused: "SWITCH2 | SWITCH"'),
        findsOneWidget);
  });

  group('notes on the row (T-0093)', () {
    testWidgets('a row that carries one shows it, last', (tester) async {
      final doc = _doc([
        ResolvedGame(
          detection: Detection.fromJson(<String, dynamic>{
            'raw_title': 'HOLLOW PINE 2',
            'platform_hint': 'PS5',
            'source_photo': 'shelf1.jpg',
            'notes': 'label worn, partially occluded',
          }),
        ),
      ]);
      await _pump(tester, doc, FakeExportSaver());

      expect(
          find.text('PS5 - raw: "HOLLOW PINE 2" - '
              'not in .xcoll -- tap to pick a match - '
              'note: "label worn, partially occluded"'),
          findsOneWidget);
    });

    testWidgets('a row without one grows no clause', (tester) async {
      await _pump(tester, _doc([_game('HOLLOW PINE 2')]), FakeExportSaver());

      expect(
          find.text('PS4 - raw: "HOLLOW PINE 2" - '
              'not in .xcoll -- tap to pick a match'),
          findsOneWidget);
      expect(find.textContaining('note:'), findsNothing);
    });

    // The only producer measured to exist: qwen2.5vl:7b answers `""` on every
    // control row, so a note on screen is a human's, off `Detection.manual`
    // or the hand-edited document the CLI usage header documents.
    testWidgets('a manual row keeps both its marks and the note',
        (tester) async {
      final doc = _doc([
        ResolvedGame(
          detection: Detection.manual(
            rawTitle: 'Nocturne 5 Gold',
            platformHint: 'PS4',
            notes: 'logo-only spine, no text to read',
          ),
        ),
      ]);
      await _pump(tester, doc, FakeExportSaver());

      expect(find.byIcon(Icons.edit_note), findsOneWidget);
      expect(
          find.text('PS4 - added by hand - '
              'not in .xcoll -- tap to pick a match - '
              'note: "logo-only spine, no text to read"'),
          findsOneWidget);
    });
  });

  /// The owner, after their first export: fewer rows in the file than they had
  /// marked, and nothing on screen said which could not go. A row that cannot
  /// reach
  /// `.xcoll` used to differ only by things not being there.
  group('rows that cannot reach .xcoll (T-0123)', () {
    testWidgets('an unmatched row says so, and says what to do about it',
        (tester) async {
      await _pump(tester, _doc([_game('JP SPINE')]), FakeExportSaver());

      expect(
          find.text('PS4 - raw: "JP SPINE" - '
              'not in .xcoll -- tap to pick a match'),
          findsOneWidget);
    });

    testWidgets('it is said before the row is approved, and after',
        (tester) async {
      await _pump(tester, _doc([_game('JP SPINE')]), FakeExportSaver());

      expect(find.textContaining('not in .xcoll'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.check_circle));
      await tester.pumpAndSettle();
      expect(find.textContaining('not in .xcoll'), findsOneWidget);
    });

    // The clause has two reasons behind it now (T-0290) and only one of them
    // is fixable by tapping. An animation item states film or series in
    // `platform_id`, which nothing upstream of the exporter knows, so the row
    // is dropped WITH a match -- and "tap to pick a match" there would send
    // the user after a remedy that does not exist.
    testWidgets('a kind .xcoll cannot carry says which reason it is',
        (tester) async {
      final doc = _doc([
        _game('LANTERN COAST',
            workKind: WorkKind.animation,
            best: _candidate(1, 'Lantern Coast', score: 0.91)),
      ]);
      await _pump(tester, doc, FakeExportSaver());

      expect(find.textContaining('not in .xcoll -- film or series?'),
          findsOneWidget);
      expect(find.textContaining('tap to pick a match'), findsNothing);
    });

    testWidgets('a row that can export carries no such clause', (tester) async {
      final doc = _doc([
        _game('DUSKHOLLOWE', best: _candidate(1, 'Duskhollow', score: 0.62)),
      ]);
      await _pump(tester, doc, FakeExportSaver());

      expect(find.text('PlayStation 4 - raw: "DUSKHOLLOWE" - score 62%'),
          findsOneWidget);
      expect(find.textContaining('not in .xcoll'), findsNothing);
    });

    testWidgets('the remedy the clause points at removes it', (tester) async {
      final match = _candidate(1, 'Duskhollow', score: 0.62);
      await _pump(tester, _doc([_game('DUSKHOLLOWE', candidates: [match])]),
          FakeExportSaver());

      await tester.tap(find.byKey(const Key('review-row-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('candidate-igdb:1')));
      await tester.pumpAndSettle();

      expect(find.textContaining('not in .xcoll'), findsNothing);
      expect(find.textContaining('score 62%'), findsOneWidget);
    });

    testWidgets('the drop dialog names the rows, and counts the ones it marked',
        (tester) async {
      final doc = _doc([
        _game('JP SPINE', status: ReviewStatus.approved),
        _game('WORN LABEL', status: ReviewStatus.approved),
        _game('MOOR',
            best: _candidate(3, 'MOOR'), status: ReviewStatus.approved),
        _game('LOGO ONLY'),
      ]);
      await _pump(tester, doc, FakeExportSaver());

      // every unmatched row is marked, approved or not ...
      expect(find.textContaining('not in .xcoll'), findsNWidgets(3));

      await _tapExport(tester, 'tonkatsu');

      // ... and the dialog still counts only what an export would drop, which
      // is the two approved ones, by name.
      expect(_inDialog('2 approved items'), findsOneWidget);
      expect(_inDialog('JP SPINE\nWORN LABEL'), findsOneWidget);
      expect(_inDialog('LOGO ONLY'), findsNothing);
    });

    testWidgets('a shelf with more dropped rows than fit lists ten and counts '
        'the rest', (tester) async {
      final doc = _doc([
        for (var i = 0; i < 12; i++)
          _game('SPINE $i', status: ReviewStatus.approved),
      ]);
      await _pump(tester, doc, FakeExportSaver());

      await _tapExport(tester, 'tonkatsu');

      expect(_inDialog('12 approved items'), findsOneWidget);
      expect(_inDialog('SPINE 9'), findsOneWidget);
      expect(_inDialog('SPINE 10'), findsNothing);
      expect(_inDialog('...and 2 more'), findsOneWidget);
    });
  });

  /// The clause the group above added is one of up to seven dash-joined
  /// fragments, and its position moves with which neighbours a row carries --
  /// so there is no fixed place on the row to look for it. The frame is what
  /// makes the group findable without reading (T-0223).
  group("rows that need a real hand are framed (T-0223)", () {
    testWidgets('exactly the rows the clause names carry a frame',
        (tester) async {
      final doc = _doc([
        _game('JP SPINE'),
        _game('MOOR', best: _candidate(3, 'MOOR')),
        _game('WORN LABEL'),
        _game('ARCA', best: _candidate(4, 'Arca')),
      ]);
      await _pump(tester, doc, FakeExportSaver());

      expect(find.textContaining('not in .xcoll'), findsNWidgets(2));
      expect(_frames(tester), [0, 2]);
    });

    testWidgets('a frame appears and goes with the clause, on the same tap',
        (tester) async {
      final match = _candidate(1, 'Duskhollow', score: 0.62);
      await _pump(tester, _doc([_game('DUSKHOLLOWE', candidates: [match])]),
          FakeExportSaver());
      expect(_frames(tester), [0]);

      await tester.tap(find.byKey(const Key('review-row-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('candidate-igdb:1')));
      await tester.pumpAndSettle();

      expect(find.textContaining('not in .xcoll'), findsNothing);
      expect(_frames(tester), isEmpty);
    });

    // Approving a row it cannot carry does not make `.xcoll` able to carry it,
    // and the frame is a property of the data, like the clause (T-0123).
    testWidgets('marking a row neither adds nor removes one', (tester) async {
      await _pump(tester, _doc([_game('JP SPINE')]), FakeExportSaver());

      for (final icon in [Icons.check_circle, Icons.cancel]) {
        await tester.tap(find.byIcon(icon));
        await tester.pumpAndSettle();
        expect(_frames(tester), [0]);
      }
    });

    testWidgets('the frame costs the row no height and no width',
        (tester) async {
      await _pump(tester, _doc([_game('JP SPINE')]), FakeExportSaver());

      // A Container would have spent the border's width as padding on both;
      // the DecoratedBox is the tile's own size, which is what leaves
      // `_wideLayout`'s 380 px subtitle budget derived from the same numbers.
      expect(tester.getSize(find.byKey(const Key('unmatched-frame-0'))),
          tester.getSize(find.byKey(const Key('review-row-0'))));
    });

    // T-0043's rule: colour alone says nothing to a screen reader, so the
    // frame is an addition and never a substitute.
    testWidgets('the row reads identically with the colour removed',
        (tester) async {
      final doc = _doc([
        _game('JP SPINE'),
        _game('MOOR', best: _candidate(3, 'MOOR')),
      ]);

      await _pump(tester, doc, FakeExportSaver());
      final coloured = _strings(tester);

      final scheme = ThemeData(colorSchemeSeed: appSeedColor).colorScheme;
      await _pump(tester, doc, FakeExportSaver(),
          theme: ThemeData(
              colorScheme: scheme.copyWith(tertiary: Colors.transparent)));

      expect(_strings(tester), coloured);
      expect(coloured, contains(contains('not in .xcoll')));
    });
  });

  /// The frame above earns its place by being rare, and a run with no IGDB
  /// stage makes it true of every row. T-0230's answer: the mark goes and the
  /// run says it once. The trigger is the mode, never a count of the rows --
  /// the last test in this group is the one that pins that.
  group('a keyless run says it once instead of on every row (T-0230)', () {
    ReviewDocument unmatchedShelf() => _doc([
          _game('JP SPINE'),
          _game('WORN LABEL'),
          _game('LOGO ONLY'),
        ]);

    testWidgets('no row is framed and no row carries the clause',
        (tester) async {
      await _pump(tester, unmatchedShelf(), FakeExportSaver(), keyless: true);

      expect(_frames(tester), isEmpty);
      expect(find.textContaining('not in .xcoll'), findsNothing);
    });

    testWidgets('the run states it above the list, and names the export that '
        'works', (tester) async {
      await _pump(tester, unmatchedShelf(), FakeExportSaver(), keyless: true);

      final banner = find.byKey(const Key('keyless-run-banner'));
      expect(banner, findsOneWidget);
      expect(
        find.descendant(of: banner, matching: find.textContaining('CSV')),
        findsOneWidget,
      );
      // It may not promise keyless detection, and it may not promise
      // anything a phone cannot do (T-0229 is the other half).
      final said = _strings(tester).join(' ');
      expect(said, isNot(contains('offline')));
      expect(said, isNot(contains('never leave')));
    });

    testWidgets('an ordinary run is unchanged -- banner absent, frames present',
        (tester) async {
      await _pump(tester, unmatchedShelf(), FakeExportSaver());

      expect(find.byKey(const Key('keyless-run-banner')), findsNothing);
      expect(_frames(tester), [0, 1, 2]);
      expect(find.textContaining('not in .xcoll'), findsNWidgets(3));
    });

    // The rule is "this run had no IGDB stage", not "every row came back
    // unresolved". A matched run in which everything failed to resolve is a
    // run that went wrong, and there the frames are exactly what T-0223 put
    // them there for.
    testWidgets('a matched run whose every row is unresolved still frames',
        (tester) async {
      await _pump(tester, unmatchedShelf(), FakeExportSaver(),
          resolver: FakeResolver());

      expect(find.byKey(const Key('keyless-run-banner')), findsNothing);
      expect(_frames(tester), [0, 1, 2]);
    });

    testWidgets('the export a keyless run can use writes every marked row',
        (tester) async {
      final doc = _doc([
        _game('JP SPINE', status: ReviewStatus.approved),
        _game('WORN LABEL', status: ReviewStatus.approved),
      ]);
      final saver = FakeExportSaver();
      await _pump(tester, doc, saver, keyless: true);

      await _tapExport(tester, 'csv');

      expect(saver.calls, hasLength(1));
      expect(saver.calls.single.extension, 'csv');
      expect(saver.calls.single.content, contains('JP SPINE'));
      expect(saver.calls.single.content, contains('WORN LABEL'));
    });

    // Before the tap, not after a confirmation dialog and a "nothing to
    // export". Asked of the exporter, so the sheet cannot promise a row the
    // file then drops.
    testWidgets('the target that carries nothing says so in the sheet',
        (tester) async {
      final doc = _doc([_game('JP SPINE', status: ReviewStatus.approved)]);
      await _pump(tester, doc, FakeExportSaver(), keyless: true);

      await tester.tap(find.byKey(const Key('export-primary')));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(const Key('export-sheet-tonkatsu')),
          matching: find.textContaining('carries none of the marked rows'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('export-sheet-csv')),
          matching: find.textContaining('carries none'),
        ),
        findsNothing,
      );
    });
  });

  testWidgets('a match made by an alternative name says so (T-0004)',
      (tester) async {
    // Otherwise the row reads "Cold Archive 4" over a raw title that says
    // Biohazard, and the reviewer cannot tell a good match from a wrong one.
    final best = _candidate(1, 'Cold Archive 4',
        score: 1.0, matchedAlternativeName: 'Biohazard RE:4');
    final doc = _doc([
      _game('BIOHAZARD RE:4',
          best: best,
          candidates: [best, _candidate(2, 'Cold Archive 4: Divided Paths')]),
    ]);
    await _pump(tester, doc, FakeExportSaver());

    // The exported title stays canonical; the alternative name explains it.
    expect(find.text('Cold Archive 4'), findsOneWidget);
    expect(find.textContaining('matched as "Biohazard RE:4"'), findsOneWidget);

    await tester.tap(find.byKey(const Key('review-row-0')));
    await tester.pumpAndSettle();

    expect(find.text('PlayStation 4 - matched as "Biohazard RE:4" - '
        'score 100%'), findsOneWidget);
    // A candidate the canonical name matched carries no such note.
    expect(find.text('PlayStation 4 - score 70%'), findsOneWidget);
  });

  testWidgets('picking a candidate replaces best and sets edited',
      (tester) async {
    final best = _candidate(1, 'Duskhollow');
    final other = _candidate(2, 'Duskhollow: The Old Wardens');
    final game = _game('DUSKHOLLOWE', best: best, candidates: [best, other]);
    await _pump(tester, _doc([game]), FakeExportSaver());

    await tester.tap(find.byKey(const Key('review-row-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('candidate-igdb:2')));
    await tester.pumpAndSettle();

    expect(game.best, same(other));
    expect(game.status, ReviewStatus.edited);
    // the row itself updated, without leaving the screen
    expect(find.byKey(const Key('review-row-0')), findsOneWidget);
    expect(find.text('Duskhollow: The Old Wardens'), findsOneWidget);
    expect(find.textContaining('edited'), findsOneWidget);
  });

  testWidgets('"no match" clears best, sets rejected and drops it from exports',
      (tester) async {
    final best = _candidate(1, 'Duskhollow');
    final unresolvable = _game('WORN LABEL', best: best, candidates: [best]);
    final keeper = _game('MOOR',
        best: _candidate(3, 'MOOR'), status: ReviewStatus.approved);
    final saver = FakeExportSaver();
    await _pump(tester, _doc([unresolvable, keeper]), saver);

    await tester.tap(find.byKey(const Key('review-row-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('candidate-no-match')));
    await tester.pumpAndSettle();

    expect(unresolvable.best, isNull);
    expect(unresolvable.status, ReviewStatus.rejected);
    expect(find.text('WORN LABEL'), findsOneWidget);

    for (final target in ['csv', 'tonkatsu']) {
      await _tapExport(tester, target);
    }
    expect(saver.calls, hasLength(2));
    // rejected item is absent from both exports, the approved one is not
    for (final call in saver.calls) {
      expect(call.content, isNot(contains('Duskhollow')));
      expect(call.content, isNot(contains('"external_id": 1')));
    }
    expect(saver.calls[0].content, contains('MOOR'));
    expect(saver.calls[1].content, contains('"external_id": 3'));
  });

  testWidgets('approve and reject buttons still work', (tester) async {
    final game = _game('MOOR', best: _candidate(3, 'MOOR'));
    await _pump(tester, _doc([game]), FakeExportSaver());

    await tester.tap(find.byIcon(Icons.check_circle));
    await tester.pumpAndSettle();
    expect(game.status, ReviewStatus.approved);
    expect(find.text('Review (1/1 to export)'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.cancel));
    await tester.pumpAndSettle();
    expect(game.status, ReviewStatus.rejected);
    expect(find.text('Review (0/1 to export)'), findsOneWidget);
  });

  testWidgets('export hands the rendered string to the save backend',
      (tester) async {
    final game = _game('MOOR',
        best: _candidate(3, 'MOOR'), status: ReviewStatus.approved);
    final saver = FakeExportSaver(
        outcome: const SaveOutcome.savedToFile(r'C:\shelf\shelf.csv'));
    await _pump(tester, _doc([game]), saver);

    await _tapExport(tester, 'csv');

    expect(saver.calls, hasLength(1));
    expect(saver.calls.single.suggestedName, 'shelf.csv');
    expect(saver.calls.single.extension, 'csv');
    expect(saver.calls.single.content, CsvExporter().export(_doc([game])));
    // the outcome is reported back with the real destination
    expect(find.text(r'Saved 1 item to C:\shelf\shelf.csv'), findsOneWidget);
  });

  testWidgets('tonkatsu export uses the exporter extension', (tester) async {
    final game = _game('MOOR',
        best: _candidate(3, 'MOOR'), status: ReviewStatus.approved);
    final saver = FakeExportSaver(outcome: const SaveOutcome.shared('/tmp/x'));
    await _pump(tester, _doc([game]), saver);

    await _tapExport(tester, 'tonkatsu');

    expect(saver.calls.single.suggestedName, 'shelf.xcoll');
    expect(saver.calls.single.extension, 'xcoll');
    expect(find.text('Shared 1 item as shelf.xcoll'), findsOneWidget);
  });

  testWidgets('exporting with unresolved approved items warns first',
      (tester) async {
    final unresolved = _game('JP SPINE', status: ReviewStatus.approved);
    final resolved = _game('MOOR',
        best: _candidate(3, 'MOOR'), status: ReviewStatus.approved);
    final saver = FakeExportSaver();
    await _pump(tester, _doc([unresolved, resolved]), saver);

    // cancelling the warning aborts the export
    await _tapExport(tester, 'tonkatsu');
    expect(find.textContaining('1 approved item'), findsOneWidget);
    await tester.tap(find.text('Back to review'));
    await tester.pumpAndSettle();
    expect(saver.calls, isEmpty);

    // confirming exports without the unresolved item
    await _tapExport(tester, 'tonkatsu');
    await tester.tap(find.byKey(const Key('export-drop-confirm')));
    await tester.pumpAndSettle();
    expect(saver.calls, hasLength(1));
    expect(saver.calls.single.content, isNot(contains('JP SPINE')));
    expect(saver.calls.single.content, contains('"external_id": 3'));
  });

  testWidgets('export with nothing resolved never reaches the save backend',
      (tester) async {
    final saver = FakeExportSaver();
    await _pump(
        tester, _doc([_game('JP SPINE', status: ReviewStatus.approved)]), saver);

    await _tapExport(tester, 'tonkatsu');
    await tester.tap(find.byKey(const Key('export-drop-confirm')));
    await tester.pumpAndSettle();

    expect(saver.calls, isEmpty);
    expect(find.textContaining('Nothing to export'), findsOneWidget);
  });

  testWidgets('the primary export button carries the count and reaches every '
      'registered target (T-0118)', (tester) async {
    final game = _game('MOOR',
        best: _candidate(3, 'MOOR'), status: ReviewStatus.approved);
    final saver = FakeExportSaver(
        outcome: const SaveOutcome.savedToFile(r'C:\shelf\shelf.csv'));
    await _pump(tester, _doc([game]), saver);

    expect(find.text('Export 1 item'), findsOneWidget);

    // Over the registry, not a hand-written pair: a target added to
    // `exporters` that the surviving route cannot reach is the failure this
    // guards, and a literal list would not notice it.
    for (final target in exporters.keys) {
      await _tapExport(tester, target);
    }

    expect(saver.calls.map((c) => c.extension),
        exporters.values.map((make) => make().extension));
  });

  testWidgets('the bottom bar is the only export control (T-0118)',
      (tester) async {
    final saver = FakeExportSaver();
    await _pump(tester, _doc([_game('MOOR', best: _candidate(3, 'MOOR'))]),
        saver);

    // Nothing approved: the one control says so and refuses the tap, and
    // there is no second route that would take it anyway.
    expect(find.text('Export -- nothing approved yet'), findsOneWidget);
    final button = tester.widget<FilledButton>(
        find.byKey(const Key('export-primary')));
    expect(button.onPressed, isNull);

    expect(tester.widget<AppBar>(find.byType(AppBar)).actions, isNull);
    expect(find.byIcon(Icons.upload_file), findsNothing);
    for (final target in exporters.keys) {
      expect(find.byKey(Key('export-$target')), findsNothing);
    }

    await tester.tap(find.byKey(const Key('export-primary')));
    await tester.pumpAndSettle();
    expect(saver.calls, isEmpty);
    expect(find.byKey(const Key('export-sheet-csv')), findsNothing);
  });

  // ---- manual add (T-0012) ------------------------------------------- //

  group('adding an item the scan missed', () {
    testWidgets('the new item appears in the list immediately',
        (tester) async {
      final doc = _doc([_game('MOOR', best: _candidate(3, 'MOOR'))]);
      await _pump(tester, doc, FakeExportSaver());

      await _addItem(tester,
          title: 'Nocturne 5 Gold', platform: 'PS4', mediaType: 'Disc');

      expect(doc.games, hasLength(2));
      final added = doc.games.last;
      expect(added.detection.rawTitle, 'Nocturne 5 Gold');
      expect(added.detection.platformHint, 'PS4');
      expect(added.detection.mediaType, MediaType.disc);
      expect(added.detection.origin, DetectionOrigin.manual);
      expect(added.detection.sourcePhoto, isEmpty);
      expect(added.detection.addedFromPhoto, isNull,
          reason: 'the FAB floats over the whole list and names no shelf');

      // visible, marked as hand-entered, and still reviewable
      expect(find.byKey(const Key('review-row-1')), findsOneWidget);
      expect(find.text('Nocturne 5 Gold'), findsOneWidget);
      expect(find.textContaining('added by hand'), findsOneWidget);
      expect(find.text('Review (0/2 to export)'), findsOneWidget);
    });

    testWidgets('cancelling adds nothing', (tester) async {
      final doc = _doc([_game('MOOR', best: _candidate(3, 'MOOR'))]);
      await _pump(tester, doc, FakeExportSaver());

      await tester.tap(find.byKey(const Key('add-manual-item')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const Key('manual-title')), 'Nocturne 5 Gold');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('manual-cancel')));
      await tester.pumpAndSettle();

      expect(doc.games, hasLength(1));
    });

    testWidgets('an empty title cannot be submitted', (tester) async {
      await _pump(tester, _doc([]), FakeExportSaver());

      await tester.tap(find.byKey(const Key('add-manual-item')));
      await tester.pumpAndSettle();
      final add = tester.widget<FilledButton>(find.byKey(const Key('manual-add')));
      expect(add.onPressed, isNull);

      // whitespace is not a title either
      await tester.enterText(find.byKey(const Key('manual-title')), '   ');
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilledButton>(find.byKey(const Key('manual-add')))
            .onPressed,
        isNull,
      );
    });

    testWidgets('with IGDB configured it is resolved and its candidates '
        'are pickable', (tester) async {
      final royal = _candidate(1100000015, 'Nocturne 5 Gold');
      final vanilla = _candidate(1100000016, 'Nocturne 5');
      final resolver = FakeResolver(candidates: [royal, vanilla]);
      final doc = _doc([]);
      await _pump(tester, doc, FakeExportSaver(), resolver: resolver);

      await _addItem(tester, title: 'Nocturne 5 Gold', platform: 'PS4');

      // the typed detection is what reached the resolver
      expect(resolver.seen.single.rawTitle, 'Nocturne 5 Gold');
      expect(resolver.seen.single.platformHint, 'PS4');
      expect(doc.games.single.best, same(royal));
      expect(doc.games.single.candidates, hasLength(2));

      // and the T-0005 picker works on it like on any other row
      await tester.tap(find.byKey(const Key('review-row-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('candidate-igdb:1100000016')));
      await tester.pumpAndSettle();

      expect(doc.games.single.best, same(vanilla));
      expect(doc.games.single.status, ReviewStatus.edited);
    });

    testWidgets('without IGDB it stays pending with no match and does not '
        'error', (tester) async {
      final doc = _doc([]);
      // Exactly what ProviderPolicy.buildResolver hands over when the user
      // has entered no IGDB credentials.
      await _pump(tester, doc, FakeExportSaver(), resolver: SkipResolver());

      await _addItem(tester, title: 'Nocturne 5 Gold');

      expect(tester.takeException(), isNull);
      expect(doc.games.single.best, isNull);
      expect(doc.games.single.candidates, isEmpty);
      expect(doc.games.single.status, ReviewStatus.pending);
      expect(find.textContaining('no IGDB match'), findsOneWidget);
    });

    testWidgets('a failing IGDB lookup still keeps the typed item',
        (tester) async {
      final doc = _doc([]);
      await _pump(tester, doc, FakeExportSaver(),
          resolver: FakeResolver(fails: true));

      await _addItem(tester, title: 'Nocturne 5 Gold');

      expect(tester.takeException(), isNull);
      expect(doc.games.single.detection.rawTitle, 'Nocturne 5 Gold');
      expect(doc.games.single.best, isNull);
      expect(find.textContaining('IGDB lookup failed'), findsOneWidget);
    });

    testWidgets('an unmatched manual item exports to csv but not to .xcoll',
        (tester) async {
      final doc = _doc([]);
      final saver = FakeExportSaver();
      await _pump(tester, doc, saver, resolver: SkipResolver());

      await _addItem(tester, title: 'Nocturne 5 Gold', platform: 'PS4');
      await tester.tap(find.byIcon(Icons.check_circle));
      await tester.pumpAndSettle();

      // csv carries it, with no warning: nothing is being dropped
      await _tapExport(tester, 'csv');
      expect(find.textContaining('will be left out'), findsNothing);
      expect(saver.calls.single.content, contains('Nocturne 5 Gold,PS4,'));

      // .xcoll cannot, and says so before writing anything
      await _tapExport(tester, 'tonkatsu');
      expect(find.textContaining('1 approved item'), findsOneWidget);
      await tester.tap(find.byKey(const Key('export-drop-confirm')));
      await tester.pumpAndSettle();
      expect(saver.calls, hasLength(1),
          reason: 'the only approved item has no id, so .xcoll writes nothing '
              'and the save backend is never reached a second time');
    });
  });

  group('unread-spine reports prompt', () {
    UnreadSpineReport spine(String photo, [SpineScript script = SpineScript.japanese]) =>
        UnreadSpineReport(sourcePhoto: photo, script: script);

    testWidgets('T-0011 counts become the prompt to add missing items',
        (tester) async {
      final doc = _doc(
        [_game('MOOR', best: _candidate(3, 'MOOR'))],
        unreadable: [
          spine('shelf1.jpg'),
          spine('shelf1.jpg'),
          spine('shelf2.jpg', SpineScript.unknown),
        ],
      );
      await _pump(tester, doc, FakeExportSaver());

      expect(find.byKey(const Key('unreadable-prompt')), findsOneWidget);
      expect(find.text('At least 3 spines could not be read'), findsOneWidget);
      expect(find.textContaining('Add them by hand'), findsOneWidget);
      // The counts stayed per photo, and so did the way to act on them.
      expect(find.text('2 unread-spine reports'), findsOneWidget);
      expect(find.text('1 unread-spine report'), findsOneWidget);
      for (final photo in ['shelf1.jpg', 'shelf2.jpg']) {
        expect(find.byKey(Key('unreadable-add-$photo')), findsOneWidget);
      }
    });

    testWidgets('the prompt adds an item and then tracks what was added',
        (tester) async {
      final doc = _doc([], unreadable: [spine('shelf1.jpg')]);
      await _pump(tester, doc, FakeExportSaver());

      await _addItem(tester,
          title: 'Nocturne 5 Gold',
          trigger: const Key('unreadable-add-shelf1.jpg'));

      expect(doc.games.single.detection.isManual, isTrue);
      expect(find.text('At least 1 spine could not be read'), findsOneWidget);
      expect(find.textContaining('1 item added by hand so far.'),
          findsOneWidget);
    });

    // The measured case (T-0109): one entry, two or three spines. 10 of 10
    // runs of gpt-4.1-mini on CONTROL-HIRES shelf-3 answer this one
    // entry against a hand count off the photograph it never matches.
    testWidgets('one report naming several spines is not read as one spine',
        (tester) async {
      final doc = _doc([], unreadable: [
        UnreadSpineReport(
          sourcePhoto: 'shelf-3.jpg',
          script: SpineScript.latin,
          reason: 'two/three spines in the middle are too blurred to read',
        ),
      ]);
      await _pump(tester, doc, FakeExportSaver());

      expect(find.text('1 spine could not be read'), findsNothing);
      expect(find.text('At least 1 spine could not be read'), findsOneWidget);
      expect(find.textContaining('may be more'), findsOneWidget);
      expect(find.text('1 unread-spine report'), findsOneWidget);
      // No count is taken out of the entry's prose -- that is T-0028's
      // fabricated count with a friendlier face.
      expect(find.textContaining('2 spines'), findsNothing);
      expect(find.textContaining('3 spines'), findsNothing);
      expect(find.textContaining('two/three'), findsNothing);
    });

    testWidgets("the prompt's per-photo Add puts the item under that photo "
        '(T-0052)', (tester) async {
      _resize(tester, const Size(800, 1400));
      final doc = _doc(
        [_game('MOOR', sourcePhoto: 'shelf1.jpg')],
        photos: const ['shelf1.jpg', 'shelf2.jpg'],
        unreadable: [spine('shelf1.jpg'), spine('shelf2.jpg')],
      );
      await _pump(tester, doc, FakeExportSaver());

      await _addItem(tester,
          title: 'Nocturne 5 Gold',
          trigger: const Key('unreadable-add-shelf2.jpg'));

      // The spine that could not be read on shelf2 becomes a row on shelf2.
      expect(doc.games.last.detection.addedFromPhoto, 'shelf2.jpg');
      expect(find.text('Not from a photo'), findsNothing);
      expect(_top(tester, 'review-row-1'),
          greaterThan(_top(tester, 'photo-group-shelf2.jpg')));
    });

    testWidgets('no prompt when the scan read everything', (tester) async {
      await _pump(tester, _doc([_game('MOOR')]), FakeExportSaver());
      expect(find.byKey(const Key('unreadable-prompt')), findsNothing);
      // adding is still possible, just not prompted
      expect(find.byKey(const Key('add-manual-item')), findsOneWidget);
    });
  });

  // ---- grouped by the photo the rows came from (T-0042) ---------------- //

  group('rows grouped by source photo', () {
    ReviewDocument twoShelves() => _doc(
          [
            _game('MOOR', sourcePhoto: 'shelf1.jpg'),
            _game('ARCA', sourcePhoto: 'shelf2.jpg'),
            _game('CUBIKA', sourcePhoto: 'shelf1.jpg'),
          ],
          photos: const ['shelf1.jpg', 'shelf2.jpg'],
        );

    testWidgets('each photo heads its own rows, in scan order',
        (tester) async {
      await _pump(tester, twoShelves(), FakeExportSaver(),
          photos: [_photo('shelf1.jpg'), _photo('shelf2.jpg')]);

      expect(find.byKey(const Key('photo-group-shelf1.jpg')), findsOneWidget);
      expect(find.byKey(const Key('photo-group-shelf2.jpg')), findsOneWidget);

      // shelf1's header, then both of its rows, then shelf2's header and its
      // row -- the two shelf1 rows are no longer split by the shelf2 one.
      expect(
        [
          _top(tester, 'photo-group-shelf1.jpg'),
          _top(tester, 'review-row-0'),
          _top(tester, 'review-row-2'),
          _top(tester, 'photo-group-shelf2.jpg'),
          _top(tester, 'review-row-1'),
        ],
        orderedEquals([
          _top(tester, 'photo-group-shelf1.jpg'),
          _top(tester, 'review-row-0'),
          _top(tester, 'review-row-2'),
          _top(tester, 'photo-group-shelf2.jpg'),
          _top(tester, 'review-row-1'),
        ]..sort()),
      );

      expect(find.text('2 items'), findsOneWidget);
      expect(find.text('1 item'), findsOneWidget);
    });

    testWidgets('the file lands the rows where this screen shows them',
        (tester) async {
      // The half of T-0068 that no core test can pin: `resolve` orders the
      // file by [Detection.photoContext] because that is the field this
      // screen groups on, so a typed row is filed under its shelf in both.
      _resize(tester, const Size(800, 1400));
      Detection read(String title, String photo) => Detection(
            rawTitle: title,
            mediaType: MediaType.disc,
            confidence: 1.0,
            sourcePhoto: photo,
          );
      final games = await tester.runAsync(() =>
          Orchestrator.resolveOnly(resolverWorker: SkipResolver()).runResolve([
            read('MOOR', 'shelf1.jpg'),
            read('ARCA', 'shelf2.jpg'),
            Detection.manual(
                rawTitle: 'NOCTURNE 5 GOLD', addedFromPhoto: 'shelf2.jpg'),
            read('CUBIKA', 'shelf1.jpg'),
          ]));

      await _pump(
          tester,
          _doc(games!, photos: const ['shelf1.jpg', 'shelf2.jpg']),
          FakeExportSaver(),
          photos: [_photo('shelf1.jpg'), _photo('shelf2.jpg')]);

      expect([for (final game in games) game.detection.rawTitle],
          ['MOOR', 'CUBIKA', 'ARCA', 'NOCTURNE 5 GOLD']);
      // Every row is shown below the one before it, so the screen adds no
      // reordering of its own to the file's, and the typed row is under
      // shelf2's header rather than in a group of its own.
      final tops = [
        _top(tester, 'review-row-0'),
        _top(tester, 'review-row-1'),
        _top(tester, 'photo-group-shelf2.jpg'),
        _top(tester, 'review-row-2'),
        _top(tester, 'review-row-3'),
      ];
      expect(tops, orderedEquals([...tops]..sort()));
      expect(find.byKey(const Key('photo-group-')), findsNothing);
    });

    testWidgets('the header carries the photo itself, decoded small',
        (tester) async {
      await _pump(tester, twoShelves(), FakeExportSaver(),
          photos: [_photo('shelf1.jpg'), _photo('shelf2.jpg')]);

      final images = tester.widgetList<Image>(find.byType(Image)).toList();
      expect(images, hasLength(2));
      for (final image in images) {
        // A full-resolution decode is ~50 MB; the header asks for a
        // thumbnail-sized one instead.
        final provider = image.image as ResizeImage;
        expect(provider.width, 720);
        expect((provider.imageProvider as MemoryImage).bytes, _pixel);
      }
    });

    testWidgets('tapping the header opens the photo big enough to zoom past '
        'native resolution', (tester) async {
      await _pump(tester, twoShelves(), FakeExportSaver(),
          photos: [_photo('shelf1.jpg'), _photo('shelf2.jpg')]);

      await tester.tap(find.byKey(const Key('photo-group-shelf2.jpg')));
      await tester.pumpAndSettle();

      final viewer = tester.widget<InteractiveViewer>(
          find.byKey(const Key('photo-viewer')));
      // Fitting the long edge of a full-resolution photo into ~600 logical px
      // is ~0.15x, so 1:1 needs ~6.8x.
      expect(viewer.maxScale, greaterThanOrEqualTo(6.8));
      // The enlarged view is the untouched original, not the thumbnail.
      final full = tester.widget<Image>(find.descendant(
          of: find.byKey(const Key('photo-viewer')),
          matching: find.byType(Image)));
      expect(full.image, isA<MemoryImage>());
      expect(find.widgetWithText(AppBar, 'shelf2.jpg'), findsOneWidget);
    });

    testWidgets('a photo that produced nothing still gets a group that says so',
        (tester) async {
      final doc = _doc(
        [_game('MOOR', sourcePhoto: 'shelf1.jpg')],
        photos: const ['shelf1.jpg', 'shelf2.jpg'],
      );
      await _pump(tester, doc, FakeExportSaver(),
          photos: [_photo('shelf1.jpg'), _photo('shelf2.jpg')]);

      expect(find.byKey(const Key('photo-group-shelf2.jpg')), findsOneWidget);
      expect(find.text('nothing was read off this photo'), findsOneWidget);
    });

    testWidgets('rows off no photo land in a last group, after every shelf',
        (tester) async {
      // Tall enough that every group is laid out at once: the assertion is
      // about where the group sits, not about lazy building.
      _resize(tester, const Size(800, 1400));
      final doc = twoShelves();
      await _pump(tester, doc, FakeExportSaver(),
          photos: [_photo('shelf1.jpg'), _photo('shelf2.jpg')]);

      await _addItem(tester, title: 'Nocturne 5 Gold');

      expect(find.byKey(const Key('photo-group-')), findsOneWidget);
      expect(find.text('Not from a photo'), findsOneWidget);
      expect(_top(tester, 'photo-group-'),
          greaterThan(_top(tester, 'photo-group-shelf2.jpg')));
      expect(_top(tester, 'review-row-3'),
          greaterThan(_top(tester, 'photo-group-')));
      // and it is the same document row the exporters see
      expect(doc.games.last.detection.isManual, isTrue);
    });

    testWidgets('a document with no images groups by name and offers no '
        'broken affordance', (tester) async {
      // What opening a `review.json` later looks like: names, no bytes.
      await _pump(tester, twoShelves(), FakeExportSaver());

      expect(find.byKey(const Key('photo-group-shelf1.jpg')), findsOneWidget);
      expect(find.text('shelf2.jpg'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(find.byIcon(Icons.zoom_in), findsNothing);
      for (final name in ['shelf1.jpg', 'shelf2.jpg']) {
        final tile = tester
            .widget<InkWell>(find.byKey(Key('photo-group-$name')));
        expect(tile.onTap, isNull);
      }
      // rows are still grouped and still reviewable
      expect(_top(tester, 'review-row-2'),
          lessThan(_top(tester, 'photo-group-shelf2.jpg')));
    });

    testWidgets('a wide window puts the photo beside its rows, a narrow one '
        'above them', (tester) async {
      _resize(tester, const Size(1280, 900));
      await _pump(tester, twoShelves(), FakeExportSaver(),
          photos: [_photo('shelf1.jpg'), _photo('shelf2.jpg')]);

      final header =
          tester.getRect(find.byKey(const Key('photo-group-shelf1.jpg')));
      final row = tester.getRect(find.byKey(const Key('review-row-0')));
      expect(header.right, lessThanOrEqualTo(row.left));
      expect(header.width, 280);
      expect(row.top, header.top);

      // Same document, a window under the 840 breakpoint: stacked again.
      _resize(tester, const Size(839, 900));
      await tester.pumpAndSettle();

      final narrowHeader =
          tester.getRect(find.byKey(const Key('photo-group-shelf1.jpg')));
      final narrowRow = tester.getRect(find.byKey(const Key('review-row-0')));
      expect(narrowHeader.bottom, lessThanOrEqualTo(narrowRow.top));
      expect(narrowHeader.left, narrowRow.left);
    });
  });

  // ---- added from the shelf being read (T-0052) ------------------------ //

  group('an item typed from a photo lands in that photo group', () {
    ReviewDocument twoShelves() => _doc(
          [
            _game('MOOR', sourcePhoto: 'shelf1.jpg'),
            _game('ARCA', sourcePhoto: 'shelf2.jpg'),
          ],
          photos: const ['shelf1.jpg', 'shelf2.jpg'],
        );

    testWidgets('the group header adds to its own group, not to the bottom',
        (tester) async {
      _resize(tester, const Size(800, 1400));
      final doc = twoShelves();
      await _pump(tester, doc, FakeExportSaver(),
          photos: [_photo('shelf1.jpg'), _photo('shelf2.jpg')]);

      await _addItem(tester,
          title: 'Nocturne 5 Gold',
          trigger: const Key('photo-group-add-shelf2.jpg'));

      final added = doc.games.last.detection;
      expect(added.addedFromPhoto, 'shelf2.jpg');
      expect(added.sourcePhoto, isEmpty,
          reason: 'it was typed while looking at shelf2, not read off it');
      expect(added.origin, DetectionOrigin.manual);

      // No "Not from a photo" group was created at all, and the new row sits
      // under shelf2's header beside the shelf the human was reading.
      expect(find.text('Not from a photo'), findsNothing);
      expect(find.byKey(const Key('photo-group-')), findsNothing);
      expect(_top(tester, 'review-row-2'),
          greaterThan(_top(tester, 'photo-group-shelf2.jpg')));
      expect(_top(tester, 'review-row-2'),
          greaterThan(_top(tester, 'review-row-1')));
      expect(find.text('2 items'), findsOneWidget);
    });

    testWidgets('the dialog names the photo it will file the item under',
        (tester) async {
      await _pump(tester, twoShelves(), FakeExportSaver());

      await tester.tap(find.byKey(const Key('photo-group-add-shelf2.jpg')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('manual-from-photo')), findsOneWidget);
      expect(find.text('From shelf2.jpg'), findsOneWidget);
      await tester.tap(find.byKey(const Key('manual-cancel')));
      await tester.pumpAndSettle();

      // The FAB has no shelf to name, so it says nothing rather than lying.
      await tester.tap(find.byKey(const Key('add-manual-item')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('manual-from-photo')), findsNothing);
    });

    testWidgets('with no photo in context it still has a home, at the bottom',
        (tester) async {
      _resize(tester, const Size(800, 1400));
      final doc = twoShelves();
      await _pump(tester, doc, FakeExportSaver(),
          photos: [_photo('shelf1.jpg'), _photo('shelf2.jpg')]);

      await _addItem(tester, title: 'Nocturne 5 Gold');

      expect(doc.games.last.detection.addedFromPhoto, isNull);
      expect(find.byKey(const Key('photo-group-')), findsOneWidget);
      expect(_top(tester, 'review-row-2'),
          greaterThan(_top(tester, 'photo-group-')));
      expect(_top(tester, 'photo-group-'),
          greaterThan(_top(tester, 'photo-group-shelf2.jpg')));
    });

    testWidgets('a document opened later keeps the association and can still '
        'be added to', (tester) async {
      // No bytes, only names: the case route 3 would have lost outright.
      _resize(tester, const Size(800, 1400));
      final doc = ReviewDocument.parse(jsonEncode(twoShelves().toJson()));
      await _pump(tester, doc, FakeExportSaver());

      await _addItem(tester,
          title: 'Nocturne 5 Gold',
          trigger: const Key('photo-group-add-shelf2.jpg'));

      final reopened =
          ReviewDocument.parse(jsonEncode(doc.toJson()));
      expect(reopened.games.last.detection.addedFromPhoto, 'shelf2.jpg');
      expect(reopened.games.last.detection.photoContext, 'shelf2.jpg');
    });

    testWidgets('the loose group offers no per-photo add of its own',
        (tester) async {
      final doc = _doc([_game('JP SPINE', sourcePhoto: '')], photos: const []);
      await _pump(tester, doc, FakeExportSaver());

      expect(find.byKey(const Key('photo-group-')), findsOneWidget);
      expect(find.byKey(const Key('photo-group-add-')), findsNothing);
      expect(find.byIcon(Icons.playlist_add), findsNothing);
    });
  });

  testWidgets('a row whose kind has no platform shows none, not the hint',
      (tester) async {
    // The review-screen half of decision 0016's one behaviour change, and the
    // same rule the CSV's platform column follows: the hint is a guess about a
    // console, so a film must not wear one. `correctWorkKind` clears the match
    // and not the detection, so this row still carries the `PS4` its spine
    // gave it -- which is exactly why the fallback may not be reached when
    // something matched.
    final doc = _doc([
      _game('HARBOUR LIGHTS',
          workKind: WorkKind.movie,
          best: Candidate(
              externalId: 'tmdb:1100000091', title: 'Harbour Lights', score: 1.0))
    ]);
    await _pump(tester, doc, FakeExportSaver());

    expect(find.textContaining('PS4'), findsNothing);
    expect(find.textContaining('score 100%'), findsOneWidget);
  });
}
