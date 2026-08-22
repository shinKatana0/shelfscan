/// A scan where every photo failed is not a scan (T-0072).
///
/// With a mistyped Claude model id the run used to finish, write a review
/// document with zero games, and print `Scanned 3 photo(s): 0 game(s)
/// detected` -- a successful-looking run beside a wall of raw provider JSON.
/// The two claims that closes are pinned here: nothing is written, and the
/// process exits 2 with one line saying why.
///
/// The asymmetry T-0030 built is the other half and is pinned here too: one
/// photo of three failing is a partial result the user may want, and it still
/// warns and still returns the other two (detection_order_test.dart pins the
/// row ORDER of that same case).
///
/// Nothing here reaches a network. The subprocess group points the CLI at a
/// loopback stub that answers 404 to everything, which is the only way to
/// assert an exit code and an unwritten file.
@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

/// Measured, api.openai.com, 2026-08-15: a model id that does not exist.
const _notFoundBody = '{"error":{"message":"The model `nope-4` does not exist '
    'or you do not have access to it.","type":"invalid_request_error",'
    '"param":null,"code":"model_not_found"}}';

PhotoInput _photo(String name) =>
    PhotoInput(name: name, bytes: Uint8List.fromList([1, 2, 3]));

Detection _read(String title, String photo) => Detection(
      rawTitle: title,
      mediaType: MediaType.disc,
      confidence: 1.0,
      sourcePhoto: photo,
    );

/// Fails the named photos the way a wrong model id does, reads the rest.
class _PartlyFailingProvider implements VisionProvider {
  _PartlyFailingProvider(this.failing);

  final Set<String> failing;

  @override
  Future<PhotoAnalysis> analyze(PhotoInput photo) async {
    if (failing.contains(photo.name)) {
      throw VisionApiException(
          'Anthropic has no model "claude-4-typo" (HTTP 404): that model id '
          'was not found.',
          statusCode: 404,
          body: _notFoundBody,
          causeIsUserSet: true);
    }
    return PhotoAnalysis(items: [_read('VEX ${photo.name}', photo.name)]);
  }
}

Future<ReviewDocument> _scan(List<PhotoInput> photos, VisionProvider provider,
        {List<String>? warnings}) =>
    Orchestrator(
      visionWorker: VisionWorker(provider),
      resolverWorker: SkipResolver(),
      visionConcurrency: photos.length,
    ).runScan(photos,
        progress: ScanProgress(
            onWarning: (w) => warnings?.add(w.message)));

// --- the CLI, end to end ---------------------------------------------- //

Directory _tempDir() {
  final dir = Directory.systemTemp.createTempSync('shelfscan_all_failed_');
  addTearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows races the handles just closed; a leaked temp directory is not
      // worth a red suite (scan_path_test.dart measured this at ~1 run in 3).
    }
  });
  return dir;
}

/// A photo the CLI will accept: it identifies files by signature, not by name.
void _writePhoto(String path) => File(path)
    .writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xE0, ...List.filled(16, 0)]);

/// An OpenAI-shaped endpoint on loopback that refuses every request.
Future<HttpServer> _refusingEndpoint() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  addTearDown(() => server.close(force: true));
  server.listen((request) async {
    await request.drain<void>();
    request.response
      ..statusCode = 404
      ..headers.contentType = ContentType.json
      ..write(_notFoundBody);
    await request.response.close();
  });
  return server;
}

void main() {
  group('every photo failed', () {
    test('no document comes back, and the reason is stated once', () async {
      final photos = [_photo('a.jpg'), _photo('b.jpg'), _photo('c.jpg')];
      final provider = _PartlyFailingProvider({'a.jpg', 'b.jpg', 'c.jpg'});

      await expectLater(
        _scan(photos, provider),
        throwsA(isA<ScanFailedException>()
            .having((e) => e.failures.map((f) => f.$1), 'photos',
                ['a.jpg', 'b.jpg', 'c.jpg'])
            .having((e) => e.message, 'message',
                allOf(contains('All 3 photo(s) failed'),
                    contains('no review document'), contains('404')))),
      );
    });

    test('the shared cause is named, not counted three times', () async {
      final photos = [_photo('a.jpg'), _photo('b.jpg')];
      final error = await _scan(photos, _PartlyFailingProvider({'a.jpg', 'b.jpg'}))
          .then<Object?>((_) => null, onError: (Object e) => e);

      final message = (error as ScanFailedException).message;
      expect('404'.allMatches(message), hasLength(1));
      // The per-photo lines are the warning channel's job, and they were
      // already emitted; the summary is the line that gets read.
      expect(message, isNot(contains('a.jpg')));
    });

    test('every photo still warned on its way out', () async {
      final warnings = <String>[];
      await _scan([_photo('a.jpg'), _photo('b.jpg')],
              _PartlyFailingProvider({'a.jpg', 'b.jpg'}),
              warnings: warnings)
          .then<void>((_) {}, onError: (Object _) {});

      expect(warnings, hasLength(2));
      expect(warnings.join(), contains('claude-4-typo'));
    });

    test('a photo read to zero games is an answer, not a failure', () async {
      // The line is drawn at refused CALLS: a shelf can legitimately hold
      // nothing this pipeline recognises, and that must still produce a file.
      final doc = await _scan(
          [_photo('a.jpg')],
          _EmptyProvider());

      expect(doc.games, isEmpty);
      expect(doc.photos, ['a.jpg']);
    });
  });

  group('one photo of three (T-0030)', () {
    test('the other two still come back, and the failure still warns',
        () async {
      final warnings = <String>[];
      final doc = await _scan(
        [_photo('a.jpg'), _photo('b.jpg'), _photo('c.jpg')],
        _PartlyFailingProvider({'b.jpg'}),
        warnings: warnings,
      );

      expect([for (final game in doc.games) game.detection.rawTitle],
          ['VEX a.jpg', 'VEX c.jpg']);
      expect(warnings.single, contains('b.jpg'));
      expect(warnings.single, contains('claude-4-typo'));
    });
  });

  group('the CLI process', () {
    test('exits 2, writes nothing, and never says the scan succeeded',
        () async {
      final server = await _refusingEndpoint();
      final dir = _tempDir();
      _writePhoto('${dir.path}/shelf_a.jpg');
      _writePhoto('${dir.path}/shelf_b.jpg');
      final out = '${dir.path}/collection.review.json';

      final result = await Process.run(
        Platform.resolvedExecutable,
        [
          'run',
          'bin/shelfscan.dart',
          'scan',
          dir.path,
          '--provider',
          'openai',
          '-o',
          out,
        ],
        environment: {
          'SHELFSCAN_OPENAI_BASE_URL':
              'http://127.0.0.1:${server.port}/v1',
          'SHELFSCAN_OPENAI_MODEL': 'nope-4',
          'SHELFSCAN_OPENAI_API_KEY': 'sk-not-a-real-key',
          // Emptied rather than removed: the CLI reads a set-but-empty
          // variable as unset (T-0080), and a developer host may have real ones.
          'IGDB_CLIENT_ID': '',
          'IGDB_CLIENT_SECRET': '',
          'SHELFSCAN_OLLAMA_FALLBACK_MODEL': '',
        },
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );

      expect(result.exitCode, 2);
      expect(File(out).existsSync(), isFalse,
          reason: 'a document with zero games is a claim the shelf was read');
      expect(result.stdout, isNot(contains('game(s) detected')));

      final stderrText = result.stderr as String;
      expect(stderrText, contains('All 2 photo(s) failed'));
      expect(stderrText, contains('nope-4'));
      expect(stderrText, contains('not found'));
      expect(stderrText, isNot(contains('Unhandled exception')));
      expect(stderrText, isNot(contains('#0')));
      // The summary itself is one line, as every other exit-2 failure is.
      expect(
          const LineSplitter()
              .convert(stderrText)
              .where((l) => l.startsWith('All 2 photo(s)')),
          hasLength(1));
    });
  });
}

/// Answers every photo with nothing at all, successfully.
class _EmptyProvider implements VisionProvider {
  @override
  Future<PhotoAnalysis> analyze(PhotoInput photo) async =>
      const PhotoAnalysis();
}
