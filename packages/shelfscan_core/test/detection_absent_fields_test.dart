/// Guards the "absent means absent" normalization (T-0014).
///
/// The vision prompt used to describe `platform_hint` as
/// `"SNES | PS1 | ... | null if unclear"`, and qwen2.5vl:7b answered with
/// the four-character string "null" -- on most detections of the
/// post-T-0007 run. That string reached the review UI and the CSV export as
/// a platform name, and it made "no hint at all" indistinguishable from "a
/// hint was actually read", which is a failure class the T-0008 measurement
/// has to count.
///
/// Two things are protected here:
///   1. `Detection.fromJson` -- the single choke point shared by both
///      providers and by every read of an existing `review.json` -- maps the
///      textual "nothing here" markers to Dart null, whole-value only;
///   2. IGDB query building does not change as a result: it was already
///      unaffected, by luck rather than by design, and this pins that down.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

Detection _parse({Object? platformHint, Object? notes}) =>
    Detection.fromJson(<String, dynamic>{
      'raw_title': 'Vex',
      'platform_hint': platformHint,
      'media_type': 'disc',
      'confidence': 1.0,
      'source_photo': 'shelf_a.jpg',
      'notes': notes,
    });

/// Captures the IGDB query body while running the real client code.
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
  group('Detection.fromJson treats textual placeholders as absent', () {
    // Exactly the markers the brief names, plus casing and padding variants.
    const absent = [
      'null',
      'NULL',
      'Null',
      'none',
      'NONE',
      'unknown',
      'Unknown',
      'UNKNOWN',
      'n/a',
      'N/A',
      'N/a',
      '-',
      '',
      '   ',
      '  null  ',
      '\tUnknown\n',
    ];

    for (final marker in absent) {
      test('platform_hint ${jsonEncode(marker)} -> null', () {
        expect(_parse(platformHint: marker).platformHint, isNull);
      });

      test('notes ${jsonEncode(marker)} -> null', () {
        expect(_parse(notes: marker).notes, isNull);
      });
    }

    test('JSON null stays null', () {
      final d = _parse(platformHint: null, notes: null);
      expect(d.platformHint, isNull);
      expect(d.notes, isNull);
    });

    test('a non-string value degrades to null instead of throwing', () {
      // A model that answers `"platform_hint": 0` used to crash the parse
      // with a cast error and lose the whole photo.
      final d = _parse(platformHint: 0, notes: <String>['a']);
      expect(d.platformHint, isNull);
      expect(d.notes, isNull);
    });
  });

  group('a real value that merely contains a marker word survives', () {
    // Whole-value match, never substring: these are all legitimate reads.
    const kept = <String, String>{
      'Unknown Pleasures': 'Unknown Pleasures',
      'None Shall Pass': 'None Shall Pass',
      'Nullify': 'Nullify',
      'Mega-CD': 'Mega-CD',
      'N/A Gear': 'N/A Gear',
      'PS1': 'PS1',
      // Padding is stripped, the value itself is untouched.
      '  SNES  ': 'SNES',
    };

    kept.forEach((raw, expected) {
      test('platform_hint ${jsonEncode(raw)} is kept', () {
        expect(_parse(platformHint: raw).platformHint, expected);
      });

      test('notes ${jsonEncode(raw)} is kept', () {
        expect(_parse(notes: raw).notes, expected);
      });
    });
  });

  group('regression: an existing review.json written before the fix', () {
    // Documents already on disk carry the string; loading them heals them,
    // which is why the normalization lives at the model boundary.
    final legacy = <String, dynamic>{
      'version': 1,
      'created': '2026-08-13T17:25:31.019438Z',
      'photos': ['shelf_a.jpg'],
      'games': [
        {
          'detection': {
            'raw_title': 'COBALT CHIME',
            'platform_hint': 'null',
            'media_type': 'cartridge',
            'confidence': 1.0,
            'source_photo': 'shelf_a.jpg',
            'notes': 'null',
          },
          'best': null,
          'candidates': <dynamic>[],
          'status': 'pending',
        },
      ],
    };

    test('parses the string "null" to Dart null', () {
      final doc = ReviewDocument.fromJson(
          jsonDecode(jsonEncode(legacy)) as Map<String, dynamic>);
      final detection = doc.games.single.detection;

      expect(detection.rawTitle, 'COBALT CHIME');
      expect(detection.platformHint, isNull);
      expect(detection.notes, isNull);
    });

    test('rewriting it emits JSON null, not the word', () {
      final doc = ReviewDocument.fromJson(
          jsonDecode(jsonEncode(legacy)) as Map<String, dynamic>);
      final written = doc.games.single.detection.toJson();

      expect(written['platform_hint'], isNull);
      expect(written['notes'], isNull);
      expect(jsonEncode(written), isNot(contains('"null"')));
    });
  });

  group('round-trip', () {
    for (final entry in <String, Detection>{
      'present hint': Detection(
        rawTitle: 'Vellum Compass',
        platformHint: 'SNES',
        mediaType: MediaType.cartridge,
        confidence: 0.91,
        sourcePhoto: 'shelf_a.jpg',
        notes: 'label worn',
      ),
      'absent hint': Detection(
        rawTitle: 'Vex',
        mediaType: MediaType.disc,
        confidence: 0.4,
        sourcePhoto: 'shelf_b.jpg',
      ),
    }.entries) {
      test('toJson -> fromJson is stable for a ${entry.key}', () {
        final original = entry.value;
        final once = original.toJson();
        final reparsed = Detection.fromJson(
            jsonDecode(jsonEncode(once)) as Map<String, dynamic>);

        expect(reparsed.platformHint, original.platformHint);
        expect(reparsed.notes, original.notes);
        expect(reparsed.rawTitle, original.rawTitle);
        expect(reparsed.mediaType, original.mediaType);
        expect(reparsed.confidence, original.confidence);
        expect(reparsed.sourcePhoto, original.sourcePhoto);
        // A second pass changes nothing: the normalization is idempotent.
        expect(reparsed.toJson(), once);
      });
    }
  });

  group('IgdbClient.search is unchanged by the fix', () {
    // Before T-0014 the hint arrived as "null", was uppercased to "NULL",
    // missed `platformIds`, and the platform filter was silently dropped.
    // A genuine absence must produce exactly the same query -- confirmed
    // rather than assumed, because the fix changes what search() receives.
    Future<String> queryFor(String? hint) async {
      final igdb = _capturingIgdb();
      await igdb.client.search('Vex', platformHint: hint);
      return igdb.bodies.single;
    }

    test('absent hint builds the same query as the string "null"', () async {
      expect(await queryFor(null), await queryFor('null'));
    });

    test('and that query carries no platform filter', () async {
      final body = await queryFor(null);
      expect(body, isNot(contains('where platforms')));
      expect(body, contains('search "Vex";'));
    });

    test('a real hint still constrains the platform', () async {
      expect(await queryFor('SNES'), contains('where platforms = (19);'));
    });
  });
}
