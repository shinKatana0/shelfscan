/// Choosing the Claude model from the CLI, and what choosing one costs
/// (T-0067).
///
/// The defect these pin down is invisible in the output twice over. A pinned
/// model id answers fine until the day it 404s, and a temperature sent to a
/// model that rejects it comes back as a bare 400 that reads like a bad key.
/// So both halves are asserted on the constructed provider rather than on any
/// reply: no cloud key was available, and nothing here is
/// evidence about a real Anthropic call.
///
/// The wire consequence of `temperature: null` -- that the field is omitted
/// from the request body rather than sent as JSON null -- is pinned in
/// cloud_sampling_test.dart and is not re-derived here.
library;

import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

import '../bin/shelfscan.dart'
    show FallbackConfigError, anthropicModelVar, anthropicProviderFor,
        fallbackProviderFor;

void main() {
  const key = 'sk-ant-x';
  const noEnv = <String, String>{};

  group('--provider anthropic', () {
    test('with nothing set, the built-in default still works', () {
      final provider = anthropicProviderFor(key, noEnv);

      expect(provider.apiKey, key);
      // Not asserted as a literal: the id lives on the provider (T-0057) and
      // this test is about there BEING a working default, not about which one
      // -- an id this file pinned would be a second place to update.
      expect(provider.model, isNotEmpty);
      expect(provider.temperature, 0,
          reason: 'the default is the one model this project argued a '
              'temperature for');
    });

    test('an explicit model is used', () {
      final provider =
          anthropicProviderFor(key, const {anthropicModelVar: 'claude-opus-5'});

      expect(provider.model, 'claude-opus-5');
      expect(provider.apiKey, key);
    });

    test('an explicit model is sent with no sampling parameters', () {
      // The interaction this task exists for: sampling parameters return 400
      // on Claude Opus 4.7 and later, Sonnet 5 and Fable 5. Nothing here knows
      // which families those are -- a list would go stale exactly as the
      // pinned default did -- so ANY named model drops the temperature, and
      // the 400 cannot happen.
      for (final id in [
        'claude-opus-5',
        'claude-sonnet-5',
        'claude-fable-5',
        'claude-opus-4-7',
        // Including ones that would accept a temperature, and ones this
        // repository has never heard of: the rule keys on who chose the id.
        'claude-sonnet-4-6',
        'claude-something-not-released-yet',
      ]) {
        expect(anthropicProviderFor(key, {anthropicModelVar: id}).temperature,
            isNull,
            reason: '"$id" carried a temperature');
      }
    });

    test('an empty variable is the same as an unset one', () {
      // A shell that exports the name with no value must not select "" as a
      // model id.
      final provider = anthropicProviderFor(key, const {anthropicModelVar: ''});

      expect(provider.model, anthropicProviderFor(key, noEnv).model);
      expect(provider.temperature, 0);
    });
  });

  group('--fallback anthropic', () {
    test('reads the same variable, so the second reader is selectable too', () {
      final provider = fallbackProviderFor('anthropic', const {
        'ANTHROPIC_API_KEY': key,
        anthropicModelVar: 'claude-opus-5',
      }) as AnthropicVisionProvider;

      expect(provider.model, 'claude-opus-5');
      expect(provider.temperature, isNull);
    });

    test('the model variable alone still reaches no cloud', () {
      // The variable configures the endpoint; it never selects it. Same
      // decision as SHELFSCAN_OPENAI_* (decision 0011: cloud is an explicit
      // opt-in, typed per run).
      for (final flag in <String?>[null, 'none']) {
        expect(
          fallbackProviderFor(flag, const {
            'ANTHROPIC_API_KEY': key,
            anthropicModelVar: 'claude-opus-5',
          }),
          isNull,
          reason: 'flag "$flag" reached the cloud',
        );
      }
      // And a model with no key is still a missing key, not a silent run.
      expect(
        () => fallbackProviderFor(
            'anthropic', const {anthropicModelVar: 'claude-opus-5'}),
        throwsA(isA<FallbackConfigError>()),
      );
    });
  });
}
