/// Wire format of the OpenAI-compatible provider (T-0006).
///
/// Payload parsing is not retested here -- it is the shared
/// `parsePhotoAnalysisText` and is covered for all three providers in
/// vision_parsing_test.dart. What is provider-specific, and therefore
/// pinned here, is the request this class puts on the wire and how it
/// classifies a failure.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

const _ok = '{"items":[{"raw_title":"Vex"}]}';

http.Response _completion(String text) => http.Response(
    jsonEncode({
      'choices': [
        {
          'message': {'role': 'assistant', 'content': text}
        }
      ]
    }),
    200,
    headers: {'content-type': 'application/json'});

/// Runs one analysis and hands back the request the provider made.
Future<http.Request> _capture(
  PhotoInput photo, {
  String baseUrl = 'https://api.groq.com/openai/v1',
  String model = 'llama-4-scout',
  String apiKey = 'k-123',
}) async {
  late http.Request captured;
  await OpenAiCompatibleVisionProvider(
    baseUrl: baseUrl,
    model: model,
    apiKey: apiKey,
    client: MockClient((request) async {
      captured = request;
      return _completion(_ok);
    }),
  ).analyze(photo);
  return captured;
}

Future<PhotoAnalysis> _analyzeAgainst(http.Response response) =>
    OpenAiCompatibleVisionProvider(
      baseUrl: 'https://example.test/v1',
      model: 'm',
      apiKey: 'sk-secret-123',
      client: MockClient((_) async => response),
    ).analyze(PhotoInput(
      name: 'shelf.jpg',
      bytes: Uint8List.fromList([1, 2]),
    ));

Map<String, dynamic> _body(http.Request request) =>
    jsonDecode(request.body) as Map<String, dynamic>;

List<dynamic> _userContent(http.Request request) {
  final messages = _body(request)['messages'] as List<dynamic>;
  return (messages.single as Map<String, dynamic>)['content'] as List<dynamic>;
}

Map<String, dynamic> _part(http.Request request, String type) =>
    _userContent(request)
        .cast<Map<String, dynamic>>()
        .firstWhere((p) => p['type'] == type);

void main() {
  group('request', () {
    test('posts to {baseUrl}/chat/completions with a bearer key', () async {
      final request = await _capture(
          PhotoInput(name: 'a.jpg', bytes: Uint8List.fromList([1])));

      expect(request.method, 'POST');
      expect(request.url.toString(),
          'https://api.groq.com/openai/v1/chat/completions');
      expect(request.headers['authorization'], 'Bearer k-123');
    });

    test('a base URL written with a trailing slash gives the same path',
        () async {
      final request = await _capture(
        PhotoInput(name: 'a.jpg', bytes: Uint8List.fromList([1])),
        baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai/',
      );

      expect(request.url.toString(),
          'https://generativelanguage.googleapis.com/v1beta/openai/'
          'chat/completions');
    });

    test('sends the shared detection prompt as the text part', () async {
      final request = await _capture(
          PhotoInput(name: 'a.jpg', bytes: Uint8List.fromList([1])));

      // The provider carries no instruction text of its own; every rule in
      // it is measured wording owned by providers/vision.dart.
      expect(_part(request, 'text')['text'], detectionPrompt);
    });

    test('sends the image as a base64 data: URI in an image_url part',
        () async {
      final bytes = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0x00, 0x10]);
      final request = await _capture(
          PhotoInput(name: 'a.jpg', bytes: bytes, mimeType: 'image/png'));

      final url = (_part(request, 'image_url')['image_url']
          as Map<String, dynamic>)['url'] as String;
      expect(url, 'data:image/png;base64,${base64Encode(bytes)}');
    });

    test('falls back to image/jpeg when the photo carries no mime type',
        () async {
      final request = await _capture(
          PhotoInput(name: 'a.jpg', bytes: Uint8List.fromList([1])));

      final url = (_part(request, 'image_url')['image_url']
          as Map<String, dynamic>)['url'] as String;
      expect(url, startsWith('data:image/jpeg;base64,'));
    });

    test('names the configured model and asks for no vendor-specific extras',
        () async {
      final request = await _capture(
          PhotoInput(name: 'a.jpg', bytes: Uint8List.fromList([1])),
          model: 'gemini-2.5-flash');
      final body = _body(request);

      expect(body['model'], 'gemini-2.5-flash');
      // response_format support varies across this family; asking for it is
      // what would force per-vendor branching into the one shared class.
      expect(body.containsKey('response_format'), isFalse);
    });
  });

  group('failures', () {
    test('429 is retryable, so the worker backs off instead of failing',
        () async {
      expect(_analyzeAgainst(http.Response('rate limited', 429)),
          throwsA(isA<RetryableException>()));
    });

    test('every 5xx is retryable', () async {
      for (final status in [500, 502, 503, 529]) {
        expect(_analyzeAgainst(http.Response('server error', status)),
            throwsA(isA<RetryableException>()),
            reason: '$status was not treated as retryable');
      }
    });

    test('a 4xx that is not 429 fails the photo without retrying', () async {
      final failure = _analyzeAgainst(http.Response('{"error":"bad key"}', 401));

      expect(failure, throwsA(isA<Exception>()));
      expect(failure, throwsA(isNot(isA<RetryableException>())));
    });

    test('the error names the endpoint that failed, never the key', () async {
      await expectLater(
        _analyzeAgainst(http.Response('nope', 404)),
        throwsA(isA<Exception>().having(
            (e) => e.toString(),
            'message',
            allOf(contains('https://example.test/v1'), contains('404'),
                isNot(contains('sk-secret-123'))))),
      );
    });
  });

  test('a successful answer becomes detections', () async {
    final analysis = await _analyzeAgainst(_completion(_ok));

    expect(analysis.items.single.rawTitle, 'Vex');
    expect(analysis.items.single.sourcePhoto, 'shelf.jpg');
  });
}
