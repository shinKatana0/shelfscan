/// Guards `scan` against presenting a mistyped path as a crash (T-0037).
///
/// The path argument was the one bad input in this CLI that reached the user
/// as an unhandled `PathNotFoundException` and a six-frame stack trace out of
/// `dir.listSync()`, while every other one (unknown provider, unknown export
/// target, missing credentials) is a single stderr line and exit 2. So the
/// claims worth pinning down are the two halves of that:
///   1. the wording, and that the path comes back absolute -- the whole
///      failure is a relative path resolved against an unexpected directory;
///   2. the process really exits 2 and prints no Dart frames, which only a
///      real run of the CLI can show.
///
/// The subprocess group is deliberately confined to paths that fail before
/// any provider is constructed, so nothing here can reach a network.
@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../bin/shelfscan.dart' show noPhotosMessage, readPhotoDirectory, scanPathError;

Directory _tempDir() {
  final dir = Directory.systemTemp.createTempSync('shelfscan_scan_path_');
  // Measured here, roughly 1 run in 3 of the full suite: Windows fails the
  // recursive delete with errno 145 ("directory not empty") when it races the
  // handles just closed. A leaked temp directory is not worth a red suite.
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

ProcessResult _runScan(String path) => Process.runSync(
      Platform.resolvedExecutable,
      ['run', 'bin/shelfscan.dart', 'scan', path],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );

void main() {
  group('scanPathError', () {
    test('a directory that exists is not an error', () {
      expect(scanPathError(_tempDir().path), isNull);
    });

    test('a missing path names the absolute path it looked for', () {
      final missing = _join(_tempDir().path, 'nope');
      final message = scanPathError(missing)!;
      expect(message, 'No photo directory at $missing');
    });

    test('a relative path is answered with where it actually pointed', () {
      final message = scanPathError('no_such_photos_dir_here')!;
      expect(message,
          contains(_join(Directory.current.path, 'no_such_photos_dir_here')));
      expect(message, isNot(contains('no_such_photos_dir_here\n')));
    });

    test('.. is resolved away rather than echoed back', () {
      final message = scanPathError('sub/../no_such_photos_dir_here')!;
      expect(message, isNot(contains('..')));
      expect(message,
          contains(_join(Directory.current.path, 'no_such_photos_dir_here')));
    });

    test('a file is named as a file, not as a missing directory', () {
      final file = _join(_tempDir().path, 'shelf_a.jpg');
      File(file).writeAsBytesSync([0]);
      final message = scanPathError(file)!;
      expect(message, startsWith('Not a photo directory: $file'));
      expect(message, contains('is a file'));
      expect(message, contains('directory that holds your photos'));
    });

    test('a directory holding no photo is left to noPhotosMessage', () {
      final dir = _tempDir();
      File(_join(dir.path, 'notes.txt')).writeAsBytesSync([0]);
      expect(scanPathError(dir.path), isNull);
      // The more informative message survives: it names what was there.
      expect(
          noPhotosMessage(readPhotoDirectory(dir), dir.path,
              convertsHeic: false),
          contains('.txt x1'));
    });
  });

  group('the CLI process', () {
    test('has bin/shelfscan.dart under the working directory', () {
      expect(File('bin/shelfscan.dart').existsSync(), isTrue,
          reason: 'run `dart test` from packages/shelfscan_core');
    });

    test('exits 2 with one line on a missing directory', () {
      final result = _runScan(_join(_tempDir().path, 'nope'));
      expect(result.exitCode, 2);
      expect(result.stderr, contains('No photo directory at'));
      expect(const LineSplitter().convert(result.stderr as String), hasLength(1));
    });

    test('exits 2 with one line on a file', () {
      final file = _join(_tempDir().path, 'shelf_a.jpg');
      File(file).writeAsBytesSync([0]);
      final result = _runScan(file);
      expect(result.exitCode, 2);
      expect(result.stderr, contains('Not a photo directory:'));
      expect(const LineSplitter().convert(result.stderr as String), hasLength(1));
    });

    test('prints no Dart frames for either', () {
      for (final path in [
        _join(_tempDir().path, 'nope'),
        (() {
          final file = _join(_tempDir().path, 'shelf_a.jpg');
          File(file).writeAsBytesSync([0]);
          return file;
        })(),
      ]) {
        final stderrText = _runScan(path).stderr as String;
        expect(stderrText, isNot(contains('PathNotFoundException')));
        expect(stderrText, isNot(contains('Unhandled exception')));
        expect(stderrText, isNot(contains('#0')));
      }
    });

    test('an empty directory keeps its own message and exit 1', () {
      final result = _runScan(_tempDir().path);
      expect(result.exitCode, 1);
      expect(result.stderr, contains('No files to scan in'));
    });
  });
}
