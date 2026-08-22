/// What a cloud vision call that never reached a status tells the user
/// (T-0103).
///
/// The third file in the line `vision_failure_text_test.dart` (T-0072, cloud
/// statuses) and `ollama_failure_text_test.dart` (T-0097, the local provider
/// plus the case with no status at all) started. Both cloud providers posted
/// without a `try`, so an offline machine, a DNS failure or a mistyped host in
/// `SHELFSCAN_OPENAI_BASE_URL` propagated `http.ClientException` verbatim --
/// per photo, and since T-0072 as the shared cause on the all-photos-failed
/// summary line.
///
/// Nothing here reaches a network. The refusals come from a loopback port that
/// was bound to get a free number and then released; the exception objects are
/// real ones produced by that socket, fed back through `MockClient` where the
/// endpoint is not ours to point at loopback (Anthropic's URL is fixed in the
/// provider). The keys are fake and no request carries one anywhere.
@Timeout(Duration(minutes: 2))
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

const _key = 'sk-secret-key-12345';
const _model = 'gpt-4.1-mini-typo';

/// Measured: `http.ClientException.message` for a name that does not resolve.
/// Thrown rather than looked up -- a real `.invalid` lookup cost 22.3 s here,
/// and what is pinned is the wording, not the resolver (T-0097 measured 22 s).
const _hostLookupFailed = "Failed host lookup: 'no-such-host-xyz.invalid'";

PhotoInput get _photo =>
    PhotoInput(name: 'shelf.jpg', bytes: Uint8List.fromList([1, 2, 3]));

/// A port nothing is listening on: bound to get a free one, then released.
Future<int> _closedPort() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final port = server.port;
  await server.close(force: true);
  return port;
}

/// A refusal from a real socket rather than a hand-built exception.
///
/// Cached because a refused connection costs ~2.1 s on Windows (which retries
/// the connect), and every test below wants the same object.
Future<http.ClientException>? _refusalCache;
Future<http.ClientException> get _refusal => _refusalCache ??= () async {
      final port = await _closedPort();
      try {
        await http.Client().post(Uri.parse('http://127.0.0.1:$port/v1/x'));
      } on http.ClientException catch (e) {
        return e;
      }
      throw StateError('a closed port answered');
    }();

VisionProvider _anthropic(http.ClientException error) => AnthropicVisionProvider(
      apiKey: _key,
      model: _model,
      client: MockClient((_) async => throw error),
    );

VisionProvider _openAi(String baseUrl, {http.ClientException? throwing}) =>
    OpenAiCompatibleVisionProvider(
      baseUrl: baseUrl,
      model: _model,
      apiKey: _key,
      client: throwing == null
          ? null
          : MockClient((_) async => throw throwing),
    );

/// The error one provider raises for one photo.
Future<Object> _failure(VisionProvider provider) async {
  try {
    await provider.analyze(_photo);
  } catch (e) {
    return e;
  }
  throw StateError('the provider did not fail');
}

/// Nothing that reads as a machine talking to a machine.
///
/// The socket's own reason closes the line in parentheses and is the OS's
/// sentence, not ours, so what is pinned is that the line OPENS with one.
void _readsAsASentence(String message) {
  expect(message, isNot(contains('{')));
  expect(message, isNot(contains('Exception')));
  expect(message, isNot(contains('uri=')));
  expect(message, matches(RegExp(r'^[A-Z][^{}]*\.')), reason: message);
}

void main() {
  group('an endpoint that is not there', () {
    test('Anthropic explains itself and does not dump the socket', () async {
      final error = await _failure(_anthropic(await _refusal));
      final message = '$error';

      expect(error, isA<VisionUnreachableException>());
      expect(message, startsWith('Cannot reach Anthropic at '));
      expect(message, contains('https://api.anthropic.com/v1/messages'));
      expect((error as VisionUnreachableException).reason, isNotEmpty);
      _readsAsASentence(message);
    });

    test('the OpenAI-compatible endpoint does the same over a real socket',
        () async {
      final baseUrl = 'http://127.0.0.1:${await _closedPort()}/v1';
      final error = await _failure(_openAi(baseUrl));
      final message = '$error';

      expect(error, isA<VisionUnreachableException>());
      expect(message, startsWith('Cannot reach the endpoint at $baseUrl'));
      _readsAsASentence(message);
    });

    test('the wire path and the mock produce the same sentence', () async {
      final refusal = await _refusal;
      const baseUrl = 'https://api.groq.com/openai/v1';

      expect('${await _failure(_openAi(baseUrl, throwing: refusal))}',
          startsWith('Cannot reach the endpoint at $baseUrl'));
    });

    test('no status was reached, so this is not the T-0072 exception',
        () async {
      for (final provider in [
        _anthropic(await _refusal),
        _openAi('https://api.groq.com/openai/v1', throwing: await _refusal),
      ]) {
        expect(await _failure(provider), isNot(isA<VisionApiException>()));
      }
    });

    test('the key is not in the line, and is not blamed', () async {
      final message = '${await _failure(_anthropic(await _refusal))}';

      expect(message, isNot(contains(_key)));
      expect(message, contains('neither the key nor the model id'));
    });
  });

  group('nothing from ClientException.toString()', () {
    test('the local port and the request URI stay out of the message',
        () async {
      final refusal = await _refusal;
      final raw = '$refusal';
      // Measured, package:http 1.6.0 on Windows: the toString of a refused
      // connection is `ClientException with SocketException: <localized text>
      // (OS Error: ..., errno = 1225), address = 127.0.0.1, port = 51485,
      // uri=http://127.0.0.1:51484/v1/x` -- the port is the EPHEMERAL LOCAL
      // one, which is noise in a bug report and never the same twice.
      final localPort = (refusal as SocketException).port;

      for (final provider in [
        _anthropic(refusal),
        _openAi('https://api.groq.com/openai/v1', throwing: refusal),
      ]) {
        final message = '${await _failure(provider)}';

        expect(message, isNot(contains('uri=')));
        expect(message, isNot(contains('SocketException')));
        expect(message, isNot(contains('ClientException')));
        expect(message, isNot(contains(raw)));
        expect(localPort, isNotNull, reason: raw);
        expect(message, isNot(contains('$localPort')));
        expect(message, isNot(contains('address = ')));
      }
    });

    test('the socket\'s own reason is still there, once, at the end', () async {
      final refusal = await _refusal;
      final message = '${await _failure(_anthropic(refusal))}';

      expect(message, endsWith('(${refusal.message})'));
    });

    test('a name that does not resolve is the same failure, differently said',
        () async {
      final error = await _failure(_openAi('http://no-such-host.invalid/v1',
          throwing: http.ClientException(_hostLookupFailed)));

      expect(error, isA<VisionUnreachableException>());
      expect('$error', contains('no-such-host.invalid'));
      expect('$error', contains(_hostLookupFailed));
    });
  });

  group('the advice differs where the situation differs', () {
    test('the base URL is the first thing to check when it is the user\'s',
        () async {
      final message = '${await _failure(_openAi(
        'https://api.groq.com/openai/v1',
        throwing: await _refusal,
      ))}';

      expect(message, contains('Check that base URL first'));
      expect(message, contains('online'));
    });

    test('Anthropic sends nobody to a setting it does not have', () async {
      final message = '${await _failure(_anthropic(await _refusal))}';

      // `ollama serve` has no cloud counterpart and this address is not a
      // field, so the only actionable half is the machine's own connection.
      expect(message, isNot(contains('base URL')));
      expect(message, contains('fixed in this app'));
      expect(message, contains('online'));
    });

    test('the two do not read the same', () async {
      final refusal = await _refusal;

      expect('${await _failure(_anthropic(refusal))}',
          isNot('${await _failure(_openAi('https://x.test/v1', throwing: refusal))}'));
    });
  });

  group('the worker does not retry a machine that is offline', () {
    test('one attempt per photo, no backoff spent', () async {
      var calls = 0;
      final refusal = await _refusal;
      final worker = VisionWorker(OpenAiCompatibleVisionProvider(
        baseUrl: 'https://api.groq.com/openai/v1',
        model: _model,
        apiKey: _key,
        client: MockClient((_) async {
          calls += 1;
          throw refusal;
        }),
      ));

      await expectLater(worker.run(_photo),
          throwsA(isA<VisionUnreachableException>()));
      // 4 would be the retried count, and 14 s of sleep with it.
      expect(calls, 1);
    });

    test('and it is not a RetryableException in the first place', () async {
      expect(await _failure(_anthropic(await _refusal)),
          isNot(isA<RetryableException>()));
    });
  });

  group('the all-photos-failed summary (T-0072)', () {
    Future<String> summaryFor(VisionProvider provider) async {
      final error = await Orchestrator(
        visionWorker: VisionWorker(provider),
        resolverWorker: SkipResolver(),
        visionConcurrency: 2,
      )
          .runScan([_photo, PhotoInput(name: 'b.jpg', bytes: _photo.bytes)])
          .then<Object?>((_) => null, onError: (Object e) => e);
      return (error as ScanFailedException).message;
    }

    test('reads as a sentence when the cloud endpoint cannot be reached',
        () async {
      final summary = await summaryFor(_anthropic(await _refusal));

      expect(summary, startsWith('All 2 photo(s) failed'));
      expect(summary, contains('Cannot reach Anthropic at '));
      _readsAsASentence(summary);
      // One shared cause, named once -- not two photos' worth of it.
      expect('Cannot reach'.allMatches(summary), hasLength(1));
    });

    test('an unreachable base URL reaches the summary intact, over a socket',
        () async {
      final baseUrl = 'http://127.0.0.1:${await _closedPort()}/v1';
      final summary = await summaryFor(_openAi(baseUrl));

      expect(summary, contains('Cannot reach the endpoint at $baseUrl'));
      expect(summary, contains('Check that base URL first'));
      _readsAsASentence(summary);
    });
  });
}
