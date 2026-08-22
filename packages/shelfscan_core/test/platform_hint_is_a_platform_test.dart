/// Guards the question nothing asked: is this `platform_hint` a platform at
/// all (T-0084)?
///
/// `Detection.fromJson` normalized only the absence markers (T-0014), so every
/// other string survived into the review document, the resolver and the CSV
/// platform column. Measured at temperature 0 during T-0074, the model answered
/// the schema line itself -- `SWITCH2 | SWITCH` on every row of one photo,
/// `SWITCH2 | N64 -- omit this field entirely if the platform is unclear` on
/// most of another -- and at 0.8 the shipped prompt does it too (T-0053). The
/// row then resolves to nothing, reaches review "unmatched", and CSV publishes
/// the prompt line as the item's platform.
///
/// The hard half is what must NOT be rejected. `platformIds` is a lookup and
/// not a vocabulary: T-0026 left `NINTENDO` unmapped deliberately, and T-0002's
/// gate matches an unmapped hint against the platform name IGDB returns. So the
/// three groups below are one test each way -- the echoes go, and everything
/// the pipeline has ever really read stays.
@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';

import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

String _schemaHintLine() {
  final items =
      (jsonDecode(detectionJsonSchema) as Map<String, dynamic>)['items']
          as List<dynamic>;
  return (items.first as Map<String, dynamic>)['platform_hint'] as String;
}

/// The two strings T-0074 measured, and the whole schema line T-0053 measured
/// at 0.8 -- the last read out of [detectionJsonSchema] rather than retyped,
/// so a re-worded schema is tested as it ships.
final _echoes = <String>[
  'SWITCH2 | SWITCH',
  'SWITCH2 | N64 -- omit this field entirely if the platform is unclear',
  _schemaHintLine(),
];

Detection _parse(String? hint, {String? discarded}) =>
    Detection.fromJson(<String, dynamic>{
      'raw_title': 'HARBOUR STARBURST',
      'platform_hint': hint,
      'media_type': 'cartridge',
      'confidence': 1.0,
      'source_photo': 'shelf-1.jpg',
      if (discarded != null) 'discarded_platform_hint': discarded,
    });

/// A stand-in for the local Ollama server, answering one item whose
/// `platform_hint` is [hint].
class _StubVision {
  _StubVision(this._server, String hint) {
    _server.listen((request) async {
      await request.drain<void>();
      request.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'message': {
            'content': jsonEncode({
              'items': [
                {
                  'raw_title': 'HARBOUR STARBURST',
                  'platform_hint': hint,
                  'media_type': 'cartridge',
                },
              ],
            }),
          },
        }));
      await request.response.close();
    });
  }

  static Future<_StubVision> start(String hint) async => _StubVision(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0), hint);

  final HttpServer _server;

  String get url => 'http://127.0.0.1:${_server.port}';

  Future<void> stop() => _server.close(force: true);
}

void main() {
  group('a line of our own prompt is not a platform', () {
    for (final echo in _echoes) {
      test('${jsonEncode(echo)} never reaches platformHint', () {
        expect(_parse(echo).platformHint, isNull);
      });

      test('${jsonEncode(echo)} is kept where a human can see it', () {
        // Null on its own would be the silent drop decision 0012 keeps filing
        // bugs about: the row would look like a spine whose branding was
        // illegible, which is a different finding.
        expect(_parse(echo).discardedPlatformHint, echo);
      });

      test('${jsonEncode(echo)} is refused with a reason', () {
        expect(platformHintRejection(echo), isNotNull);
      });
    }

    test('the CSV platform column is empty rather than plausible', () {
      // The whole visible symptom: an unmatched row publishes the hint as the
      // item's platform (`CsvExporter.render`), so the human reads a column
      // that looks like an answer.
      final csv = CsvExporter().render([
        ResolvedGame(
            detection: _parse(_echoes.first), status: ReviewStatus.approved),
      ]);
      expect(csv, isNot(contains('SWITCH2')));
      expect(csv.split('\r\n')[1], startsWith('HARBOUR STARBURST,,'));
    });
  });

  group('a platform we do not happen to map still reaches the resolver', () {
    // The criterion that makes this non-trivial. "NINTENDO" is unmapped on
    // purpose (T-0026: the same wordmark is on an NES, an N64 and a Wii case)
    // and almost every low-res row answered it under the T-0028 bullet order,
    // which is one prompt edit away.
    test('NINTENDO is unmapped', () {
      expect(platformIds['NINTENDO'], isNull);
    });

    test('and survives the parse unchanged', () {
      expect(_parse('NINTENDO').platformHint, 'NINTENDO');
      expect(_parse('NINTENDO').discardedPlatformHint, isNull);
    });

    test('and still narrows the T-0002 gate by platform name', () {
      // What the hint is worth while unmapped: it sinks the wrong-console
      // candidate that IGDB's ordering would otherwise make `best`.
      expect(
          platformAgreement('NINTENDO',
              platformId: 130, platformName: 'Nintendo Switch'),
          PlatformAgreement.match);
      expect(
          platformAgreement('NINTENDO',
              platformId: 508, platformName: 'Nintendo Switch 2'),
          PlatformAgreement.match);
      expect(
          platformAgreement('NINTENDO',
              platformId: 169, platformName: 'Xbox Series X|S'),
          PlatformAgreement.mismatch);
    });
  });

  // **The table, not a shelf (T-0260).** This enumerated the platform strings
  // the control sets happened to answer, read out of the manifest's `hints`
  // key. An exhaustive set of the platforms answered across a private
  // collection is that collection's platform mix with no count needed, so the
  // key is gone; `platformIds` is the menu of every platform string this
  // project can emit, it is a superset of whatever a shelf answers, and it
  // names nobody's possessions. What is given up with the key is in that
  // report.
  group('every platform string platformIds spells survives', () {
    for (final key in platformIds.keys) {
      test('$key, the spelling platformIds keys', () {
        expect(platformHintRejection(key), isNull);
        expect(_parse(key).platformHint, key);
      });
    }

    test('the enumeration is not empty', () {
      // The loop above is vacuous against an emptied table, which is what the
      // `hints` key's own isNotEmpty guard used to catch one file away. Both
      // names are positional -- first and last key of the table as written, 36
      // keys apart -- so neither is here because a shelf answered it.
      expect(platformIds, hasLength(greaterThanOrEqualTo(30)));
      expect(platformIds.keys, containsAll(['NES', 'PLAYSTATIONVITA']));
    });
  });

  group('a plausible platform nobody has read yet survives', () {
    // Nothing here has ever come out of a run. They are the near misses of the
    // three prongs: a real platform name carrying a pipe, the longest name the
    // resolver's fallback can match against, and the branding spellings the
    // model produced before T-0053 pinned the sampling.
    const unseen = [
      'Xbox Series X|S',
      'XBOX SERIES X|S',
      'Super Nintendo Entertainment System',
      'NINTENDO SWITCH 2',
      'PlayStation Vita',
      'Sega Mega Drive',
      'Game Boy Advance',
      'Mega-CD',
    ];

    for (final hint in unseen) {
      test('${jsonEncode(hint)} is kept', () {
        expect(platformHintRejection(hint), isNull);
        expect(_parse(hint).platformHint, hint);
      });
    }
  });

  group('an existing review.json heals on load', () {
    final legacy = <String, dynamic>{
      'version': 1,
      'created': '2026-08-15T09:11:02.000Z',
      'photos': ['shelf-2.jpg'],
      'games': [
        {
          'detection': {
            'raw_title': 'そらのは 真',
            'platform_hint':
                'SWITCH2 | N64 -- omit this field entirely if the platform '
                    'is unclear',
            'media_type': 'cartridge',
            'confidence': 1.0,
            'source_photo': 'shelf-2.jpg',
          },
          'best': null,
          'candidates': <dynamic>[],
          'status': 'pending',
        },
      ],
    };

    ReviewDocument load() => ReviewDocument.fromJson(
        jsonDecode(jsonEncode(legacy)) as Map<String, dynamic>);

    test('the platform column of a document already written is emptied', () {
      expect(load().games.single.detection.platformHint, isNull);
    });

    test('and what it held is still in the document', () {
      expect(load().games.single.detection.discardedPlatformHint,
          contains('SWITCH2'));
    });

    test('rewriting it moves nothing a second time', () {
      final once = load().games.single.detection.toJson();
      final twice = Detection.fromJson(
              jsonDecode(jsonEncode(once)) as Map<String, dynamic>)
          .toJson();
      expect(twice, once);
      expect(once['platform_hint'], isNull);
    });
  });

  group('a whole scan says what it refused', () {
    // End to end through the CLI, because the claim is about what a human is
    // told, and the print is the only part of this that no unit test reaches.
    // The vision provider is a loopback stub answering the echo; nothing here
    // touches a network, a model or IGDB.
    test('the summary names the string, the count and the reason', () async {
      final stub = await _StubVision.start('SWITCH2 | SWITCH');
      addTearDown(stub.stop);
      final photos =
          Directory.systemTemp.createTempSync('shelfscan_refused_hint_');
      addTearDown(() {
        try {
          photos.deleteSync(recursive: true);
        } on FileSystemException {
          // The Windows errno 145 race the path suites document.
        }
      });
      File('${photos.path}${Platform.pathSeparator}shelf_a.jpg')
          .writeAsBytesSync([0xff, 0xd8, 0xff]);
      final out = '${photos.path}${Platform.pathSeparator}out.review.json';

      final run = await Process.run(
        Platform.resolvedExecutable,
        ['run', 'bin/shelfscan.dart', 'scan', photos.path, '-o', out],
        environment: {
          'IGDB_CLIENT_ID': '',
          'IGDB_CLIENT_SECRET': '',
          'SHELFSCAN_OLLAMA_FALLBACK_MODEL': '',
          'SHELFSCAN_OLLAMA_URL': stub.url,
        },
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );

      expect(run.stdout, contains('Platform hints refused: 1'));
      expect(run.stdout, contains('1 x "SWITCH2 | SWITCH"'));
      expect(run.stdout, contains('menu'));

      final doc = ReviewDocument.parse(File(out).readAsStringSync());
      expect(doc.games.single.detection.platformHint, isNull);
      expect(doc.games.single.detection.discardedPlatformHint,
          'SWITCH2 | SWITCH');
    });
  });

  group('round-trip', () {
    test('a hint the check keeps is untouched by it', () {
      final original = Detection(
        rawTitle: 'Vellum Compass',
        platformHint: 'SNES',
        mediaType: MediaType.cartridge,
        confidence: 0.91,
        sourcePhoto: 'shelf_a.jpg',
      );
      final once = original.toJson();
      final reparsed =
          Detection.fromJson(jsonDecode(jsonEncode(once)) as Map<String, dynamic>);
      expect(reparsed.platformHint, 'SNES');
      expect(reparsed.discardedPlatformHint, isNull);
      expect(reparsed.toJson(), once);
    });

    test('a document written before the field parses unchanged', () {
      // Additive and optional, so the version stays 1 (`addedFromPhoto`'s
      // treatment).
      final detection = Detection.fromJson(<String, dynamic>{
        'raw_title': 'COBALT CHIME',
        'platform_hint': 'SWITCH',
      });
      expect(detection.discardedPlatformHint, isNull);
      expect(detection.platformHint, 'SWITCH');
    });
  });
}
