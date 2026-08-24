/// Tests for the settings persistence split.
///
/// The load-bearing assertion here is negative: no secret value, and no
/// secret key, may ever reach the plain-preferences backend. Everything
/// else in this file exists to make that one meaningful.
///
/// The last group is the second negative (T-0082): no non-secret setting may
/// treat a blank as a value. It is T-0080's shape one layer down -- there the
/// enumeration came from scanning the CLI source, here it comes from what
/// [SettingsStore.save] actually writes, so a setting added to the store has
/// no treatment until someone states one.
library;

import 'dart:io';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelfscan_app/provider_config.dart';
import 'package:shelfscan_app/settings_store.dart';
import 'package:shelfscan_core/shelfscan_core.dart';

/// Records every write so a test can inspect what a backend was told.
class RecordingStore implements SecretStore, PrefsStore {
  final Map<String, String> values = {};
  final List<({String key, String value})> writes = [];

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    writes.add((key: key, value: value));
    // The contract both backends really have -- checked against the two real
    // ones by 'the fake keeps the contract the real backends do' below, which
    // is what this fake asserted about `SharedPrefsStore` and was wrong about
    // for the whole of T-0082.
    if (value.isEmpty) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }
}

const _anthropicKey = 'sk-ant-SECRET-anthropic';
const _openAiKey = 'sk-SECRET-endpoint';
const _igdbId = 'igdbid-SECRET-0123';
const _igdbSecret = 'igdbsecret-SECRET-4567';
const _tmdbToken = 'tmdbtoken-SECRET-89ab';

ProviderSettings _filledSettings() => ProviderSettings(
      backend: VisionBackend.cloud,
      ollamaUrl: 'http://192.0.2.10:11500',
      ollamaModel: 'llava:13b',
      openAiBaseUrl: 'https://api.groq.com/openai/v1',
      openAiModel: 'llama-4-scout',
      openAiApiKey: _openAiKey,
      anthropicApiKey: _anthropicKey,
      anthropicModel: 'claude-opus-5',
      igdbClientId: _igdbId,
      igdbClientSecret: _igdbSecret,
      tmdbToken: _tmdbToken,
    );

/// Every non-secret setting, stated once. Checked below against the keys a
/// full save really writes, so this list cannot quietly fall behind the store.
const _nonSecretKeys = <String>{
  SettingsStore.keyBackend,
  SettingsStore.keyOllamaUrl,
  SettingsStore.keyOllamaModel,
  SettingsStore.keyOpenAiBaseUrl,
  SettingsStore.keyOpenAiModel,
  SettingsStore.keyAnthropicModel,
  SettingsStore.keyThemeMode,
};

/// The preferences of an app with every non-secret setting deliberately set to
/// something other than its default -- the one file each case below blanks a
/// single key of.
Future<Map<String, String>> _configuredPrefs() async {
  final prefs = RecordingStore();
  final store = SettingsStore(secrets: RecordingStore(), prefs: prefs);
  await store.save(_filledSettings());
  await store.saveThemeMode(ThemeMode.dark);
  return Map.of(prefs.values);
}

/// Everything [stored] configures, as one string: two preference files agree
/// here exactly when they configure the same app. Rendered by saving back what
/// was loaded rather than by listing fields, so a setting added to the store
/// joins the comparison with no second edit here.
Future<String> _configuredBy(Map<String, String> stored) async {
  final store = SettingsStore(
    secrets: RecordingStore(),
    prefs: RecordingStore()..values.addAll(stored),
  );
  final loaded = await store.load();
  final themeMode = await store.loadThemeModeOrDefault();

  final echoed = RecordingStore();
  final echo = SettingsStore(secrets: RecordingStore(), prefs: echoed);
  await echo.save(loaded);
  await echo.saveThemeMode(themeMode);
  final keys = echoed.values.keys.toList()..sort();
  return [for (final key in keys) '$key=${echoed.values[key]}'].join('\n');
}

void main() {
  tearDown(() => ProviderPolicy.debugLocalServerIsThisMachineOverride = null);

  test('secrets go to the keychain and never to preferences', () async {
    final secrets = RecordingStore();
    final prefs = RecordingStore();
    await SettingsStore(secrets: secrets, prefs: prefs)
        .save(_filledSettings());

    // The whole point of the split: not one secret value touched prefs.
    for (final write in prefs.writes) {
      for (final secret in [
        _anthropicKey,
        _openAiKey,
        _igdbId,
        _igdbSecret,
        _tmdbToken,
      ]) {
        expect(write.value, isNot(contains(secret)),
            reason: 'secret leaked into shared_preferences under '
                '"${write.key}"');
      }
      expect(
        write.key,
        isNot(anyOf(
          SettingsStore.keyAnthropicApiKey,
          SettingsStore.keyOpenAiApiKey,
          SettingsStore.keyIgdbClientId,
          SettingsStore.keyIgdbClientSecret,
          SettingsStore.keyTmdbToken,
        )),
      );
    }

    expect(secrets.values, {
      SettingsStore.keyAnthropicApiKey: _anthropicKey,
      SettingsStore.keyOpenAiApiKey: _openAiKey,
      SettingsStore.keyIgdbClientId: _igdbId,
      SettingsStore.keyIgdbClientSecret: _igdbSecret,
      SettingsStore.keyTmdbToken: _tmdbToken,
    });
    // Every model name is configuration, not a credential -- the Claude one
    // included (T-0067).
    expect(prefs.values, {
      SettingsStore.keyBackend: 'cloud',
      SettingsStore.keyOllamaUrl: 'http://192.0.2.10:11500',
      SettingsStore.keyOllamaModel: 'llava:13b',
      SettingsStore.keyOpenAiBaseUrl: 'https://api.groq.com/openai/v1',
      SettingsStore.keyOpenAiModel: 'llama-4-scout',
      SettingsStore.keyAnthropicModel: 'claude-opus-5',
    });
  });

  test('everything saved comes back on the next launch', () async {
    final secrets = RecordingStore();
    final prefs = RecordingStore();
    await SettingsStore(secrets: secrets, prefs: prefs)
        .save(_filledSettings());

    // A fresh store over the same backends == a restarted app.
    final loaded = await SettingsStore(secrets: secrets, prefs: prefs).load();

    expect(loaded.backend, VisionBackend.cloud);
    expect(loaded.ollamaUrl, 'http://192.0.2.10:11500');
    expect(loaded.ollamaModel, 'llava:13b');
    expect(loaded.anthropicApiKey, _anthropicKey);
    // A model id survives the restart, which is the whole point of storing
    // it: the default it replaces will one day be retired (T-0067).
    expect(loaded.anthropicModel, 'claude-opus-5');
    expect(loaded.openAiBaseUrl, 'https://api.groq.com/openai/v1');
    expect(loaded.openAiModel, 'llama-4-scout');
    expect(loaded.openAiApiKey, _openAiKey);
    expect(loaded.igdbClientId, _igdbId);
    expect(loaded.igdbClientSecret, _igdbSecret);
    expect(loaded.hasIgdbCredentials, isTrue);
    expect(loaded.tmdbToken, _tmdbToken);
    expect(loaded.hasTmdbToken, isTrue);
  });

  test('empty storage yields the platform defaults', () async {
    final loaded =
        await SettingsStore(secrets: RecordingStore(), prefs: RecordingStore())
            .load();

    expect(loaded.backend, ProviderPolicy.defaultBackend);
    expect(loaded.ollamaUrl, defaultOllamaUrl);
    expect(loaded.ollamaModel, defaultOllamaModel);
    expect(loaded.anthropicApiKey, isEmpty);
    // The third credential is as absent as the other four, and a run that
    // finds it so is the one most users will be on (T-0363).
    expect(loaded.tmdbToken, isEmpty);
    expect(loaded.hasTmdbToken, isFalse);
    // Nothing stored must mean the provider's own default, not an id this
    // side has copied down.
    expect(loaded.anthropicModel, isEmpty);
    expect(loaded.hasIgdbCredentials, isFalse);
    // Nothing stored must never mean "yes, send my photos to the cloud".
    expect(loaded.backend, isNot(VisionBackend.openAiCompatible));
    expect(loaded.openAiBaseUrl, isEmpty);
    expect(loaded.openAiModel, isEmpty);
    expect(loaded.openAiApiKey, isEmpty);
  });

  test('a stored endpoint backend survives a restart on either platform',
      () async {
    for (final onThisMachine in [true, false]) {
      ProviderPolicy.debugLocalServerIsThisMachineOverride = onThisMachine;
      final secrets = RecordingStore();
      final prefs = RecordingStore();
      await SettingsStore(secrets: secrets, prefs: prefs).save(
          _filledSettings()..backend = VisionBackend.openAiCompatible);

      final loaded =
          await SettingsStore(secrets: secrets, prefs: prefs).load();

      expect(loaded.backend, VisionBackend.openAiCompatible,
          reason: 'onThisMachine=$onThisMachine');
    }
  });

  test('a cloud_fallback preference stored before T-0061 is inert', () async {
    // The app that wrote it offered a second reader; this one has no field
    // to load it into and never asks for the key again.
    ProviderPolicy.debugLocalServerIsThisMachineOverride = true;
    final prefs = RecordingStore();
    await prefs.write('cloud_fallback', 'true');
    final secrets = RecordingStore()..values['anthropic_api_key'] = 'sk-ant-x';
    final store = SettingsStore(secrets: secrets, prefs: prefs);

    final loaded = await store.load();

    expect(ProviderPolicy.build(loaded), isA<OllamaVisionProvider>());
    // Re-saving does not carry the old consent forward either.
    prefs.writes.clear();
    await store.save(loaded);
    expect(prefs.writes.map((w) => w.key), isNot(contains('cloud_fallback')));
  });

  test('clearing a key removes it from the keychain', () async {
    final secrets = RecordingStore();
    final prefs = RecordingStore();
    final store = SettingsStore(secrets: secrets, prefs: prefs);
    await store.save(_filledSettings());

    await store.save(_filledSettings()..anthropicApiKey = '');

    expect(secrets.values.containsKey(SettingsStore.keyAnthropicApiKey),
        isFalse);
    expect((await store.load()).anthropicApiKey, isEmpty);
  });

  test('a stored local backend survives being read on a phone', () async {
    final secrets = RecordingStore();
    final prefs = RecordingStore();
    await SettingsStore(secrets: secrets, prefs: prefs)
        .save(ProviderSettings(backend: VisionBackend.local));
    expect(prefs.values[SettingsStore.keyBackend], 'local');

    // Same preferences file, now read on a phone. Until T-0361 this was
    // downgraded to cloud, because local did not exist here; it does now, so
    // the stored choice is honoured and what the backup really got wrong --
    // the desktop's loopback URL travelling with it -- is refused by name at
    // the tap instead of being silently swapped for another backend.
    ProviderPolicy.debugLocalServerIsThisMachineOverride = false;
    final loaded = await SettingsStore(secrets: secrets, prefs: prefs).load();

    expect(loaded.backend, VisionBackend.local);
    expect(ProviderPolicy.check(loaded).blocker, contains('this device'));
  });

  group('a blank non-secret setting is an unset one (T-0082)', () {
    test('every setting the store persists is accounted for', () async {
      final secrets = RecordingStore();
      final prefs = RecordingStore();
      final store = SettingsStore(secrets: secrets, prefs: prefs);
      await store.save(_filledSettings());
      await store.saveThemeMode(ThemeMode.dark);

      // How the enumeration is taken: not by reading the class and retyping
      // its keys, but by asking a fully-configured save which ones it wrote.
      expect(prefs.values.keys.toSet(), _nonSecretKeys);

      // ... and every key constant declared in the file is one of those or a
      // secret, so a setting wired up as neither fails here instead of
      // slipping past the probes below.
      final declared = RegExp(r"static const key\w+ = '([a-z0-9_]+)'")
          .allMatches(File('lib/settings_store.dart').readAsStringSync())
          .map((match) => match.group(1)!)
          .toSet();
      expect(declared, isNotEmpty,
          reason: 'the source scan found nothing, so the comparison below '
              'would pass on an empty file');
      expect(declared, {..._nonSecretKeys, ...secrets.values.keys});
    });

    for (final key in _nonSecretKeys) {
      test('$key blank configures the app that $key absent does', () async {
        final full = await _configuredPrefs();

        expect(await _configuredBy(full),
            isNot(await _configuredBy(Map.of(full)..remove(key))),
            reason: 'nothing loaded answers to $key, so the comparison below '
                'would pass however it is read');
        expect(await _configuredBy(Map.of(full)..[key] = ''),
            await _configuredBy(Map.of(full)..remove(key)));
      });
    }

    test('a preferences file written before this change heals on load',
        () async {
      // The state a user who ever cleared the field is already in: '' on disk,
      // and no reason for them to go and re-save it.
      final prefs = RecordingStore()
        ..values[SettingsStore.keyOllamaUrl] = ''
        ..values[SettingsStore.keyOllamaModel] = '';

      final loaded =
          await SettingsStore(secrets: RecordingStore(), prefs: prefs).load();

      expect(loaded.ollamaUrl, defaultOllamaUrl);
      expect(loaded.ollamaModel, defaultOllamaModel);
      final provider = ProviderPolicy.build(loaded) as OllamaVisionProvider;
      expect(provider.baseUrl, defaultOllamaUrl);
      expect(provider.model, defaultOllamaModel);
    });

    test('the fake keeps the contract the real backends do', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues(
          {SettingsStore.keyOllamaUrl: 'http://localhost:11434'});
      const real = SharedPrefsStore();

      await real.write(SettingsStore.keyOllamaUrl, '');

      expect(await real.read(SettingsStore.keyOllamaUrl), isNull,
          reason: 'RecordingStore below deletes on empty and every test here '
              'believes it; a real backend that stored the blank instead '
              'would make all of them fiction');
    });

    test('a cleared secret still deletes, and no default is invented for it',
        () async {
      final secrets = RecordingStore();
      final store = SettingsStore(secrets: secrets, prefs: RecordingStore());
      await store.save(_filledSettings());

      await store.save(_filledSettings()
        ..anthropicApiKey = ''
        ..igdbClientId = ''
        ..igdbClientSecret = ''
        ..tmdbToken = '');

      expect(secrets.values.keys, [SettingsStore.keyOpenAiApiKey]);
      final loaded = await store.load();
      expect(loaded.anthropicApiKey, isEmpty);
      expect(loaded.hasIgdbCredentials, isFalse);
      expect(loaded.hasTmdbToken, isFalse);
      // The asymmetry, in one line: blank means the default on one side of the
      // split and means nothing at all on the other.
      expect(loaded.ollamaUrl, isNotEmpty);
    });

    test('local can always run, whatever is or is not stored', () async {
      // ProviderPolicy._missing answers null for local unconditionally; this
      // is what makes that an answer rather than an oversight.
      ProviderPolicy.debugLocalServerIsThisMachineOverride = true;
      for (final stored in [
        <String, String>{},
        {SettingsStore.keyOllamaUrl: '', SettingsStore.keyOllamaModel: ''},
        {SettingsStore.keyOllamaUrl: 'http://localhost:11434'},
      ]) {
        final loaded = await SettingsStore(
          secrets: RecordingStore(),
          prefs: RecordingStore()..values.addAll(stored),
        ).load();
        loaded.backend = VisionBackend.local;

        expect(ProviderPolicy.check(loaded).blocker, isNull, reason: '$stored');
        expect((ProviderPolicy.build(loaded) as OllamaVisionProvider).baseUrl,
            isNotEmpty);
      }
    });
  });

  test('a broken backend never blocks app start', () async {
    final store = SettingsStore(secrets: _ThrowingStore(), prefs: _ThrowingStore());

    final loaded = await store.loadOrDefaults();

    expect(loaded.backend, ProviderPolicy.defaultBackend);
    expect(loaded.anthropicApiKey, isEmpty);
  });
}

class _ThrowingStore implements SecretStore, PrefsStore {
  @override
  Future<String?> read(String key) async => throw StateError('keychain locked');

  @override
  Future<void> write(String key, String value) async =>
      throw StateError('keychain locked');
}
