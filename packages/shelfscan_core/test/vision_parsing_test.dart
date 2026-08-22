/// Detection parsing for both vision providers.
///
/// The prompt asks for strict JSON, but a model is free to ignore that, so
/// the parsing side is what actually has to hold. "Unreadable spine ->
/// omit the item" (T-0007) also means an empty `items` list is a normal,
/// successful answer -- never an error.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

final _photo = PhotoInput(name: 'shelf.jpg', bytes: Uint8List.fromList([1, 2]));

/// Anthropic returns the model text inside a content block.
http.Client _anthropicReturning(String modelText) => MockClient((_) async =>
    http.Response(
        jsonEncode({
          'content': [
            {'type': 'text', 'text': modelText}
          ]
        }),
        200));

/// Ollama returns the model text as `message.content`.
http.Client _ollamaReturning(String modelText) => MockClient((_) async =>
    http.Response(
        jsonEncode({
          'message': {'content': modelText}
        }),
        200));

/// The OpenAI-compatible family returns it as `choices[0].message.content`.
http.Client _openAiReturning(String modelText) => MockClient((_) async =>
    http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {'content': modelText}
            }
          ]
        }),
        200));

Future<PhotoAnalysis> _anthropic(String modelText) =>
    AnthropicVisionProvider(apiKey: 'k', client: _anthropicReturning(modelText))
        .analyze(_photo);

Future<PhotoAnalysis> _ollama(String modelText) =>
    OllamaVisionProvider(client: _ollamaReturning(modelText)).analyze(_photo);

Future<PhotoAnalysis> _openAi(String modelText) =>
    OpenAiCompatibleVisionProvider(
      baseUrl: 'https://example.test/v1',
      model: 'm',
      apiKey: 'k',
      client: _openAiReturning(modelText),
    ).analyze(_photo);

const _fullItem = '''
{"items":[{"raw_title":"Vellum Compass","platform_hint":"SNES",
"media_type":"cartridge","confidence":0.91,"notes":"label worn"}]}''';

/// Everything except raw_title is optional in the schema.
const _minimalItem = '{"items":[{"raw_title":"Vex"}]}';

void main() {
  // Same expectations on both sides: the providers differ only in transport.
  final providers = <String, Future<PhotoAnalysis> Function(String)>{
    'anthropic': _anthropic,
    'ollama': _ollama,
    'openai-compatible': _openAi,
  };

  providers.forEach((name, analyze) {
    group('$name provider', () {
      test('parses a full item', () async {
        final detections = (await analyze(_fullItem)).items;

        expect(detections, hasLength(1));
        final d = detections.single;
        expect(d.rawTitle, 'Vellum Compass');
        expect(d.platformHint, 'SNES');
        expect(d.mediaType, MediaType.cartridge);
        expect(d.confidence, closeTo(0.91, 1e-9));
        expect(d.notes, 'label worn');
        // The provider stamps the photo name; the model never sends it.
        expect(d.sourcePhoto, 'shelf.jpg');
      });

      test('empty items is a valid answer, not an error', () async {
        expect((await analyze('{"items":[]}')).items, isEmpty);
      });

      test('missing items key yields no detections', () async {
        expect((await analyze('{}')).items, isEmpty);
      });

      test('missing optional fields fall back to defaults', () async {
        final d = (await analyze(_minimalItem)).items.single;

        expect(d.rawTitle, 'Vex');
        expect(d.platformHint, isNull);
        expect(d.mediaType, MediaType.unknown);
        expect(d.confidence, 0.0);
        expect(d.notes, isNull);
      });

      test('the literal string "null" is not a platform (T-0014)', () async {
        // What qwen2.5vl:7b actually answered for most of a low-res run.
        final d = (await analyze('{"items":[{"raw_title":"Vex",'
                '"platform_hint":"null","notes":"null"}]}'))
            .items
            .single;

        expect(d.platformHint, isNull);
        expect(d.notes, isNull);
      });

      test('unknown media_type degrades to unknown', () async {
        final d = (await analyze(
                '{"items":[{"raw_title":"Vex","media_type":"vhs"}]}'))
            .items
            .single;

        expect(d.mediaType, MediaType.unknown);
      });

      // ---- unreadable spines (T-0011) ------------------------------- //

      test('an absent "unreadable" key means none were reported', () async {
        expect((await analyze(_fullItem)).unreadable, isEmpty);
      });

      test('unreadable entries parse and are stamped with the photo',
          () async {
        final analysis = await analyze('{"items":[],"unreadable":['
            '{"script":"japanese","reason":"kanji too small"},'
            '{"script":"latin","reason":"glare"}]}');

        expect(analysis.items, isEmpty);
        expect(analysis.unreadable, hasLength(2));
        expect(analysis.unreadable.first.script, SpineScript.japanese);
        expect(analysis.unreadable.first.reason, 'kanji too small');
        // The model never sends it; the parser stamps it, exactly like it
        // does for detections.
        expect(analysis.unreadable.first.sourcePhoto, 'shelf.jpg');
        expect(analysis.unreadable.last.script, SpineScript.latin);
      });

      test('an unreadable entry never becomes an item', () async {
        // The failure this guards against is the tempting "shortcut" of
        // turning a reported unreadable spine into a low-confidence
        // detection -- that is the T-0007 invention bug wearing a hat.
        final analysis = await analyze('{"items":[],"unreadable":'
            '[{"script":"japanese","reason":"cannot read"}]}');

        expect(analysis.items, isEmpty);
      });

      test('an unknown script degrades to unknown instead of throwing',
          () async {
        final analysis = await analyze(
            '{"unreadable":[{"script":"hangul","reason":"blurred"}]}');

        expect(analysis.unreadable.single.script, SpineScript.unknown);
      });

      test('a textual placeholder reason reads as no reason', () async {
        final analysis =
            await analyze('{"unreadable":[{"script":"japanese",'
                '"reason":"none"}]}');

        expect(analysis.unreadable.single.reason, isNull);
      });

      // ---- response envelope (T-0013) ------------------------------- //

      test('surrounding whitespace is tolerated', () async {
        final analysis = await analyze('\n\n  $_minimalItem \n ');

        expect(analysis.items.single.rawTitle, 'Vex');
      });

      test('a backtick in a title survives', () async {
        // The replaced global strip of ``` deleted these characters wherever
        // they appeared, title included; only a leading/trailing fence may go.
        const title = r'``` Weird ` Title ```';
        final analysis =
            await analyze('{"items":[{"raw_title":"$title"}]}');

        expect(analysis.items.single.rawTitle, title);
      });

      test('a fenced payload keeps the backticks inside its title', () async {
        const title = r'a ``` b';
        final analysis =
            await analyze('```json\n{"items":[{"raw_title":"$title"}]}\n```');

        expect(analysis.items.single.rawTitle, title);
      });

      test('a payload that is not JSON fails', () async {
        expect(analyze('I count three games on this shelf.'),
            throwsA(isA<FormatException>()));
      });
    });
  });

  group('code fences', () {
    const fenced = '```json\n{"items":[{"raw_title":"Vex"}]}\n```';

    test('anthropic strips them', () async {
      // Documented behaviour: the cloud model wraps JSON despite the prompt.
      expect((await _anthropic(fenced)).items.single.rawTitle, 'Vex');
    });

    test('ollama strips them too', () async {
      // Was the inverse assertion until T-0013: Ollama is called with
      // `format: json`, so it decoded `message.content` directly and threw
      // FormatException on a fence the Anthropic provider absorbed.
      expect((await _ollama(fenced)).items.single.rawTitle, 'Vex');
    });

    test('the openai-compatible family strips them too', () async {
      // This family is asked for no `response_format`, so a fence is the
      // expected shape rather than an accident (T-0006).
      expect((await _openAi(fenced)).items.single.rawTitle, 'Vex');
    });
  });
}
