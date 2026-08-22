/// Guards the legal-mark strip on the IGDB query (T-0063).
///
/// Detections of `CONTROL-HIRES` returned zero games because their title
/// carried a ®. Which buckets moved, and by how much, is
/// doc/measurements.md, "The resolver, measured at last"; how many rows were
/// involved is a count of a private shelf and is in the control record
/// (T-0246). This header kept its own copy of that figure, stale, until
/// T-0153. Whether a title carries a mark is the first-ask/repeat
/// difference in the vision model (T-0086 corrected T-0053's cold/warm
/// reading: the prompt cache decides it, not a freshly loaded model) -- so
/// before this, the resolver's match rate depended on whether that server
/// process had already been asked for the photo.
///
/// Three things have to hold together:
///   1. the query IGDB is sent carries no mark;
///   2. the review document still carries the raw title exactly as read;
///   3. [stripLegalMarks] never changes a [titleKey], which is what keeps it
///      from drifting into a second normalization that disagrees with the
///      dedupe one (T-0056's defect class).
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

/// In the spelling that reaches this package -- the vision model writes the
/// single-character forms, never the `(R)`/`(TM)` ASCII spellings.
const _marks = ['®', '©', '℗', '™', '℠'];

/// The mark SHAPES a first-ask `CONTROL-HIRES` run wrote, plus the shapes the
/// strip must leave alone: a mark before a numeral, around a slashed numeral
/// pair, twice in one title, between a word and a digit, on an abbreviation
/// ending in a period, and on a title carrying no Latin script at all.
///
/// The titles that carried them are real, were read off photographs during
/// development, and are not published; every row below is invented and
/// reproduces one shape. Whether a repeat ask reproduces the marks at all is
/// not guaranteed -- the two hi-res documents on disk carry none -- which is
/// why the shapes are pinned here rather than re-read.
const _controlTitles = [
  'SOLAR PILGRIM® XII THE CINDER AGE',
  'SOLAR PILGRIM® X/X-2 HD Remaster',
  'SOLAR PILGRIM® VII & SOLAR PILGRIM® VIII REMASTERED - TWIN PACK',
  'WINTER TIDE™ -SOLAR PILGRIM® VII- REVERIE',
  'SOLAR PILGRIM™ IX',
  'COLD ARCHIVE™ requiem',
  'The Legend of Vireo™: Echo of the Hollow',
  "The Legend of Vireo™: Wren's Awakening",
  'The Legend of Vireo™: Ashes of the Kingdom',
  'The Legend of Vireo™: Ashes of the Kingdom Nintendo Switch 2 Edition',
  'The Legend of Vireo™: Sunward Blade HD',
  'Super Whack Bros.™ Ultimate',
  'Super Pippo Maker™ 2',
  "Comics' Weaver-Man 2",
  'Mythéon Brilliant Zircite',
  'そらのは0 約束の丘',
];

Map<String, dynamic> _game(int id, String name, List<(int, String)> platforms) =>
    {
      'id': id,
      'name': name,
      'platforms': [
        for (final (platformId, platformName) in platforms)
          {'id': platformId, 'name': platformName},
      ],
    };

/// An IGDB stub that records the `search "..."` term of every request.
({IgdbClient client, List<String> searched}) _spyIgdb(
    List<Map<String, dynamic>> games) {
  final searched = <String>[];
  final transport = MockClient((request) async {
    if (request.url.host == 'id.twitch.tv') {
      return http.Response(
          jsonEncode({'access_token': 'stub-token', 'expires_in': 3600}), 200);
    }
    final term = RegExp(r'search "([^"]*)"').firstMatch(request.body);
    // T-0094's field filter sends a body with no `search` term. Answering it
    // with the same rows would make the searches below unreachable, since the
    // filter fires only where a search returned nothing.
    if (term == null) return http.Response('[]', 200);
    searched.add(term.group(1)!);
    return http.Response(jsonEncode(games), 200);
  });
  return (
    client: IgdbClient(
        clientId: 'stub', clientSecret: 'stub', client: transport),
    searched: searched,
  );
}

Detection _detection(String title, {String? hint = 'SWITCH'}) => Detection(
      rawTitle: title,
      platformHint: hint,
      mediaType: MediaType.cartridge,
      confidence: 1.0,
      sourcePhoto: 'shelf.jpg',
    );

const _switch = (130, 'Nintendo Switch');

void main() {
  group('stripLegalMarks', () {
    test('removes every mark, wherever it sits in the title', () {
      expect(stripLegalMarks('SOLAR PILGRIM® XII THE CINDER AGE'),
          'SOLAR PILGRIM XII THE CINDER AGE');
      expect(stripLegalMarks('WINTER TIDE™ -SOLAR PILGRIM® VII- REVERIE'),
          'WINTER TIDE -SOLAR PILGRIM VII- REVERIE');
      expect(stripLegalMarks('MOONLIGHT®3'), 'MOONLIGHT 3');
      expect(stripLegalMarks('™ FROST WAKE ®'), 'FROST WAKE');
    });

    test('leaves the punctuation IGDB searches through alone', () {
      // Measured against a real title that is not published: folding the
      // slash and hyphen away to spaces returned 0 hits, where the form that
      // keeps them returned the right game. The figure is the finding; the
      // row below is invented and cannot evidence it.
      expect(stripLegalMarks('SOLAR PILGRIM® X/X-2 HD Remaster'),
          'SOLAR PILGRIM X/X-2 HD Remaster');
      expect(stripLegalMarks("Comics' Weaver-Man 2"), "Comics' Weaver-Man 2");
      expect(stripLegalMarks('Super Whack Bros.™ Ultimate'),
          'Super Whack Bros. Ultimate');
    });

    test('is idempotent, so applying it twice is harmless', () {
      for (final title in _controlTitles) {
        expect(stripLegalMarks(stripLegalMarks(title)),
            stripLegalMarks(title));
      }
    });
  });

  group('agreement with titleKey', () {
    test('every stripped mark is one titleKey already folds away', () {
      for (final mark in _marks) {
        expect(titleKey('solar pilgrim${mark} xii'), titleKey('solar pilgrim xii'),
            reason: 'titleKey no longer folds $mark away, so stripping it '
                'in the query is now a second normalization');
      }
    });

    test('stripping never changes the identity titleKey assigns', () {
      for (final title in _controlTitles) {
        expect(titleKey(stripLegalMarks(title)), titleKey(title),
            reason: title);
      }
    });
  });

  group('the query IGDB is sent', () {
    test('carries no mark, for each of the four detections that returned '
        'nothing', () async {
      const titles = [
        'SOLAR PILGRIM® XII THE CINDER AGE',
        'SOLAR PILGRIM® X/X-2 HD Remaster',
        'SOLAR PILGRIM® VII & SOLAR PILGRIM® VIII REMASTERED - TWIN PACK',
        'WINTER TIDE™ -SOLAR PILGRIM® VII- REVERIE',
      ];
      const expected = [
        'solar pilgrim xii the cinder age',
        'solar pilgrim x/x-2 hd remaster',
        'solar pilgrim vii & solar pilgrim viii remastered - twin pack',
        'winter tide -solar pilgrim vii- reverie',
      ];
      // One spy per title, and its first term: the stub answers with zero
      // rows, which since T-0065 is followed by shortened retries.
      for (var i = 0; i < titles.length; i++) {
        final igdb = _spyIgdb([]);
        await ResolverWorker(igdb.client).process(_detection(titles[i]));
        expect(igdb.searched.first, expected[i]);
      }
    });

    test('is stripped by IgdbClient itself, not only by the resolver',
        () async {
      final igdb = _spyIgdb([]);
      await igdb.client.search('cold archive™ requiem');
      expect(igdb.searched.single, 'cold archive requiem');
    });

    test('has the aliases applied to the stripped form', () async {
      final igdb = _spyIgdb([]);
      await ResolverWorker(igdb.client).process(_detection('BIOHAZARD® RE:4'));
      expect(igdb.searched.first, 'resident evil re:4');
    });
  });

  group('the review document', () {
    test('carries the raw title exactly as the model read it', () async {
      const raw = 'WINTER TIDE™ -SOLAR PILGRIM® VII- REVERIE';
      final igdb = _spyIgdb([
        _game(1, 'Winter Tide: Solar Pilgrim VII - Reverie', [_switch]),
      ]);
      final resolved =
          await ResolverWorker(igdb.client).process(_detection(raw));

      expect(resolved.detection.rawTitle, raw);
      final json = jsonDecode(jsonEncode(
          ReviewDocument(
            version: 1,
            created: 'now',
            photos: const ['shelf.jpg'],
            games: [resolved],
          ).toJson())) as Map<String, dynamic>;
      expect(
        ((json['games'] as List).single as Map)['detection']['raw_title'],
        raw,
      );
    });
  });

  group('the first-ask/repeat difference', () {
    test('both spellings of one title resolve identically', () async {
      const games = [
        {
          'id': 1,
          'name': 'Solar Pilgrim XII: The Cinder Age',
          'platforms': [
            {'id': 130, 'name': 'Nintendo Switch'},
          ],
        },
      ];
      Future<ResolvedGame> resolve(String title) async =>
          ResolverWorker(_spyIgdb(games).client).process(_detection(title));

      final firstAsk = await resolve('SOLAR PILGRIM® XII THE CINDER AGE');
      final repeat = await resolve('SOLAR PILGRIM XII THE CINDER AGE');

      expect(firstAsk.best, isNotNull);
      expect(firstAsk.best!.igdbId, repeat.best!.igdbId);
      expect(firstAsk.best!.score, repeat.best!.score);
      expect(jsonEncode(firstAsk.toJson()['best']),
          jsonEncode(repeat.toJson()['best']));
      expect(jsonEncode(firstAsk.toJson()['candidates']),
          jsonEncode(repeat.toJson()['candidates']));
    });

    test('the same holds for a title carrying ™, which was never fatal but '
        'moves the score', () async {
      const games = [
        {
          'id': 2,
          'name': 'Super Pippo Maker 2',
          'platforms': [
            {'id': 130, 'name': 'Nintendo Switch'},
          ],
        },
      ];
      Future<ResolvedGame> resolve(String title) async =>
          ResolverWorker(_spyIgdb(games).client).process(_detection(title));

      final firstAsk = await resolve('Super Pippo Maker™ 2');
      final repeat = await resolve('Super Pippo Maker 2');
      expect(firstAsk.best!.score, repeat.best!.score);
      expect(firstAsk.best!.score, 1.0);
    });
  });
}
