/// What the shell hands the pipeline for one chosen folder (T-0161).
///
/// Against real directories rather than a mocked filesystem: the thing under
/// test IS the walk, and the two shapes the GoG group is for -- a folder of
/// installers and a folder of installed games -- differ only in what is on
/// disk.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shelfscan_app/media_folders.dart';
import 'package:shelfscan_core/shelfscan_core.dart';

late Directory _root;

String _dir(String name) {
  final directory = Directory('${_root.path}${Platform.pathSeparator}$name')
    ..createSync(recursive: true);
  return directory.path;
}

void _file(String name, [String content = '']) {
  File('${_root.path}${Platform.pathSeparator}$name')
    ..createSync(recursive: true)
    ..writeAsStringSync(content);
}

String _gogInfo(String name, String id) =>
    '{"gameId": "$id", "rootGameId": "$id", "name": "$name"}';

/// Every entry of the chosen folder, read by the source the app hands it to.
Future<List<SourceReading>> _readings() async => [
      for (final entry in (await readMediaFolder(_root.path)).entries)
        const InstalledGameSource().read(entry)
    ];

void main() {
  setUp(() => _root = Directory.systemTemp.createTempSync('shelfscan_folder'));
  tearDown(() => _root.deleteSync(recursive: true));

  group('what one folder hands over', () {
    test('a folder of installers is one entry per file', () async {
      _file('setup_moor_1.9_(21474).exe');
      _file('Marlows.Gate.3.GOG.zip');
      _file('notes.txt');

      final folder = await readMediaFolder(_root.path);

      expect(folder.path, _root.path);
      expect(folder.name, folderName(_root.path));
      expect([for (final entry in folder.entries) entry.name], [
        'Marlows.Gate.3.GOG.zip',
        'notes.txt',
        'setup_moor_1.9_(21474).exe',
      ]);
      // Not the chosen folder: a container is read as a title when the entry's
      // own name carries none, and this one names the collection (T-0193).
      expect(folder.entries.every((e) => e.container == null), isTrue);
      expect(folder.entries.every((e) => e.content == null), isTrue);
    });

    test('an installed GoG game is its metadata, not its file tree', () async {
      _dir('Harbour Lantern/Screenshots');
      _dir('Harbour Lantern/data');
      _file('Harbour Lantern/goggame-1100000001.info',
          _gogInfo('Harbour Lantern', '1100000001'));
      _file('Harbour Lantern/unins000.exe');

      final folder = await readMediaFolder(_root.path);

      expect([for (final entry in folder.entries) entry.name],
          ['goggame-1100000001.info']);
      expect(folder.entries.single.container, 'Harbour Lantern');
      expect(folder.entries.single.content, contains('Harbour Lantern'));
    });

    test('a game folder with no metadata is handed over by its own name',
        () async {
      _dir('Dusk-Rail 2/bin');
      _file('Dusk-Rail 2/hbl2.exe');

      final folder = await readMediaFolder(_root.path);

      expect([for (final entry in folder.entries) entry.name], ['Dusk-Rail 2']);
      expect(folder.entries.single.container, isNull);
    });

    test('the walk stops one level down', () async {
      for (var i = 0; i < 40; i++) {
        _file('Dusk-Rail 2/bin/module$i.dll');
      }

      final folder = await readMediaFolder(_root.path);

      // 41 files are on disk under it and the folder is one entry: at depth 2
      // every one of them would be a DeclinedEntry on the review screen.
      expect(folder.entries.length, 1);
    });

    test('the chosen folder being one game is read as that game', () async {
      _dir('Screenshots');
      _dir('Saves');
      _file('goggame-1100000014.info', _gogInfo('Ombra 4', '1100000014'));

      final folder = await readMediaFolder(_root.path);

      expect([for (final entry in folder.entries) entry.name],
          ['goggame-1100000014.info']);
    });

    test('a DLC manifest beside the base game is handed over too', () async {
      _file('Astralane/goggame-1100000007.info',
          _gogInfo('Astralane', '1100000007'));
      _file('Astralane/goggame-1100000006.info',
          '{"gameId": "1100000006", "rootGameId": "1100000007", '
              '"name": "Astralane: Pre-Order Bonus"}');

      final folder = await readMediaFolder(_root.path);

      expect(folder.entries.length, 2);
      // The DLC is core's to decline (GogMetadataSource.dlcNotAGame); the
      // shell may not read a rootGameId to decide what to hand over.
      const source = InstalledGameSource();
      final readings = [for (final e in folder.entries) source.read(e)];
      expect([for (final r in readings) ...r.items].length, 1);
      expect([for (final r in readings) ...r.declined].single.reason,
          GogMetadataSource.dlcNotAGame);
    });

    test('a folder its own name cannot title is read by the installer in it',
        () async {
      _file('New Folder/setup_harbour_lantern_1.6.15.exe');
      _file('New Folder/setup_harbour_lantern_1.6.15-1.bin');

      final folder = await readMediaFolder(_root.path);

      expect([for (final entry in folder.entries) entry.name],
          ['setup_harbour_lantern_1.6.15.exe']);
      // The directory it sits in, not the chosen folder: that is where the
      // file is, and the name that failed to title it is now spent.
      expect(folder.entries.single.container, 'New Folder');
      expect(const InstalledGameSource().read(folder.entries.single).items
          .single.rawTitle, 'harbour lantern');
    });

    test('and it is still one entry, whatever the folder holds', () async {
      for (var i = 0; i < 40; i++) {
        _file('New Folder/setup_game${i}_1.0.exe');
      }
      _file('Screenshots/Screenshot 1.png');

      final folder = await readMediaFolder(_root.path);

      expect([for (final entry in folder.entries) entry.name],
          ['New Folder', 'Screenshots']);
    });

    test('a folder that names a game keeps it when the file agrees', () async {
      _file('Harbour Lantern/Harbour Lantern.exe');

      final folder = await readMediaFolder(_root.path);

      expect([for (final entry in folder.entries) entry.name],
          ['Harbour Lantern']);
    });

    test('a folder name an installer contradicts outright loses it (T-0183)',
        () async {
      // T-0178 kept `Harbour Lantern` here. Its rule could only give up a folder
      // name that the English `_genericNames` listed, and a Russian-locale Windows
      // names a new folder `Новая папка` -- so the folder won and the game one
      // file away was never read. Driven in core by `installer_naming_test`;
      // this pins that the app's walk asks the same question.
      _file('Harbour Lantern/setup_tulip_hospital_2.1.0.9.exe');
      _file('Новая папка/setup_iron_march_2_ultimate_2.1.0.4.exe');

      final folder = await readMediaFolder(_root.path);

      expect([for (final entry in folder.entries) entry.name], [
        'setup_tulip_hospital_2.1.0.9.exe',
        'setup_iron_march_2_ultimate_2.1.0.4.exe',
      ]);
    });

    test('a GoG install never reaches the installer inside it', () async {
      _file('New Folder/goggame-1100000001.info',
          _gogInfo('Harbour Lantern', '1100000001'));
      _file('New Folder/setup_tulip_hospital_2.1.0.9.exe');

      final folder = await readMediaFolder(_root.path);

      expect([for (final entry in folder.entries) entry.name],
          ['goggame-1100000001.info']);
      expect(folder.entries.single.content, contains('Harbour Lantern'));
    });

    test('an empty folder hands over nothing and does not throw', () async {
      final folder = await readMediaFolder(_root.path);
      expect(folder.entries, isEmpty);
    });
  });

  group('the folder the user pointed at is not a game (T-0193)', () {
    // Scanned under a name of its own rather than the `shelfscan_folder<n>`
    // temp directory the group above uses: a borrowed title has to be
    // recognisable as the chosen folder's when it appears.
    Future<MediaFolder> chosen() => readMediaFolder(_dir('Downloaded games'));

    test('a subdirectory that titles nothing borrows nothing', () async {
      _dir('Downloaded games/New Folder');
      _dir('Downloaded games/Saves');
      _dir('Downloaded games/Screenshots');

      final folder = await chosen();

      expect([for (final entry in folder.entries) entry.name],
          ['New Folder', 'Saves', 'Screenshots']);
      expect(folder.entries.every((e) => e.container == null), isTrue);
    });

    test('so three of them are three declines, not one plausible row',
        () async {
      _dir('Downloaded games/New Folder');
      _dir('Downloaded games/Saves');
      _dir('Downloaded games/Screenshots');

      final folder = await chosen();
      final doc = await Orchestrator.resolveOnly(resolverWorker: SkipResolver())
          .runScan(const [],
              sources: [SourceRun(const InstalledGameSource(), folder.entries)]);

      // The defect this closes is the merge, not the row: all three took the
      // same borrowed title, so stage 2 folded them into ONE row reading like
      // a game nobody owns (measured 2026-08-16).
      expect(doc.games, isEmpty);
      expect([for (final e in doc.declinedEntries) e.name],
          ['New Folder', 'Saves', 'Screenshots']);
    });

    test('and a game one level down still keeps the folder it is in',
        () async {
      _file('Downloaded games/New Folder/setup_harbour_lantern_1.6.15.exe');
      _dir('Downloaded games/Screenshots');

      final folder = await chosen();

      expect([for (final entry in folder.entries) entry.name],
          ['setup_harbour_lantern_1.6.15.exe', 'Screenshots']);
      expect(folder.entries.first.container, 'New Folder');
    });
  });

  /// The app's half of T-0349, whose Scope was `packages/` (T-0352).
  ///
  /// Driven in core by `film_in_a_folder_test`, which owns the rule itself;
  /// these pin that the app's walk asks the same question in the same order,
  /// because the CLI being right and the product wrong is the shell a person
  /// never uses being the correct one.
  group('a film in its own folder (T-0352)', () {
    test('reaches review as a film, not as a game named after the folder',
        () async {
      _file('Harbour Lantern (2007) [1080p BluRay]/'
          'Harbour.Lantern.2007.1080p.BluRay.x264-MOOR.mkv');

      final item = (await _readings()).single.items.single;

      expect(item.rawTitle, 'Harbour Lantern');
      expect(item.workKind, WorkKind.movie);
      expect(item.sourceYear, 2007);
      // The invented half of the defect: a film is not on `PC`, and the walk
      // was the thing inventing the hint by handing over a directory name.
      expect(item.platformHint, isNull);
    });

    test('and the folder own name goes over as neither name nor container',
        () async {
      _file('Harbour Lantern (2007) [1080p BluRay]/'
          'Harbour.Lantern.2007.1080p.BluRay.x264-MOOR.mkv');

      final entry = (await readMediaFolder(_root.path)).entries.single;

      expect(entry.name, 'Harbour.Lantern.2007.1080p.BluRay.x264-MOOR.mkv');
      expect(entry.container, isNull);
    });

    test('a folder whose own name says nothing about a film still yields one',
        () async {
      _file('Tidewrack/Tidewrack.1998.1080p.BluRay.x264-LANTERN.mkv');

      final item = (await _readings()).single.items.single;

      expect(item.rawTitle, 'Tidewrack');
      expect(item.workKind, WorkKind.movie);
      // The year is the part the folder name could not have given.
      expect(item.sourceYear, 1998);
    });

    test('the entry is the one a loose film file already produced', () async {
      // Why nothing downstream is a new path: the same file name with the same
      // empty container, whether the film sits loose in the chosen folder or
      // one level down in its own.
      const film = 'Tidewrack.1998.1080p.BluRay.x264-LANTERN.mkv';
      _file(film);
      final flat = (await readMediaFolder(_root.path)).entries.single;
      File('${_root.path}${Platform.pathSeparator}$film').deleteSync();
      _file('Tidewrack (1998)/$film');
      final nested = (await readMediaFolder(_root.path)).entries.single;

      expect(nested.name, flat.name);
      expect(nested.container, flat.container);
    });

    test('a series folder is one honest decline, not a game row', () async {
      for (var i = 1; i <= 3; i++) {
        _file('Dusk Rail/Dusk Rail.S01E0$i.1080p.WEB-DL-MOOR.mkv');
      }

      final reading = (await _readings()).single;

      expect(reading.items, isEmpty);
      expect(reading.declined.single.reason, DeclineReason.seriesEpisode);
    });

    test('a folder holding an installer AND a film stays a game folder',
        () async {
      // The one entry per subdirectory cannot be two works, so the folder
      // keeps the reading it had and the film in it is lost -- the cost
      // T-0349 stated rather than paid for by breaking the budget.
      _file('Moor/setup_moor_1.9.exe');
      _file('Moor/Harbour.Lantern.2007.1080p.BluRay.x264-MOOR.mkv');

      final item = (await _readings()).single.items.single;

      expect(item.rawTitle, 'Moor');
      expect(item.workKind, WorkKind.game);
    });

    test('two films are as ambiguous as two installers', () async {
      _file('Films/Tidewrack.1998.1080p.BluRay.x264-LANTERN.mkv');
      _file('Films/Pale.Anchor.1994.720p.WEB-DL.h264-MOOR.mp4');

      final entry = (await readMediaFolder(_root.path)).entries.single;

      expect(entry.name, 'Films');
    });

    test('a release extracted in place is the film, not the archive beside it',
        () async {
      // Which of the two questions is asked first is observable here, and this
      // is the shape that makes it so: the `.rar` parts parse as a game
      // through the installer grammar, and the folder's own name titles
      // nothing, so asking the installer first hands the folder over under a
      // carrier's name and loses the kind.
      _file('New Folder/Tidewrack.1998.1080p.BluRay.x264-LANTERN.mkv');
      _file('New Folder/Tidewrack.1998.1080p.BluRay.x264-LANTERN.rar');
      _file('New Folder/Tidewrack.1998.1080p.BluRay.x264-LANTERN.r00');

      final item = (await _readings()).single.items.single;

      expect(item.workKind, WorkKind.movie);
      expect(item.sourceYear, 1998);
    });

    test('a folder of video naming neither a film nor an episode is unchanged',
        () async {
      // Deliberate: firing on the mere PRESENCE of video rather than on
      // evidence a name carries would turn a game folder whose only
      // recognisable file is an `intro.mkv` into a decline.
      _file('Clips/clip.mkv');
      _file('Clips/holiday.mp4');

      final entry = (await readMediaFolder(_root.path)).entries.single;

      expect(entry.name, 'Clips');
    });

    test('a GoG install is untouched by a film file beside it', () async {
      _file('Moor/goggame-1100000002.info', _gogInfo('MOOR', '1100000002'));
      _file('Moor/Harbour.Lantern.2007.1080p.BluRay.x264-MOOR.mkv');

      final folder = await readMediaFolder(_root.path);

      expect([for (final entry in folder.entries) entry.name],
          ['goggame-1100000002.info']);
    });
  });

  group('the guarantee the goggame-*.info filter exists for', () {
    test('an installed game is still exactly one reviewable row', () async {
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
        _file('Marlows Gate 3/$name');
      }
      _dir('Marlows Gate 3/Data/Localization');

      final folder = await readMediaFolder(_root.path);

      expect(folder.entries.length, 1);
      expect(folder.entries.single.name, 'Marlows Gate 3');
      expect((await _readings()).single.items.single.workKind, WorkKind.game);
    });

    test('one entry per subdirectory, whichever name the entry took', () async {
      _file('Tidewrack/Tidewrack.1998.1080p.BluRay.x264-LANTERN.mkv');
      _file('Dusk Rail/Dusk Rail.S01E01.1080p.WEB-DL-MOOR.mkv');
      _file('New Folder/setup_harbour_lantern_1.6.15.exe');
      _file('Marlows Gate 3/MarlowsGate3.exe');
      _file('Clips/clip.mkv');

      final folder = await readMediaFolder(_root.path);

      // The budget alone, so that widening the rule fails HERE and changing
      // which name an entry took does not: five subdirectories, five entries,
      // whether each went over under its own name, an installer's or a film's.
      expect(folder.entries.length, 5);
    });
  });

  group('which source reads which entry', () {
    const source = InstalledGameSource();

    test('metadata wins its own file, and its decline is not overwritten', () {
      final reading = source.read(const SourceEntry(
          name: 'goggame-1100000001.info',
          container: 'Harbour Lantern',
          content: 'not json at all'));

      // FilenameSource would answer `not a game file` about the same entry --
      // the reason it declines a `.info` on purpose (T-0158).
      expect(reading.items, isEmpty);
      expect(reading.declined.single.reason, GogMetadataSource.notJson);
    });

    test('a metadata row carries the store id and the publisher title', () {
      final reading = source.read(SourceEntry(
          name: 'goggame-1100000001.info',
          container: 'Harbour Lantern',
          content: _gogInfo('Harbour Lantern', '1100000001')));

      final item = reading.items.single;
      expect(item.rawTitle, 'Harbour Lantern');
      expect(item.sourceId, '${GogMetadataSource.idPrefix}1100000001');
      expect(item.origin, DetectionOrigin.metadata);
      expect(item.origin.isAuthoritative, isTrue);
    });

    test('everything else is the filename source', () {
      final reading = source.read(const SourceEntry(
          name: 'setup_moor_1.9_(21474).exe', container: 'Games'));

      expect(reading.items.single.rawTitle, 'moor');
      expect(reading.items.single.origin, DetectionOrigin.filename);
    });
  });

  group('the folder the user did not mean', () {
    test('a downloads folder is questioned, citing what it reads instead', () {
      final concern = folderConcern(r'C:\Users\someone\Downloads');
      expect(concern, isNotNull);
      expect(concern, contains('Downloads is where files land'));
      expect(concern, contains('not one of them is a game'));
      expect(concern, contains('T-0158'));
    });

    test('the personal and system folders are all questioned', () {
      for (final name in const [
        'Downloads',
        'Desktop',
        'Documents',
        'Pictures',
        'Music',
        'Videos',
        'OneDrive',
        'AppData',
        'Temp',
        'Program Files',
        'Program Files (x86)',
        'Windows',
        'Users',
      ]) {
        expect(folderConcern('C:/x/$name'), isNotNull, reason: name);
      }
    });

    test('a drive root is questioned as the whole drive', () {
      expect(folderConcern(r'C:\'), contains('the whole of C:'));
      expect(folderConcern('/'), isNotNull);
    });

    test('a games folder is not questioned', () {
      expect(folderConcern(r'C:\GOG Games'), isNull);
      expect(folderConcern(r'C:\Users\someone\Games\Harbour Lantern'), isNull);
      // Trailing separator included: it is what a root looks like otherwise.
      expect(folderConcern('C:/GOG Games/'), isNull);
    });

    test('the check is on the last segment, not on the path', () {
      expect(folderConcern(r'C:\Downloads\GOG Games'), isNull);
    });

    test('the warning names every kind the control above it offers', () {
      for (final concern in [
        folderConcern(r'C:\Users\someone\Downloads')!,
        folderConcern(r'C:\')!,
      ]) {
        expect(concern, contains('read by name, subdirectories included'));
        expect(concern, contains('a film can come back as a game'));
        expect(concern, contains('an application as either'));
        expect(concern, contains('Review every row'));
      }
    });

    test('and no longer promises that every entry is read as a game', () {
      expect(folderConcern(r'C:\'),
          isNot(contains('read as the name of a game')));
      expect(folderConcern(r'C:\Users\someone\Downloads'),
          isNot(contains('where games are installed')));
    });

    // The distinction T-0351 exists for: T-0158 measured a Downloads folder
    // against an application installer, and nothing else. That a film comes
    // back as a game is T-0162's third way for a name to be read wrong and
    // carries no rate, so the citation stays behind the measured sentence
    // rather than in front of both.
    test('the T-0158 citation stays on the sentence T-0158 measured', () {
      const measured = 'not one of them is a game -- it reads '
          'NoteWellSetup.exe exactly as it reads setup_moor_1.9.exe (T-0158)';
      final concern = folderConcern(r'C:\Users\someone\Downloads')!;

      expect(concern, contains(measured));
      expect('(T-0158)'.allMatches(concern).length, 1);
      expect(concern.indexOf('a film can come back as a game'),
          lessThan(concern.indexOf(measured)));
    });
  });
}
