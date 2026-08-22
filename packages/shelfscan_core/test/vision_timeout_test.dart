/// The CLI's bound on one vision call (T-0108).
///
/// T-0104 bounded every outbound call and gave each provider a `timeout`
/// constructor parameter; no shell passed one, so 120 s was the only number
/// reachable from either surface, and the one configuration this project has
/// measured above it (`qwen2.5vl:32b`, ~360 s per 4000x3000 photo for want of
/// VRAM -- doc/measurements.md) had no way to finish.
///
/// Two claims are worth separating and both are made below. That the string
/// parses is the cheap half; that the parsed value ends up on the socket is
/// the half the defect was about, so one case is a real loopback
/// `ServerSocket` that accepts the connection and never writes a byte, and it
/// is timed. 1 s there rather than the shipped budget so the suite does not
/// sit through two minutes.
@Timeout(Duration(seconds: 90))
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

import '../bin/shelfscan.dart'
    show
        FallbackConfigError,
        anthropicProviderFor,
        fallbackProviderFor,
        maxVisionTimeoutSeconds,
        ollamaProviderFor,
        openAiProviderFor,
        raiseVisionTimeoutAdvice,
        visionTimeoutFrom,
        visionTimeoutVar;

/// A run with every variable the paths below need, so the timeout is the only
/// thing each case varies.
const _configured = {
  'ANTHROPIC_API_KEY': 'sk-ant-not-a-key',
  'SHELFSCAN_OLLAMA_FALLBACK_MODEL': 'gemma3:12b',
  'SHELFSCAN_OPENAI_BASE_URL': 'https://api.groq.com/openai/v1',
  'SHELFSCAN_OPENAI_MODEL': 'meta-llama/llama-4-scout',
  'SHELFSCAN_OPENAI_API_KEY': 'gsk-not-a-key',
};

Map<String, String> _with(String? value) => {
      ..._configured,
      if (value != null) visionTimeoutVar: value,
    };

/// The `timeout` of whatever the CLI built, whichever provider it is.
Duration _timeoutOf(VisionProvider provider) => switch (provider) {
      OllamaVisionProvider p => p.timeout,
      AnthropicVisionProvider p => p.timeout,
      OpenAiCompatibleVisionProvider p => p.timeout,
      _ => fail('no timeout on $provider'),
    };

/// The sentence that provider will add to a stall, or null if it adds none.
String? _remedyOf(VisionProvider provider) => switch (provider) {
      OllamaVisionProvider p => p.stallRemedy,
      AnthropicVisionProvider p => p.stallRemedy,
      OpenAiCompatibleVisionProvider p => p.stallRemedy,
      _ => fail('no stall remedy on $provider'),
    };

final _closers = <Future<void> Function()>[];

/// A loopback server that accepts, reads, and writes nothing ever.
Future<int> _silence() async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final live = <Socket>[];
  server.listen((socket) {
    live.add(socket);
    socket.listen((_) {}, onError: (_) {}, cancelOnError: true);
  });
  _closers.add(() async {
    for (final socket in live) {
      socket.destroy();
    }
    await server.close();
  });
  return server.port;
}

/// The sentence one stalled call puts in front of the user.
Future<String> _stallMessage(VisionProvider provider) async {
  try {
    await provider.analyze(PhotoInput(name: 'shelf.jpg', bytes: Uint8List(3)));
  } catch (e) {
    return '$e';
  }
  fail('the stalled endpoint was not reported');
}

void main() {
  tearDown(() async {
    for (final close in _closers) {
      await close();
    }
    _closers.clear();
  });

  group('the value reaches the provider', () {
    test('unset is the shipped budget', () {
      expect(visionTimeoutFrom(_with(null)), visionCallTimeout);
      expect(_timeoutOf(ollamaProviderFor(_with(null))), visionCallTimeout);
    });

    test('every provider the CLI can build carries it', () {
      final env = _with('900');
      expect(_timeoutOf(ollamaProviderFor(env)), const Duration(seconds: 900));
      expect(_timeoutOf(openAiProviderFor(env)), const Duration(seconds: 900));
      // Both branches: a named model is the one that also drops temperature.
      expect(_timeoutOf(anthropicProviderFor('sk-ant-not-a-key', env)),
          const Duration(seconds: 900));
      expect(
          _timeoutOf(anthropicProviderFor('sk-ant-not-a-key',
              {...env, 'SHELFSCAN_ANTHROPIC_MODEL': 'claude-opus-5'})),
          const Duration(seconds: 900));
    });

    test('the second reader is bounded by it too', () {
      // A fallback read is a vision call and stalls the same way; before
      // T-0108 it was the same 120 s whatever the primary was given.
      final env = _with('900');
      for (final name in const [null, 'ollama', 'anthropic', 'openai']) {
        expect(_timeoutOf(fallbackProviderFor(name, env)!),
            const Duration(seconds: 900),
            reason: 'fallback ${name ?? 'from the environment'}');
      }
    });

    test('it bounds the call and not merely the field', () async {
      final port = await _silence();
      final provider = ollamaProviderFor({
        ..._with('1'),
        'SHELFSCAN_OLLAMA_URL': 'http://127.0.0.1:$port',
      });

      final started = DateTime.now();
      final error = await provider
          .analyze(PhotoInput(name: 'shelf.jpg', bytes: Uint8List(3)))
          .then<Object?>((_) => null, onError: (Object e) => e);
      final waited = DateTime.now().difference(started);

      expect(error, isA<OllamaUnreachableException>());
      expect('$error', contains('Timed out after 1 s'));
      // The point of the case: on the shipped default this returns at 120 s.
      expect(waited, lessThan(const Duration(seconds: 30)), reason: '$waited');
    });
  });

  group('a value that is not a number of seconds', () {
    for (final value in const [
      'abc',
      '',
      ' ',
      '0',
      '-1',
      '-0',
      '12.5',
      '90s',
      '1e3',
      '1_800',
      '99999999999999999999',
    ]) {
      test('"$value" never becomes a wait', () {
        // Empty is the one that is not an error: every variable in this CLI
        // reads set-but-empty as unset (T-0080), so it is the default here
        // like everywhere else.
        if (value.isEmpty) {
          expect(visionTimeoutFrom(_with(value)), visionCallTimeout);
          return;
        }
        expect(() => visionTimeoutFrom(_with(value)),
            throwsA(isA<FallbackConfigError>()));
        // Refused at the factory, so no provider is built on it either --
        // there is no path on which a bad value reaches a socket.
        expect(() => ollamaProviderFor(_with(value)),
            throwsA(isA<FallbackConfigError>()));
      });
    }

    test('the refusal names the variable, the bounds and what was typed', () {
      final error = () {
        try {
          visionTimeoutFrom(_with('nonsense'));
        } on FallbackConfigError catch (e) {
          return e.message;
        }
        fail('accepted');
      }();
      expect(error, contains(visionTimeoutVar));
      expect(error, contains('nonsense'));
      expect(error, contains('$maxVisionTimeoutSeconds'));
      expect(error, contains('${visionCallTimeout.inSeconds} s'));
    });

    test('above the ceiling is refused, at it is not', () {
      // The ceiling is what keeps "bounded" true: a bound nobody outlasts is
      // the unbounded wait T-0104 removed, typed in by hand.
      expect(visionTimeoutFrom(_with('$maxVisionTimeoutSeconds')),
          const Duration(seconds: maxVisionTimeoutSeconds));
      expect(() => visionTimeoutFrom(_with('${maxVisionTimeoutSeconds + 1}')),
          throwsA(isA<FallbackConfigError>()));
      expect(visionTimeoutFrom(_with('1')), const Duration(seconds: 1));
    });

    test('the ceiling clears the slowest model this project has measured', () {
      // qwen2.5vl:32b, ~360 s per 4000x3000 photo (doc/measurements.md) --
      // the configuration the variable exists for. A ceiling below it would
      // expose a control that cannot reach the one case it is for.
      expect(maxVisionTimeoutSeconds, greaterThan(360));
    });
  });

  // T-0152. The diagnosis is core's and is said everywhere; the remedy names
  // this variable and is said only where the variable exists.
  group('the stall names the control, on the shell that has one', () {
    test('every provider the CLI builds carries it, primary and fallback', () {
      final env = _with('900');
      expect(_remedyOf(ollamaProviderFor(env)), raiseVisionTimeoutAdvice);
      expect(_remedyOf(openAiProviderFor(env)), raiseVisionTimeoutAdvice);
      expect(_remedyOf(anthropicProviderFor('sk-ant-not-a-key', env)),
          raiseVisionTimeoutAdvice);
      expect(
          _remedyOf(anthropicProviderFor('sk-ant-not-a-key',
              {...env, 'SHELFSCAN_ANTHROPIC_MODEL': 'claude-opus-5'})),
          raiseVisionTimeoutAdvice);
      // The second reader is bounded by the variable, so it advises about it.
      for (final name in const [null, 'ollama', 'anthropic', 'openai']) {
        expect(_remedyOf(fallbackProviderFor(name, env)!),
            raiseVisionTimeoutAdvice,
            reason: 'fallback ${name ?? 'from the environment'}');
      }
    });

    test('it names the variable, its bounds, and reads as a sentence', () {
      expect(raiseVisionTimeoutAdvice, contains(visionTimeoutVar));
      expect(raiseVisionTimeoutAdvice, contains('$maxVisionTimeoutSeconds'));
      expect(raiseVisionTimeoutAdvice, endsWith('.'));
      expect(raiseVisionTimeoutAdvice, isNot(contains('{')));
    });

    test('a stalled local read gives the diagnosis and then the remedy',
        () async {
      final port = await _silence();
      final message = await _stallMessage(ollamaProviderFor({
        ..._with('1'),
        'SHELFSCAN_OLLAMA_URL': 'http://127.0.0.1:$port',
      }));

      expect(message, startsWith('Timed out after 1 s'));
      expect(message, contains('legitimately takes minutes'));
      expect(message, contains('$visionTimeoutVar=<seconds>'));
      // The order is the whole change: T-0104 said what happened and why, and
      // stopped one clause short of what to do about it.
      expect(message.indexOf(visionTimeoutVar),
          greaterThan(message.indexOf('legitimately takes minutes')));
    });

    test('a stalled cloud read gets the same two halves', () async {
      final port = await _silence();
      final message = await _stallMessage(openAiProviderFor({
        ..._with('1'),
        'SHELFSCAN_OPENAI_BASE_URL': 'http://127.0.0.1:$port/v1',
      }));

      expect(message, contains('far likelier to have caught a stall'));
      expect(message, contains('$visionTimeoutVar=<seconds>'));
    });
  });

  // The other half of T-0152: the app has no such control (T-0108 argues why),
  // so a provider built the way `app/lib/provider_config.dart` builds one --
  // no `timeout`, no `stallRemedy` -- must not imply one exists.
  group('the stall names no control on a shell without one', () {
    test('the local sentence ends on the diagnosis', () async {
      final port = await _silence();
      // 1 s rather than the app's default 120 s: the remedy clause is what is
      // under test, and the suite should not sit through the budget.
      final message = await _stallMessage(OllamaVisionProvider(
        baseUrl: 'http://127.0.0.1:$port',
        timeout: const Duration(seconds: 1),
      ));

      expect(message, contains('legitimately takes minutes'));
      expect(message, endsWith('legitimately takes minutes.'));
      expect(message, isNot(contains(visionTimeoutVar)));
      expect(message, isNot(contains('SHELFSCAN')));
      expect(message, isNot(contains('raise')));
    });

    test('and so does the cloud one', () async {
      final port = await _silence();
      final message = await _stallMessage(OpenAiCompatibleVisionProvider(
        baseUrl: 'http://127.0.0.1:$port/v1',
        model: 'meta-llama/llama-4-scout',
        apiKey: 'gsk-not-a-key',
        timeout: const Duration(seconds: 1),
      ));

      expect(message, contains('far likelier to have caught a stall'));
      expect(message, isNot(contains(visionTimeoutVar)));
      expect(message, isNot(contains('SHELFSCAN')));
    });

    test('no provider in lib/ offers a remedy by default', () {
      // The default is what the app gets, and it is the same on all three.
      expect(_remedyOf(OllamaVisionProvider()), isNull);
      expect(_remedyOf(AnthropicVisionProvider(apiKey: 'sk-ant-not-a-key')),
          isNull);
      expect(
          _remedyOf(OpenAiCompatibleVisionProvider(
              baseUrl: 'https://api.groq.com/openai/v1',
              model: 'meta-llama/llama-4-scout',
              apiKey: 'gsk-not-a-key')),
          isNull);
    });
  });
}
