/// Guards the platform hint reaching the pipeline at all (T-0021).
///
/// Measured on the two real photos with qwen2.5vl:7b: the spines whose
/// branding the menu had no token for produced no hints at all while every
/// other row carried one, purely because the value menu listed
/// `SNES | PS1 | N64 | ...` and no Nintendo Switch. Three separate pieces have
/// to hold together for that fix to be
/// worth anything, and each is easy to undo alone:
///   1. the menu names the console, so there is a value to answer with;
///   2. the hint is read off the branding rather than recalled from what the
///      model knows -- without this the Switch 2 case of HARBOUR STARBURST
///      came back `N64`;
///   3. `platformIds` keys the spelling the model actually produces, or the
///      recovered hint is dropped again at the IGDB query.
///
/// The T-0014 escape and the T-0007 title rules are load-bearing neighbours
/// of edit (1) and (2); they are re-pinned here from this angle because a
/// wording change that quietly took either out would still pass everything
/// above.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

String _platformHintSpec() {
  final items =
      (jsonDecode(detectionJsonSchema) as Map<String, dynamic>)['items']
          as List<dynamic>;
  return (items.first as Map<String, dynamic>)['platform_hint'] as String;
}

({IgdbClient client, List<String> bodies}) _capturingIgdb() {
  final bodies = <String>[];
  final transport = MockClient((request) async {
    if (request.url.host == 'id.twitch.tv') {
      return http.Response(
          jsonEncode({'access_token': 'stub-token', 'expires_in': 3600}), 200);
    }
    bodies.add(request.body);
    return http.Response('[]', 200);
  });
  return (
    client:
        IgdbClient(clientId: 'stub', clientSecret: 'stub', client: transport),
    bodies: bodies,
  );
}

void main() {
  group('the value menu offers the console (T-0021)', () {
    test('names Nintendo Switch', () {
      // The whole cause of a hintless stack: the ellipsis did not stand in for
      // the missing value, the model simply answered nothing.
      expect(_platformHintSpec(), contains('SWITCH'));
    });

    test('keeps the PlayStation vocabulary that was already working', () {
      // 9 of 9 correct on the rows the menu already covered is the thing not
      // to trade away for the Switch ones.
      final spec = _platformHintSpec();
      expect(spec, contains('PS1'));
      expect(spec, contains('SNES'));
      expect(spec, contains('N64'));
    });

    test('still ends with T-0014\'s escape, phrased as an action', () {
      // Removing the escape made the model pick a menu entry instead of
      // declining -- "N64" for every Switch item. Adding a value to the
      // menu is exactly the edit that could rewrite this clause by accident.
      final spec = _platformHintSpec();
      expect(spec, contains('omit this field entirely if the platform is '
          'unclear'));
      expect(spec.toLowerCase(), isNot(contains('null')));
    });
  });

  group('the hint is read, not recalled (T-0021)', () {
    test('the rules forbid deriving the platform from the title', () {
      expect(detectionPromptRules, contains(RegExp(r'"platform_hint" is READ, '
          r'not recalled')));
      expect(detectionPromptRules, contains('console branding'));
      expect(
        detectionPromptRules,
        contains(RegExp(r'Never\s+derive it from the title or from which '
            r'console you know the game to be on')),
      );
    });

    test('and repeat the omit escape where the reader is told to read', () {
      // The rules and the schema have to agree about the unclear case;
      // "read it off the branding" without a way out is the T-0014 trap
      // rediscovered from the other side.
      expect(detectionPromptRules,
          contains('If no console branding is legible, omit the field.'));
    });

    test('title rules are untouched by it (T-0007)', () {
      // The new rule licenses reading a logo for the PLATFORM only. If that
      // ever generalizes to titles it re-opens the hallucination this
      // pipeline's most expensive bug was about.
      expect(
        detectionPromptRules,
        contains(RegExp(r'NEVER infer a title from box art, colour, shape, '
            r'logo, artwork style')),
      );
      expect(detectionPromptRules,
          contains('Only characters you can actually\n  read on the item '
              'count as evidence.'));
      expect(detectionPromptRules, contains('OMIT that item entirely'));
      // The platform licence must name the platform field, never titles.
      final platformRule = detectionPromptRules
          .split('\n- ')
          .firstWhere((rule) => rule.startsWith('"platform_hint"'));
      expect(platformRule.toLowerCase(), isNot(contains('raw_title')));
    });
  });

  group('platformIds keys the spelling the model produces (T-0021)', () {
    test('both the menu token and the printed branding map to Switch', () {
      // Measured: every row came back as "NINTENDO SWITCH", not "SWITCH".
      // Both consoles, because the same answer comes off both bands (T-0023).
      expect(platformIds['SWITCH'], {130, 508});
      expect(platformIds['NINTENDOSWITCH'], {130, 508});
    });

    Future<String> queryFor(String? hint) async {
      final igdb = _capturingIgdb();
      await igdb.client.search('Moonlight 3', platformHint: hint);
      return igdb.bodies.single;
    }

    test('a branding-spelled hint still constrains the platform', () async {
      expect(await queryFor('NINTENDO SWITCH'),
          contains('where platforms = (130,508);'));
    });

    test('lower case and stray spacing survive the lookup', () async {
      expect(await queryFor(' nintendo switch '),
          contains('where platforms = (130,508);'));
    });

    test('the short token behaves identically', () async {
      expect(await queryFor('SWITCH'), await queryFor('NINTENDO SWITCH'));
    });
  });

  group('the hint is read off THIS box, not the game (T-0026)', () {
    test('the rule reaches re-releases, not only new titles', () {
      // T-0021's wording closed the case for HARBOUR STARBURST and left
      // this one open: a large minority of the Switch cases answered PS2
      // because the titles are PlayStation-2-era classics.
      expect(detectionPromptRules, contains('re-releases of older games'));
      expect(
        detectionPromptRules,
        contains(RegExp(r'platform a game\s+originally shipped on is never '
            r'evidence about the box')),
      );
    });

    test('it says where on the item the branding is to be found', () {
      // The single highest-value sentence measured: naming the console icon
      // and the publisher wordmark separately roughly halved the wrong hints
      // and recovered spines no earlier run had read.
      expect(detectionPromptRules, contains('console icon'));
      expect(detectionPromptRules, contains(RegExp(
          r'publisher wordmark at the opposite end.*\n?.*is not console '
          r'branding')));
    });

    test('a manufacturer wordmark is refused as a platform', () {
      // What took the Switch cases from almost none correct to every row:
      // the model was reading the Nintendo logo and answering "NINTENDO".
      expect(detectionPromptRules,
          contains('Name the console, not the manufacturer'));
    });

    test('the re-release clause stays inside the platform bullet', () {
      // Promoting it to a bullet of its own measured worse (7 wrong -> 9),
      // and it must not drift out of the rule it qualifies.
      final platformRule = detectionPromptRules
          .split('\n- ')
          .firstWhere((rule) => rule.startsWith('"platform_hint"'));
      expect(platformRule, contains('re-releases of older games'));
      expect(platformRule, contains('Name the console, not the manufacturer'));
      // T-0007's boundary: this bullet licenses reading a logo for the
      // PLATFORM only.
      expect(platformRule.toLowerCase(), isNot(contains('raw_title')));
    });
  });

  group('the measured Nintendo answer resolves (T-0026)', () {
    Future<String> queryFor(String? hint) async {
      final igdb = _capturingIgdb();
      await igdb.client.search('Starweave Chronicles 3', platformHint: hint);
      return igdb.bodies.single;
    }

    test('SWITCH -- the string measured on both Switch photos -- resolves',
        () async {
      // The acceptance check for T-0026: after the prompt fix all 46 Switch
      // detections answered this exact token, so it has to survive the
      // uppercase-and-strip lookup and constrain the query.
      expect(await queryFor('SWITCH'), contains('where platforms = (130,508);'));
    });

    test('the bare manufacturer wordmark is deliberately left unmapped',
        () async {
      // "NINTENDO" is equally the branding of a NES, N64 or Wii case, so
      // keying it to Switch would filter an NES search down to nothing.
      // Unmapped costs only the filter -- the search still runs unconstrained
      // -- which is why T-0026 constrained the model instead of adding a key.
      expect(platformIds['NINTENDO'], isNull);
      expect(await queryFor('NINTENDO'), isNot(contains('where platforms')));
    });
  });
}
