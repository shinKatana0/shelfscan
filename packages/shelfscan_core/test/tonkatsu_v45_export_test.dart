import 'dart:convert';

import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

const _gameId = 611611;
const _movieId = 477477;

Candidate _candidate(String catalogue, int id,
        {String title = 'Mossvale Passage',
        int? year,
        String? platform}) =>
    Candidate(
      externalId: '$catalogue:$id',
      title: title,
      score: 1,
      releaseYear: year,
      platformId: platform == null ? null : 2121,
      platformName: platform,
    );

ResolvedGame _row(String title,
        {WorkKind kind = WorkKind.game,
        Candidate? best,
        String? platform,
        int? sourceYear,
        ReviewStatus status = ReviewStatus.approved}) =>
    ResolvedGame(
      detection: Detection(
        rawTitle: title,
        mediaType: MediaType.disc,
        confidence: 0.8,
        sourcePhoto: 'synthetic_shelf.jpg',
        platformHint: platform,
        sourceYear: sourceYear,
        workKind: kind,
      ),
      best: best,
      status: status,
    );

ReviewDocument _document(List<ResolvedGame> rows) => ReviewDocument(
      version: 1,
      created: '2026-01-01T00:00:00.000Z',
      photos: const ['synthetic_shelf.jpg'],
      games: rows,
    );

List<Map<String, dynamic>> _cards(
        ReviewDocument document, TonkatsuCardsExporter exporter) =>
    (jsonDecode(exporter.export(document)) as List<dynamic>)
        .cast<Map<String, dynamic>>();

void main() {
  group('tonkatsuV45Export default and legacy path', () {
    test('the compile-time flag defaults off and registry uses it', () {
      expect(tonkatsuV45Export, isFalse);
      expect((exporters['tonkatsu-cards']!() as TonkatsuCardsExporter).v45Export,
          isFalse);
    });

    test('an explicit off flag keeps the four-key leftover contract', () {
      final matched = _row('MOSSVALE PASSAGE',
          best: _candidate(igdbCatalogue, _gameId,
              title: 'Mossvale Passage', year: 1996, platform: 'SNES'));
      final unmatched = _row('QUARRY OF BELLS', platform: 'PS4');
      final document = _document([matched, unmatched]);
      final legacy = TonkatsuCardsExporter(v45Export: false);
      expect(legacy.select(document), [unmatched]);
      expect(legacy.export(document), '''
[
  {
    "title": "QUARRY OF BELLS",
    "type": "game",
    "platform": "PS4"
  }
]'''.trim());
      expect(legacy.export(document), TonkatsuCardsExporter().export(document));

      final xcoll = jsonDecode(TonkatsuExporter().export(document)) as Map;
      expect(xcoll['version'], 2);
      expect((xcoll['items'] as List).single, {
        'media_type': 'game',
        'external_id': _gameId,
        'platform_id': 2121,
      });
    });
  });

  group('v45 card mapping', () {
    final v45 = TonkatsuCardsExporter(v45Export: true);

    test('matched and unmatched approved rows are both included', () {
      final matched = _row('MOSSVALE PASSAGE',
          best: _candidate(igdbCatalogue, _gameId,
              title: 'Mossvale Passage', year: 1996, platform: 'SNES'));
      final unmatched = _row('QUARRY OF BELLS', platform: 'PS4');
      final cards = _cards(_document([matched, unmatched]), v45);
      expect(cards, [
        {
          'title': 'Mossvale Passage',
          'type': 'game',
          'alt_title': 'MOSSVALE PASSAGE',
          'year': 1996,
          'platform': 'SNES',
        },
        {'title': 'QUARRY OF BELLS', 'type': 'game', 'platform': 'PS4'},
      ]);
      expect(cards.first['year'], isA<int>());
      expect(cards.last.containsKey('year'), isFalse);
    });

    test('sourceYear alone is omitted along with unsupported metadata', () {
      final card = _cards(
          _document([_row('Quarry of Bells', sourceYear: 2019)]), v45).single;
      expect(card, {'title': 'Quarry of Bells', 'type': 'game'});
    });

    test('a wrong-catalogue best supplies no title, year or platform', () {
      final card = _cards(
          _document([
            _row('MOSSVALE PASSAGE',
                best: _candidate(tmdbCatalogue, _movieId,
                    title: 'Different Film', year: 2008,
                    platform: 'Unrelated Platform'),
                platform: 'PS4')
          ]),
          v45).single;
      expect(card, {
        'title': 'MOSSVALE PASSAGE',
        'type': 'game',
        'platform': 'PS4',
      });
    });

    test('a movie may carry a trusted year but no platform', () {
      final card = _cards(
          _document([
            _row('LANTERN HOUR',
                kind: WorkKind.movie,
                best: _candidate(tmdbCatalogue, _movieId,
                    title: 'Lantern Hour', year: 2004),
                platform: 'PS4')
          ]),
          v45).single;
      expect(card, {
        'title': 'Lantern Hour',
        'type': 'movie',
        'alt_title': 'LANTERN HOUR',
        'year': 2004,
      });
    });

    const expectedTypes = {
      WorkKind.game: 'game',
      WorkKind.movie: 'movie',
      WorkKind.animation: 'animation',
      WorkKind.animationFilm: 'animation',
      WorkKind.animationSeries: 'animation',
      WorkKind.anime: 'anime',
    };
    test('every current WorkKind has an explicit type, anime stays distinct',
        () {
      expect(expectedTypes.keys.toSet(), WorkKind.values.toSet());
      for (final entry in expectedTypes.entries) {
        final card = _cards(
            _document([_row('Lantern Hour', kind: entry.key)]), v45).single;
        expect(card['type'], entry.value, reason: entry.key.name);
      }
    });

    test('the existing cards vocabulary includes types without source kinds',
        () {
      expect(TonkatsuCardsExporter.cardTypes, containsAll([
        'tv_show', 'visual_novel', 'manga', 'book'
      ]));
    });

    test('review gate, empty handling, and deterministic rendering hold', () {
      final document = _document([
        _row('Mossvale Passage', status: ReviewStatus.pending),
        _row('Quarry of Bells', status: ReviewStatus.rejected),
        _row('Lantern Hour', status: ReviewStatus.edited),
        _row('   '),
      ]);
      expect(v45.select(document), [document.games[2]]);
      expect(_cards(document, v45), [
        {'title': 'Lantern Hour', 'type': 'game'}
      ]);
      expect(v45.export(document), v45.export(document));
      expect(TonkatsuCardsExporter(v45Export: true).export(document),
          v45.export(document));
      expect(v45.emptyFileIsUsable, isFalse);
      expect(v45.render([_row('   ')]), '[]');
    });
  });
}
