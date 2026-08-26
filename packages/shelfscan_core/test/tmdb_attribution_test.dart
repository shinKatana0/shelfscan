/// The mandated TMDB attribution, and the two places this shell states it
/// (T-0384).
///
/// TMDB's terms mandate a sentence word for word, with only the bracketed
/// word of "This [website, program, service, application, product]"
/// substituted; `doc/backlog.md`'s T-0383 entry carries the requirement and
/// `doc/reports/T-0383.md` the reasoning for `application`. The app states it
/// on the settings screen and the three READMEs carry it; this shell had
/// nothing, while naming TMDB to the user and building the client itself.
///
/// **The literal below is a second, independent copy of the required text,
/// not an import of the constant under test.** Comparing the constant to
/// itself asserts nothing about the requirement, and the cost of the sentence
/// existing twice in this package is the point of it.
///
/// Since T-0400 the published files are held to the same standard from here:
/// `NOTICE` carves the mark out of the MIT grant and restates the sentence,
/// and the three READMEs were checked by hand until now. Nothing watched
/// either, which is the `.env.example` shape `documented_lists_test.dart`
/// exists for.
///
/// **Whole sentence, never a fragment.** The wording T-0383 replaced
/// contained the fragments anyone would grep for and was still a paraphrase,
/// and T-0383's own first edit ate the full stop while every fragment
/// survived. So every assertion here is on the complete string, with
/// whitespace flattened so a sentence wrapped across two source lines or
/// across a terminal still counts as one.
@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../bin/shelfscan.dart' show tmdbAttribution;
import 'cli_snapshot.dart';

/// The required text, typed here from the requirement rather than read from
/// the code it is guarding.
const _required = 'This application uses TMDB and the TMDB APIs but is not '
    'endorsed, certified, or otherwise approved by TMDB.';

/// An invented token shape. Nothing here reaches TMDB: no row in the fixture
/// is a film, so no search is ever made.
const _token = 'tmdb-not-a-token';

/// The one file `NOTICE` carves out of the MIT grant (T-0400).
const _asset = 'app/assets/tmdb/blue_long_1.svg';

/// Walks up to the directory holding `LICENSE`, the same shape
/// `documented_lists_test.dart` uses to reach `.env.example`.
String _readRepoFile(String name) {
  for (var dir = Directory.current.absolute;; dir = dir.parent) {
    if (File(_join(dir.path, 'LICENSE')).existsSync()) {
      return File(_join(dir.path, name)).readAsStringSync();
    }
    if (dir.path == dir.parent.path) {
      fail('no LICENSE at or above ${Directory.current.path}');
    }
  }
}

/// Runs of whitespace collapsed to one space, so a wrap is not a difference.
final _whitespace = RegExp(r'\s+');

String _flat(String text) => text.replaceAll(_whitespace, ' ').trim();

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

/// Spawns the CLI with [tmdbToken] set, IGDB blanked either way.
///
/// Blanked rather than absent: a set-but-empty variable reads as unset
/// (T-0080), and the machine running this may hold real credentials.
Future<ProcessResult> _runCli(List<String> args, {String tmdbToken = ''}) =>
    Process.run(
      Platform.resolvedExecutable,
      [cliSnapshot(), ...args],
      environment: {
        'IGDB_CLIENT_ID': '',
        'IGDB_CLIENT_SECRET': '',
        'SHELFSCAN_TMDB_TOKEN': tmdbToken,
      },
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );

void main() {
  setUpAll(cliSnapshot);

  test('the constant is the required text, whole', () {
    expect(_flat(tmdbAttribution), _required);
  });

  test('the usage banner states it', () async {
    final result = await _runCli([]);

    // The banner is stderr and exit 2, which is what `shelfscan` with no
    // arguments has always answered; the banner itself points users at it.
    expect(result.exitCode, 2);
    expect(_flat(result.stderr as String), contains(_required));
  });

  group('a run says it when a TMDB token is set, and only then', () {
    late Directory games;
    late String out;

    setUp(() {
      games = _tempDir('shelfscan_attrib_games_');
      out = _join(
          _tempDir('shelfscan_attrib_out_').path, 'attrib.review.json');
      // Invented, and neither is a film: a film needs a video extension, so
      // no row here can reach a catalogue even with a token set.
      _folder(games, 'Cinder Harbour');
      _folder(games, 'Wren Signal 2');
    });

    test('with a token, on stdout', () async {
      final result = await _runCli(
        ['scan-installs', games.path, '-o', out],
        tmdbToken: _token,
      );

      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      expect(_flat(result.stdout as String), contains(_required));
    });

    test('without one, nothing of it', () async {
      final result = await _runCli(['scan-installs', games.path, '-o', out]);

      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      // The control for the assertion below: without it a run that never
      // reached the resolver factory would pass by saying nothing at all.
      expect(result.stdout, contains('IGDB credentials not set'));
      expect(_flat(result.stdout as String), isNot(contains(_required)));
      // No fragment of it either, so a future half-edit cannot leave the
      // notice standing here in pieces.
      expect(result.stdout, isNot(contains('TMDB and the TMDB APIs')));
    });
  });

  group('the published files carry it too (T-0400)', () {
    for (final name in const [
      'NOTICE',
      'README.md',
      'README.ru.md',
      'README.ja.md',
    ]) {
      test('$name states it whole', () {
        expect(_flat(_readRepoFile(name)), contains(_required));
      });
    }

    test('NOTICE names the carved-out file by its repository path', () {
      expect(_readRepoFile('NOTICE'), contains(_asset));
    });

    test('NOTICE points at the licence it is carving out of', () {
      expect(_readRepoFile('NOTICE'), contains('LICENSE'));
    });

    // T-0400's binding decision: the carve-out went to NOTICE precisely so
    // LICENSE keeps matching MIT, which is what GitHub's sidebar detects.
    // Appending the carve-out here instead is the one edit that silently
    // undoes it, and it would name TMDB.
    test('LICENSE stays bare MIT and says nothing of TMDB', () {
      expect(_readRepoFile('LICENSE'), isNot(contains('TMDB')));
    });
  });
}

