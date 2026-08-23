/// A 200 that carries no answer text, for a reason that is not the output cap
/// (T-0142).
///
/// T-0111 made `finish_reason: length` a sentence and left the neighbour alone.
/// The neighbour is the endpoint that answers HTTP 200 and says nothing for
/// some other reason: `content` is documented null in the OpenAI shape for a
/// refusal, for a tool-only answer and for `finish_reason: content_filter`, and
/// the `as String` cast turned every one of those into `type 'Null' is not a
/// subtype of type 'String'` -- the T-0072 class, naming a Dart type instead of
/// anything about the run. Anthropic joined a text-less content list to '' and
/// died one step later as `FormatException: Unexpected end of input`.
///
/// **None of these shapes has been seen here.** Every response below is built
/// from the vendors' documented response shapes, not recorded off a run, which
/// is a weaker footing than T-0111 had for the cap.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

final _photo = PhotoInput(name: 'shelf.jpg', bytes: Uint8List.fromList([1, 2]));

http.Response _openAi(
  String? content, {
  String? finish,
  String? refusal,
  bool withChoice = true,
}) =>
    http.Response(
        jsonEncode({
          'choices': [
            if (withChoice)
              {
                'message': {
                  'role': 'assistant',
                  'content': content,
                  if (refusal != null) 'refusal': refusal,
                },
                if (finish != null) 'finish_reason': finish,
              }
          ]
        }),
        200);

/// [blocks] is the whole `content` array, so a tool-only answer and an empty
/// one are both expressible.
http.Response _anthropic(List<Map<String, Object?>> blocks, {String? stop}) =>
    http.Response(
        jsonEncode({
          'content': blocks,
          if (stop != null) 'stop_reason': stop,
        }),
        200);

http.Response _ollama(String? content, {String? done}) => http.Response(
    jsonEncode({
      'message': {'content': content},
      if (done != null) 'done_reason': done,
    }),
    200);

Future<PhotoAnalysis> _analyzeOpenAi(http.Response answer) =>
    OpenAiCompatibleVisionProvider(
      baseUrl: 'https://example.test/v1',
      model: 'gpt-5.5',
      apiKey: 'sk-secret-123',
      client: MockClient((_) async => answer),
    ).analyze(_photo);

Future<PhotoAnalysis> _analyzeAnthropic(http.Response answer) =>
    AnthropicVisionProvider(
      apiKey: 'k',
      client: MockClient((_) async => answer),
    ).analyze(_photo);

Future<PhotoAnalysis> _analyzeOllama(http.Response answer) =>
    OllamaVisionProvider(client: MockClient((_) async => answer))
        .analyze(_photo);

Future<String> _messageOf(Future<PhotoAnalysis> analysis) async {
  try {
    await analysis;
  } on Object catch (e) {
    return e.toString();
  }
  fail('the empty answer was accepted instead of reported');
}

void main() {
  group('an image the endpoint refused gets its own sentence', () {
    test('openai-compatible: finish_reason content_filter', () async {
      final message = await _messageOf(
          _analyzeOpenAi(_openAi(null, finish: 'content_filter')));

      expect(message, contains('declined this photograph'));
      expect(message, contains('content_filter'));
      // A cast error named a Dart type; this must name the run.
      expect(message, isNot(contains('is not a subtype')));
      expect(message, isNot(contains('FormatException')));
    });

    test('it offers the readers that exist and no control that does not',
        () async {
      final message = await _messageOf(
          _analyzeOpenAi(_openAi(null, finish: 'content_filter')));

      // Both are real on both surfaces: the model id is user-typed (T-0067) and
      // the backend is the app's switch / the CLI's --provider.
      expect(message, contains('model id'));
      expect(message, contains('backend'));
      // Android has no local backend at all, so the local route is qualified
      // rather than promised (ProviderPolicy.available).
      expect(message, contains('where this machine can run Ollama'));
      // There is no setting that relaxes the endpoint's filter, and saying
      // there is would be T-0072 in a new costume.
      expect(message, contains('nothing in this app or the CLI can relax'));
    });

    test("it does not borrow the cap's advice", () async {
      final message = await _messageOf(
          _analyzeOpenAi(_openAi(null, finish: 'content_filter')));

      // A refused photograph is not made acceptable by being cut in half.
      expect(message, isNot(contains('two or three sections')));
      expect(message, isNot(contains('output cap')));
    });

    test('anthropic: stop_reason refusal', () async {
      final message =
          await _messageOf(_analyzeAnthropic(_anthropic([], stop: 'refusal')));

      expect(message, startsWith('Anthropic declined this photograph'));
      expect(message, contains('refusal'));
    });

    test("the model's own words are quoted when there are any", () async {
      // `message.refusal` is the only one of these fields that carries an
      // explanation; the other two vendors' shapes carry none.
      final message = await _messageOf(_analyzeOpenAi(_openAi(null,
          finish: 'content_filter', refusal: 'I cannot identify people.')));

      expect(message, contains('It said: I cannot identify people.'));
    });
  });

  group('an unrecognised reason is named, not absorbed', () {
    test('openai-compatible: a reason nobody here has seen', () async {
      final message = await _messageOf(
          _analyzeOpenAi(_openAi(null, finish: 'model_thinking_only')));

      expect(message, contains('"model_thinking_only"'));
      expect(message, contains('quoted as the endpoint gave it'));
    });

    test('openai-compatible: tool calls and no text', () async {
      final message =
          await _messageOf(_analyzeOpenAi(_openAi(null, finish: 'tool_calls')));

      expect(message, contains('"tool_calls"'));
    });

    test('anthropic: a content list holding no text block', () async {
      final message = await _messageOf(_analyzeAnthropic(
          _anthropic([
            {'type': 'tool_use', 'id': 't1', 'name': 'x', 'input': {}}
          ], stop: 'tool_use')));

      expect(message, contains('"tool_use"'));
      expect(message, isNot(contains('FormatException')));
    });

    test('ollama: the same hole, and no key to clear anyone of', () async {
      // `load` and `unload` are documented done_reasons that come with no
      // content; unmeasured here, like everything else in this file.
      final message = await _messageOf(_analyzeOllama(_ollama('', done:
          'load')));

      expect(message, contains('Ollama at http://localhost:11434'));
      expect(message, contains('"load"'));
      // A keyless server has no key to clear anyone of suspecting (T-0097).
      expect(message.toLowerCase(), isNot(contains('key')));
    });
  });

  group('no reason at all is still a sentence', () {
    test('openai-compatible: null content, no finish_reason', () async {
      final message = await _messageOf(_analyzeOpenAi(_openAi(null)));

      expect(message, contains('named no reason'));
      expect(message, isNot(contains('is not a subtype')));
    });

    test('openai-compatible: an empty string is as empty as a null', () async {
      final message =
          await _messageOf(_analyzeOpenAi(_openAi('   ', finish: 'stop')));

      expect(message, contains('no text at all'));
      expect(message, isNot(contains('FormatException')));
    });

    test('openai-compatible: a choices array with nothing in it', () async {
      final message =
          await _messageOf(_analyzeOpenAi(_openAi(null, withChoice: false)));

      // Used to be a bare StateError from `.first`.
      expect(message, contains('no text at all'));
      expect(message, isNot(contains('No element')));
    });

    test('anthropic: an empty content array and no stop_reason', () async {
      final message = await _messageOf(_analyzeAnthropic(_anthropic([])));

      expect(message, contains('named no reason'));
    });

    test('ollama: content missing altogether', () async {
      final message = await _messageOf(_analyzeOllama(_ollama(null)));

      expect(message, isNot(contains('is not a subtype')));
      expect(message, contains('no text at all'));
    });
  });

  group('the exception is the one the rest of the app already handles', () {
    test('a 200, with the raw answer on it and out of the message', () async {
      Object? thrown;
      try {
        await _analyzeOpenAi(_openAi(null,
            finish: 'content_filter', refusal: 'refused'));
      } on Object catch (e) {
        thrown = e;
      }

      expect(thrown, isA<VisionApiException>());
      final failure = thrown! as VisionApiException;
      // The call really did succeed; the app offers a Settings route for
      // 401/403/404 and this is none of them (T-0111).
      expect(failure.statusCode, 200);
      expect(failure.body, contains('content_filter'));
    });

    test('it is not retried: the endpoint said no, not "not now"', () async {
      expect(_analyzeOpenAi(_openAi(null, finish: 'content_filter')),
          throwsA(isNot(isA<RetryableException>())));
    });
  });

  group("T-0111's sentence still wins where it applies", () {
    test('finish_reason length with no content is still the cap', () async {
      final message =
          await _messageOf(_analyzeOpenAi(_openAi(null, finish: 'length')));

      expect(message, contains('output cap'));
      expect(message, contains('wrote no answer at all'));
      expect(message, isNot(contains('named "length"')));
    });

    test('anthropic: max_tokens with no text block is still the cap', () async {
      final message =
          await _messageOf(_analyzeAnthropic(_anthropic([], stop: 'max_tokens')));

      expect(message, contains('output cap'));
    });

    test('ollama: done_reason length with empty content is still the cap',
        () async {
      final message = await _messageOf(_analyzeOllama(_ollama('', done:
          'length')));

      expect(message, contains('8192-token output cap'));
      expect(message, contains('wrote no answer at all'));
    });
  });

  test('an answer with text in it is untouched by any of this', () async {
    final analysis =
        await _analyzeOpenAi(_openAi('{"items":[{"raw_title":"Vex"}]}',
            finish: 'stop'));

    expect(analysis.items.single.rawTitle, 'Vex');
  });
}
