/// The third road to the output cap: a completion that wrote nothing (T-0464).
///
/// T-0120 gave that shape its own opening clause -- "wrote no answer at all" --
/// and never its own conclusion. T-0427 then added the loop road and chose
/// between it and density on `answerRepeatsItself`, which answers `false` for
/// an answer with no records in it, so a silent completion fell through to the
/// density conclusion: the model id declared fine, the shelf declared too full,
/// and fewer spines offered as the fix. Every clause after the first was wrong
/// about a model that spends the budget reasoning, because it spends it on any
/// frame however few spines are in it.
///
/// So these tests are mostly negative. What the sentence must NOT say is the
/// whole of the defect, and the two roads it borrowed from have to stay exactly
/// where they were -- which is why the loop road is pinned whole here as well.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

final _photo = PhotoInput(name: 'shelf.jpg', bytes: Uint8List.fromList([3, 5]));

String _item(String title) => '{"raw_title":"$title",'
    '"platform_hint":"SWITCH","media_type":"cartridge","confidence":0.9}';

/// An honest answer the cap cut off part-way: the density road's input.
final _cutOff = '{"items":[${[
  for (var i = 1; i <= 24; i++) _item('Marlow Ridge $i'),
].join(',')},{"raw_title":"Copper Lant';

/// One record written until the budget is gone: the loop road's input.
final _looping =
    '{"items":[${List.filled(40, _item('Silt Harbour')).join(',')}';

/// Every request the provider made, so a retry cannot hide in a message test.
final _calls = <String>[];

Future<PhotoAnalysis> _ollama(String content, {String? done = 'length'}) =>
    OllamaVisionProvider(
        client: MockClient((request) async {
          _calls.add(request.url.path);
          return http.Response(
              jsonEncode({
                'message': {'content': content},
                if (done != null) 'done_reason': done,
              }),
              200);
        })).analyze(_photo);

Future<PhotoAnalysis> _openAi(String? content) =>
    OpenAiCompatibleVisionProvider(
      baseUrl: 'https://example.test/v1',
      model: 'nimbus-vision-x',
      apiKey: 'sk-not-a-key',
      client: MockClient((request) async {
        _calls.add(request.url.path);
        return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {'role': 'assistant', 'content': content},
                  'finish_reason': 'length',
                }
              ]
            }),
            200);
      }),
    ).analyze(_photo);

Future<PhotoAnalysis> _anthropic(String? text) => AnthropicVisionProvider(
      apiKey: 'k',
      client: MockClient((request) async {
        _calls.add(request.url.path);
        return http.Response(
            jsonEncode({
              'content': [
                if (text != null) {'type': 'text', 'text': text}
              ],
              'stop_reason': 'max_tokens',
            }),
            200);
      }),
    ).analyze(_photo);

Future<String> _messageFrom(Future<PhotoAnalysis> analysis) async {
  try {
    await analysis;
  } on Object catch (e) {
    return e.toString();
  }
  fail('the capped answer was accepted instead of reported');
}

/// The three clauses the density road owns. None may appear on a road where
/// the frame is not evidence for anything.
const _aboutTheShelf = [
  'two or three sections',
  'more on that shelf',
  'fewer spines',
];

void main() {
  setUp(_calls.clear);

  group('a capped answer with no text says nothing about the shelf', () {
    test('none of the density advice survives on it', () async {
      final message = await _messageFrom(_ollama(''));

      for (final claim in _aboutTheShelf) {
        expect(message, isNot(contains(claim)),
            reason: 'the frame is not evidence here and this sends the user '
                'to re-shoot a photograph that was fine');
      }
      // Nor the loop road's, which is about the frame for a different reason.
      expect(message, isNot(contains('titles face the camera')));
      expect(message, isNot(contains('edge-on')));
    });

    test('it does not clear the model id it has the only evidence against',
        () async {
      final local = await _messageFrom(_ollama(''));
      final cloud = await _messageFrom(_openAi(''));

      for (final message in [local, cloud]) {
        expect(message,
            isNot(contains('The key, the model id and the photo file are all '
                'fine')));
        expect(message,
            isNot(contains('Neither the model id nor the photo file is at '
                'fault')));
      }
      // And it borrows no key vocabulary on the keyless path either (T-0097).
      expect(local.toLowerCase(), isNot(contains('the key')));
    });

    test('the conclusion is the model and the output budget', () async {
      final message = await _messageFrom(_ollama(''));

      expect(message, contains('wrote no answer at all'));
      expect(message, contains('there is no answer at all, not a shortened '
          'one'));
      expect(message, contains('spend an entire output budget'));
      expect(message, contains('the model is the fix that is yours'));
      // The cap itself is still not offered as a knob (T-0072).
      expect(message, contains('8192-token output cap'));
      expect(message, contains('fixed in this build'));
    });

    test('the action names a tested model without closing the door on others',
        () async {
      final message = await _messageFrom(_ollama(''));

      expect(message, contains('Reach for a vision instruct model'));
      expect(message, contains('qwen3-vl:8b-instruct'));
      expect(message, contains('has been tested here'));
      expect(message,
          contains('other image-capable models that answer directly work here '
              'too'),
          reason: 'naming one model must not read as naming the only one');
      expect(message.toLowerCase(), isNot(contains('only supported')));
      expect(message.toLowerCase(), isNot(contains('the only model')));
    });

    test('word for word, on the local path the run was reported from',
        () async {
      final message = await _messageFrom(_ollama(''));

      expect(
          message,
          contains('Ollama at http://localhost:11434 stopped model '
              '"$defaultOllamaModel" at the 8192-token output cap and wrote no '
              'answer at all -- a reasoning model can spend the whole budget '
              'thinking before it writes a character. Nothing here is '
              'evidence about the photograph -- and nothing was cut short: '
              'there is no answer at all, not a shortened one. A model that '
              'reasons before it answers can spend an entire output budget '
              'doing so on any frame, and this route asks for one concise '
              'structured answer instead. Reach for a vision instruct model: '
              '"qwen3-vl:8b-instruct" is one that has been tested here, and '
              'other image-capable models that answer directly work here too. '
              'That cap is fixed in this build and neither the app nor the '
              'CLI has a control for it, so the model is the fix that is '
              'yours.'));
    });
  });

  group('the two roads it used to borrow from are where they were', () {
    test('a part-way answer still gets the density conclusion', () async {
      final message = await _messageFrom(_ollama(_cutOff));

      expect(message, contains('breaks off part-way'));
      expect(message, contains('there was more on that shelf than one answer '
          'can hold'));
      expect(message, contains('fewer spines is the fix that is yours'));
      expect(message, isNot(contains('vision instruct')));
    });

    test('the loop road, word for word', () async {
      final message = await _messageFrom(_ollama(_looping));

      expect(
          message,
          contains('Ollama at http://localhost:11434 stopped model '
              '"$defaultOllamaModel" at the 8192-token output cap so the answer '
              'breaks off part-way and is no longer the complete JSON the '
              'rest of the scan reads. Neither the model id nor the photo '
              'file is at fault -- and neither is the size of the shelf: the '
              'answer that was cut off is the same few entries written out '
              'over and over, not a long list that ran out of room. That '
              'happens when a frame holds narrow strips that look like a '
              'spine and carry nothing to read -- cases stacked edge-on, '
              'showing a rib and a logo and no title. The model cannot tell '
              'one from the next, so it enumerates them without end. Re-frame '
              'the shot so that only spines whose titles face the camera are '
              'in it, and keep edge-on stacks out of frame. Cutting this same '
              'shot into sections will not help: every section still holds '
              'them. That cap is fixed in this build and neither the app nor '
              'the CLI has a control for it, so the framing is the fix that '
              'is yours.'));
      expect(message, isNot(contains('vision instruct')));
    });

    test('whitespace is not an answer either', () async {
      // The flag is `answer.trim().isEmpty`, so a completion of spaces is the
      // silent road and not a part-way one.
      final message = await _messageFrom(_ollama('   \n\t '));

      expect(message, contains('wrote no answer at all'));
      expect(message, isNot(contains('two or three sections')));
    });
  });

  group('all three providers reach it', () {
    test('an openai-compatible endpoint with empty content', () async {
      final message = await _messageFrom(_openAi(''));

      expect(message, contains('nimbus-vision-x'));
      expect(message, contains('vision instruct'));
      expect(message, isNot(contains('two or three sections')));
    });

    test('an openai-compatible endpoint with no content field at all',
        () async {
      final message = await _messageFrom(_openAi(null));

      expect(message, contains('wrote no answer at all'));
      expect(message, contains('qwen3-vl:8b-instruct'));
    });

    test('anthropic with no text block', () async {
      final message = await _messageFrom(_anthropic(null));

      expect(message, contains('Anthropic'));
      expect(message, contains('vision instruct'));
      expect(message, isNot(contains('fewer spines')));
    });
  });

  group('it is still one capped completion and one exception', () {
    test('the provider asks once and does not ask again', () async {
      await _messageFrom(_ollama(''));

      expect(_calls, hasLength(1),
          reason: 'a silent completion costs a whole budget; asking again '
              'buys a second one for the same answer');
    });

    test('it is not retryable, on this road as on the other two', () async {
      await expectLater(
          _ollama(''), throwsA(isNot(isA<RetryableException>())));
      await expectLater(
          _ollama(_cutOff), throwsA(isNot(isA<RetryableException>())));
      await expectLater(
          _ollama(_looping), throwsA(isNot(isA<RetryableException>())));
    });

    test('the raw answer stays off the message', () async {
      Object? thrown;
      try {
        await _openAi('');
      } on Object catch (e) {
        thrown = e;
      }

      final failure = thrown! as VisionApiException;
      expect(failure.statusCode, 200);
      expect(failure.body, isNotEmpty);
    });
  });

  group('and it is not the empty answer that never hit the cap', () {
    test('done_reason stop with no text is the other exception entirely',
        () async {
      // T-0142's pair: a 200 carrying no text for a reason that is not the
      // budget. Nothing about a cap, a model to swap or an output budget
      // belongs in it, and this road must not have blurred them.
      final capped = await _messageFrom(_ollama(''));
      final empty = await _messageFrom(_ollama('', done: 'stop'));

      expect(empty, contains('with no text at all'));
      // It says the phrase once, to rule the cap OUT; it never quotes a
      // number and never sends anyone to change the model for that reason.
      expect(empty, contains('the only empty answer this build can explain is '
          'the output cap, and this was not that'));
      expect(empty, isNot(contains('token output cap')));
      expect(empty, isNot(contains('vision instruct')));
      expect(capped, isNot(contains('with no text at all')));
      expect(capped, contains('8192-token output cap'));
    });
  });
}
