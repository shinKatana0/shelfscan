/// What an endpoint that accepts the connection and then says nothing tells
/// the user (T-0104).
///
/// The fourth file in the line `vision_failure_text_test.dart` (T-0072, cloud
/// statuses), `ollama_failure_text_test.dart` (T-0097, the local provider and
/// a server that is not there) and `cloud_unreachable_test.dart` (T-0103, the
/// cloud half of that). Those three all end in an exception the socket handed
/// over. This one is the case where the socket hands nothing over at all:
/// before this task no call in the package set a timeout, so the CLI sat at
/// `vision` and the app at `Scanning` for as long as anyone let them.
///
/// Every stall below is a real loopback `ServerSocket` that reads the request
/// and never writes a byte -- no mock stands in for the silence anywhere. The
/// two endpoints this repository hardcodes (Anthropic's URL, IGDB's) are
/// reached through [_ToLoopback], which rewrites the address and delegates to a
/// real `http.Client`: the wire, the stall and the timeout are real, and only
/// the host is redirected.
///
/// Timeouts are passed explicitly at 1-2 s so the suite does not sit through
/// the shipped budget. The shipped budget itself is exercised once, by the 35 s
/// answer that must NOT be aborted -- that provider is constructed with no
/// timeout argument at all.
///
/// The file budget is the axe for a hang, not a claim about any duration: no
/// test here can legitimately outlast the 35 s answer plus the shipped 120 s
/// bound, so 155 s is the ceiling and 6 minutes is 2.3x it. It was 4 minutes
/// until T-0203, which measured the 35 s test at 35.0 s idle and 35.0-35.1 s
/// under four concurrent full-suite runs -- a wall-clock wait does not inflate
/// under load, so this number is headroom for a slower machine and nothing
/// else.
@Timeout(Duration(minutes: 6))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

const _key = 'sk-not-a-real-key-000';
const _model = 'some-model';
const _fast = Duration(seconds: 1);

PhotoInput get _photo =>
    PhotoInput(name: 'shelf.jpg', bytes: Uint8List.fromList([1, 2, 3]));

/// One detection, in each provider's own envelope.
const _ollamaBody = '{"message":{"content":"{\\"items\\":[{\\"raw_title\\":'
    '\\"Duskhollow\\",\\"confidence\\":0.9}]}"}}';

/// What a reply to [path] should be: null is the stall this file is about.
typedef _Reply = String? Function(String path);

final _closers = <Future<void> Function()>[];

/// A loopback server that replies per [reply] and holds the connection open
/// forever when it returns null.
///
/// Raw rather than `HttpServer` because the silence has to be exact: what is
/// being reproduced is a socket that completes the handshake, reads the
/// request and then writes nothing, which is what a stalled proxy or a wedged
/// model runner leaves behind.
Future<int> _stallServer(_Reply reply, {Duration? after}) async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final live = <Socket>[];
  server.listen((socket) {
    live.add(socket);
    // Once per request line rather than once per connection: `http.Client`
    // keeps the connection alive, so IgdbClient's token and its searches all
    // arrive down one socket and a server that answers only the first of them
    // stalls the rest by accident.
    socket.listen((data) {
      for (final line in String.fromCharCodes(data).split('\r\n')) {
        final parts = line.split(' ');
        if (parts.length != 3 || !parts[2].startsWith('HTTP/')) continue;
        final body = reply(parts[1]);
        if (body == null) continue;
        void write() => socket.write('HTTP/1.1 200 OK\r\n'
            'content-type: application/json\r\n'
            'content-length: ${utf8.encode(body).length}\r\n'
            '\r\n$body');
        after == null ? write() : Future<void>.delayed(after, write);
      }
    }, onError: (_) {}, cancelOnError: true);
  });
  _closers.add(() async {
    for (final socket in live) {
      socket.destroy();
    }
    await server.close();
  });
  return server.port;
}

/// A header block with a `content-length` and then nothing.
///
/// The case that decides where the bound goes: `Client.post` reads the body
/// after `send` returns, so a wrapper on `send` alone lets this one through.
Future<int> _headersThenSilence() async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final live = <Socket>[];
  server.listen((socket) {
    live.add(socket);
    // Once: a second header block would arrive as the 40 bytes of body this
    // one promises, and the call would come back parseable instead of stalled.
    var wrote = false;
    socket.listen((_) {
      if (wrote) return;
      wrote = true;
      socket.write('HTTP/1.1 200 OK\r\n'
          'content-type: application/json\r\n'
          'content-length: 40\r\n'
          '\r\n');
    }, onError: (_) {}, cancelOnError: true);
  });
  _closers.add(() async {
    for (final socket in live) {
      socket.destroy();
    }
    await server.close();
  });
  return server.port;
}

/// Sends a request for an address this repository fixes to a loopback port.
///
/// A real `http.Client` underneath, so the stall, the socket and the timeout
/// are the real ones; only the host is rewritten. Injected clients are the
/// caller's to close, which is why every test that uses one registers it.
class _ToLoopback extends http.BaseClient {
  _ToLoopback(this.port);

  final int port;
  final http.Client _inner = http.Client();
  int calls = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    calls += 1;
    final copy = http.Request(
      request.method,
      request.url.replace(scheme: 'http', host: '127.0.0.1', port: port),
    )..bodyBytes = (request as http.Request).bodyBytes;
    for (final entry in request.headers.entries) {
      if (entry.key.toLowerCase() != 'content-length') {
        copy.headers[entry.key] = entry.value;
      }
    }
    return _inner.send(copy);
  }

  @override
  void close() => _inner.close();
}

_ToLoopback _redirected(int port) {
  final client = _ToLoopback(port);
  _closers.add(() async => client.close());
  return client;
}

/// The error one call raises, or a failure if it did not raise one.
Future<Object> _failure(Future<Object?> Function() call) async {
  try {
    await call();
  } catch (e) {
    return e;
  }
  throw StateError('the stalled endpoint was not reported');
}

/// Nothing that reads as a machine talking to a machine (the bar
/// `cloud_unreachable_test.dart` set for T-0103's sentences).
void _readsAsASentence(String message) {
  expect(message, isNot(contains('{')));
  expect(message, isNot(contains('Exception')));
  expect(message, isNot(contains('uri=')));
  expect(message, matches(RegExp(r'^[A-Z][^{}]*\.')), reason: message);
}

void main() {
  tearDown(() async {
    for (final close in _closers.reversed) {
      await close();
    }
    _closers.clear();
  });

  group('a server that accepts and never answers', () {
    test('Ollama says so instead of hanging', () async {
      final port = await _stallServer((_) => null);
      final error = await _failure(() => OllamaVisionProvider(
            baseUrl: 'http://127.0.0.1:$port',
            timeout: _fast,
          ).analyze(_photo));

      expect(error, isA<OllamaUnreachableException>());
      expect('$error',
          startsWith('Timed out after 1 s waiting for Ollama at '
              'http://127.0.0.1:$port'));
      _readsAsASentence('$error');
    });

    test('the OpenAI-compatible endpoint says so', () async {
      final port = await _stallServer((_) => null);
      final baseUrl = 'http://127.0.0.1:$port/v1';
      final error = await _failure(() => OpenAiCompatibleVisionProvider(
            baseUrl: baseUrl,
            model: _model,
            apiKey: _key,
            timeout: _fast,
          ).analyze(_photo));

      expect(error, isA<VisionUnreachableException>());
      expect('$error',
          startsWith('Timed out after 1 s waiting for the endpoint at '
              '$baseUrl'));
      _readsAsASentence('$error');
    });

    test('Anthropic says so, over a real socket at a rewritten address',
        () async {
      final port = await _stallServer((_) => null);
      final error = await _failure(() => AnthropicVisionProvider(
            apiKey: _key,
            model: _model,
            timeout: _fast,
            client: _redirected(port),
          ).analyze(_photo));

      expect(error, isA<VisionUnreachableException>());
      expect('$error',
          startsWith('Timed out after 1 s waiting for Anthropic at '
              'https://api.anthropic.com/v1/messages'));
      _readsAsASentence('$error');
    });

    test('an IGDB search says so, and names IGDB rather than Twitch', () async {
      final port = await _stallServer((path) =>
          path.contains('token') ? '{"access_token":"t","expires_in":3600}' : null);
      final error = await _failure(() => IgdbClient(
            clientId: 'id',
            clientSecret: 'secret',
            timeout: _fast,
            client: _redirected(port),
          ).search('duskhollow'));

      expect(error, isA<IgdbTimeoutException>());
      expect('$error',
          startsWith('Timed out after 1 s waiting for IGDB at '
              'https://api.igdb.com/v4'));
      _readsAsASentence('$error');
    });

    test('a stalled OAuth token names Twitch, which is the other host',
        () async {
      final port = await _stallServer((_) => null);
      final error = await _failure(() => IgdbClient(
            clientId: 'id',
            clientSecret: 'secret',
            timeout: _fast,
            client: _redirected(port),
          ).search('duskhollow'));

      expect((error as IgdbTimeoutException).service, 'Twitch');
      expect('$error', contains('https://id.twitch.tv/oauth2/token'));
    });

    test('headers with a content-length and then silence is still a stall',
        () async {
      // The bound is on post(), not on a BaseClient wrapper over send():
      // measured, a 3 s bound on send() never fires here because the headers
      // arrive at once and the body never does.
      final port = await _headersThenSilence();
      final error = await _failure(() => OllamaVisionProvider(
            baseUrl: 'http://127.0.0.1:$port',
            timeout: _fast,
          ).analyze(_photo));

      expect(error, isA<OllamaUnreachableException>());
      expect('$error', contains('Timed out after 1 s'));
    });
  });

  group('the sentence says what was waited for and how long', () {
    test('the number is the budget that was actually given', () async {
      final port = await _stallServer((_) => null);
      final error = await _failure(() => OllamaVisionProvider(
            baseUrl: 'http://127.0.0.1:$port',
            timeout: const Duration(seconds: 2),
          ).analyze(_photo));

      expect('$error', contains('Timed out after 2 s'));
      expect((error as OllamaUnreachableException).waited,
          const Duration(seconds: 2));
    });

    test('a stall is not the endpoint refusing, and does not read like one',
        () async {
      final stalled = await _stallServer((_) => null);
      final refusedPort = await () async {
        final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        final port = probe.port;
        await probe.close();
        return port;
      }();

      final stall = '${await _failure(() => OllamaVisionProvider(
            baseUrl: 'http://127.0.0.1:$stalled',
            timeout: _fast,
          ).analyze(_photo))}';
      // 10 s, not [_fast]: a refused connection costs 2.1 s on Windows
      // (T-0103 measured it; Windows retries the connect), so a bound tighter
      // than that reports a refusal as a stall -- which is how this test first
      // failed.
      final refusal = '${await _failure(() => OllamaVisionProvider(
            baseUrl: 'http://127.0.0.1:$refusedPort',
            timeout: const Duration(seconds: 10),
          ).analyze(_photo))}';

      expect(refusal, startsWith('Cannot reach Ollama at'));
      expect(stall, isNot(contains('Cannot reach')));
      expect(stall, contains('not even a refusal'));
      // T-0097's remedy is for a server that was never started; this one is
      // running and mute, and telling the user to start it would be wrong.
      expect(refusal, contains('ollama serve'));
      expect(stall, isNot(contains('ollama serve')));
    });

    test('no socket reason is invented for a failure the socket never reported',
        () async {
      final port = await _stallServer((_) => null);
      final error = await _failure(() => OpenAiCompatibleVisionProvider(
            baseUrl: 'http://127.0.0.1:$port/v1',
            model: _model,
            apiKey: _key,
            timeout: _fast,
          ).analyze(_photo));

      expect((error as VisionUnreachableException).reason, isEmpty);
      expect('$error', isNot(endsWith(')')));
    });

    test('the key is not in the line, and is not blamed', () async {
      final port = await _stallServer((_) => null);
      final message = '${await _failure(() => OpenAiCompatibleVisionProvider(
            baseUrl: 'http://127.0.0.1:$port/v1',
            model: _model,
            apiKey: _key,
            timeout: _fast,
          ).analyze(_photo))}';

      expect(message, isNot(contains(_key)));
      expect(message, contains('Neither the key nor the model id'));
    });

    test('the advice differs where the URL is the user\'s', () async {
      final port = await _stallServer((_) => null);
      final mine = '${await _failure(() => OpenAiCompatibleVisionProvider(
            baseUrl: 'http://127.0.0.1:$port/v1',
            model: _model,
            apiKey: _key,
            timeout: _fast,
          ).analyze(_photo))}';
      final theirs = '${await _failure(() => AnthropicVisionProvider(
            apiKey: _key,
            timeout: _fast,
            client: _redirected(port),
          ).analyze(_photo))}';

      expect(mine, contains('check that base URL first'));
      expect(theirs, isNot(contains('base URL')));
      expect(theirs, contains('fixed in this app'));
    });

    test('the all-photos-failed summary carries it once, as a sentence',
        () async {
      final port = await _stallServer((_) => null);
      final error = await Orchestrator(
        visionWorker: VisionWorker(OllamaVisionProvider(
          baseUrl: 'http://127.0.0.1:$port',
          timeout: _fast,
        )),
        resolverWorker: SkipResolver(),
        visionConcurrency: 2,
      )
          .runScan([_photo, PhotoInput(name: 'b.jpg', bytes: _photo.bytes)])
          .then<Object?>((_) => null, onError: (Object e) => e);
      final summary = (error as ScanFailedException).message;

      expect(summary, startsWith('All 2 photo(s) failed'));
      expect(summary, contains('Timed out after 1 s waiting for Ollama'));
      expect('Timed out'.allMatches(summary), hasLength(1));
      _readsAsASentence(summary);
    });
  });

  group('a slow answer is not a stall', () {
    test('a 35 s vision call succeeds under the shipped budget', () async {
      // The provider takes no timeout argument here on purpose: what is being
      // proven is that the number this package ships tolerates a read longer
      // than any this project has measured (34.5 s, T-0090).
      final port = await _stallServer((_) => _ollamaBody,
          after: const Duration(seconds: 35));
      final clock = Stopwatch()..start();
      final analysis = await OllamaVisionProvider(
        baseUrl: 'http://127.0.0.1:$port',
      ).analyze(_photo);

      expect(analysis.items.single.rawTitle, 'Duskhollow');
      expect(clock.elapsed, greaterThan(const Duration(seconds: 34)));
      expect(visionCallTimeout, greaterThan(const Duration(seconds: 35)));
    });

    test('IGDB is bounded far tighter, and that is a different measurement',
        () async {
      expect(igdbCallTimeout, lessThan(visionCallTimeout));
      expect(igdbCallTimeout, greaterThan(const Duration(seconds: 10)));
    });

    test('the rate limiter\'s own wait is not part of the budget', () async {
      // 8 searches at 4 rps means the last lane waits ~1 s for a slot; with the
      // bound around waitForSlot rather than the request, a tight timeout would
      // abort a request that had not been sent yet.
      final port = await _stallServer((path) => path.contains('token')
          ? '{"access_token":"t","expires_in":3600}'
          : '[]');
      final client = IgdbClient(
        clientId: 'id',
        clientSecret: 'secret',
        timeout: _fast,
        client: _redirected(port),
      );

      final hits = await Future.wait(
          [for (var i = 0; i < 8; i++) client.search('game $i')]);

      expect(hits, everyElement(isEmpty));
    });
  });

  group('a stalled photo is not retried', () {
    test('one call and one budget, not four of each', () async {
      final port = await _stallServer((_) => null);
      final client = _redirected(port);
      final worker = VisionWorker(AnthropicVisionProvider(
        apiKey: _key,
        timeout: _fast,
        client: client,
      ));
      final clock = Stopwatch()..start();

      await expectLater(
          worker.run(_photo), throwsA(isA<VisionUnreachableException>()));

      expect(client.calls, 1);
      // Retried it would be 4 calls plus 2+4+8 s of backoff.
      expect(clock.elapsed, lessThan(const Duration(seconds: 4)));
    });

    test('and it is not a RetryableException in the first place', () async {
      final port = await _stallServer((_) => null);

      expect(
          await _failure(() => IgdbClient(
                clientId: 'id',
                clientSecret: 'secret',
                timeout: _fast,
                client: _redirected(port),
              ).search('x')),
          isNot(isA<RetryableException>()));
    });
  });

  group('the run ends, and so does the process', () {
    test('a timed-out call leaves no connection holding the VM open', () async {
      // `Future.timeout` abandons the wait, not the socket: measured, a child
      // that caught its timeout and returned from main at 11 ms was still
      // running 146 s later, because a pending connection keeps the event loop
      // alive. That is the same hang moved to exit, so boundedPost closes the
      // client it owns.
      final port = await _stallServer((_) => null);
      final clock = Stopwatch()..start();
      final result = await Process.run(
        Platform.resolvedExecutable,
        ['run', 'test/stalled_exit_probe.dart', '$port'],
      );

      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      expect(result.stdout, contains('Timed out after 1 s waiting for Ollama'));
      expect(clock.elapsed, lessThan(const Duration(seconds: 60)));
    });
  });

  group('every outbound call is bounded', () {
    test('no request in lib/ posts outside boundedPost', () {
      final offenders = <String>[];
      for (final file in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final source = file.readAsStringSync();
        if (file.path.endsWith('http_timeout.dart')) continue;
        final posts = 'client.post('.allMatches(source).length;
        final bounded = 'boundedPost('.allMatches(source).length;
        if (posts != bounded) {
          offenders.add('${file.path}: $posts post(s), $bounded bounded');
        }
      }

      expect(offenders, isEmpty,
          reason: 'an unbounded request is the whole of T-0104');
    });
  });
}
