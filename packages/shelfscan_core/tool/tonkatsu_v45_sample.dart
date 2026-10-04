import 'package:shelfscan_core/shelfscan_core.dart';

Candidate _catalogue(String source, int id, String title, int year,
        {String? platform}) =>
    Candidate(
      externalId: '$source:$id',
      title: title,
      score: 1,
      releaseYear: year,
      platformId: platform == null ? null : 19,
      platformName: platform,
    );

ResolvedGame _reviewed(String title, WorkKind kind,
        {Candidate? best, String? platform}) =>
    ResolvedGame(
      detection: Detection(
        rawTitle: title,
        mediaType: MediaType.disc,
        confidence: 1,
        sourcePhoto: 'synthetic_fixture.jpg',
        workKind: kind,
        platformHint: platform,
      ),
      best: best,
      status: ReviewStatus.approved,
    );

ReviewDocument tonkatsuV45SampleDocument() => ReviewDocument(
    version: 1,
    created: '2026-01-01T00:00:00.000Z',
    photos: const ['synthetic_fixture.jpg'],
    games: [
      _reviewed('CHRONO TRIGGER', WorkKind.game,
          best: _catalogue(igdbCatalogue, 101010, 'Chrono Trigger', 1995,
              platform: 'SNES')),
      _reviewed('DUNE', WorkKind.movie,
          best: _catalogue(tmdbCatalogue, 202020, 'Dune', 2021)),
      _reviewed('Fullmetal Alchemist: Brotherhood', WorkKind.anime),
      _reviewed('SPIRITED AWAY', WorkKind.animationFilm,
          best: _catalogue(tmdbCatalogue, 303030, 'Spirited Away', 2001)),
      _reviewed('Quenlar Orbital Apricot Index Q7V4', WorkKind.game),
    ],
  );

void main() {
  if (!tonkatsuV45Export) {
    throw StateError('Run with -DtonkatsuV45Export=true');
  }
  print(exporters['tonkatsu-cards']!().export(tonkatsuV45SampleDocument()));
}
