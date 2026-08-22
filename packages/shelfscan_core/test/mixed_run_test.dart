/// One run, several sources (T-0179 / T-0173).
///
/// `Orchestrator.runScan` took ONE `SourceRun` until this task, so the shelf
/// and the disk could only be scanned as two commands writing two documents --
/// and the second `-o` overwrote the first. What is pinned here is the case
/// T-0155's doc comment says the seam exists for: a game owned on a disc AND
/// installed on the PC comes out of ONE invocation as ONE row.
///
/// The headline test is a real CLI subprocess. It needs a vision answer, so a
/// loopback HTTP server stands in for Ollama -- the wire, the CLI, the walk,
/// the dedupe and the written file are all real, and only the model is a
/// fixture. The IGDB variables are blanked, so stage 3
/// provably takes the skip branch and no request leaves the machine.
@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

import '../bin/shelfscan.dart'
    show
        InstalledGameSource,
        installsFlag,
        libraryFlag,
        readInstallDirectory,
        sourceRunsFor;
import '../bin/galaxy_db.dart' show GalaxyLibrary, galaxyRowToJson;
import 'cli_snapshot.dart';

/// The GoG product id of MOOR (1993) on GOG's own store, as quoted in
/// doc/measurements.md, "The exact join". Nothing from a real library is
/// used anywhere in this file.
const _moorId = '1100000002';

/// `goggame-<gameId>.info` reduced to the keys the source reads (T-0157).
String _info(String name, String id) =>
    jsonEncode({'gameId': id, 'rootGameId': id, 'name': name, 'version': 1});

/// The smallest thing `sniffImage` calls a JPEG.
final _jpegBytes =
    Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, ...List.filled(64, 0)]);

Directory _tempDir(String prefix) {
  final dir = Directory.systemTemp.createTempSync(prefix);
  addTearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // The Windows errno 145 race the other path suites document.
    }
  });
  return dir;
}

String _join(String dir, String name) => '$dir${Platform.pathSeparator}$name';

/// A loopback stand-in for Ollama: one `PC` disc detection per photo.
///
/// The hint is `PC` and that is the whole realism of the fixture: a boxed PC
/// game on a DVD is the physical object whose install this run also reads, and
/// the two are one game. It is not a free choice -- dedupe groups by hint, and
/// an ABSENT hint is its own group beside `pc` just as `PS4` is (measured
/// here: the same run with no hint comes out as two rows). Two hints that are
/// not the same platform stay two rows by T-0018-02, which this task must not
/// disturb.
Future<Uri> _fakeOllama(String rawTitle) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  addTearDown(() => server.close(force: true));
  server.listen((request) async {
    await request.drain<void>();
    final answer = jsonEncode({
      'items': [
        {
          'raw_title': rawTitle,
          'platform_hint': 'PC',
          'media_type': 'disc',
          'confidence': 0.9,
        },
      ],
      'unreadable': <Object>[],
    });
    request.response
      ..headers.contentType = ContentType.json
      ..write(jsonEncode({
        'message': {'content': answer},
      }));
    await request.response.close();
  });
  return Uri.parse('http://${server.address.address}:${server.port}');
}

/// Async, not `runSync`: the stand-in server above lives in this isolate, and
/// a synchronous wait blocks the event loop that would have answered the
/// subprocess -- the CLI then sits out its full 120 s vision timeout.
Future<ProcessResult> _runCli(List<String> args, {required Uri ollama}) =>
    Process.run(
      Platform.resolvedExecutable,
      [cliSnapshot(), ...args],
      environment: {
        'SHELFSCAN_OLLAMA_URL': ollama.toString(),
        // Blanked so a machine that has IGDB credentials cannot turn this into
        // a live API call: every row comes back unresolved, which is the
        // documented skip-the-resolve-stage behaviour.
        'IGDB_CLIENT_ID': '',
        'IGDB_CLIENT_SECRET': '',
      },
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );

/// A library row in the JSON `GogLibrarySource` parses, built through the
/// reader's own encoder so the fixture cannot drift from the real shape.
SourceEntry _libraryEntry(String id, String title) => SourceEntry(
      name: 'gog_$id',
      content: galaxyRowToJson('gog_$id', jsonEncode({'title': title}), 0, 1),
    );

void main() {
  setUpAll(cliSnapshot);

  group('the CLI, end to end, in one invocation', () {
    late Directory photos;
    late Directory games;
    // Its own directory, not `photos` or `games`: both are walked by the run,
    // and only the walk-before-write order keeps an output file inside either
    // from being read back as an entry. `photos.parent` was the shared system
    // temp root, which two concurrent suites then shared (T-0216).
    late Directory outs;

    setUp(() {
      photos = _tempDir('shelfscan_mixed_photos_');
      games = _tempDir('shelfscan_mixed_games_');
      outs = _tempDir('shelfscan_mixed_out_');
      File(_join(photos.path, 'shelf1.jpg')).writeAsBytesSync(_jpegBytes);
      final moor = Directory(_join(games.path, 'MOOR'))..createSync();
      File(_join(moor.path, 'goggame-$_moorId.info'))
          .writeAsStringSync(_info('MOOR', _moorId));
    });

    test('a disc and an install of one game are ONE row in ONE review.json',
        () async {
      final ollama = await _fakeOllama('MOOR');
      final out = _join(outs.path, 'mixed.review.json');

      final result = await _runCli(
        ['scan', photos.path, installsFlag, games.path, '-o', out],
        ollama: ollama,
      );

      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      final doc = ReviewDocument.parse(File(out).readAsStringSync());

      // The whole point of the task: one row, not one per input.
      expect(doc.games, hasLength(1));
      final row = doc.games.single.detection;
      expect(titleKey(row.rawTitle), titleKey('MOOR'));
      // The install won the merge -- `isAuthoritative` outranks photo yield in
      // `_DedupeGroup.absorb` (T-0155) -- so the surviving row is the one with
      // a product id on it, which is what T-0159's exact join needs.
      expect(row.origin, DetectionOrigin.metadata);
      expect(row.sourceId, 'gog:$_moorId');
      expect(row.sourceEntry, 'goggame-$_moorId.info');

      // One document, and it knows about both halves of the run.
      expect(doc.photos, ['shelf1.jpg']);
      expect(result.stdout, contains('1 game(s) detected'));
    });

    test('each added source keeps its own notice, and the summary names both',
        () async {
      final ollama = await _fakeOllama('MOOR');
      final out = _join(outs.path, 'notices.review.json');

      final result = await _runCli(
        ['scan', photos.path, installsFlag, games.path, '-o', out],
        ollama: ollama,
      );

      // T-0158's input contract is a property of what is read, not of which
      // command was typed: every title read off a Downloads folder was an
      // application, so the notice is unconditional here too.
      expect(result.stdout, contains('No photo is read and no vision model'));
      expect(result.stdout, contains('Scanned'));
      expect(result.stdout, contains('entry(ies)'));
    });

    test('a games folder that refuses costs no vision call at all', () async {
      final ollama = await _fakeOllama('MOOR');
      final result = await _runCli(
        [
          'scan',
          photos.path,
          installsFlag,
          _join(games.path, 'not-a-directory'),
        ],
        ollama: ollama,
      );

      // Exit 2 with the other pre-flight failures, and nothing written: a typo
      // in the folder must not be paid for with a scan of the shelf first
      // (T-0051's rule, applied to the new argument).
      expect(result.exitCode, 2);
      expect(result.stderr, contains('No games folder at'));
      expect(result.stdout, isNot(contains('== vision ==')));
    });

    test('a photo-only run is untouched: no notice, no declined block',
        () async {
      final ollama = await _fakeOllama('MOOR');
      final out = _join(outs.path, 'photos.review.json');

      final result =
          await _runCli(['scan', photos.path, '-o', out], ollama: ollama);

      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      expect(result.stdout, isNot(contains('No photo is read')));
      expect(result.stdout, isNot(contains('Not a game:')));
      final written = File(out).readAsStringSync();
      expect(written, isNot(contains('declined_entries')));
      expect(written, isNot(contains('source_entry')));
    });
  });

  group('sourceRunsFor', () {
    test('is empty when a run has neither', () {
      expect(sourceRunsFor(), isEmpty);
    });

    test('is installs then library, so the more specific claim is read first',
        () {
      final games = _tempDir('shelfscan_runs_');
      File(_join(games.path, 'setup_moor_1.9.exe')).writeAsStringSync('');
      final runs = sourceRunsFor(
        installs: readInstallDirectory(games),
        library: GalaxyLibrary(
          entries: [_libraryEntry(_moorId, 'MOOR')],
          asOf: DateTime(2026, 8, 16),
          schemaVersion: 40,
        ),
      );

      expect(runs, hasLength(2));
      expect(runs.first.source, isA<InstalledGameSource>());
      expect(runs.last.source, isA<GogLibrarySource>());
    });
  });

  group('runScan over several sources', () {
    test('reads every run, and one game in two of them is one row', () async {
      final games = _tempDir('shelfscan_two_sources_');
      final moor = Directory(_join(games.path, 'MOOR'))..createSync();
      File(_join(moor.path, 'goggame-$_moorId.info'))
          .writeAsStringSync(_info('MOOR', _moorId));

      final doc =
          await Orchestrator.resolveOnly(resolverWorker: SkipResolver())
              .runScan(
        const [],
        sources: sourceRunsFor(
          installs: readInstallDirectory(games),
          library: GalaxyLibrary(
            entries: [
              _libraryEntry(_moorId, 'MOOR'),
              _libraryEntry('1100000014', 'Another Game'),
            ],
            asOf: DateTime(2026, 8, 16),
            schemaVersion: 40,
          ),
        ),
      );

      // Three rows in, two out: the install and the library entry for the same
      // product are one game, and only a single run can put them through one
      // dedupe.
      expect([for (final game in doc.games) game.detection.rawTitle],
          ['MOOR', 'Another Game']);
      expect(doc.games.first.detection.sourceId, 'gog:$_moorId');
    });

    test('the source stage counts one bar across every run, not one each',
        () async {
      final counts = <(int, int)>[];
      await Orchestrator.resolveOnly(resolverWorker: SkipResolver()).runScan(
        const [],
        sources: [
          SourceRun(const GogLibrarySource(), [_libraryEntry('1', 'One')]),
          SourceRun(const GogLibrarySource(),
              [_libraryEntry('2', 'Two'), _libraryEntry('3', 'Three')]),
        ],
        progress: ScanProgress(onItem: (stage, done, total) {
          if (stage == 'source') counts.add((done, total));
        }),
      );

      expect(counts, [(1, 3), (2, 3), (3, 3)]);
    });

    test('two runs declining for one reason are named once, not twice',
        () async {
      // Grouped by reason across the whole stage (`_warnDeclined`): 40 skipped
      // entries are one line, which is the trade already measured for a games
      // folder that declines more than it accepts.
      final warnings = <String>[];
      final dlc = SourceEntry(
          name: 'gog_9001',
          content: galaxyRowToJson(
              'gog_9001', jsonEncode({'title': 'An Expansion'}), 1, 1));
      await Orchestrator.resolveOnly(resolverWorker: SkipResolver()).runScan(
        const [],
        sources: [
          SourceRun(const GogLibrarySource(), [dlc]),
          SourceRun(const GogLibrarySource(), [dlc]),
        ],
        progress: ScanProgress(onWarning: (w) => warnings.add(w.message)),
      );

      expect(warnings, hasLength(1));
      expect(warnings.single, contains('2 entries'));
    });

    test('an empty list is exactly a run with no sources at all', () async {
      final doc =
          await Orchestrator.resolveOnly(resolverWorker: SkipResolver())
              .runScan(const [], sources: const []);

      expect(doc.games, isEmpty);
      expect(doc.declinedEntries, isEmpty);
    });
  });

  group('scan-installs may add the library beside it', () {
    test('the flag is the same word on both commands', () {
      // One spelling, so a user who learned it on `scan` does not have to
      // learn a second one here.
      expect(libraryFlag, '--library');
      expect(installsFlag, '--installs');
    });
  });
}
