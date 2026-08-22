/// The OpenAI-compatible provider learns its request shape from the
/// endpoint's own 400s (T-0089).
///
/// The defect: `max_tokens: 4096` went out unconditionally and every GPT-5
/// model answers HTTP 400 `Unsupported parameter: 'max_tokens' is not
/// supported with this model. Use 'max_completion_tokens' instead.`, so the
/// provider was pinned to the previous generation on the one endpoint this
/// project has a key for.
///
/// The bodies below are verbatim from api.openai.com, 2026-08-15. What is
/// pinned here is that the correction keys on what the endpoint SAID: no
/// model id appears in any assertion, because no model id appears in the
/// implementation.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

const _ok = '{"items":[{"raw_title":"Vex"}]}';

http.Response _completion() => http.Response(
    jsonEncode({
      'choices': [
        {
          'message': {'role': 'assistant', 'content': _ok}
        }
      ]
    }),
    200,
    headers: {'content-type': 'application/json'});

/// Measured verbatim against api.openai.com on 2026-08-15: `gpt-5`,
/// `gpt-5-mini`, `gpt-5.4-nano`, `gpt-5.4-mini`, `gpt-5.5` and `gpt-5.6-terra`
/// all answer exactly this to a request carrying `max_tokens`.
http.Response _renameMaxTokens() => http.Response(
    jsonEncode({
      'error': {
        'message': "Unsupported parameter: 'max_tokens' is not supported with "
            "this model. Use 'max_completion_tokens' instead.",
        'type': 'invalid_request_error',
        'param': 'max_tokens',
        'code': 'unsupported_parameter',
      }
    }),
    400);

/// Measured the same day on `gpt-5`, `gpt-5-mini`, `gpt-5.5`, `gpt-5.6-luna`,
/// `gpt-5.6-sol` and `gpt-5.6-terra` -- and NOT on `gpt-5.1`, `gpt-5.2`,
/// `gpt-5.4`, `gpt-5.4-mini` or `gpt-5.4-nano`, which take temperature 0.
/// Acceptance is not monotonic in the version, which is the measured form of
/// T-0067's objection to a table.
http.Response _refuseTemperature() => http.Response(
    jsonEncode({
      'error': {
        'message': "Unsupported value: 'temperature' does not support 0.0 "
            'with this model. Only the default (1) value is supported.',
        'type': 'invalid_request_error',
        'param': 'temperature',
        'code': 'unsupported_value',
      }
    }),
    400);

/// Not a measured body either: no endpoint here has been seen to refuse
/// `seed`, but its consequence sentence was live unpinned prose until T-0139
/// added the cap's and the gap showed up beside it.
http.Response _refuseSeed() => http.Response(
    jsonEncode({
      'error': {
        'message': "Unrecognized request argument supplied: seed",
        'type': 'invalid_request_error',
        'param': 'seed',
        'code': null,
      }
    }),
    400);

/// Not a measured body: api.openai.com always offers the rename, and this
/// project can reach one endpoint of the seven (T-0089). It is that vendor's
/// own refusal minus the sentence naming a replacement -- the answer expected
/// from a vendor in this family that takes neither name.
http.Response _refuseMaxTokensOutright() => http.Response(
    jsonEncode({
      'error': {
        'message': "Unsupported parameter: 'max_tokens' is not supported with "
            'this model.',
        'type': 'invalid_request_error',
        'param': 'max_tokens',
        'code': 'unsupported_parameter',
      }
    }),
    400);

/// Bytes derived from the name so a test endpoint can tell one photo's request
/// from another's -- the request body carries the image, never the file name.
PhotoInput _photo([String name = 'shelf.jpg']) =>
    PhotoInput(name: name, bytes: Uint8List.fromList(name.codeUnits));

/// A provider whose endpoint answers with [script], one entry per call, and
/// [_completion] once the script runs out. Hands back every request body sent
/// and every note raised.
class _Endpoint {
  _Endpoint({List<http.Response Function()> script = const []})
      : _script = [...script];

  final List<http.Response Function()> _script;
  final bodies = <Map<String, dynamic>>[];
  final notes = <String>[];

  late final provider = OpenAiCompatibleVisionProvider(
    baseUrl: 'https://api.example.test/v1',
    model: 'a-model',
    apiKey: 'sk-secret-123',
    onRequestAdjusted: notes.add,
    client: MockClient((request) async {
      bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
      return _script.isEmpty ? _completion() : _script.removeAt(0)();
    }),
  );

  Future<PhotoAnalysis> analyze([String name = 'shelf.jpg']) =>
      provider.analyze(_photo(name));
}

/// An endpoint that answers like `gpt-5.5`: one bad parameter per response,
/// `max_tokens` before `temperature` (both bodies above are its own words).
http.Response _oneBadParameterAtATime(Map<String, dynamic> body) {
  if (body.containsKey('max_tokens')) return _renameMaxTokens();
  if (body.containsKey('temperature')) return _refuseTemperature();
  return _completion();
}

/// Holds arriving requests until a whole wave of them is in flight, so
/// "three photos in flight before any has learned anything" is a fact of the
/// test rather than a scheduling accident. Releases early when fewer photos
/// than that are left, which is what keeps it from deadlocking without a
/// timer.
class _Wave {
  _Wave({required this.size, required int photos}) : _outstanding = photos;

  final int size;
  int _outstanding;
  final _waiting = <Completer<void>>[];

  Future<void> arrive() {
    final held = Completer<void>();
    _waiting.add(held);
    _release();
    return held.future;
  }

  void finished() {
    _outstanding -= 1;
    _release();
  }

  void _release() {
    if (_waiting.length < (size < _outstanding ? size : _outstanding)) return;
    final wave = [..._waiting];
    _waiting.clear();
    for (final held in wave) {
      held.complete();
    }
  }
}

/// One provider, several photos through [runPool] at [concurrency] -- the
/// shape the vision stage actually runs in (`Orchestrator.visionConcurrency`,
/// 3 for every cloud backend).
class _Stage {
  _Stage({
    required this.photos,
    required this.concurrency,
    http.Response Function(Map<String, dynamic> body)? endpoint,
  }) : _endpoint = endpoint ?? _oneBadParameterAtATime;

  final List<String> photos;
  final int concurrency;
  final http.Response Function(Map<String, dynamic>) _endpoint;

  final bodies = <Map<String, dynamic>>[];
  final accepted = <Map<String, dynamic>>[];
  final notes = <String>[];
  final scanned = <String>[];
  final failed = <String, Object>{};

  late final _wave = _Wave(size: concurrency, photos: photos.length);

  late final provider = OpenAiCompatibleVisionProvider(
    baseUrl: 'https://api.example.test/v1',
    model: 'a-model',
    apiKey: 'sk-secret-123',
    onRequestAdjusted: notes.add,
    client: MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      bodies.add(body);
      await _wave.arrive();
      final response = _endpoint(body);
      if (response.statusCode == 200) accepted.add(body);
      return response;
    }),
  );

  Future<void> run() async {
    await runPool<String, PhotoAnalysis>(
      photos,
      (name) async {
        try {
          final analysis = await VisionWorker(provider).run(_photo(name));
          scanned.add(name);
          return analysis;
        } finally {
          _wave.finished();
        }
      },
      concurrency: concurrency,
      onError: (name, error) => failed[name] = error,
    );
  }
}

void main() {
  group('the shape sent first', () {
    test('is max_tokens, the field every endpoint in this family has taken',
        () async {
      final endpoint = _Endpoint();
      await endpoint.analyze();

      // Not max_completion_tokens first, and the direction is the argument:
      // an endpoint that has not adopted the rename may IGNORE an unknown
      // field, leaving the request uncapped with nothing said. A refusal of
      // max_tokens is loud and self-describing.
      expect(endpoint.bodies.single['max_tokens'], 8192);
      expect(endpoint.bodies.single.containsKey('max_completion_tokens'),
          isFalse);
      expect(endpoint.bodies.single['temperature'], 0);
      expect(endpoint.bodies.single['seed'], isNotNull);
    });

    test('is what an endpoint that accepts it keeps getting -- no probe, '
        'no retry, no extra call', () async {
      final endpoint = _Endpoint();
      await endpoint.analyze('a.jpg');
      await endpoint.analyze('b.jpg');

      expect(endpoint.bodies, hasLength(2));
      expect(endpoint.notes, isEmpty);
      expect(endpoint.provider.refusedParameters, isEmpty);
    });
  });

  group('a refused field', () {
    test('is re-sent under the name the endpoint gave', () async {
      final endpoint = _Endpoint(script: [_renameMaxTokens]);
      final analysis = await endpoint.analyze();

      expect(endpoint.bodies, hasLength(2));
      expect(endpoint.bodies.last.containsKey('max_tokens'), isFalse);
      expect(endpoint.bodies.last['max_completion_tokens'], 8192);
      // The photo is not lost to the correction: the caller sees the answer.
      expect(analysis.items.single.rawTitle, 'Vex');
    });

    test('is dropped when the endpoint names no replacement', () async {
      final endpoint = _Endpoint(script: [_refuseTemperature]);
      await endpoint.analyze();

      expect(endpoint.bodies.last.containsKey('temperature'), isFalse);
      expect(endpoint.bodies.last['max_tokens'], 8192);
      expect(endpoint.bodies.last['seed'], isNotNull);
    });

    test('costs one call per correction, once, not once per photo', () async {
      final endpoint =
          _Endpoint(script: [_renameMaxTokens, _refuseTemperature]);
      await endpoint.analyze('a.jpg');
      final afterFirst = endpoint.bodies.length;
      await endpoint.analyze('b.jpg');
      await endpoint.analyze('c.jpg');

      expect(afterFirst, 3, reason: 'two refusals plus the accepted call');
      expect(endpoint.bodies.length, 5, reason: 'later photos go once');
      expect(endpoint.bodies.last['max_completion_tokens'], 8192);
      expect(endpoint.bodies.last.containsKey('temperature'), isFalse);
    });

    test('never costs the model, the messages or the image', () async {
      final endpoint =
          _Endpoint(script: [_renameMaxTokens, _refuseTemperature]);
      await endpoint.analyze();

      for (final body in endpoint.bodies) {
        expect(body['model'], 'a-model');
        expect(body['messages'], isA<List<dynamic>>());
      }
      expect(jsonEncode(endpoint.bodies.first['messages']),
          jsonEncode(endpoint.bodies.last['messages']));
    });
  });

  group('what the run is told', () {
    test('names the field, the replacement and the endpoint\'s own sentence',
        () async {
      final endpoint = _Endpoint(script: [_renameMaxTokens]);
      await endpoint.analyze();

      expect(
          endpoint.notes.single,
          allOf(
            contains('max_tokens'),
            contains('max_completion_tokens'),
            contains('https://api.example.test/v1'),
            contains("Use 'max_completion_tokens' instead"),
            isNot(contains('sk-secret-123')),
          ));
    });

    test('says outright that a dropped temperature ends the stated sampling',
        () async {
      final endpoint = _Endpoint(script: [_refuseTemperature]);
      await endpoint.analyze();

      // T-0053/T-0057: an unrecorded sampling state is the thing those tasks
      // exist to end, so it may not be reached quietly.
      expect(
          endpoint.notes.single,
          allOf(contains('Sampling'), contains('record that'),
              contains('temperature 0')));
    });

    test('says outright that a dropped seed ends the asking for repeatability',
        () async {
      final endpoint = _Endpoint(script: [_refuseSeed]);
      await endpoint.analyze();

      expect(endpoint.notes.single,
          allOf(contains('Repeats'), contains('repeatable')));
    });

    test('says outright that a dropped output cap leaves the run uncapped',
        () async {
      final endpoint = _Endpoint(script: [_refuseMaxTokensOutright]);
      await endpoint.analyze();

      // T-0089's send order exists so this state is never reached quietly; the
      // note is what makes it loud (T-0139).
      expect(
          endpoint.notes.single,
          allOf(contains('Nothing caps'), contains('rest of this run'),
              contains('billing')));
      expect(endpoint.bodies.last.containsKey('max_tokens'), isFalse);
      expect(endpoint.bodies.last.containsKey('max_completion_tokens'),
          isFalse);
    });

    test('says nothing of the kind when the cap survives under another name',
        () async {
      final endpoint = _Endpoint(script: [_renameMaxTokens]);
      await endpoint.analyze();

      expect(endpoint.notes.single, isNot(contains('Nothing caps')));
      expect(endpoint.bodies.last['max_completion_tokens'], 8192);
    });

    test('announces the cap by the name it was lost under, not the name it was '
        'sent under', () async {
      // T-0120's state: the endpoint renames the cap and then refuses the name
      // it gave. The field in that second 400 is `max_completion_tokens`, so a
      // case keyed on `max_tokens` would leave the uncapped run unannounced.
      final endpoint = _Endpoint(script: [
        _renameMaxTokens,
        () => http.Response(
            jsonEncode({
              'error': {
                'message': "Unsupported parameter: 'max_completion_tokens' is "
                    "not supported with this model. Use 'max_tokens' instead.",
                'param': 'max_completion_tokens',
              }
            }),
            400),
      ]);
      await endpoint.analyze();

      expect(endpoint.notes, hasLength(2));
      expect(endpoint.notes.first, isNot(contains('Nothing caps')));
      expect(endpoint.notes.last, contains('Nothing caps'));
    });

    test('is raised once per correction, not once per photo', () async {
      final endpoint = _Endpoint(script: [_renameMaxTokens]);
      await endpoint.analyze('a.jpg');
      await endpoint.analyze('b.jpg');

      expect(endpoint.notes, hasLength(1));
      expect(endpoint.provider.refusedParameters,
          {'max_tokens': 'max_completion_tokens'});
    });
  });

  group('a 400 that is not a refused field', () {
    test('still fails the photo, explained', () async {
      final endpoint = _Endpoint(
          script: [() => http.Response('{"error":{"message":"bad image"}}', 400)]);

      await expectLater(
        endpoint.analyze(),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message',
            allOf(contains('400'), contains('bad image')))),
      );
      expect(endpoint.bodies, hasLength(1), reason: 'nothing to retry with');
    });

    test('a body that is not JSON at all is not mistaken for one', () async {
      final endpoint =
          _Endpoint(script: [() => http.Response('<html>gateway</html>', 400)]);

      await expectLater(endpoint.analyze(), throwsA(isA<Exception>()));
      expect(endpoint.bodies, hasLength(1));
    });

    test('a field this provider never sends is not invented into the request',
        () async {
      final endpoint = _Endpoint(script: [
        () => http.Response(
            jsonEncode({
              'error': {
                'message': "Unsupported parameter: 'top_p' is not supported "
                    "with this model. Use 'top_k' instead.",
                'param': 'top_p',
              }
            }),
            400)
      ]);

      await expectLater(endpoint.analyze(), throwsA(isA<Exception>()));
      expect(endpoint.provider.refusedParameters, isEmpty);
    });

    test('the same field refused twice does not loop', () async {
      // An endpoint that renames max_tokens and then refuses the name it gave
      // would ping-pong under a rule that trusted every replacement; the
      // second correction degrades to a drop and the request terminates.
      final endpoint = _Endpoint(script: [
        _renameMaxTokens,
        () => http.Response(
            jsonEncode({
              'error': {
                'message': "Unsupported parameter: 'max_completion_tokens' is "
                    "not supported with this model. Use 'max_tokens' instead.",
                'param': 'max_completion_tokens',
              }
            }),
            400),
      ]);
      await endpoint.analyze();

      expect(endpoint.bodies, hasLength(3));
      expect(endpoint.bodies.last.containsKey('max_tokens'), isFalse);
      expect(endpoint.bodies.last.containsKey('max_completion_tokens'), isFalse);
    });
  });

  test('an endpoint answering in prose with no param is still obeyed',
      () async {
    // Not every vendor in this family answers the `param` field; the message
    // is then the only structure there is.
    final endpoint = _Endpoint(script: [
      () => http.Response(
          jsonEncode({
            'error': {
              'message': "Unsupported parameter: 'max_tokens'. Use "
                  "'max_completion_tokens' instead."
            }
          }),
          400)
    ]);
    await endpoint.analyze();

    expect(endpoint.bodies.last['max_completion_tokens'], 8192);
  });

  group('three photos in flight before anything is learned (T-0120)', () {
    test('all scan -- the owner got one of three', () async {
      final stage = _Stage(
          photos: ['a.jpg', 'b.jpg', 'c.jpg'],
          concurrency: 3,
          endpoint: _oneBadParameterAtATime);
      await stage.run();

      expect(stage.scanned, hasLength(3));
      expect(stage.failed, isEmpty);
      // Two corrections, told once each however many photos hit them.
      expect(stage.notes, hasLength(2));
      expect(stage.provider.refusedParameters,
          {'max_tokens': 'max_completion_tokens', 'temperature': null});
    });

    test('the replacement the endpoint just gave is not itself recorded as '
        'refused, so the output cap survives', () async {
      // The defect: photo two read its own stale 400 against the shape photo
      // one had already corrected, found `max_completion_tokens` in both the
      // message and that shape, and recorded the endpoint as refusing it. The
      // cap then vanished from every later request with nothing said -- the
      // silent failure the send order exists to prevent.
      final stage =
          _Stage(photos: ['a.jpg', 'b.jpg', 'c.jpg'], concurrency: 3);
      await stage.run();

      expect(stage.provider.refusedParameters.containsKey(
          'max_completion_tokens'), isFalse);
      expect(stage.accepted, hasLength(3));
      for (final body in stage.accepted) {
        expect(body['max_completion_tokens'], 8192);
      }
    });

    test('a call refused what another has already corrected re-sends, and is '
        'neither failed nor announced again', () async {
      final stage =
          _Stage(photos: ['a.jpg', 'b.jpg', 'c.jpg'], concurrency: 3);
      await stage.run();

      // Six refusals (three photos x two corrections) and three answers: the
      // rule costs uploads in the first wave, not photographs. At concurrency
      // 1 the same script is five calls.
      expect(stage.bodies, hasLength(9));
      expect(stage.notes, hasLength(2));
    });

    test('a real 400 is still a real 400 while corrections are landing',
        () async {
      // The retry must be bounded by corrections actually made, or a photo the
      // endpoint genuinely refuses would re-send for as long as the others
      // keep learning.
      final stage = _Stage(
        photos: ['a.jpg', 'bad.jpg', 'c.jpg'],
        concurrency: 3,
        endpoint: (body) {
          final image = ((body['messages'] as List<dynamic>).first
              as Map<String, dynamic>)['content'] as List<dynamic>;
          final url = ((image.last as Map<String, dynamic>)['image_url']
              as Map<String, dynamic>)['url'] as String;
          return url.contains(base64Encode('bad.jpg'.codeUnits))
              ? http.Response('{"error":{"message":"bad image"}}', 400)
              : _oneBadParameterAtATime(body);
        },
      );
      await stage.run();

      expect(stage.scanned, unorderedEquals(['a.jpg', 'c.jpg']));
      expect(stage.failed.keys, ['bad.jpg']);
      expect(stage.failed['bad.jpg'].toString(), contains('bad image'));
    });
  });

  test('an endpoint that refuses nothing makes one call per photo at '
      'concurrency 3', () async {
    // gpt-4.1-mini: T-0090's request, byte for byte, and no coordination
    // imposed on a path that needs none.
    final stage = _Stage(
        photos: ['a.jpg', 'b.jpg', 'c.jpg'],
        concurrency: 3,
        endpoint: (_) => _completion());
    await stage.run();

    expect(stage.bodies, hasLength(3));
    expect(stage.scanned, hasLength(3));
    expect(stage.notes, isEmpty);
    expect(stage.provider.refusedParameters, isEmpty);
    for (final body in stage.bodies) {
      expect(body['max_tokens'], 8192);
      expect(body['temperature'], 0);
      expect(body['seed'], isNotNull);
    }
  });

  test('a provider built with no sampling has nothing to be refused', () async {
    final bodies = <Map<String, dynamic>>[];
    await OpenAiCompatibleVisionProvider(
      baseUrl: 'https://api.example.test/v1',
      model: 'a-model',
      apiKey: 'k',
      temperature: null,
      seed: null,
      client: MockClient((request) async {
        bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        return _completion();
      }),
    ).analyze(_photo());

    expect(bodies.single.containsKey('temperature'), isFalse);
    expect(bodies.single.containsKey('seed'), isFalse);
    expect(bodies.single['max_tokens'], 8192);
  });
}
