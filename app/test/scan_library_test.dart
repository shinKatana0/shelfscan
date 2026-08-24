/// The GOG library control on the scan screen (T-0179).
///
/// T-0177 shipped `app/lib/galaxy_db.dart` and nothing in the UI called it, so
/// in the app the feature did not exist. What is pinned here is that it has a
/// control of its own, that the control obeys the four things this screen has
/// already learned -- one dialog per press (T-0116), a list that can be pruned
/// (T-0138), nothing added during a run (T-0121), what is dropped is named
/// rather than counted (T-0123/T-0140) -- and that a run mixing photographs
/// with the library is ONE run, so a disc and the same game in the library are
/// one row.
///
/// The read itself is not here: it copies a 3 MB database and queries it over
/// `dart:ffi` on another isolate, none of which completes inside
/// `testWidgets`'s fake async, and the real file is a real purchases file.
/// The screen therefore takes a reader seam and `galaxy_db_test.dart` drives
/// the real reader against real databases, as a plain test. Every title below
/// is invented or a public GOG store id quoted from doc/measurements.md, "The
/// exact join".
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:shelfscan_app/input_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelfscan_app/galaxy_db.dart';
import 'package:shelfscan_app/media_folders.dart';
import 'package:shelfscan_app/photo_files.dart';
import 'package:shelfscan_app/provider_config.dart';
import 'package:shelfscan_app/screens/scan_screen.dart';
import 'package:shelfscan_app/settings_store.dart';
import 'package:shelfscan_core/shelfscan_core.dart';

import 'settings_store_test.dart' show RecordingStore;

final _jpeg =
    Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, ...List.filled(32, 0)]);

/// MOOR (1993) on GOG's own store.
const _moorId = '1100000002';

const _gogGames = r'C:\GOG Games';

SourceEntry _release(String id, String title,
        {int isDlc = 0, int visible = 1}) =>
    SourceEntry(
      name: 'gog_$id',
      content: galaxyRowToJson(
          'gog_$id', jsonEncode({'title': title}), isDlc, visible),
    );

GalaxyLibrary _library(List<SourceEntry> entries) => GalaxyLibrary(
      entries: entries,
      asOf: DateTime(2026, 8, 16, 14, 51),
      schemaVersion: galaxySchemaVersion,
    );

MediaFolder _folder(String path, List<String> names) => MediaFolder(
      path: path,
      name: folderName(path),
      entries: [
        for (final name in names)
          SourceEntry(name: name, container: folderName(path))
      ],
    );

/// Answers both file dialogs, so the guard can be tested across all three
/// controls: what stacked explorers for the owner was one dialog per press.
class _BothPicker extends InputPicker {
  _BothPicker({this.directory, this.files = const {}, this.gate});

  final String? directory;
  final Map<String, Uint8List> files;
  final Completer<void>? gate;
  int directoryCalls = 0;
  int fileCalls = 0;

  @override
  Future<String?> pickFolder({required String prompt}) async {
    directoryCalls++;
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

/// Records what the model was asked to read: a library run must ask it
/// nothing, which no assertion about the screen can reach.
class _RecordingVision implements VisionProvider {
  _RecordingVision({this.gates = const {}, this.title = 'READ'});

  final Map<String, Completer<void>> gates;
  final String title;
  final seen = <String>[];

  @override
  Future<PhotoAnalysis> analyze(PhotoInput photo) async {
    seen.add(photo.name);
    await gates[photo.name]?.future;
    return PhotoAnalysis(
      items: [
        Detection(
          rawTitle: title,
          // The same hint the library row carries. Dedupe groups by hint and a
          // hintless read is its own row beside a hinted one, deliberately
          // (T-0018-01): the physical object that pairs with a GOG library row
          // is a boxed PC game, and it says PC on the spine.
          platformHint: GogMetadataSource.platformHint,
          mediaType: MediaType.disc,
          confidence: 1.0,
          sourcePhoto: photo.name,
        ),
      ],
      unreadable: const [],
    );
  }
}

/// The reader seam, plus a count of how many times it was actually called.
class _Reader {
  _Reader(this._answer, {this.gate});

  final Future<GalaxyLibrary> Function() _answer;
  final Completer<void>? gate;
  int calls = 0;

  Future<GalaxyLibrary> read() async {
    calls++;
    await gate?.future;
    return _answer();
  }
}

Future<(_RecordingVision, _Reader)> _pump(
  WidgetTester tester, {
  required _BothPicker picker,
  VisionBackend backend = VisionBackend.local,
  Map<String, Completer<void>> gates = const {},
  GalaxyLibrary? library,
  Object? readerThrows,
  Completer<void>? readerGate,
  String visionTitle = 'READ',
  MediaFolder? folder,
  String? operatingSystem,
}) async {
  final vision = _RecordingVision(gates: gates, title: visionTitle);
  final held = library ?? _library([_release(_moorId, 'MOOR')]);
  final reader = _Reader(
    () async {
      if (readerThrows != null) throw readerThrows;
      return held;
    },
    gate: readerGate,
  );
  await tester.pumpWidget(MaterialApp(
    home: ScanScreen(
      settings: ProviderSettings(backend: backend),
      store: SettingsStore(secrets: RecordingStore(), prefs: RecordingStore()),
      picker: picker,
      debugVisionProvider: vision,
      debugLibraryReader: reader.read,
      debugFolderReader: (path) async => folder ?? _folder(path, const []),
      debugOperatingSystem: operatingSystem,
    ),
  ));
  return (vision, reader);
}

Future<void> _addLibrary(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('add-gog-library')));
  await tester.pumpAndSettle();
}

bool _scanEnabled(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byType(FilledButton)).onPressed != null;

void main() {
  testWidgets('the library has its own control, beside the folder one',
      (tester) async {
    final (_, reader) =
        await _pump(tester, picker: _BothPicker(directory: _gogGames));

    // Named on the empty screen before anything is added, where the second
    // input is named too.
    expect(find.byKey(const Key('library-hint')), findsOneWidget);
    expect(find.byKey(const Key('add-gog-library')), findsOneWidget);
    expect(find.byKey(const Key('add-games-folder')), findsOneWidget);
    expect(_scanEnabled(tester), isFalse);

    await _addLibrary(tester);

    expect(reader.calls, 1);
    expect(find.byKey(const Key('library-input')), findsOneWidget);
    expect(_scanEnabled(tester), isTrue);
  });

  // T-0344. The owner pressed this on a phone and nothing happened. Galaxy is
  // a Windows program, so on any other host there is no database and no press
  // could have worked -- the control is therefore not offered, and the reason
  // takes its place. Both directions are pinned here because the host these
  // tests run on can only ever be one of them.
  group('a host that cannot have Galaxy is not offered it (T-0344)', () {
    testWidgets('the control is absent, not dead', (tester) async {
      final (_, reader) = await _pump(tester,
          picker: _BothPicker(), operatingSystem: 'android');

      expect(find.byKey(const Key('add-gog-library')), findsNothing);
      // Not merely disabled: a greyed control that does nothing when pressed
      // is what was reported, and would read as the same defect.
      expect(find.text('Add GOG library'), findsNothing);
      expect(reader.calls, 0);

      // The two inputs this host does have are untouched.
      expect(find.text('Add photos'), findsOneWidget);
      expect(find.byKey(const Key('add-games-folder')), findsOneWidget);
    });

    testWidgets('the offer is replaced by why, in the reader\'s own words',
        (tester) async {
      await _pump(tester, picker: _BothPicker(), operatingSystem: 'android');

      expect(find.byKey(const Key('library-hint')), findsNothing);
      expect(find.byKey(const Key('no-library-here')), findsOneWidget);
      // galaxyUnsupported, so the screen and the reader name the platform
      // identically and cannot drift.
      expect(find.text(galaxyUnsupported('android')!), findsOneWidget);
    });

    testWidgets('a host that can have it is offered it', (tester) async {
      await _pump(tester, picker: _BothPicker(), operatingSystem: 'windows');

      expect(find.byKey(const Key('add-gog-library')), findsOneWidget);
      expect(find.byKey(const Key('library-hint')), findsOneWidget);
      expect(find.byKey(const Key('no-library-here')), findsNothing);
    });
  });

  testWidgets('it says how old the cache is, before the row count means '
      'anything', (tester) async {
    await _pump(tester, picker: _BothPicker(),
        library: _library(
            [_release(_moorId, 'MOOR'), _release('1100000014', 'Another')]));

    await _addLibrary(tester);

    expect(find.textContaining('2 releases to read'), findsOneWidget);
    // The staleness sentence itself, in the reader's own words -- a game
    // bought since the last sync is missing from this list.
    expect(find.textContaining('a local cache of the last sync'),
        findsOneWidget);
  });

  testWidgets('two presses inside one frame read the database once (T-0116)',
      (tester) async {
    final gate = Completer<void>();
    final (_, reader) =
        await _pump(tester, picker: _BothPicker(), readerGate: gate);

    // No pump between the taps: the second press reaches a control still built
    // as enabled, which is the press that produced a real stack of
    // explorers on the pickers.
    await tester.tap(find.byKey(const Key('add-gog-library')));
    await tester.tap(find.byKey(const Key('add-gog-library')));
    gate.complete();
    await tester.pumpAndSettle();

    expect(reader.calls, 1);
  });

  testWidgets('no picker opens while the library is being read', (tester) async {
    final gate = Completer<void>();
    final picker =
        _BothPicker(directory: _gogGames, files: {'shelf1.jpg': _jpeg});
    await _pump(tester, picker: picker, readerGate: gate);

    await tester.tap(find.byKey(const Key('add-gog-library')));
    await tester.pump();
    await tester.tap(find.text('Add photos'), warnIfMissed: false);
    await tester.tap(find.byKey(const Key('add-games-folder')),
        warnIfMissed: false);
    await tester.pump();

    expect(picker.fileCalls, 0, reason: 'the library read is still in flight');
    expect(picker.directoryCalls, 0);

    gate.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('and it does not read while a picker is up', (tester) async {
    final gate = Completer<void>();
    final (_, reader) = await _pump(tester,
        picker: _BothPicker(directory: _gogGames, gate: gate));

    await tester.tap(find.byKey(const Key('add-games-folder')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('add-gog-library')),
        warnIfMissed: false);
    await tester.pump();
    expect(reader.calls, 0, reason: 'the folder dialog is still open');

    gate.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('the control is dead during a run, and nothing is read if '
      'pressed', (tester) async {
    final gates = {'shelf1.jpg': Completer<void>()};
    final (_, reader) = await _pump(tester,
        picker: _BothPicker(files: {'shelf1.jpg': _jpeg}), gates: gates);

    await tester.tap(find.text('Add photos'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan'));
    await tester.pump();

    final button = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Add GOG library'));
    expect(button.onPressed, isNull);
    await tester.tap(find.byKey(const Key('add-gog-library')),
        warnIfMissed: false);
    await tester.pump();
    expect(reader.calls, 0);

    gates['shelf1.jpg']!.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('it can be taken back out, and not during a run (T-0138)',
      (tester) async {
    final gates = {'shelf1.jpg': Completer<void>()};
    await _pump(tester,
        picker: _BothPicker(files: {'shelf1.jpg': _jpeg}), gates: gates);

    await _addLibrary(tester);
    await tester.tap(find.text('Add photos'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Scan'));
    await tester.pump();
    final locked =
        tester.widget<IconButton>(find.byKey(const Key('remove-library')));
    expect(locked.onPressed, isNull, reason: 'the run walks this input');

    gates['shelf1.jpg']!.complete();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('remove-library')));
    await tester.pump();
    expect(find.byKey(const Key('library-input')), findsNothing);
    expect(find.text('shelf1.jpg'), findsOneWidget);
  });

  testWidgets('adding it twice is refused by name, not silently ignored',
      (tester) async {
    final (_, reader) = await _pump(tester, picker: _BothPicker());

    await _addLibrary(tester);
    await _addLibrary(tester);

    expect(reader.calls, 1);
    expect(find.byKey(const Key('library-input')), findsOneWidget);
    expect(find.byKey(const Key('rejected-photos')), findsOneWidget);
    expect(find.textContaining('remove it first'), findsOneWidget);
  });

  testWidgets('a host with no Galaxy is named, not left silent', (tester) async {
    await _pump(tester, picker: _BothPicker(),
        readerThrows: GalaxyLibraryException(galaxyUnsupported('android')!));

    await _addLibrary(tester);

    // The same shape as `heicDecodeUnsupported`: the platform is named rather
    // than a read being attempted and failing obscurely.
    expect(find.byKey(const Key('library-input')), findsNothing);
    expect(find.textContaining('GOG Galaxy does not run on android'),
        findsOneWidget);
    expect(_scanEnabled(tester), isFalse);
  });

  testWidgets('an absent database is named with what to do about it',
      (tester) async {
    await _pump(tester, picker: _BothPicker(),
        readerThrows: GalaxyLibraryException(
            'No GOG Galaxy library database at C:\\nowhere.db.'));

    await _addLibrary(tester);

    expect(find.textContaining('No GOG Galaxy library database'),
        findsOneWidget);
  });

  testWidgets('a library-only run asks the model nothing and needs no key',
      (tester) async {
    // Cloud with no key: `ProviderPolicy.build` throws a StateError for these
    // settings, so a run that survives them is one that built no provider.
    final (vision, _) = await _pump(tester, picker: _BothPicker(),
        backend: VisionBackend.cloud,
        library: _library([_release(_moorId, 'MOOR')]));

    await _addLibrary(tester);
    await tester.tap(find.text('Scan'));
    await tester.pumpAndSettle();

    expect(vision.seen, isEmpty);
    expect(find.textContaining('Review ('), findsOneWidget);
    expect(find.textContaining('MOOR'), findsWidgets);
  });

  testWidgets('what the library declines is named, not counted', (tester) async {
    await _pump(tester, picker: _BothPicker(), library: _library([
      _release(_moorId, 'MOOR'),
      _release('1100000017', 'MOOR - Soundtrack', isDlc: 1),
    ]));

    await _addLibrary(tester);
    await tester.tap(find.text('Scan'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    // One row exported, and the release that did not become one is on the
    // screen with its reason rather than folded into a count.
    expect(find.byKey(const Key('scan-warnings')), findsOneWidget);
    expect(find.textContaining('gog_1100000017'), findsOneWidget);
  });

  testWidgets('photos and the library are ONE run: a disc and the same game '
      'owned are one row', (tester) async {
    final (vision, _) = await _pump(tester,
        picker: _BothPicker(files: {'shelf1.jpg': _jpeg}),
        visionTitle: 'MOOR', library: _library([_release(_moorId, 'MOOR')]));

    await _addLibrary(tester);
    await tester.tap(find.text('Add photos'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan'));
    await tester.pumpAndSettle();

    // The photo really was read -- this is not a library-only run wearing a
    // photo's name -- and the two inputs still produced one row.
    expect(vision.seen, ['shelf1.jpg']);
    expect(find.text('Review (0/1 to export)'), findsOneWidget);
  });

  testWidgets('a folder and the library in one run are two sources, not one',
      (tester) async {
    final (vision, _) = await _pump(
      tester,
      picker: _BothPicker(directory: _gogGames),
      folder: _folder(_gogGames, const ['setup_harbour_lantern_1.6.15.exe']),
      library: _library([_release(_moorId, 'MOOR')]),
    );

    await tester.tap(find.byKey(const Key('add-games-folder')));
    await tester.pumpAndSettle();
    await _addLibrary(tester);
    await tester.tap(find.text('Scan'));
    await tester.pumpAndSettle();

    // Each list is read by the source that owns it -- a `gog_<id>` row is not
    // a file name and a `setup_*.exe` is not a library row -- which is why the
    // screen states the pairing rather than letting one source guess.
    expect(vision.seen, isEmpty);
    expect(find.text('Review (0/2 to export)'), findsOneWidget);
  });
}
