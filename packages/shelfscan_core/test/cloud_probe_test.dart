import 'package:test/test.dart';

import '../tool/cloud_probe.dart';

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
}
