/// Guards the titleless-detection drop (T-0035).
///
/// qwen2.5vl:32b emitted one detection of a run with an empty `raw_title` and a
/// `PS5` hint, and it reached the review document as a row containing
/// nothing. The row is dropped at the two parse entry points and counted as
/// an unreadable spine instead, so that nothing disappears in silence.
///
/// Three things are protected here:
///   1. no such row reaches `items`, from either parse entry point;
///   2. an existing `review.json` carrying one is healed on load, the same
///      way T-0014's absent markers are;
///   3. a title of one legitimate character is not collateral damage.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

/// Values the model can put in `raw_title` that name nothing.
const _titleless = <String, Object?>{
  'empty string': '',
  'a single space': ' ',
  'spaces': '     ',
  'tab and newline': '\t\n',
  'non-breaking space': '\u00A0',
  'JSON null': null,
  'a number': 0,
  'absent key': _absent,
};

/// Marker for "do not write the key at all".
const _absent = Object();

Map<String, dynamic> _item(Object? title, {String? hint}) => {
      if (!identical(title, _absent)) 'raw_title': title,
      if (hint != null) 'platform_hint': hint,
      'media_type': 'disc',
      'confidence': 1.0,
    };

PhotoAnalysis _analyzed(List<Map<String, dynamic>> items,
        {List<Map<String, dynamic>> unreadable = const []}) =>
    parsePhotoAnalysisText(
      jsonEncode({'items': items, 'unreadable': unreadable}),
      'shelf_a.jpg',
    );

/// The whole document shape, so the drop is exercised where it lands rather
/// than only where it is decided.
Map<String, dynamic> _document(List<Map<String, dynamic>> detections,
        {List<Map<String, dynamic>> unreadable = const []}) =>
    jsonDecode(jsonEncode({
      'version': 1,
      'created': '2026-08-14T09:12:00.000Z',
      'photos': ['shelf_a.jpg'],
      'games': [
        for (final detection in detections)
          {
            'detection': {'source_photo': 'shelf_a.jpg', ...detection},
            'best': null,
            'candidates': <dynamic>[],
            'status': 'pending',
          },
      ],
      'unreadable': unreadable,
    })) as Map<String, dynamic>;

void main() {
  group('a titleless detection never becomes an item', () {
    _titleless.forEach((name, title) {
      test('$name -> dropped from items', () {
        final analysis = _analyzed([_item(title, hint: 'PS5')]);

        expect(analysis.items, isEmpty);
        // A non-string used to throw out of the cast and lose the photo.
        expect(analysis.unreadable, hasLength(1));
      });

      test('$name -> counted as an unreadable spine on its photo', () {
        final spine = _analyzed([_item(title)]).unreadable.single;

        expect(spine.sourcePhoto, 'shelf_a.jpg');
        expect(spine.script, SpineScript.unknown);
        expect(spine.reason, isNotNull);
      });

      test('$name -> dropped when read back out of a review.json', () {
        final doc = ReviewDocument.fromJson(_document([_item(title)]));

        expect(doc.games, isEmpty);
        expect(doc.unreadable, hasLength(1));
        expect(doc.unreadableByPhoto, {'shelf_a.jpg': 1});
      });
    });

    test('the readable items beside it are untouched', () {
      final analysis = _analyzed([
        _item('COBALT CHIME'),
        _item(''),
        _item('Vex'),
      ]);

      expect(analysis.items.map((d) => d.rawTitle), ['COBALT CHIME', 'Vex']);
      expect(analysis.unreadable, hasLength(1));
    });

    test('the spines the model reported itself keep their own entries', () {
      final analysis = _analyzed(
        [_item('  ')],
        unreadable: [
          {'script': 'japanese', 'reason': 'kanji too small'}
        ],
      );

      expect(analysis.items, isEmpty);
      expect(analysis.unreadable.map((u) => u.script),
          [SpineScript.japanese, SpineScript.unknown]);
      expect(analysis.unreadable.first.reason, 'kanji too small');
    });

    test('two of them off different photos no longer merge into one row', () {
      // titleKey folds both to the empty string, so before the fix stage 2
      // collapsed them into a single meaningless review row.
      final detections = [
        ...parsePhotoAnalysisText('{"items":[{"raw_title":""}]}', 'a.jpg').items,
        ...parsePhotoAnalysisText('{"items":[{"raw_title":" "}]}', 'b.jpg')
            .items,
      ];

      expect(detections, isEmpty);
      expect(dedupeDetections(detections), isEmpty);
    });
  });

  group('a one-character title survives', () {
    // The shortest legitimate spine reads the project has to keep working.
    for (final title in ['Z', '7', '真', 'Ω']) {
      test('${jsonEncode(title)} stays an item', () {
        final analysis = _analyzed([_item(title, hint: 'PS5')]);

        expect(analysis.unreadable, isEmpty);
        expect(analysis.items.single.rawTitle, title);
        expect(analysis.items.single.platformHint, 'PS5');
      });

      test('${jsonEncode(title)} survives a review.json round-trip', () {
        final doc = ReviewDocument.fromJson(_document([_item(title)]));

        expect(doc.unreadable, isEmpty);
        expect(doc.games.single.detection.rawTitle, title);
      });
    }
  });

  group('both providers get the same guarantee', () {
    // The rule lives in the shared parse function, but that is exactly the
    // kind of thing T-0013 found copy-pasted per provider once already.
    final photo =
        PhotoInput(name: 'shelf_a.jpg', bytes: Uint8List.fromList([1, 2]));
    const answer = '{"items":[{"raw_title":"","platform_hint":"PS5"},'
        '{"raw_title":"Vex"}]}';

    final providers = <String, VisionProvider>{
      'anthropic': AnthropicVisionProvider(
        apiKey: 'k',
        client: MockClient((_) async => http.Response(
            jsonEncode({
              'content': [
                {'type': 'text', 'text': answer}
              ]
            }),
            200)),
      ),
      'ollama': OllamaVisionProvider(
        client: MockClient((_) async => http.Response(
            jsonEncode({
              'message': {'content': answer}
            }),
            200)),
      ),
      'openai-compatible': OpenAiCompatibleVisionProvider(
        baseUrl: 'https://example.test/v1',
        model: 'm',
        apiKey: 'k',
        client: MockClient((_) async => http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': answer}
                }
              ]
            }),
            200)),
      ),
    };

    providers.forEach((name, provider) {
      test('$name drops it and keeps the real read', () async {
        final analysis = await provider.analyze(photo);

        expect(analysis.items.single.rawTitle, 'Vex');
        expect(analysis.unreadable.single.sourcePhoto, 'shelf_a.jpg');
      });
    });
  });

  group('round-trip', () {
    test('a document written after the fix reads back identically', () {
      final written = ReviewDocument(
        version: 1,
        created: '2026-08-14T09:12:00.000Z',
        photos: ['shelf_a.jpg'],
        games: [
          ResolvedGame(
            detection: Detection(
              rawTitle: 'Z',
              mediaType: MediaType.disc,
              confidence: 1.0,
              sourcePhoto: 'shelf_a.jpg',
            ),
          ),
        ],
        unreadable: [UnreadSpineReport.titleless(sourcePhoto: 'shelf_a.jpg')],
      ).toJson();

      final reparsed = ReviewDocument.fromJson(
          jsonDecode(jsonEncode(written)) as Map<String, dynamic>);

      expect(reparsed.toJson(), written);
    });

    test('healing an old document is idempotent', () {
      // The healed document must not keep growing an unreadable entry per
      // load, which is what a rule applied on write instead of on read does.
      final legacy = _document([
        _item('', hint: 'PS5'),
        _item('COBALT CHIME'),
      ], unreadable: [
        {'source_photo': 'shelf_a.jpg', 'script': 'japanese', 'reason': null}
      ]);

      final once = ReviewDocument.fromJson(legacy).toJson();
      final twice = ReviewDocument.fromJson(
              jsonDecode(jsonEncode(once)) as Map<String, dynamic>)
          .toJson();

      expect(once['games'], hasLength(1));
      expect(once['unreadable'], hasLength(2));
      expect(twice, once);
    });

    test('the healed entry is a normal unreadable spine on re-read', () {
      final healed = ReviewDocument.fromJson(_document([_item(' ')])).toJson();
      final reparsed = ReviewDocument.fromJson(
          jsonDecode(jsonEncode(healed)) as Map<String, dynamic>);

      expect(reparsed.unreadable.single.sourcePhoto, 'shelf_a.jpg');
      expect(reparsed.unreadable.single.script, SpineScript.unknown);
    });

    test('a hand-typed manual entry with no title is dropped too', () {
      // Manual entries are added by hand-editing review.json (CLI) and carry
      // no source photo, so the spine that replaces one names none either.
      final doc = ReviewDocument.fromJson(_document([
        {'raw_title': '   ', 'source_photo': '', 'origin': 'manual'}
      ]));

      expect(doc.games, isEmpty);
      expect(doc.unreadable.single.sourcePhoto, '');
    });
  });

  group('nothing exportable is lost by the drop', () {
    // CsvExporter.canExport already refused a titleless row (T-0012) and
    // .xcoll needs an id it could never resolve, so no target could take it.
    test('the row could not have been exported anyway', () {
      final titleless = ResolvedGame(
        detection: Detection(
          rawTitle: '  ',
          mediaType: MediaType.disc,
          confidence: 1.0,
          sourcePhoto: 'shelf_a.jpg',
        ),
        status: ReviewStatus.approved,
      );

      expect(CsvExporter().canExport(titleless), isFalse);
    });
  });
}
