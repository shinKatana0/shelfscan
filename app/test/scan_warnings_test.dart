/// What the app does with a pipeline warning (T-0030).
///
/// The bug this pins: the scan screen used to pass `onStage` and `onItem`
/// and nothing for `onWarning`, so a photo whose vision call died vanished
/// -- the review screen opened built from whichever photos happened to work,
/// with nothing saying so. Measured case: during the 32B run one photo died
/// with `Ollama 500` after retries, losing that photograph's whole share.
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

/// Reads every photo except [fails], which dies the way a provider dies.
///
/// [gate], when given, holds back the photos that do not fail, so a test can
/// assert what the screen shows *while* the run is still going.
class PartlyFailingVision implements VisionProvider {
  PartlyFailingVision({this.fails, this.gate});

  final String? fails;
  final Completer<void>? gate;

  @override
  Future<PhotoAnalysis> analyze(PhotoInput photo) async {
    if (photo.name == fails) {
      throw Exception('Ollama 500: model runner has unexpectedly stopped');
    }
    await gate?.future;
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

Future<void> _pumpScan(
  WidgetTester tester, {
  required List<String> photos,
  required VisionProvider vision,
  ProviderSettings? settings,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: ScanScreen(
      picker: FakeInputPicker(photos),
      settings: settings ?? ProviderSettings(backend: VisionBackend.local),
      store: SettingsStore(secrets: RecordingStore(), prefs: RecordingStore()),
      debugVisionProvider: vision,
    ),
  ));
  await tester.tap(find.text('Add photos'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Scan'));
}

Finder _warning(String text) => find.descendant(
      of: find.byKey(const Key('scan-warnings')),
      matching: find.textContaining(text),
    );

final _banner = find.byKey(const Key('failed-photos-banner'));

void main() {
  testWidgets('a photo lost mid-run is named while the run is still going',
      (tester) async {
    final gate = Completer<void>();
    await _pumpScan(
      tester,
      photos: ['shelf1.jpg', 'shelf2.jpg'],
      vision: PartlyFailingVision(fails: 'shelf1.jpg', gate: gate),
    );

    // shelf1 has died; shelf2 is still held at the gate, so this is the
    // middle of the run, not its report.
    await tester.pump();
    await tester.pump();
    expect(_warning('shelf1.jpg'), findsOneWidget);
    expect(_warning('Ollama 500'), findsOneWidget);
    expect(find.text('shelfscan'), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();

    expect(_banner, findsOneWidget);
    expect(
      find.descendant(of: _banner, matching: find.text('shelf1.jpg -- '
          'nothing from it is in this list.')),
      findsOneWidget,
    );
    expect(
      find.descendant(
          of: _banner, matching: find.text('1 of 2 photos could not be '
              'scanned')),
      findsOneWidget,
    );
    // Only the photo that survived is behind the list being reviewed.
    expect(find.text('DUSKHOLLOW'), findsOneWidget);
  });

  testWidgets('a clean run shows no warning affordance anywhere',
      (tester) async {
    await _pumpScan(
      tester,
      photos: ['shelf1.jpg', 'shelf2.jpg'],
      vision: PartlyFailingVision(),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('scan-warnings')), findsNothing);
    expect(_banner, findsNothing);
    expect(find.textContaining('could not be scanned'), findsNothing);
    expect(find.text('DUSKHOLLOW'), findsOneWidget);
  });

  testWidgets('a warning that is not about a photo does not accuse one',
      (tester) async {
    // Credentials present, so the resolve stage runs and fails per detection
    // (flutter_test answers every request with 400). Those warnings name a
    // title, and the photos they came off are in the document.
    await _pumpScan(
      tester,
      photos: ['shelf1.jpg', 'shelf2.jpg'],
      vision: PartlyFailingVision(),
      settings: ProviderSettings(
        backend: VisionBackend.local,
        igdbClientId: 'id',
        igdbClientSecret: 'secret',
      ),
    );
    await tester.pumpAndSettle();

    expect(_banner, findsNothing);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(_warning('Resolver failed'), findsOneWidget);
  });
}
