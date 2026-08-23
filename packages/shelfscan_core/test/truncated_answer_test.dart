/// An answer that stopped at the output cap says so (T-0111).
///
/// Until this, all three providers handed the text straight to
/// `parsePhotoAnalysisText` and the photo died as `FormatException: Unexpected
/// end of input` -- a true sentence about the JSON and no sentence at all about
/// the token budget that cut it. T-0120 crossed it live, twice in one run, in
/// the shape these tests reproduce: `finish_reason: length`, 4096 completion
/// tokens, and `content` EMPTY, because the reasoning model spent the whole
/// budget before writing a character.
///
/// The other half of the job is the negative: a model that answers badly
/// without being truncated must still fail exactly as it does today, or this
/// becomes a message that blames the cap for everything.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

final _photo = PhotoInput(name: 'shelf.jpg', bytes: Uint8List.fromList([1, 2]));

/// What a cut-off answer actually looks like: valid text, invalid JSON.
const _halfJson = '{"items":[{"raw_title":"Vellum Compass","platform_hint":"SN';

const _wholeJson = '{"items":[{"raw_title":"Vex"}]}';

http.Response _openAi(String? content, {String? finish}) => http.Response(
    jsonEncode({
      'choices': [
        {
          'message': {'role': 'assistant', 'content': content},
          if (finish != null) 'finish_reason': finish,
        }
      ]
    }),
    200);

http.Response _anthropic(String? text, {String? stop}) => http.Response(
    jsonEncode({
      'content': [
        if (text != null) {'type': 'text', 'text': text}
      ],
      if (stop != null) 'stop_reason': stop,
    }),
    200);

http.Response _ollama(String content, {String? done}) => http.Response(
    jsonEncode({
      'message': {'content': content},
      if (done != null) 'done_reason': done,
    }),
    200);

/// The provider under a mock endpoint, plus the cap its request carried.
final _requestCaps = <String, int?>{};

Future<PhotoAnalysis> _analyzeOpenAi(http.Response answer,
    {List<http.Response> before = const []}) {
  final queued = [...before, answer];
  return OpenAiCompatibleVisionProvider(
    baseUrl: 'https://example.test/v1',
    model: 'gpt-5.5',
    apiKey: 'sk-secret-123',
    client: MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      _requestCaps['last'] =
          (body['max_tokens'] ?? body['max_completion_tokens']) as int?;
      return queued.removeAt(0);
    }),
  ).analyze(_photo);
}

Future<PhotoAnalysis> _analyzeAnthropic(http.Response answer) =>
    AnthropicVisionProvider(
      apiKey: 'k',
      client: MockClient((request) async {
        _requestCaps['last'] =
            (jsonDecode(request.body) as Map<String, dynamic>)['max_tokens']
                as int?;
        return answer;
      }),
    ).analyze(_photo);

Future<PhotoAnalysis> _analyzeOllama(http.Response answer) =>
    OllamaVisionProvider(client: MockClient((_) async => answer))
        .analyze(_photo);

/// The 400 that renames the cap, and the 400 that refuses the rename outright
/// -- the pair that leaves a run carrying no cap at all (T-0120, T-0139).
http.Response _refuses(String field, {String? instead}) => http.Response(
    jsonEncode({
      'error': {
        'message': "Unsupported parameter: '$field' is not supported with this "
            'model.${instead == null ? '' : " Use '$instead' instead."}',
        'param': field,
      }
    }),
    400);

Future<String> _messageOf(Future<PhotoAnalysis> analysis) async {
  try {
    await analysis;
  } on Object catch (e) {
    return e.toString();
  }
  fail('the truncated answer was accepted instead of reported');
}

void main() {
  group('a truncated answer names the cap', () {
    test('openai-compatible: half a JSON document', () async {
      final message =
          await _messageOf(_analyzeOpenAi(_openAi(_halfJson, finish: 'length')));

      // The number is read off the request rather than retyped, so the sentence
      // cannot outlive a change to the constant behind it.
      expect(message, contains('${_requestCaps['last']}-token output cap'));
      expect(message, contains('breaks off part-way'));
      expect(message, isNot(contains('FormatException')));
    });

    test('openai-compatible: the empty content T-0120 measured', () async {
      // Two of three photos of a live run arrived exactly like this: 200,
      // finish_reason length, completion_tokens 4096, content "".
      final message =
          await _messageOf(_analyzeOpenAi(_openAi('', finish: 'length')));

      expect(message, contains('${_requestCaps['last']}-token output cap'));
      expect(message, contains('wrote no answer at all'));
      expect(message, contains('thinking'));
    });

    test('openai-compatible: content missing altogether', () async {
      // A null here used to be a cast error rather than a FormatException, so
      // it is a third failure text for one cause.
      final message =
          await _messageOf(_analyzeOpenAi(_openAi(null, finish: 'length')));

      expect(message, contains('wrote no answer at all'));
      expect(message, isNot(contains('is not a subtype')));
    });

    test('anthropic: stop_reason max_tokens', () async {
      final message =
          await _messageOf(_analyzeAnthropic(_anthropic(_halfJson, stop:
              'max_tokens')));

      expect(message, contains('Anthropic'));
      expect(message, contains('${_requestCaps['last']}-token output cap'));
    });

    test('anthropic: truncated with no text block at all', () async {
      final message = await _messageOf(
          _analyzeAnthropic(_anthropic(null, stop: 'max_tokens')));

      expect(message, contains('wrote no answer at all'));
    });

    test('ollama: done_reason length names the cap the request sent', () async {
      final message =
          await _messageOf(_analyzeOllama(_ollama(_halfJson, done: 'length')));

      // Until T-0281 this request carried no cap and the sentence said so. It
      // carries one now, so the number is this build's and quoting it is the
      // same rule the cloud pair follows -- name what was sent, never invent a
      // ceiling.
      expect(message, contains('Ollama at http://localhost:11434'));
      expect(message, contains('8192-token output cap'));
      expect(message, isNot(contains("endpoint's own")));
      // A keyless server has no key to clear anyone of suspecting (T-0097).
      expect(message.toLowerCase(), isNot(contains('the key')));
    });
  });

  group('the message is one the user can act on', () {
    test('it offers the action they have, not the one they do not', () async {
      final message =
          await _messageOf(_analyzeOpenAi(_openAi(_halfJson, finish: 'length')));

      expect(message, contains('two or three sections'));
      // The app has no cap control and neither has the CLI, so the sentence
      // says so rather than sending them to look for one (T-0072).
      expect(message, contains('fixed in this build'));
      // The three things a user suspects first, all cleared in one clause.
      expect(message,
          contains('The key, the model id and the photo file are all fine'));
    });

    test('the raw answer stays out of the message and on the exception',
        () async {
      Object? thrown;
      try {
        await _analyzeOpenAi(_openAi(_halfJson, finish: 'length'));
      } on Object catch (e) {
        thrown = e;
      }

      expect(thrown, isA<VisionApiException>());
      final failure = thrown! as VisionApiException;
      expect(failure.message, isNot(contains('Vellum Compass')));
      expect(failure.body, contains('Vellum Compass'));
      // The call succeeded; only the answer did not fit. The app offers a
      // Settings route for 401/403/404 and this is none of them.
      expect(failure.statusCode, 200);
    });

    test('it is not retried: four attempts buy four capped completions',
        () async {
      expect(_analyzeOpenAi(_openAi(_halfJson, finish: 'length')),
          throwsA(isNot(isA<RetryableException>())));
    });

    test('an endpoint that refused every name for the cap quotes no number',
        () async {
      // The T-0120 state: the cap is renamed, the rename is refused, and the
      // run carries no cap. A message naming 8192 there would name a field the
      // request no longer has.
      final message = await _messageOf(
        _analyzeOpenAi(
          _openAi(_halfJson, finish: 'length'),
          before: [
            _refuses('max_tokens', instead: 'max_completion_tokens'),
            _refuses('max_completion_tokens'),
          ],
        ),
      );

      expect(_requestCaps['last'], isNull);
      expect(message, contains("endpoint's own"));
      expect(message, isNot(contains('token output cap')));
    });
  });

  group('a malformed answer that was not truncated fails as it always did', () {
    test('openai-compatible: finish_reason stop and prose', () async {
      expect(_analyzeOpenAi(_openAi('I count three games.', finish: 'stop')),
          throwsA(isA<FormatException>()));
    });

    test('openai-compatible: no finish_reason field at all', () async {
      // Endpoints in this family that omit it must not read as truncated.
      expect(_analyzeOpenAi(_openAi('I count three games.')),
          throwsA(isA<FormatException>()));
    });

    test('anthropic: stop_reason end_turn and prose', () async {
      expect(
          _analyzeAnthropic(
              _anthropic('I count three games.', stop: 'end_turn')),
          throwsA(isA<FormatException>()));
    });

    test('ollama: done_reason stop and prose', () async {
      expect(_analyzeOllama(_ollama('I count three games.', done: 'stop')),
          throwsA(isA<FormatException>()));
    });

    test('an ordinary answer is untouched by any of this', () async {
      final analysis = await _analyzeOpenAi(_openAi(_wholeJson, finish: 'stop'));

      expect(analysis.items.single.rawTitle, 'Vex');
    });

    test('a cut-off answer that still parses is reported, not accepted',
        () async {
      // The field is the authority, not the shape of the JSON: a document that
      // parses after the cap cut it is a shelf missing however many spines the
      // budget ran out on, and accepting it silently loses them (decision
      // 0012: a silent failure is worse than a loud one).
      expect(_analyzeOpenAi(_openAi(_wholeJson, finish: 'length')),
          throwsA(isA<VisionApiException>()));
    });

    test('anthropic: a cut-off answer that still parses is reported too',
        () async {
      // The same assertion on the provider T-0284 asked about, because its cap
      // is the lowest of the three and nobody has ever held a key for it: the
      // `stop_reason` branch has to run BEFORE the parse, or a document the cap
      // happened to cut on a closing brace arrives looking complete.
      expect(_analyzeAnthropic(_anthropic(_wholeJson, stop: 'max_tokens')),
          throwsA(isA<VisionApiException>()));
    });
  });
}
