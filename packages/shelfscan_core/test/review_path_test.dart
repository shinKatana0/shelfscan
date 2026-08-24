/// Guards `resolve` and `export` against presenting a mistyped path as a
/// crash (T-0049).
///
/// The same defect T-0037 removed from `scan`, in the two commands its brief
/// asserted were already safe: both went straight to
/// `File(args.first).readAsStringSync()` and died with an unhandled
/// `PathNotFoundException` and a five-frame trace. So the claims are the two
/// halves of T-0037's: the wording, with the path resolved to absolute, and
/// that a real process exits 2 printing no Dart frames.
///
/// Every subprocess here stops before an IGDB client or a vision provider is
/// constructed -- the path cases fail on the path, and the one valid-file
/// case runs with the IGDB variables blanked so `resolve` stops at the
/// credentials check -- so nothing in this file can reach a network.
@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../bin/shelfscan.dart' show reviewPathError;
import 'cli_snapshot.dart';

/// A reviewed document as `scan` writes one: a single approved, resolved game.
const _reviewFixture = {
  'version': 1,
  'created': '2026-08-13T17:25:31.019438Z',
  'photos': ['shelf_b.jpg'],
  'games': [
    {
      'detection': {
        'raw_title': 'CROWN OF TIDEFALL',
        'platform_hint': 'PS5',
        'media_type': 'disc',
        'confidence': 1.0,
        'source_photo': 'shelf_b.jpg',
        'notes': null,
      },
      'best': {
        'igdb_id': 1100000048,
        'title': 'Crown of Tidefall',
        'platform_id': 167,
        'platform_name': 'PlayStation 5',
        'score': 1.0,
      },
      'candidates': [
        {
          'igdb_id': 1100000048,
          'title': 'Crown of Tidefall',
          'platform_id': 167,
          'platform_name': 'PlayStation 5',
          'score': 1.0,
        }
      ],
      'status': 'approved',
    },
  ],
};

Directory _tempDir() {
  final dir = Directory.systemTemp.createTempSync('shelfscan_review_path_');
  // Same race as scan_path_test: Windows fails the recursive delete with
  // errno 145 when it beats the handles just closed.
  addTearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // ignore
    }
  });
  return dir;
}

String _join(String dir, String name) => '$dir${Platform.pathSeparator}$name';

/// A review file in a fresh temp directory, plus that directory's path.
({String file, String dir}) _reviewFile() {
  final dir = _tempDir();
  final file = _join(dir.path, 'collection.review.json');
  File(file).writeAsStringSync(jsonEncode(_reviewFixture));
  return (file: file, dir: dir.path);
}

ProcessResult _runCli(List<String> args) => Process.runSync(
      Platform.resolvedExecutable,
      [cliSnapshot(), ...args],
      // Blanked rather than inherited: a machine that has IGDB credentials
      // set would otherwise turn the valid-file case into a live API call.
      environment: const {
        'IGDB_CLIENT_ID': '',
        'IGDB_CLIENT_SECRET': '',
        'SHELFSCAN_TMDB_TOKEN': '',
      },
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );

List<String> _lines(Object? stderrText) =>
    const LineSplitter().convert(stderrText as String);

void main() {
  setUpAll(cliSnapshot);

  group('reviewPathError', () {
    test('a file that exists is not an error', () {
      expect(reviewPathError(_reviewFile().file, 'resolve'), isNull);
    });

    test('a missing path names the absolute path it looked for', () {
      final missing = _join(_tempDir().path, 'no_such_review.json');
      expect(reviewPathError(missing, 'resolve'), 'No review file at $missing');
    });

    test('a relative path is answered with where it actually pointed', () {
      final message = reviewPathError('no_such_review.json', 'export')!;
      expect(message,
          contains(_join(Directory.current.path, 'no_such_review.json')));
    });

    test('.. is resolved away rather than echoed back', () {
      final message =
          reviewPathError('sub/../no_such_review.json', 'export')!;
      expect(message, isNot(contains('..')));
      expect(message,
          contains(_join(Directory.current.path, 'no_such_review.json')));
    });

    test('a directory is named as a directory, and by the command', () {
      final dir = _tempDir().path;
      for (final command in ['resolve', 'export']) {
        final message = reviewPathError(dir, command)!;
        expect(message, startsWith('Not a review file: $dir'));
        expect(message, contains('is a directory'));
        expect(message, contains('$command takes the review.json'));
      }
    });
  });

  group('the CLI process', () {
    test('has bin/shelfscan.dart under the working directory', () {
      expect(File('bin/shelfscan.dart').existsSync(), isTrue,
          reason: 'run `dart test` from packages/shelfscan_core');
    });

    test('resolve exits 2 with one line on a missing file', () {
      final missing = _join(_tempDir().path, 'no_such_review.json');
      final result = _runCli(['resolve', missing]);
      expect(result.exitCode, 2);
      expect(result.stderr, contains('No review file at $missing'));
      expect(_lines(result.stderr), hasLength(1));
    });

    test('export exits 2 with one line on a missing file', () {
      final missing = _join(_tempDir().path, 'no_such_review.json');
      final result =
          _runCli(['export', missing, '--target', 'csv', '-o', 'out.csv']);
      expect(result.exitCode, 2);
      expect(result.stderr, contains('No review file at $missing'));
      expect(_lines(result.stderr), hasLength(1));
    });

    test('resolve exits 2 with one line on a directory', () {
      final dir = _tempDir().path;
      final result = _runCli(['resolve', dir]);
      expect(result.exitCode, 2);
      expect(result.stderr, contains('Not a review file: $dir'));
      expect(result.stderr, contains('resolve takes the review.json'));
      expect(_lines(result.stderr), hasLength(1));
    });

    test('export exits 2 with one line on a directory', () {
      final dir = _tempDir().path;
      final result =
          _runCli(['export', dir, '--target', 'csv', '-o', 'out.csv']);
      expect(result.exitCode, 2);
      expect(result.stderr, contains('Not a review file: $dir'));
      expect(result.stderr, contains('export takes the review.json'));
      expect(_lines(result.stderr), hasLength(1));
    });

    test('prints no Dart frames for any of the four', () {
      final missing = _join(_tempDir().path, 'no_such_review.json');
      final dir = _tempDir().path;
      for (final args in [
        ['resolve', missing],
        ['export', missing, '--target', 'csv', '-o', 'out.csv'],
        ['resolve', dir],
        ['export', dir, '--target', 'csv', '-o', 'out.csv'],
      ]) {
        final stderrText = _runCli(args).stderr as String;
        expect(stderrText, isNot(contains('PathNotFoundException')),
            reason: args.join(' '));
        expect(stderrText, isNot(contains('Unhandled exception')),
            reason: args.join(' '));
        expect(stderrText, isNot(contains('#0')), reason: args.join(' '));
      }
    });

    test('an existing review file still exports', () {
      final review = _reviewFile();
      final out = _join(review.dir, 'shelf.csv');
      final result =
          _runCli(['export', review.file, '--target', 'csv', '-o', out]);
      expect(result.exitCode, 0);
      expect(result.stdout, contains('Exported 1 of 1 approved game(s)'));
      expect(
          File(out).readAsStringSync(),
          'title,platform,media_type,external_id,source_photo\r\n'
          'Crown of Tidefall,PlayStation 5,disc,igdb:1100000048,shelf_b.jpg\r\n');
    });

    test('an existing review file gets past the check into resolve proper', () {
      final result = _runCli(['resolve', _reviewFile().file]);
      expect(result.stderr, isNot(contains('review file at')));
      // Without credentials the next gate is the one that stops it; that it
      // is reached at all is what says the path was accepted. Resolving for
      // real needs IGDB, which resolve_command_test stubs.
      expect(result.stderr, contains('needs IGDB credentials'));
      expect(result.exitCode, 2);
    });
  });
}
