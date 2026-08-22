/// What the Local/Cloud switch says at the moment it is tapped (T-0040).
///
/// The bug this pins: selecting Cloud with no key stored changed nothing on
/// screen. The user learned the choice was unusable only after picking
/// photos and pressing Scan, and was never told at all that an external
/// backend uploads pictures of their home -- that warning existed only on
/// the settings screen, for one of the two external backends.
///
/// Everything asserted here is decided from a [ProviderSettings] in memory:
/// no provider is constructed and nothing is dialled.
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelfscan_app/provider_config.dart';
import 'package:shelfscan_app/screens/scan_screen.dart';
import 'package:shelfscan_app/settings_store.dart';
import 'package:shelfscan_core/shelfscan_core.dart';

import 'scan_wiring_test.dart' show FakeFilePicker;
import 'settings_store_test.dart' show RecordingStore;

SettingsStore _store() =>
    SettingsStore(secrets: RecordingStore(), prefs: RecordingStore());

Future<void> _pump(WidgetTester tester, ProviderSettings settings) =>
    tester.pumpWidget(MaterialApp(
      home: ScanScreen(settings: settings, store: _store()),
    ));

/// Taps a segment of the app-bar switch. The segments are icon-only, so the
/// icon is the handle.
Future<void> _select(WidgetTester tester, IconData icon) async {
  await tester.tap(find.byIcon(icon));
  // A single pump, not pumpAndSettle: the answer must already be on screen
  // after one frame, which it cannot be if anything was awaited.
  await tester.pump();
}

String _adviceText(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('backend-advice'))).data!;

void main() {
  tearDown(() => ProviderPolicy.debugLocalAllowedOverride = null);

  group('what a tap can know', () {
    test('local needs nothing and costs nothing', () {
      final check = ProviderPolicy.check(
          ProviderSettings(backend: VisionBackend.local));

      expect(check.canRun, isTrue);
      expect(check.warning, isNull);
      expect(check.hasNotice, isFalse);
    });

    test('cloud with no key is knowable as unusable', () {
      final check = ProviderPolicy.check(
          ProviderSettings(backend: VisionBackend.cloud));

      expect(check.canRun, isFalse);
      expect(check.blocker, contains('Anthropic API key'));
      expect(check.blocker, contains('Settings'));
    });

    test('cloud with a key can run and still leaves the machine', () {
      final check = ProviderPolicy.check(ProviderSettings(
          backend: VisionBackend.cloud, anthropicApiKey: 'sk-ant-x'));

      expect(check.canRun, isTrue);
      expect(check.warning, cloudPrivacyWarning);
    });

    test('every external backend warns; the local one never does', () {
      for (final backend in ProviderPolicy.available) {
        final check =
            ProviderPolicy.check(ProviderSettings(backend: backend));
        expect(check.warning, backend == VisionBackend.local ? isNull : isNotNull,
            reason: '${backend.label} warning');
      }
      // Only the endpoint branch carries the free-tier sentence: it is not
      // true of a paid Anthropic account.
      expect(endpointPrivacyWarning, contains('training on what'));
      expect(cloudPrivacyWarning, isNot(contains('training')));
    });

    test('a stated risk always comes with an action (T-0070)', () {
      for (final localAllowed in [true, false]) {
        ProviderPolicy.debugLocalAllowedOverride = localAllowed;
        for (final backend in VisionBackend.values) {
          final check =
              ProviderPolicy.check(ProviderSettings(backend: backend));
          expect(check.advice == null, check.warning == null,
              reason: '${backend.label}, localAllowed=$localAllowed: '
                  'warning=${check.warning} advice=${check.advice}');
        }
      }
    });

    test('no advice names a backend this platform does not offer (T-0070)',
        () {
      // "or use Local" was true where it was written and false on the
      // platform this app exists for. Asked of the policy rather than of a
      // remembered platform name, so a backend that becomes unavailable
      // later is caught the same way.
      for (final localAllowed in [true, false]) {
        ProviderPolicy.debugLocalAllowedOverride = localAllowed;
        final absent = VisionBackend.values
            .where((b) => !ProviderPolicy.available.contains(b));
        for (final backend in ProviderPolicy.available) {
          final advice =
              ProviderPolicy.check(ProviderSettings(backend: backend)).advice;
          for (final gone in absent) {
            expect(advice, isNot(contains(gone.label)),
                reason: '${backend.label} advice offers ${gone.label}');
          }
        }
      }
    });

    test('the advice is platform-dependent where the risk is not (T-0070)',
        () {
      for (final backend in [
        VisionBackend.cloud,
        VisionBackend.openAiCompatible,
      ]) {
        expect(privacyAdvice(backend, localAllowed: true),
            isNot(privacyAdvice(backend, localAllowed: false)));
      }
      for (final localAllowed in [true, false]) {
        expect(privacyAdvice(VisionBackend.local, localAllowed: localAllowed),
            isNull);
      }
      // Cloud-only: the endpoint branch still has somewhere to send the user,
      // the Anthropic branch has nothing but the photo itself.
      expect(
          privacyAdvice(VisionBackend.openAiCompatible, localAllowed: false),
          contains(VisionBackend.cloud.label));
      expect(privacyAdvice(VisionBackend.cloud, localAllowed: false),
          contains('leave out of the scan'));
    });

    test('each missing endpoint field is named at the tap', () {
      final settings =
          ProviderSettings(backend: VisionBackend.openAiCompatible);

      expect(ProviderPolicy.check(settings).blocker, contains('API endpoint'));
      settings.openAiBaseUrl = 'https://api.groq.com/openai/v1';
      expect(ProviderPolicy.check(settings).blocker, contains('model name'));
      settings.openAiModel = 'llama-4-scout';
      expect(ProviderPolicy.check(settings).blocker,
          contains('api.groq.com/openai/v1'));
      settings.openAiApiKey = 'gsk-x';
      expect(ProviderPolicy.check(settings).canRun, isTrue);
    });

    test('the early answer is word-for-word the late failure', () {
      // The guard against the two drifting apart, which is what would make
      // the early one a second, subtly different truth.
      final unusable = [
        ProviderSettings(backend: VisionBackend.cloud),
        ProviderSettings(backend: VisionBackend.openAiCompatible),
        ProviderSettings(
            backend: VisionBackend.openAiCompatible,
            openAiBaseUrl: 'https://openrouter.ai/api/v1'),
        ProviderSettings(
            backend: VisionBackend.openAiCompatible,
            openAiBaseUrl: 'https://openrouter.ai/api/v1',
            openAiModel: 'qwen/qwen2.5-vl-72b-instruct'),
      ];
      for (final settings in unusable) {
        expect(
          () => ProviderPolicy.build(settings),
          throwsA(isA<StateError>().having((e) => e.message, 'message',
              ProviderPolicy.check(settings).blocker)),
        );
      }
    });

    test('a stored Anthropic key gives a local run nothing to say and '
        'nowhere to go (T-0061)', () {
      final settings = ProviderSettings(
          backend: VisionBackend.local, anthropicApiKey: 'sk-ant-x');

      expect(ProviderPolicy.check(settings).hasNotice, isFalse);
      expect(ProviderPolicy.build(settings), isA<OllamaVisionProvider>());
    });

    test('a cloud-only platform is answered for the backend it will really '
        'use', () {
      ProviderPolicy.debugLocalAllowedOverride = false;
      // Stored settings say local -- e.g. preferences restored from a
      // desktop backup. The scan would run cloud, so the tap says cloud.
      final check = ProviderPolicy.check(
          ProviderSettings(backend: VisionBackend.local));

      expect(check.backend, VisionBackend.cloud);
      expect(check.warning, cloudPrivacyWarning);
      expect(check.blocker, contains('Anthropic API key'));
    });
  });

  group('the first frame', () {
    // T-0076: the notice was computed only on a tap and on the way back from
    // Settings, so the two users who never do either -- every Android user,
    // where cloud is the default, and any desktop user whose cloud choice is
    // already stored -- were told nothing at all.
    setUp(() => FilePicker.platform = FakeFilePicker());

    testWidgets('a stored cloud backend says so before anything is touched',
        (tester) async {
      await _pump(
          tester,
          ProviderSettings(
              backend: VisionBackend.cloud, anthropicApiKey: 'sk-ant-x'));

      // No pumpAndSettle and no tap: this is the first frame or it is nothing.
      expect(find.text(cloudPrivacyWarning), findsOneWidget);
      expect(_adviceText(tester),
          privacyAdvice(VisionBackend.cloud, localAllowed: true));
    });

    testWidgets('a stored endpoint backend says the endpoint sentence',
        (tester) async {
      await _pump(
          tester,
          ProviderSettings(
            backend: VisionBackend.openAiCompatible,
            openAiBaseUrl: 'https://openrouter.ai/api/v1',
            openAiModel: 'qwen/qwen2.5-vl-72b-instruct',
            openAiApiKey: 'sk-or-x',
          ));

      expect(find.text(endpointPrivacyWarning), findsOneWidget);
      expect(_adviceText(tester), contains('data policy'));
    });

    testWidgets('local shows nothing at launch, as it shows nothing on a tap',
        (tester) async {
      await _pump(tester, ProviderSettings(backend: VisionBackend.local));

      expect(find.byKey(const Key('backend-warning')), findsNothing);
      expect(find.byKey(const Key('backend-advice')), findsNothing);
      expect(find.byKey(const Key('status-open-settings')), findsNothing);
    });

    testWidgets('the cloud-only platform launches on cloud and is warned',
        (tester) async {
      ProviderPolicy.debugLocalAllowedOverride = false;
      // Nothing stored at all: the constructor takes the platform default,
      // which on Android is cloud. This is the launch the task is about.
      final settings = ProviderSettings(anthropicApiKey: 'sk-ant-x');
      expect(settings.backend, VisionBackend.cloud);

      await _pump(tester, settings);

      expect(find.text(cloudPrivacyWarning), findsOneWidget);
      expect(_adviceText(tester), contains('leave out of the scan'));
      expect(_adviceText(tester), isNot(contains(VisionBackend.local.label)));
    });

    testWidgets('a stored local backend on a cloud-only platform is answered '
        'for the backend it will really use', (tester) async {
      // Preferences restored from a desktop backup onto a phone: the scan
      // would run cloud, so the first frame says cloud.
      ProviderPolicy.debugLocalAllowedOverride = false;
      await _pump(
          tester,
          ProviderSettings(
              backend: VisionBackend.local, anthropicApiKey: 'sk-ant-x'));

      expect(find.text(cloudPrivacyWarning), findsOneWidget);
    });

    testWidgets('cloud without a key launches with the warning and not the '
        'blocker', (tester) async {
      // The two are different things on different affordances (T-0040), and
      // only one of them is a report about an action. The blocker still
      // arrives -- at the Scan the user chose to press, on a tap of the
      // switch, and on the way back from Settings (T-0079).
      await _pump(tester, ProviderSettings(backend: VisionBackend.cloud));

      expect(find.text(cloudPrivacyWarning), findsOneWidget);
      expect(find.textContaining('needs an Anthropic API key'), findsNothing);
      expect(find.byKey(const Key('status-open-settings')), findsNothing);

      await tester.tap(find.text('Add photos'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Scan'));
      await tester.pumpAndSettle();

      expect(find.textContaining('needs an Anthropic API key'), findsOneWidget);
      expect(find.byKey(const Key('status-open-settings')), findsOneWidget);
      expect(find.text(cloudPrivacyWarning), findsOneWidget);
    });

    testWidgets('the launch notice is cleared by a tap back to local',
        (tester) async {
      await _pump(tester, ProviderSettings(backend: VisionBackend.cloud));
      expect(find.byKey(const Key('backend-warning')), findsOneWidget);

      await _select(tester, Icons.computer);

      expect(find.byKey(const Key('backend-warning')), findsNothing);
    });
  });

  group('the switch on the scan screen', () {
    setUp(() => FilePicker.platform = FakeFilePicker());

    testWidgets('cloud without a key says so at once and offers the way out',
        (tester) async {
      await _pump(tester, ProviderSettings(backend: VisionBackend.local));
      expect(find.byKey(const Key('backend-warning')), findsNothing);

      await _select(tester, Icons.cloud);

      expect(find.textContaining('needs an Anthropic API key'), findsOneWidget);
      expect(find.text(cloudPrivacyWarning), findsOneWidget);

      await tester.tap(find.byKey(const Key('status-open-settings')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('settings-anthropic-key')), findsOneWidget);
    });

    testWidgets('cloud with a key is not blocked, but still says the photos '
        'leave', (tester) async {
      await _pump(
          tester,
          ProviderSettings(
              backend: VisionBackend.local, anthropicApiKey: 'sk-ant-x'));

      await _select(tester, Icons.cloud);

      expect(find.text(cloudPrivacyWarning), findsOneWidget);
      expect(find.textContaining('needs an Anthropic API key'), findsNothing);
      expect(find.byKey(const Key('status-open-settings')), findsNothing);
    });

    testWidgets('the risk arrives with the action, on a platform that has '
        'one (T-0070)', (tester) async {
      ProviderPolicy.debugLocalAllowedOverride = true;
      await _pump(
          tester,
          ProviderSettings(
              backend: VisionBackend.local, anthropicApiKey: 'sk-ant-x'));

      await _select(tester, Icons.cloud);
      expect(_adviceText(tester),
          privacyAdvice(VisionBackend.cloud, localAllowed: true));
      expect(_adviceText(tester), contains(VisionBackend.local.label));

      await _select(tester, Icons.dns);
      expect(_adviceText(tester), contains('data policy'));

      await _select(tester, Icons.computer);
      expect(find.byKey(const Key('backend-advice')), findsNothing);
    });

    testWidgets('a cloud-only platform is offered no local escape (T-0070)',
        (tester) async {
      ProviderPolicy.debugLocalAllowedOverride = false;
      await _pump(tester, ProviderSettings(anthropicApiKey: 'sk-ant-x'));

      // The app-bar switch still exists here: cloud-only is not one backend
      // but two, Anthropic and a named endpoint.
      await _select(tester, Icons.dns);
      expect(_adviceText(tester), isNot(contains(VisionBackend.local.label)));
      expect(_adviceText(tester), contains(VisionBackend.cloud.label));

      await _select(tester, Icons.cloud);
      expect(_adviceText(tester), isNot(contains(VisionBackend.local.label)));
      expect(_adviceText(tester), contains('leave out of the scan'));
    });

    testWidgets('the local default is nagged at about nothing', (tester) async {
      await _pump(tester, ProviderSettings(backend: VisionBackend.cloud));
      // Arrive with something on screen, so this asserts a clear rather than
      // an absence that was never filled.
      await _select(tester, Icons.dns);
      expect(find.byKey(const Key('backend-warning')), findsOneWidget);

      await _select(tester, Icons.computer);

      expect(find.byKey(const Key('backend-warning')), findsNothing);
      expect(find.byKey(const Key('status-open-settings')), findsNothing);
      expect(find.textContaining('needs'), findsNothing);
    });

    testWidgets('the choice is still persisted, and the switch still shows it',
        (tester) async {
      final settings = ProviderSettings(backend: VisionBackend.local);
      final prefs = RecordingStore();
      await tester.pumpWidget(MaterialApp(
        home: ScanScreen(
          settings: settings,
          store: SettingsStore(secrets: RecordingStore(), prefs: prefs),
        ),
      ));

      await _select(tester, Icons.cloud);
      await tester.pumpAndSettle();

      expect(settings.backend, VisionBackend.cloud);
      expect(prefs.values[SettingsStore.keyBackend], 'cloud');
    });

    testWidgets('the notice is still there after a trip through Settings',
        (tester) async {
      await _pump(
          tester,
          ProviderSettings(
              backend: VisionBackend.cloud, anthropicApiKey: 'sk-ant-x'));

      await tester.tap(find.byKey(const Key('open-settings')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('settings-save')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings-save')));
      await tester.pumpAndSettle();

      expect(find.text(cloudPrivacyWarning), findsOneWidget);
      expect(_adviceText(tester),
          privacyAdvice(VisionBackend.cloud, localAllowed: true));
    });

    testWidgets('coming back from Settings without fixing it says so again '
        '(T-0079)', (tester) async {
      // The trip the message itself asked for. Before this the blocker was
      // blanked on the way back, so the user who was sent to add a key and
      // did not add one came home to no trace of the reason they went.
      await _pump(tester, ProviderSettings(backend: VisionBackend.local));
      await _select(tester, Icons.cloud);
      expect(find.byKey(const Key('status-open-settings')), findsOneWidget);

      await tester.tap(find.byKey(const Key('status-open-settings')));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.textContaining('needs an Anthropic API key'), findsOneWidget);
      expect(find.byKey(const Key('status-open-settings')), findsOneWidget);
      expect(find.text(cloudPrivacyWarning), findsOneWidget);
    });

    testWidgets('coming back having added the key clears the blocker '
        '(T-0079)', (tester) async {
      final settings = ProviderSettings(backend: VisionBackend.local);
      await _pump(tester, settings);
      await _select(tester, Icons.cloud);
      expect(find.byKey(const Key('status-open-settings')), findsOneWidget);

      await tester.tap(find.byKey(const Key('status-open-settings')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const Key('settings-anthropic-key')), 'sk-ant-typed');
      // The field just typed into scrolls the view back to itself unless
      // focus is dropped first.
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('settings-save')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings-save')));
      await tester.pumpAndSettle();

      expect(settings.anthropicApiKey, 'sk-ant-typed');
      expect(find.textContaining('needs an Anthropic API key'), findsNothing);
      expect(find.byKey(const Key('status-open-settings')), findsNothing);
      // Fixed is not the same as harmless: the upload is still true.
      expect(find.text(cloudPrivacyWarning), findsOneWidget);
    });

    testWidgets('what comes back is the condition now, not the message from '
        'before the trip (T-0079)', (tester) async {
      // The discriminating case between "recompute the blocker" and "keep
      // whatever was in the status line": a trip that fixes half of what was
      // missing comes back naming the other half -- which neither keeping the
      // old sentence nor clearing it on return produces.
      //
      // It used to make the difference by switching the backend inside
      // Settings; that screen chooses no backend since T-0115, so the
      // condition that changes over the trip is the endpoint's own.
      final settings =
          ProviderSettings(backend: VisionBackend.local, openAiModel: '');
      await _pump(tester, settings);
      await _select(tester, Icons.dns);
      expect(find.textContaining('needs the API endpoint'), findsOneWidget);

      await tester.tap(find.byKey(const Key('status-open-settings')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('settings-openai-url')),
          'https://api.groq.com/openai/v1');
      // The field just typed into scrolls the view back to itself unless
      // focus is dropped first.
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('settings-save')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings-save')));
      await tester.pumpAndSettle();

      expect(settings.openAiBaseUrl, 'https://api.groq.com/openai/v1');
      expect(find.textContaining('needs the API endpoint'), findsNothing);
      expect(find.textContaining('needs a model name'), findsOneWidget);
      expect(find.byKey(const Key('status-open-settings')), findsOneWidget);
    });

    testWidgets('ignoring the early answer still fails the scan the same way',
        (tester) async {
      // The late failure is not replaced by the early one; it is still there
      // for anyone who taps Scan anyway.
      await _pump(tester, ProviderSettings(backend: VisionBackend.local));
      await _select(tester, Icons.cloud);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add photos'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Scan'));
      await tester.pumpAndSettle();

      expect(find.textContaining('needs an Anthropic API key'), findsOneWidget);
      expect(find.byKey(const Key('status-open-settings')), findsOneWidget);
    });
  });
}
