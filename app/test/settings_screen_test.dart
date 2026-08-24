/// Widget tests for the settings screen.
///
/// No keychain and no preferences file are touched: the screen takes a
/// [SettingsStore] and these tests give it in-memory backends.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelfscan_app/main.dart' show appSeedColor;
import 'package:shelfscan_app/provider_config.dart';
import 'package:shelfscan_app/screens/scan_screen.dart';
import 'package:shelfscan_app/screens/settings_screen.dart';
import 'package:shelfscan_app/settings_store.dart';
import 'package:shelfscan_core/shelfscan_core.dart';

import 'settings_store_test.dart' show RecordingStore;

class _Backends {
  final secrets = RecordingStore();
  final prefs = RecordingStore();

  SettingsStore get store => SettingsStore(secrets: secrets, prefs: prefs);
}

Future<void> _pump(
  WidgetTester tester,
  ProviderSettings settings,
  _Backends backends,
) =>
    tester.pumpWidget(MaterialApp(
      home: SettingsScreen(settings: settings, store: backends.store),
    ));

/// The form is taller than the test viewport, so anything below the fold
/// gets scrolled to first -- the fields exist, they are just off screen.
///
/// The unfocus is load-bearing: a field that still holds focus scrolls the
/// view back to itself during the settle, which put the target back off
/// screen once the form grew past two screens (T-0006).
Future<void> _tap(WidgetTester tester, Finder target) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

final _warning = find.byKey(const Key('settings-privacy-warning'));

String _textOf(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data!;

String _warningText(WidgetTester tester) =>
    _textOf(tester, 'settings-privacy-risk');

String _adviceText(WidgetTester tester) =>
    _textOf(tester, 'settings-privacy-advice');

String _inForceText(WidgetTester tester) =>
    _textOf(tester, 'settings-backend-in-force');

void main() {
  tearDown(() => ProviderPolicy.debugLocalServerIsThisMachineOverride = null);

  testWidgets('configures every backend and chooses none (T-0115)',
      (tester) async {
    // The choice is the scan screen's switch, which writes the same
    // preference this screen's Save does. A second copy of it here staged the
    // choice until Save, so the same stored value had two meanings of a tap.
    for (final onThisMachine in [true, false]) {
      ProviderPolicy.debugLocalServerIsThisMachineOverride = onThisMachine;
      await _pump(tester, ProviderSettings(), _Backends());

      expect(find.byKey(const Key('settings-backend')), findsNothing,
          reason: 'onThisMachine=$onThisMachine');
      expect(find.byType(SegmentedButton<VisionBackend>), findsNothing);
      // The fields for every backend are here whichever one is in force --
      // which is why this screen never had a mode to select.
      expect(find.text('Cloud (Anthropic)'), findsOneWidget);
      expect(find.text('Endpoint (any OpenAI-compatible service)'),
          findsOneWidget);
      // Ollama's too, on both platforms since T-0361: where the server is
      // another machine the fields are the only way to name it, and the
      // paragraph that says so is rendered with them.
      expect(find.byKey(const Key('settings-ollama-url')), findsOneWidget);
      expect(find.byKey(const Key('settings-ollama-model')), findsOneWidget);
      expect(find.text('Local (Ollama)'), findsOneWidget);
      expect(find.byKey(const Key('settings-ollama-lan-note')),
          onThisMachine ? findsNothing : findsOneWidget);
    }
  });

  testWidgets('names the backend in force and where its switch is',
      (tester) async {
    ProviderPolicy.debugLocalServerIsThisMachineOverride = true;
    await _pump(tester, ProviderSettings(backend: VisionBackend.cloud),
        _Backends());

    expect(_inForceText(tester), contains(VisionBackend.cloud.label));
    // The advice under the warning says "switch to Local"; the control it
    // means is one screen back, so the sentence has to say so.
    expect(_inForceText(tester), contains('scan screen'));
  });

  testWidgets('a local backend stored on a phone is described as itself',
      (tester) async {
    ProviderPolicy.debugLocalServerIsThisMachineOverride = false;
    // Preferences restored from a desktop backup onto a phone. Until T-0361
    // the policy corrected this to cloud; local is now real here, so the
    // screen names what is actually in force and warns in its own words --
    // which are not the cloud ones, because the photos stop at the network.
    await _pump(tester, ProviderSettings(backend: VisionBackend.local),
        _Backends());

    expect(_inForceText(tester), contains(VisionBackend.local.label));
    expect(_warningText(tester), lanPrivacyWarning);
    expect(_warningText(tester), isNot(cloudPrivacyWarning));
  });

  testWidgets('every backend the policy offers is described, on both '
      'platforms', (tester) async {
    for (final onThisMachine in [true, false]) {
      ProviderPolicy.debugLocalServerIsThisMachineOverride = onThisMachine;
      for (final backend in ProviderPolicy.available) {
        await _pump(tester, ProviderSettings(backend: backend), _Backends());
        final reason = '$backend, onThisMachine=$onThisMachine';

        expect(_inForceText(tester), contains(backend.label), reason: reason);
        final check = ProviderPolicy.check(ProviderSettings(backend: backend));
        if (check.warning == null) {
          expect(_warning, findsNothing, reason: reason);
        } else {
          expect(_warningText(tester), check.warning, reason: reason);
          expect(_adviceText(tester), check.advice, reason: reason);
        }
      }
    }
  });

  testWidgets('key fields are obscured until revealed', (tester) async {
    await _pump(tester, ProviderSettings(), _Backends());

    for (final key in [
      'settings-anthropic-key',
      'settings-igdb-id',
      'settings-igdb-secret',
      'settings-tmdb-token',
    ]) {
      expect(tester.widget<TextField>(find.byKey(Key(key))).obscureText, isTrue,
          reason: '$key must not render a credential in plain text');
    }

    // ... and the user can still check what they typed.
    await _tap(
        tester,
        find.descendant(
          of: find.byKey(const Key('settings-anthropic-key')),
          matching: find.byIcon(Icons.visibility),
        ));
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('settings-anthropic-key')))
          .obscureText,
      isFalse,
    );
  });

  testWidgets('saving routes each field to the right backend', (tester) async {
    ProviderPolicy.debugLocalServerIsThisMachineOverride = true;
    final backends = _Backends();
    // Cloud because the scan screen's switch put it there; Save has to carry
    // it through untouched now that this screen cannot set it (T-0115).
    final settings = ProviderSettings(backend: VisionBackend.cloud);
    await _pump(tester, settings, backends);

    await tester.enterText(
        find.byKey(const Key('settings-anthropic-key')), 'sk-ant-typed');
    await tester.enterText(
        find.byKey(const Key('settings-igdb-id')), 'typed-id');
    await tester.enterText(
        find.byKey(const Key('settings-igdb-secret')), 'typed-secret');
    await tester.enterText(
        find.byKey(const Key('settings-tmdb-token')), 'typed-tmdb-token');
    await tester.enterText(
        find.byKey(const Key('settings-ollama-url')), 'http://localhost:11434');
    await _tap(tester, find.byKey(const Key('settings-save')));

    expect(backends.secrets.values, containsPair('anthropic_api_key', 'sk-ant-typed'));
    expect(backends.secrets.values, containsPair('igdb_client_id', 'typed-id'));
    expect(
        backends.secrets.values, containsPair('igdb_client_secret', 'typed-secret'));
    expect(backends.secrets.values,
        containsPair('tmdb_token', 'typed-tmdb-token'));
    expect(backends.prefs.values, {
      SettingsStore.keyBackend: 'cloud',
      SettingsStore.keyOllamaUrl: 'http://localhost:11434',
      SettingsStore.keyOllamaModel: defaultOllamaModel,
    });
    for (final write in backends.prefs.writes) {
      expect(
          write.value,
          isNot(anyOf('sk-ant-typed', 'typed-id', 'typed-secret',
              'typed-tmdb-token')));
    }
    // The caller's settings object carries the new values immediately.
    expect(settings.anthropicApiKey, 'sk-ant-typed');
    expect(settings.backend, VisionBackend.cloud);
    expect(settings.hasIgdbCredentials, isTrue);
    expect(settings.tmdbToken, 'typed-tmdb-token');
  });

  group('clearing a field asks for the default (T-0082)', () {
    /// The gesture the UI invites: `hintText` on both fields IS the default,
    /// which is the Material affordance for "clear this and you get that".
    /// It stored `''` instead, and the scan died minutes later blaming Ollama.
    Future<ProviderSettings> clearAndSave(
      WidgetTester tester,
      _Backends backends, {
      required String typed,
    }) async {
      ProviderPolicy.debugLocalServerIsThisMachineOverride = true;
      final settings =
          ProviderSettings(ollamaUrl: 'http://localhost:11434', ollamaModel: 'llava:13b');
      await _pump(tester, settings, backends);

      await tester.enterText(find.byKey(const Key('settings-ollama-url')), typed);
      await tester.enterText(
          find.byKey(const Key('settings-ollama-model')), typed);
      await _tap(tester, find.byKey(const Key('settings-save')));
      return settings;
    }

    testWidgets('the hint the field shows is the value clearing it produces',
        (tester) async {
      ProviderPolicy.debugLocalServerIsThisMachineOverride = true;
      await _pump(tester, ProviderSettings(), _Backends());

      // If these two ever stop being the defaults, the affordance is a lie
      // again and the rest of this group is testing something else.
      expect(
          tester
              .widget<TextField>(find.byKey(const Key('settings-ollama-url')))
              .decoration!
              .hintText,
          defaultOllamaUrl);
      expect(
          tester
              .widget<TextField>(find.byKey(const Key('settings-ollama-model')))
              .decoration!
              .hintText,
          defaultOllamaModel);
    });

    testWidgets('the object the scan screen keeps is fixed in this session, '
        'not at the next launch', (tester) async {
      final backends = _Backends();
      final settings = await clearAndSave(tester, backends, typed: '');

      // The settings screen edits the caller's object in place and pops; the
      // scan screen goes on scanning with this very instance.
      expect(settings.ollamaUrl, defaultOllamaUrl);
      expect(settings.ollamaModel, defaultOllamaModel);
      final provider = ProviderPolicy.build(settings) as OllamaVisionProvider;
      expect(provider.baseUrl, defaultOllamaUrl);
      expect(provider.model, defaultOllamaModel);
      expect(ProviderPolicy.check(settings).blocker, isNull);
    });

    testWidgets('and nothing blank is left in preferences either',
        (tester) async {
      final backends = _Backends();
      await clearAndSave(tester, backends, typed: '');

      expect(backends.prefs.values, {
        SettingsStore.keyBackend: VisionBackend.local.name,
        SettingsStore.keyOllamaUrl: defaultOllamaUrl,
        SettingsStore.keyOllamaModel: defaultOllamaModel,
      });
      // The exact map above already says it; this says why. A `''` left in
      // preferences is a value some future reader trusts, which is the half of
      // this defect that outlives the session.
      expect(backends.prefs.values.values, everyElement(isNotEmpty));
    });

    testWidgets('a field holding only spaces is a cleared field',
        (tester) async {
      final settings = await clearAndSave(tester, _Backends(), typed: '   ');

      expect(settings.ollamaUrl, defaultOllamaUrl);
      expect(settings.ollamaModel, defaultOllamaModel);
    });

    testWidgets('a blank stored before this change shows the default it now '
        'means', (tester) async {
      ProviderPolicy.debugLocalServerIsThisMachineOverride = true;
      final backends = _Backends();
      backends.prefs.values[SettingsStore.keyOllamaUrl] = '';
      backends.prefs.values[SettingsStore.keyOllamaModel] = '';

      // What the app really starts with, not a hand-built object.
      await _pump(tester, await backends.store.load(), backends);

      expect(
          tester
              .widget<TextField>(find.byKey(const Key('settings-ollama-url')))
              .controller!
              .text,
          defaultOllamaUrl);
    });

    testWidgets('a cleared key is still cleared -- no default is invented for '
        'a credential', (tester) async {
      ProviderPolicy.debugLocalServerIsThisMachineOverride = true;
      final backends = _Backends();
      final settings = ProviderSettings(
          backend: VisionBackend.cloud, anthropicApiKey: 'sk-ant-typed');
      await _pump(tester, settings, backends);

      await tester.enterText(
          find.byKey(const Key('settings-anthropic-key')), '');
      await _tap(tester, find.byKey(const Key('settings-save')));

      expect(backends.secrets.values, isEmpty);
      expect(settings.anthropicApiKey, isEmpty);
      // The asymmetry, at the point a user would meet it: the same gesture
      // means "give me the default" on one field and "forget this" on the next.
      expect(ProviderPolicy.check(settings).blocker, contains('API key'));
    });
  });

  testWidgets('every backend that uploads warns, in its own words; Local does '
      'not (T-0058)', (tester) async {
    ProviderPolicy.debugLocalServerIsThisMachineOverride = true;
    await _pump(tester, ProviderSettings(), _Backends());

    expect(_warning, findsNothing,
        reason: 'the local default is nagged at about nothing');

    // Anthropic: an upload, but a paid API rather than a free tier, so no
    // training sentence. This was the case that said nothing at all until
    // T-0058 -- and after T-0061 removed the toggle, nothing on the whole
    // screen did. It is still said here, on the screen where the key that
    // turns the upload on is typed, though the choice itself moved (T-0115).
    await _pump(
        tester, ProviderSettings(backend: VisionBackend.cloud), _Backends());
    expect(_warningText(tester), cloudPrivacyWarning);

    await _pump(tester,
        ProviderSettings(backend: VisionBackend.openAiCompatible), _Backends());
    expect(_warningText(tester), endpointPrivacyWarning);

    // Not the same sentence with a different noun: only a named third party
    // may be funding its free tier with what is submitted to it.
    expect(endpointPrivacyWarning, contains('training on what'));
    expect(cloudPrivacyWarning, isNot(contains('training')));
    for (final warning in [cloudPrivacyWarning, endpointPrivacyWarning]) {
      expect(warning, contains('leave this machine'));
    }
  });

  testWidgets('a cloud-only platform is warned before it touches anything',
      (tester) async {
    // Android arrives on this screen already set to cloud, so the warning
    // has to be on the first frame rather than on a tap that never comes.
    ProviderPolicy.debugLocalServerIsThisMachineOverride = false;
    await _pump(tester, ProviderSettings(), _Backends());

    expect(_warningText(tester), cloudPrivacyWarning);
  });

  testWidgets('the warning also says what to do about it, and where a local '
      'backend exists that is Local (T-0070)', (tester) async {
    ProviderPolicy.debugLocalServerIsThisMachineOverride = true;
    await _pump(
        tester, ProviderSettings(backend: VisionBackend.cloud), _Backends());
    expect(_adviceText(tester), contains(VisionBackend.local.label));

    await _pump(tester,
        ProviderSettings(backend: VisionBackend.openAiCompatible), _Backends());
    // The sentence T-0058 dropped, restored on the platform it is true on.
    expect(_adviceText(tester), contains('data policy'));
    expect(_adviceText(tester), contains(VisionBackend.local.label));

    // Two strings, not one: the measured risk wording is untouched by the
    // advice sitting under it.
    expect(_warningText(tester), endpointPrivacyWarning);

    await _pump(tester, ProviderSettings(), _Backends());
    expect(find.byKey(const Key('settings-privacy-advice')), findsNothing);
  });

  testWidgets('a phone is offered Local as the escape, without being told the '
      'photos stay put (T-0070, T-0361)', (tester) async {
    ProviderPolicy.debugLocalServerIsThisMachineOverride = false;
    await _pump(tester, ProviderSettings(), _Backends());

    // Cloud is still where a phone arrives. What changed is that there is
    // now somewhere to go: Local, which keeps the photos off the internet
    // and NOT on this device. The second half is the one that would be a
    // false promise here, so it is asserted against rather than assumed.
    expect(_adviceText(tester), contains(VisionBackend.local.label));
    expect(_adviceText(tester), contains('your own network'));
    expect(_adviceText(tester), isNot(contains('this machine')));

    await _pump(tester,
        ProviderSettings(backend: VisionBackend.openAiCompatible), _Backends());
    expect(_adviceText(tester), contains('data policy'));
    expect(_adviceText(tester), contains(VisionBackend.local.label));
    expect(_adviceText(tester), isNot(contains('this machine')));
  });

  testWidgets('a backend stored before this change still resolves, and Save '
      'writes it back unchanged (T-0115)', (tester) async {
    ProviderPolicy.debugLocalServerIsThisMachineOverride = true;
    final backends = _Backends();
    // Written by an older build's Save, or by the scan screen's switch --
    // the same key either way.
    backends.prefs.values[SettingsStore.keyBackend] = 'openAiCompatible';
    final settings = await backends.store.load();
    await _pump(tester, settings, backends);

    expect(settings.backend, VisionBackend.openAiCompatible);
    expect(_inForceText(tester),
        contains(VisionBackend.openAiCompatible.label));
    expect(_warningText(tester), endpointPrivacyWarning);

    backends.prefs.writes.clear();
    await _tap(tester, find.byKey(const Key('settings-save')));

    expect(backends.prefs.values,
        containsPair(SettingsStore.keyBackend, 'openAiCompatible'));
    expect(settings.backend, VisionBackend.openAiCompatible,
        reason: 'a screen that cannot choose a backend must not reset one');
  });

  test('the privacy wording has exactly one definition (T-0058, T-0070)', () {
    // One clause per distinct piece of privacy wording. The settings screen
    // carried its own paraphrase of the risk for the whole of T-0040; this
    // fails on the next copy of any of them, wherever in the app it is
    // written. Extended for T-0070's advice, which is four strings with no
    // clause common to all four -- so the list, not the shape, is what grows
    // when the text does.
    const clauses = [
      'uploaded in full to', // both risk statements
      'keep them on this machine', // advice where the server is this machine
      "data policy before you scan", // advice on either endpoint platform
      // T-0361's three: local's own risk where it is another machine, the
      // way out both uploading backends offer there, and local's own way out.
      'over plain HTTP', // the LAN risk statement
      'server on your own network instead of to the internet',
      'stay on one machine', // advice for local where local is elsewhere
    ];
    final dartFiles = [
      for (final entry in Directory('lib').listSync(recursive: true))
        if (entry is File && entry.path.endsWith('.dart')) entry,
    ];

    for (final clause in clauses) {
      final copies = [
        for (final file in dartFiles)
          if (file.readAsStringSync().contains(clause)) file.path,
      ];
      expect(copies, hasLength(1), reason: '"$clause" copies: $copies');
      expect(copies.single, endsWith('provider_config.dart'),
          reason: '"$clause" belongs with the policy');
    }
  });

  testWidgets('the endpoint key is a secret; its URL and model are not',
      (tester) async {
    ProviderPolicy.debugLocalServerIsThisMachineOverride = true;
    final backends = _Backends();
    final settings =
        ProviderSettings(backend: VisionBackend.openAiCompatible);
    await _pump(tester, settings, backends);

    await tester.enterText(find.byKey(const Key('settings-openai-url')),
        'https://api.groq.com/openai/v1');
    await tester.enterText(
        find.byKey(const Key('settings-openai-model')), 'llama-4-scout');
    await tester.enterText(
        find.byKey(const Key('settings-openai-key')), 'gsk-typed');
    // Obscured like every other credential field -- checked before the save
    // pops the screen.
    expect(
        tester
            .widget<TextField>(find.byKey(const Key('settings-openai-key')))
            .obscureText,
        isTrue);

    await _tap(tester, find.byKey(const Key('settings-save')));

    expect(backends.secrets.values,
        containsPair(SettingsStore.keyOpenAiApiKey, 'gsk-typed'));
    expect(backends.prefs.values,
        containsPair(SettingsStore.keyOpenAiBaseUrl,
            'https://api.groq.com/openai/v1'));
    expect(backends.prefs.values,
        containsPair(SettingsStore.keyOpenAiModel, 'llama-4-scout'));
    for (final write in backends.prefs.writes) {
      expect(write.value, isNot(contains('gsk-typed')));
    }
    expect(settings.backend, VisionBackend.openAiCompatible);
    expect(ProviderPolicy.build(settings),
        isA<OpenAiCompatibleVisionProvider>());
  });

  group('the Claude model (T-0067)', () {
    testWidgets('is optional: nothing typed still builds a working provider',
        (tester) async {
      ProviderPolicy.debugLocalServerIsThisMachineOverride = true;
      final backends = _Backends();
      final settings = ProviderSettings(
          backend: VisionBackend.cloud, anthropicApiKey: 'sk-ant-x');
      await _pump(tester, settings, backends);

      await _tap(tester, find.byKey(const Key('settings-save')));

      expect(settings.anthropicModel, isEmpty);
      final provider =
          ProviderPolicy.build(settings) as AnthropicVisionProvider;
      // Which id it is belongs to the provider (T-0057); that there IS one,
      // and that it keeps the temperature that id was argued for, belongs
      // here.
      expect(provider.model, isNotEmpty);
      expect(provider.temperature, 0);
    });

    testWidgets('is a preference, and naming one drops the temperature',
        (tester) async {
      ProviderPolicy.debugLocalServerIsThisMachineOverride = true;
      final backends = _Backends();
      final settings = ProviderSettings(
          backend: VisionBackend.cloud, anthropicApiKey: 'sk-ant-x');
      await _pump(tester, settings, backends);

      await tester.enterText(
          find.byKey(const Key('settings-anthropic-model')), 'claude-opus-5');
      await _tap(tester, find.byKey(const Key('settings-save')));

      // A model name is configuration; only the key beside it is a secret.
      expect(backends.prefs.values,
          containsPair(SettingsStore.keyAnthropicModel, 'claude-opus-5'));
      expect(backends.secrets.values.containsKey(
          SettingsStore.keyAnthropicModel), isFalse);

      final provider =
          ProviderPolicy.build(settings) as AnthropicVisionProvider;
      expect(provider.model, 'claude-opus-5');
      // The interaction this task exists for: sampling parameters return 400
      // on Claude Opus 4.7 and later, Sonnet 5 and Fable 5, and that 400
      // arriving mid-scan reads as a broken key. No list of those families is
      // kept anywhere -- it would age exactly as the pinned default did -- so
      // ANY model the user names is sent without one.
      expect(provider.temperature, isNull);
    });

    testWidgets('the field is not obscured -- it is not a credential',
        (tester) async {
      await _pump(tester, ProviderSettings(), _Backends());

      expect(
        tester
            .widget<TextField>(find.byKey(const Key('settings-anthropic-model')))
            .obscureText,
        isFalse,
      );
      // Where the current ids come from, rather than a list of them that
      // would go stale the way the pinned default did.
      expect(find.textContaining('api.anthropic.com/v1/models'),
          findsOneWidget);
    });
  });

  testWidgets('the second-reader control is gone, on either platform '
      '(T-0061)', (tester) async {
    // It doubled the cost, uploaded every photo of a private home, and on
    // its one measurement added 15 rows of which 15 were wrong (T-0032).
    // The CLI keeps --fallback for measuring a cloud second reader; the
    // product ships no switch for it.
    for (final onThisMachine in [true, false]) {
      ProviderPolicy.debugLocalServerIsThisMachineOverride = onThisMachine;
      await _pump(tester, ProviderSettings(anthropicApiKey: 'sk-ant-x'),
          _Backends());

      expect(find.byType(SwitchListTile), findsNothing,
          reason: 'onThisMachine=$onThisMachine');
      expect(find.textContaining('second time'), findsNothing);
      expect(find.textContaining('EVERY photo'), findsNothing);
    }
  });

  testWidgets('a stored cloud_fallback=true from before T-0061 turns nothing '
      'on', (tester) async {
    ProviderPolicy.debugLocalServerIsThisMachineOverride = true;
    final backends = _Backends();
    await backends.prefs.write('cloud_fallback', 'true');
    // The settings the app would really start with, not a hand-built object.
    final settings = await backends.store.load();
    await _pump(tester, settings, backends);

    expect(find.byType(SwitchListTile), findsNothing);

    backends.prefs.writes.clear();
    await _tap(tester, find.byKey(const Key('settings-save')));

    // Saving over it writes no consent of any kind back.
    expect(backends.prefs.writes.map((w) => w.key),
        isNot(contains('cloud_fallback')));
    expect(ProviderPolicy.build(settings), isA<OllamaVisionProvider>());
  });

  testWidgets('the IGDB section is marked optional and hands over the Twitch '
      'console address', (tester) async {
    await _pump(tester, ProviderSettings(), _Backends());

    expect(find.text('IGDB (optional)'), findsOneWidget);

    // The clipboard is a platform channel; intercept it rather than let the
    // test bang on a real one.
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    final link = find.byKey(const Key('settings-igdb-console-link'));
    expect(find.descendant(of: link, matching: find.textContaining(
        twitchConsoleUrl)), findsOneWidget,
        reason: 'the address must be readable without tapping anything');

    await _tap(tester, link);
    expect(copied, twitchConsoleUrl);
    expect(find.textContaining('Link copied'), findsOneWidget);
  });

  // The section used to say the rows "arrive unresolved and you fix them
  // during review", which was not true of a run with no credentials: the
  // resolve stage is skipped outright, so those rows carry no candidate list
  // and there is nothing on the review screen to pick from. It names the mode
  // and its control instead (T-0230) -- one control per stored thing, and the
  // other screen states it, which is the shape T-0115 set.
  testWidgets('the IGDB section names the keyless mode and where to choose it',
      (tester) async {
    await _pump(tester, ProviderSettings(), _Backends());

    final note = tester
        .widget<Text>(find.byKey(const Key('settings-igdb-optional')))
        .data!;

    expect(note, contains(TitleMatching.keyless.label));
    expect(note, contains('scan screen'));
    expect(note, isNot(contains('fix them during review')));

    // And it stopped speaking for the whole run (T-0367). It said "Without
    // them a scan is a Keyless run", which a TMDB token alone now makes
    // false: what a blank pair costs is a GAME row, and the TMDB section
    // below has said exactly that about its own kind since T-0363.
    expect(note, contains('game row'));
    expect(note, isNot(contains('a scan is a')));
  });

  // TMDB issues two credentials on one page and they look nothing alike: the
  // read token is long and starts eyJ, the v3 key is short. Someone who pastes
  // the wrong one gets a 401 with nothing in it to act on, so the screen says
  // which it wants before the paste rather than after it (T-0363).
  testWidgets('the TMDB field names which of the two credentials it wants',
      (tester) async {
    await _pump(tester, ProviderSettings(), _Backends());

    final label = tester
        .widget<TextField>(find.byKey(const Key('settings-tmdb-token')))
        .decoration!;

    expect(label.labelText, contains('Read Access Token'));
    // Naming the one it wants is not enough on its own: the other one has to
    // be excluded by name, or a reader matches "Token" against either.
    expect(label.helperText, contains('API Key'));
    expect(label.helperText, contains('not the'));
    expect(label.helperText, contains('eyJ'));
  });

  testWidgets('the TMDB section is optional, says what a blank one costs, and '
      'hands over the address', (tester) async {
    await _pump(tester, ProviderSettings(), _Backends());

    expect(find.text('TMDB (optional)'), findsOneWidget);

    final note = _textOf(tester, 'settings-tmdb-optional');
    // The keyless film row, in the words T-0308 settled it in. It may not
    // read as a warning that the app now needs a third credential, so the
    // export that still works is named beside the one that does not.
    expect(note, contains('.xcoll no'));
    expect(note, contains('CSV yes'));
    expect(note, contains('Games are unaffected'));

    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    final link = find.byKey(const Key('settings-tmdb-console-link'));
    expect(
        find.descendant(
            of: link, matching: find.textContaining(tmdbApiSettingsUrl)),
        findsOneWidget,
        reason: 'the address must be readable without tapping anything');

    await _tap(tester, link);
    expect(copied, tmdbApiSettingsUrl);
  });

  // TMDB's terms mandate this sentence word for word, with only the bracketed
  // word substituted (T-0383; T-0379 shipped a paraphrase). The three READMEs
  // carry the same sentence for a reader who never installs; this is the
  // in-app half, and why it is on this screen rather than the review one is
  // argued in the comment beside the widget.
  testWidgets('the TMDB attribution is stated, and asserts no relationship',
      (tester) async {
    // Unconditional on purpose: the requirement is about the application, and
    // a person reads this section before there is a token to condition on.
    for (final settings in [
      ProviderSettings(),
      ProviderSettings(tmdbToken: 'tmdb-not-a-token'),
    ]) {
      await _pump(tester, settings, _Backends());

      // Asserted whole rather than in fragments, because the requirement is
      // the whole sentence: the wording this replaced contained every
      // fragment anyone thought to check for and was still a paraphrase. The
      // literal below is a second, independent copy of the required text --
      // importing the screen's own string would make the comparison vacuous.
      final text = _textOf(tester, 'settings-tmdb-attribution');
      expect(
          text,
          'This application uses TMDB and the TMDB APIs but is not endorsed, '
          'certified, or otherwise approved by TMDB.');

      // The sentence exists to deny a relationship, so a warm phrasing
      // defeats it however true the rest of the line is.
      for (final claim in [
        'partner',
        'powered by',
        'official',
        'in association',
        'together with',
      ]) {
        expect(text.toLowerCase(), isNot(contains(claim)),
            reason: 'an attribution that reads as an endorsement is not one');
      }

      // And it is not a feature announcement. No run through this shell has
      // ever had an answer from TMDB (doc/measurements.md, "TMDB's `year`
      // filters, and the first live film searches"), and the tv endpoint has
      // been called by nothing at all, so the line says what the app uses and
      // claims nothing about what it got back.
      for (final claim in ['film', 'series', 'match', 'result']) {
        expect(text.toLowerCase(), isNot(contains(claim)),
            reason: 'the attribution may not describe the path as exercised');
      }
    }
  });

  // T-0385. The terms permit a TMDB mark in an application only on a
  // condition -- "Any use of any TMDB logos in Your Application must be less
  // prominent than the logos or marks that primarily describe or identify
  // Your Application" -- and that comparison is settled here out of the widget
  // tree. It has to be: doc/conventions.md section 3 forbids driving the GUI,
  // so a compliance claim that needs somebody to look at the screen is a claim
  // this project cannot make at all.
  testWidgets(
      'the TMDB mark is the published asset, and smaller than the wordmark '
      'that identifies this application', (tester) async {
    // The identifying mark is the application's name in the app bar of its
    // primary screen. Read off the real ScanScreen under the real theme,
    // because the size belongs to the theme and not to this file -- a copied
    // number would stop tracking the thing it is compared against.
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(colorSchemeSeed: appSeedColor, useMaterial3: true),
      home: ScanScreen(
        settings: ProviderSettings(backend: VisionBackend.local),
        store:
            SettingsStore(secrets: RecordingStore(), prefs: RecordingStore()),
      ),
    ));
    final wordmark = find.descendant(
      of: find.byType(AppBar),
      matching: find.text('shelfscan'),
    );
    expect(wordmark, findsOneWidget);
    final wordmarkType = tester
        .widget<RichText>(
            find.descendant(of: wordmark, matching: find.byType(RichText)))
        .text
        .style!
        .fontSize!;
    final wordmarkBox = tester.getRect(wordmark).height;

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(colorSchemeSeed: appSeedColor, useMaterial3: true),
      home: SettingsScreen(
          settings: ProviderSettings(), store: _Backends().store),
    ));
    final logo = find.byKey(const Key('settings-tmdb-logo'));
    expect(logo, findsOneWidget);

    // Rendered from the committed file, by its own key. TMDB publishes SVG
    // and no raster format, and states no alteration rule, so a PNG here
    // would be a derivative in a shape its owner neither publishes nor has
    // said anything about; naming the path pins which file is on screen.
    expect(tmdbLogoAsset, 'assets/tmdb/blue_long_1.svg');
    expect(tester.widget<SvgPicture>(logo).height, tmdbLogoHeight);

    // Unaltered, and it decodes -- the two halves of "renders from the
    // published SVG" that can be had without looking at a screen. The
    // intrinsic size is the published viewBox: a recoloured, re-cropped or
    // re-exported copy would not land on it, and a file the renderer cannot
    // parse throws here instead of showing a blank.
    final art = await vg.loadPicture(const SvgAssetLoader(tmdbLogoAsset), null);
    expect(art.size.width, closeTo(423.04, 0.5));
    expect(art.size.height, closeTo(35.4, 0.5));

    // Aspect preserved, so the height above governs the whole mark: no BoxFit
    // stretches it and nothing widens it independently.
    final box = tester.getRect(logo);
    expect(box.height, tmdbLogoHeight);
    expect(box.width / box.height,
        closeTo(art.size.width / art.size.height, 0.01));

    // Both comparisons, because they fail differently. The first is the
    // requirement as stated -- the mark against the type size of the mark it
    // must yield to. The second is what the two actually occupy once laid
    // out, which is what catches a height that grows through a wrapper
    // rather than through the constant.
    expect(tmdbLogoHeight, lessThan(wordmarkType));
    expect(tester.getRect(logo).height, lessThan(wordmarkBox));
  });

  testWidgets('a storage failure is reported instead of silently losing keys',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SettingsScreen(
        settings: ProviderSettings(),
        store: const SettingsStore(secrets: _FailingStore(), prefs: _FailingStore()),
      ),
    ));

    await tester.enterText(
        find.byKey(const Key('settings-anthropic-key')), 'sk-ant-typed');
    await _tap(tester, find.byKey(const Key('settings-save')));

    expect(find.textContaining('Could not save settings'), findsOneWidget);
    // still on the settings screen, values intact
    expect(find.byKey(const Key('settings-save')), findsOneWidget);
  });
}

class _FailingStore implements SecretStore, PrefsStore {
  const _FailingStore();

  @override
  Future<String?> read(String key) async => null;

  @override
  Future<void> write(String key, String value) async =>
      throw StateError('keychain unavailable');
}
