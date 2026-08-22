/// A reasoning model's thinking arrives inline in the answer (T-0083).
///
/// Measured 2026-08-15 against Groq on `qwen/qwen3.6-27b`, the one
/// vision-capable model that account is offered: asked for JSON only,
/// `message.content` begins `\n<think>\nThe user wants me to identify game
/// titles...` and there is no separate `reasoning` field. The key that produced
/// that measurement has been overwritten, so every response below is a
/// `MockClient` literal reproducing the recorded shape -- no call left this
/// machine.
///
/// The other half of the job is the boundary: a marker this rule does not cover
/// must still fail exactly as it does today, and a payload that begins `{` must
/// come through untouched.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

final _photo = PhotoInput(name: 'shelf.jpg', bytes: Uint8List.fromList([1, 2]));

const _answer = '{"items":[{"raw_title":"Vellum Compass"}]}';

/// The recorded opening, continued into the shape a reasoning model actually
/// writes. The echoed `{"items":...}` is not decoration: models here copy the
/// schema's example text verbatim (T-0014, T-0028), and it is valid JSON, so a
/// parser that hunted for the first `{` would answer with it.
const _thinking = '\n<think>\n'
    'The user wants me to identify game titles from this shelf photo and answer '
    'with JSON only, in the shape {"items":[{"raw_title":"..."}]}. Let me read '
    'the spines from left to right.\n'
    '</think>\n\n';

http.Response _openAiSaying(String content, {String? finish}) => http.Response(
    jsonEncode({
      'choices': [
        {
          'message': {'role': 'assistant', 'content': content},
          if (finish != null) 'finish_reason': finish,
        }
      ]
    }),
    200,
    // Without the charset an http.Response encodes its body latin1, and the
    // Kimi marker below is not latin1.
    headers: {'content-type': 'application/json; charset=utf-8'});

Future<PhotoAnalysis> _openAi(String content, {String? finish}) =>
    OpenAiCompatibleVisionProvider(
      baseUrl: 'https://api.groq.test/openai/v1',
      model: 'qwen/qwen3.6-27b',
      apiKey: 'k',
      client: MockClient((_) async => _openAiSaying(content, finish: finish)),
    ).analyze(_photo);

Future<PhotoAnalysis> _ollama(String content) => OllamaVisionProvider(
        client: MockClient((_) async => http.Response(
            jsonEncode({
              'message': {'content': content}
            }),
            200)))
    .analyze(_photo);

Future<PhotoAnalysis> _anthropic(String text) => AnthropicVisionProvider(
        apiKey: 'k',
        client: MockClient((_) async => http.Response(
            jsonEncode({
              'content': [
                {'type': 'text', 'text': text}
              ]
            }),
            200)))
    .analyze(_photo);

Future<String> _messageOf(Future<PhotoAnalysis> analysis) async {
  try {
    await analysis;
  } on Object catch (e) {
    return e.toString();
  }
  fail('the answer was accepted instead of reported');
}

void main() {
  group('the measured shape', () {
    test('the recorded think preamble parses', () async {
      final analysis = await _openAi('$_thinking$_answer');

      expect(analysis.items.single.rawTitle, 'Vellum Compass');
      expect(analysis.items.single.sourcePhoto, 'shelf.jpg');
    });

    test('the thinking is dropped, not searched for JSON', () async {
      // The echoed example inside the block decodes to raw_title "...", so this
      // is what a first-brace scan would have returned instead.
      final analysis = await _openAi('$_thinking$_answer');

      expect(analysis.items.single.rawTitle, isNot('...'));
    });

    test('thinking then a fenced payload parses', () async {
      // Both conventions in one answer: the fence stripper (T-0013) runs on
      // what is left after the block goes.
      final analysis = await _openAi('$_thinking```json\n$_answer\n```');

      expect(analysis.items.single.rawTitle, 'Vellum Compass');
    });

    test('the parse entry point takes it directly', () {
      final analysis =
          parsePhotoAnalysisText('$_thinking$_answer', 'shelf.jpg');

      expect(analysis.items.single.rawTitle, 'Vellum Compass');
    });
  });

  group('a rule about the payload, not a list of markers', () {
    for (final tag in ['think', 'thinking', 'reasoning', 'analysis']) {
      test('<$tag> is covered without being named', () async {
        final analysis = await _openAi('<$tag>weighing it up</$tag>\n$_answer');

        expect(analysis.items.single.rawTitle, 'Vellum Compass');
      });
    }

    test('attributes on the opening tag are covered', () async {
      final analysis =
          await _openAi('<think type="internal">hm</think>\n$_answer');

      expect(analysis.items.single.rawTitle, 'Vellum Compass');
    });
  });

  group('the boundary', () {
    test('a marker that is not an element still fails', () async {
      // Kimi's markers are not tags, so nothing here recognises them and the
      // answer dies at jsonDecode exactly as it does today.
      final message =
          await _messageOf(_openAi('◁think▷weighing it up◁/think▷\n$_answer'));

      expect(message, contains('FormatException'));
    });

    test('prose before the payload still fails', () async {
      final message =
          await _messageOf(_openAi('Here is the JSON you asked for:\n$_answer'));

      expect(message, contains('FormatException'));
    });

    test('an answer wrapped whole in an element fails as it does today',
        () async {
      // Stripped to an empty string this would be "Unexpected end of input" --
      // a worse sentence about a different problem. The block goes only when
      // something is left after it.
      final message = await _messageOf(_openAi('<answer>$_answer</answer>'));

      expect(message, contains('FormatException'));
      expect(message, isNot(contains('end of input')));
    });

    test('an unclosed block that ran into the cap is still the cap', () async {
      // The provider reads finish_reason before it parses (T-0111), so an
      // answer that is thinking and nothing else never reaches this rule.
      final message = await _messageOf(
          _openAi('<think>the shelf holds a lot of', finish: 'length'));

      expect(message, contains('output cap'));
      expect(message, isNot(contains('FormatException')));
    });

    test('an unclosed block that stopped on its own is a FormatException',
        () async {
      final message =
          await _messageOf(_openAi('<think>the shelf holds a lot of'));

      expect(message, contains('FormatException'));
    });
  });

  group('the payload is untouched', () {
    test('a title that contains a marker survives', () async {
      const title = '<think> and other stories';
      final analysis =
          await _openAi('{"items":[{"raw_title":"$title"}]}');

      expect(analysis.items.single.rawTitle, title);
    });

    test('an ordinary answer is unchanged', () async {
      expect((await _openAi(_answer)).items.single.rawTitle, 'Vellum Compass');
    });
  });

  group('one parse for every provider', () {
    // The thinking is a property of the MODEL, not of the transport, and Ollama
    // serves reasoning models too -- so this is deliberate, not incidental. The
    // Ollama request is unchanged and T-0013/T-0014/T-0028/T-0035's tests are
    // unedited.
    test('ollama gets the same parse', () async {
      expect((await _ollama('$_thinking$_answer')).items.single.rawTitle,
          'Vellum Compass');
    });

    test('anthropic gets the same parse', () async {
      expect((await _anthropic('$_thinking$_answer')).items.single.rawTitle,
          'Vellum Compass');
    });
  });
}
