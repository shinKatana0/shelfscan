/// The Stop control on the scan screen (T-0121).
///
/// The defect: once Scan was pressed the run went to completion, and the owner
/// hit that while a misconfigured cloud model was burning calls. So the test
/// that matters asserts what the provider was NEVER asked for after the tap --
/// a button that only hid the progress bar would pass every other assertion
/// here.
library;

import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelfscan_app/provider_config.dart';
import 'package:shelfscan_app/screens/scan_screen.dart';
import 'package:shelfscan_app/settings_store.dart';
import 'package:shelfscan_core/shelfscan_core.dart';

import 'scan_wiring_test.dart' show FakeFilePicker;
import 'settings_store_test.dart' show RecordingStore;

/// Holds each photo at its own gate and records what it was handed, so the
/// test can stop the run at a chosen point and then read what followed.
class _GatedVision implements VisionProvider {
  _GatedVision(this.gates);

  final Map<String, Completer<void>> gates;
  final asked = <String>[];

  @override
  Future<PhotoAnalysis> analyze(PhotoInput photo) async {
    asked.add(photo.name);
    await gates[photo.name]?.future;
    return PhotoAnalysis(
      items: [
        Detection(
          rawTitle: 'DUSKHOLLOW ${photo.name}',
          mediaType: MediaType.disc,
          confidence: 1.0,
          sourcePhoto: photo.name,
        ),
      ],
      unreadable: const [],
    );
  }
}

final _stop = find.byKey(const Key('scan-stop'));
final _bar = find.byKey(const Key('scan-progress'));

bool _enabled(WidgetTester tester, Finder button) =>
    tester.widget<ButtonStyleButton>(button).onPressed != null;

Finder _scanButton() => find.ancestor(
    of: find.text('Scan'), matching: find.byType(FilledButton));

ScanScreen _screen(_GatedVision vision) => ScanScreen(
      // Local runs one photo at a time (ProviderPolicy.visionConcurrency), so
      // exactly one photo is in flight when the stop arrives.
      settings: ProviderSettings(backend: VisionBackend.local),
      store: SettingsStore(secrets: RecordingStore(), prefs: RecordingStore()),
      debugVisionProvider: vision,
    );

void main() {
  testWidgets('there is no stop control until a run is going', (tester) async {
    final gates = {'shelf1.jpg': Completer<void>()};
    FilePicker.platform = FakeFilePicker(gates.keys.toList());
    final vision = _GatedVision(gates);
    await tester.pumpWidget(MaterialApp(home: _screen(vision)));

    expect(_stop, findsNothing);

    await tester.tap(find.text('Add photos'));
    await tester.pumpAndSettle();
    expect(_stop, findsNothing, reason: 'photos chosen is not a run');

    await tester.tap(find.text('Scan'));
    await tester.pump();
    expect(_stop, findsOneWidget);

    gates['shelf1.jpg']!.complete();
    await tester.pumpAndSettle();

    // The run handed over to review, so there is nothing left to stop.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(_stop, findsNothing);
    expect(_bar, findsNothing);
  });

  testWidgets('stopping a run sends no further photo and says what it kept',
      (tester) async {
    final gates = {
      'shelf1.jpg': Completer<void>(),
      'shelf2.jpg': Completer<void>(),
      'shelf3.jpg': Completer<void>(),
    };
    FilePicker.platform = FakeFilePicker(gates.keys.toList());
    final vision = _GatedVision(gates);
    await tester.pumpWidget(MaterialApp(home: _screen(vision)));

    await tester.tap(find.text('Add photos'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan'));
    await tester.pump();

    gates['shelf1.jpg']!.complete();
    await tester.pump();
    await tester.pump();
    expect(vision.asked, ['shelf1.jpg', 'shelf2.jpg'],
        reason: 'the second photo is in flight when the stop arrives');

    await tester.tap(_stop);
    await tester.pump();

    // Still running: what is in flight is still in flight, and the screen must
    // not claim otherwise.
    expect(_bar, findsOneWidget);
    expect(_enabled(tester, _stop), isFalse);
    expect(find.text('Stopping...'), findsOneWidget);
    expect(_enabled(tester, _scanButton()), isFalse,
        reason: 'a second run must not start while the first is stopping');

    gates['shelf2.jpg']!.complete();
    await tester.pumpAndSettle();

    expect(vision.asked, ['shelf1.jpg', 'shelf2.jpg'],
        reason: 'shelf3.jpg must never have been sent');
    expect(_bar, findsNothing);
    expect(_stop, findsNothing);

    // The two photos that were read are kept, and the one that was not is
    // named -- here and in the warning line the summary points at.
    final status = tester.widget<Text>(find.byKey(const Key('scan-status')));
    expect(status.data, contains('2 items from 2 of 3 photos'));
    expect(status.data, contains('shelf3.jpg'));
    expect(find.textContaining('Stopped before shelf3.jpg'), findsOneWidget);

    // The review is held rather than pushed: the account of the stop is what
    // the user asked for, and Resume review is the way into the rest.
    expect(find.byKey(const Key('resume-review')), findsOneWidget);
    expect(find.text('Last scan: 2 items, 0 marked'), findsOneWidget);
    expect(find.text('Add photos'), findsOneWidget,
        reason: 'a stopped run stays on the scan screen');

    await tester.tap(find.byKey(const Key('resume-review-button')));
    await tester.pumpAndSettle();
    expect(find.text('DUSKHOLLOW shelf1.jpg'), findsOneWidget);
    expect(find.text('DUSKHOLLOW shelf3.jpg'), findsNothing);
  });

  testWidgets('a stop before anything was read opens no review at all',
      (tester) async {
    final gates = {
      'shelf1.jpg': Completer<void>(),
      'shelf2.jpg': Completer<void>(),
    };
    FilePicker.platform = FakeFilePicker(gates.keys.toList());
    final vision = _GatedVision(gates);
    await tester.pumpWidget(MaterialApp(home: _screen(vision)));

    await tester.tap(find.text('Add photos'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan'));
    await tester.pump();

    await tester.tap(_stop);
    await tester.pump();
    // The photo in flight still finishes; it is the only one that ever
    // started, and it fails, so nothing survives the run.
    gates['shelf1.jpg']!.completeError(StateError('vision is down'));
    await tester.pumpAndSettle();

    expect(vision.asked, ['shelf1.jpg']);
    final status = tester.widget<Text>(find.byKey(const Key('scan-status')));
    expect(status.data, contains('Stopped before any photo was read'));
    expect(status.data, contains('shelf2.jpg'));
    expect(find.byKey(const Key('resume-review')), findsNothing);
    // A stop is not a condition Settings can fix, so no shortcut is offered.
    expect(find.byKey(const Key('status-open-settings')), findsNothing);
  });
}
