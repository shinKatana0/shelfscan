/// What separates two candidates a human is asked to choose between (T-0170,
/// folding T-0172).
///
/// T-0165 stopped the resolver guessing between two rows at the identical top
/// score on one platform, and T-0159 made a store product id resolve by an
/// exact join. Both decisions were right and both arrived at review invisible:
/// a same-name pair is identical in every field `Candidate` carried, and the
/// join had to write `score: 1.0` into the same field a lucky Levenshtein
/// match writes it into. The two facts that separate them -- the game's release
/// year, and the mechanism that made the match -- are carried here.
///
/// The pairs below are the three collisions measured live 2026-08-16 on
/// T-0156's desktop titles (doc/measurements.md, "The tie nobody could
/// see"), and the join figures are that file's "The exact join", 394 of 480.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

const _pc = (6, 'PC (Microsoft Windows)');

Map<String, dynamic> _game(
  int id,
  String name,
  List<(int, String)> platforms, {
  int? year,
  List<String> alternativeNames = const [],
}) =>
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

Map<String, dynamic> _external(String uid, Map<String, dynamic> game) =>
    {'id': 1100000026, 'uid': uid, 'game': game};

Future<ResolvedGame> _resolve(
  Detection detection, {
  List<Map<String, dynamic>> games = const [],
  List<Map<String, dynamic>> externalRows = const [],
}) {
  final transport = MockClient((request) async {
    if (request.url.host == 'id.twitch.tv') {
      return http.Response(
          jsonEncode({'access_token': 'stub-token', 'expires_in': 3600}), 200);
    }
    return http.Response(
        jsonEncode(request.url.path.endsWith('/external_games')
            ? externalRows
            : games),
        200);
  });
  return ResolverWorker(
          IgdbClient(clientId: 'stub', clientSecret: 'stub', client: transport))
      .process(detection);
}

Detection _spine(String title, {String hint = 'PC'}) => Detection(
      rawTitle: title,
      platformHint: hint,
      mediaType: MediaType.unknown,
      confidence: 1.0,
      sourcePhoto: 'shelf1.jpg',
    );

Detection _gogInstall(String title, String sourceId) => Detection.fromSource(
      rawTitle: title,
      origin: DetectionOrigin.metadata,
      sourceEntry: 'goggame-${sourceId.split(':').last}.info',
      sourceId: sourceId,
      platformHint: GogMetadataSource.platformHint,
    );

Candidate _plain({int? releaseYear, MatchMethod? matchMethod}) => Candidate(
      igdbId: 67,
      title: 'Regent of Aurex',
      platformId: 6,
      platformName: 'PC (Microsoft Windows)',
      score: 1.0,
      releaseYear: releaseYear,
      matchMethod: matchMethod ?? MatchMethod.fuzzy,
    );

void main() {
  group('the year reaches the candidate the human is offered', () {
    test('two identically named games arrive as 1993 and 2016', () async {
      final resolved = await _resolve(_spine('regent of aurex'), games: [
        _game(1100000058, 'Regent of Aurex', [_pc], year: 1993),
        _game(1100000009, 'Regent of Aurex', [_pc], year: 2016),
      ]);
      expect(resolved.best, isNull, reason: 'T-0165 refuses the tie');
      expect(resolved.candidates.map((c) => c.releaseYear), [1993, 2016]);
      // Everything else on the two rows is identical, which is the defect.
      expect(resolved.candidates.map((c) => c.title), everyElement('Regent of Aurex'));
      expect(resolved.candidates.map((c) => c.score), everyElement(1.0));
    });

    test('1993 against 2012, likewise', () async {
      final resolved = await _resolve(_spine('cabalists'), games: [
        _game(1100000059, 'Cabalists', [_pc], year: 1993),
        _game(1100000010, 'Cabalists', [_pc], year: 2012),
      ]);
      expect(resolved.candidates.map((c) => c.releaseYear), [1993, 2012]);
    });

    test('and a pair separated only by a generation, one of them matched on '
        'an alternative name', () async {
      final resolved = await _resolve(_spine('moor'), games: [
        _game(1100000011, 'Moor', [_pc], year: 2016),
        _game(1100000012, 'The Ultimate Moor', [_pc],
            year: 1995, alternativeNames: ['Moor']),
      ]);
      expect(resolved.candidates.map((c) => c.releaseYear), [2016, 1995]);
    });

    test('a game IGDB has no date for carries no year rather than a wrong one',
        () async {
      // A small fraction of the games one control run touches (T-0165).
      final resolved = await _resolve(_spine('cabalists'), games: [
        _game(1, 'Cabalists', [_pc]),
      ]);
      expect(resolved.candidates.single.releaseYear, isNull);
      expect(resolved.candidates.single.toJson()['release_year'], isNull);
    });
  });

  group('how the match was made', () {
    test('a joined row and a fuzzy 1.000 are the same score and different '
        'methods', () async {
      final joined = await _resolve(
        _gogInstall('MOOR', 'gog:1100000027'),
        externalRows: [
          _external('1100000027',
              _game(1100000012, 'The Ultimate Moor', [_pc], year: 1995)),
        ],
      );
      final fuzzy = await _resolve(_spine('the ultimate moor'), games: [
        _game(1100000012, 'The Ultimate Moor', [_pc], year: 1995),
      ]);

      expect(joined.best!.score, 1.0);
      expect(fuzzy.best!.score, 1.0);
      expect(joined.best!.igdbId, fuzzy.best!.igdbId);
      // The one thing that now tells them apart.
      expect(joined.best!.matchMethod, MatchMethod.externalId);
      expect(fuzzy.best!.matchMethod, MatchMethod.fuzzy);
    });

    test('the join carries the year as well, off the same request', () async {
      // `gamesByExternalId` already expands `game.first_release_date`, so the
      // nine multi-platform joins that reach review carry it too.
      final joined = await _resolve(
        _gogInstall('Regent of Aurex', 'gog:1100000028'),
        externalRows: [
          _external('1100000028', _game(1100000058, 'Regent of Aurex', [_pc], year: 1993)),
        ],
      );
      expect(joined.best!.releaseYear, 1993);
    });

    test('a uid IGDB does not know falls back and is a fuzzy match again',
        () async {
      final resolved = await _resolve(
        _gogInstall('Ivor Lane', 'gog:9999999999'),
        games: [_game(1100000029, 'Ivor Lane', [_pc], year: 2010)],
      );
      expect(resolved.best!.igdbId, 1100000029);
      expect(resolved.best!.matchMethod, MatchMethod.fuzzy);
    });
  });

  group('review.json takes both additively', () {
    test('a document written before either field existed reads back unchanged',
        () {
      final before = {
        'igdb_id': 1100000058,
        'title': 'Regent of Aurex',
        'platform_id': 6,
        'platform_name': 'PC (Microsoft Windows)',
        'score': 1.0,
      };
      final candidate = Candidate.fromJson(before);
      expect(candidate.releaseYear, isNull);
      expect(candidate.matchMethod, MatchMethod.fuzzy,
          reason: 'every match written before this key was scored');
    });

    test('and one written after it round-trips', () {
      for (final candidate in [
        _plain(releaseYear: 1993),
        _plain(),
        _plain(matchMethod: MatchMethod.externalId, releaseYear: 2016),
      ]) {
        final json = candidate.toJson();
        final read = Candidate.fromJson(jsonDecode(jsonEncode(json)));
        expect(read.toJson(), json);
        expect(read.releaseYear, candidate.releaseYear);
        expect(read.matchMethod, candidate.matchMethod);
      }
    });

    test('through the whole document, with T-0035 healing untouched', () {
      final document = ReviewDocument.parse(jsonEncode({
        'version': 1,
        'created': '2026-08-16T09:00:00.000000Z',
        'photos': ['shelf1.jpg'],
        'games': [
          {
            'detection': {
              'raw_title': 'REGENT OF AUREX',
              // The absent markers a model writes as text, which must still
              // read back as absences beside the new keys.
              'platform_hint': 'null',
              'notes': 'none',
              'media_type': 'unknown',
              'confidence': 1.0,
              'source_photo': 'shelf1.jpg',
            },
            'best': null,
            'candidates': [
              {
                'igdb_id': 1100000058,
                'title': 'Regent of Aurex',
                'platform_id': 6,
                'platform_name': 'PC (Microsoft Windows)',
                'score': 1.0,
                'matched_alternative_name': 'none',
                'release_year': 1993,
                'match_method': 'externalId',
              },
            ],
            'status': 'pending',
          },
        ],
      }));

      final candidate = document.games.single.candidates.single;
      expect(candidate.releaseYear, 1993);
      expect(candidate.matchMethod, MatchMethod.externalId);
      expect(candidate.matchedAlternativeName, isNull);
      expect(document.games.single.detection.platformHint, isNull);
      expect(document.games.single.detection.notes, isNull);

      final again = ReviewDocument.parse(jsonEncode(document.toJson()));
      expect(jsonEncode(again.toJson()), jsonEncode(document.toJson()));
    });

    test('an unknown method reads as fuzzy rather than throwing', () {
      // A document written by a newer build, seen from this one.
      final candidate = Candidate.fromJson({
        'igdb_id': 1100000058,
        'title': 'Regent of Aurex',
        'platform_id': 6,
        'platform_name': 'PC (Microsoft Windows)',
        'score': 1.0,
        'match_method': 'steamManifest',
      });
      expect(candidate.matchMethod, MatchMethod.fuzzy);
    });

    test('a year of the wrong shape is a named error, not a silent null', () {
      expect(
        () => Candidate.fromJson({
          'igdb_id': 1100000058,
          'title': 'Regent of Aurex',
          'platform_id': 6,
          'platform_name': 'PC (Microsoft Windows)',
          'score': 1.0,
          'release_year': '1993',
        }, path: 'games[0].best'),
        throwsA(isA<ReviewFormatException>().having((e) => e.toString(),
            'message', contains('games[0].best.release_year'))),
      );
    });
  });

  group('the exporters are untouched by either field', () {
    // Both targets take ids and titles; neither has a column for these.
    final approved = ResolvedGame(
      detection: _spine('REGENT OF AUREX'),
      best: _plain(releaseYear: 1993, matchMethod: MatchMethod.externalId),
      status: ReviewStatus.approved,
    );
    final bare = ResolvedGame(
      detection: _spine('REGENT OF AUREX'),
      best: _plain(),
      status: ReviewStatus.approved,
    );

    test('the .xcoll items are identical', () {
      // Everything but the export timestamp, which moves between two calls.
      List<dynamic> items(ResolvedGame game) =>
          (jsonDecode(TonkatsuExporter().render([game]))
              as Map<String, dynamic>)['items'] as List<dynamic>;
      expect(items(approved), items(bare));
    });

    test('the CSV row is identical', () {
      expect(CsvExporter().render([approved]), CsvExporter().render([bare]));
    });
  });
}
