/// The capability pre-flight, through the real CLI and a real socket (T-0464).
///
/// The unit tests beside this one hold the parsing and the policy. What only a
/// whole run can answer is the part the brief asserts by counting rather than
/// by reading: **one `/api/show` per run whatever the photo count**, and a
/// refusal that costs no vision call at all. Both are properties of the wiring
/// and neither is visible from the provider.
///
/// The stand-in server is a loopback `HttpServer` and the CLI is a real
/// subprocess, so the wire, the argument parsing, the exit code and the
/// written file are all real and only the model is a fixture. Every fixture in
/// it is invented.
@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';

import 'cli_snapshot.dart';

/// The smallest thing `sniffImage` calls a JPEG.
final _jpegBytes =
    Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, ...List.filled(64, 0)]);

/// A model id nothing here has published, which is the point: the policy reads
/// what the server says and never the name.
const _model = 'nimbus-vision:7b';

/// One shelf, answered the same way for every photograph.
const _answer = '{"items":[{"raw_title":"Vellum Compass",'
    '"platform_hint":"PS4","media_type":"disc","confidence":0.9}],'
    '"unreadable":[]}';

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

/// A loopback stand-in for Ollama that records the route of every request.
///
/// [capabilities] null means the answer carries no `capabilities` key at all,
/// which is the older-Ollama case. [showStatus] other than 200 is the route
/// that is not there.
Future<(Uri, List<String>)> _stubOllama({
  List<String>? capabilities = const ['completion', 'vision'],
  int showStatus = 200,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  addTearDown(() => server.close(force: true));
  final routes = <String>[];
  server.listen((request) async {
    await request.drain<void>();
    routes.add(request.uri.path);
    request.response.headers.contentType = ContentType.json;
    if (request.uri.path == '/api/show') {
      request.response.statusCode = showStatus;
      request.response.write(showStatus == 200
          ? jsonEncode({
              'details': {'family': 'invented'},
              if (capabilities != null) 'capabilities': capabilities,
            })
          : jsonEncode({'error': "model '$_model' not found"}));
    } else {
      request.response.write(jsonEncode({
        'message': {'content': _answer},
        'done_reason': 'stop',
      }));
    }
    await request.response.close();
  });
  return (
    Uri.parse('http://${server.address.address}:${server.port}'),
    routes,
  );
}

/// Async, not `runSync`: the stand-in server lives in this isolate, and a
/// synchronous wait blocks the event loop that would have answered the child.
Future<ProcessResult> _runCli(List<String> args, {required Uri ollama}) =>
    Process.run(
      Platform.resolvedExecutable,
      [cliSnapshot(), ...args],
      environment: {
        'SHELFSCAN_OLLAMA_URL': ollama.toString(),
        'SHELFSCAN_OLLAMA_MODEL': _model,
        // Blanked so a machine that has credentials cannot turn this into a
        // live API call: every row comes back unresolved, which is the
        // documented skip.
        'IGDB_CLIENT_ID': '',
        'IGDB_CLIENT_SECRET': '',
        'SHELFSCAN_TMDB_TOKEN': '',
      },
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );

int _count(List<String> routes, String path) =>
    routes.where((route) => route == path).length;

void main() {
  setUpAll(cliSnapshot);

  late Directory photos;
  late Directory outs;
  late String out;

  setUp(() {
    photos = _tempDir('shelfscan_preflight_photos_');
    outs = _tempDir('shelfscan_preflight_out_');
    out = _join(outs.path, 'collection.review.json');
    for (final name in const ['shelf1.jpg', 'shelf2.jpg', 'shelf3.jpg']) {
      File(_join(photos.path, name)).writeAsBytesSync(_jpegBytes);
    }
  });

  test('three photographs ask the model question once', () async {
    final (ollama, routes) = await _stubOllama();

    final result = await _runCli(['scan', photos.path, '-o', out],
        ollama: ollama);

    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
    expect(_count(routes, '/api/show'), 1,
        reason: 'the question is about the model, not about a photograph');
    expect(_count(routes, '/api/chat'), 3);
    // Nothing that would download, load or unload anything.
    expect(routes.toSet(), {'/api/show', '/api/chat'});
  });

  test('a model the server says has no vision is refused, before any photo',
      () async {
    final (ollama, routes) =
        await _stubOllama(capabilities: const ['completion', 'tools']);

    final result = await _runCli(['scan', photos.path, '-o', out],
        ollama: ollama);

    // Exit 2, the pre-flight code the other configuration refusals use.
    expect(result.exitCode, 2);
    expect(result.stderr, contains('has no vision capability'));
    expect(result.stderr, contains('needs an image-capable model'));
    expect(result.stderr, contains(_model));
    // The whole point of a pre-flight: no photograph was spent finding out.
    expect(_count(routes, '/api/chat'), 0);
    expect(File(out).existsSync(), isFalse);
  });

  test('a model that reasons first runs, and says so once', () async {
    final (ollama, routes) = await _stubOllama(
        capabilities: const ['completion', 'vision', 'tools', 'thinking']);

    final result = await _runCli(['scan', photos.path, '-o', out],
        ollama: ollama);

    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
    expect(result.stderr, contains('WARN: '));
    expect(result.stderr, contains('reasons before it answers'));
    expect('WARN: '.allMatches(result.stderr as String), hasLength(1));
    // Warned, not blocked: the run read every photograph and wrote its file.
    expect(_count(routes, '/api/chat'), 3);
    expect(File(out).existsSync(), isTrue);
  });

  test('a model with vision and no thinking says nothing at all', () async {
    final (ollama, _) = await _stubOllama();

    final result = await _runCli(['scan', photos.path, '-o', out],
        ollama: ollama);

    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
    expect(result.stderr, isNot(contains('reasons before it answers')));
    expect(result.stderr, isNot(contains('vision capability')));
  });

  group('a probe that got no answer never fails a scan', () {
    test('a 404 on the manifest route', () async {
      final (ollama, routes) = await _stubOllama(showStatus: 404);

      final result = await _runCli(['scan', photos.path, '-o', out],
          ollama: ollama);

      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      expect(_count(routes, '/api/chat'), 3);
      expect(result.stderr, isNot(contains('vision capability')));
    });

    test('an Ollama old enough to publish no capabilities', () async {
      final (ollama, routes) = await _stubOllama(capabilities: null);

      final result = await _runCli(['scan', photos.path, '-o', out],
          ollama: ollama);

      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      expect(_count(routes, '/api/chat'), 3);
      expect(result.stderr, isNot(contains('reasons before it answers')));
    });
  });

  test('the banner says what makes a local model a good fit', () async {
    final result = await Process.run(
      Platform.resolvedExecutable,
      [cliSnapshot()],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );

    expect(result.exitCode, 2);
    expect(result.stderr, contains('Choosing a local model:'));
    expect(result.stderr, contains('image-capable'));
    expect(result.stderr, contains('one concise structured answer'));
  });
}
