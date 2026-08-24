/// Local on a phone: the address the app cannot guess, and the cleartext
/// decision it deliberately did not make (T-0361).
///
/// The measurement this must not be read as overturning is stated once, here
/// and in `provider_config.dart`: on-device models are too weak for spine OCR,
/// which is a fact about a model running ON the phone. Nothing below runs one
/// there. What it pins is the other reading of "local" -- the desktop's model,
/// reached over the network -- and the three things that follow from the
/// server being somewhere else.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelfscan_app/provider_config.dart';
import 'package:shelfscan_app/screens/settings_screen.dart';
import 'package:shelfscan_app/settings_store.dart';
import 'package:shelfscan_core/shelfscan_core.dart';

import 'settings_store_test.dart' show RecordingStore;

/// Invented, and it has to be: a real address off this network would be a
/// fact about the owner's house, which is the one thing no fixture here may
/// carry. Nothing resolves it and nothing tries -- the policy answers from the
/// string alone.
const _aServerOnTheNetwork = 'http://a-desktop.invalid:11434';

void main() {
  tearDown(
      () => ProviderPolicy.debugLocalServerIsThisMachineOverride = null);

  group('the phone can choose local, and is not defaulted into it', () {
    test('it is offered, and cloud is still what a first launch gets', () {
      ProviderPolicy.debugLocalServerIsThisMachineOverride = false;

      expect(ProviderPolicy.available, contains(VisionBackend.local));
      expect(ProviderPolicy.defaultBackend, VisionBackend.cloud);
      expect(ProviderSettings().backend, VisionBackend.cloud);
    });

    test('a supplied address is what the provider is built with', () {
      ProviderPolicy.debugLocalServerIsThisMachineOverride = false;
      final settings = ProviderSettings(
          backend: VisionBackend.local, ollamaUrl: _aServerOnTheNetwork);

      expect(ProviderPolicy.check(settings).canRun, isTrue);
      final provider = ProviderPolicy.build(settings) as OllamaVisionProvider;
      expect(provider.baseUrl, _aServerOnTheNetwork);
    });
  });

  group('the address cannot default to something that cannot work', () {
    test('blank stays blank on a phone and resolves on a desktop', () {
      ProviderPolicy.debugLocalServerIsThisMachineOverride = false;
      expect(ProviderSettings().ollamaUrl, isEmpty);
      expect(ProviderSettings(ollamaUrl: '').ollamaUrl, isEmpty);

      // T-0082 unchanged where there is something to resolve to.
      ProviderPolicy.debugLocalServerIsThisMachineOverride = true;
      expect(ProviderSettings().ollamaUrl, defaultOllamaUrl);
      expect(ProviderSettings(ollamaUrl: '').ollamaUrl, defaultOllamaUrl);
    });

    test('a blank one blocks at the tap, naming what is missing', () {
      ProviderPolicy.debugLocalServerIsThisMachineOverride = false;
      final blocker = ProviderPolicy
          .check(ProviderSettings(backend: VisionBackend.local))
          .blocker;

      expect(blocker, isNotNull);
      expect(blocker, contains('Settings'));
      // The failure this replaces is a timeout per photo, minutes in. So the
      // sentence has to say the device is not the server, or the reader
      // supplies the only address they know: this one.
      expect(blocker, contains('network'));
    });

    test('every form of "this device" is refused, and only on a phone', () {
      const thisDevice = [
        'http://localhost:11434',
        'http://127.0.0.1:11434',
        'http://127.1.2.3:11434',
        'http://[::1]:11434',
        'http://0.0.0.0:11434',
        'http://LOCALHOST:11434',
      ];

      ProviderPolicy.debugLocalServerIsThisMachineOverride = false;
      for (final url in thisDevice) {
        final settings = ProviderSettings(
            backend: VisionBackend.local, ollamaUrl: url);
        expect(ProviderPolicy.check(settings).blocker, contains('this device'),
            reason: url);
        expect(() => ProviderPolicy.build(settings), throwsStateError,
            reason: url);
      }

      // The same strings are the ordinary case on a desktop, and one of them
      // is the built-in default: a check that fired there would break the
      // platform this app already worked on.
      ProviderPolicy.debugLocalServerIsThisMachineOverride = true;
      for (final url in thisDevice) {
        expect(
            ProviderPolicy.check(ProviderSettings(
                    backend: VisionBackend.local, ollamaUrl: url))
                .blocker,
            isNull,
            reason: url);
      }
    });

    test('an address elsewhere is not judged, on either platform', () {
      // Whether it answers is a network question and the policy may not ask
      // one. It is a hostname to this code and nothing more.
      for (final onThisMachine in [true, false]) {
        ProviderPolicy.debugLocalServerIsThisMachineOverride = onThisMachine;
        expect(
            ProviderPolicy.check(ProviderSettings(
                    backend: VisionBackend.local,
                    ollamaUrl: _aServerOnTheNetwork))
                .blocker,
            isNull,
            reason: 'onThisMachine=$onThisMachine');
      }
    });

    testWidgets('the field offers a shape to fill in, never an address',
        (tester) async {
      ProviderPolicy.debugLocalServerIsThisMachineOverride = false;
      await tester.pumpWidget(MaterialApp(
        home: SettingsScreen(
          settings: ProviderSettings(),
          store: SettingsStore(
              secrets: RecordingStore(), prefs: RecordingStore()),
        ),
      ));

      final field = tester.widget<TextField>(
          find.byKey(const Key('settings-ollama-url')));
      expect(field.controller!.text, isEmpty,
          reason: 'a pre-filled address here is one nobody chose');
      // T-0082 made hintText mean "clear this and you get that". Where
      // clearing gets you nothing, the hint may not read as a value.
      expect(field.decoration!.hintText, isNot(defaultOllamaUrl));
      expect(field.decoration!.hintText, contains('ADDRESS'));
    });
  });

  group('local stops meaning "nothing leaves" where local is elsewhere', () {
    test('it warns, and the warning says where they go and how', () {
      ProviderPolicy.debugLocalServerIsThisMachineOverride = false;
      final check =
          ProviderPolicy.check(ProviderSettings(backend: VisionBackend.local));

      expect(check.warning, lanPrivacyWarning);
      expect(check.advice, isNotNull);
      // The whole of what T-0069 corrected in the README: local was never a
      // synonym for offline, and on this platform it is visibly not one.
      expect(check.warning, contains('leave this device'));
      expect(check.warning, contains('plain HTTP'));
      expect(check.warning, isNot(contains('do not leave')));
    });

    test('and says nothing at all where nothing leaves', () {
      ProviderPolicy.debugLocalServerIsThisMachineOverride = true;
      final check =
          ProviderPolicy.check(ProviderSettings(backend: VisionBackend.local));

      expect(check.warning, isNull);
      expect(check.advice, isNull);
    });
  });

  group('the cleartext decision stays made', () {
    // A source assertion, in the shape backend_order_test.dart already uses
    // for the scan screen: the decision is that this manifest declares no
    // cleartext permission, and the cheapest way for it to be undone is
    // somebody adding one because a search result said to. The reasoning is
    // in the file; this fails if either the reasoning or the decision goes.
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

    test('the manifest was found and is the one that matters', () {
      // A release build takes src/main; a green from an empty read would say
      // nothing, and src/debug is a different file with different contents.
      expect(manifest, contains('<manifest'));
      expect(manifest, contains('android.permission.INTERNET'),
          reason: 'the release-build permission trap, doc/android-build.md');
    });

    test('no cleartext permission is declared, at either grain', () {
      // The comment below names both attributes at length, so the markup has
      // to be judged without it -- and a strip that ate everything would make
      // the two assertions below pass on nothing, which is the shape
      // doc/conventions.md 4a says to control in both directions.
      final declarations =
          manifest.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
      expect(declarations, contains('<application'));
      expect(declarations, isNot(contains('WHY IT LOOKS NEEDED')));

      expect(declarations, isNot(contains('usesCleartextTraffic')));
      expect(declarations, isNot(contains('networkSecurityConfig')));
    });

    test('and the reason is written where the flag would go', () {
      // Not decoration: the argument is why an auditor should read the
      // absence as a decision rather than as an oversight, and why adding
      // the flag would buy nothing here while costing something elsewhere.
      expect(manifest, contains('deliberately no android:networkSecurityConfig'));
      expect(manifest, contains('no policy will be enforced'));
    });
  });
}
