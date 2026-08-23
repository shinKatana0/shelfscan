/// The real Windows credential store and the real preferences file.
///
/// Everything in `app/test/` runs [SettingsStore] against in-memory fakes, so
/// the two backends underneath it -- [SecureSecretStore] over
/// `flutter_secure_storage`, [SharedPrefsStore] over `shared_preferences` --
/// have never been executed against an operating system (T-0017). This file
/// is the harness that does it.
///
/// ## Why it is four runs and not one test
///
/// The property worth proving is that a secret survives a **restart**, and a
/// restart cannot be expressed inside one `flutter drive` invocation: the
/// integration test *is* the app process, so anything it can reach in one run
/// it could also have reached from memory. `tester.restartAndRestore` and a
/// fresh `pumpWidget` rebuild the widget tree, which is a different and much
/// weaker claim.
///
/// So the restart is the process boundary between two invocations. Each run
/// executes one phase, named by `--dart-define`, and a phase that reads never
/// writes:
///
///   1. `write` -- store an invented secret and an invented non-secret.
///   2. `read`  -- a NEW process reads both back. Nothing in this process
///                 wrote them, so what it finds came out of the OS store and
///                 the preferences file, across a process death.
///   3. `clear` -- store `''` in both, which both backends define as delete.
///   4. `gone`  -- a NEW process confirms the delete also survived.
///
/// Phase 2 carries the claim; phase 4 is T-0017's last clause (clearing a key
/// removes it from the credential store) held to the same standard.
///
/// ## Running it -- see doc/reports/T-0287.md
///
///   cd app
///   flutter drive --driver=test_driver/integration_test.dart \
///     --target=integration_test/keychain_persistence_test.dart \
///     -d windows --dart-define=SHELFSCAN_KEYCHAIN_PHASE=write
///
/// then the same line again with `read`, `clear` and `gone`, in that order.
/// Run all four: `write` and `clear` leave state in the real credential store
/// of whoever runs them, and `gone` is what takes it back out.
///
/// **This opens a window.** `doc/conventions.md` section 3 forbids driving it
/// while the owner is at the machine, which is why the worker that wrote this
/// did not run it.
///
/// ## Why it does not touch the app's own keys
///
/// The probe keys below are its own. Writing to [SettingsStore]'s real keys
/// would overwrite whatever the person running this has in their credential
/// store -- their Anthropic key, their IGDB pair -- and a harness that
/// destroys the thing it is verifying is the clipboard incident again. What
/// has never been tested is the backends, not the key names, so the backends
/// are what this exercises.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shelfscan_app/settings_store.dart';

/// Invented, and deliberately unmistakable as such: nothing here is anyone's
/// credential, and the secret's value doubles as the needle phase `read`
/// searches the preferences file for.
const _secretKey = 'shelfscan_probe_secret';
const _plainKey = 'shelfscan_probe_plain';
const _secretValue = 'probe-secret-must-not-reach-preferences';
const _plainValue = 'http://probe.invalid:11434';

const _phase = String.fromEnvironment('SHELFSCAN_KEYCHAIN_PHASE');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // A fresh pair per phase, and per assertion inside a phase: an instance that
  // has already answered once could be answering from itself.
  SecretStore secrets() => const SecureSecretStore();
  PrefsStore plain() => const SharedPrefsStore();

  testWidgets('phase "$_phase" against the real stores', (tester) async {
    switch (_phase) {
      case 'write':
        await secrets().write(_secretKey, _secretValue);
        await plain().write(_plainKey, _plainValue);
        // Same process: proves the write was accepted, nothing more.
        expect(await secrets().read(_secretKey), _secretValue);
        expect(await plain().read(_plainKey), _plainValue);

      case 'read':
        // This process has written nothing. Both values therefore crossed a
        // process boundary, which is the whole point of the harness.
        expect(
          await secrets().read(_secretKey),
          _secretValue,
          reason: 'the secret did not survive the restart, or phase "write" '
              'was not run first',
        );
        expect(
          await plain().read(_plainKey),
          _plainValue,
          reason: 'the non-secret did not survive the restart, or phase '
              '"write" was not run first',
        );
        await _expectSecretIsNotInPreferencesFile();

      case 'clear':
        await secrets().write(_secretKey, '');
        await plain().write(_plainKey, '');
        expect(await secrets().read(_secretKey), isNull);
        expect(await plain().read(_plainKey), isNull);

      case 'gone':
        expect(
          await secrets().read(_secretKey),
          isNull,
          reason: 'clearing removed the secret in-process but it came back '
              'after a restart: the credential store still holds it',
        );
        expect(await plain().read(_plainKey), isNull);

      default:
        fail(
          'no phase. Pass one of write | read | clear | gone as '
          '--dart-define=SHELFSCAN_KEYCHAIN_PHASE=... and run them in that '
          'order; see the comment at the top of this file.',
        );
    }
  });
}

/// The split is the point of `settings_store.dart`, and this is the one
/// assertion that can only be made against a real preferences file: the
/// secret's value must not appear in it, and the non-secret's must.
///
/// The candidate paths are searched rather than hard-coded because the
/// location follows the Runner's identity and the plugin's own version. A
/// miss fails loudly and names everything it looked at -- a skipped
/// assertion here would be the silent failure PROJECT.md rejects.
Future<void> _expectSecretIsNotInPreferencesFile() async {
  final support = await getApplicationSupportDirectory();
  final candidates = [
    File('${support.path}${Platform.pathSeparator}shared_preferences.json'),
    File('${support.parent.path}${Platform.pathSeparator}'
        'shared_preferences.json'),
  ];
  final found = candidates.where((f) => f.existsSync()).toList();

  expect(
    found,
    isNotEmpty,
    reason: 'no preferences file at any of: '
        '${candidates.map((f) => f.path).join(', ')}. Either the plugin no '
        'longer writes one (it may have moved to the registry) or the '
        'identity changed; find it and add the path here rather than '
        'dropping the assertion.',
  );

  final contents = found.first.readAsStringSync();
  expect(
    contents.contains(_secretValue),
    isFalse,
    reason: 'the secret reached the plain preferences file at '
        '${found.first.path} -- the split in settings_store.dart is broken',
  );
  expect(
    contents.contains(_plainValue),
    isTrue,
    reason: 'the non-secret is not in ${found.first.path}, so the negative '
        'assertion above proves nothing: this file is not the one being '
        'written',
  );
}
