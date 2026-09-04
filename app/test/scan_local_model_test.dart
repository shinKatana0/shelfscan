/// What the app does with the local server's answer about the model (T-0464).
///
/// The same policy the CLI runs, on the surface where the model id is a field
/// rather than an environment variable. Three things are pinned here and not
/// in core: that the refusal lands on the status line with the Settings route
/// under it, that the warning lands in the run's own warning list without
/// stopping anything, and that the question is asked once per run rather than
/// once per photograph.
///
/// Every model id below is invented except the one the recommendation names.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shelfscan_app/provider_config.dart';
import 'package:shelfscan_app/screens/scan_screen.dart';
import 'package:shelfscan_app/settings_store.dart';
import 'package:shelfscan_core/shelfscan_core.dart';

import 'scan_wiring_test.dart' show FakeInputPicker;
import 'settings_store_test.dart' show RecordingStore;

const _model = 'nimbus-vision:7b';

const _answer = '{"items":[{"raw_title":"Vellum Compass",'
    '"platform_hint":"PS4","media_type":"disc","confidence":0.9}],'
    '"unreadable":[]}';

OllamaModelReport _report(
        {OllamaCapability vision = OllamaCapability.present,
        OllamaCapability thinking = OllamaCapability.absent}) =>
    OllamaModelReport(vision: vision, thinking: thinking);

/// A real [OllamaVisionProvider] whose chat call is answered by [gate], so the
/// screen can be inspected while the run is still going.
OllamaVisionProvider _gatedProvider(Future<void> gate) => OllamaVisionProvider(
      model: _model,
      client: MockClient((_) async {
        await gate;
        return http.Response(
            jsonEncode({
              'message': {'content': _answer},
              'done_reason': 'stop',
            }),
            200,
            headers: {'content-type': 'application/json'});
      }),
    );

/// Pumps the scan screen on the local backend and presses Scan.
///
/// [asked] records every pre-flight, which is how "once per run" is counted
/// rather than read off the code. [vision] null leaves the screen to build its
/// own provider through [ProviderPolicy] -- which is what the refusal case
/// needs, because a refusal must happen before anything is asked of it.
Future<void> _pumpScan(
  WidgetTester tester, {
  required OllamaModelReport report,
  required List<String> asked,
  OllamaVisionProvider? vision,
  List<String> photos = const ['shelf1.jpg'],
}) async {
  await tester.pumpWidget(MaterialApp(
    home: ScanScreen(
      settings: ProviderSettings(
          backend: VisionBackend.local, ollamaModel: _model),
      store: SettingsStore(secrets: RecordingStore(), prefs: RecordingStore()),
      picker: FakeInputPicker(photos),
      debugVisionProvider: vision,
      debugModelReport: (provider) async {
        asked.add(provider.model);
        return report;
      },
    ),
  ));
  await tester.tap(find.text('Add photos'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Scan'));
}

String _status(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('scan-status'))).data!;

void main() {
  testWidgets('a model with no vision stops the run on the status line',
      (tester) async {
    final asked = <String>[];
    await _pumpScan(tester,
        report: _report(vision: OllamaCapability.absent), asked: asked);
    await tester.pumpAndSettle();

    expect(asked, [_model]);
    expect(_status(tester), contains('has no vision capability'));
    expect(_status(tester), contains('needs an image-capable model'));
    // The sentence ends on the model id, which is a field one screen over, so
    // the route is offered with it (T-0169's rule).
    expect(find.byKey(const Key('status-open-settings')), findsOneWidget);
    // Nothing was read, so no review opened over the top of the sentence.
    expect(find.text('Scan'), findsOneWidget);
  });

  testWidgets('a model that reasons first is named, and the run goes on',
      (tester) async {
    final gate = Completer<void>();
    final asked = <String>[];
    await _pumpScan(
      tester,
      report: _report(thinking: OllamaCapability.present),
      asked: asked,
      vision: _gatedProvider(gate.future),
    );

    // Before the first photograph finishes: the warning is about the model,
    // and waiting for a result to state it would be stating it too late.
    await tester.pump();
    await tester.pump();
    expect(asked, [_model]);
    final warning = find.descendant(
      of: find.byKey(const Key('scan-warnings')),
      matching: find.textContaining('reasons before it answers'),
    );
    expect(warning, findsOneWidget);
    // Warned, not blocked.
    expect(find.byKey(const Key('scan-status')), findsNothing);

    gate.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('a model with vision and no thinking says nothing at all',
      (tester) async {
    final gate = Completer<void>();
    await _pumpScan(
      tester,
      report: _report(),
      asked: [],
      vision: _gatedProvider(gate.future),
    );

    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('scan-warnings')), findsNothing);
    expect(find.byKey(const Key('scan-status')), findsNothing);

    gate.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('a server that said nothing usable blocks and warns nothing',
      (tester) async {
    final gate = Completer<void>();
    await _pumpScan(
      tester,
      report: const OllamaModelReport.unanswered(),
      asked: [],
      vision: _gatedProvider(gate.future),
    );

    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('scan-warnings')), findsNothing);
    expect(find.byKey(const Key('scan-status')), findsNothing);

    gate.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('three photographs ask the question once', (tester) async {
    final gate = Completer<void>();
    final asked = <String>[];
    await _pumpScan(
      tester,
      report: _report(),
      asked: asked,
      vision: _gatedProvider(gate.future),
      photos: const ['shelf1.jpg', 'shelf2.jpg', 'shelf3.jpg'],
    );

    await tester.pump();
    await tester.pump();
    expect(asked, hasLength(1));

    gate.complete();
    await tester.pumpAndSettle();
  });
}
