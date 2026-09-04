/// The four 200-shape sentences and the route into the field they name
/// (T-0169).
///
/// T-0096 pinned the split for the statuses; four sentences then landed in one
/// day that a status cannot separate. Three of them end by telling the user the
/// model id is theirs to type *in the app's settings* and every one arrived
/// with no way to get there -- and T-0164's did not even arrive as a
/// `VisionApiException`, so the match did not see it at all.
///
/// What is pinned here is the same split as `scan_all_failed_test.dart`, one
/// layer down: the sentence is unchanged either way, and the route follows what
/// the sentence blames rather than what the transport answered. The fourth
/// sentence (T-0111) is the contrast and is deliberately in this file: it says
/// the key, the model id and the photo are all fine, so it must still offer
/// nothing -- on the two of its three roads that say that. The third (T-0464)
/// says the opposite under the same builder and the same status: no evidence
/// about the photograph, and a model id to change. It offers the route with
/// the rest (T-0465), which is what makes this file's split a property of the
/// sentence rather than of the builder.
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

/// The real builders, not hand-written copies of their sentences: what the
/// screen classifies has to be the object a provider actually throws.
Object _truncated() => visionTruncatedFailure(
      service: 'Anthropic',
      model: 'claude-not-a-model',
      cap: 4096,
      answer: '{"items":[{"raw_title":"Vex"',
      body: '{"stop_reason":"max_tokens"}',
    );

/// The same builder on its other two roads (T-0464), which the screen has to
/// tell apart because their sentences end in different places.
Object _truncatedSilent() => visionTruncatedFailure(
      service: 'Anthropic',
      model: 'claude-not-a-model',
      cap: 4096,
      answer: '',
      body: '{"stop_reason":"max_tokens"}',
    );

Object _truncatedLooping() => visionTruncatedFailure(
      service: 'Anthropic',
      model: 'claude-not-a-model',
      cap: 4096,
      answer: '{"items":[${List.filled(40, '{"raw_title":"Silt Harbour",'
          '"platform_hint":"SWITCH","confidence":0.9}').join(',')}',
      body: '{"stop_reason":"max_tokens"}',
    );

Object _emptyAnswer() => visionEmptyAnswerFailure(
      service: 'Anthropic',
      model: 'claude-not-a-model',
      reason: 'stop',
      body: '{"content":[]}',
    );

Object _notJson() => visionNotJsonFailure(
      service: 'Anthropic',
      model: 'claude-not-a-model',
      answer: 'Sure! Here are the games I can see on that shelf:',
    );

Object _wrongShape() => visionWrongShapeFailure(
      service: 'Anthropic',
      model: 'claude-not-a-model',
      problem: 'items[0] is a String; it must be an object with a "raw_title"',
      answer: '{"items":["Vex"]}',
    );

Future<void> _pumpScan(WidgetTester tester, Object failure) async {
  // Bigger than the 800x600 default, because these four sentences do not fit
  // it: the empty-answer one overflows the body Column by 44 px there and the
  // "Open settings" button, which sits under the text, is the half that goes
  // off the bottom. That is a real defect and it is **T-0177**, not this test's
  // subject -- what is measured here is which failures offer the route.
  tester.view.physicalSize = const Size(1000, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    home: ScanScreen(
      settings: ProviderSettings(
        backend: VisionBackend.cloud,
        anthropicApiKey: 'sk-test',
        anthropicModel: 'claude-not-a-model',
      ),
      store: SettingsStore(secrets: RecordingStore(), prefs: RecordingStore()),
      picker: FakeInputPicker(const ['shelf1.jpg']),
      debugVisionProvider: ScriptedVision({'shelf1.jpg': failure}),
    ),
  ));
  await tester.tap(find.text('Add photos'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Scan'));
  await tester.pumpAndSettle();
}

String _statusText(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('scan-status'))).data!;

final _route = find.byKey(const Key('status-open-settings'));

void main() {
  testWidgets('a 200 that carried no text offers the route (T-0142)',
      (tester) async {
    await _pumpScan(tester, _emptyAnswer());

    final status = _statusText(tester);
    expect(status, contains('with no text at all'));
    expect(status, contains('another model id or another backend'));
    expect(_route, findsOneWidget);
  });

  testWidgets('a 200 that was not JSON offers it too, and it is a '
      'FormatException (T-0164)', (tester) async {
    // The one the status match could never have seen: not a VisionApiException,
    // and before this task it fell to `_ => false` with the rest of the
    // unclassifiable world.
    expect(_notJson(), isA<FormatException>());

    await _pumpScan(tester, _notJson());

    final status = _statusText(tester);
    expect(status, contains('text that is not the JSON document'));
    expect(status, contains("the app's settings"));
    expect(_route, findsOneWidget);
  });

  testWidgets('a 200 whose JSON was the wrong document offers it (T-0167)',
      (tester) async {
    await _pumpScan(tester, _wrongShape());

    final status = _statusText(tester);
    expect(status, contains('JSON that is not the document'));
    expect(status, contains("the app's settings"));
    expect(_route, findsOneWidget);
  });

  testWidgets('a 200 whose answer ran out of room offers nothing (T-0111)',
      (tester) async {
    await _pumpScan(tester, _truncated());

    // The negative that keeps the rule honest, and it is the sentence's own
    // claim: it names the key, the model id and the photo file as fine and
    // offers a remedy Settings does not hold. Status 200 as the rule would have
    // offered the route here as well.
    final status = _statusText(tester);
    expect(status, contains('output cap'));
    expect(status, contains('The key, the model id and the photo file are all '
        'fine'));
    expect(status, contains('Photograph it in two or three sections'));
    expect(_route, findsNothing);
  });

  testWidgets('a 200 that wrote nothing at all offers the route (T-0465)',
      (tester) async {
    // One builder, one status, the opposite answer -- and the sentence is the
    // argument again: this road clears the photograph of carrying any
    // evidence and ends on the model id, which is a Settings field on both
    // surfaces. Offering nothing under it was the sentence and the button
    // disagreeing, which is the defect T-0169 exists to prevent.
    await _pumpScan(tester, _truncatedSilent());

    final status = _statusText(tester);
    expect(status, contains('wrote no answer at all'));
    expect(status, contains('Nothing here is evidence about the photograph'));
    expect(status, contains('Reach for a vision instruct model'));
    expect(_route, findsOneWidget);
  });

  testWidgets('a 200 that repeated itself to the cap offers nothing (T-0427)',
      (tester) async {
    // The third road, and the one the flag must NOT follow: the remedy here
    // is the framing, so the button would take back what the sentence said.
    await _pumpScan(tester, _truncatedLooping());

    final status = _statusText(tester);
    expect(status, contains('it enumerates them without end'));
    expect(status, contains('Re-frame the shot'));
    expect(_route, findsNothing);
  });

  testWidgets('the sentence is unchanged whichever way the route goes',
      (tester) async {
    // Added, never substituted (T-0096): the button is beside the report, not
    // instead of it. Checked on the pair that disagree about the button while
    // sharing a status.
    await _pumpScan(tester, _wrongShape());
    expect(_statusText(tester), contains(visionWrongShapeMessage(
      service: 'Anthropic',
      model: 'claude-not-a-model',
      problem: 'items[0] is a String; it must be an object with a "raw_title"',
      answer: '{"items":["Vex"]}',
    )));

    await _pumpScan(tester, _truncated());
    expect(_statusText(tester), contains(visionTruncatedMessage(
      service: 'Anthropic',
      model: 'claude-not-a-model',
      cap: 4096,
      wroteNothing: false,
    )));
  });
}
