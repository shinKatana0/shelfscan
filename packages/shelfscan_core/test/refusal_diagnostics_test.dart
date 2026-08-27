/// What answered a refused cloud vision call, and where that may be said
/// (T-0437).
///
/// T-0435 split 401 from 403 and named the case it could not tell apart: a
/// proxy or gateway in front of the endpoint answering on its own, having put
/// nothing to the API. The fields that separate those -- `server`, `cf-ray`,
/// `content-type` and a classification of the body -- plus the handle support
/// looks up, `x-request-id`, now travel on
/// [VisionApiException.diagnostics] rather than in the sentence the user
/// reads.
///
/// **Two invariants this file exists to hold.** The metadata must not appear
/// in [VisionApiException.message], which is a status line somebody reads
/// rather than searches; and none of it may cost a credential -- the measured
/// 401 from api.openai.com echoes the API key back inside `error.message`,
/// which is why that field is never read and no character of the body is ever
/// quoted. The first group asserts the second invariant in both directions,
/// so an empty fixture cannot pass for a refusal.
///
/// Every fixture here is invented (`doc/conventions.md` §3b), including
/// anything shaped like a credential, a request id or an endpoint.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

const _service = 'https://api.invented-endpoint.test/v1';
const _model = 'vision-mini-typo';

/// Invented, and shaped like the thing that must never be printed.
const _credential = 'sk-invented-9WQ2m4Kx7Ttz0Ab1Cd3Ef5Gh7Ij9Kl';

/// Control characters by code point rather than by escape: a backslash in this
/// file is one shell away from being eaten (`doc/conventions.md` §4a).
final _lf = String.fromCharCode(0x0a);
final _cr = String.fromCharCode(0x0d);
final _nul = String.fromCharCode(0x00);

/// The measured 401 shape, with the invented key where the real endpoint puts
/// the real one.
final _echoBody = jsonEncode({
  'error': {
    'message': 'Incorrect API key provided: $_credential. You can find your '
        'API key at https://api.invented-endpoint.test/keys.',
    'type': 'invalid_request_error',
    'code': 'invalid_api_key',
  }
});

Exception _failure(int status, String body, Map<String, String> headers) =>
    visionApiFailure(
      service: _service,
      model: _model,
      statusCode: status,
      body: body,
      headers: headers,
      // Held false throughout so every status arrives as a
      // VisionApiException and the field is reachable; 401 and 403 are
      // non-retryable on both providers anyway.
      retryable: false,
    );

String? _diagnostics(int status, String body,
        [Map<String, String> headers = const {}]) =>
    (_failure(status, body, headers) as VisionApiException).diagnostics;

String _message(int status, String body,
        [Map<String, String> headers = const {}]) =>
    (_failure(status, body, headers) as VisionApiException).message;

const _refused = [401, 403];

void main() {
  group('the key in error.message reaches no diagnostics either', () {
    for (final status in _refused) {
      test('$status names the two enum fields and not the message', () {
        final said = _diagnostics(status, _echoBody)!;

        // The control in the other direction, on the SAME body: the absence
        // above is this code declining to read `error.message`, not a fixture
        // with nothing in it to find.
        expect(providerDetail(_echoBody), contains(_credential));

        expect(said, isNot(contains(_credential)));
        expect(said, isNot(contains('sk-')));
        expect(said, isNot(contains('Incorrect API key provided')));
        expect(said, contains('type invalid_request_error'));
        expect(said, contains('code invalid_api_key'));
      });

      test('$status quotes no character of the body', () {
        // Not one word of the prose, whatever the field it sits in.
        final body = jsonEncode({
          'error': {
            'message': 'Incorrect API key provided: $_credential.',
            'type': 'invalid_request_error',
            'detail': 'organisation org_invented is not permitted here',
          }
        });

        expect(providerDetail(body), contains(_credential));
        expect(_diagnostics(status, body), isNot(contains('organisation')));
        expect(_diagnostics(status, body), isNot(contains('permitted')));
        expect(_diagnostics(status, body), isNot(contains(_credential)));
      });
    }

    test('a request header echoed back is not among the fields read', () {
      // The defence is the allowlist, not a shape test: the four headers read
      // are ones an endpoint generates, never ones it received. A proxy
      // echoing the request would put it somewhere this code does not look.
      final said = _diagnostics(403, '', {
        'authorization': 'Bearer $_credential',
        'x-original-authorization': _credential,
        'x-api-key': _credential,
        'server': 'invented-proxy',
      })!;

      expect(said, isNot(contains(_credential)));
      expect(said, isNot(contains('Bearer')));
      expect(said, contains('server invented-proxy'));
    });
  });

  group('the metadata stays off the sentence the user reads', () {
    for (final status in _refused) {
      test('$status says none of it in the message', () {
        const headers = {
          'content-type': 'text/html; charset=utf-8',
          'x-request-id': 'req_invented_0a1b2c',
          'server': 'cloudfront-invented',
          'cf-ray': '1a2b3c4d5e6f7a8b-AAA',
        };
        final message = _message(status, '<html>no</html>', headers);

        expect(message, isNot(contains('content-type')));
        expect(message, isNot(contains('x-request-id')));
        expect(message, isNot(contains('cf-ray')));
        expect(message, isNot(contains('req_invented_0a1b2c')));
        expect(message, isNot(contains('cloudfront-invented')));
        expect(message, isNot(contains('non-json')));
        // What T-0435 put there is untouched and still there.
        expect(message, contains('$status'));
      });
    }

    test('403 sends the reader to the connection before the settings', () {
      final message = _message(403, '');

      expect(message.toLowerCase(), contains('connection'));
      expect(message.toLowerCase(), contains('vpn'));
      expect(message,
          contains('refused over one network and work over another'));
      // T-0435 forbids `accepted` here, and the first draft of this clause
      // brought the word back in a sentence about a different request. The
      // rule survives the new clause rather than being relaxed for it.
      expect(message.toLowerCase(), isNot(contains('accepted')));
      // The clause the Open settings button still lands on (T-0435).
      expect(message, contains('check the key you configured'));
      expect(message.indexOf('another connection'),
          lessThan(message.indexOf('check the key you configured')));
    });

    test('401 does not gain the connection clause', () {
      final message = _message(401, '');

      expect(message, contains('rejected the API key'));
      expect(message.toLowerCase(), isNot(contains('vpn')));
    });
  });

  group('the body is classified, never quoted', () {
    // Every fixture carries the word `forbidden` somewhere the diagnostics
    // may not read it -- prose in `message`, a member this code does not
    // know, body text -- so one assertion covers all four.
    const cases = {
      'json': '{"error":{"type":"region_blocked","message":"forbidden"}}',
      'unrecognized-json': '{"detail":"forbidden"}',
      'non-json': '<html><body>403 Forbidden</body></html>',
      'empty': '',
    };

    cases.forEach((expected, body) {
      for (final status in _refused) {
        test('$status on a $expected body', () {
          final said = _diagnostics(status, body)!;

          expect(said, contains('body $expected'));
          expect(said.toLowerCase(), isNot(contains('forbidden')));
          expect(said, isNot(contains('html')));
        });
      }
    });

    test('the json class is the shape this code can read fields out of', () {
      // `json` is not "it parsed" -- it is the OpenAI error shape, the one
      // `type` and `code` are read from. That is why `{"detail":...}` is a
      // different answer even though both decode.
      expect(_diagnostics(403, cases['json']!),
          contains('type region_blocked'));
      expect(_diagnostics(403, cases['unrecognized-json']!),
          isNot(contains('type ')));
    });

    test('unrecognized-json and non-json are different answers', () {
      // The endpoint spoke JSON this code does not know, against something
      // that was not speaking JSON at all. Collapsing them loses the whole
      // point of the field.
      final unknownShape = _diagnostics(403, '{"detail":"no"}')!;
      final notJson = _diagnostics(403, 'no')!;

      expect(unknownShape, contains('body unrecognized-json'));
      expect(notJson, contains('body non-json'));
      expect(unknownShape, isNot(contains('body non-json')));
      expect(notJson, isNot(contains('body unrecognized-json')));
    });

    test('malformed JSON is non-json, not a throw', () {
      for (final body in const [
        '{"error":{"type":"forbidden"',
        '{,}',
        '{"error":}',
        'null,',
      ]) {
        expect(_diagnostics(403, body), contains('body non-json'),
            reason: body);
      }
    });

    test('JSON that is not an object is unrecognized-json', () {
      for (final body in const [
        '[{"type":"forbidden"}]',
        '"forbidden"',
        '403',
        'null',
        'true',
      ]) {
        expect(_diagnostics(403, body), contains('body unrecognized-json'),
            reason: body);
      }
    });

    test('an error member this code cannot read is unrecognized-json', () {
      for (final body in const [
        '{"error":"forbidden"}',
        '{"error":["forbidden"]}',
        '{"errors":[{"type":"forbidden"}]}',
      ]) {
        expect(_diagnostics(403, body), contains('body unrecognized-json'),
            reason: body);
      }
    });

    test('a whitespace-only body is empty rather than non-json', () {
      // Three spaces carry nothing; calling them non-json would suggest
      // something answered with a document.
      expect(_diagnostics(403, '   '), contains('body empty'));
      expect(_diagnostics(403, '$_lf$_lf'), contains('body empty'));
    });

    test('a content-type announcing JSON over a body that is not is kept as '
        'both', () {
      // The finding itself: something answered in place of the API. Neither
      // field is reconciled into the other.
      final said = _diagnostics(403, '<html>blocked</html>',
          {'content-type': 'application/json'})!;

      expect(said, contains('content-type application/json'));
      expect(said, contains('body non-json'));
    });
  });

  group('header keys are matched whatever their case', () {
    // Established rather than assumed, and it is not what the brief said.
    // Measured on http 1.6.0, Dart 3.13.0: a Response built from the wire by
    // the IO client comes back with every key lower-cased, and a Response
    // built by the constructor keeps the keys it was handed, in a plain
    // Map with no case folding at all. `probe over 127.0.0.1` printed
    // `[transfer-encoding, cf-ray, content-type, x-request-id]` for the
    // first and `[Content-Type, CF-Ray, X-Request-Id]` for the second, and
    // a lowercase lookup on the second returned null. So neither casing may
    // be assumed at a lookup, and both are held here.
    test('the casing the constructor preserves is still found', () {
      final said = _diagnostics(403, '', const {
        'Content-Type': 'text/html',
        'X-Request-Id': 'req_invented_1',
        'Server': 'invented-edge',
        'CF-RAY': '1a2b3c4d5e6f7a8b-BBB',
      })!;

      expect(said, contains('content-type text/html'));
      expect(said, contains('x-request-id req_invented_1'));
      expect(said, contains('server invented-edge'));
      expect(said, contains('cf-ray 1a2b3c4d5e6f7a8b-BBB'));
    });

    test('the casing the wire produces is found too', () {
      final said = _diagnostics(403, '', const {
        'content-type': 'text/html',
        'x-request-id': 'req_invented_2',
        'server': 'invented-edge',
        'cf-ray': '1a2b3c4d5e6f7a8b-CCC',
      })!;

      expect(said, contains('content-type text/html'));
      expect(said, contains('x-request-id req_invented_2'));
      expect(said, contains('server invented-edge'));
      expect(said, contains('cf-ray 1a2b3c4d5e6f7a8b-CCC'));
    });

    test('a case-sensitive lookup would have reported this response clean', () {
      // The control for the paragraph above: this map contains all four
      // fields and not one of them under a lowercase key.
      const mixed = {'CONTENT-TYPE': 'text/plain', 'X-Request-ID': 'req_3'};

      expect(mixed.keys.any((key) => key == key.toLowerCase()), isFalse);
      expect(_diagnostics(403, '', mixed), contains('content-type text/plain'));
      expect(_diagnostics(403, '', mixed), contains('x-request-id req_3'));
    });
  });

  group('a value that cannot be made safe is absent, never coerced', () {
    String said(String name, String value) =>
        _diagnostics(403, '', {name: value})!;

    test('an over-long header is dropped whole, leaving no prefix', () {
      // The decision this task turned on. The header class strictly contains
      // the token class, so it admits `Bearer <token>` -- exactly the string
      // a trim would have printed the front of.
      final bearer = 'Bearer eyJhbGciOiJIUzI1NiJ9.${'Q' * 60}.${'Z' * 43}';
      final line = said('x-request-id', bearer);

      expect(line, isNot(contains('Bearer')));
      expect(line, isNot(contains('eyJ')));
      expect(line, isNot(contains('QQQ')));
      expect(line, isNot(contains('x-request-id')));
      // Every other field is gated on its own, so the line still renders.
      expect(line, contains('HTTP 403'));
      expect(line, contains('body empty'));
    });

    test('both sides of the 80-character bound', () {
      expect(said('server', 'a' * 80), contains('server ${'a' * 80}'));
      expect(said('server', 'a' * 81), isNot(contains('server ')));
      expect(
          said('content-type',
              'multipart/form-data; boundary=----InventedBoundary7MA4YWxkTrZ'),
          contains('boundary=----InventedBoundary7MA4YWxkTrZ'));
    });

    test('one dropped value does not suppress the others', () {
      final line = _diagnostics(403, '', {
        'server': 'b' * 200,
        'content-type': 'text/html',
        'x-request-id': 'req_invented_4',
      })!;

      expect(line, isNot(contains('bbb')));
      expect(line, isNot(contains('server ')));
      expect(line, contains('content-type text/html'));
      expect(line, contains('x-request-id req_invented_4'));
    });

    test('a multi-line header survives as one line', () {
      final line = _diagnostics(403, '', {
        'content-type': 'text/html;${_cr}${_lf} charset=utf-8',
        'x-request-id': 'req_invented_5$_lf',
      })!;

      expect(line.codeUnits.any((unit) => unit < 32 || unit == 127), isFalse);
      expect(line, contains('x-request-id req_invented_5'));
      expect(line, contains('content-type'));
    });

    test('a header that is only control characters is nothing at all', () {
      expect(said('server', '$_nul$_lf$_cr'), isNot(contains('server ')));
      expect(said('cf-ray', '   '), isNot(contains('cf-ray')));
      expect(said('x-request-id', ''), isNot(contains('x-request-id')));
    });

    test('a header outside printable ASCII is dropped', () {
      // Header values are ASCII by specification, and this one is about to be
      // read by a person -- so a right-to-left override cannot be smuggled
      // into a status line through one. Those two code points are built
      // rather than typed: the analyzer refuses them in a literal, which is
      // the same objection one level up.
      final override = String.fromCharCode(0x202e);
      final pop = String.fromCharCode(0x202c);
      for (final value in [
        'sacr${String.fromCharCode(0xe9)}-bleu-invented',
        'edge-${override}terces$pop',
        'edge-${String.fromCharCode(0x4e2d)}',
      ]) {
        expect(said('server', value), isNot(contains('server ')),
            reason: value);
      }
    });

    test('the type and code gates from T-0435 are unchanged here', () {
      String named(Object? type) =>
          _diagnostics(403, jsonEncode({'error': {'type': type}}))!;

      expect(named('a' * 48), contains('type ${'a' * 48}'));
      expect(named('a' * 49), isNot(contains('type ')));
      expect(named('two words'), isNot(contains('type ')));
      expect(named(403), isNot(contains('type ')));
      expect(named(null), isNot(contains('type ')));
      expect(named({'name': 'x'}), isNot(contains('type ')));
    });
  });

  group('an absent field is absent without complaint', () {
    for (final status in _refused) {
      test('$status with no headers at all still answers', () {
        final said = _diagnostics(status, '')!;

        expect(said, 'HTTP $status; body empty');
      });
    }

    test('a body with fields and no headers names only the fields', () {
      final said = _diagnostics(403, _echoBody)!;

      expect(said,
          'HTTP 403; type invalid_request_error; code invalid_api_key; '
          'body json');
    });

    test('headers with none of the four read are not mentioned', () {
      final said = _diagnostics(403, '', const {
        'date': 'Thu, 01 Jan 1970 00:00:00 GMT',
        'connection': 'keep-alive',
        'vary': 'Accept-Encoding',
      })!;

      expect(said, 'HTTP 403; body empty');
    });

    test('the fields keep their order however the headers arrive', () {
      final said = _diagnostics(403, _echoBody, const {
        'cf-ray': '1a2b3c4d5e6f7a8b-DDD',
        'server': 'invented-edge',
        'x-request-id': 'req_invented_6',
        'content-type': 'application/json',
      })!;

      expect(
          said,
          'HTTP 403; type invalid_request_error; code invalid_api_key; '
          'content-type application/json; body json; '
          'x-request-id req_invented_6; server invented-edge; '
          'cf-ray 1a2b3c4d5e6f7a8b-DDD');
    });
  });

  group('no other status carries any of this', () {
    for (final status in const [400, 404, 429, 500, 502, 418]) {
      test('$status has no diagnostics', () {
        expect(
            _diagnostics(status, _echoBody, const {
              'content-type': 'application/json',
              'cf-ray': '1a2b3c4d5e6f7a8b-EEE',
            }),
            isNull);
      });
    }

    test('and their sentences are unmoved', () {
      // providerDetail is what those branches quote and it is untouched.
      const said = 'Unsupported parameter: max_tokens';
      final body = jsonEncode({'error': {'message': said}});

      expect(_message(400, body), contains('Provider said: $said'));
      expect(_message(404, body), contains(said));
      expect(_message(429, body), contains(said));
      expect(_message(502, body), contains(said));
    });
  });

  group('through a provider, which is the path that carries the headers', () {
    Future<VisionApiException> refusalAt(
        int status, String body, Map<String, String> headers) async {
      final provider = OpenAiCompatibleVisionProvider(
        baseUrl: _service,
        model: _model,
        apiKey: _credential,
        client: MockClient(
            (_) async => http.Response(body, status, headers: headers)),
      );
      try {
        await provider.analyze(
            PhotoInput(name: 'shelf.jpg', bytes: Uint8List.fromList([1, 2])));
      } on VisionApiException catch (e) {
        return e;
      }
      throw StateError('the provider did not fail');
    }

    test('a 403 from something in front of the API says so', () async {
      final error = await refusalAt(403, '<html>Access denied</html>', const {
        'Content-Type': 'text/html; charset=UTF-8',
        'Server': 'invented-edge',
        'CF-Ray': '1a2b3c4d5e6f7a8b-FFF',
      });

      expect(error.diagnostics, contains('content-type text/html'));
      expect(error.diagnostics, contains('body non-json'));
      expect(error.diagnostics, contains('server invented-edge'));
      expect(error.diagnostics, contains('cf-ray 1a2b3c4d5e6f7a8b-FFF'));
      expect(error.diagnostics, isNot(contains('Access denied')));
      expect('$error', isNot(contains('invented-edge')));
    });

    test('a 401 keeps the raw body for a debugger and says none of it',
        () async {
      final error = await refusalAt(401, _echoBody,
          const {'content-type': 'application/json', 'x-request-id': 'req_7'});

      expect(error.diagnostics, contains('type invalid_request_error'));
      expect(error.diagnostics, contains('body json'));
      expect(error.diagnostics, contains('x-request-id req_7'));
      expect(error.diagnostics, isNot(contains(_credential)));
      expect('$error', isNot(contains(_credential)));
      // Unchanged: the raw answer is kept, unshown, for a bug report.
      expect(error.body, contains(_credential));
    });

    test('a 404 through the same provider carries no diagnostics', () async {
      final error = await refusalAt(404, _echoBody,
          const {'content-type': 'application/json', 'server': 'invented'});

      expect(error.diagnostics, isNull);
    });
  });
}
