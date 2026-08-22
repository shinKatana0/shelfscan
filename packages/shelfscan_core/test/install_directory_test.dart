/// Guards `scan-installs`: the CLI half of the GoG group (T-0160).
///
/// Three claims are worth pinning, and none of them is about parsing -- both
/// sources are settled and tested elsewhere (T-0157, T-0158):
///   1. WHAT reaches core. A games folder is walked one level down and no
///      further, and inside a game's own folder only `goggame-*.info` is read;
///      everything else in there would be a decline to group or a row to
///      reject.
///   2. WHICH source reads what. The hand-over is a single decline reason, so
///      no entry is ever a row from one source and a named decline from the
///      other.
///   3. That the result is the same review document a photo scan writes, all
///      the way through `resolve` and `export`.
///
/// Nothing here touches the network: every run is built on
/// [Orchestrator.resolveOnly], which holds no vision worker at all, plus
/// [SkipResolver], whose http client throws on any request.
library;

import 'dart:convert';
import 'dart:io';

import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

import '../bin/shelfscan.dart'
    show
        InstallDirectory,
        InstalledGameSource,
        declinedReport,
        gamesFolderError,
        installScope,
        installsPathError,
        notAGamesFolder,
        readInstallDirectory;

/// `goggame-<gameId>.info` as GoG's installer writes it, reduced to the three
/// keys the source reads (T-0157).
String _info(String name, String id) =>
    jsonEncode({'gameId': id, 'rootGameId': id, 'name': name, 'version': 1});

Directory _folder(String name, [Directory? parent]) {
  final dir = Directory('${(parent ?? _root!).path}/$name')
    ..createSync(recursive: true);
  return dir;
}

void _file(Directory dir, String name, [String content = '']) =>
    File('${dir.path}/$name').writeAsStringSync(content);

Directory? _root;

/// The document a `scan-installs` run writes, built exactly as `_installs`
/// builds it.
Future<ReviewDocument> _run(InstallDirectory listing) =>
    Orchestrator.resolveOnly(resolverWorker: SkipResolver()).runScan(
      const [],
      sources: [SourceRun(const InstalledGameSource(), listing.entries)],
    );

void main() {
  setUp(() => _root = Directory.systemTemp.createTempSync('shelfscan_games_'));
  tearDown(() => _root!.deleteSync(recursive: true));

  group('what reaches core', () {
    test('the folder\'s own files and each subdirectory, by name', () {
      _file(_root!, 'setup_harbour_lantern_1.6.15.exe');
      _folder('Marlows Gate 3');

      final listing = readInstallDirectory(_root!);

      expect(listing.entries.map((e) => e.name),
          ['Marlows Gate 3', 'setup_harbour_lantern_1.6.15.exe']);
      expect(listing.gameDirectories, 1);
      expect(listing.looseFiles, 1);
      expect(listing.metadataFiles, 0);
      // Not the scanned directory's name: a container is read as a title when
      // the entry's own name carries none, and this one names the collection
      // (T-0193).
      expect(listing.entries.map((e) => e.container).toSet(), {null});
    });

    test('a goggame-*.info one level down is read, with its text', () {
      final game = _folder('Moor');
      _file(game, 'goggame-1100000002.info', _info('MOOR', '1100000002'));

      final listing = readInstallDirectory(_root!);
      final metadata =
          listing.entries.singleWhere((e) => e.content != null);

      expect(metadata.name, 'goggame-1100000002.info');
      expect(metadata.container, 'Moor');
      expect(jsonDecode(metadata.content!), containsPair('name', 'MOOR'));
      expect(listing.metadataFiles, 1);
    });

    test('nothing else inside a game folder is enumerated', () {
      final game = _folder('Moor');
      _file(game, 'goggame-1100000002.info', _info('MOOR', '1100000002'));
      _file(game, 'MOORx64.exe');
      _file(game, 'unins000.exe');
      _file(game, 'gog.ico');
      _file(game, 'goggame-1100000002.hashdb');

      final listing = readInstallDirectory(_root!);

      expect(listing.entries.map((e) => e.name),
          ['Moor', 'goggame-1100000002.info']);
    });

    test('the walk stops at one level: a data subtree never reaches core', () {
      final game = _folder('Marlows Gate 3');
      final data = _folder('Data', game);
      _file(data, 'Marlow.pak');
      _file(data, 'goggame-9999999999.info', _info('Not A Game', '9999999999'));
      _file(_folder('Localization', data), 'English.pak');

      final listing = readInstallDirectory(_root!);

      expect(listing.entries.map((e) => e.name), ['Marlows Gate 3']);
      expect(listing.entries.single.content, isNull);
    });

    test('listing order is the sort order, so a re-run reads the same', () {
      _file(_root!, 'setup_zork_1.0.exe');
      _file(_root!, 'setup_arcanum_1.0.exe');
      _folder('Ashenmoor');

      expect(readInstallDirectory(_root!).entries.map((e) => e.name),
          readInstallDirectory(_root!).entries.map((e) => e.name));
      expect(readInstallDirectory(_root!).entries.map((e) => e.name),
          ['Ashenmoor', 'setup_arcanum_1.0.exe', 'setup_zork_1.0.exe']);
    });

    test('an empty directory yields no entry, which the command exits on', () {
      expect(readInstallDirectory(_root!).entries, isEmpty);
    });
  });

  group('which source reads what', () {
    test('metadata claims the .info and carries the GoG product id', () {
      final reading = const InstalledGameSource().read(SourceEntry(
        name: 'goggame-1100000001.info',
        container: 'Tulip Hospital',
        content: _info('Tulip Hospital', '1100000001'),
      ));

      expect(reading.declined, isEmpty);
      expect(reading.items.single.rawTitle, 'Tulip Hospital');
      expect(reading.items.single.origin, DetectionOrigin.metadata);
      expect(reading.items.single.sourceId, 'gog:1100000001');
    });

    test('an entry with no metadata falls through to the file name', () {
      final reading = const InstalledGameSource()
          .read(const SourceEntry(name: 'Marlows Gate 3', container: 'Games'));

      expect(reading.declined, isEmpty);
      expect(reading.items.single.rawTitle, 'Marlows Gate 3');
      expect(reading.items.single.origin, DetectionOrigin.filename);
    });

    test('a BROKEN .info keeps its own reason and is not re-read as a name',
        () {
      final reading = const InstalledGameSource().read(const SourceEntry(
        name: 'goggame-1100000001.info',
        container: 'Tulip Hospital',
        content: '{ "gameId": ',
      ));

      expect(reading.items, isEmpty);
      expect(reading.declined.single.reason, GogMetadataSource.notJson);
      expect(reading.declined.single.reason, isNot(DeclineReason.notAGameFile));
    });

    test('DLC metadata is declined by the source that read it', () {
      final reading = const InstalledGameSource().read(SourceEntry(
        name: 'goggame-1100000006.info',
        container: 'Astralane',
        content: jsonEncode({
          'gameId': '1100000006',
          'rootGameId': '1100000007',
          'name': 'Astralane - Pre-order Bonus',
        }),
      ));

      expect(reading.items, isEmpty);
      expect(reading.declined.single.reason, GogMetadataSource.dlcNotAGame);
    });

    test('no entry is ever both a row and a decline', () {
      final game = _folder('Moor');
      _file(game, 'goggame-1100000002.info', _info('MOOR', '1100000002'));
      _file(_root!, 'saves.zip.torrent');

      final source = const InstalledGameSource();
      for (final entry in readInstallDirectory(_root!).entries) {
        final reading = source.read(entry);
        expect(reading.items.isEmpty, reading.declined.isNotEmpty,
            reason: entry.name);
      }
    });
  });

  group('the directory both sources could claim', () {
    test('the folder name and its .info become ONE row, the .info winning',
        () async {
      final game = _folder('MOOR');
      _file(game, 'goggame-1100000002.info', _info('MOOR', '1100000002'));

      final doc = await _run(readInstallDirectory(_root!));

      expect(doc.games, hasLength(1));
      expect(doc.games.single.detection.origin, DetectionOrigin.metadata);
      expect(doc.games.single.detection.sourceId, 'gog:1100000002');
      expect(doc.games.single.detection.sourceEntry,
          'goggame-1100000002.info');
    });

    test('a broken .info leaves the folder name as the row rather than losing '
        'the game', () async {
      final game = _folder('MOOR');
      _file(game, 'goggame-1100000002.info', 'not json at all');

      final doc = await _run(readInstallDirectory(_root!));

      expect(doc.games.single.detection.rawTitle, 'MOOR');
      expect(doc.games.single.detection.origin, DetectionOrigin.filename);
      expect(doc.declinedEntries.single.reason, GogMetadataSource.notJson);
    });

    test('two titles that do NOT agree stay two rows -- the cost of emitting '
        'the folder entry as well', () async {
      final game = _folder('MG3');
      _file(game, 'goggame-1100000008.info',
          _info('Marlow\'s Gate 3', '1100000008'));

      final doc = await _run(readInstallDirectory(_root!));

      // The folder entry is enumerated first, so the row it did not merge into
      // holds the earlier place -- dedupe keeps first-seen order.
      expect(doc.games.map((g) => g.detection.rawTitle),
          ['MG3', 'Marlow\'s Gate 3']);
    });
  });

  group('an install and its installer in one folder', () {
    test('produce one row, and the authoritative title is the one kept',
        () async {
      final game = _folder('MOOR');
      _file(game, 'goggame-1100000002.info', _info('MOOR', '1100000002'));
      _file(_root!, 'setup_moor_1.9_(21474).exe');

      final listing = readInstallDirectory(_root!);
      expect(listing.entries, hasLength(3));

      final doc = await _run(listing);

      expect(doc.games, hasLength(1));
      expect(doc.games.single.detection.origin, DetectionOrigin.metadata);
      expect(doc.games.single.detection.rawTitle, 'MOOR');
    });

    test('and it is authority that decides it, not arrival order', () {
      final installer = Detection.fromSource(
        rawTitle: 'moor',
        origin: DetectionOrigin.filename,
        sourceEntry: 'setup_moor_1.9_(21474).exe',
        platformHint: 'PC',
      );
      final installed = Detection.fromSource(
        rawTitle: 'MOOR',
        origin: DetectionOrigin.metadata,
        sourceEntry: 'goggame-1100000002.info',
        sourceId: 'gog:1100000002',
        platformHint: 'PC',
      );

      for (final order in [
        [installer, installed],
        [installed, installer]
      ]) {
        final merged = dedupeDetections(order);
        expect(merged, hasLength(1));
        expect(merged.single.origin, DetectionOrigin.metadata,
            reason: 'first: ${order.first.origin}');
      }
    });
  });

  group('a folder whose name titles nothing (T-0178)', () {
    test('is read under the installer inside it, which is the whole row',
        () async {
      final game = _folder('New Folder');
      _file(game, 'setup_harbour_lantern_1.6.15.exe');
      _file(game, 'setup_harbour_lantern_1.6.15-1.bin');

      final listing = readInstallDirectory(_root!);

      expect(listing.entries.single.name, 'setup_harbour_lantern_1.6.15.exe');
      expect(listing.entries.single.container, 'New Folder');
      expect(listing.gameDirectories, 1);
      expect(listing.installerNamed, 1);

      final doc = await _run(listing);
      expect(doc.games.single.detection.rawTitle, 'harbour lantern');
      expect(doc.games.single.detection.origin, DetectionOrigin.filename);
    });

    test('costs no row when the folder holds a library rather than a game',
        () async {
      final dump = _folder('New Folder');
      for (var i = 0; i < 40; i++) {
        _file(dump, 'setup_game${i}_1.0.exe');
      }

      final listing = readInstallDirectory(_root!);

      expect(listing.entries.single.name, 'New Folder');
      expect(listing.installerNamed, 0);

      // No row at all since T-0193: the entry is one, and `New Folder` has no
      // container left to borrow a title from. What 40 installers may not do
      // is cost a row each.
      final doc = await _run(listing);
      expect(doc.games, isEmpty);
      expect(doc.declinedEntries.single.name, 'New Folder');
    });

    test('is not looked into at all when a goggame-*.info is in it', () {
      final game = _folder('New Folder');
      _file(game, 'goggame-1100000002.info', _info('MOOR', '1100000002'));
      _file(game, 'setup_harbour_lantern_1.6.15.exe');

      final listing = readInstallDirectory(_root!);

      expect(listing.entries.map((e) => e.name),
          ['New Folder', 'goggame-1100000002.info']);
      expect(listing.installerNamed, 0);
    });

    test('a folder that DOES title a game keeps its own name', () async {
      // The installer inside agrees with it, so the folder name stands and
      // keeps the better string (T-0158). What used to hold whatever the
      // installer said is now conditional -- see the next test.
      final game = _folder('Harbour Lantern');
      _file(game, 'Harbour Lantern.exe');

      final listing = readInstallDirectory(_root!);

      expect(listing.entries.single.name, 'Harbour Lantern');
      expect((await _run(listing)).games.single.detection.rawTitle,
          'Harbour Lantern');
    });

    test('a folder name an installer contradicts outright loses it (T-0183)',
        () async {
      // T-0178 handed over `Harbour Lantern` here. The generic-name list is
      // English, so it could only ever give up a folder name it had a word
      // for, and a Russian-locale Windows names a new folder `Новая папка`.
      final game = _folder('Harbour Lantern');
      _file(game, 'setup_tulip_hospital_2.1.0.9.exe');

      final listing = readInstallDirectory(_root!);

      expect(listing.entries.single.name, 'setup_tulip_hospital_2.1.0.9.exe');
      expect(listing.installerNamed, 1);
      expect((await _run(listing)).games.single.detection.rawTitle,
          'tulip hospital');
    });

    test('the measured Russian folder, through the walk', () async {
      final game = _folder('Новая папка');
      _file(game, 'setup_iron_march_2_ultimate_2.1.0.4.exe');

      final listing = readInstallDirectory(_root!);

      expect(listing.entries.single.name,
          'setup_iron_march_2_ultimate_2.1.0.4.exe');
      expect((await _run(listing)).games.single.detection.rawTitle,
          'iron march 2 ultimate');
    });

    test('an installed game\'s file tree is still not a row each', () {
      final game = _folder('New Folder');
      _file(game, 'Marlow.pak');
      _file(game, 'steam_api64.dll');
      _file(game, 'unins000.exe');
      _file(game, 'Sundrop Hollow.exe');
      _folder('Content', game);

      final listing = readInstallDirectory(_root!);

      expect(listing.entries.single.name, 'Sundrop Hollow.exe');
    });

    test('the numbered sibling reaches the decline report by name (T-0189)',
        () async {
      // The other half of that folder, measured the same day: the
      // sibling whose single file is `setup.exe`. It was a row titled `Новая
      // папка`, which no decline report mentioned because nothing had
      // declined -- and two such siblings emitting one title is what made a
      // merge look like a decline in T-0184.
      _file(_folder('Новая папка (2)'), 'setup.exe');
      _file(_folder('Новая папка'), 'setup_iron_march_2_ultimate_2.1.0.4.exe');

      final doc = await _run(readInstallDirectory(_root!));

      expect(doc.games.map((g) => g.detection.rawTitle),
          ['iron march 2 ultimate']);
      expect(doc.declinedEntries.single.name, 'Новая папка (2)');
      expect(declinedReport(doc).join('\n'),
          contains('1 x a numbered copy of another name, not a title'));
      expect(declinedReport(doc).join('\n'), contains('Новая папка (2)'));
    });

    test('the summary says so, and only when it happened', () {
      _file(_folder('New Folder'), 'setup_mire_2.exe');

      expect(installScope(readInstallDirectory(_root!)),
          contains('1 folder(s) read under an installer name inside them'));

      _file(_root!, 'setup_zork_1.0.exe');
      _folder('Ashenmoor');
      expect(installScope(readInstallDirectory(_root!)),
          contains('read under an installer name'));
    });
  });

  group('the directory the user pointed at is not a game (T-0193)', () {
    // Scanned under a name of its own rather than the `shelfscan_games_<n>`
    // temp directory the rest of this file uses: a borrowed title has to be
    // recognisable as the scan root's when it appears.
    Directory named() => _folder('Downloaded games');

    test('a subdirectory that titles nothing borrows nothing', () {
      final root = named();
      for (final name in ['New Folder', 'Saves', 'Screenshots']) {
        _folder(name, root);
      }

      final listing = readInstallDirectory(root);

      expect(listing.entries.map((e) => e.name),
          ['New Folder', 'Saves', 'Screenshots']);
      expect(listing.entries.map((e) => e.container).toSet(), {null});
    });

    test('so three of them are three declines, not one plausible row',
        () async {
      final root = named();
      for (final name in ['New Folder', 'Saves', 'Screenshots']) {
        _folder(name, root);
      }

      final doc = await _run(readInstallDirectory(root));

      // The defect this closes is the merge, not the row: all three took the
      // same borrowed title, so stage 2 folded them into ONE row reading like
      // a game nobody owns (measured 2026-08-16).
      expect(doc.games, isEmpty);
      expect(doc.declinedEntries.map((e) => e.name),
          ['New Folder', 'Saves', 'Screenshots']);
      expect(doc.declinedEntries.map((e) => e.reason).toSet(),
          {DeclineReason.noTitle});
    });

    test('nor does a loose file in it', () async {
      final root = named();
      _file(root, 'setup.exe');

      final doc = await _run(readInstallDirectory(root));

      expect(doc.games, isEmpty);
      expect(doc.declinedEntries.single.name, 'setup.exe');
    });

    test('and a real game beside them still comes back', () async {
      final root = named();
      _folder('Screenshots', root);
      _folder('Tulip Hospital', root);
      _file(_folder('New Folder', root), 'setup_harbour_lantern_1.6.15.exe');

      final doc = await _run(readInstallDirectory(root));

      // The subdirectory one level down is a game's own folder and IS a
      // container: `New Folder` spends its own name and the installer inside
      // it keeps the parent it was found in.
      expect(doc.games.map((g) => g.detection.rawTitle),
          ['harbour lantern', 'Tulip Hospital']);
      expect(doc.declinedEntries.single.name, 'Screenshots');
    });
  });

  group('the document it writes', () {
    test('is a review document with no photos and every decline named',
        () async {
      final game = _folder('Tulip Hospital');
      _file(game, 'goggame-1100000001.info',
          _info('Tulip Hospital', '1100000001'));
      _file(_root!, 'setup_mire_2.exe');
      _file(_root!, 'shelf.jpg');
      _file(_root!, 'unins000.exe');

      final doc = await _run(readInstallDirectory(_root!));

      expect(doc.photos, isEmpty);
      expect(doc.unreadable, isEmpty);
      expect(doc.failedPhotos, isEmpty);
      expect(doc.games.map((g) => g.detection.rawTitle),
          containsAll(['Tulip Hospital', 'mire 2']));
      expect(doc.declinedEntries.map((e) => e.name),
          containsAll(['shelf.jpg', 'unins000.exe']));
      expect(declinedReport(doc).first, contains('declined_entries'));
      expect(declinedReport(doc), contains('  1 x ${DeclineReason.notAGameFile}'));
    });

    test('round-trips through resolve and export unchanged', () async {
      final game = _folder('Tulip Hospital');
      _file(game, 'goggame-1100000001.info',
          _info('Tulip Hospital', '1100000001'));
      _file(_root!, 'Ashfall.2.GOG.zip');

      final written = const JsonEncoder.withIndent('  ')
          .convert((await _run(readInstallDirectory(_root!))).toJson());

      // Exactly what `resolve` does: read the file back, re-run stage 3 over
      // the detections in it.
      final reread = ReviewDocument.parse(written);
      expect(reread.games.map((g) => g.detection.rawTitle),
          ['Ashfall 2', 'Tulip Hospital']);
      final resolved = await Orchestrator.resolveOnly(
              resolverWorker: SkipResolver())
          .runResolve([for (final game in reread.games) game.detection]);
      expect(resolved.map((g) => g.detection.rawTitle),
          reread.games.map((g) => g.detection.rawTitle));

      // And what `export` does, on a document approved the way review.json is
      // hand-edited.
      final approved = jsonDecode(written) as Map<String, dynamic>;
      for (final game in approved['games'] as List) {
        (game as Map<String, dynamic>)['status'] = 'approved';
      }
      final doc = ReviewDocument.parse(jsonEncode(approved));
      expect(exporters['csv']!().export(doc), contains('Tulip Hospital'));
      expect(exporters['tonkatsu']!().export(doc), contains('"version": 2'));
    });

    test('a source row carries its entry as provenance, and no photo',
        () async {
      _file(_root!, 'Ashfall.2.GOG.zip');

      final doc = await _run(readInstallDirectory(_root!));

      expect(doc.games.single.detection.sourceEntry, 'Ashfall.2.GOG.zip');
      expect(doc.games.single.detection.sourcePhoto, isEmpty);
      expect(doc.games.single.detection.rawTitle, 'Ashfall 2');
    });
  });

  group('the input contract', () {
    test('a personal or system directory is refused by name', () {
      for (final name in notAGamesFolder) {
        final dir = _folder(name);
        expect(gamesFolderError(dir.path), isNotNull, reason: name);
      }
      expect(gamesFolderError(_folder('Downloads').path), contains('T-0158'));
    });

    test('the refusal is case-insensitive', () {
      expect(gamesFolderError(_folder('DOWNLOADS').path), isNotNull);
    });

    test('a plausible games folder is not refused', () {
      for (final name in ['Games', 'GOG Games', 'M0OR', 'steam library']) {
        expect(gamesFolderError(_folder(name).path), isNull, reason: name);
      }
    });

    test('a drive or filesystem root is refused', () {
      final root = Directory(_root!.uri.pathSegments.first.endsWith(':')
          ? '${_root!.uri.pathSegments.first}\\'
          : '/');
      expect(gamesFolderError(root.path), isNotNull);
    });

    test('a missing directory and a file are named, absolute', () {
      _file(_root!, 'setup_mire_2.exe');

      expect(installsPathError('${_root!.path}/nope'),
          allOf(startsWith('No games folder at'), contains('nope')));
      expect(installsPathError('${_root!.path}/setup_mire_2.exe'),
          allOf(contains('is a file'), contains('scan-installs takes')));
      expect(installsPathError(_root!.path), isNull);
    });

    test('the summary names what was covered, not only what was found', () {
      _file(_root!, 'setup_mire_2.exe');
      _file(_root!, 'notes.txt');
      final game = _folder('Moor');
      _file(game, 'goggame-1100000002.info', _info('MOOR', '1100000002'));

      expect(
          installScope(readInstallDirectory(_root!)),
          allOf(startsWith('4 entry(ies)'), contains('1 folder'),
              contains('2 loose file'), contains('1 goggame')));
    });
  });
}
