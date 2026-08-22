/// The client half of `stalled_endpoint_test.dart`'s exit check (T-0104).
///
/// A separate process because the thing being measured is whether a timed-out
/// connection keeps the Dart VM alive after `main` returns, and a test that
/// hosted the stalled server itself would hold the loop open with its own
/// listening socket. Not a `_test.dart`: `dart test` never collects it.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:shelfscan_core/shelfscan_core.dart';

Future<void> main(List<String> args) async {
  try {
    await OllamaVisionProvider(
      baseUrl: 'http://127.0.0.1:${args.single}',
      timeout: const Duration(seconds: 1),
    ).analyze(PhotoInput(
        name: 'shelf.jpg', bytes: Uint8List.fromList(const [1, 2, 3])));
  } on OllamaUnreachableException catch (e) {
    stdout.writeln(e.message);
  }
}
