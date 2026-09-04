/// Guards all three commands against paying for a run and then losing it to a
/// mistyped `-o` (T-0051).
///
/// The last of the four input-path defects, and the expensive one: T-0037,
/// T-0049 and T-0050 all failed before anything had been done, while this one
/// failed at `File(outPath).writeAsStringSync(...)` -- the last statement of a
/// scan, after the whole vision run had been paid for -- with an unhandled
/// `PathNotFoundException` and exit 255. So there are three claims, not two:
///   1. the wording, with the path absolute and normalised, as in the other
///      three;
///   2. the process really exits 2 and prints no Dart frames;
///   3. on `scan` the refusal lands BEFORE the first provider call. That one
///      cannot be shown by reading the source, so the vision provider here is
///      a loopback stub that counts requests: the bad-`-o` run must leave it
///      at zero, and the control run with a good `-o` must move it off zero,
///      which is what makes the zero mean "the check ran first" rather than
///      "the scan never got that far".
///
/// Nothing here reaches a network or a provider. `SHELFSCAN_OLLAMA_URL` points
/// at the in-test stub on 127.0.0.1, the IGDB variables are blanked so the
/// resolve stage is skipped, and `SHELFSCAN_OLLAMA_FALLBACK_MODEL` is blanked
/// so a machine that has one set cannot escalate.
///
/// The budget is headroom for a slower machine, not a claim about any
/// duration. This was the most load-sensitive file in the suite: it spawns 14
/// CLI children, and until T-0217 each one front-end compiled the entry point
/// from source, because `dart run` on a file path writes no snapshot. They now
/// run the kernel snapshot `cli_snapshot.dart` builds once per run, measured
/// to take a child from 2.29 s to 0.32 s. The budget is left exactly where
/// T-0203 put it: it was headroom then and it is more of it now, and widening
/// an allowance in the same task that shrank the work would hide which of the
/// two did anything.
@Timeout(Duration(minutes: 6))
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../bin/shelfscan.dart' show outputPathError;
import 'cli_snapshot.dart';

Directory _tempDir() {
  final dir = Directory.systemTemp.createTempSync('shelfscan_output_path_');
  // Same Windows errno 145 race the other three path suites document: the
  // recursive delete loses to handles that have only just closed.
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

/// A photo directory `scan` will accept: one file with a read extension.
///
/// The bytes are never decoded here -- the stub answers whatever it is sent --
/// so what matters is only that [readPhotoDirectory] takes the file and that
/// no HEIC conversion is triggered.
String _photoDir() {
  final dir = _tempDir();
  File(_join(dir.path, 'shelf_a.jpg')).writeAsBytesSync([0xff, 0xd8, 0xff]);
  return dir.path;
}

/// One approved, resolved game -- the smallest document `export` can carry.
const _reviewFixture = {
  'version': 1,
  'created': '2026-08-14T09:00:00.000000Z',
  'photos': ['shelf_b.jpg'],
  'games': [
    {
      'detection': {
        'raw_title': 'CROWN OF TIDEFALL',
        'platform_hint': 'PS5',
        'media_type': 'disc',
        'confidence': 1.0,
        'source_photo': 'shelf_b.jpg',
      },
      'best': {
        'igdb_id': 1100000048,
        'title': 'Crown of Tidefall',
        'platform_id': 167,
        'platform_name': 'PlayStation 5',
        'score': 1.0,
      },
      'candidates': <Object>[],
      'status': 'approved',
    },
  ],
};

({String file, String dir}) _reviewFile() {
  final dir = _tempDir();
  final file = _join(dir.path, 'collection.review.json');
  File(file).writeAsStringSync(jsonEncode(_reviewFixture));
  return (file: file, dir: dir.path);
}

/// A stand-in for the local Ollama server that records every call.
///
/// Loopback and in-process: the point of it is the counter, so that "the
/// provider was never called" is a measurement rather than an argument.
class _StubVision {
  _StubVision(this._server) {
    _server.listen((request) async {
      // The vision route alone. Since T-0464 a scan also reads the model's
      // manifest from /api/show before stage 1, and what this counter is about
      // is what the provider spent -- not how many sockets were opened.
      if (request.uri.path == '/api/chat') calls += 1;
      await request.drain<void>();
      request.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'message': {
            'content': jsonEncode({
              'items': [
                {'raw_title': 'COBALT CHIME', 'media_type': 'cartridge'},
              ],
            }),
          },
        }));
      await request.response.close();
    });
  }

  static Future<_StubVision> start() async =>
      _StubVision(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  final HttpServer _server;
  var calls = 0;

  String get url => 'http://127.0.0.1:${_server.port}';

  Future<void> stop() => _server.close(force: true);
}

/// [Process.run], never `runSync`: the stub above shares this isolate's event
/// loop, and a synchronous wait would block the very server the child is
/// talking to.
Future<ProcessResult> _runCli(List<String> args, {String? ollamaUrl}) =>
    Process.run(
      Platform.resolvedExecutable,
      [cliSnapshot(), ...args],
      environment: {
        'IGDB_CLIENT_ID': '',
        'IGDB_CLIENT_SECRET': '',
        'SHELFSCAN_TMDB_TOKEN': '',
        'SHELFSCAN_OLLAMA_FALLBACK_MODEL': '',
        if (ollamaUrl != null) 'SHELFSCAN_OLLAMA_URL': ollamaUrl,
      },
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );

List<String> _lines(Object? stderrText) =>
    const LineSplitter().convert(stderrText as String);

void main() {
  setUpAll(cliSnapshot);

  group('outputPathError', () {
    test('a writable path in an existing directory is not an error', () {
      expect(outputPathError(_join(_tempDir().path, 'out.csv')), isNull);
    });

    test('checking leaves nothing behind', () {
      final dir = _tempDir();
      final out = _join(dir.path, 'out.csv');
      expect(outputPathError(out), isNull);
      expect(File(out).existsSync(), isFalse,
          reason: 'the probe must not create the output file');
      expect(dir.listSync(), isEmpty);
    });

    test('an existing file is fine and is not truncated by the check', () {
      final out = _join(_tempDir().path, 'out.csv');
      File(out).writeAsStringSync('title,platform\r\n');
      expect(outputPathError(out), isNull);
      expect(File(out).readAsStringSync(), 'title,platform\r\n');
    });

    test('a missing directory names it, and the file it would have held', () {
      final dir = _tempDir().path;
      final message = outputPathError(_join(_join(dir, 'nope'), 'out.csv'))!;
      expect(message, startsWith('No output directory at ${_join(dir, 'nope')}'));
      expect(message, contains(_join(_join(dir, 'nope'), 'out.csv')));
      expect(message, isNot(contains('\n')));
    });

    test('a file where a directory should be is named as a file', () {
      final dir = _tempDir().path;
      final file = _join(dir, 'notes.txt');
      File(file).writeAsStringSync('x');
      final message = outputPathError(_join(file, 'out.csv'))!;
      expect(message, startsWith('Not an output directory: $file is a file'));
      expect(message, contains('-o writes'));
    });

    test('a directory as the output path is named as a directory', () {
      final dir = _tempDir().path;
      final message = outputPathError(dir)!;
      expect(message, startsWith('Not an output file: $dir is a directory'));
      expect(message, contains('not the directory to write it into'));
    });

    test('a relative path is answered with where it actually pointed', () {
      final message = outputPathError('no_such_out_dir/out.csv')!;
      expect(message,
          contains(_join(Directory.current.path, 'no_such_out_dir')));
    });

    test('.. is resolved away rather than echoed back', () {
      final message = outputPathError('sub/../no_such_out_dir/out.csv')!;
      expect(message, isNot(contains('..')));
      expect(message,
          contains(_join(Directory.current.path, 'no_such_out_dir')));
    });
  });

  group('the CLI process', () {
    test('has bin/shelfscan.dart under the working directory', () {
      expect(File('bin/shelfscan.dart').existsSync(), isTrue,
          reason: 'run `dart test` from packages/shelfscan_core');
    });

    test('every command exits 2 with one line on a missing -o directory',
        () async {
      final review = _reviewFile();
      final bad = _join(_join(_tempDir().path, 'nope'), 'out.json');
      for (final args in [
        ['scan', _photoDir(), '-o', bad],
        ['resolve', review.file, '-o', bad],
        ['export', review.file, '--target', 'csv', '-o', bad],
      ]) {
        final result = await _runCli(args);
        expect(result.exitCode, 2, reason: args.first);
        expect(result.stderr, contains('No output directory at'),
            reason: args.first);
        expect(_lines(result.stderr), hasLength(1), reason: args.first);
      }
    });

    test('prints no Dart frames for any of the three', () async {
      final review = _reviewFile();
      final bad = _join(_join(_tempDir().path, 'nope'), 'out.json');
      for (final args in [
        ['scan', _photoDir(), '-o', bad],
        ['resolve', review.file, '-o', bad],
        ['export', review.file, '--target', 'csv', '-o', bad],
      ]) {
        final stderrText = (await _runCli(args)).stderr as String;
        expect(stderrText, isNot(contains('PathNotFoundException')),
            reason: args.first);
        expect(stderrText, isNot(contains('Unhandled exception')),
            reason: args.first);
        expect(stderrText, isNot(contains('#0')), reason: args.first);
      }
    });

    test('a directory given to -o is refused too', () async {
      final review = _reviewFile();
      final result = await _runCli(
          ['export', review.file, '--target', 'csv', '-o', review.dir]);
      expect(result.exitCode, 2);
      expect(result.stderr, contains('Not an output file: ${review.dir}'));
      expect(_lines(result.stderr), hasLength(1));
    });

    test('resolve refuses before it asks for IGDB credentials', () async {
      // The output check is worth nothing behind a gate that sends the user
      // off to register a Twitch application first.
      final bad = _join(_join(_tempDir().path, 'nope'), 'out.json');
      final result = await _runCli(['resolve', _reviewFile().file, '-o', bad]);
      expect(result.stderr, contains('No output directory at'));
      expect(result.stderr, isNot(contains('IGDB')));
      expect(result.stdout, isNot(contains('IGDB')));
    });

    test('export writes nothing and still exports to a good path', () async {
      final review = _reviewFile();
      final out = _join(review.dir, 'shelf.csv');
      expect((await _runCli(['export', review.file, '--target', 'csv', '-o',
              _join(_join(review.dir, 'nope'), 'shelf.csv')]))
          .exitCode,
          2);
      expect(Directory(review.dir).listSync().map((e) => e.path),
          [review.file]);

      final ok =
          await _runCli(['export', review.file, '--target', 'csv', '-o', out]);
      expect(ok.exitCode, 0);
      expect(
          File(out).readAsStringSync(),
          'title,platform,media_type,external_id,source_photo\r\n'
          'Crown of Tidefall,PlayStation 5,disc,igdb:1100000048,shelf_b.jpg\r\n');
    });

    test('an existing output file is still overwritten in place', () async {
      final review = _reviewFile();
      final out = _join(review.dir, 'shelf.csv');
      File(out).writeAsStringSync('stale contents from an earlier export\n');
      final result =
          await _runCli(['export', review.file, '--target', 'csv', '-o', out]);
      expect(result.exitCode, 0);
      expect(File(out).readAsStringSync(), startsWith('title,platform'));
      expect(File(out).readAsStringSync(), isNot(contains('stale')));
    });
  });

  group('scan refuses before the first provider call', () {
    late _StubVision stub;

    setUp(() async {
      stub = await _StubVision.start();
      addTearDown(stub.stop);
    });

    test('a bad -o leaves the vision provider untouched', () async {
      final bad = _join(_join(_tempDir().path, 'nope'), 'collection.json');
      final result =
          await _runCli(['scan', _photoDir(), '-o', bad], ollamaUrl: stub.url);
      expect(result.exitCode, 2);
      expect(result.stderr, contains('No output directory at'));
      // The whole claim of this task: a check that runs after the vision
      // stage is worth almost nothing, so zero is the assertion, not "the
      // message was printed".
      expect(stub.calls, 0);
    });

    test('the same scan with a good -o does reach it', () async {
      // The control that gives the zero above its meaning: same photo
      // directory, same stub, only the -o differs.
      final dir = _tempDir().path;
      final out = _join(dir, 'collection.review.json');
      final result =
          await _runCli(['scan', _photoDir(), '-o', out], ollamaUrl: stub.url);
      expect(result.exitCode, 0, reason: result.stderr as String);
      expect(stub.calls, 1);
      final written = jsonDecode(File(out).readAsStringSync())
          as Map<String, dynamic>;
      expect((written['games'] as List<dynamic>).single, isA<Object>());
      expect(result.stdout, contains('1 game(s) detected'));
    });

    test('a scan over an existing review file overwrites it', () async {
      final dir = _tempDir().path;
      final out = _join(dir, 'collection.review.json');
      File(out).writeAsStringSync('{"version": 1, "stale": true}');
      final result =
          await _runCli(['scan', _photoDir(), '-o', out], ollamaUrl: stub.url);
      expect(result.exitCode, 0, reason: result.stderr as String);
      expect(File(out).readAsStringSync(), isNot(contains('stale')));
      expect(File(out).readAsStringSync(), contains('COBALT CHIME'));
    });
  });
}
