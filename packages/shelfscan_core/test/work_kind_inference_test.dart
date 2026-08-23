/// The kind of work a disk entry is a copy of, inferred from its name
/// (T-0162, decision 0015).
///
/// A disk source has no prompt, so nothing tells it what it is looking at: the
/// extension narrows the entry and the grammar of the name settles it, and a
/// name that settles neither declines. These tests are that rule, and the
/// third group is the one that matters most -- one folder holding all three
/// shapes at once, which is what a real download directory is.
///
/// **Every name here is invented** (`doc/conventions.md` §3b). None is off any
/// disk, and the films are not films: a title that resolves against a real
/// catalogue would make this a test of TMDB rather than of the parser.
library;

import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

SourceReading _read(String name, {String? container}) =>
    const FilenameSource().read(SourceEntry(
      name: name,
      container: container,
      content: '',
    ));

Detection _row(String name, {String? container}) {
  final reading = _read(name, container: container);
  expect(reading.items, hasLength(1),
      reason: '$name should have produced exactly one row, and declined '
          '${reading.declined.map((d) => d.reason)}');
  return reading.items.single;
}

String _decline(String name, {String? container}) {
  final reading = _read(name, container: container);
  expect(reading.items, isEmpty,
      reason: '$name should have produced no row, and produced '
          '${reading.items.map((i) => i.rawTitle)}');
  return reading.declined.single.reason;
}

void main() {
  group('the extension narrows the kind', () {
    test('an installer is a game, which is what it was before films existed',
        () {
      final row = _row('setup_harbour_lantern_1.6.15_(45683).exe');
      expect(row.workKind, WorkKind.game);
      expect(row.rawTitle, 'harbour lantern');
    });

    test('a release-named video is a film', () {
      final row = _row('The.Glasshouse.Verdict.1999.1080p.BluRay.x264-GROUP.mkv');
      expect(row.workKind, WorkKind.movie);
      expect(row.rawTitle, 'The Glasshouse Verdict');
      expect(row.sourceYear, 1999);
    });

    test('every video container reaches the film grammar, not just .mkv', () {
      for (final extension in ['mkv', 'mp4', 'avi', 'm4v', 'webm']) {
        final row = _row('Tidewrack.Lament.2004.720p.WEBRip.x265.$extension');
        expect(row.workKind, WorkKind.movie, reason: extension);
        expect(row.rawTitle, 'Tidewrack Lament', reason: extension);
      }
    });

    test('audio is still never a row, which is the half that did not move', () {
      expect(_decline('Tidewrack.Lament.2004.320kbps.mp3'),
          DeclineReason.notAGameFile);
    });
  });

  group('the grammar settles what the extension left open', () {
    test('a year alone marks a film', () {
      final row = _row('Pale Anchor 1987.mkv');
      expect(row.workKind, WorkKind.movie);
      expect(row.rawTitle, 'Pale Anchor');
      expect(row.sourceYear, 1987);
    });

    test('a resolution alone marks a film, with no year to carry', () {
      final row = _row('Pale.Anchor.1080p.BluRay.mkv');
      expect(row.workKind, WorkKind.movie);
      expect(row.rawTitle, 'Pale Anchor');
      expect(row.sourceYear, isNull);
    });

    test('the LAST year is the release year, not the first', () {
      // A title may end in a number that reads as a year. Taking the first
      // truncates the title; this is the whole reason the film grammar cuts
      // differently from the installer one.
      final row = _row('Harbour Lantern 2049 2017 1080p BluRay x264-GROUP.mkv');
      expect(row.rawTitle, 'Harbour Lantern 2049');
      expect(row.sourceYear, 2017);
    });

    test('a title year with nothing after it stays in the title', () {
      final row = _row('Pale Anchor 2049 1080p.mkv');
      expect(row.rawTitle, 'Pale Anchor 2049');
      expect(row.sourceYear, isNull);
    });

    test('a bracketed year is read where the grammar is not scene-shaped', () {
      final row = _row('Pale Anchor (1987).mkv');
      expect(row.workKind, WorkKind.movie);
      expect(row.sourceYear, 1987);
    });
  });

  group('a film carries no platform, and that is not the same as PC', () {
    test('the hint is null rather than the filename default', () {
      expect(_row('Pale.Anchor.1987.1080p.BluRay.mkv').platformHint, isNull);
      expect(_row('setup_pale_anchor_1.2.3.exe').platformHint,
          filenamePlatformHint);
    });
  });

  group('a series episode is not a film, and declines', () {
    test('the season/episode shape', () {
      expect(_decline('Tidewrack.Lament.S01E04.1080p.WEB-DL.mkv'),
          DeclineReason.seriesEpisode);
      expect(_decline('Tidewrack Lament 1x04 720p.mkv'),
          DeclineReason.seriesEpisode);
    });

    test('the spelt-out shape', () {
      expect(_decline('Tidewrack Lament Season 2 1080p.mkv'),
          DeclineReason.seriesEpisode);
    });

    test('the fansub shape, which is the one with a bare episode number', () {
      expect(_decline('[SubGroup] Tidewrack Lament - 04 [1080p].mkv'),
          DeclineReason.seriesEpisode);
    });

    test('a spaced hyphen before a number is NOT an episode on its own', () {
      // The guard on the fansub rule. Without it a film with a numeric
      // subtitle is lost to a rule written for a series, which is the
      // silent-failure class this project refuses.
      final row = _row('Pale Anchor - 2 1999 1080p BluRay.mkv');
      expect(row.workKind, WorkKind.movie);
      expect(row.sourceYear, 1999);
    });
  });

  group('where nothing settles the kind, the source declines', () {
    test('a video with neither a year nor a resolution', () {
      expect(_decline('Kitchen renovation.mkv'), DeclineReason.noWorkKind);
    });

    test('a bare word', () {
      expect(_decline('clip.mp4'), DeclineReason.noWorkKind);
    });

    test('the decline is an exclusion, not a failure', () {
      // Nothing broke: a name was read and held nothing this collection
      // wants. The class is what the review screen groups warnings by.
      final reading = _read('Kitchen renovation.mkv');
      expect(reading.declined.single.severity, Severity.exclusion);
    });
  });

  group('one folder, three shapes -- the case a per-run mode cannot read', () {
    // Decision 0015's argument for the row property, as a test: a real
    // download directory is mixed, and a mode would have to scan it once per
    // kind and discard most of each pass.
    const folder = [
      'setup_harbour_lantern_1.6.15_(45683).exe',
      'The.Glasshouse.Verdict.1999.1080p.BluRay.x264-GROUP.mkv',
      'Kitchen renovation.mkv',
    ];

    test('one pass reads the game and the film and declines the third', () {
      final kinds = <WorkKind>[];
      final declined = <String>[];
      for (final name in folder) {
        final reading = _read(name);
        kinds.addAll(reading.items.map((i) => i.workKind));
        declined.addAll(reading.declined.map((d) => d.reason));
      }

      expect(kinds, [WorkKind.game, WorkKind.movie]);
      expect(declined, [DeclineReason.noWorkKind]);
    });

    test('the kind is on the ROW, so the two rows disagree within one run', () {
      final rows = [for (final name in folder.take(2)) _row(name)];
      expect(rows.map((r) => r.workKind).toSet(), hasLength(2));
    });
  });

  group('the inference never guesses', () {
    test('no video name produces a kind without a marker for it', () {
      // The property, not an instance of it: for a name carrying neither
      // marker there is no input that yields a row.
      for (final name in [
        'holiday.mkv',
        'Untitled.mp4',
        'render final v2.avi',
        'cutscene intro.mkv',
      ]) {
        expect(_read(name).items, isEmpty, reason: name);
      }
    });
  });
}
