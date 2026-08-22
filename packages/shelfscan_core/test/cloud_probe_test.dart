import 'dart:io';

import 'package:test/test.dart';

import '../tool/cloud_probe.dart';
import '../tool/control_capture.dart'
    show hiRes, manifestPath, notHereExit;

/// The published manifest's shape, and the same file with its control-set
/// blocks hand-edited out. Neither needs a figure: the point is what the tool
/// answers when it cannot find one.
const _published = '''
```control-set
[CONTROL-HIRES]
photos = a.jpg, b.jpg
```
''';

const _promptOnly = '''
```control-set
[PROMPT]
fingerprint = 0000beef
```
''';

void main() {
  group('flattenUsage', () {
    test('lifts the nested details objects the bill is hidden in', () {
      // The shape api.openai.com returned for a CONTROL-HIRES photo on
      // gpt-5.5, 2026-08-16. `reasoning_tokens` is two thirds of the answer
      // and is only in the nested object.
      final flat = flattenUsage({
        'prompt_tokens': 11045,
        'completion_tokens': 3846,
        'total_tokens': 14891,
        'prompt_tokens_details': {'cached_tokens': 8653, 'audio_tokens': 0},
        'completion_tokens_details': {
          'reasoning_tokens': 2451,
          'accepted_prediction_tokens': 0,
        },
      });

      expect(flat['prompt_tokens'], 11045);
      expect(flat['completion_tokens'], 3846);
      expect(flat['prompt_tokens_details.cached_tokens'], 8653);
      expect(flat['completion_tokens_details.reasoning_tokens'], 2451);
    });

    test('drops non-numeric fields rather than carrying them into the tally',
        () {
      final flat = flattenUsage({
        'prompt_tokens': 12,
        'model': 'gpt-5.5',
        'prompt_tokens_details': {'cached_tokens': 0, 'note': 'text'},
      });

      expect(flat.keys, ['prompt_tokens', 'prompt_tokens_details.cached_tokens']);
    });
  });

  group('a checkout that cannot answer the probe', () {
    late Directory root;

    setUp(() {
      root = Directory.systemTemp.createTempSync('shelfscan-probe-test');
      File('${root.path}/$manifestPath')
        ..createSync(recursive: true)
        ..writeAsStringSync(_published);
    });
    tearDown(() => root.deleteSync(recursive: true));

    test('will not probe where the working record is absent (T-0261)',
        () async {
      expect(
          await runProbe([hiRes, '1', '${root.path}/out.json'], const {},
              from: root),
          notHereExit);
    });

    test('names a missing manifest block instead of a null check (T-0232)',
        () async {
      File('${root.path}/$manifestPath').writeAsStringSync(_promptOnly);
      expect(
          await runProbe([hiRes, '1', '${root.path}/out.json'], const {},
              from: root),
          2);
    });
  });
}
