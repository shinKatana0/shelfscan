/// What the scan screen shows while a run is in flight (T-0041).
///
/// The defect this pins: an ~80 s three-photo local run reported itself as
/// one line of text, which reads as a hang. `onItem` already carries
/// `done / total`, so the bar is determinate wherever a stage counts, and
/// indeterminate -- not stuck at zero -- where one does not.
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

/// Holds each photo until its own gate is opened, so a test can look at the
/// screen at a chosen point of the run.
class GatedVision implements VisionProvider {
  GatedVision(this.gates);

  final Map<String, Completer<void>> gates;

  @override
  Future<PhotoAnalysis> analyze(PhotoInput photo) async {
    await gates[photo.name]?.future;
    return PhotoAnalysis(
      items: [
        Detection(
          rawTitle: 'DUSKHOLLOW',
          mediaType: MediaType.disc,
          confidence: 1.0,
          sourcePhoto: photo.name,
          platformHint: 'PS4',
        ),
      ],
      unreadable: const [],
    );
  }
}

final _bar = find.byKey(const Key('scan-progress'));

LinearProgressIndicator _indicator(WidgetTester tester) =>
    tester.widget<LinearProgressIndicator>(_bar);

void main() {
  testWidgets('the bar is determinate once a stage reports a total, with the '
      'stage still named beside it', (tester) async {
    final gates = {
      'shelf1.jpg': Completer<void>(),
      'shelf2.jpg': Completer<void>(),
    };
    await tester.pumpWidget(MaterialApp(
      home: ScanScreen(
        picker: FakeInputPicker(gates.keys.toList()),
        // Local runs one photo at a time (ProviderPolicy.visionConcurrency),
        // so the gates open the run one countable step at a time.
        settings: ProviderSettings(backend: VisionBackend.local),
        store: SettingsStore(secrets: RecordingStore(), prefs: RecordingStore()),
        debugVisionProvider: GatedVision(gates),
      ),
    ));

    // Nothing is running yet.
    expect(_bar, findsNothing);

    await tester.tap(find.text('Add photos'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan'));
    await tester.pump();

    // Vision has started but counted nothing yet: indeterminate, and saying
    // which stage it is rather than showing a bar pinned at zero.
    expect(_bar, findsOneWidget);
    expect(_indicator(tester).value, isNull);
    expect(find.text('Reading photos'), findsOneWidget);
    expect(find.text('working...'), findsOneWidget);

    gates['shelf1.jpg']!.complete();
    await tester.pump();
    await tester.pump();

    expect(_indicator(tester).value, 0.5);
    expect(find.text('1 / 2'), findsOneWidget);
    expect(find.text('Reading photos'), findsOneWidget);

    gates['shelf2.jpg']!.complete();
    await tester.pumpAndSettle();

    // The run has handed over to review; nothing is in flight to report.
    expect(_bar, findsNothing);
    expect(find.text('DUSKHOLLOW'), findsOneWidget);
  });

  testWidgets('a run that dies takes the bar with it', (tester) async {
    // A bar left spinning over an error message is the same lie as a bar
    // stuck at zero.
    await tester.pumpWidget(MaterialApp(
      home: ScanScreen(
        picker: FakeInputPicker(['shelf1.jpg']),
        settings: ProviderSettings(backend: VisionBackend.cloud),
        store: SettingsStore(secrets: RecordingStore(), prefs: RecordingStore()),
      ),
    ));

    await tester.tap(find.text('Add photos'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan'));
    await tester.pumpAndSettle();

    expect(find.textContaining('needs an Anthropic API key'), findsOneWidget);
    expect(_bar, findsNothing);
  });
}
