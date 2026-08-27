/// The version the tree declares, asserted rather than remembered (T-0404).
///
/// Decision 0014's release order -- both pubspecs, then `CHANGELOG.md`, then
/// the tag -- was a rule enforced by remembering it, and two of its three
/// parts are assertable. This file asserts them.
///
/// **The build number is the load-bearing half, because its absence is
/// silent.** With no `+N` behind the version in `app/pubspec.yaml` Flutter
/// substitutes `1`, warns nobody, and the apk goes out declaring
/// `versionCode='1'` -- which is how every Android package this project has
/// produced came to declare the same version as every other, none of them an
/// upgrade of any other as far as Android is concerned. Nothing else in the
/// tree would have said so.
///
/// The suite runs in `app/`, so the core pubspec is reached by a relative
/// path, the way `settings_licenses_test.dart` reaches `../LICENSE`.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelfscan_app/app_version.dart';
import 'package:shelfscan_app/provider_config.dart';
import 'package:shelfscan_app/screens/settings_screen.dart';
import 'package:shelfscan_app/settings_store.dart';

import 'settings_store_test.dart' show RecordingStore;

/// `MAJOR.MINOR.PATCH+BUILD`, with `+BUILD` required rather than optional.
final _version = RegExp(r'^(\d+)\.(\d+)\.(\d+)\+(\d+)$');

/// The top-level `version:` key. Anchored per line so it cannot match a
/// dependency constraint indented under `dependencies:`.
final _versionKey = RegExp(r'^version:[ \t]*(\S+)[ \t]*$', multiLine: true);

String _pubspecVersion(String path) {
  final file = File(path);
  expect(file.existsSync(), isTrue, reason: '$path is not where it was');
  final match = _versionKey.firstMatch(file.readAsStringSync());
  expect(match, isNotNull, reason: '$path declares no top-level version');
  return match![1]!;
}

Future<void> _pumpSettings(WidgetTester tester) =>
    tester.pumpWidget(MaterialApp(
      home: SettingsScreen(
        settings: ProviderSettings(),
        store: SettingsStore(
          secrets: RecordingStore(),
          prefs: RecordingStore(),
        ),
      ),
    ));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const appPubspec = 'pubspec.yaml';
  const corePubspec = '../packages/shelfscan_core/pubspec.yaml';

  group('the pattern this file judges versions by', () {
    // Controls on the matcher itself, kept because a pattern that cannot
    // fail is a pattern that proves nothing about what it passed. The first
    // two are the whole point of the file: a version with no build number
    // must NOT match.
    test('a version with no build number is rejected', () {
      expect(_version.hasMatch('0.2.0'), isFalse);
      expect(_version.hasMatch('0.2.0+'), isFalse);
    });

    test('a build number that is not an integer is rejected', () {
      expect(_version.hasMatch('0.2.0+2026-08-25'), isFalse);
      expect(_version.hasMatch('0.2.0+beta'), isFalse);
    });

    test('a full version is accepted', () {
      expect(_version.hasMatch('0.2.0+2'), isTrue);
      expect(_version.hasMatch('10.20.30+400'), isTrue);
    });

    test('the key pattern reads the top-level version, not a constraint', () {
      const pubspec = 'name: x\n'
          'version: 1.2.3+4\n'
          'dependencies:\n'
          '  version: ^9.9.9\n';
      expect(_versionKey.firstMatch(pubspec)![1], '1.2.3+4');
    });
  });

  group('the two pubspecs', () {
    test('both carry a build number', () {
      for (final path in const [appPubspec, corePubspec]) {
        expect(_version.hasMatch(_pubspecVersion(path)), isTrue,
            reason: '$path must read MAJOR.MINOR.PATCH+BUILD. Without the '
                '+BUILD half Flutter substitutes 1 and says nothing, and '
                'the apk declares versionCode=1 like every one before it.');
      }
    });

    test('both carry the same version', () {
      expect(_pubspecVersion(corePubspec), _pubspecVersion(appPubspec),
          reason: 'decision 0014: the two move in lockstep, so that a bug '
              'report naming a version is unambiguous about which half it '
              'came from');
    });
  });

  group('the version the app displays', () {
    test('appVersion is the app pubspec version', () {
      expect(appVersion, _pubspecVersion(appPubspec),
          reason: 'app_version.dart is a second copy of the pubspec version '
              'and this is the check that makes that acceptable');
    });

    testWidgets('the licence page shows it', (tester) async {
      await _pumpSettings(tester);

      final entry = find.byKey(const Key('settings-licenses'));
      // Same guards settings_licenses_test.dart documents: About is last on
      // a form taller than the test viewport.
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.ensureVisible(entry);
      await tester.pumpAndSettle();
      await tester.tap(entry);
      await tester.pumpAndSettle();

      expect(find.byType(LicensePage), findsOneWidget);
      expect(find.text(appVersion), findsOneWidget,
          reason: 'these packages are hand-installed and nothing else in the '
              'app says which one this is');
    });
  });
}
