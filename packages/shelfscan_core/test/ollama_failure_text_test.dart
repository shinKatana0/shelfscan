/// What a refused LOCAL vision call tells the person running the server
/// (T-0097).
///
/// The sibling of `vision_failure_text_test.dart`, one task later and for the
/// provider T-0072 could not reach. `OllamaVisionProvider` threw
/// `Exception('Ollama <status>: <body>')`, so the server's own JSON was the
/// whole message -- and since T-0072 the all-photos-failed summary quotes the
/// shared cause, which put that JSON on the last line of the run as well. It
/// is the default provider on Windows, so this was the path most users are on.
///
/// The bodies are real, measured against the local server (Ollama 0.32.9) on
/// 2026-08-15, one call each. Nothing here reaches a network: the wire cases
/// go through a loopback stub or a closed loopback port, everything else
/// through `MockClient`.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

/// Measured: `/api/chat` for a tag that is not pulled. It echoes the model
/// back, which is the evidence the message keys on.
const _notPulled = '{"error":"model \'qwen2.5vl:7b\' not found"}';

/// Measured: the same request one path segment off the server root. Plain
/// text, from Ollama's own router, and it names no model.
const _wrongRoute = '404 page not found';

/// Measured: 8 bytes of fake JPEG. A whole JSON document encoded as a STRING
/// inside `error` -- the one readable clause is buried under two layers of
/// escaping, and this exact string used to BE the message.
const _undecodableImage = '{"error":"{\\"error\\":{\\"code\\":400,'
    '\\"message\\":\\"Failed to load image or audio file\\",'
    '\\"type\\":\\"invalid_request_error\\"}}"}';

/// Measured: a request whose shape the server could not parse at all.
const _malformed = '{"error":"json: cannot unmarshal string into Go struct '
    'field ChatRequest.messages of type []api.Message"}';

/// doc/measurements.md's `qwen2.5vl:32b` case: a runner that dies for want of
/// VRAM.
const _runnerDied = '{"error":"model runner has unexpectedly stopped"}';

/// Measured: `http.ClientException.message` for a name that does not resolve.
/// Unlike the refusal beside it this one is not localized by the OS.
const _hostLookupFailed = "Failed host lookup: 'no-such-host.invalid'";

PhotoInput get _photo =>
    PhotoInput(name: 'shelf.jpg', bytes: Uint8List.fromList([1, 2, 3]));

OllamaVisionProvider _answering(String body, int status) =>
    OllamaVisionProvider(
        client: MockClient((_) async => http.Response(body, status)));

/// The error one provider raises for one answer.
Future<Object> _failure(VisionProvider provider) async {
  try {
    await provider.analyze(_photo);
  } catch (e) {
    return e;
  }
  throw StateError('the provider did not fail');
}

Future<Object> _errorFor(String body, int status) =>
    _failure(_answering(body, status));

Future<String> _messageFor(String body, int status) async =>
    '${await _errorFor(body, status)}';

/// Nothing that reads as a machine talking to a machine.
///
/// A quoted explanation may end without a full stop -- it is the server's
/// sentence, not ours -- so what is pinned is that the line OPENS with one.
void _readsAsASentence(String message) {
  expect(message, isNot(contains('{')));
  expect(message, isNot(contains(r'\"')));
  expect(message, isNot(contains('"type":')));
  expect(message, isNot(contains('Exception')));
  expect(message, matches(RegExp(r'^[A-Z][^{}]*\.')), reason: message);
}

/// A port nothing is listening on: bound to get a free one, then released.
Future<int> _closedPort() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final port = server.port;
  await server.close(force: true);
  return port;
}

/// An Ollama-shaped server on loopback that refuses every request the same way.
Future<HttpServer> _refusing(String body, int status) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  addTearDown(() => server.close(force: true));
  server.listen((request) async {
    await request.drain<void>();
    request.response
      ..statusCode = status
      ..write(body);
    await request.response.close();
  });
  return server;
}

void main() {
  group('the server is not running', () {
    test('says so, names the remedy, and is not the socket dump', () async {
      final error = await _failure(OllamaVisionProvider(
          baseUrl: 'http://127.0.0.1:${await _closedPort()}'));
      final message = '$error';

      expect(error, isA<OllamaUnreachableException>());
      expect(message, startsWith('Cannot reach Ollama at http://127.0.0.1:'));
      expect(message, contains('ollama serve'));
      // The sentence a downloaded build fails on, and the one thing it cannot
      // leave the reader to guess (T-0453): which of the two programs is
      // missing. Nothing here bundles Ollama, so on a machine that has only
      // unzipped this one, nothing answering is the expected state -- and a
      // remedy alone reads as this program being broken.
      expect(message, contains('separate program'));
      expect(message, contains('does not include or install it'));
      // It claims nothing about where to install it: this address may be
      // another machine, which is the case the next sentence is for.
      expect(message, isNot(contains('ollama.com')));
      // The reason is the socket's, and on Windows it comes back in the OS
      // display language -- so it may never be the whole explanation.
      expect((error as OllamaUnreachableException).reason, isNotEmpty);
      expect(message, isNot(contains('uri=')));
      expect(message, isNot(contains('SocketException')));
    });

    test('fails the photo instead of retrying a server that is down',
        () async {
      final error = await _failure(OllamaVisionProvider(
          baseUrl: 'http://127.0.0.1:${await _closedPort()}'));

      expect(error, isNot(isA<RetryableException>()));
    });

    test('a host that does not resolve is the same failure, differently said',
        () async {
      // Thrown rather than looked up: a real .invalid lookup cost 22 s, and
      // what is being pinned is the wording, not the resolver.
      final error = await _failure(OllamaVisionProvider(
          baseUrl: 'http://no-such-host.invalid:11434',
          client: MockClient((_) async =>
              throw http.ClientException(_hostLookupFailed))));

      expect(error, isA<OllamaUnreachableException>());
      expect('$error', contains('no-such-host.invalid'));
      expect('$error', contains(_hostLookupFailed));
      // Both halves of the remedy, because only one of them fits this case.
      expect('$error', contains('another machine'));
    });
  });

  group('the model is not pulled', () {
    test('names the model and the pull that fixes it', () async {
      final message = await _messageFor(_notPulled, 404);

      expect(message, contains('"qwen2.5vl:7b"'));
      expect(message, contains('not pulled'));
      expect(message, contains('ollama pull qwen2.5vl:7b'));
      _readsAsASentence(message);
    });

    test('the raw body stays on the exception, never in the message',
        () async {
      final error = await _errorFor(_notPulled, 404);

      expect(error, isA<VisionApiException>());
      expect((error as VisionApiException).body, _notPulled);
      expect(error.statusCode, 404);
    });

    test('fails the photo without retrying: a pull is the user\'s move',
        () async {
      expect(await _errorFor(_notPulled, 404), isNot(isA<RetryableException>()));
    });
  });

  group('a 404 that names no model is about the address', () {
    test('does not claim the model is missing', () async {
      final message = await _messageFor(_wrongRoute, 404);

      expect(message, isNot(contains('not pulled')));
      expect(message, isNot(contains('ollama pull')));
      expect(message, contains('Check the URL'));
      expect(message, contains('404 page not found'));
    });

    test('a missing model and a wrong URL do not read the same', () async {
      expect(await _messageFor(_notPulled, 404),
          isNot(await _messageFor(_wrongRoute, 404)));
    });
  });

  group('the double-encoded body', () {
    test('becomes the one clause inside it', () async {
      final message = await _messageFor(_undecodableImage, 400);

      // Before: the whole of _undecodableImage WAS the message.
      expect(message, contains('Failed to load image or audio file'));
      expect(message, isNot(contains('invalid_request_error')));
      expect(message, isNot(contains(r'\"')));
      _readsAsASentence(message);
    });

    test('blames the photo rather than the model id', () async {
      final message = await _messageFor(_undecodableImage, 400);

      expect(message, contains('not the model id'));
      expect(message, contains('"qwen2.5vl:7b"'));
    });

    test('the encoded body is still there for a bug report', () async {
      final error = await _errorFor(_undecodableImage, 400);

      expect((error as VisionApiException).body, _undecodableImage);
    });

    test('a singly-encoded 400 is quoted just as plainly', () async {
      final message = await _messageFor(_malformed, 400);

      expect(message, contains('cannot unmarshal string'));
      _readsAsASentence(message);
    });
  });

  group('a status the worker retries', () {
    test('a 500 blames the server and survives the retries as a sentence',
        () async {
      final error = await _errorFor(_runnerDied, 500);

      expect(error, isA<RetryableException>());
      expect('$error', contains('model runner has unexpectedly stopped'));
      expect('$error', contains('VRAM'));
      // The type name is not an explanation and used to lead this line.
      expect('$error', isNot(contains('RetryableException')));
    });

    test('429 stays retryable and still explains itself', () async {
      final error = await _errorFor('{"error":"too many requests"}', 429);

      expect(error, isA<RetryableException>());
      expect('$error', contains('429'));
      expect('$error', contains('fewer photos'));
    });

    test('an unexpected status is still a sentence with a number in it',
        () async {
      final message = await _messageFor('<html>teapot</html>', 418);

      expect(message, contains('418'));
      expect(message, contains('teapot'));
    });

    test('a body with no explanation in it is capped, never dumped whole',
        () async {
      final long = jsonEncode({'unexpected': List.filled(200, 'padding')});
      final message = await _messageFor(long, 503);

      expect(message.length, lessThan(long.length));
      expect(message, contains('503'));
    });
  });

  group('the defaults are referenced, not retyped', () {
    test('an unconfigured provider names the shared constants', () async {
      final provider = OllamaVisionProvider(
          client: MockClient((_) async => http.Response(_notPulled, 404)));
      final message = '${await _failure(provider)}';

      // documented_lists_test.dart fails on a second literal of either, so a
      // message that names them can only have got them from the constants.
      expect(message, contains(defaultOllamaUrl));
      expect(message, contains(defaultOllamaModel));
    });
  });

  group('over a real socket', () {
    test('the loopback stub produces the same explanation as the mock',
        () async {
      final server = await _refusing(_undecodableImage, 400);
      final message = '${await _failure(OllamaVisionProvider(
        baseUrl: 'http://127.0.0.1:${server.port}',
      ))}';

      expect(message, contains('Failed to load image or audio file'));
      _readsAsASentence(message);
    });
  });

  group('the all-photos-failed summary (T-0072)', () {
    /// Every photo of a scan refused the same way, as a whole run would be.
    Future<String> summaryFor(String body, int status) async {
      final error = await Orchestrator(
        visionWorker: VisionWorker(_answering(body, status)),
        resolverWorker: SkipResolver(),
        visionConcurrency: 2,
      )
          .runScan([_photo, PhotoInput(name: 'b.jpg', bytes: _photo.bytes)])
          .then<Object?>((_) => null, onError: (Object e) => e);
      return (error as ScanFailedException).message;
    }

    test('reads as a sentence when the cause is a photo Ollama refused',
        () async {
      final summary = await summaryFor(_undecodableImage, 400);

      expect(summary, startsWith('All 2 photo(s) failed'));
      expect(summary, contains('Failed to load image or audio file'));
      _readsAsASentence(summary);
    });

    test('reads as a sentence when the server is not running', () async {
      final error = await Orchestrator(
        visionWorker: VisionWorker(OllamaVisionProvider(
            baseUrl: 'http://127.0.0.1:${await _closedPort()}')),
        resolverWorker: SkipResolver(),
        visionConcurrency: 2,
      )
          .runScan([_photo, PhotoInput(name: 'b.jpg', bytes: _photo.bytes)])
          .then<Object?>((_) => null, onError: (Object e) => e);

      final summary = (error as ScanFailedException).message;
      expect(summary, contains('ollama serve'));
      expect(summary, isNot(contains('Exception:')));
      // One shared cause, named once -- not two photos' worth of it.
      expect('ollama serve'.allMatches(summary), hasLength(1));
    });

    test('a model that is not pulled reaches the summary intact', () async {
      final summary = await summaryFor(_notPulled, 404);

      expect(summary, contains('ollama pull qwen2.5vl:7b'));
      _readsAsASentence(summary);
    });
  });
}
