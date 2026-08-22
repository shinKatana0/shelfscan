/// What a refused cloud vision call tells the person who typed the model id
/// (T-0072).
///
/// The defect was a successful-LOOKING run: `AnthropicVisionProvider` threw
/// the provider's raw body, so a wrong model id, a wrong key and a rejected
/// parameter arrived as three walls of the same JSON and none of them said
/// which. Both cloud providers share one message function, so every claim
/// here is made against both -- they had the same defect and one of them was
/// added after the other (T-0006).
///
/// The bodies are real. 404, 401 and 400 were taken from api.openai.com on
/// 2026-08-15, one call each; the Anthropic ones are its documented shape,
/// unmeasured, because no Anthropic key was available.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

const _key = 'sk-secret-key-12345';
const _model = 'gpt-4.1-mini-typo';
const _baseUrl = 'https://api.groq.com/openai/v1';

/// Measured, api.openai.com, 2026-08-15.
const _openAi404 = '{\n  "error": {\n'
    '    "message": "The model `gpt-4.1-mini-typo` does not exist or you do '
    'not have access to it.",\n'
    '    "type": "invalid_request_error",\n'
    '    "param": null,\n'
    '    "code": "model_not_found"\n  }\n}';

/// Measured against a deliberately fake key: the endpoint echoes the key back
/// with both ends intact, which is why no 401 message quotes a body.
const _openAi401 = '{"error":{"message":"Incorrect API key provided: '
    'sk-secret-key-12345. You can find your API key at '
    'https://platform.openai.com/account/api-keys.",'
    '"type":"invalid_request_error","code":"invalid_api_key"}}';

/// Measured on gpt-5-mini, the live case T-0089 filed: this provider
/// hardcodes `max_tokens` and every GPT-5 model refuses it.
const _openAi400 = '{"error":{"message":"Unsupported parameter: '
    '\'max_tokens\' is not supported with this model. Use '
    '\'max_completion_tokens\' instead.","type":"invalid_request_error",'
    '"param":"max_tokens","code":"unsupported_parameter"}}';

const _anthropic404 = '{"type":"error","error":{"type":"not_found_error",'
    '"message":"model: gpt-4.1-mini-typo"}}';

const _anthropic401 = '{"type":"error","error":{"type":"authentication_error",'
    '"message":"invalid x-api-key"}}';

PhotoInput get _photo =>
    PhotoInput(name: 'shelf.jpg', bytes: Uint8List.fromList([1, 2, 3]));

typedef _Provider = ({String name, VisionProvider Function(http.Response) at});

final _providers = <_Provider>[
  (
    name: 'Anthropic',
    at: (response) => AnthropicVisionProvider(
          apiKey: _key,
          model: _model,
          client: MockClient((_) async => response),
        ),
  ),
  (
    name: 'openai-compatible',
    at: (response) => OpenAiCompatibleVisionProvider(
          baseUrl: _baseUrl,
          model: _model,
          apiKey: _key,
          client: MockClient((_) async => response),
        ),
  ),
];

/// The error one provider raises for one answer.
Future<Object> _failure(VisionProvider provider) async {
  try {
    await provider.analyze(_photo);
  } catch (e) {
    return e;
  }
  throw StateError('the provider did not fail');
}

/// Runs [body] once per cloud provider, with the message it produced.
void _forBothProviders(
  String description,
  http.Response Function(String providerName) response,
  void Function(String message, Object error) body,
) {
  for (final provider in _providers) {
    test('$description (${provider.name})', () async {
      final error = await _failure(provider.at(response(provider.name)));
      body('$error', error);
    });
  }
}

http.Response _notFound(String providerName) => http.Response(
    providerName == 'Anthropic' ? _anthropic404 : _openAi404, 404);

http.Response _unauthorized(String providerName) => http.Response(
    providerName == 'Anthropic' ? _anthropic401 : _openAi401, 401);

void main() {
  group('404 on a model id that does not exist', () {
    _forBothProviders('names the model and says the id was not found',
        _notFound, (message, _) {
      expect(message, contains('"$_model"'));
      expect(message, contains('404'));
      expect(message, contains('not found'));
    });

    _forBothProviders('does not blame the key', _notFound, (message, _) {
      expect(message, isNot(contains(_key)));
      expect(message.toLowerCase(), isNot(contains('rejected the api key')));
    });

    _forBothProviders('fails the photo without retrying', _notFound,
        (_, error) {
      expect(error, isNot(isA<RetryableException>()));
      expect(error, isA<VisionApiException>());
    });

    _forBothProviders('is a sentence, not the provider\'s JSON', _notFound,
        (message, error) {
      expect(message, isNot(contains('{')));
      expect(message, isNot(contains('"type":')));
      // Kept for a bug report, just never as the explanation.
      expect((error as VisionApiException).body, contains('{'));
      expect(error.statusCode, 404);
    });
  });

  group('401 on a key the endpoint will not take', () {
    _forBothProviders('says the key was rejected', _unauthorized,
        (message, _) {
      expect(message.toLowerCase(), contains('rejected the api key'));
      expect(message, contains('401'));
    });

    _forBothProviders('does not say the model id was not found', _unauthorized,
        (message, _) {
      expect(message, isNot(contains('not found')));
    });

    // The measured 401 body echoes the key back with its ends intact, so
    // quoting the provider here would put key material in a log the user is
    // about to paste into a bug report.
    _forBothProviders('never repeats the key back', _unauthorized,
        (message, _) {
      expect(message, isNot(contains(_key)));
      expect(message, isNot(contains('Incorrect API key provided')));
    });
  });

  test('a wrong model and a wrong key do not read the same', () async {
    for (final provider in _providers) {
      final wrongModel = '${await _failure(provider.at(_notFound(provider.name)))}';
      final wrongKey =
          '${await _failure(provider.at(_unauthorized(provider.name)))}';

      expect(wrongModel, isNot(wrongKey));
      expect(wrongModel, contains('404'));
      expect(wrongKey, contains('401'));
    }
  });

  group('400 on a parameter the model will not take', () {
    _forBothProviders(
        'quotes the one sentence that is the fix',
        (_) => http.Response(_openAi400, 400),
        (message, _) {
      // T-0089: this provider hardcodes max_tokens and every GPT-5 model
      // refuses it. Our own sentence cannot know that; the endpoint's can.
      expect(message, contains('max_completion_tokens'));
      expect(message, contains('"$_model"'));
      expect(message, isNot(contains('{')));
    });
  });

  group('a status the worker retries', () {
    _forBothProviders(
        '429 stays retryable and still explains itself',
        (_) => http.Response('{"error":{"message":"rate limit"}}', 429),
        (message, error) {
      expect(error, isA<RetryableException>());
      expect(message, contains('rate-limiting'));
      // The type name is not an explanation and used to lead this line.
      expect(message, isNot(contains('RetryableException')));
    });

    _forBothProviders('a 5xx blames the endpoint, not the run',
        (_) => http.Response('upstream connect error', 502), (message, error) {
      expect(error, isA<RetryableException>());
      expect(message, contains('502'));
      expect(message, contains('try again later'));
      // Not JSON at all: a proxy's plain text is the only information there
      // is, so it is quoted rather than dropped.
      expect(message, contains('upstream connect error'));
    });
  });

  test('a body with no message field is capped, never dumped whole', () async {
    final long = jsonEncode({'unexpected': List.filled(200, 'padding')});
    final message =
        '${await _failure(_providers.first.at(http.Response(long, 418)))}';

    expect(message.length, lessThan(long.length));
    expect(message, contains('418'));
  });
}
