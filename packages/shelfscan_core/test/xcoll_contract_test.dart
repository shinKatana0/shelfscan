/// The two halves of the `.xcoll` contract that no test stated on purpose
/// (T-0456): the envelope, and the pair each [WorkKind] writes inside it.
///
/// **The envelope.** `ARCHITECTURE.md` "Key decisions" 4 and `PROJECT.md` both
/// pin `version: 2`, and upstream's `docs/RCOLL_FORMAT.md` at `release/0.44`
/// says `Always 3 (v2 also accepted on import)` -- so 2 is the deliberate
/// choice rather than a stale one: an older build refuses a v3 file cleanly,
/// and v3's one relevant addition (`user_rating`) is a field this project does
/// not carry. Until this file the only assertion anywhere was a by-the-way
/// `contains('"version": 2')` inside a test about install directories, which
/// would have gone green on a file that had quietly moved every other part of
/// the envelope.
///
/// **The matrix.** What the writer puts in `media_type` and `platform_id` for
/// a kind, and which catalogue's id it will accept for one, are three answers
/// that have only ever been asserted kind by kind, in the task that added each
/// kind. Driven off [WorkKind.values] here, so a sixth kind fails this file
/// until somebody has answered all three for it -- which is the same guard the
/// exporter's own default-less switches are, one level out and readable.
///
/// Every fixture value is invented.
library;

import 'dart:convert';

import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

/// A platform id that is plainly the match's rather than the kind's: the two
/// numbers the kind can contribute are `0` and `1`.
const _matchPlatformId = 4242;

const _externalId = 770077;

Detection _detection(WorkKind kind) => Detection(
      rawTitle: 'THE GLASS ORRERY',
      mediaType: MediaType.disc,
      confidence: 0.9,
      sourcePhoto: 'shelf_b.jpg',
      workKind: kind,
    );

/// One approved row of [kind] whose match came from [catalogue].
ResolvedGame _row(WorkKind kind, String catalogue) => ResolvedGame(
      detection: _detection(kind),
      best: Candidate(
        externalId: '$catalogue:$_externalId',
        title: 'The Glass Orrery',
        platformId: catalogue == igdbCatalogue ? _matchPlatformId : null,
        platformName: catalogue == igdbCatalogue ? 'Fictional Console' : null,
        score: 1.0,
      ),
      status: ReviewStatus.approved,
    );

ReviewDocument _document(List<ResolvedGame> games) => ReviewDocument(
      version: 1,
      created: '2026-09-04T00:00:00.000Z',
      photos: const [],
      games: games,
    );

Map<String, dynamic> _rendered(ReviewDocument doc) =>
    jsonDecode(TonkatsuExporter().export(doc)) as Map<String, dynamic>;

List<Map<String, dynamic>> _items(ReviewDocument doc) => [
      for (final item in _rendered(doc)['items'] as List<dynamic>)
        item as Map<String, dynamic>
    ];

/// What the writer produces for one kind, or null where it declines the row.
typedef _Written = ({String mediaType, String catalogue, int? platformId});

/// The whole of the type/source table this project implements, against
/// upstream `release/0.44`.
///
/// `platformId: null` means the KEY IS ABSENT, which is not the same as a
/// `null` value -- the pinned contract has no reading for the latter and the
/// writer omits the key instead.
const _matrix = <WorkKind, _Written?>{
  WorkKind.game: (
    mediaType: 'game',
    catalogue: igdbCatalogue,
    platformId: _matchPlatformId,
  ),
  WorkKind.movie: (
    mediaType: 'movie',
    catalogue: tmdbCatalogue,
    platformId: null,
  ),
  // Declined: `platform_id` states film-or-series and nobody has answered.
  WorkKind.animation: null,
  WorkKind.animationFilm: (
    mediaType: 'animation',
    catalogue: tmdbCatalogue,
    platformId: 0,
  ),
  WorkKind.animationSeries: (
    mediaType: 'animation',
    catalogue: tmdbCatalogue,
    platformId: 1,
  ),
  // Declined for the other reason: upstream keys `anime` by AniList or Kitsu
  // and this project wires neither, so there is no id here that could fill the
  // field honestly.
  WorkKind.anime: null,
};

void main() {
  group('the envelope is pinned, and this is where it says so', () {
    // Both documents, because the envelope is not a property of the items: a
    // writer that read `version` off something in the file would pass one of
    // these and fail the other.
    final documents = {
      'an empty document': _document(const []),
      'a document with a row in it': _document([_row(WorkKind.game, 'igdb')]),
    };

    documents.forEach((what, doc) {
      test('version is the integer 2 in $what', () {
        final version = _rendered(doc)['version'];
        expect(version, 2);
        // Three separate ways the field has to be wrong before an importer
        // notices, and `== 2` alone catches only the first: a bumped number,
        // a string, and a double from a hand-edited writer.
        expect(version, isNot(3));
        expect(version, isA<int>());
        expect(version, isNot('2'));
      });

      test('format is light in $what', () {
        expect(_rendered(doc)['format'], 'light');
      });
    });

    test('and both survive into the text, not just the decoded map', () {
      final text = TonkatsuExporter().export(_document(const []));
      expect(text, contains('"version": 2'));
      expect(text, contains('"format": "light"'));
    });
  });

  group('what the writer puts in an item, kind by kind', () {
    test('the table answers every kind and invents none', () {
      expect(_matrix.keys.toSet(), WorkKind.values.toSet(),
          reason: 'a kind with no row here is a kind nobody answered '
              'media_type, platform_id and the catalogue for');
    });

    _matrix.forEach((kind, written) {
      if (written == null) {
        test('${kind.key} is declined whatever it matched', () {
          for (final catalogue in [igdbCatalogue, tmdbCatalogue]) {
            final row = _row(kind, catalogue);
            expect(row.best, isNotNull,
                reason: 'the row matched; the refusal is not about that');
            expect(TonkatsuExporter().canExport(row), isFalse,
                reason: '$catalogue was accepted for ${kind.key}');
          }
        });

        test('and no item of it reaches the file beside a row that exports',
            () {
          final items = _items(_document([
            _row(kind, igdbCatalogue),
            _row(kind, tmdbCatalogue),
            _row(WorkKind.game, igdbCatalogue),
          ]));
          expect(items, hasLength(1));
          expect(items.single['media_type'], 'game');
        });
        return;
      }

      test('${kind.key} writes media_type ${written.mediaType}', () {
        final item = _items(_document([_row(kind, written.catalogue)])).single;
        expect(item['media_type'], written.mediaType);
        expect(item['external_id'], _externalId,
            reason: 'a bare integer, with the catalogue implied by the type');
      });

      test('${kind.key} and its platform_id', () {
        final item = _items(_document([_row(kind, written.catalogue)])).single;
        if (written.platformId == null) {
          expect(item.containsKey('platform_id'), isFalse,
              reason: 'the key is omitted, never written null');
        } else {
          expect(item['platform_id'], written.platformId);
        }
      });

      test('${kind.key} refuses an id from the other catalogue', () {
        final other = written.catalogue == igdbCatalogue
            ? tmdbCatalogue
            : igdbCatalogue;
        expect(TonkatsuExporter().canExport(_row(kind, other)), isFalse,
            reason: 'the namespace has to agree with what the kind implies '
                '(decision 0016)');
      });
    });
  });

  // The assertion that fails if somebody later "helps" by widening
  // `_catalogue` to answer TMDB for this kind. It is not a loose match: an
  // `anime` item's id is AniList's or Kitsu's, so a TMDB id under that
  // `media_type` names a different work.
  group('nothing TMDB-shaped ever reaches the file under media_type anime',
      () {
    test('an anime row carrying a real TMDB candidate is still declined', () {
      final row = _row(WorkKind.anime, tmdbCatalogue);
      expect(row.best!.externalId, startsWith('$tmdbCatalogue:'));
      expect(TonkatsuExporter().canExport(row), isFalse);
    });

    test('and the word never appears in a rendered file at all', () {
      final text = TonkatsuExporter().export(_document([
        _row(WorkKind.anime, tmdbCatalogue),
        _row(WorkKind.animationFilm, tmdbCatalogue),
        _row(WorkKind.animationSeries, tmdbCatalogue),
      ]));
      // Not `isNot(contains('anime'))`: `"animation"` does not contain it, but
      // a future kind's spelling might, so the assertion is on the values the
      // items actually carry.
      expect([
        for (final item in jsonDecode(text)['items'] as List<dynamic>)
          (item as Map<String, dynamic>)['media_type']
      ], ['animation', 'animation']);
    });

    test('csv carries the row instead, so it is not lost', () {
      final doc = _document([_row(WorkKind.anime, tmdbCatalogue)]);
      expect(CsvExporter().select(doc), hasLength(1));
    });
  });
}
