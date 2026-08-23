/// A 200 whose text is not a JSON document at all (T-0164).
///
/// The last of the four shapes a 200 arrives in: T-0111 the output cap, T-0142
/// no text, T-0083 a leading reasoning element, and here text that reached the
/// decoder and is simply not a document -- prose, an apology, or a reasoning
/// marker T-0083's rule deliberately does not reach.
///
/// **Nothing here is measured.** No endpoint has produced one of these;
/// every response below is a `MockClient` literal reproducing a shape,
/// and no call leaves the machine.
///
/// The type is unchanged on purpose. `vision_parsing_test.dart` pins a
/// `FormatException` for this answer (T-0013) and four boundary tests in
/// `reasoning_preamble_test.dart` pin it again (T-0083); both files are
/// unedited, and what changed is the sentence inside it.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

final _photo = PhotoInput(name: 'shelf.jpg', bytes: Uint8List.fromList([1, 2]));

const _openAiUrl = 'https://api.groq.test/openai/v1';
const _openAiModel = 'qwen/qwen3.6-27b';
const _ollamaUrl = 'http://localhost:11434';
const _ollamaModel = 'qwen2.5vl:7b';
const _anthropicModel = 'claude-sonnet-4-6';

/// Without the charset an `http.Response` encodes its body latin1, and two of
/// the markers below are not latin1 (T-0083).
http.Response _json(Map<String, Object?> body) => http.Response(
    jsonEncode(body), 200,
    headers: {'content-type': 'application/json; charset=utf-8'});

Future<PhotoAnalysis> _openAi(String content, {String? finish}) =>
    OpenAiCompatibleVisionProvider(
      baseUrl: _openAiUrl,
      model: _openAiModel,
      apiKey: 'k',
      client: MockClient((_) async => _json({
            'choices': [
              {
                'message': {'role': 'assistant', 'content': content},
                if (finish != null) 'finish_reason': finish,
              }
            ]
          })),
    ).analyze(_photo);

Future<PhotoAnalysis> _ollama(String content, {String? done}) =>
    OllamaVisionProvider(
      baseUrl: _ollamaUrl,
      model: _ollamaModel,
      client: MockClient((_) async => _json({
            'message': {'content': content},
            if (done != null) 'done_reason': done,
          })),
    ).analyze(_photo);

Future<PhotoAnalysis> _anthropic(String text, {String? stop}) =>
    AnthropicVisionProvider(
      apiKey: 'k',
      client: MockClient((_) async => _json({
            'content': [
              {'type': 'text', 'text': text}
            ],
            if (stop != null) 'stop_reason': stop,
          })),
    ).analyze(_photo);

Future<String> _messageOf(Future<PhotoAnalysis> analysis) async {
  try {
    await analysis;
  } on Object catch (e) {
    return e.toString();
  }
  fail('the answer was accepted instead of reported');
}

/// The shapes the task was filed for. The first is the one the backlog entry
/// and `vision_parsing_test.dart` both quote.
const _prose = 'I count three games on this shelf.';
const _apology =
    "I'm sorry, I can't identify the games in this image with confidence.";
const _kimi = '◁think▷reading the spines◁/think▷ three games';
const _harmony = '<|channel|>analysis<|message|>the shelf holds a lot of';

const _answer = '{"items":[{"raw_title":"Vellum Compass"}]}';

void main() {
  final providers = <String, ({
    Future<PhotoAnalysis> Function(String) analyze,
    String service,
    String model,
    bool hasKey,
  })>{
    'openai-compatible': (
      analyze: _openAi,
      service: _openAiUrl,
      model: _openAiModel,
      hasKey: true,
    ),
    'anthropic': (
      analyze: _anthropic,
      service: 'Anthropic',
      model: _anthropicModel,
      hasKey: true,
    ),
    'ollama': (
      analyze: _ollama,
      service: 'Ollama at $_ollamaUrl',
      model: _ollamaModel,
      hasKey: false,
    ),
  };

  providers.forEach((name, p) {
    group('$name provider', () {
      test('prose names the model and the endpoint, not the JSON', () async {
        final message = await _messageOf(p.analyze(_prose));

        expect(message, contains(p.service));
        expect(message, contains('"${p.model}"'));
        // The whole point of the task: what the old sentence said, and nothing
        // else, was the decoder's complaint about character 1.
        expect(message, isNot(contains('Unexpected character')));
        expect(message, isNot(contains('at character')));
      });

      test('it quotes what the model actually said', () async {
        expect(await _messageOf(p.analyze(_prose)), contains('It said: $_prose'));
      });

      test('an apology is the same shape', () async {
        final message = await _messageOf(p.analyze(_apology));

        expect(message, contains('It said: $_apology'));
        expect(message, contains('"${p.model}"'));
      });

      for (final marker in {'a Kimi marker': _kimi, 'a harmony header': _harmony}
          .entries) {
        test('${marker.key} -- outside T-0083\'s rule -- gets the sentence',
            () async {
          final message = await _messageOf(p.analyze(marker.value));

          expect(message, contains('"${p.model}"'));
          expect(message, contains('It said: '));
        });
      }

      test('the key clause matches whether there is a key', () async {
        final message = await _messageOf(p.analyze(_prose));

        expect(message, p.hasKey ? contains('Your key') : isNot(contains('key')),
            reason: 'T-0097: the local path names no key it does not have');
      });

      test('the remedy offered is the model id', () async {
        final message = await _messageOf(p.analyze(_prose));

        expect(message, contains('the model id is yours to type'));
        // The prompt is a measured artifact no user can reach (decision
        // 0002), so it is never what a message tells them to change.
        expect(message, isNot(contains('prompt')));
      });

      test('the type is still a FormatException (T-0013 stays pinned)', () {
        expect(p.analyze(_prose), throwsA(isA<FormatException>()));
      });

      test('an ordinary answer is untouched', () async {
        expect((await p.analyze(_answer)).items.single.rawTitle,
            'Vellum Compass');
      });
    });
  });

  group('the quote', () {
    test('is capped through the shared helper at 200 characters', () async {
      final long = 'x' * 500;
      final message = await _messageOf(_openAi(long));

      expect(message, contains('It said: ${'x' * 200}...'));
      expect(message, isNot(contains('x' * 201)));
    });

    test('is collapsed to one line', () async {
      final message = await _messageOf(_openAi('I count\n\nthree   games.'));

      expect(message, contains('It said: I count three games.'));
    });
  });

  group('the sentences that already own their shape still win', () {
    test('the output cap does, even though the text is not JSON', () async {
      final message = await _messageOf(_openAi(_prose, finish: 'length'));

      expect(message, contains('output cap'));
      expect(message, isNot(contains('not the JSON document')));
    });

    test('so does Ollama\'s, under its own field name', () async {
      final message = await _messageOf(_ollama(_prose, done: 'length'));

      expect(message, contains('output cap'));
      expect(message, isNot(contains('not the JSON document')));
    });

    test('an empty answer is T-0142\'s, not this one', () async {
      final message = await _messageOf(_anthropic('   ', stop: 'end_turn'));

      expect(message, contains('no text at all'));
      expect(message, isNot(contains('not the JSON document')));
    });
  });

  group('the boundary', () {
    test('valid JSON of the wrong shape is left alone', () async {
      // A cast error, not a decode failure: a different problem with a
      // different fix, and deliberately not covered here.
      final message = await _messageOf(_openAi('[{"raw_title":"Vex"}]'));

      expect(message, isNot(contains('not the JSON document')));
    });

    test('the shared parse entry point still throws the bare decoder error',
        () {
      // The wrapper is per provider because only a provider knows the service
      // and the model; T-0083 and the empty-title tests call this directly.
      expect(() => parsePhotoAnalysisText(_prose, 'shelf.jpg'),
          throwsA(isA<FormatException>()));
      expect(() => parsePhotoAnalysisText(_prose, 'shelf.jpg'),
          throwsA(predicate((Object e) => '$e'.contains('character 1'))));
    });

    test('a fenced payload still parses rather than reaching the sentence',
        () async {
      final analysis = await _openAi('```json\n$_answer\n```');

      expect(analysis.items.single.rawTitle, 'Vellum Compass');
    });
  });

  group('the message alone', () {
    test('reads as one sentence family with T-0111 and T-0142', () {
      final message = visionNotJsonMessage(
        service: _openAiUrl,
        model: _openAiModel,
        answer: _prose,
      );

      expect(message, startsWith('$_openAiUrl answered for model '));
      expect(message, contains('(HTTP 200)'));
    });

    test('an answer that is only whitespace drops the quote clause', () {
      // Unreachable through a provider -- all three reject a blank answer as
      // T-0142's shape first -- so this pins the helper, not a code path.
      final message = visionNotJsonMessage(
        service: 'Anthropic',
        model: _anthropicModel,
        answer: '   ',
      );

      expect(message, isNot(contains('It said')));
    });
  });
}
