/// A 200 whose text is valid JSON and is not this document (T-0167).
///
/// The fifth shape a 200 arrives in, and the last of the sequence: T-0111 the
/// output cap, T-0142 no text, T-0083 a leading reasoning element, T-0164 text
/// that is not JSON, and here JSON that decoded into something else.
///
/// **Nothing here is measured.** No endpoint has produced one of these;
/// every response below is a `MockClient` literal reproducing a shape
/// the filing measured offline through `parsePhotoAnalysisText`, and no call
/// leaves the machine.
///
/// The type is a `VisionApiException`, not T-0164's `FormatException`: the cast
/// error this replaces is pinned by nothing, so the choice was free and went to
/// the class the other two 200s already use.
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

Future<Object> _errorOf(Future<PhotoAnalysis> analysis) async {
  try {
    await analysis;
  } on Object catch (e) {
    return e;
  }
  fail('the answer was accepted instead of reported');
}

/// The five the filing measured, each with the clause the parse should stop on.
const _shapes = <String, (String, String)>{
  'the array without its envelope': (
    '[{"raw_title":"Vex"}]',
    'the answer is a list; it must be an object with an "items" list'
  ),
  'a list of plain titles': (
    '{"items":["Vex"]}',
    'items[0] is a string; it must be an object with a "raw_title"'
  ),
  'a number': (
    '42',
    'the answer is a number; it must be an object with an "items" list'
  ),
  'a bare string': (
    '"a string"',
    'the answer is a string; it must be an object with an "items" list'
  ),
  'unreadable as strings': (
    '{"unreadable":["a japanese spine"]}',
    'unreadable[0] is a string; it must be an object reporting something the '
        'model could not read'
  ),
  // Not in the filing's five: the list level itself, which falls out of the
  // same check.
  'items as one title': (
    '{"items":"Vex"}',
    'items is a string; it must be a list of the items the model read'
  ),
};

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
      _shapes.forEach((label, shape) {
        final (answer, problem) = shape;
        test('$label names the model and what was wrong', () async {
          final message = await _messageOf(p.analyze(answer));

          expect(message, contains(p.service));
          expect(message, contains('"${p.model}"'));
          expect(message, contains(problem));
          // The whole point of the task: all five used to be a Dart generic
          // and nothing about the run.
          expect(message, isNot(contains('is not a subtype')));
          expect(message, isNot(contains('type cast')));
        });
      });

      test('it quotes what the model actually sent', () async {
        expect(await _messageOf(p.analyze('{"items":["Vex"]}')),
            contains('It said: {"items":["Vex"]}'));
      });

      test('the key clause matches whether there is a key', () async {
        final message = await _messageOf(p.analyze('42'));

        expect(message, p.hasKey ? contains('Your key') : isNot(contains('key')),
            reason: 'T-0097: the local path names no key it does not have');
      });

      test('the remedy offered is the model id', () async {
        final message = await _messageOf(p.analyze('42'));

        expect(message, contains('the model id is yours to type'));
        // The prompt is a measured artifact no user can reach (decision
        // 0002), so it is never what a message tells them to change.
        expect(message, isNot(contains('prompt')));
      });

      test('the type is the family\'s, carrying the answer for a bug report',
          () async {
        final error = await _errorOf(p.analyze('[{"raw_title":"Vex"}]'));

        expect(error, isA<VisionApiException>());
        expect((error as VisionApiException).statusCode, 200);
        expect(error.body, '[{"raw_title":"Vex"}]');
        // Free choice, exercised: T-0164 kept FormatException because T-0013
        // and T-0083 pin it, and a cast error was pinned by nothing.
        expect(error, isNot(isA<FormatException>()));
      });

      test('an ordinary answer is untouched', () async {
        expect((await p.analyze(_answer)).items.single.rawTitle,
            'Vellum Compass');
      });
    });
  });

  group('an empty answer is an answer', () {
    test('an empty items array is not a failure', () async {
      final analysis = await _openAi('{"items":[]}');

      expect(analysis.items, isEmpty);
      expect(analysis.unreadable, isEmpty);
    });

    test('so is an empty document, and empty lists on both halves', () async {
      // T-0028 measured the local model answering `unreadable: []` on every
      // photo, including photos with unread spines on them.
      expect((await _ollama('{}')).items, isEmpty);
      expect((await _ollama('{"items":[],"unreadable":[]}')).unreadable,
          isEmpty);
    });

    test('an absent half is still an empty one, not a wrong shape', () async {
      final analysis = await _anthropic('{"unreadable":[]}');

      expect(analysis.items, isEmpty);
    });

    test('a null half reads as empty, as it did before the check', () async {
      final analysis = await _openAi('{"items":null,"unreadable":null}');

      expect(analysis.items, isEmpty);
      expect(analysis.unreadable, isEmpty);
    });
  });

  group('nothing is repaired into something plausible', () {
    test('the answer is declined whole rather than half-accepted', () async {
      // One good row and one string: the tempting case, since the good row is
      // parseable on its own. Half a document accepted looks like all of it.
      final message =
          await _messageOf(_openAi('{"items":[{"raw_title":"Vex"},"Rez"]}'));

      expect(message, contains('items[1] is a string'));
      expect(message, contains('declined whole rather than repaired'));
    });

    test('a wrong-typed field one level in is named by its path', () async {
      // Not a cast this parse makes -- `Detection.fromJson`'s own check, which
      // reached the user bare until the wrapper started catching it.
      final message = await _messageOf(
          _openAi('{"items":[{"raw_title":"Vex","confidence":"high"}]}'));

      expect(message, contains('items[0].confidence is a string'));
      expect(message, contains('"$_openAiModel"'));
    });

    test('an item with no title is still an unreadable spine, not a failure',
        () async {
      // The pre-existing rule (Detection.hasTitle): a wrong TYPE in the title
      // is an absent title, and that has a row of its own.
      final analysis = await _openAi('{"items":[{"raw_title":42}]}');

      expect(analysis.items, isEmpty);
      expect(analysis.unreadable.single.sourcePhoto, 'shelf.jpg');
    });
  });

  group('the sentences that already own their shape still win', () {
    test('the output cap does, even though the shape is also wrong', () async {
      final message = await _messageOf(_openAi('{"items":["Vex"]}',
          finish: 'length'));

      expect(message, contains('output cap'));
      expect(message, isNot(contains('it must be')));
    });

    test('an empty answer is T-0142\'s', () async {
      final message = await _messageOf(_anthropic('   ', stop: 'end_turn'));

      expect(message, contains('no text at all'));
    });

    test('text that never decoded is T-0164\'s, not this one', () async {
      final message = await _messageOf(_openAi('I count three games.'));

      expect(message, contains('not the JSON document'));
      expect(message, isNot(contains('it must be')));
    });
  });

  group('the parse alone', () {
    test('names the path without any provider present', () {
      expect(
          () => parsePhotoAnalysisText('{"items":["Vex"]}', 'shelf.jpg'),
          throwsA(isA<ReviewFormatException>()
              .having((e) => e.path, 'path', 'items[0]')));
    });

    test('the same type the review file has used since T-0050', () {
      // One vocabulary for "JSON that parsed and is not this document",
      // whichever document it is.
      expect(() => parsePhotoAnalysisText('42', 'shelf.jpg'),
          throwsA(isA<ReviewFormatException>()));
    });

    test('a fenced wrong shape is unwrapped first, then declined', () async {
      final message = await _messageOf(_openAi('```json\n[1,2]\n```'));

      expect(message, contains('the answer is a list'));
    });
  });

  group('the message alone', () {
    test('reads as one sentence family with the other four', () {
      final message = visionWrongShapeMessage(
        service: _openAiUrl,
        model: _openAiModel,
        problem: 'items[0] is a string; it must be an object with a "raw_title"',
        answer: '{"items":["Vex"]}',
      );

      expect(message, startsWith('$_openAiUrl answered for model '));
      expect(message, contains('(HTTP 200)'));
    });

    test('the quote goes through the shared 200-character helper', () {
      final answer = '[${'"x",' * 200}]';
      final message = visionWrongShapeMessage(
        service: 'Anthropic',
        model: _anthropicModel,
        problem: 'the answer is a list; it must be an object',
        answer: answer,
      );

      expect(message, contains('It said: ${answer.substring(0, 200)}...'));
      expect(message, isNot(contains(answer)));
    });
  });
}
