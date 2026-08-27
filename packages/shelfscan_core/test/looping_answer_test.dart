/// Two roads reach the output cap, and the message now knows which (T-0427).
///
/// The density road was the only one the sentence knew: "there was more on
/// that shelf than one answer can hold. Photograph it in two or three
/// sections". A frame can carry no more readable titles than one that scans
/// cleanly and still fill the cap, because it also holds narrow strips that
/// look like a spine and carry no title -- and there the advice sends the user
/// to re-shoot a photograph in sections that every section still ruins.
///
/// The hard half is the other direction. A real shelf legitimately carries
/// near-identical titles -- a numbered series, a remaster beside its original,
/// volumes differing by one word -- and calling that a loop is a worse defect
/// than the one being fixed. So every fixture below is invented, and the
/// similar-but-distinct ones are as much the subject as the repeating ones.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

final _photo = PhotoInput(name: 'shelf.jpg', bytes: Uint8List.fromList([7]));

String _item(String title) => '{"raw_title":"$title",'
    '"platform_hint":"SWITCH","media_type":"cartridge","confidence":0.9}';

const _edgeOn = '{"script":"unknown",'
    '"reason":"seen edge-on: a rib and a logo, no title"}';

/// The shape the cap actually leaves behind: an array that never closes and an
/// outer object that never closes either.
String _cutOff(String key, Iterable<String> records) =>
    '{"$key":[${records.join(',')}';

/// A numbered series, a remaster and its original, and volumes a word apart --
/// the three legitimate reasons a frame is full of titles that look alike.
final _similarButDistinct = <String>[
  for (var i = 1; i <= 12; i++) _item('Lantern Circuit $i'),
  _item('Harbour Glass'),
  _item('Harbour Glass Remastered'),
  _item('Harbour Glass: Director\\u0027s Cut'),
  for (var i = 1; i <= 12; i++) _item('Paper Kite Volume $i'),
  _item('Paper Kite Anthology'),
  _item('Paper Kite Encore'),
  _item('Tin Orchard'),
  _item('Tin Orchard 2'),
];

/// The run shape: one record written out until the budget is gone. T-0278's
/// second loop site is this, in `unreadable` rather than in `items`.
String _runOf(String record, int times) =>
    _cutOff('items', List.filled(times, record));

/// The cycle shape, and the one a long consecutive run would miss: the model
/// re-emits the block it just wrote, so no record ever follows itself.
List<String> _cycle(int distinct, int passes) => [
      for (var pass = 0; pass < passes; pass++)
        for (var i = 0; i < distinct; i++) _item('Silt Harbour $i'),
    ];

Future<String> _messageFrom(Future<PhotoAnalysis> analysis) async {
  try {
    await analysis;
  } on Object catch (e) {
    return e.toString();
  }
  fail('the truncated answer was accepted instead of reported');
}

Future<PhotoAnalysis> _ollama(String content) =>
    OllamaVisionProvider(
        client: MockClient((_) async => http.Response(
            jsonEncode({
              'message': {'content': content},
              'done_reason': 'length',
            }),
            200))).analyze(_photo);

Future<PhotoAnalysis> _openAi(String content) =>
    OpenAiCompatibleVisionProvider(
      baseUrl: 'https://example.test/v1',
      model: 'gpt-5.5',
      apiKey: 'sk-not-a-key',
      client: MockClient((_) async => http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': content},
                'finish_reason': 'length',
              }
            ]
          }),
          200)),
    ).analyze(_photo);

Future<PhotoAnalysis> _anthropic(String content) => AnthropicVisionProvider(
      apiKey: 'k',
      client: MockClient((_) async => http.Response(
          jsonEncode({
            'content': [
              {'type': 'text', 'text': content}
            ],
            'stop_reason': 'max_tokens',
          }),
          200)),
    ).analyze(_photo);

void main() {
  group('similarity is not evidence', () {
    test('a series, a remaster and a run of volumes are not a loop', () {
      expect(_similarButDistinct.length, greaterThan(20),
          reason: 'the fixture has to clear the cycle floor, or it proves '
              'nothing about the cycle rule');
      expect(answerRepeatsItself(_cutOff('items', _similarButDistinct)),
          isFalse);
    });

    test('two copies of one game on the shelf are not a loop', () {
      // Owning a game twice, or catching one case in the frame from two
      // angles, is an ordinary shelf and an ordinary pair of identical rows.
      final rows = [..._similarButDistinct];
      rows.insert(4, rows[4]);
      expect(answerRepeatsItself(_cutOff('items', rows)), isFalse);
    });

    test('an unreadable reason repeated a few times is not a loop', () {
      // T-0093 measured phantom `unreadable` entries arriving byte-identical
      // to each other. That is the model misbehaving and it is not this
      // defect, so the floor has to sit above it.
      expect(
          answerRepeatsItself(_cutOff('unreadable', List.filled(3, _edgeOn))),
          isFalse);
    });

    test('an honest answer cut off mid-record is not a loop', () {
      final honest = '${_cutOff('items', _similarButDistinct)},'
          '{"raw_title":"Copper Lant';
      expect(answerRepeatsItself(honest), isFalse);
    });
  });

  group('exact repetition past any plausible run is', () {
    test('one record written out until the budget is gone', () {
      expect(answerRepeatsItself(_runOf(_item('Silt Harbour'), 40)), isTrue);
    });

    test('the unreadable site, every entry byte-identical', () {
      expect(answerRepeatsItself(_cutOff('unreadable', List.filled(40, _edgeOn))),
          isTrue);
    });

    test('a cycle, where no record ever follows itself', () {
      final records = _cycle(20, 9);
      for (var i = 1; i < records.length; i++) {
        expect(records[i], isNot(records[i - 1]),
            reason: 'the fixture must contain no consecutive repeat at all, '
                'or it is testing the run rule again');
      }
      expect(answerRepeatsItself(_cutOff('items', records)), isTrue);
    });

    test('where the line sits: five in a row is not, six is', () {
      final row = _item('Silt Harbour');
      expect(answerRepeatsItself(_cutOff('items', List.filled(5, row))),
          isFalse);
      expect(answerRepeatsItself(_cutOff('items', List.filled(6, row))),
          isTrue);
    });
  });

  group('it cannot throw on the input it exists to judge', () {
    // Every one of these is an answer a cap can leave behind, and a detector
    // that dies on the truncated text is no detector.
    const survivable = <String, String>{
      'empty': '',
      'whitespace': '   \n\t ',
      'cut mid-string': '{"items":[{"raw_title":"Copper Lant',
      'cut mid-key': '{"items":[{"raw_ti',
      'prose, not JSON at all': 'I count three games on this shelf.',
      'nothing but opening braces': '{{{{{{{{{{',
      'nothing but closing braces': '}}}}}}}}}}',
      'a bare array of records': '[{"a":1},{"a":1}',
      'an escaped quote inside a title': r'{"items":[{"raw_title":"Say \"Ah\"',
    };

    survivable.forEach((what, answer) {
      test('$what answers false rather than throwing', () {
        expect(answerRepeatsItself(answer), isFalse);
      });
    });

    test('a brace inside a title does not move the depth', () {
      // If the scanner counted braces inside strings, this run would come out
      // as unbalanced junk and the loop would go unseen.
      expect(answerRepeatsItself(_runOf(_item('Brace } Trouble {'), 40)),
          isTrue);
    });

    test('a loop that never completes one record reads as density', () {
      // Stated because it is the deliberate blind spot: no complete record
      // means no evidence, and the incumbent message is the safe default.
      expect(answerRepeatsItself('{"items":[{"raw_title":"Silt Harbour'),
          isFalse);
    });
  });

  group('the two messages', () {
    test('the loop branch names framing and withdraws sectioning', () async {
      final message =
          await _messageFrom(_ollama(_runOf(_item('Silt Harbour'), 40)));

      expect(message, contains('the same few entries written out over and '
          'over'));
      expect(message, contains('only spines whose titles face the camera'));
      expect(message, contains('keep edge-on stacks out of frame'));
      expect(message, contains('the framing is the fix that is yours'));
      // The whole point: the advice that does not work must be gone, not
      // merely joined by better advice.
      expect(message, isNot(contains('two or three sections')));
      expect(message, isNot(contains('more on that shelf')));
      // Still the same cap, still not a Settings field.
      expect(message, contains('8192-token output cap'));
    });

    test('the density branch is word for word what it was', () async {
      final message =
          await _messageFrom(_ollama(_cutOff('items', _similarButDistinct)));

      expect(
          message,
          contains('Ollama at http://localhost:11434 stopped model '
              '"qwen2.5vl:7b" at the 8192-token output cap so the answer '
              'breaks off part-way and is no longer the complete JSON the '
              'rest of the scan reads. Neither the model id nor the photo '
              'file is at fault -- there was more on that shelf than one '
              'answer can hold. Photograph it in two or three sections and '
              'scan those instead. That cap is fixed in this build and '
              'neither the app nor the CLI has a control for it, so fewer '
              'spines is the fix that is yours.'));
    });

    test('a cloud endpoint gets the same discrimination', () async {
      // The three providers all hand their truncated text to one constructor,
      // so this cost nothing extra to give them.
      final looped =
          await _messageFrom(_openAi(_runOf(_item('Silt Harbour'), 40)));
      final dense =
          await _messageFrom(_openAi(_cutOff('items', _similarButDistinct)));

      expect(looped, contains('titles face the camera'));
      expect(looped, isNot(contains('two or three sections')));
      expect(dense, contains('two or three sections'));
      expect(dense, isNot(contains('titles face the camera')));
    });

    test('and so does Anthropic', () async {
      final looped =
          await _messageFrom(_anthropic(_runOf(_item('Silt Harbour'), 40)));

      expect(looped, contains('titles face the camera'));
      expect(looped, isNot(contains('two or three sections')));
    });

    test('a loop and an empty answer cannot both be claimed', () async {
      // An answer with no text has no records to repeat, so the reasoning
      // model's empty completion keeps its own sentence.
      final message = await _messageFrom(_openAi(''));

      expect(message, contains('wrote no answer at all'));
      expect(message, isNot(contains('titles face the camera')));
    });

    test('the raw answer still stays off the message', () async {
      Object? thrown;
      try {
        await _ollama(_runOf(_item('Silt Harbour'), 40));
      } on Object catch (e) {
        thrown = e;
      }

      final failure = thrown! as VisionApiException;
      expect(failure.message, isNot(contains('Silt Harbour')));
      expect(failure.body, contains('Silt Harbour'));
      expect(failure.statusCode, 200);
    });
  });
}
