/// What a folder-sourced group shows on the review screen (T-0161).
///
/// T-0042 put the shelf photo in a group's header so the human could see what
/// was NOT picked up. A folder has no picture, and the same question has a
/// better answer for it: the entries the sources declined, which the document
/// carries by name (T-0155). So the header is the photo header with the
/// picture replaced by the skipped list -- grouped by reason, names behind a
/// tap, because a games folder declines more than it accepts (T-0158) and
/// fifty lines is as unusable as silence.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelfscan_app/screens/review_screen.dart';
import 'package:shelfscan_core/shelfscan_core.dart';

ResolvedGame _fromFolder(String title, String entry,
        {DetectionOrigin origin = DetectionOrigin.filename}) =>
    ResolvedGame(
      detection: Detection.fromSource(
        rawTitle: title,
        origin: origin,
        sourceEntry: entry,
        platformHint: 'PC',
      ),
      best: null,
      candidates: const [],
      status: ReviewStatus.pending,
    );

ResolvedGame _fromPhoto(String title, String photo) => ResolvedGame(
      detection: Detection(
        rawTitle: title,
        mediaType: MediaType.disc,
        confidence: 1.0,
        sourcePhoto: photo,
      ),
      best: null,
      candidates: const [],
      status: ReviewStatus.pending,
    );

ReviewDocument _doc({
  List<String> photos = const [],
  List<ResolvedGame> games = const [],
  List<DeclinedEntry> declined = const [],
}) =>
    ReviewDocument(
      version: 1,
      created: '2026-08-16T00:00:00Z',
      photos: photos,
      games: games,
      declinedEntries: declined,
    );

Future<void> _pump(WidgetTester tester, ReviewDocument document,
        {List<String> folders = const []}) =>
    tester.pumpWidget(MaterialApp(
      home: ReviewScreen(document: document, folders: folders),
    ));

void main() {
  testWidgets('folder rows get their own group, named after the folder',
      (tester) async {
    await _pump(
      tester,
      _doc(games: [
        _fromFolder('moor', 'setup_moor_1.9.exe'),
        _fromFolder('Harbour Lantern', 'goggame-1100000001.info',
            origin: DetectionOrigin.metadata),
      ]),
      folders: [r'C:\GOG Games'],
    );

    expect(find.byKey(const Key('folder-group')), findsOneWidget);
    expect(find.text('GOG Games'), findsOneWidget);
    expect(find.text(r'C:\GOG Games'), findsOneWidget);
    expect(find.text('2 items'), findsOneWidget);
    // Not the loose group: two source rows are not two rows nobody can place.
    expect(find.text('Not from a photo'), findsNothing);
  });

  testWidgets('one group for the folder, not one per game directory',
      (tester) async {
    await _pump(
      tester,
      _doc(games: [
        for (var i = 0; i < 50; i++) _fromFolder('Game $i', 'Game $i'),
      ]),
      folders: [r'C:\GOG Games'],
    );

    // The container of a games directory is a different name per game, so
    // grouping on it would be fifty headers of one row each.
    expect(find.byKey(const Key('folder-group')), findsOneWidget);
    expect(find.text('50 items'), findsOneWidget);
  });

  testWidgets('two folders are counted in the title and named under it',
      (tester) async {
    await _pump(
      tester,
      _doc(games: [_fromFolder('moor', 'setup_moor_1.9.exe')]),
      folders: [r'C:\GOG Games', r'E:\Installers'],
    );

    expect(find.text('2 folders'), findsOneWidget);
    expect(find.text(r'C:\GOG Games'), findsOneWidget);
    expect(find.text(r'E:\Installers'), findsOneWidget);
  });

  testWidgets('the header offers no photo affordances', (tester) async {
    await _pump(
      tester,
      _doc(games: [_fromFolder('moor', 'setup_moor_1.9.exe')]),
      folders: [r'C:\GOG Games'],
    );

    // No thumbnail and no enlarge tap -- there is no image. And no "add an
    // item from this", which writes the group's name into `addedFromPhoto`:
    // models.dart reserves that field for a photo file name, and the csv
    // export publishes it as provenance to a reader with no `origin` column.
    expect(find.byType(Image), findsNothing);
    expect(find.byKey(const Key('photo-group-GOG Games')), findsNothing);
    expect(find.byKey(const Key('photo-group-add-GOG Games')), findsNothing);
  });

  testWidgets('a folder that yielded nothing still says so', (tester) async {
    await _pump(
      tester,
      _doc(declined: const [
        DeclinedEntry(name: 'NoteWellSetup.exe', reason: 'not a game file'),
      ]),
      folders: [r'C:\Users\someone\Downloads'],
    );

    expect(find.byKey(const Key('folder-group')), findsOneWidget);
    expect(find.text('no game was read out of this folder'), findsOneWidget);
  });

  group('what the user sees of the declined entries', () {
    final declined = [
      const DeclinedEntry(
          name: 'unins000.exe',
          reason: 'installer support file, not a game'),
      const DeclinedEntry(
          name: 'DXSETUP.exe', reason: 'installer support file, not a game'),
      const DeclinedEntry(name: 'manual.pdf', reason: 'not a game file'),
      const DeclinedEntry(name: 'save1.sav', reason: 'not a game file'),
      const DeclinedEntry(name: 'cover.png', reason: 'not a game file'),
    ];

    testWidgets('folded it is one line, not one line per entry',
        (tester) async {
      await _pump(
        tester,
        _doc(games: [_fromFolder('moor', 'setup_moor_1.9.exe')],
            declined: declined),
        folders: [r'C:\GOG Games'],
      );

      expect(find.text('5 files skipped, no game in them'), findsOneWidget);
      for (final entry in declined) {
        expect(find.text(entry.name), findsNothing,
            reason: 'five names folded, not five lines');
      }
    });

    testWidgets('opened it names every one of them, under its reason',
        (tester) async {
      await _pump(
        tester,
        _doc(games: [_fromFolder('moor', 'setup_moor_1.9.exe')],
            declined: declined),
        folders: [r'C:\GOG Games'],
      );

      await tester.tap(find.byKey(const Key('declined-entries')));
      await tester.pumpAndSettle();

      // By reason, because that is what the reasons are a closed set for, and
      // it is what the orchestrator's own warnings group by.
      expect(find.text('2 installer support file, not a game'), findsOneWidget);
      expect(find.text('unins000.exe, DXSETUP.exe'), findsOneWidget);
      expect(find.text('3 not a game file'), findsOneWidget);
      expect(find.text('manual.pdf, save1.sav, cover.png'), findsOneWidget);
    });

    testWidgets('a photo-only run shows no folder group at all', (tester) async {
      await _pump(
        tester,
        _doc(photos: ['shelf1.jpg'], games: [_fromPhoto('Duskhollow', 'shelf1.jpg')]),
      );

      expect(find.byKey(const Key('folder-group')), findsNothing);
      expect(find.byKey(const Key('declined-entries')), findsNothing);
      expect(find.byKey(const Key('photo-group-shelf1.jpg')), findsOneWidget);
    });
  });

  testWidgets('the shelves keep their place: photos first, folder, loose last',
      (tester) async {
    await _pump(
      tester,
      _doc(photos: ['shelf1.jpg'], games: [
        _fromPhoto('Duskhollow', 'shelf1.jpg'),
        _fromFolder('moor', 'setup_moor_1.9.exe'),
        ResolvedGame(
          detection: Detection.manual(rawTitle: 'typed by hand'),
          best: null,
          candidates: const [],
          status: ReviewStatus.pending,
        ),
      ]),
      folders: [r'C:\GOG Games'],
    );

    double top(Finder finder) => tester.getTopLeft(finder).dy;
    expect(top(find.byKey(const Key('photo-group-shelf1.jpg'))),
        lessThan(top(find.byKey(const Key('folder-group')))));
    expect(top(find.byKey(const Key('folder-group'))),
        lessThan(top(find.text('Not from a photo'))));
  });
}
