/// The status line as one line with one voice (T-0101).
///
/// Four things write it and each is pinned here in the same file, because
/// what is under test is not any one of them but the register they share: a
/// sentence saying why there is no review screen, written by whoever knows
/// the answer, with no category label in front of it. The defect that opened
/// this was `Failed: All 3 photo(s) failed`, where the screen's prefix and
/// the exception's own opening said the same word twice.
///
/// Behaviour is pinned elsewhere and deliberately not restated: which
/// failures offer the route into Settings is `scan_all_failed_test.dart`
/// (T-0096, T-0102), and when the blocker is allowed to appear at all is
/// `scan_backend_switch_test.dart` (T-0040, T-0076, T-0079).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelfscan_app/provider_config.dart';
import 'package:shelfscan_app/screens/scan_screen.dart';
import 'package:shelfscan_app/settings_store.dart';
import 'package:shelfscan_core/shelfscan_core.dart';

import 'scan_all_failed_test.dart' show ScriptedVision;
import 'scan_wiring_test.dart' show FakeInputPicker;
import 'settings_store_test.dart' show RecordingStore;

SettingsStore _store() =>
    SettingsStore(secrets: RecordingStore(), prefs: RecordingStore());

String _statusText(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('scan-status'))).data!;

/// The shape every one of the four has to keep. Two claims, both of which the
/// `Failed: ` prefix broke: a label is not a sentence, and a line that names
/// its category twice names it once too often.
void _readsAsOneSentence(String status) {
  expect(status, isNot(startsWith('Failed')));
  expect(status, isNot(startsWith('Error')));
  expect(status, isNot(contains('failed: All ')));
  expect(status, matches(RegExp(r'^[A-Z]')));
}

Future<void> _scan(WidgetTester tester) async {
  await tester.tap(find.text('Add photos'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Scan'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('1. a blocker: the condition, in the policy\'s own words',
      (tester) async {
    final settings = ProviderSettings(backend: VisionBackend.local);
    await tester.pumpWidget(MaterialApp(
      home: ScanScreen(
          settings: settings, store: _store(), picker: FakeInputPicker()),
    ));
    await tester.tap(find.byIcon(Icons.cloud));
    await tester.pump();

    final status = _statusText(tester);
    expect(status,
        'Cloud recognition needs an Anthropic API key -- add it in Settings.');
    _readsAsOneSentence(status);
  });

  testWidgets('2. the same blocker at the Scan button is the same string',
      (tester) async {
    final settings = ProviderSettings(backend: VisionBackend.cloud);
    await tester.pumpWidget(MaterialApp(
      home: ScanScreen(
          settings: settings, store: _store(), picker: FakeInputPicker()),
    ));
    await _scan(tester);

    // T-0040's property, read off the screen rather than off the policy: the
    // early answer and the late failure are one constant, so a fix to the
    // doubling that gave either of them its own wording would fail here.
    final status = _statusText(tester);
    expect(status, ProviderPolicy.check(settings).blocker);
    _readsAsOneSentence(status);
  });

  testWidgets('3. every photo failed: the exception\'s sentence, unprefixed',
      (tester) async {
    final failure = visionApiFailure(
      service: 'Anthropic',
      model: 'claude-not-a-model',
      statusCode: 404,
      body: '{"type":"error","error":{"type":"not_found_error"}}',
      retryable: false,
    );
    await tester.pumpWidget(MaterialApp(
      home: ScanScreen(
        settings: ProviderSettings(
          backend: VisionBackend.cloud,
          anthropicApiKey: 'sk-test',
          anthropicModel: 'claude-not-a-model',
        ),
        store: _store(),
        picker: FakeInputPicker(['shelf1.jpg', 'shelf2.jpg']),
        debugVisionProvider: ScriptedVision(
            {'shelf1.jpg': failure, 'shelf2.jpg': failure}),
      ),
    ));
    await _scan(tester);

    // Byte for byte what the CLI prints and what the orchestrator wrote: the
    // app quotes it whole and adds nothing to the front of it.
    final status = _statusText(tester);
    expect(status, startsWith('All 2 photo(s) failed: nothing was read, '));
    expect(status, contains('has no model "claude-not-a-model"'));
    expect(status, isNot(contains('Failed: All')));
    _readsAsOneSentence(status);
  });

  testWidgets('4. an error of no known shape: the screen supplies the sentence',
      (tester) async {
    // Mounted above the app's own Navigator, so opening the review screen
    // throws once the scan succeeds. That is a stand-in, and it is the only
    // one a widget test has left: since T-0072 every provider failure arrives
    // as ScanFailedException and T-0096 gave that its own branch, so nothing
    // a photo can do reaches this catch any more (the same fact T-0079
    // recorded before T-0072 made it briefly reachable).
    await tester.pumpWidget(MaterialApp(
      home: const SizedBox.shrink(),
      // An Overlay of its own, because the app bar's tooltips need one and the
      // Navigator that usually provides it is what this tree withholds.
      builder: (context, child) => Overlay(initialEntries: [
        OverlayEntry(
          builder: (_) => ScanScreen(
            settings: ProviderSettings(backend: VisionBackend.local),
            store: _store(),
            picker: FakeInputPicker(),
            debugVisionProvider: ScriptedVision(const {}),
          ),
        ),
      ]),
    ));
    await _scan(tester);

    final status = _statusText(tester);
    expect(status, startsWith('The scan could not finish: '));
    // No route: an unrecognised failure cannot be claimed to be a Settings
    // one, which is the T-0096 rule applied to the case it says nothing about.
    expect(find.byKey(const Key('status-open-settings')), findsNothing);
    _readsAsOneSentence(status);
  });
}
