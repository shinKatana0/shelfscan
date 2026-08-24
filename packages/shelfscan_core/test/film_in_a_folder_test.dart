/// A film kept in its own folder (T-0349), which is the ordinary way films are
/// kept and was the one layout the walk read as a game.
///
/// Both halves of that were deliberate. The walk is depth-1 for entries, and
/// the `goggame-*.info` filter under it is what keeps an installed game to one
/// reviewable row; the kind fork is extension-first, and a directory name has
/// no extension, so it never reached the fork. What nobody had decided is what
/// happens when a directory's whole content is one film.
///
/// The rule and the walk are tested in one file on purpose: the rule reads
/// strings and the walk reads a directory, but the claim under test spans them
/// -- a folder holds a film, and a film row reaches review. The counter-claim
/// is in the same file for the same reason, and it is the one that must not
/// move: an installed game still arrives as one row.
library;

import 'dart:convert';
import 'dart:io';

import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

import '../bin/shelfscan.dart'
    show InstalledGameSource, installScope, readInstallDirectory;

/// `goggame-<gameId>.info` reduced to the three keys the source reads (T-0157).
String _info(String name, String id) =>
    jsonEncode({'gameId': id, 'rootGameId': id, 'name': name, 'version': 1});

Directory? _root;

Directory _folder(String name) =>
    Directory('${_root!.path}/$name')..createSync(recursive: true);

void _file(Directory dir, String name, [String content = '']) =>
    File('${dir.path}/$name').writeAsStringSync(content);

/// Every entry of the listing, read by the source `scan-installs` hands it to.
List<SourceReading> _readings() => [
      for (final entry in readInstallDirectory(_root!).entries)
        const InstalledGameSource().read(entry)
    ];

void main() {
  setUp(() => _root = Directory.systemTemp.createTempSync('shelfscan_film_'));
  tearDown(() => _root!.deleteSync(recursive: true));

  group('the rule, over names alone', () {
    test('one film names the folder it is in', () {
      expect(
          videoNamingFolder(
              const ['Harbour.Lantern.2007.1080p.BluRay.x264-MOOR.mkv']),
          'Harbour.Lantern.2007.1080p.BluRay.x264-MOOR.mkv');
    });

    test('what a release folder holds beside the film does not confuse it', () {
      expect(
          videoNamingFolder(const [
            'Pale.Anchor.1994.720p.WEB-DL.h264-MOOR.mp4',
            'Pale.Anchor.1994.720p.WEB-DL.h264-MOOR.srt',
            'sample.mkv',
            'moor.nfo',
          ]),
          'Pale.Anchor.1994.720p.WEB-DL.h264-MOOR.mp4');
    });

    test('a release extracted in place keeps its archives and still names it',
        () {
      // The carrier parts parse as a game through the installer grammar, which
      // is why the block below is on what RUNS and not on what carries.
      expect(
          videoNamingFolder(const [
            'Tidewrack.1998.1080p.BluRay.x264-LANTERN.mkv',
            'Tidewrack.1998.1080p.BluRay.x264-LANTERN.rar',
            'Tidewrack.1998.1080p.BluRay.x264-LANTERN.r00',
          ]),
          'Tidewrack.1998.1080p.BluRay.x264-LANTERN.mkv');
    });

    test('a runnable that names a game stops it -- the mixed folder', () {
      expect(
          videoNamingFolder(const [
            'setup_moor_1.9.exe',
            'Harbour.Lantern.2007.1080p.BluRay.x264-MOOR.mkv',
          ]),
          isNull);
    });

    test('an installed game own launcher stops it too', () {
      expect(
          videoNamingFolder(const [
            'MarlowsGate3.exe',
            'unins000.exe',
            'intro.mkv',
          ]),
          isNull);
    });

    test('two films are as ambiguous as two installers', () {
      expect(
          videoNamingFolder(const [
            'Tidewrack.1998.1080p.BluRay.x264-LANTERN.mkv',
            'Pale.Anchor.1994.720p.WEB-DL.h264-MOOR.mp4',
          ]),
          isNull);
    });

    test('several files of ONE film are one answer, not two', () {
      expect(
          videoNamingFolder(const [
            'Tidewrack.1998.1080p.BluRay.x264-LANTERN.mkv',
            'Tidewrack.1998.720p.BluRay.x264-LANTERN.mp4',
          ]),
          'Tidewrack.1998.1080p.BluRay.x264-LANTERN.mkv');
    });

    test('a folder of episodes hands over one of them', () {
      expect(
          videoNamingFolder(const [
            'Dusk Rail.S01E01.1080p.WEB-DL-MOOR.mkv',
            'Dusk Rail.S01E02.1080p.WEB-DL-MOOR.mkv',
          ]),
          'Dusk Rail.S01E01.1080p.WEB-DL-MOOR.mkv');
    });

    test('a film in the same folder outranks the episodes', () {
      expect(
          videoNamingFolder(const [
            'Dusk Rail.S01E01.1080p.WEB-DL-MOOR.mkv',
            'Tidewrack.1998.1080p.BluRay.x264-LANTERN.mkv',
          ]),
          'Tidewrack.1998.1080p.BluRay.x264-LANTERN.mkv');
    });

    test('video that names neither a film nor an episode answers nothing', () {
      // Deliberately not a decline: the rule fires on evidence a name carries,
      // and a game folder's `intro.mkv` carries none either.
      expect(videoNamingFolder(const ['clip.mkv', 'holiday.mp4']), isNull);
      expect(videoNamingFolder(const []), isNull);
      expect(videoNamingFolder(const ['readme.txt', 'Marlow.pak']), isNull);
    });

    test('the extension is read whatever its case', () {
      expect(
          videoNamingFolder(
              const ['TIDEWRACK.1998.1080P.BLURAY.X264-LANTERN.MKV']),
          'TIDEWRACK.1998.1080P.BLURAY.X264-LANTERN.MKV');
    });
  });

  group('the walk', () {
    test('a film in its own folder reaches review as a film', () {
      final film = _folder('Harbour Lantern (2007) [1080p BluRay]');
      _file(film, 'Harbour.Lantern.2007.1080p.BluRay.x264-MOOR.mkv');

      final item = _readings().single.items.single;

      expect(item.rawTitle, 'Harbour Lantern');
      expect(item.workKind, WorkKind.movie);
      expect(item.sourceYear, 2007);
      // The invented half of the defect: a film is not on `PC`, and the walk
      // was the thing inventing the hint by handing over a directory name.
      expect(item.platformHint, isNull);
    });

    test('the folder own name goes over neither as name nor as container', () {
      final film = _folder('Harbour Lantern (2007) [1080p BluRay]');
      _file(film, 'Harbour.Lantern.2007.1080p.BluRay.x264-MOOR.mkv');

      final entry = readInstallDirectory(_root!).entries.single;

      expect(entry.name, 'Harbour.Lantern.2007.1080p.BluRay.x264-MOOR.mkv');
      expect(entry.container, isNull);
    });

    test('a folder whose name says nothing about a film still yields one', () {
      final film = _folder('Tidewrack');
      _file(film, 'Tidewrack.1998.1080p.BluRay.x264-LANTERN.mkv');

      final item = _readings().single.items.single;

      expect(item.rawTitle, 'Tidewrack');
      expect(item.workKind, WorkKind.movie);
      expect(item.sourceYear, 1998);
    });

    test('the entry is the one a flat folder already produced', () {
      // Why nothing downstream is a new path: the walk hands the same file
      // name over with the same empty container whether the film sits loose in
      // the scanned folder or one level down in its own. T-0344 measured the
      // flat side end to end; this change makes the nested side reach it.
      const film = 'Tidewrack.1998.1080p.BluRay.x264-LANTERN.mkv';
      _file(_root!, film);
      final flat = readInstallDirectory(_root!).entries.single;
      File('${_root!.path}/$film').deleteSync();
      _file(_folder('Tidewrack (1998)'), film);
      final nested = readInstallDirectory(_root!).entries.single;

      expect(nested.name, flat.name);
      expect(nested.container, flat.container);
    });

    test('a series folder is one honest decline, not a game row', () {
      final series = _folder('Dusk Rail');
      for (var i = 1; i <= 3; i++) {
        _file(series, 'Dusk Rail.S01E0$i.1080p.WEB-DL-MOOR.mkv');
      }

      final reading = _readings().single;

      expect(reading.items, isEmpty);
      expect(reading.declined.single.reason, DeclineReason.seriesEpisode);
    });

    test('a folder holding an installer AND a film stays a game folder', () {
      final mixed = _folder('Moor');
      _file(mixed, 'setup_moor_1.9.exe');
      _file(mixed, 'Harbour.Lantern.2007.1080p.BluRay.x264-MOOR.mkv');

      final item = _readings().single.items.single;

      expect(item.rawTitle, 'Moor');
      expect(item.workKind, WorkKind.game);
    });

    test('a GoG install is untouched by a film file beside it', () {
      final game = _folder('Moor');
      _file(game, 'goggame-1100000002.info', _info('MOOR', '1100000002'));
      _file(game, 'Harbour.Lantern.2007.1080p.BluRay.x264-MOOR.mkv');

      final listing = readInstallDirectory(_root!);

      expect(listing.entries.map((e) => e.name),
          ['Moor', 'goggame-1100000002.info']);
      expect(listing.videoNamed, 0);
    });

    test('the summary line names the folders read under a video name', () {
      final film = _folder('Tidewrack');
      _file(film, 'Tidewrack.1998.1080p.BluRay.x264-LANTERN.mkv');

      final listing = readInstallDirectory(_root!);

      expect(listing.videoNamed, 1);
      expect(installScope(listing),
          contains('1 folder(s) read under a video name inside them'));
      expect(installScope(listing), isNot(contains('installer name')));
    });
  });

  group('the guarantee the second-level filter exists for', () {
    test('an installed game is still exactly one reviewable row', () {
      final game = _folder('Marlows Gate 3');
      for (final name in const [
        'MarlowsGate3.exe',
        'unins000.exe',
        'crack.exe',
        'moorengine64.dll',
        'lanternaudio.dll',
        'physcore.dll',
        'Marlow.pak',
        'Content.pak',
        'intro.mkv',
        'logo.mkv',
        'readme.txt',
      ]) {
        _file(game, name);
      }
      Directory('${game.path}/Data/Localization').createSync(recursive: true);

      final listing = readInstallDirectory(_root!);

      expect(listing.entries.length, 1);
      expect(listing.entries.single.name, 'Marlows Gate 3');
      expect(listing.videoNamed, 0);
      expect(_readings().single.items.single.workKind, WorkKind.game);
    });

    test('one entry per subdirectory, whichever name the entry took', () {
      _file(_folder('Tidewrack'),
          'Tidewrack.1998.1080p.BluRay.x264-LANTERN.mkv');
      _file(_folder('Dusk Rail'), 'Dusk Rail.S01E01.1080p.WEB-DL-MOOR.mkv');
      _file(_folder('New Folder'), 'setup_harbour_lantern_1.6.15.exe');
      _file(_folder('Marlows Gate 3'), 'MarlowsGate3.exe');
      _file(_folder('Clips'), 'clip.mkv');

      final listing = readInstallDirectory(_root!);

      expect(listing.gameDirectories, 5);
      expect(listing.entries.length, 5);
    });
  });
}
