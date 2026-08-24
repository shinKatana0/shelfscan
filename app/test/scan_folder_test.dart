/// The folder control on the scan screen (T-0161).
///
/// A second button rather than a mode on Add photos -- a real call, and
/// the code's: no vision call, no cost, no key, and its own failures. What is
/// pinned here is that it is separate, that it cannot open two dialogs
/// (T-0116) or open one during a run (T-0121/T-0138), and that a folder full
/// of other things is questioned before it is read: over a `Downloads` folder
/// this source titles every installer it finds and not one of them is a game
/// (T-0158), which nothing downstream can recover from.
///
/// The walk itself is not here -- it is real I/O, which never completes inside
/// `testWidgets`'s fake async, so the screen takes a reader seam and
/// `game_folders_test.dart` drives the real one against real directories.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:shelfscan_app/input_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelfscan_app/game_folders.dart';
import 'package:shelfscan_app/photo_files.dart';
import 'package:shelfscan_app/provider_config.dart';
import 'package:shelfscan_app/screens/scan_screen.dart';
import 'package:shelfscan_app/settings_store.dart';
import 'package:shelfscan_core/shelfscan_core.dart';

import 'settings_store_test.dart' show RecordingStore;

final _jpeg =
    Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, ...List.filled(32, 0)]);

const _gogGames = r'C:\GOG Games';
const _downloads = r'C:\Users\someone\Downloads';

MediaFolder _folder(String path, List<String> names) => MediaFolder(
      path: path,
      name: folderName(path),
      entries: [
        for (final name in names)
          SourceEntry(name: name, container: folderName(path))
      ],
    );

/// Answers both dialogs, so the guard can be tested across them: the presses
/// that stack explorers are the ones landing while another one is open, and
/// two controls make that a cross-product rather than two cases.
class _BothPicker extends InputPicker {
  _BothPicker({this.directory, this.files = const {}, this.gate});

  final String? directory;
  final Map<String, Uint8List> files;
  final Completer<void>? gate;
  int directoryCalls = 0;
  int fileCalls = 0;
  String? askedPrompt;

  @override
  Future<String?> pickFolder({required String prompt}) async {
    directoryCalls++;
    askedPrompt = prompt;
    await gate?.future;
    return directory;
  }

  @override
  Future<List<PickedFile>?> pickPhotos() async {
    fileCalls++;
    await gate?.future;
    return [
      for (final entry in files.entries) (name: entry.key, bytes: entry.value)
    ];
  }
}

/// Records what the model was asked to read -- a folder run must ask it
/// nothing at all, which no assertion about the screen can reach.
class _RecordingVision implements VisionProvider {
  _RecordingVision({this.gates = const {}});

  final Map<String, Completer<void>> gates;
  final seen = <String>[];

  @override
  Future<PhotoAnalysis> analyze(PhotoInput photo) async {
    seen.add(photo.name);
    await gates[photo.name]?.future;
    return PhotoAnalysis(
      items: [
        Detection(
          rawTitle: 'READ ${photo.name}',
          mediaType: MediaType.disc,
          confidence: 1.0,
          sourcePhoto: photo.name,
        ),
      ],
      unreadable: const [],
    );
  }
}

Future<_RecordingVision> _pump(
  WidgetTester tester, {
  required _BothPicker picker,
  VisionBackend backend = VisionBackend.local,
  Map<String, Completer<void>> gates = const {},
  MediaFolder? folder,
}) async {
  final vision = _RecordingVision(gates: gates);
  final held = folder ?? _folder(_gogGames, const ['setup_moor_1.9.exe']);
  await tester.pumpWidget(MaterialApp(
    home: ScanScreen(
      settings: ProviderSettings(backend: backend),
      store: SettingsStore(secrets: RecordingStore(), prefs: RecordingStore()),
      picker: picker,
      debugVisionProvider: vision,
      debugFolderReader: (path) async =>
          held.path == path ? held : _folder(path, const []),
    ),
  ));
  return vision;
}

Future<void> _addFolder(WidgetTester tester) async {
  await tester.tap(find.text('Add media folder'));
  await tester.pumpAndSettle();
}

bool _scanEnabled(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byType(FilledButton)).onPressed != null;

void main() {
  testWidgets('the folder has its own control, beside Add photos',
      (tester) async {
    final picker = _BothPicker(directory: _gogGames);
    await _pump(tester, picker: picker,
        folder: _folder(_gogGames, const ['setup_moor_1.9.exe', 'notes.txt']));

    expect(find.text('Add photos'), findsOneWidget);
    expect(find.byKey(const Key('add-games-folder')), findsOneWidget);
    expect(_scanEnabled(tester), isFalse);

    await _addFolder(tester);

    // The folder dialog was opened and the file dialog was not: one control,
    // one function.
    expect(picker.directoryCalls, 1);
    expect(picker.fileCalls, 0);
    expect(find.text('GOG Games'), findsOneWidget);
    expect(find.textContaining('2 entries to read'), findsOneWidget);
    expect(_scanEnabled(tester), isTrue);
  });

  testWidgets(
      'the control names the folder it wants, in the button and in the dialog',
      (tester) async {
    final picker = _BothPicker(directory: _gogGames);
    await _pump(tester, picker: picker);

    // Before anything is picked, the empty screen already names the second
    // input by what is kept in it rather than as "a folder".
    expect(find.byKey(const Key('folder-hint')), findsOneWidget);
    await _addFolder(tester);
    // T-0158's steer, verbatim where it is read at the moment of choosing:
    // the button lost the word "games" in T-0345 and this prompt did not.
    expect(
        picker.askedPrompt,
        'Pick the folder your games are installed in or your films are '
        'kept in');
  });

  // T-0345. The label said "games" while the same walk had read films since
  // T-0162, so a person with a folder of films had no reason to press it. The
  // establishment run is in doc/reports/T-0344.md: film-shaped names come back
  // through this control as film rows, unchanged, so what was wrong was the
  // label and not the reader.
  group('the folder control says what the scan actually reads (T-0345)', () {
    testWidgets('no control offers games only', (tester) async {
      await _pump(tester, picker: _BothPicker(directory: _gogGames));

      expect(find.text('Add media folder'), findsOneWidget);
      expect(find.text('Add games folder'), findsNothing);
      expect(find.textContaining('games and films'), findsOneWidget);
    });

    testWidgets('and the question before a mixed folder names both',
        (tester) async {
      await _pump(tester,
          picker: _BothPicker(directory: _downloads),
          folder: _folder(_downloads, const ['NoteWellSetup.exe']));

      await tester.tap(find.text('Add media folder'));
      await tester.pumpAndSettle();

      expect(find.text('Read games and films out of $_downloads?'),
          findsOneWidget);
    });

    testWidgets('a folder of films reaches review as film rows',
        (tester) async {
      // The walk itself is real I/O and never completes in this fake async
      // (see the seam's own comment), so the entries a folder of films
      // produces are handed in and what is pinned here is that the screen
      // carries them into a run and the kind survives to review.
      const films = 'films';
      final vision = await _pump(tester,
          picker: _BothPicker(directory: films),
          folder: _folder(films, const [
            'Tidewrack.1998.1080p.BluRay.x264-LANTERN.mkv',
            'Pale.Anchor.1994.720p.WEB-DL.h264-MOOR.mp4',
          ]));

      await _addFolder(tester);
      await tester.tap(find.text('Scan'));
      await tester.pumpAndSettle();

      expect(vision.seen, isEmpty, reason: 'no photograph, no vision call');
      expect(find.textContaining('Review ('), findsOneWidget);
      expect(find.textContaining('Tidewrack'), findsWidgets);
      // The kind clause the review row prints for anything but a game
      // (T-0340). Two rows, two films.
      expect(find.textContaining('- Film'), findsNWidgets(2));
    });

    testWidgets('and nothing offers or implies anime', (tester) async {
      // No source produces one: the filename grammar declines an episodic
      // name by DeclineReason.seriesEpisode, so a label covering anime would
      // cover nothing.
      await _pump(tester, picker: _BothPicker(directory: _gogGames));

      expect(find.textContaining('nime'), findsNothing);
    });
  });

  testWidgets('two presses inside one frame open one dialog (T-0116)',
      (tester) async {
    final gate = Completer<void>();
    final picker = _BothPicker(directory: _gogGames, gate: gate);
    await _pump(tester, picker: picker);

    // No pump between the taps: the second press reaches a button still built
    // as enabled, which is the press that produced a real stack.
    await tester.tap(find.byKey(const Key('add-games-folder')));
    await tester.tap(find.byKey(const Key('add-games-folder')));
    gate.complete();
    await tester.pumpAndSettle();

    expect(picker.directoryCalls, 1);
  });

  testWidgets('neither picker opens while the other one is up', (tester) async {
    final gate = Completer<void>();
    final picker = _BothPicker(
        directory: _gogGames, files: {'shelf1.jpg': _jpeg}, gate: gate);
    await _pump(tester, picker: picker);

    await tester.tap(find.byKey(const Key('add-games-folder')));
    await tester.pump();
    await tester.tap(find.text('Add photos'), warnIfMissed: false);
    await tester.pump();
    expect(picker.fileCalls, 0, reason: 'the folder dialog is still open');

    gate.complete();
    await tester.pumpAndSettle();
    expect(picker.directoryCalls, 1);
  });

  testWidgets('the control is dead during a run, and nothing opens if pressed',
      (tester) async {
    final gates = {'shelf1.jpg': Completer<void>()};
    final picker =
        _BothPicker(directory: _gogGames, files: {'shelf1.jpg': _jpeg});
    await _pump(tester, picker: picker, gates: gates);

    await tester.tap(find.text('Add photos'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan'));
    await tester.pump();

    final button = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Add media folder'));
    expect(button.onPressed, isNull);
    await tester.tap(find.byKey(const Key('add-games-folder')),
        warnIfMissed: false);
    await tester.pump();
    expect(picker.directoryCalls, 0);

    gates['shelf1.jpg']!.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('a folder can be taken back out, and not during a run',
      (tester) async {
    final gates = {'shelf1.jpg': Completer<void>()};
    final vision = await _pump(
      tester,
      picker:
          _BothPicker(directory: _gogGames, files: {'shelf1.jpg': _jpeg}),
      gates: gates,
    );

    await _addFolder(tester);
    await tester.tap(find.text('Add photos'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Scan'));
    await tester.pump();
    final locked = tester.widget<IconButton>(
        find.byKey(const Key('remove-folder-$_gogGames')));
    expect(locked.onPressed, isNull, reason: 'the run walks this list');

    gates['shelf1.jpg']!.complete();
    await tester.pumpAndSettle();
    expect(vision.seen, ['shelf1.jpg']);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('remove-folder-$_gogGames')));
    await tester.pump();
    expect(find.text('GOG Games'), findsNothing);
    expect(find.text('shelf1.jpg'), findsOneWidget);
  });

  testWidgets('the same folder twice is refused by name, not added twice',
      (tester) async {
    await _pump(tester, picker: _BothPicker(directory: _gogGames));

    await _addFolder(tester);
    await _addFolder(tester);

    expect(find.text('GOG Games'), findsOneWidget);
    expect(find.byKey(const Key('rejected-photos')), findsOneWidget);
    expect(find.textContaining('read the same folder twice'), findsOneWidget);
  });

  group('the folder the user did not mean', () {
    testWidgets('a downloads folder is questioned before it is read',
        (tester) async {
      await _pump(tester,
          picker: _BothPicker(directory: _downloads),
          folder: _folder(_downloads, const ['NoteWellSetup.exe']));

      await tester.tap(find.text('Add media folder'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('folder-concern')), findsOneWidget);
      expect(find.textContaining('not one of them is a game'), findsOneWidget);
      expect(find.textContaining('T-0158'), findsOneWidget);

      await tester.tap(find.byKey(const Key('folder-concern-cancel')));
      await tester.pumpAndSettle();
      expect(find.text('Downloads'), findsNothing);
      expect(_scanEnabled(tester), isFalse);
    });

    testWidgets('and added anyway if the user says so', (tester) async {
      await _pump(tester,
          picker: _BothPicker(directory: _downloads),
          folder: _folder(_downloads, const ['NoteWellSetup.exe']));

      await tester.tap(find.text('Add media folder'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('folder-concern-accept')));
      await tester.pumpAndSettle();

      expect(find.text('Downloads'), findsOneWidget);
      expect(_scanEnabled(tester), isTrue);
    });

    testWidgets('a games folder is not questioned at all', (tester) async {
      await _pump(tester, picker: _BothPicker(directory: _gogGames));

      await tester.tap(find.text('Add media folder'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('folder-concern')), findsNothing);
      expect(find.text('GOG Games'), findsOneWidget);
    });
  });

  testWidgets('a folder-only run asks the model nothing and needs no key',
      (tester) async {
    // Cloud with no key: `ProviderPolicy.build` throws a StateError for these
    // settings, so a run that survives them is one that built no provider.
    final vision = await _pump(tester,
        picker: _BothPicker(directory: _gogGames),
        backend: VisionBackend.cloud,
        folder:
            _folder(_gogGames, const ['setup_moor_1.9.exe', 'unins000.exe']));

    await _addFolder(tester);
    await tester.tap(find.text('Scan'));
    await tester.pumpAndSettle();

    expect(vision.seen, isEmpty);
    expect(find.textContaining('Review ('), findsOneWidget);
    expect(find.textContaining('moor'), findsWidgets);
  });
}
