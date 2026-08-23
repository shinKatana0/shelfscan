/// The sampling options the local provider states on every request (T-0053).
///
/// Pinned as a wire test because the defect it closes is invisible in the
/// output: a request without `options` still answers, and the answer is a
/// draw from whatever temperature the model's Modelfile happens to carry.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

final _photo =
    PhotoInput(name: 'shelf.jpg', bytes: Uint8List.fromList([1, 2, 3]));

http.Response _ok() => http.Response(
    jsonEncode({
      'message': {'role': 'assistant', 'content': '{"items":[]}'}
    }),
    200,
    headers: {'content-type': 'application/json'});

Future<Map<String, dynamic>> _sentBy(OllamaVisionProvider Function(http.Client)
    build) async {
  late Map<String, dynamic> body;
  await build(MockClient((request) async {
    body = jsonDecode(request.body) as Map<String, dynamic>;
    return _ok();
  })).analyze(_photo);
  return body;
}

void main() {
  test('every request states temperature and seed', () async {
    final body = await _sentBy((client) => OllamaVisionProvider(client: client));

    expect(body['options'],
        {'temperature': 0, 'seed': 20260814, 'num_predict': 8192});
  });

  test('both are overridable, so a run can deliberately sample', () async {
    final body = await _sentBy((client) =>
        OllamaVisionProvider(client: client, temperature: 0.8, seed: 3));

    // `num_predict` rides along and is not overridable; ollama_generation_cap_test
    // is where that is argued.
    expect(body['options'],
        {'temperature': 0.8, 'seed': 3, 'num_predict': 8192});
  });
}
