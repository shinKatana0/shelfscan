/// The release build refuses the debug key (T-0398).
///
/// A source assertion, in the shape `android_local_test.dart` already uses for
/// the manifest: the decision is that `buildTypes.release` has no fallback to
/// the debug signing config, and the cheapest way for it to come back is
/// somebody restoring the `flutter create` scaffold to make a build go
/// through. That is exactly the edit nobody would file a task for, and
/// noticing it here costs no Android SDK, no keystore and no build.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// What `keytool -printcert` answers for an apk signed with the debug key.
const _debugKeyOwner = 'CN=Android Debug';

void main() {
  final gradle = File('android/app/build.gradle.kts').readAsStringSync();
  // The comments below name the debug config at length in order to say why it
  // is absent, so the code has to be judged without them -- and a strip that
  // ate everything would make the assertions pass on nothing, which is the
  // shape doc/conventions.md 4a says to control in both directions.
  final code = gradle.replaceAll(RegExp(r'//.*'), '');

  group('the release build refuses the debug key', () {
    test('the file was found, and the comment strip left the code', () {
      expect(gradle, contains('buildTypes'));
      expect(gradle, contains('never getByName'));
      expect(code, contains('buildTypes'));
      expect(code, contains('signingConfigs'));
      expect(code, isNot(contains('never getByName')));
    });

    test('no build type signs with the debug key', () {
      expect(code, isNot(contains('getByName("debug")')));
      expect(code, isNot(contains(_debugKeyOwner)));
    });

    test('an absent key.properties fails the build instead', () {
      expect(code, contains('key.properties'));
      expect(code, contains('GradleException'));
      // The refusal has to be reachable from a release task and from no
      // other, which is what these two halves are: the graph is inspected,
      // and only release tasks throw.
      expect(code, contains('whenReady'));
      expect(code, contains('Release'));
    });

    test('and says what to do about it', () {
      expect(code, contains('key.properties.example'));
      expect(code, contains('keytool'));
      expect(code, contains("JDK's bin directory"));
      // The half a contributor without a keystore depends on.
      expect(code, contains('Debug and profile builds need none of this'));
    });
  });

  group('the example file carries names and no credential', () {
    final example = File('android/key.properties.example');

    test('it is committed', () {
      expect(example.existsSync(), isTrue);
    });

    test('it names every key the build requires', () {
      final text = example.readAsStringSync();
      for (final key in const [
        'storeFile',
        'storePassword',
        'keyAlias',
        'keyPassword',
      ]) {
        expect(text, contains('$key='), reason: 'the build reads $key');
        expect(code, contains(key), reason: '$key is not read by the build');
      }
    });

    test('and every value in it is empty', () {
      final assignments = example
          .readAsLinesSync()
          .where((line) => !line.trimLeft().startsWith('#'))
          .where((line) => line.contains('='))
          .toList();
      expect(assignments, isNotEmpty);
      for (final line in assignments) {
        final value = line.substring(line.indexOf('=') + 1).trim();
        expect(value, isEmpty,
            reason: 'a plausible example value is what gets copied');
      }
    });
  });

  group('the secrets stay ignored in both places', () {
    // The "verify, do not redo" requirement: nothing here adds an ignore
    // rule, it fails if one of the two existing sets goes away.
    for (final ignore in const {
      'the repository root': '../.gitignore',
      'app/android': 'android/.gitignore',
    }.entries) {
      test('${ignore.key} covers the keystore and its passwords', () {
        final text = File(ignore.value).readAsStringSync();
        expect(text, contains('key.properties'));
        expect(text, contains('.jks'));
        expect(text, contains('.keystore'));
      });
    }
  });
}
