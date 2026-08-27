/// What a refused cloud vision call may say, and the one field it may never
/// quote (T-0435).
///
/// The defect: `401` and `403` were one branch reading *"rejected the API
/// key -- the key itself"*. A 403 does not carry that. On this endpoint
/// family it is a project or organisation the key may not reach, a region
/// that is not served, a permission the key does not hold, or a model it may
/// not use -- and something in front of the API can answer one having put no
/// question to the API at all.
///
/// **The silence those two statuses kept is the thing to protect.**
/// api.openai.com answers 401 with the key echoed back inside
/// `error.message`, both ends intact, redacted at its own discretion and not
/// at ours (measured 2026-08-15, one call). So the split reads `error.type`
/// and `error.code` -- enum-like tokens a credential is not written into --
/// and leaves `error.message` and [providerDetail] alone. The first group
/// below is the one this file exists for, and it asserts in both directions:
/// the credential is absent from the message, AND the same body is one
/// [providerDetail] would have quoted, so the absence is this function's
/// refusal rather than an empty body.
///
/// Every fixture here is invented, including anything shaped like a
/// credential.
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
/// file is one shell away from being eaten.
final _lf = String.fromCharCode(0x0a);
final _nul = String.fromCharCode(0x00);
final _bell = String.fromCharCode(0x07);

/// The measured 401 shape, with the invented key in the place the real
/// endpoint puts the real one.
String _echoBody(String code) => jsonEncode({
      'error': {
        'message': 'Incorrect API key provided: $_credential. You can find '
            'your API key at https://api.invented-endpoint.test/keys.',
        'type': 'invalid_request_error',
        'code': code,
      }
    });

String _body(Object? error) => jsonEncode({'error': error});

String _message(int status, String body) => visionApiMessage(
    service: _service, model: _model, statusCode: status, body: body);

/// The two statuses whose body may hold the key, and the code each fixture
/// carries for it.
const _refused = {401: 'invalid_api_key', 403: 'model_not_permitted'};

void main() {
  group('the key in error.message reaches no message', () {
    _refused.forEach((status, code) {
      final body = _echoBody(code);

      test('$status quotes nothing the credential is in', () {
        final message = _message(status, body);

        expect(message, isNot(contains(_credential)));
        expect(message, isNot(contains('sk-')));
        expect(message, isNot(contains('Incorrect API key provided')));
      });

      test('$status refuses a body that was quotable', () {
        // The control in the other direction: the absence above is this
        // function declining to quote, not a body with nothing in it.
        expect(providerDetail(body), contains(_credential));
        expect(_message(status, body), isNot(contains('Provider said')));
      });

      test('$status names the two fields it does read', () {
        final message = _message(status, body);

        expect(message, contains('invalid_request_error'));
        expect(message, contains(code));
      });

      test('$status still says which status it was', () {
        expect(_message(status, body), contains('$status'));
      });
    });

    test('every other status still quotes the explanation', () {
      // providerDetail is untouched and every other branch depends on it.
      const said = 'Unsupported parameter: max_tokens';
      final body = _body({'message': said});

      expect(_message(400, body), contains('Provider said: $said'));
      expect(_message(404, body), contains(said));
      expect(_message(429, body), contains(said));
      expect(_message(502, body), contains(said));

      for (final status in _refused.keys) {
        expect(_message(status, body), isNot(contains(said)));
        expect(_message(status, body), isNot(contains('Provider said')));
      }
    });
  });

  group('a 403 claims less than a 401', () {
    final plain401 = _message(401, '');
    final plain403 = _message(403, '');

    test('they do not read the same', () {
      expect(plain403, isNot(plain401));
      expect(plain401, contains('401'));
      expect(plain403, contains('403'));
    });

    test('401 still says the key was rejected', () {
      // The app's status line is asserted on this phrase
      // (app/test/scan_all_failed_test.dart).
      expect(plain401, contains('rejected the API key'));
    });

    test('403 does not say the key is the thing that is wrong', () {
      expect(plain403.toLowerCase(), isNot(contains('rejected the api key')));
      expect(plain403, isNot(contains('the key itself')));
      expect(plain403.toLowerCase(), isNot(contains('wrong key')));
      expect(plain403.toLowerCase(), isNot(contains('incorrect')));
      expect(plain403.toLowerCase(), isNot(contains('invalid key')));
    });

    test('403 does not report that the credential was taken either', () {
      // A 403 can come from a proxy in front of the API that put no question
      // to it, so the sentence carries no verdict on the key in either
      // direction -- which is why the word is absent rather than negated.
      expect(plain403.toLowerCase(), isNot(contains('authenticat')));
      expect(plain403.toLowerCase(), isNot(contains('the key is fine')));
      expect(plain403.toLowerCase(), isNot(contains('accepted')));
      expect(plain403.toLowerCase(), isNot(contains('signed in')));
    });

    test('403 says what it does carry, and what else can answer one', () {
      expect(plain403, contains('access was refused'));
      expect(plain403, contains('proxy'));
      expect(plain403, contains('"$_model"'));
    });

    test('403 does not blame the model id the way a 404 does', () {
      expect(plain403, isNot(contains('not found')));
    });
  });

  group('a body this code cannot read is silence, not a throw', () {
    const unreadable = {
      'not JSON at all': '<html><body>403 Forbidden</body></html>',
      'empty': '',
      'whitespace': '   ',
      'a JSON array': '[{"type":"forbidden"}]',
      'a JSON string': '"forbidden"',
      'a JSON number': '403',
      'no error member': '{"detail":"forbidden"}',
      'error is a string': '{"error":"forbidden"}',
      'error is a list': '{"error":["forbidden"]}',
      'error has neither field': '{"error":{"message":"forbidden"}}',
    };

    unreadable.forEach((what, body) {
      for (final status in _refused.keys) {
        test('$status on $what', () {
          final message = _message(status, body);

          expect(message, contains('$status'));
          expect(message, isNot(contains('The endpoint named it')));
          expect(message.toLowerCase(), isNot(contains('forbidden')));
        });
      }
    });
  });

  group('a value that is not a token is dropped, never trimmed to fit', () {
    String named(Object? type) => _message(403, _body({'type': type}));

    test('a token at the bound is quoted, one past it is not', () {
      // The longest this family is known to use is 36 characters; the bound
      // is 48, and both sides of it are held here.
      expect(named('a' * 48), contains('a' * 48));
      expect(named('a' * 49), isNot(contains('The endpoint named it')));
      expect(named('unsupported_country_region_territory'),
          contains('unsupported_country_region_territory'));
    });

    test('an over-long value leaves no prefix of itself behind', () {
      // A bearer token is one unbroken run of exactly the characters a token
      // is made of, so a length cut alone would print the front of it. This
      // is the case that decides drop-whole over trim-to-fit.
      final bearer = 'eyJhbGciOiJIUzI1NiJ9.${'Q' * 60}.${'Z' * 43}';
      final message = named(bearer);

      expect(message, isNot(contains('eyJ')));
      expect(message, isNot(contains('QQQ')));
      expect(message, isNot(contains('The endpoint named it')));
    });

    test('a value with a space in it is not a token', () {
      // The echo again, one field over: even in `type` it is refused, because
      // what is quoted has to look like a token and not merely be short.
      expect(named('Incorrect API key provided: $_credential'),
          isNot(contains(_credential)));
      expect(named('two words'), isNot(contains('two words')));
    });

    test('a value that is not a string is absent, not coerced', () {
      for (final type in <Object?>[
        {'name': 'forbidden'},
        ['forbidden'],
        403,
        4.03,
        true,
        null,
      ]) {
        expect(named(type), isNot(contains('The endpoint named it')),
            reason: 'a $type in `type` is a body of an unknown shape');
      }
      expect(named({'name': 'forbidden'}).toLowerCase(),
          isNot(contains('forbidden')));
      expect(named(403), isNot(contains('type 403')));
    });

    test('control characters and newlines do not survive', () {
      final message = _message(
          403,
          _body({
            'type': 'quota${_lf}exceeded',
            'code': ' region_blocked$_lf',
          }));

      expect(message, contains('quotaexceeded'));
      expect(message, contains('region_blocked'));
      expect(
          message.codeUnits.any((unit) => unit < 32 || unit == 127), isFalse);
    });

    test('a value that is only control characters is nothing at all', () {
      expect(
          named('$_nul$_bell$_lf'), isNot(contains('The endpoint named it')));
      expect(named('   '), isNot(contains('The endpoint named it')));
    });

    test('one field present and one absent still names the one', () {
      final message = _message(401, _body({'code': 'invalid_api_key'}));

      expect(message, contains('code invalid_api_key'));
      expect(message, isNot(contains('type ')));
    });
  });

  group('through a provider, which is what the user sees', () {
    Future<Object> failureAt(int status, String body) async {
      final provider = OpenAiCompatibleVisionProvider(
        baseUrl: _service,
        model: _model,
        apiKey: _credential,
        client: MockClient((_) async => http.Response(body, status)),
      );
      try {
        await provider.analyze(
            PhotoInput(name: 'shelf.jpg', bytes: Uint8List.fromList([1, 2])));
      } catch (e) {
        return e;
      }
      throw StateError('the provider did not fail');
    }

    for (final entry in _refused.entries) {
      test('${entry.key} fails the photo with the sentence, not the body',
          () async {
        final error = await failureAt(entry.key, _echoBody(entry.value));

        expect(error, isA<VisionApiException>());
        expect('$error', isNot(contains(_credential)));
        expect('$error', isNot(contains('{')));
        expect('$error', contains(entry.value));

        final api = error as VisionApiException;
        expect(api.statusCode, entry.key);
        // Kept for a bug report, exactly as every other status keeps it.
        expect(api.body, contains(_credential));
      });
    }
  });
}
