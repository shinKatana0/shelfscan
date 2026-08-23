/// The generation cap the local provider sends on every request (T-0281).
///
/// Pinned as a wire test for the reason the sampling options are: the defect it
/// closes is invisible in the output. A request without `num_predict` still
/// answers on every frame that answers at all, and the only frames that tell
/// the two apart are the ones dense enough to make the model loop -- where the
/// uncapped request spends the whole context window and about five minutes
/// producing something that is not JSON.
///
/// The value is a decision, not a default, so an accidental change to it has to
/// fail something. What it rests on is the doc comment on `_numPredict`.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

/// The densest synthetic frame that answered honestly generated this many
/// tokens (doc/measurements.md, "The 7B's density ceiling"). A cap at or under
/// it would report that frame as truncated instead of returning its rows.
const _honestMaximumTokens = 5504;

final _photo =
    PhotoInput(name: 'shelf.jpg', bytes: Uint8List.fromList([1, 2, 3]));

http.Response _ok() => http.Response(
    jsonEncode({
      'message': {'role': 'assistant', 'content': '{"items":[]}'}
    }),
    200,
    headers: {'content-type': 'application/json'});

Future<Map<String, dynamic>> _optionsSent() async {
  late Map<String, dynamic> body;
  await OllamaVisionProvider(client: MockClient((request) async {
    body = jsonDecode(request.body) as Map<String, dynamic>;
    return _ok();
  })).analyze(_photo);
  return body['options'] as Map<String, dynamic>;
}

void main() {
  test('every request carries num_predict, and it is 8192', () async {
    expect((await _optionsSent())['num_predict'], 8192);
  });

  test('the cap clears the densest honest answer measured', () async {
    final cap = (await _optionsSent())['num_predict'] as int;

    expect(cap, greaterThan(_honestMaximumTokens),
        reason: 'a cap at or below $_honestMaximumTokens tokens turns a frame '
            'that would have answered into a truncation failure');
  });

  test('sampling is still overridable and the cap is not', () async {
    late Map<String, dynamic> body;
    await OllamaVisionProvider(
      client: MockClient((request) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return _ok();
      }),
      temperature: 0.8,
      seed: 3,
    ).analyze(_photo);

    // The truncated message says the cap is fixed in this build and offers
    // fewer spines as the fix that is the user's; a constructor parameter for
    // it would make that sentence false.
    expect(body['options'], {
      'temperature': 0.8,
      'seed': 3,
      'num_predict': 8192,
    });
  });
}
