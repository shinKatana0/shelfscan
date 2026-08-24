/// An anime series: the row a name can answer, and the question only a person
/// can (T-0368, decision 0015, decision 0016).
///
/// Three things are pinned here, and the middle one is the finding.
///
/// **The source answers what the grammar states and nothing more.** A
/// fansub-shaped name numbers an episode of a named series, so it yields one
/// [WorkKind.animationSeries] row; a scene-shaped one numbers an episode of a
/// series of unstated kind and goes on declining, because this project has a
/// kind for an anime series and none for a live-action one.
///
/// **N episodes are one row, and it is not [ResolvedGame.parts].** Every
/// episode parses to the same title with the same absent hint, which is the
/// pair `dedupeDetections` folds on -- so the relation runs the opposite way
/// from a box's: a box is one row a catalogue answered with several entries
/// and expands into N, a series is N files that are readings of one work and
/// folds into one. There is nothing to expand it back into, because an episode
/// is not a catalogue entry and this target has no item for one.
///
/// **The exporter's two decisions moved together.** `_catalogue` answers TMDB
/// for every animation kind now that one of them can be answered, and
/// `platform_id` carries `0` for a film and `1` for a series. The row nobody
/// has answered is still refused, and by the one reason that is still true of
/// it.
///
/// **Every name here is invented** (`doc/conventions.md` §3b), and reuses the
/// families already in this tree's fixtures. No title is anybody's.
library;

import 'dart:convert';

import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

SourceReading _read(String name) => const FilenameSource()
    .read(SourceEntry(name: name, container: null, content: ''));

Detection _row(String name) {
  final reading = _read(name);
  expect(reading.items, hasLength(1),
      reason: '$name produced no row, and declined '
          '${reading.declined.map((d) => d.reason)}');
  return reading.items.single;
}

ResolvedGame _resolved(WorkKind kind, {String externalId = 'tmdb:770001'}) =>
    ResolvedGame(
      detection: Detection.fromSource(
        rawTitle: 'Tidewrack Lament',
        origin: DetectionOrigin.filename,
        sourceEntry: '[SubGroup] Tidewrack Lament - 04 [1080p].mkv',
        workKind: kind,
      ),
      best: Candidate(
        externalId: externalId,
        title: 'Tidewrack Lament',
        platformId: null,
        platformName: null,
        score: 1.0,
      ),
      status: ReviewStatus.approved,
    );

ReviewDocument _document(List<ResolvedGame> games) => ReviewDocument(
      version: 1,
      created: '2026-08-24T00:00:00.000Z',
      photos: const [],
      games: games,
    );

List<dynamic> _items(ReviewDocument doc) =>
    (jsonDecode(TonkatsuExporter().export(doc)) as Map<String, dynamic>)
        ['items'] as List<dynamic>;

void main() {
  group('a fansub-shaped name is a series row', () {
    test('the title is the series, without the episode number', () {
      final row = _row('[SubGroup] Tidewrack Lament - 04 [1080p].mkv');
      expect(row.workKind, WorkKind.animationSeries);
      expect(row.rawTitle, 'Tidewrack Lament');
    });

    test('and carries no platform hint, the way a film does not', () {
      // Null and `PC` are different answers, and an anime has no platform for
      // the same reason a film has none: the gate has nothing to gate.
      expect(_row('[SubGroup] Tidewrack Lament - 04 [1080p].mkv').platformHint,
          isNull);
    });

    test('and no year, because the number it printed is an episode', () {
      expect(
          _row('[SubGroup] Tidewrack Lament - 04 [1080p].mkv').sourceYear,
          isNull);
    });

    test('a subtitle before the episode number stays in the title', () {
      expect(_row('[SubGroup] Tidewrack Lament - Second Voyage - 07 [720p].mkv')
          .rawTitle,
          'Tidewrack Lament - Second Voyage');
    });

    test('a version-marked episode is the same series', () {
      expect(_row('[SubGroup] Dusk Rail - 11v2 [1080p].mkv').rawTitle,
          'Dusk Rail');
    });
  });

  group('what still declines, and the reason is still true of it', () {
    String decline(String name) {
      final reading = _read(name);
      expect(reading.items, isEmpty,
          reason: '$name produced ${reading.items.map((i) => i.rawTitle)}');
      return reading.declined.single.reason;
    }

    // The scene series shape says series and not which KIND of series.
    // Answering `animation` to it would file every television release as
    // anime in somebody else's collection, and decision 0015 says a source
    // declines where the grammar settles nothing.
    test('the scene series shape', () {
      expect(decline('Tidewrack.Lament.S01E04.1080p.WEB-DL.mkv'),
          DeclineReason.seriesEpisode);
      expect(decline('Dusk Rail 1x04 720p.mkv'), DeclineReason.seriesEpisode);
      expect(decline('Dusk Rail Season 2 1080p.mkv'),
          DeclineReason.seriesEpisode);
    });

    test('and it is the SAME reason, not a new one', () {
      // The constant's own comment promised this: whichever task teaches this
      // source series turns the decline into rows, not into a different
      // reason.
      expect(DeclineReason.seriesEpisode, 'a series episode, not a film');
    });

    test('a film with a numeric subtitle is still a film', () {
      // The guard on the fansub rule, and the reason it is bracket-groups AND
      // a dash episode rather than either alone.
      final row = _row('Pale Anchor - 2 1999 1080p BluRay.mkv');
      expect(row.workKind, WorkKind.movie);
      expect(row.sourceYear, 1999);
    });

    test('a bracket group beside a YEAR is not a fansub name', () {
      // `_bracketGroups` matches parentheses too, so the wider reading of the
      // rule would make a parenthesised year evidence of anime.
      final row = _row('Pale Anchor (1999) 1080p BluRay.mkv');
      expect(row.workKind, WorkKind.movie);
    });
  });

  group('N episodes are ONE row, and not by expanding anything', () {
    List<Detection> episodes(int count) => [
          for (var i = 1; i <= count; i++)
            _row('[SubGroup] Tidewrack Lament - '
                '${i.toString().padLeft(2, '0')} [1080p].mkv'),
        ];

    test('a folder of episodes deduplicates to one series row', () {
      final rows = dedupeDetections(episodes(6));
      expect(rows, hasLength(1));
      expect(rows.single.rawTitle, 'Tidewrack Lament');
      expect(rows.single.workKind, WorkKind.animationSeries);
    });

    test('two different series stay two rows', () {
      final rows = dedupeDetections([
        ...episodes(3),
        _row('[SubGroup] Dusk Rail - 01 [1080p].mkv'),
      ]);
      expect(rows, hasLength(2));
    });

    // The relation the brief asked to be checked rather than assumed. A box
    // is one row a catalogue answered with several entries; a series is
    // several entries that are one work. `parts` is read by LENGTH, and a
    // series row's is empty -- so `mapsToSeveral` is false, the review screen
    // offers no expansion, and there is nothing an expansion could produce:
    // an episode has no catalogue id and this target has no item for one.
    test('a series row is not a box: nothing offers to expand it', () {
      final row = ResolvedGame(
        detection: dedupeDetections(episodes(6)).single,
        status: ReviewStatus.pending,
      );
      expect(row.parts, isEmpty);
      expect(row.mapsToSeveral, isFalse);
      expect(row.expandParts(), hasLength(1));
    });
  });

  group('a folder whose videos are all episodes', () {
    test('hands over one of them, and it now names the series', () {
      final chosen = videoNamingFolder(const [
        '[SubGroup] Tidewrack Lament - 01 [1080p].mkv',
        '[SubGroup] Tidewrack Lament - 02 [1080p].mkv',
        '[SubGroup] Tidewrack Lament - 03 [1080p].mkv',
      ]);
      expect(chosen, isNotNull);
      expect(_row(chosen!).workKind, WorkKind.animationSeries);
    });

    test('two series in one folder are as ambiguous as two films', () {
      expect(
          videoNamingFolder(const [
            '[SubGroup] Tidewrack Lament - 01 [1080p].mkv',
            '[SubGroup] Dusk Rail - 01 [1080p].mkv',
          ]),
          isNull);
    });

    test('a film in the folder still wins over the episodes', () {
      final chosen = videoNamingFolder(const [
        'Pale Anchor 1999 1080p BluRay x264-GROUP.mkv',
        '[SubGroup] Tidewrack Lament - 01 [1080p].mkv',
      ]);
      expect(_row(chosen!).workKind, WorkKind.movie);
    });

    test('a runnable file that names a game still stops the rule', () {
      // The guarantee `installerNamingFolder` protects: one entry per
      // subdirectory, and a game folder stays a game folder.
      expect(
          videoNamingFolder(const [
            'setup_harbour_lantern_1.6.15.exe',
            '[SubGroup] Tidewrack Lament - 01 [1080p].mkv',
          ]),
          isNull);
    });

    test('a scene-shaped folder still hands over a declining name', () {
      final chosen = videoNamingFolder(const [
        'Dusk.Rail.S01E01.1080p.WEB-DL.mkv',
        'Dusk.Rail.S01E02.1080p.WEB-DL.mkv',
      ]);
      expect(_read(chosen!).declined.single.reason,
          DeclineReason.seriesEpisode);
    });
  });

  group('the person answers, and the answer survives the file', () {
    // The finding this task turns on. `review.json` is the contract between
    // review and export, so a kind that reads back as a different kind
    // destroys exactly the answer the review step exists to collect. Two
    // kinds share one `media_type` because the importer files them together;
    // they cannot share a `work_kind`.
    test('film and series round-trip through review.json distinctly', () {
      for (final kind in const [
        WorkKind.animation,
        WorkKind.animationFilm,
        WorkKind.animationSeries
      ]) {
        final row = _resolved(kind);
        final back = ReviewDocument.fromJson(
            jsonDecode(jsonEncode(_document([row]).toJson()))
                as Map<String, dynamic>);
        expect(back.games.single.detection.workKind, kind,
            reason: '${kind.key} read back as something else');
      }
    });

    test('a document written before the answer existed is still an anime', () {
      // There is no installed base (decision 0014), but the legacy spelling
      // is the honest landing place for a row nobody answered rather than a
      // guess at which of the two it was.
      expect(WorkKind.parse('animation', 'work_kind'), WorkKind.animation);
    });

    test('correcting the kind is still what re-routes it', () {
      final row = _resolved(WorkKind.animation);
      row.correctWorkKind(WorkKind.animationSeries);
      expect(row.detection.workKind, WorkKind.animationSeries);
      // The two answers are two different TMDB searches, so a match taken
      // under one is not an answer under the other.
      expect(row.best, isNull);
      expect(row.needsReresolution, isTrue);
    });

    test('answering the kind it already has is a no-op', () {
      final row = _resolved(WorkKind.animationSeries);
      row.correctWorkKind(WorkKind.animationSeries);
      expect(row.best, isNotNull);
    });
  });

  group('the exporter carries an answered row and refuses an unanswered one',
      () {
    test('an anime film is media_type animation, platform_id 0', () {
      expect(_items(_document([_resolved(WorkKind.animationFilm)])).single, {
        'media_type': 'animation',
        'external_id': 770001,
        'platform_id': 0,
      });
    });

    test('an anime series is the same media_type, platform_id 1', () {
      expect(_items(_document([_resolved(WorkKind.animationSeries)])).single, {
        'media_type': 'animation',
        'external_id': 770001,
        'platform_id': 1,
      });
    });

    test('an unanswered anime row is still refused', () {
      final row = _resolved(WorkKind.animation);
      expect(TonkatsuExporter().canExport(row), isFalse);
      expect(_items(_document([row])), isEmpty);
    });

    test('and csv still carries it, so the row is not lost', () {
      expect(
          CsvExporter().select(_document([_resolved(WorkKind.animation)])),
          hasLength(1));
    });

    // The half that moved WITH `_platformId`, and the reason it had to. The
    // comment on `_catalogue` said `null for a kind this target declines
    // anyway`, which stopped being true the moment a row could be answered.
    // Left alone, an answered anime row would have been refused for a second
    // reason wearing the first one's clothes.
    test('an answered anime row is identified by TMDB, not by nothing', () {
      expect(TonkatsuExporter().canExport(_resolved(WorkKind.animationSeries)),
          isTrue);
    });

    test('a games-catalogue id under an anime kind is refused', () {
      // Decision 0016's namespace check: the id must come from the catalogue
      // the kind's `media_type` implies.
      expect(
          TonkatsuExporter().canExport(
              _resolved(WorkKind.animationSeries, externalId: 'igdb:770001')),
          isFalse);
    });
  });
}
