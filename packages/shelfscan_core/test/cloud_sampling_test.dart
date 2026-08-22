/// The sampling options the two cloud providers state on every request
/// (T-0057), and the one the Anthropic API cannot offer.
///
/// Pinned as wire tests for the same reason as ollama_sampling_test.dart: the
/// defect is invisible in the output. A request without sampling options still
/// answers, and the answer is a draw at whatever the endpoint chose. Neither
/// provider has ever been called for real from this repository -- no cloud
/// key was available -- so these tests pin the REQUEST and claim nothing about the
/// replies.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

final _photo =
    PhotoInput(name: 'shelf.jpg', bytes: Uint8List.fromList([1, 2, 3]));

http.Response _anthropicOk() => http.Response(
    jsonEncode({
      'content': [
        {'type': 'text', 'text': '{"items":[]}'}
      ]
    }),
    200,
    headers: {'content-type': 'application/json'});

http.Response _completionOk() => http.Response(
    jsonEncode({
      'choices': [
        {
          'message': {'role': 'assistant', 'content': '{"items":[]}'}
        }
      ]
    }),
    200,
    headers: {'content-type': 'application/json'});

Future<Map<String, dynamic>> _bodyOf(
  VisionProvider Function(http.Client) build,
  http.Response Function() reply,
) async {
  late Map<String, dynamic> body;
  await build(MockClient((request) async {
    body = jsonDecode(request.body) as Map<String, dynamic>;
    return reply();
  })).analyze(_photo);
  return body;
}

Future<Map<String, dynamic>> _anthropic(
        {double? temperature = 0, String model = 'claude-sonnet-4-6'}) =>
    _bodyOf(
        (client) => AnthropicVisionProvider(
            apiKey: 'k', model: model, temperature: temperature, client: client),
        _anthropicOk);

Future<Map<String, dynamic>> _openAiCompatible(
        {double? temperature = 0, int? seed = 20260814}) =>
    _bodyOf(
        (client) => OpenAiCompatibleVisionProvider(
              baseUrl: 'https://api.groq.com/openai/v1',
              model: 'llama-4-scout',
              apiKey: 'k',
              temperature: temperature,
              seed: seed,
              client: client,
            ),
        _completionOk);

void main() {
  group('Anthropic', () {
    test('every request states a temperature', () async {
      expect((await _anthropic())['temperature'], 0);
    });

    test('and carries no seed, because the Messages API has none', () async {
      final body = await _anthropic();

      expect(body.containsKey('seed'), isFalse);
      // Nothing else may quietly stand in for one either: top_p and top_k are
      // left unset on purpose (see the constructor), and Claude 4+ rejects
      // top_p sent alongside temperature.
      expect(body.containsKey('top_p'), isFalse);
      expect(body.containsKey('top_k'), isFalse);
    });

    test('temperature is overridable, so a run can deliberately sample',
        () async {
      expect((await _anthropic(temperature: 0.8))['temperature'], 0.8);
    });

    test('null omits the field, for the models that reject it', () async {
      // Sampling parameters return 400 on Claude Opus 4.7 and later, Sonnet 5
      // and Fable 5; without this escape hatch, pinning the temperature would
      // break every configuration pointing at one of them.
      final body = await _anthropic(temperature: null, model: 'claude-opus-5');

      expect(body.containsKey('temperature'), isFalse);
      expect(body['model'], 'claude-opus-5');
    });
  });

  group('OpenAI-compatible', () {
    test('every request states temperature and seed', () async {
      final body = await _openAiCompatible();

      expect(body['temperature'], 0);
      expect(body['seed'], 20260814);
    });

    test('both are overridable, so a run can vary one at a time', () async {
      final body = await _openAiCompatible(temperature: 0.8, seed: 3);

      expect(body['temperature'], 0.8);
      expect(body['seed'], 3);
    });

    test('either can be dropped for an endpoint that rejects the field',
        () async {
      final body = await _openAiCompatible(temperature: null, seed: null);

      expect(body.containsKey('temperature'), isFalse);
      expect(body.containsKey('seed'), isFalse);
    });
  });
}
