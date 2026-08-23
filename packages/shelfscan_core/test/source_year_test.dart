/// The year a NAME printed, from the parse to the tie rule (T-0171).
///
/// T-0158 measured the parse and left the value at the source boundary;
/// T-0165 measured what a candidate-side year buys and named the source-side
/// one as the direction it could not implement. This file drives the whole
/// path: the parse rule's own examples, the field on the detection, the
/// `review.json` it round-trips through, and the one thing the resolver is
/// allowed to do with it.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

const _pc = (6, 'PC (Microsoft Windows)');
const _switch1 = (130, 'Nintendo Switch');
const _switch2 = (508, 'Nintendo Switch 2');

Map<String, dynamic> _game(int id, String name, List<(int, String)> platforms,
        {int? year, List<String> alternativeNames = const []}) =>
    {
      'id': id,
      'name': name,
      if (alternativeNames.isNotEmpty)
        'alternative_names': [
          for (final alternative in alternativeNames) {'name': alternative},
        ],
      if (year != null)
        'first_release_date':
            DateTime.utc(year, 6, 1).millisecondsSinceEpoch ~/ 1000,
      'platforms': [
        for (final (platformId, platformName) in platforms)
          {'id': platformId, 'name': platformName},
      ],
    };

Future<ResolvedGame> _resolve(
    List<Map<String, dynamic>> games, Detection detection) {
  final transport = MockClient((request) async {
    if (request.url.host == 'id.twitch.tv') {
      return http.Response(
          jsonEncode({'access_token': 'stub-token', 'expires_in': 3600}), 200);
    }
    return http.Response(jsonEncode(games), 200);
  });
  return ResolverWorker(
          IgdbClient(clientId: 'stub', clientSecret: 'stub', client: transport))
      .process(detection);
}

Detection _fromName(String name, {String? container}) =>
    const FilenameSource()
        .read(SourceEntry(name: name, container: container))
        .items
        .single;

Detection _spine(String rawTitle, {String? hint}) => Detection(
      rawTitle: rawTitle,
      platformHint: hint,
      mediaType: MediaType.disc,
      confidence: 0.9,
      sourcePhoto: 'shelf_a.jpg',
    );

/// The two IGDB rows that tie at 1.000 on one platform, measured live
/// 2026-08-16 (doc/measurements.md, "The tie nobody could see").
final _regentOfAurex = [
  _game(1100000058, 'Regent of Aurex', [_pc], year: 1993),
  _game(1100000009, 'Regent of Aurex', [_pc], year: 2016),
];

void main() {
  group('the parse reaches the detection', () {
    test("a name that prints a year where a title cannot be carries it", () {
      expect(_fromName('Regent.of.Aurex.1993.DOSBox.GOG.zip').sourceYear, 1993);
      expect(_fromName('Cabalists.1993.GOG-Razor1911.iso').sourceYear, 1993);
      expect(_fromName('Tulip.Hospital.(1997).GOG.zip').sourceYear, 1997);
      expect(_fromName('Game.Name.2019.RePack-GROUP').sourceYear, 2019);
      expect(_fromName('Z-CON.ORB.Defense.1994.GOG-CODEX.rar').sourceYear, 1994);
    });

    test('a name whose digits ARE the title carries none', () {
      // T-0158's position rule, and the reason the year is not shape-decided:
      // 2016 in `MOOR 2016` and 2019 in `Game.Name.2019.RePack` are the same
      // four digits.
      for (final name in ['MOOR.2016.iso', 'Volo 2004', 'Punter PFL 2005']) {
        final detection = _fromName(name);
        expect(detection.sourceYear, isNull, reason: name);
        expect(detection.rawTitle, contains(RegExp(r'\d{4}$')),
            reason: 'the digits stay in the title they are part of');
      }
    });

    test('the year is never folded into the title, and the volume key is what '
        'it was', () {
      expect(_fromName('Regent.of.Aurex.1993.DOSBox.GOG.zip').rawTitle,
          'Regent of Aurex');
      expect(_fromName('Tulip.Hospital.(1997).GOG.zip').rawTitle,
          'Tulip Hospital');
      // Exempting four-digit numbers from the volume key would buy the folded
      // form and lose this pair (T-0165).
      expect(volumeNumbersAgree('punter pfl 2004', 'Punter PFL 2004'), isTrue);
      expect(volumeNumbersAgree('punter pfl 2004', 'Punter PFL 2005'), isFalse);
      expect(volumeNumbersAgree('regent of aurex 1993', 'Regent of Aurex'),
          isFalse);
    });

    test('a GoG installer name carries a build id and no year', () {
      expect(_fromName('setup_moor_1.9_(21474).exe').sourceYear, isNull);
      expect(_fromName('setup_marlows_gate_3_2.0.0.7_(64bit).exe').sourceYear,
          isNull);
    });

    test("a title recovered from the container brings that name's year", () {
      final detection =
          _fromName('setup.exe', container: 'Tulip.Hospital.(1997).GOG');
      expect(detection.rawTitle, 'Tulip Hospital');
      expect(detection.sourceYear, 1997);
    });

    test('a metadata row is unaffected: nothing else emits one', () {
      expect(
          Detection.fromSource(
            rawTitle: 'Vex',
            origin: DetectionOrigin.metadata,
            sourceEntry: 'goggame-1100000001.info',
          ).sourceYear,
          isNull);
    });
  });

  group('the review document', () {
    test('a photographed row writes no source_year key', () {
      // The bytes a photo-only scan wrote before this field existed, which is
      // the same rule `source_entry` and `source_id` are absent-by-default for.
      final photographed = _spine('Duskhollow');
      expect(photographed.toJson().containsKey('source_year'), isFalse);
      expect(jsonEncode(photographed.toJson()), isNot(contains('source_year')));
    });

    test('a filename row round-trips through JSON', () {
      final detection = _fromName('Regent.of.Aurex.1993.DOSBox.GOG.zip');
      final reparsed = Detection.fromJson(
          jsonDecode(jsonEncode(detection.toJson())) as Map<String, dynamic>);
      expect(reparsed.sourceYear, 1993);
      expect(reparsed.rawTitle, 'Regent of Aurex');
      expect(reparsed.sourceEntry, 'Regent.of.Aurex.1993.DOSBox.GOG.zip');
      expect(jsonEncode(reparsed.toJson()), jsonEncode(detection.toJson()));
    });

    test('a whole document round-trips, and T-0035 still heals beside the key',
        () {
      final document = ReviewDocument.parse(jsonEncode({
        'version': 1,
        'created': '2026-08-16T00:00:00Z',
        'photos': <String>[],
        'games': [
          {
            'detection': {
              'raw_title': 'Regent of Aurex',
              'platform_hint': 'null',
              'notes': 'none',
              'origin': 'filename',
              'source_entry': 'Regent.of.Aurex.1993.DOSBox.GOG.zip',
              'source_year': 1993,
            },
            'best': null,
            'candidates': <dynamic>[],
            'status': 'pending',
          },
        ],
      }));

      final detection = document.games.single.detection;
      expect(detection.sourceYear, 1993);
      expect(detection.platformHint, isNull);
      expect(detection.notes, isNull);
      expect(detection.origin, DetectionOrigin.filename);

      final again = ReviewDocument.parse(jsonEncode(document.toJson()));
      expect(jsonEncode(again.toJson()), jsonEncode(document.toJson()));
    });

    test('a document written before the field parses unchanged', () {
      final detection = Detection.fromJson({
        'raw_title': 'Vex',
        'media_type': 'disc',
        'confidence': 0.9,
        'source_photo': 'shelf_a.jpg',
      });
      expect(detection.sourceYear, isNull);
    });

    test('a year of the wrong shape is a named error, not a silent null', () {
      expect(
        () => Detection.fromJson({
          'raw_title': 'Regent of Aurex',
          'source_year': '1993',
        }, path: 'games[0].detection'),
        throwsA(isA<ReviewFormatException>().having((e) => e.toString(),
            'message', contains('games[0].detection.source_year'))),
      );
    });
  });

  group('the tie the source year separates', () {
    test('Regent of Aurex, 1993 against the 2016 remake', () async {
      final resolved = await _resolve(
          _regentOfAurex, _fromName('Regent.of.Aurex.1993.DOSBox.GOG.zip'));
      expect(resolved.best?.externalId, 'igdb:1100000058');
      expect(resolved.best?.releaseYear, 1993);
      // Refused for the human without it, which is what this replaces.
      expect(
          (await _resolve(_regentOfAurex, _spine('regent of aurex', hint: 'PC')))
              .best,
          isNull);
    });

    test('Cabalists, 1993 against 2012', () async {
      final resolved = await _resolve([
        _game(1100000059, 'Cabalists', [_pc], year: 1993),
        _game(1100000010, 'Cabalists', [_pc], year: 2012),
      ], _fromName('Cabalists.1993.GOG-Razor1911.iso'));
      expect(resolved.best?.externalId, 'igdb:1100000059');
    });

    test('the third measured collision stays refused: its name prints no year',
        () async {
      final resolved = await _resolve([
        _game(1100000011, 'Moor', [_pc], year: 2016),
        _game(1100000012, 'The Ultimate Moor', [_pc],
            year: 1995, alternativeNames: ['Moor']),
      ], _fromName('setup_moor_1.9_(21474).exe'));
      expect(resolved.best, isNull);
      expect(resolved.candidates.map((c) => c.score), everyElement(1.0));
    });

    test('both rows stay in the picker either way', () async {
      final resolved = await _resolve(
          _regentOfAurex, _fromName('Regent.of.Aurex.1993.DOSBox.GOG.zip'));
      // It decides between candidates; it never removes one. A filter would,
      // and that is the difference the whole choice turns on.
      expect(resolved.candidates.map((c) => c.externalId),
          ['igdb:1100000058', 'igdb:1100000009']);
    });
  });

  group('what it must not decide', () {
    test('a year matching no candidate leaves the refusal in place', () async {
      // The wrong-year case, which is the one nobody has a rate for: a repack
      // year in the slot the parser reads. It costs the refusal that was
      // already happening.
      final detection = _fromName('Regent.of.Aurex.1997.RePack-GROUP.zip');
      expect(detection.sourceYear, 1997, reason: 'the claim is made');
      expect((await _resolve(_regentOfAurex, detection)).best, isNull);
    });

    test('a year matching two of the tied rows leaves it in place too',
        () async {
      final resolved = await _resolve([
        _game(1, 'Cabalists', [_pc], year: 1993),
        _game(2, 'Cabalists', [_pc], year: 1993),
        _game(3, 'Cabalists', [_pc], year: 2012),
      ], _fromName('Cabalists.1993.GOG-Razor1911.iso'));
      expect(resolved.best, isNull);
    });

    test('one game on two consoles is still the human\'s to decide', () async {
      // T-0165's console clause: the year cannot answer WHICH machine, so a
      // tie spanning two platform ids declines the tie-break outright.
      final resolved = await _resolve([
        _game(1100000053, 'Starweave Chronicles 2', [_switch2, _switch1],
            year: 2017),
      ],
          Detection.fromSource(
            rawTitle: 'Starweave Chronicles 2',
            origin: DetectionOrigin.filename,
            sourceEntry: 'Starweave.Chronicles.2.2017.iso',
            platformHint: 'SWITCH',
            sourceYear: 2017,
          ));
      expect(resolved.best, isNull);
      expect(resolved.candidates.map((c) => c.platformId), [508, 130]);
    });

    test('a row that auto-matches today auto-matches the same game with a '
        'year on it', () async {
      // The tie-break is reached only from the refusal, so it can add an
      // auto-match and never move one. Same fixture, one field apart.
      final oneRelease = [
        _game(1100000049, 'Solar Pilgrim XVI', [_pc], year: 2023),
        _game(1100000050, "Solar Pilgrim XVI: Collector's Edition", [_pc],
            year: 2023, alternativeNames: ['Solar Pilgrim XVI']),
      ];
      final without = await _resolve(
          oneRelease,
          Detection.fromSource(
            rawTitle: 'Solar Pilgrim XVI',
            origin: DetectionOrigin.filename,
            sourceEntry: 'Solar.Pilgrim.XVI.iso',
            platformHint: 'PC',
          ));
      final with2016 = await _resolve(
          oneRelease,
          Detection.fromSource(
            rawTitle: 'Solar Pilgrim XVI',
            origin: DetectionOrigin.filename,
            sourceEntry: 'Solar.Pilgrim.XVI.2016.iso',
            platformHint: 'PC',
            sourceYear: 2016,
          ));
      expect(without.best?.externalId, 'igdb:1100000049');
      expect(with2016.best?.externalId, 'igdb:1100000049');
    });

    test('a photographed row is decided exactly as before', () async {
      // No read of either control set carries a year, so this branch
      // is the whole of the photo path: nothing to compare, nothing changes.
      final photographed = _spine('regent of aurex', hint: 'PC');
      expect(photographed.sourceYear, isNull);
      expect((await _resolve(_regentOfAurex, photographed)).best, isNull);
    });
  });
}
