/// `android.newDsl=false` is pinned to the toolchain it was measured against
/// (T-0407).
///
/// T-0399 measured the block: with `android.newDsl=true` the Flutter Gradle
/// Plugin fails to apply at all, because it casts the project's android
/// extension to `AbstractAppExtension` and the new DSL hands it an
/// `ApplicationExtension`. Nothing in `app/android/` is at fault and no edit
/// here moves it, so the flag stays false and the account lives in
/// `doc/android-build.md`, "Built-in Kotlin is taken; the new DSL is blocked
/// upstream".
///
/// What that left standing was a rule enforced by remembering it -- *retry on
/// any Flutter upgrade* -- which nothing fires and nobody watches. This file
/// is the trigger. **The property is not "the flag is false", which is true
/// and useless.** It is: the flag is false AND the toolchain is still the one
/// under which false was the right answer.
///
/// **Flutter's version is the pin, and the AGP major is the second pin.** The
/// cast is Flutter-side and only Flutter can fix it -- AGP 9.1 handing over an
/// `ApplicationExtension` is the new DSL working as designed -- so an AGP
/// point release cannot have moved this and must not turn the file red. The
/// AGP *major* is pinned for a different event: AGP 10 removes the flag
/// outright, and then the line in `gradle.properties` is no longer a choice.
/// Kotlin's version is not pinned at all; it belongs to `builtInKotlin`, which
/// T-0399 settled, and the two flags were measured independent.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _properties = 'android/gradle.properties';
const _settings = 'android/settings.gradle.kts';

/// The framework version under which `false` was measured to be the only
/// value that builds, major and minor only: Flutter's newDsl support will
/// arrive in a release, never in a hotfix, and 3.47.x going red would be red
/// for the wrong reason.
const _measuredFlutter = '3.47';

/// AGP 9 is the last major that offers the flag at all.
const _measuredAgpMajor = '9';

const _retry = 'Retry the flag now -- one line plus one build:\n'
    '  1. set android.newDsl=true in app/$_properties\n'
    '  2. cd app && flutter build apk --debug\n'
    'If the build no longer dies applying '
    'dev.flutter.flutter-gradle-plugin, keep the flag true and delete this '
    'pin; the deprecated Project.android accessor and the newDsl option '
    'warning go with it. If it still dies, put the flag back and move the '
    'pin in this file to the version you are on.\n'
    'Either way re-prove the release-signing refusal (T-0398) afterwards: '
    'it is bound to gradle.taskGraph.whenReady, and a DSL change can move '
    'what `this` is there.\n'
    'flutter build apk --config-only does NOT answer this -- it writes the '
    'build files and runs no Gradle configuration.\n'
    'Account: doc/android-build.md, "Built-in Kotlin is taken; the new DSL '
    'is blocked upstream". Upstream: flutter/flutter#180137.';

/// Anchored per line, so the comment block above the flag -- which says
/// "newDsl stays false" in prose -- cannot satisfy it.
final _flag = RegExp(r'^android\.newDsl[ \t]*=[ \t]*(\S+)[ \t]*$',
    multiLine: true);

final _agp = RegExp(r'id\("com\.android\.application"\)[ \t]+'
    r'version[ \t]+"([^"]+)"');

/// `MAJOR.MINOR` of a Dart-or-Flutter style version, which may carry a
/// prerelease tail (`3.47.0-0.1.pre`).
final _head = RegExp(r'^(\d+)\.(\d+)\.');

String? _headOf(String version) {
  final match = _head.firstMatch(version);
  return match == null ? null : '${match[1]}.${match[2]}';
}

/// The framework version of the SDK actually running this test, read from the
/// SDK rather than from anything the repository declares -- the repository
/// declares no Flutter version, and one that it did would be the remembered
/// rule again rather than a check on it.
///
/// `flutter test` exports `FLUTTER_ROOT`; the walk up from the test binary is
/// the fallback, measured to reach the same root five levels up. Neither
/// carries into a message: the paths are the machine's.
String? _frameworkVersion() {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null) {
    final found = _versionIn(root);
    if (found != null) return found;
  }
  var dir = File(Platform.resolvedExecutable).parent;
  for (var up = 0; up < 8; up++) {
    final found = _versionIn(dir.path);
    if (found != null) return found;
    dir = dir.parent;
  }
  return null;
}

String? _versionIn(String flutterRoot) {
  final file = File('$flutterRoot/bin/cache/flutter.version.json');
  if (!file.existsSync()) return null;
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map) return null;
    final version = decoded['frameworkVersion'];
    return version is String && version.isNotEmpty ? version : null;
  } on Object {
    return null;
  }
}

void main() {
  group('the patterns this file judges by', () {
    // Controls in both directions: a pattern that cannot fail proves nothing
    // about what it passed, and each of these would otherwise pass on the
    // prose beside the thing it reads.
    test('the flag pattern reads a setting, not the comment above it', () {
      const properties = '# newDsl stays false because with it true the\n'
          '# Flutter Gradle Plugin fails to apply.\n'
          'android.newDsl=false\n'
          'android.builtInKotlin=true\n';
      expect(_flag.firstMatch(properties)![1], 'false');
      expect(_flag.hasMatch('#android.newDsl=true\n'), isFalse);
      expect(_flag.hasMatch('  android.newDsl=true\n'), isFalse);
    });

    test('the AGP pattern reads the application plugin and no other', () {
      const settings = 'id("com.android.application") version "9.1.0" '
          'apply false\n'
          'id("org.jetbrains.kotlin.android") version "2.4.0" apply false\n';
      expect(_agp.allMatches(settings).length, 1);
      expect(_agp.firstMatch(settings)![1], '9.1.0');
    });

    test('a version head is major and minor, prerelease tail and all', () {
      expect(_headOf('3.47.0'), '3.47');
      expect(_headOf('3.47.11'), '3.47');
      expect(_headOf('3.50.0-0.1.pre'), '3.50');
      expect(_headOf('10.2.0'), '10.2');
      expect(_headOf('3.47'), isNull);
      expect(_headOf('not a version'), isNull);
    });
  });

  group('the flag the toolchain is pinned for', () {
    test('android.newDsl is declared, and declared false', () {
      final file = File(_properties);
      expect(file.existsSync(), isTrue,
          reason: 'app/$_properties is not where it was');
      final match = _flag.firstMatch(file.readAsStringSync());
      expect(match, isNotNull,
          reason: 'app/$_properties no longer sets android.newDsl at all. '
              'AGP 9 defaults it to true, so an absent line is the value '
              'T-0399 measured to be unbuildable.\n$_retry');
      expect(match![1], 'false',
          reason: 'android.newDsl is no longer false, so either this block '
              'has been taken deliberately -- in which case delete this '
              'file and rewrite the doc section -- or the build is about to '
              'fail applying dev.flutter.flutter-gradle-plugin.\n'
              'Account: doc/android-build.md, "Built-in Kotlin is taken; '
              'the new DSL is blocked upstream".');
    });
  });

  group('the toolchain false was measured against', () {
    test('the running SDK could be read at all', () {
      // A check that cannot see its subject must not read as green --
      // check-bundle-assets.dart exits 2 for the same reason.
      expect(_frameworkVersion(), isNotNull,
          reason: 'neither FLUTTER_ROOT nor the walk up from the test binary '
              'reached bin/cache/flutter.version.json, so nothing here has '
              'checked the toolchain and this file has proved nothing. Run '
              'it under `flutter test` from app/.');
    });

    test('Flutter is still the version the block was measured on', () {
      final running = _frameworkVersion();
      expect(_headOf(running!), _measuredFlutter,
          reason: 'Flutter has moved off $_measuredFlutter.x, and '
              'android.newDsl=false has not been retried on what you are '
              'running now. The cast that blocks it is Flutter-side -- the '
              'Flutter Gradle Plugin casting the android extension to '
              'AbstractAppExtension -- so a Flutter release is exactly the '
              'event that can have fixed it.\n$_retry');
    });

    test('AGP is still a major that offers the flag', () {
      final settings = File(_settings);
      expect(settings.existsSync(), isTrue,
          reason: 'app/$_settings is not where it was');
      final match = _agp.firstMatch(settings.readAsStringSync());
      expect(match, isNotNull,
          reason: 'app/$_settings no longer declares a version for '
              'com.android.application, so nothing here knows which AGP the '
              'flag is being set for.');
      expect(match![1]!.split('.').first, _measuredAgpMajor,
          reason: 'AGP has left major $_measuredAgpMajor, and AGP 10 removes '
              'android.newDsl entirely: the line in app/$_properties stops '
              'being a choice and the build either applies '
              'dev.flutter.flutter-gradle-plugin under the new DSL or does '
              'not. Delete the line and build; if it fails, the blocker is '
              'the same Flutter-side cast and there is no flag left to hide '
              'behind.\n$_retry');
    });
  });
}
