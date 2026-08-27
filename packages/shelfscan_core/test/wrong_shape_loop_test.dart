/// The same misattribution, on the branch where the loop closed its document
/// (T-0428).
///
/// T-0427 fixed the truncation sentence; this is its sibling. A repetition
/// loop either fills the context before the model closes its document or
/// closes it first -- HTTP 200, valid JSON, the wrong shape -- and which of
/// the two a user meets is decided by nothing the user did (T-0278). The
/// second ending landed on a sentence carrying the same claim T-0427 removed
/// from the first: that the one cause measured for this shape is a frame
/// holding more spines than the model can hold at once, ended by photographing
/// the shelf in sections. Density is a trigger for the loop and not the loop,
/// so on a frame full of narrow strips seen edge-on that names a false cause
/// and offers a remedy every section still defeats -- and then sends the user
/// to the model id, which is not at fault either.
///
/// **Nothing here is measured and nothing here is real.** Every document is a
/// literal built in this file, every title is invented, no photograph was
/// opened and no call leaves the machine.
///
/// The hard half is the other direction, unchanged from the sibling: a real
/// shelf legitimately carries a numbered series, a remaster beside its
/// original, volumes a word apart. Similarity is never evidence, so the
/// similar-but-distinct documents below are as much the subject as the
/// repeating ones.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

final _photo = PhotoInput(name: 'shelf.jpg', bytes: Uint8List.fromList([3]));

const _ollamaUrl = 'http://localhost:11434';
const _ollamaModel = 'qwen2.5vl:7b';
const _openAiUrl = 'https://api.groq.test/openai/v1';
const _openAiModel = 'qwen/qwen3.6-27b';

Map<String, Object?> _item(String title) => {
      'raw_title': title,
      'platform_hint': 'SWITCH',
      'media_type': 'cartridge',
      'confidence': 0.9,
    };

/// The three legitimate reasons one frame is full of titles that look alike.
final _distinct = <Map<String, Object?>>[
  for (var i = 1; i <= 12; i++) _item('Ashen Ferry $i'),
  _item('Glass Meridian'),
  _item('Glass Meridian Remastered'),
  _item('Glass Meridian: Extended Cut'),
  for (var i = 1; i <= 12; i++) _item('Nine Lantern Road Volume $i'),
  _item('Copper Vellum'),
  _item('Copper Vellum 2'),
];

final _distinctTitles = [for (final r in _distinct) r['raw_title'] as String];

/// Wrong shape one: the array without its envelope.
String _bareList(List<Object?> records) => jsonEncode(records);

/// Wrong shape two, and the one a model plausibly writes: a list of plain
/// titles where the objects belong.
String _stringItems(List<String> titles) => jsonEncode({'items': titles});

/// The run shape: one record written out until the answer is gone.
List<Object?> _run(int times) => List.filled(times, _item('Copper Vellum'));

/// The cycle shape, which a run test alone would miss: the model re-emits the
/// block it just wrote, so no record ever follows itself.
List<String> _cycleTitles(int distinct, int passes) => [
      for (var pass = 0; pass < passes; pass++)
        for (var i = 0; i < distinct; i++) 'Copper Vellum $i',
    ];

http.Response _json(Map<String, Object?> body) => http.Response(
    jsonEncode(body), 200,
    headers: {'content-type': 'application/json; charset=utf-8'});

Future<PhotoAnalysis> _ollama(String content) => OllamaVisionProvider(
      baseUrl: _ollamaUrl,
      model: _ollamaModel,
      client: MockClient((_) async => _json({
            'message': {'content': content}
          })),
    ).analyze(_photo);

Future<PhotoAnalysis> _openAi(String content) => OpenAiCompatibleVisionProvider(
      baseUrl: _openAiUrl,
      model: _openAiModel,
      apiKey: 'k',
      client: MockClient((_) async => _json({
            'choices': [
              {
                'message': {'role': 'assistant', 'content': content}
              }
            ]
          })),
    ).analyze(_photo);

Future<Object> _errorOf(Future<PhotoAnalysis> analysis) async {
  try {
    await analysis;
  } on Object catch (e) {
    return e;
  }
  fail('the wrong-shape answer was accepted instead of reported');
}

Future<String> _messageOf(Future<PhotoAnalysis> analysis) async =>
    (await _errorOf(analysis)).toString();

/// Clauses that must not survive on either branch: the withdrawn cause and the
/// remedy that rested on it.
const _falseCause = [
  'the one cause measured for this shape',
  'more spines than the model can hold at once',
  'wall of copies',
  'two or three sections',
];

void main() {
  group('a looping document is told what actually caused it', () {
    test('the run shape, through the local provider', () async {
      final message = await _messageOf(_ollama(_bareList(_run(40))));

      expect(message,
          contains('the same few entries written out over and over'));
      expect(
          message,
          contains(
              'narrow strips that look like a spine and carry nothing to '
              'read'));
      expect(message, contains('cases stacked edge-on'));
      expect(message, contains('Re-frame the shot'));
      for (final clause in _falseCause) {
        expect(message, isNot(contains(clause)), reason: clause);
      }
    });

    test('the cycle shape, where no record ever follows itself', () async {
      final message =
          await _messageOf(_openAi(_stringItems(_cycleTitles(20, 6))));

      expect(message,
          contains('the same few entries written out over and over'));
      expect(message,
          contains('Cutting this same shot into sections will not help'));
    });

    test('sectioning is withdrawn in as many words, not merely omitted',
        () async {
      final message = await _messageOf(_ollama(_bareList(_run(40))));

      expect(message, contains('every section still holds them'));
    });

    test('the answer is still declined whole, and still named', () async {
      final message = await _messageOf(_ollama(_bareList(_run(40))));

      expect(message, contains('"$_ollamaModel"'));
      expect(message, contains('the answer is a list; it must be an object'));
      expect(message, contains('declined whole rather than repaired'));
    });
  });

  group('a looping frame is not sent to the model id', () {
    test('the sentence does not offer it, and says so', () async {
      final message = await _messageOf(_openAi(_bareList(_run(40))));

      expect(message, isNot(contains('the model id is yours to type')));
      expect(message, contains('the model id is not what to change either'));
    });

    test('and neither does the Settings shortcut behind it', () async {
      final looped = await _errorOf(_openAi(_bareList(_run(40))));
      final other = await _errorOf(_openAi('42'));

      // T-0169: the app reads the route off the failure, not the status, and
      // both of these are 200. A `true` here would offer the model id through
      // the button after the sentence withdrew it.
      expect((looped as UserSetCause).causeIsUserSet, isFalse);
      expect((other as UserSetCause).causeIsUserSet, isTrue);
    });
  });

  group('an answer that does not repeat keeps its own sentence', () {
    test('a numbered series and a remaster are not a loop', () async {
      final message = await _messageOf(_openAi(_bareList(_distinct)));

      expect(message, contains('the model id is yours to type'));
      expect(message, isNot(contains('over and over')));
      expect(message, isNot(contains('edge-on')));
    });

    test('the same titles as plain strings are still not a loop', () async {
      final message = await _messageOf(_ollama(_stringItems(_distinctTitles)));

      expect(message, contains('the model id is yours to type'));
      expect(message, isNot(contains('Re-frame')));
    });

    test('and the false cause is gone from this branch too', () async {
      final message = await _messageOf(_openAi('42'));

      for (final clause in _falseCause) {
        expect(message, isNot(contains(clause)), reason: clause);
      }
      expect(message, contains('Scan that photo again'));
    });

    test('an ordinary answer is untouched by any of this', () async {
      final analysis = await _openAi(jsonEncode({
        'items': [_item('Copper Vellum')]
      }));

      expect(analysis.items.single.rawTitle, 'Copper Vellum');
    });
  });

  group('the typed rule sees what the text scan structurally cannot', () {
    final titles = List.filled(600, 'Copper Vellum');

    test('a list of plain strings holds no brace-balanced records', () {
      // Not a defect in the sibling: the text road judges an answer cut off
      // mid-record, and brace matching is the only thing that reads one.
      expect(answerRepeatsItself(_stringItems(titles)), isFalse);
    });

    test('decoded, the same list is a loop', () {
      expect(documentRepeatsItself(jsonDecode(_stringItems(titles))), isTrue);
    });

    test('which is what the message ends up saying', () async {
      expect(await _messageOf(_ollama(_stringItems(titles))),
          contains('over and over'));
    });
  });

  group('the two roads share one rule, not two copies of it', () {
    List<Object?> runOf(int n) => List.filled(n, _item('Copper Vellum'));
    String textOf(List<Object?> records) => jsonEncode({'items': records});

    test('the run line sits in the same place on both: five is not, six is',
        () {
      for (final (n, expected) in [(5, false), (6, true)]) {
        final text = textOf(runOf(n));
        expect(answerRepeatsItself(text), expected, reason: 'text, $n');
        expect(documentRepeatsItself(jsonDecode(text)), expected,
            reason: 'document, $n');
      }
    });

    test('and so does the cycle line: a quarter distinct is, more is not', () {
      final cases = <String, (List<Object?>, bool)>{
        'twenty distinct over eighty': (
          [for (final t in _cycleTitles(20, 4)) _item(t)],
          true
        ),
        'twenty-one distinct over eighty': (
          [for (var i = 0; i < 80; i++) _item('Copper Vellum ${i % 21}')],
          false
        ),
      };
      cases.forEach((label, expected) {
        final (records, want) = expected;
        final text = textOf(records);
        expect(answerRepeatsItself(text), want, reason: 'text, $label');
        expect(documentRepeatsItself(jsonDecode(text)), want,
            reason: 'document, $label');
      });
    });

    test('below the cycle floor the run test is the only one that runs', () {
      // Nineteen records, all distinct but one pair -- under either floor.
      final records = [
        for (var i = 0; i < 18; i++) _item('Copper Vellum $i'),
        _item('Copper Vellum 0'),
      ];

      expect(documentRepeatsItself(jsonDecode(textOf(records))), isFalse);
    });
  });

  group('the loop is judged on the longest list, so a short repeat is not one',
      () {
    test('a repeated field beside a longer distinct list is left alone', () {
      final document = {
        'items': _distinctTitles,
        'notes': List.filled(8, 'seen edge-on'),
      };

      expect(documentRepeatsItself(document), isFalse);
    });

    test('and the loop is found wherever in the document it sits', () {
      final document = {
        'meta': {'photo': 'shelf.jpg'},
        'result': {
          'unreadable': List.filled(60, {'reason': 'no title on the strip'})
        },
      };

      expect(documentRepeatsItself(document), isTrue);
    });
  });

  group('the detection cannot throw on the input it exists to judge', () {
    // Every one of these decoded and is not the document this scan asks for,
    // which is the whole population this branch sees.
    final shapes = <String, Object?>{
      'a number': 42,
      'a bare string': 'a string',
      'null': null,
      'true': true,
      'an empty object': <String, Object?>{},
      'an empty list': <Object?>[],
      'items as one title': {'items': 'Copper Vellum'},
      'unreadable as strings': {
        'unreadable': ['a spine with no title']
      },
      'a list of nulls': [null, null, null],
      'a list of lists': [
        [1, 2],
        [3, 4]
      ],
      'nesting with no list at the bottom': {
        'a': {
          'b': {
            'c': {'d': 'e'}
          }
        }
      },
      'a list of mixed kinds': [1, 'two', null, true, <String, Object?>{}],
      'a string holding a brace': {
        'items': ['Brace } Trouble {']
      },
      'numbers where records belong': {
        'items': [1, 2, 3, 4, 5, 6, 7]
      },
    };

    shapes.forEach((label, document) {
      test('$label answers rather than throws', () {
        expect(documentRepeatsItself(document), isA<bool>());
      });
    });

    test('a deeply nested document is walked without recursing', () {
      Object? nested = 'bottom';
      for (var i = 0; i < 20000; i++) {
        nested = [nested];
      }

      expect(documentRepeatsItself(nested), isFalse);
    });

    test('and the same shapes reach the user as a sentence, not a crash',
        () async {
      for (final shape in shapes.entries) {
        final text = jsonEncode(shape.value);
        try {
          // Two of these decode into a document this scan CAN read -- an
          // object with neither half is a photograph with nothing on it, which
          // is an answer and never an error (T-0028).
          await _openAi(text);
        } on Object catch (e) {
          expect(e.toString(), contains('(HTTP 200)'), reason: shape.key);
        }
      }
    });
  });

  group('the sibling is untouched', () {
    test('a truncated looping answer still gets the truncation sentence',
        () async {
      final records =
          List.filled(40, jsonEncode(_item('Copper Vellum'))).join(',');
      final analysis = OllamaVisionProvider(
        baseUrl: _ollamaUrl,
        model: _ollamaModel,
        client: MockClient((_) async => _json({
              'message': {'content': '{"items":[$records'},
              'done_reason': 'length',
            })),
      ).analyze(_photo);

      final message = await _messageOf(analysis);

      expect(message, contains('output cap'));
      expect(message, isNot(contains('(HTTP 200)')));
      expect(message, contains('the framing is the fix that is yours'));
    });
  });
}
