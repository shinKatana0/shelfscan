/// What the review screen says about a photo the user stopped before (T-0140).
///
/// The defect: every photo missing from the document went into one list called
/// `failedPhotos`, and the banner over the review read "could not be scanned"
/// for all of them -- so a photo the user's own Stop kept out of the run was
/// reported as a failure of the provider, the file or the network. The names
/// were right and nothing was hidden; the sentence was wrong.
///
/// These run the real [Orchestrator] behind a fake provider, so the stop line
/// the screen classifies on is the one core actually writes.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelfscan_app/provider_config.dart';
import 'package:shelfscan_app/screens/scan_screen.dart';
import 'package:shelfscan_app/settings_store.dart';
import 'package:shelfscan_core/shelfscan_core.dart';

import 'scan_wiring_test.dart' show FakeInputPicker;
import 'settings_store_test.dart' show RecordingStore;

/// Fails the photos in [fails], holds the rest at their own gate so the test
/// can put a stop in the middle of a run.
class _StagedVision implements VisionProvider {
  _StagedVision({this.gates = const {}, this.fails = const {}});

  final Map<String, Completer<void>> gates;
  final Set<String> fails;
  final asked = <String>[];

  @override
  Future<PhotoAnalysis> analyze(PhotoInput photo) async {
    asked.add(photo.name);
    if (fails.contains(photo.name)) {
      throw Exception('Ollama 500: model runner has unexpectedly stopped');
    }
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

final _stopControl = find.byKey(const Key('scan-stop'));
final _failedBanner = find.byKey(const Key('failed-photos-banner'));
final _stoppedBanner = find.byKey(const Key('stopped-photos-banner'));

Finder _inBanner(Finder banner, String text) =>
    find.descendant(of: banner, matching: find.text(text));

/// Local runs one photo at a time (ProviderPolicy.visionConcurrency), so the
/// photos are sent in order and exactly one is in flight when the stop lands.
Future<_StagedVision> _runToStop(
  WidgetTester tester, {
  required List<String> photos,
  required _StagedVision vision,
  required int stopAfterAsked,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: ScanScreen(
      settings: ProviderSettings(backend: VisionBackend.local),
      store: SettingsStore(secrets: RecordingStore(), prefs: RecordingStore()),
      picker: FakeInputPicker(photos),
      debugVisionProvider: vision,
    ),
  ));
  await tester.tap(find.text('Add photos'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Scan'));
  // Pump first and count after: the pool reaches the first photo's own await
  // inside the tap, so `asked` grows before any frame exists to stop from.
  for (var i = 0; i < 50; i++) {
    await tester.pump();
    if (vision.asked.length >= stopAfterAsked) break;
  }
  expect(vision.asked.length, stopAfterAsked,
      reason: 'the stop has to land while the run is going');
  await tester.tap(_stopControl);
  await tester.pump();
  for (final gate in vision.gates.values) {
    if (!gate.isCompleted) gate.complete();
  }
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('resume-review-button')));
  await tester.pumpAndSettle();
  return vision;
}

void main() {
  testWidgets('a photo the stop reached is not called a failure',
      (tester) async {
    final vision = await _runToStop(
      tester,
      photos: ['shelf1.jpg', 'shelf2.jpg'],
      vision: _StagedVision(gates: {'shelf1.jpg': Completer<void>()}),
      stopAfterAsked: 1,
    );

    expect(vision.asked, ['shelf1.jpg'], reason: 'shelf2.jpg was never sent');
    expect(_failedBanner, findsNothing);
    expect(find.textContaining('could not be scanned'), findsNothing);

    expect(_stoppedBanner, findsOneWidget);
    expect(_inBanner(_stoppedBanner, '1 of 2 photos was not looked at'),
        findsOneWidget);
    expect(
      _inBanner(_stoppedBanner, 'The scan was stopped before shelf2.jpg -- '
          'nothing from it is in this list.'),
      findsOneWidget,
    );
  });

  testWidgets('a failure and a stop in one run get one banner each',
      (tester) async {
    final vision = await _runToStop(
      tester,
      photos: ['shelf1.jpg', 'shelf2.jpg', 'shelf3.jpg'],
      vision: _StagedVision(
        gates: {'shelf2.jpg': Completer<void>()},
        fails: {'shelf1.jpg'},
      ),
      stopAfterAsked: 2,
    );

    expect(vision.asked, ['shelf1.jpg', 'shelf2.jpg'],
        reason: 'shelf3.jpg was never sent');
    // Only shelf2 was read, so the review covers one photo of three and each
    // of the other two is accounted for in its own words.
    expect(find.text('DUSKHOLLOW shelf2.jpg'), findsOneWidget);

    expect(
      _inBanner(_failedBanner, '1 of 3 photos could not be scanned'),
      findsOneWidget,
    );
    expect(
      _inBanner(_failedBanner,
          'shelf1.jpg -- nothing from it is in this list.'),
      findsOneWidget,
    );
    expect(
      _inBanner(_stoppedBanner, '1 of 3 photos was not looked at'),
      findsOneWidget,
    );
    expect(
      _inBanner(_stoppedBanner, 'The scan was stopped before shelf3.jpg -- '
          'nothing from it is in this list.'),
      findsOneWidget,
    );
  });
}
