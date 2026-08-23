/// Guards the anti-hallucination prompt (T-0007).
///
/// Two things are protected here:
///   1. the shared rules text actually reaches BOTH providers' wire format;
///   2. neither provider file grows its own copy of the instructions again
///      -- the duplication is what let the original bug apply to only one
///      model's prompt.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

final _photo = PhotoInput(name: 'shelf.jpg', bytes: Uint8List.fromList([1, 2]));

/// The source around [needle], so a failure can quote the shape that is there
/// instead of printing the whole file as its `Actual` (T-0324). The window is
/// flattened rather than the file: this scan matches against the source as
/// written, and only the quote needs to fit on a reporter line.
String _flattenedAround(String source, String needle) {
  final at = source.indexOf(needle);
  if (at < 0) return '(not present)';
  final from = at > 60 ? at - 60 : 0;
  var to = at + needle.length + 120;
  if (to > source.length) to = source.length;
  return '...${source.substring(from, to).replaceAll(RegExp(r'\s+'), ' ')}...';
}

/// Captures the outgoing request body instead of hitting a real endpoint.
({http.Client client, List<Map<String, dynamic>> sent}) _capturing(
    String responseBody) {
  final sent = <Map<String, dynamic>>[];
  final client = MockClient((request) async {
    sent.add(jsonDecode(request.body) as Map<String, dynamic>);
    return http.Response(responseBody, 200);
  });
  return (client: client, sent: sent);
}

const _anthropicOk = '{"content":[{"type":"text","text":"{\\"items\\":[]}"}]}';
const _ollamaOk = '{"message":{"content":"{\\"items\\":[]}"}}';

void main() {
  group('shared prompt const', () {
    test('states the anti-invention rules the bug was about', () {
      // Wording may be tuned; these are the load-bearing instructions.
      expect(detectionPromptRules, contains('OMIT that item entirely'));
      expect(detectionPromptRules, contains('Do NOT emit a guessed entry'));
      expect(
        detectionPromptRules,
        contains(RegExp(r'NEVER infer a title from box art, colour, shape, '
            r'logo')),
      );
      expect(detectionPromptRules,
          contains(RegExp(r'"confidence" expresses how clearly you could READ')));
      // The partial-text rule predates T-0007 and must survive it.
      expect(detectionPromptRules, contains('partial text'));
      // Japanese: transcribe, never translate or romanize from memory.
      expect(detectionPromptRules, contains('Japanese titles'));
      expect(detectionPromptRules, contains('never romanize a title from '
          'memory'));
    });

    test('asks for an unreadable spine to be reported, not titled (T-0011)',
        () {
      // The omit rule and the report rule have to coexist: reporting a
      // spine must never read as permission to name it.
      expect(detectionPromptRules, contains('"unreadable"'));
      expect(detectionPromptRules, contains('Report it, do not title it'));
      // The escalation trigger is the entry, so the model has to be told
      // what to put in it.
      expect(detectionPromptRules, contains('which script'));
    });

    test('the unreadable array carries no title field to guess into', () {
      final schema = jsonDecode(detectionJsonSchema) as Map<String, dynamic>;
      final unreadable = schema['unreadable'] as List<dynamic>;

      expect(unreadable, hasLength(1));
      final entry = unreadable.single as Map<String, dynamic>;
      expect(entry.keys, unorderedEquals(<String>['script', 'reason']));
      expect(entry['script'], contains('japanese'));
      // "unknown" is itself the way out, unlike the platform menu -- there
      // is nothing to invent when you cannot tell.
      expect(entry['script'], contains('unknown'));
      for (final key in entry.keys) {
        expect(key, isNot(anyOf('raw_title', 'title', 'guess')));
      }
    });

    test('neither unreadable value is a ready-made answer (T-0028)', () {
      // The measured provocation: this entry read `"script": "japanese |
      // latin | unknown"` / `"reason": "... e.g. 'characters too small'"`,
      // and the model returned it verbatim three times per photo on all
      // three photos. Both halves have to describe what to report rather
      // than hand over something copyable.
      final entry = ((jsonDecode(detectionJsonSchema)
          as Map<String, dynamic>)['unreadable'] as List<dynamic>)
          .single as Map<String, dynamic>;

      expect(entry['reason'], isNot(contains('e.g.')),
          reason: 'a quoted example reason is copied back as the answer');
      expect(entry['reason'], isNot(contains("'")));
      // A bare pipe menu is copyable as-is; the platform field earns its
      // menu by pairing it with an action, this one does not have one.
      expect(entry['script'], isNot(contains('|')));
      // Copying either value verbatim must not yield a usable script.
      expect(SpineScript.parse(entry['script'] as String),
          SpineScript.unknown);
    });

    test('the rules give the model a way to report none (T-0028)', () {
      // Removing the copied example is only half of it: with no visible way
      // to say "nothing", the array is a section waiting to be filled.
      expect(detectionPromptRules, contains('"unreadable": []'));
      expect(detectionPromptRules, contains('not a failure'));
      // Padding it is what made the T-0011 escalation fire on every photo.
      expect(detectionPromptRules, contains('not copies of each other'));
    });

    test('the Japanese rule is not buried under the branding prose (T-0034)',
        () {
      // Measured, not taste. T-0026 landed 14 lines of console-branding prose
      // directly after this rule, and at 1200x900 -- where the Japanese
      // Switch 2 spines are illegible rather than merely untranslatable -- the
      // model began naming them: 0 of 4 runs invented at T-0021, 4 of 4 at
      // T-0026. Moving the bullet below "platform_hint" and "confidence",
      // without changing a word of it, restored 0 of 4. Nothing else in this
      // file can see that difference: every assertion here still passes with
      // the bullets in the order that invents.
      final japanese = detectionPromptRules.indexOf('Japanese titles');
      final platform =
          detectionPromptRules.indexOf('"platform_hint" is READ');
      final confidence =
          detectionPromptRules.indexOf('"confidence" expresses');
      final unreadable =
          detectionPromptRules.indexOf('add one entry to');

      expect([japanese, platform, confidence, unreadable],
          everyElement(greaterThanOrEqualTo(0)));
      expect(japanese, greaterThan(platform),
          reason: 'the branding prose must not sit between the Japanese rule '
              'and the items it governs');
      expect(japanese, greaterThan(confidence));
      expect(japanese, lessThan(unreadable),
          reason: 'an unread Japanese spine is reported, never titled');
    });

    test('the platform bullet stays ahead of "confidence" (T-0034, T-0033)',
        () {
      // The assertions above pass with the platform bullet anywhere below the
      // Japanese one, and both places below it were measured worse: at the
      // very end, hi-res re-releases fell back to `PS2` and hints went
      // the correct-hint figure fell; one place later, after `confidence`, 1 of 4
  // low-res
      // runs invented again. T-0033 measured what the position buys when it
      // is right -- on one 1200x900 photograph the same 2990 characters
      // answer `SWITCH` on every row here and `NINTENDO` on almost every row in
  // T-0028's
      // order, which is a raft of duplicate review rows across the five photos.
      expect(detectionPromptRules.indexOf('"platform_hint" is READ'),
          lessThan(detectionPromptRules.indexOf('"confidence" expresses')));
    });

    test('the rules keep every bullet a re-sort could drop (T-0034)', () {
      // The order above is only safe to assert if nothing fell out of the list
      // while it was being reordered.
      final bullets = detectionPromptRules
          .split('\n')
          .where((line) => line.startsWith('- '))
          .length;
      expect(bullets, 7);
    });

    test('full prompt is rules + output contract', () {
      expect(detectionPrompt, contains(detectionPromptRules));
      expect(detectionPrompt, contains(detectionJsonSchema));
      expect(detectionPrompt, contains('STRICT JSON only'));
    });
  });

  group('output schema stops provoking the word "null" (T-0014)', () {
    // The schema is handed to the model as an example of the answer, so it
    // has to parse as the thing it is asking for.
    late List<dynamic> items;

    setUp(() {
      items = (jsonDecode(detectionJsonSchema) as Map<String, dynamic>)['items']
          as List<dynamic>;
    });

    test('never shows a quoted null as a field value', () {
      // The exact provocation: `"platform_hint": "SNES | ... | null if
      // unclear"` taught the model to answer with the word in quotes.
      for (final item in items.cast<Map<String, dynamic>>()) {
        for (final entry in item.entries) {
          final value = entry.value;
          if (value is! String) continue;
          expect(value.toLowerCase(), isNot(contains('null')),
              reason: '${entry.key} still describes absence inside a string');
        }
      }
    });

    test('gives the unclear case an explicit way out of the value menu', () {
      // Measured on the real photos: with the menu but no escape branch the
      // model stops saying "I cannot tell" and picks a menu entry instead
      // (it answered "N64" for every spine of one photograph). The escape must
      // name an action -- omitting the field -- not another quoted word.
      final hint = (items.first as Map<String, dynamic>)['platform_hint'];

      expect(hint, isA<String>());
      expect(hint, contains('omit this field'));
      expect(hint, contains('unclear'));
    });

    test('the menu offers one Switch and no second one (T-0074)', () {
      // Measured, not taste. Adding `SWITCH2` beside `SWITCH` here is the
      // obvious way to collect the auto-matches a Switch 2 hint is worth,
      // and it was measured alone and behind four rules written to restrain
      // it: the model answers the new token for whole photos off Switch 1
      // bands (false hints schema-only, more with a rule beside it), and one
      // of those rules also brought back invented titles at 1200x900 on 3 runs
      // of 4. The menu is a vocabulary this model copies verbatim -- see
      // [detectionPromptRules].
      final hint = ((jsonDecode(detectionJsonSchema)
              as Map<String, dynamic>)['items'] as List<dynamic>)
          .first as Map<String, dynamic>;
      final tokens = (hint['platform_hint'] as String)
          .split('|')
          .map((t) => t.trim().toUpperCase().replaceAll(' ', ''))
          .where((t) => t.startsWith('SWITCH'));

      expect(tokens, ['SWITCH']);
    });

    test('still names the platform vocabulary', () {
      // Dropping the examples would cost hint quality, which is the thing
      // T-0008 measures.
      expect(detectionJsonSchema, contains('SNES'));
      expect(detectionJsonSchema, contains('PS1'));
    });

    test('the unreadable channel does not weaken the escape (T-0011)', () {
      // Adding a second array is exactly the kind of edit that quietly
      // rewrites the neighbouring line. The escape clause is measured
      // behaviour, not wording taste -- see the doc comment on the const.
      expect(detectionJsonSchema, contains('omit this field entirely if the '
          'platform is unclear'));
    });

    // `notes` is in this list despite being answered `""` on every row of
    // both control sets: deleting the line makes one hi-res photo report 2
    // phantom unreadable spines, 5 of 5 runs taken after `ollama stop`
    // (T-0093, numbers on the const). It is pinned here so the next reader who
    // notices the empty field finds the measurement before repeating it.
    test('keeps the fields the parser reads', () {
      final first = items.first as Map<String, dynamic>;
      expect(
        first.keys,
        containsAll(<String>[
          'raw_title',
          'platform_hint',
          'media_type',
          'confidence',
          'notes',
        ]),
      );
      expect(first['media_type'], contains('cartridge | disc | unknown'));
    });
  });

  group('providers send the shared rules', () {
    test('AnthropicVisionProvider puts them in the system prompt', () async {
      final capture = _capturing(_anthropicOk);
      await AnthropicVisionProvider(apiKey: 'k', client: capture.client)
          .analyze(_photo);

      expect(capture.sent, hasLength(1));
      expect(capture.sent.single['system'], contains(detectionPromptRules));
    });

    test('OllamaVisionProvider puts them in the user message', () async {
      final capture = _capturing(_ollamaOk);
      await OllamaVisionProvider(client: capture.client).analyze(_photo);

      expect(capture.sent, hasLength(1));
      final messages = capture.sent.single['messages'] as List<dynamic>;
      expect(messages.single['content'], contains(detectionPromptRules));
    });
  });

  group('no duplicated instruction text', () {
    // Relative to the package root, which is `dart test`'s working directory.
    const providerFiles = [
      'lib/src/providers/vision.dart',
      'lib/src/providers/ollama_vision.dart',
    ];

    test('the rules are declared exactly once, in vision.dart', () {
      final declarations = providerFiles
          .where((path) =>
              File(path).readAsStringSync().contains('const detectionPromptRules'))
          .toList();
      expect(declarations, ['lib/src/providers/vision.dart']);
    });

    test('ollama_vision.dart carries no prompt text of its own', () {
      const path = 'lib/src/providers/ollama_vision.dart';
      final source = File(path).readAsStringSync();

      // fail() rather than expect(): a matcher against `source` prints the
      // whole file as its Actual and buries the one sentence that says what
      // is wrong (T-0324). Nothing here is flattened -- none of the three
      // shapes below can be broken by a rewrap, and the line number is worth
      // more than the tolerance would be.
      if (!source.contains('detectionPrompt')) {
        fail('$path: a source scan found no detectionPrompt, so the Ollama '
            'provider names no shared const and its request is built from '
            'text of its own.');
      }
      // The old duplicate was a multi-line string literal; the file needs
      // none of its own. (Doc comments are free to mention anything.)
      for (final duplicate in const ["'''", 'You identify video games']) {
        final at = source.indexOf(duplicate);
        if (at < 0) continue;
        final line = '\n'.allMatches(source.substring(0, at)).length + 1;
        fail('$path line $line: a source scan found `$duplicate`, which is '
            'prompt text carried in this file rather than composed from the '
            'const in vision.dart. What is there:\n  '
            '${_flattenedAround(source, duplicate)}');
      }
    });
  });
}
