/// What the app offers when EVERY photo of a run failed (T-0096).
///
/// T-0072 made that run throw `ScanFailedException` instead of opening an
/// empty review screen, which put a real sentence on the status line -- and
/// the sentence is about the model id and the key, both of which are Settings
/// fields, while the shortcut into Settings was set only by the missing-key
/// `StateError`. What is pinned here is the split: the route is offered for
/// the failures Settings holds a field for and withheld for the ones it does
/// not, and the sentence itself is unchanged either way.
///
/// The split has two axes since T-0102, and both are pinned: a call that
/// reached an HTTP status is judged by the status, one that reached none is
/// judged by whether the address it could not reach is a Settings field.
///
/// The partial case is the contrast, and it is deliberately in this file too:
/// one photo of three failing on the SAME fixable cause must still warn and
/// still open review (T-0030), because the run produced a result.
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shelfscan_app/provider_config.dart';
import 'package:shelfscan_app/screens/scan_screen.dart';
import 'package:shelfscan_app/settings_store.dart';
import 'package:shelfscan_core/shelfscan_core.dart';

import 'scan_wiring_test.dart' show FakeFilePicker;
import 'settings_store_test.dart' show RecordingStore;

/// Throws the error scripted for a photo's name, reads every other photo.
class ScriptedVision implements VisionProvider {
  ScriptedVision(this.errors);

  final Map<String, Object> errors;

  @override
  Future<PhotoAnalysis> analyze(PhotoInput photo) async {
    if (errors[photo.name] case final error?) throw error;
    return PhotoAnalysis(
      items: [
        Detection(
          // One title per photo, not one shared one: dedupe merges equal
          // titles across photos, which would hide how many photos were read.
          rawTitle: 'READ ${photo.name}',
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

/// The real explanation path (T-0072), not a hand-written string: what the
/// screen classifies is the exception a provider actually throws.
Exception _apiFailure(int status, {required bool retryable}) =>
    visionApiFailure(
      service: 'Anthropic',
      model: 'claude-not-a-model',
      statusCode: status,
      body: '{"type":"error","error":{"type":"not_found_error"}}',
      retryable: retryable,
    );

/// A local server that is not running: the exception the provider throws
/// (T-0097), not a hand-written copy of its sentence.
Exception _ollamaUnreachable() => OllamaUnreachableException(
    'http://localhost:11434', 'Connection refused');

/// A cloud endpoint that never answered (T-0103). [endpointIsUserSet] is the
/// whole of the difference between the two cloud providers, so both are built
/// from one helper rather than two: the OpenAI-compatible base URL is typed
/// into Settings, Anthropic's endpoint is fixed in this repository.
Exception _cloudUnreachable({required bool endpointIsUserSet}) =>
    VisionUnreachableException(
      http.ClientException('Connection refused'),
      service: endpointIsUserSet ? 'the endpoint' : 'Anthropic',
      endpoint: endpointIsUserSet
          ? 'https://api.groq.test/openai/v1'
          : 'https://api.anthropic.com/v1/messages',
      endpointIsUserSet: endpointIsUserSet,
    );

/// An exception of no known shape -- what the screen does with a failure it
/// cannot classify, which the untyped `Exception` fixture used to stand for
/// until T-0097 and T-0103 gave the two unreachable cases a type each.
Exception _unclassifiable() => Exception('something else entirely');

Future<void> _pumpScan(
  WidgetTester tester, {
  required List<String> photos,
  required Map<String, Object> failWith,
}) async {
  FilePicker.platform = FakeFilePicker(photos);
  await tester.pumpWidget(MaterialApp(
    home: ScanScreen(
      // Cloud with a key: the configuration a 404 on a model id comes from,
      // and it puts the privacy warning directly above the status line, which
      // is where the shortcut has to remain findable.
      settings: ProviderSettings(
        backend: VisionBackend.cloud,
        anthropicApiKey: 'sk-test',
        anthropicModel: 'claude-not-a-model',
      ),
      store: SettingsStore(secrets: RecordingStore(), prefs: RecordingStore()),
      debugVisionProvider: ScriptedVision(failWith),
    ),
  ));
  await tester.tap(find.text('Add photos'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Scan'));
}

String _statusText(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('scan-status'))).data!;

final _route = find.byKey(const Key('status-open-settings'));

void main() {
  testWidgets('every photo failed on a model id: the sentence AND the route',
      (tester) async {
    await _pumpScan(
      tester,
      photos: ['shelf1.jpg', 'shelf2.jpg'],
      failWith: {
        'shelf1.jpg': _apiFailure(404, retryable: false),
        'shelf2.jpg': _apiFailure(404, retryable: false),
      },
    );
    await tester.pumpAndSettle();

    // Added, not substituted: the report of what happened is still the whole
    // status line, and it is the orchestrator's own sentence.
    final status = _statusText(tester);
    expect(status, contains('All 2 photo(s) failed'));
    expect(status, contains('nothing was read'));
    expect(status, contains('has no model "claude-not-a-model"'));
    expect(status, contains('HTTP 404'));
    expect(_route, findsOneWidget);

    // No review screen was opened over it -- this line is the whole report.
    expect(find.text('shelfscan'), findsOneWidget);
    expect(find.textContaining('READ '), findsNothing);
  });

  testWidgets('a rejected key offers the route as well', (tester) async {
    await _pumpScan(
      tester,
      photos: ['shelf1.jpg'],
      failWith: {'shelf1.jpg': _apiFailure(401, retryable: false)},
    );
    await tester.pumpAndSettle();

    expect(_statusText(tester), contains('rejected the API key'));
    expect(_route, findsOneWidget);
  });

  testWidgets('a request the endpoint refused offers nothing', (tester) async {
    await _pumpScan(
      tester,
      photos: ['shelf1.jpg'],
      failWith: {'shelf1.jpg': _apiFailure(400, retryable: false)},
    );
    await tester.pumpAndSettle();

    // The 400 sentence names "a parameter or the model id", and a parameter is
    // not a Settings field: this is how an endpoint refuses a photo, and it is
    // unmeasured which endpoint families answer it for a bad model id.
    expect(_statusText(tester), contains('as invalid (HTTP 400)'));
    expect(_route, findsNothing);
  });

  testWidgets('a local server that is not running says so and offers the URL',
      (tester) async {
    await _pumpScan(
      tester,
      photos: ['shelf1.jpg', 'shelf2.jpg'],
      failWith: {
        'shelf1.jpg': _ollamaUnreachable(),
        'shelf2.jpg': _ollamaUnreachable(),
      },
    );
    await tester.pumpAndSettle();

    final status = _statusText(tester);
    expect(status, contains('All 2 photo(s) failed'));
    expect(status, contains('Cannot reach Ollama'));
    // The likelier remedy still leads, and the button does not displace it:
    // the Ollama URL is a Settings field and a wrong one fails identically.
    expect(status, contains('ollama serve'));
    expect(_route, findsOneWidget);
  });

  testWidgets('a cloud base URL that never answered offers the route too',
      (tester) async {
    await _pumpScan(
      tester,
      photos: ['shelf1.jpg'],
      failWith: {'shelf1.jpg': _cloudUnreachable(endpointIsUserSet: true)},
    );
    await tester.pumpAndSettle();

    expect(_statusText(tester), contains('Check that base URL first'));
    expect(_route, findsOneWidget);
  });

  testWidgets('a cloud endpoint this app fixes offers nothing', (tester) async {
    await _pumpScan(
      tester,
      photos: ['shelf1.jpg'],
      failWith: {'shelf1.jpg': _cloudUnreachable(endpointIsUserSet: false)},
    );
    await tester.pumpAndSettle();

    // Same class, same rule, opposite answer: the sentence itself says there
    // is nothing to correct in Settings, so a button under it would contradict
    // the line above it.
    expect(_statusText(tester),
        contains('nothing to correct in your settings'));
    expect(_route, findsNothing);
  });

  testWidgets('a failure of no known shape offers nothing', (tester) async {
    await _pumpScan(
      tester,
      photos: ['shelf1.jpg'],
      failWith: {'shelf1.jpg': _unclassifiable()},
    );
    await tester.pumpAndSettle();

    expect(_statusText(tester), contains('something else entirely'));
    expect(_route, findsNothing);
  });

  testWidgets('a rate limit the retries did not clear offers nothing',
      (tester) async {
    await _pumpScan(
      tester,
      photos: ['shelf1.jpg'],
      failWith: {'shelf1.jpg': _apiFailure(429, retryable: true)},
    );
    // The worker's three backoffs (2 s + 4 s + 8 s) schedule no frame, so
    // pumpAndSettle alone would return while the run is still asleep.
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();

    expect(_statusText(tester), contains('rate-limiting'));
    // The sentence says the run is fine and to try later; Settings holds
    // nothing that changes it, and RetryableVisionApiException carries no
    // status for the screen to misread as one it could.
    expect(_route, findsNothing);
  });

  testWidgets('one fixable cause among several still offers the route',
      (tester) async {
    await _pumpScan(
      tester,
      photos: ['shelf1.jpg', 'shelf2.jpg'],
      failWith: {
        'shelf1.jpg': _apiFailure(404, retryable: false),
        // Was the unreachable fixture until T-0102 made that case fixable; the
        // property under test is `any` over a MIXED set, so the unfixable half
        // has to stay unfixable.
        'shelf2.jpg': _unclassifiable(),
      },
    );
    await tester.pumpAndSettle();

    expect(_statusText(tester), contains('Each photo failed differently'));
    expect(_route, findsOneWidget);
  });

  testWidgets('one photo of three on the same fixable cause: T-0030 stands',
      (tester) async {
    await _pumpScan(
      tester,
      photos: ['shelf1.jpg', 'shelf2.jpg', 'shelf3.jpg'],
      failWith: {'shelf1.jpg': _apiFailure(404, retryable: false)},
    );
    await tester.pumpAndSettle();

    // A partial result is a result: review opens, the lost photo is named
    // there, and nothing on the way calls the run a failure or sends the user
    // to Settings for a scan that mostly worked.
    expect(find.byKey(const Key('failed-photos-banner')), findsOneWidget);
    expect(find.text('READ shelf2.jpg'), findsOneWidget);
    // Scrolled to since T-0230: this run has no IGDB stage, so the review
    // screen leads with the keyless banner, and at 800x600 the third group
    // was the last thing that fit. The property is that the row is there,
    // not that three groups fit one viewport.
    await tester.scrollUntilVisible(find.text('READ shelf3.jpg'), 100);
    expect(find.text('READ shelf3.jpg'), findsOneWidget);
    expect(_route, findsNothing);
    expect(find.byKey(const Key('scan-status')), findsNothing);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const Key('scan-warnings')),
        matching: find.textContaining('shelf1.jpg'),
      ),
      findsOneWidget,
    );
    expect(_route, findsNothing);
    expect(find.byKey(const Key('scan-status')), findsNothing);
  });
}
