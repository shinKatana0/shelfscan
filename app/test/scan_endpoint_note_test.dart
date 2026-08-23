/// What the app does when the endpoint refuses a parameter (T-0110).
///
/// The bug this pins: the scan screen built the OpenAI-compatible provider
/// without `onRequestAdjusted`, so on a model that refuses `temperature` --
/// measured live 2026-08-15 on `gpt-5`, `gpt-5-mini`, `gpt-5.5` and the three
/// `gpt-5.6` models -- the app dropped temperature 0 and scanned on at the
/// endpoint's own sampling with nothing on screen. The CLI printed a `WARN`
/// line for the same correction.
///
/// The 400 bodies below are the ones `openai_request_shape_test.dart` measured
/// verbatim against api.openai.com on 2026-08-15.
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

http.Response _completion() => http.Response(
    jsonEncode({
      'choices': [
        {
          'message': {
            'role': 'assistant',
            'content': '{"items":[{"raw_title":"Vex"}]}',
          }
        }
      ]
    }),
    200,
    headers: {'content-type': 'application/json'});

http.Response _renameMaxTokens() => http.Response(
    jsonEncode({
      'error': {
        'message': "Unsupported parameter: 'max_tokens' is not supported with "
            "this model. Use 'max_completion_tokens' instead.",
        'type': 'invalid_request_error',
        'param': 'max_tokens',
        'code': 'unsupported_parameter',
      }
    }),
    400);

http.Response _refuseTemperature() => http.Response(
    jsonEncode({
      'error': {
        'message': "Unsupported value: 'temperature' does not support 0.0 "
            'with this model. Only the default (1) value is supported.',
        'type': 'invalid_request_error',
        'param': 'temperature',
        'code': 'unsupported_value',
      }
    }),
    400);

ProviderSettings _endpointSettings() => ProviderSettings(
      backend: VisionBackend.openAiCompatible,
      openAiBaseUrl: 'https://endpoint.test/v1',
      openAiModel: 'gpt-5.5',
      openAiApiKey: 'key',
    );

/// Runs the real [OpenAiCompatibleVisionProvider] against [answer], built
/// through the screen's own note channel. [heard] collects what the provider
/// said, so an assertion can compare the screen against the provider's exact
/// words rather than against a copy written here.
Future<void> _pumpScan(
  WidgetTester tester, {
  required Future<http.Response> Function(Map<String, Object?> sent) answer,
  required List<String> heard,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: ScanScreen(
      picker: FakeInputPicker(['shelf1.jpg']),
      settings: _endpointSettings(),
      store: SettingsStore(secrets: RecordingStore(), prefs: RecordingStore()),
      debugVisionProviderBuilder: (onNote) => OpenAiCompatibleVisionProvider(
        baseUrl: 'https://endpoint.test/v1',
        model: 'gpt-5.5',
        apiKey: 'key',
        client: MockClient((request) async =>
            answer(jsonDecode(request.body) as Map<String, Object?>)),
        onRequestAdjusted: (note) {
          heard.add(note);
          onNote(note);
        },
      ),
    ),
  ));
  await tester.tap(find.text('Add photos'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Scan'));
}

Finder _note(String text) => find.descendant(
      of: find.byKey(const Key('scan-warnings')),
      matching: find.text(text),
    );

void main() {
  testWidgets('a refused temperature is on screen while the run continues',
      (tester) async {
    final gate = Completer<void>();
    final heard = <String>[];
    await _pumpScan(
      tester,
      heard: heard,
      answer: (sent) async {
        if (sent.containsKey('temperature')) return _refuseTemperature();
        await gate.future;
        return _completion();
      },
    );

    // The correction happens on the first call, so the note is due before any
    // photo has finished -- which is the only moment at which it can still
    // stop a run whose numbers would otherwise be unattributable.
    await tester.pump();
    await tester.pump();
    expect(heard, hasLength(1));
    // The provider's sentence, whole: a test that matched a substring or a
    // paraphrase would pass while the app dropped the consequence half of it
    // (T-0139), which is the half naming the sampling this run really used.
    expect(_note(heard.single), findsOneWidget);
    expect(heard.single, contains("will not take \"temperature\""));

    gate.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('both corrections of one run are heard', (tester) async {
    // T-0120 measured gpt-5.5 doing exactly this: the cap is renamed on the
    // first call, temperature refused on the retry.
    final gate = Completer<void>();
    final heard = <String>[];
    await _pumpScan(
      tester,
      heard: heard,
      answer: (sent) async {
        if (sent.containsKey('max_tokens')) return _renameMaxTokens();
        if (sent.containsKey('temperature')) return _refuseTemperature();
        await gate.future;
        return _completion();
      },
    );

    await tester.pump();
    await tester.pump();
    expect(heard, hasLength(2));
    // Newest first, and the panel is capped at 120 px (T-0041) -- two notes of
    // this length do not fit, so the first correction is reached by scrolling
    // the same way a run's other warnings are.
    expect(_note(heard.last), findsOneWidget);
    await tester.drag(
        find.byKey(const Key('scan-warnings')), const Offset(0, -300));
    await tester.pump();
    expect(_note(heard.first), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('an endpoint that refuses nothing produces no note',
      (tester) async {
    final heard = <String>[];
    var calls = 0;
    await _pumpScan(
      tester,
      heard: heard,
      answer: (sent) async {
        calls += 1;
        return _completion();
      },
    );
    await tester.pumpAndSettle();

    expect(calls, 1);
    expect(heard, isEmpty);
    expect(find.byKey(const Key('scan-warnings')), findsNothing);
  });

  test('the endpoint provider is built with the caller\'s note sink', () {
    void sink(String note) {}
    final wired = ProviderPolicy.build(_endpointSettings(),
        onRequestAdjusted: sink) as OpenAiCompatibleVisionProvider;
    expect(wired.onRequestAdjusted, same(sink));

    final unwired =
        ProviderPolicy.build(_endpointSettings()) as OpenAiCompatibleVisionProvider;
    expect(unwired.onRequestAdjusted, isNull);
  });
}
