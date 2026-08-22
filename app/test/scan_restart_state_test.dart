/// What a new scan starts on top of (T-0122).
///
/// Owner: a new run must clear the error log. Two red panels
/// look alike on this screen and exactly one of them is about the run: the
/// scan's warnings, which a new run clears, and the picker's rejections, which
/// T-0039 keeps deliberately -- a file rejected at the picker is still
/// rejected. Both halves are one sequence here, because clearing everything
/// and clearing nothing each pass half of it.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelfscan_app/provider_config.dart';
import 'package:shelfscan_app/screens/scan_screen.dart';
import 'package:shelfscan_app/settings_store.dart';
import 'package:shelfscan_core/shelfscan_core.dart';

import 'scan_picker_test.dart' show RecordingFilePicker;
import 'settings_store_test.dart' show RecordingStore;

final _jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, ...List.filled(32, 0)]);
final _notAPhoto = Uint8List.fromList('shelf1.jpg, shelf2.jpg'.codeUnits);

/// One provider for two runs: the first fails every photo, the second is held
/// open so the test can read the screen while the run is going rather than
/// after it has written its own warnings.
class _SwitchableVision implements VisionProvider {
  bool failEverything = true;
  Completer<void>? hold;

  @override
  Future<PhotoAnalysis> analyze(PhotoInput photo) async {
    if (failEverything) {
      throw Exception('Ollama 500: model runner has unexpectedly stopped');
    }
    await hold?.future;
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

final _warnings = find.byKey(const Key('scan-warnings'));
final _rejected = find.byKey(const Key('rejected-photos'));
final _status = find.byKey(const Key('scan-status'));

Finder _inside(Finder panel, String text) =>
    find.descendant(of: panel, matching: find.textContaining(text));

void main() {
  testWidgets('a new run clears the last run\'s errors and keeps the picker\'s '
      'rejections', (tester) async {
    final vision = _SwitchableVision();
    FilePicker.platform = RecordingFilePicker({
      'shelf1.jpg': _jpeg,
      'shelf2.jpg': _jpeg,
      'notes.txt': _notAPhoto,
    });
    await tester.pumpWidget(MaterialApp(
      home: ScanScreen(
        settings: ProviderSettings(backend: VisionBackend.local),
        store:
            SettingsStore(secrets: RecordingStore(), prefs: RecordingStore()),
        debugVisionProvider: vision,
      ),
    ));

    await tester.tap(find.text('Add photos'));
    await tester.pumpAndSettle();
    expect(_inside(_rejected, 'notes.txt'), findsOneWidget);

    // Run 1: every photo dies, so the screen ends up holding both kinds of
    // report at once -- a warning per photo and the sentence on the status
    // line -- and no review is pushed over them.
    await tester.tap(find.text('Scan'));
    await tester.pumpAndSettle();
    expect(_inside(_warnings, 'shelf1.jpg'), findsOneWidget);
    expect(_inside(_warnings, 'Ollama 500'), findsNWidgets(2));
    expect(_status, findsOneWidget);
    expect(_inside(_rejected, 'notes.txt'), findsOneWidget);

    // Run 2, read while it is still going: what it writes itself would
    // otherwise be indistinguishable from what it failed to clear.
    vision
      ..failEverything = false
      ..hold = Completer<void>();
    await tester.tap(find.text('Scan'));
    await tester.pump();

    expect(find.byKey(const Key('scan-progress')), findsOneWidget,
        reason: 'the second run is under way, not finished');
    expect(_warnings, findsNothing);
    expect(_status, findsNothing);
    expect(_inside(_rejected, 'notes.txt'), findsOneWidget,
        reason: 'the file is still rejected -- T-0039');
    expect(find.byKey(const Key('rejected-photos-heading')), findsOneWidget);

    vision.hold!.complete();
    await tester.pumpAndSettle();
    expect(find.text('READ shelf1.jpg'), findsOneWidget,
        reason: 'the run finished and handed over to review');
  });

  testWidgets('the two panels say which run each is about', (tester) async {
    final vision = _SwitchableVision();
    FilePicker.platform = RecordingFilePicker({
      'shelf1.jpg': _jpeg,
      'notes.txt': _notAPhoto,
    });
    await tester.pumpWidget(MaterialApp(
      home: ScanScreen(
        settings: ProviderSettings(backend: VisionBackend.local),
        store:
            SettingsStore(secrets: RecordingStore(), prefs: RecordingStore()),
        debugVisionProvider: vision,
      ),
    ));

    await tester.tap(find.text('Add photos'));
    await tester.pumpAndSettle();
    // Nothing has run, so the surviving panel must not read as a scan's log.
    expect(find.byKey(const Key('rejected-photos-heading')), findsOneWidget);
    expect(find.text('From your last pick, not from a scan:'), findsOneWidget);
    expect(find.byKey(const Key('scan-warnings-heading')), findsNothing);

    await tester.tap(find.text('Scan'));
    await tester.pumpAndSettle();
    // A run of a photograph that read cleanly still has the endpoint's own
    // notes to report, and those are failures (T-0222).
    expect(find.text('Went wrong in this scan:'), findsOneWidget);
  });
}
