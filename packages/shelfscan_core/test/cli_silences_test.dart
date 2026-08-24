/// The two things a run did not say (T-0184, folding T-0188).
///
/// Both were measured against a real folder of downloaded games during
/// development; that folder is not published. Both are reproduced here as a
/// real CLI subprocess: `scan-installs` makes no vision call and no IGDB
/// call with the credentials blanked, so the whole command is exercised with
/// nothing faked and nothing leaving the machine.
///
/// The first group builds a folder of its own, and no count in it is a count
/// of anything real. What T-0184 named is that the run stated an entry count
/// and a game count and never said what the difference between them was, so
/// any fixture where the two differ reproduces it.
@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';

import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

import '../bin/shelfscan.dart'
    show
        commandOptions,
        declinedNamesShown,
        declinedReport,
        entryAccounting,
        installsFlag,
        libraryFlag,
        unknownOptionError;
import 'cli_snapshot.dart';

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

Directory _folder(Directory parent, String name) =>
    Directory(_join(parent.path, name))..createSync();

void _file(Directory parent, String name, [String content = '']) =>
    File(_join(parent.path, name)).writeAsStringSync(content);

Future<ProcessResult> _runCli(List<String> args) => Process.run(
      Platform.resolvedExecutable,
      [cliSnapshot(), ...args],
      environment: {
        'IGDB_CLIENT_ID': '',
        'IGDB_CLIENT_SECRET': '',
        'SHELFSCAN_TMDB_TOKEN': '',
      },
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );

ReviewDocument _doc({
  List<DeclinedEntry> declined = const [],
  int rows = 0,
}) =>
    ReviewDocument(
      version: 1,
      created: '',
      photos: const [],
      games: [
        for (var i = 0; i < rows; i++)
          ResolvedGame(
              detection: Detection(
                  rawTitle: 'row $i',
                  mediaType: MediaType.unknown,
                  confidence: 0,
                  sourcePhoto: '')),
      ],
      declinedEntries: declined,
    );

void main() {
  setUpAll(cliSnapshot);

  group('an entry count and a game count that differ', () {
    late Directory games;
    late String out;

    setUp(() {
      games = _tempDir('shelfscan_silence_games_');
      // A second temp directory, not `games`: `readInstallDirectory` counts
      // every loose file as an entry, and this group asserts those counts.
      // Inside `games` passes today -- measured -- only because the walk runs
      // before the write, so nothing here should depend on that order.
      // `games.parent` was the shared system temp root, which two concurrent
      // suites then shared (T-0216).
      out = _join(_tempDir('shelfscan_silence_out_').path,
          'silence.review.json');
      _folder(games, 'Tulip Hospital');
      _folder(games, 'Mire 2');
      // `Новая папка` is what Windows itself names a new folder in Russian and
      // `(2)` is its own duplication mark on the second; the numbered one is
      // the decline this group pins. Windows' vocabulary, not anybody's data
      // -- the argument is in `corpus/installer_names.tsv`, section 7.
      _folder(games, 'Новая папка');
      _file(_folder(games, 'Новая папка (2)'), 'setup.exe');
    });

    test('4 entries, 3 rows, and the fourth is a decline (T-0189)', () async {
      final result = await _runCli(['scan-installs', games.path, '-o', out]);

      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      expect(result.stdout, contains('4 entry(ies)'));
      expect(result.stdout, contains('3 game(s) found'));
      // This group was built on the MERGE this folder used to produce: both
      // siblings emitted `Новая папка`, stage 2 merged them, and the
      // difference between 4 and 3 was read as a decline nobody had made
      // (T-0184). T-0189 made the second sibling decline for real, so the
      // merge is gone from this fixture and the same two numbers now have the
      // other explanation -- which is the whole reason the line states both
      // instead of leaving a subtraction. The merge clause keeps its own test
      // in `entryAccounting names the merge when every row came from an entry`.
      expect(result.stdout,
          contains('Of 4 entry(ies) read: 1 named no game, 3 named one.'));
      expect(result.stdout, isNot(contains('merged into another row')));
      expect(result.stdout, contains('Not a game: 1 entry(ies)'));
      expect(result.stdout, contains('Новая папка (2)'));
      expect(File(out).readAsStringSync(), contains('declined_entries'));
    });

    test('a decline in the same folder is NAMED, not counted', () async {
      _file(games, 'shelf.jpg');
      _file(games, 'unins000.exe');

      final result = await _runCli(['scan-installs', games.path, '-o', out]);

      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      expect(result.stdout, contains('Not a game: 3 entry(ies)'));
      expect(result.stdout, contains('shelf.jpg'));
      expect(result.stdout, contains('unins000.exe'));
      expect(result.stdout,
          contains('Of 6 entry(ies) read: 3 named no game, 3 named one'));
      // The document is where a shell reads them as values, and it still is.
      final doc = ReviewDocument.parse(File(out).readAsStringSync());
      expect(doc.declinedEntries.map((e) => e.name),
          containsAll(['shelf.jpg', 'unins000.exe']));
    });
  });

  group('declinedReport names entries without a line each', () {
    test('is empty when nothing declined', () {
      expect(declinedReport(_doc()), isEmpty);
    });

    test('names every entry when there are few', () {
      final report = declinedReport(_doc(declined: const [
        DeclinedEntry(name: 'crack.exe', reason: 'no title in the name'),
        DeclinedEntry(name: 'notes.txt', reason: 'not a game file'),
      ]));

      expect(report.first, contains('2 entry(ies)'));
      expect(report.join('\n'), contains('crack.exe'));
      expect(report.join('\n'), contains('notes.txt'));
    });

    test('40 of one reason are two lines, six names and a count', () {
      final report = declinedReport(_doc(declined: [
        for (var i = 0; i < 40; i++)
          DeclinedEntry(name: 'file$i.torrent', reason: 'not a game file'),
      ]));

      // The shape, stated: a header plus at most two lines per distinct
      // reason, whatever the folder holds.
      expect(report, hasLength(3));
      expect(report[1], '  40 x not a game file');
      expect(report[2], contains('file0.torrent'));
      expect(report[2],
          contains('and ${40 - declinedNamesShown} more, all in '
              '"declined_entries"'));
      expect(report[2], isNot(contains('file39.torrent')));
    });

    test('two reasons are two blocks, sorted so a re-run repeats', () {
      final report = declinedReport(_doc(declined: const [
        DeclinedEntry(name: 'b.exe', reason: 'no title in the name'),
        DeclinedEntry(name: 'a.txt', reason: 'not a game file'),
      ]));

      expect(report, hasLength(5));
      expect(report[1], '  1 x no title in the name');
      expect(report[3], '  1 x not a game file');
    });
  });

  group('entryAccounting', () {
    test('says nothing on a run that read no entry', () {
      expect(
          entryAccounting(_doc(rows: 3),
              entries: 0, rowsAreAllFromEntries: false),
          isEmpty);
    });

    test('names the merge when every row came from an entry', () {
      expect(
          entryAccounting(_doc(rows: 3), entries: 4,
                  rowsAreAllFromEntries: true)
              .single,
          'Of 4 entry(ies) read: 0 named no game, 4 named one, and 1 of those '
          'merged into another row -- one game named in two places is one row.');
    });

    test('claims no merge on a run that also read photographs', () {
      // `scan`'s document holds rows off photographs too, so the difference is
      // not attributable to an entry and is not stated.
      expect(
          entryAccounting(_doc(rows: 9), entries: 4,
                  rowsAreAllFromEntries: false)
              .single,
          'Of 4 entry(ies) read: 0 named no game, 4 named one.');
    });

    test('counts declines out of the entries that named a game', () {
      expect(
          entryAccounting(
                  _doc(rows: 1, declined: const [
                    DeclinedEntry(name: 'a', reason: 'not a game file'),
                    DeclinedEntry(name: 'b', reason: 'not a game file'),
                  ]),
                  entries: 3,
                  rowsAreAllFromEntries: true)
              .single,
          'Of 3 entry(ies) read: 2 named no game, 1 named one.');
    });
  });

  group('an unknown option is refused before anything is read', () {
    late Directory games;

    setUp(() {
      games = _tempDir('shelfscan_flags_games_');
      _folder(games, 'Tulip Hospital');
    });

    test('the measured invented flag exits 2 and reads nothing', () async {
      final out =
          _join(_tempDir('shelfscan_flags_out_').path, 'never.review.json');
      final result = await _runCli([
        'scan-installs',
        games.path,
        '--this-flag-does-not-exist',
        'zzz',
        '-o',
        out,
      ]);

      expect(result.exitCode, 2);
      expect(result.stderr, contains('--this-flag-does-not-exist'));
      expect(result.stderr, contains('Options of "scan-installs"'));
      // Before any work begins: the unconditional input notice is the first
      // thing this command prints, and it was not printed.
      expect(result.stdout, isNot(contains('No photo is read')));
      expect(File(out).existsSync(), isFalse);
    });

    test('a flag of another command names that command', () async {
      final result = await _runCli(
          ['scan-installs', games.path, installsFlag, games.path]);

      expect(result.exitCode, 2);
      expect(result.stderr, contains('is not an option of "scan-installs"'));
      expect(result.stderr, contains('it belongs to "scan"'));
      expect(result.stdout, isNot(contains('No photo is read')));
    });

    test('the same refusal off the process, for every command', () {
      expect(unknownOptionError('scan-installs', const ['dir', installsFlag]),
          contains('"scan"'));
      expect(unknownOptionError('scan-library', const [libraryFlag]),
          contains('"scan"'));
      expect(unknownOptionError('scan-library', const [libraryFlag]),
          contains('"scan-installs"'));
      expect(unknownOptionError('export', const ['r.json', '--provider', 'x']),
          contains('"scan"'));
      expect(unknownOptionError('resolve', const ['r.json', '--target', 'csv']),
          contains('"export"'));
    });

    test('every option a command has is accepted by it', () {
      for (final command in commandOptions.entries) {
        for (final option in command.value.entries) {
          final args = [option.key, if (option.value) 'value'];
          expect(unknownOptionError(command.key, args), isNull,
              reason: '${command.key} ${option.key}');
        }
      }
    });

    test("a known option's value is stepped over, never examined", () {
      // `-o --library` names a file called `--library`, oddly but legally.
      expect(unknownOptionError('scan-installs', const ['dir', '-o', '--zzz']),
          isNull);
    });

    test('an unknown COMMAND is left to the usage text', () {
      expect(unknownOptionError('scna', const ['--anything']), isNull);
    });

    test('a positional argument is not an option and is not refused', () {
      expect(unknownOptionError('scan-installs', const ['dir', 'extra']),
          isNull);
      expect(unknownOptionError('scan-installs', const ['-']), isNull);
    });
  });
}
