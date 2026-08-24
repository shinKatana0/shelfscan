/// Persisting [ProviderSettings] and the theme choice across app restarts.
///
/// Storage is a platform concern and belongs to the shell, not to
/// `shelfscan_core` (ARCHITECTURE.md platform boundary).
///
/// Two backends, split strictly by sensitivity -- this split is the whole
/// point of the file, so keep it visible:
///   * [SecretStore]  -> flutter_secure_storage -> OS keychain / Keystore.
///     Anthropic API key, the OpenAI-compatible endpoint's key, IGDB client
///     id AND secret. The client id is half of a credential pair, so it is
///     a secret too.
///   * [PrefsStore]   -> shared_preferences -> plain, world-readable-ish
///     file. Everything else, and nothing more.
/// A secret must never be handed to [PrefsStore]. There is a test for it, and
/// another that enumerates the non-secrets from what [SettingsStore.save]
/// writes rather than from a list here that could go stale (T-0082).
///
/// Both are abstract so the settings screen and its tests can run against
/// in-memory fakes -- same injection-seam style as `ExportSaver`.
library;

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'provider_config.dart';

/// Secrets. Backed by the OS keychain (Windows credential store, Android
/// Keystore-encrypted prefs).
abstract class SecretStore {
  const SecretStore();

  Future<String?> read(String key);

  /// Writing an empty value deletes the entry: a cleared field must not
  /// leave a stale credential in the keychain.
  Future<void> write(String key, String value);
}

/// Non-secrets only.
abstract class PrefsStore {
  const PrefsStore();

  Future<String?> read(String key);

  /// Writing an empty value deletes the entry, exactly as [SecretStore.write]
  /// does. The asymmetry ran the other way until T-0082: a cleared field left
  /// a `''` in preferences that outlived the session and that every `?? default`
  /// reading it stepped straight over.
  Future<void> write(String key, String value);
}

class SecureSecretStore extends SecretStore {
  const SecureSecretStore([this._storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) => value.isEmpty
      ? _storage.delete(key: key)
      : _storage.write(key: key, value: value);
}

class SharedPrefsStore extends PrefsStore {
  const SharedPrefsStore();

  @override
  Future<String?> read(String key) async =>
      (await SharedPreferences.getInstance()).getString(key);

  @override
  Future<void> write(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    value.isEmpty ? await prefs.remove(key) : await prefs.setString(key, value);
  }
}

/// Loads and saves [ProviderSettings], routing each field to the backend
/// its sensitivity demands.
class SettingsStore {
  const SettingsStore({
    this.secrets = const SecureSecretStore(),
    this.prefs = const SharedPrefsStore(),
  });

  final SecretStore secrets;
  final PrefsStore prefs;

  // Secret keys.
  static const keyAnthropicApiKey = 'anthropic_api_key';
  static const keyOpenAiApiKey = 'openai_compatible_api_key';
  static const keyIgdbClientId = 'igdb_client_id';
  static const keyIgdbClientSecret = 'igdb_client_secret';

  // Plain preference keys.
  static const keyBackend = 'vision_backend';
  static const keyOllamaUrl = 'ollama_url';
  static const keyOllamaModel = 'ollama_model';
  static const keyOpenAiBaseUrl = 'openai_compatible_base_url';
  static const keyOpenAiModel = 'openai_compatible_model';
  // A model name is configuration, not a credential -- same reasoning as the
  // endpoint's model above, and the reason it sits on this side of the split.
  static const keyAnthropicModel = 'anthropic_model';
  // `cloud_fallback` was written here until T-0061. It is deliberately not
  // read back: there is no second reader left for it to switch on.

  /// Deliberately not a [ProviderSettings] field: that class is the provider
  /// contract (backend, URLs, models, keys) and is handed to
  /// `ProviderPolicy.build`, which has no business seeing a UI preference.
  /// Its own key, read and written on its own, keeps the two apart.
  static const keyThemeMode = 'theme_mode';

  /// Every non-secret here reads a stored `''` as the absent value, so a
  /// preferences file written before T-0082 heals on the next launch rather
  /// than needing the user to notice and re-save.
  Future<ProviderSettings> load() async {
    final backendName = await prefs.read(keyBackend);
    return ProviderSettings(
      // A stored name no offered backend answers to falls back to the
      // default. It used to catch a platform refusing one of them as well;
      // since T-0361 none does, so what is left is a preference written by a
      // build that named them differently.
      backend: _backendFrom(backendName),
      // Passed through null and all: the defaults for these two are
      // [ProviderSettings]'s, which also decides what a stored `''` means, and
      // naming them here as well was the second copy of that rule.
      ollamaUrl: await prefs.read(keyOllamaUrl),
      ollamaModel: await prefs.read(keyOllamaModel),
      openAiBaseUrl: await prefs.read(keyOpenAiBaseUrl) ?? '',
      openAiModel: await prefs.read(keyOpenAiModel) ?? '',
      anthropicModel: await prefs.read(keyAnthropicModel) ?? '',
      anthropicApiKey: await secrets.read(keyAnthropicApiKey) ?? '',
      openAiApiKey: await secrets.read(keyOpenAiApiKey) ?? '',
      igdbClientId: await secrets.read(keyIgdbClientId) ?? '',
      igdbClientSecret: await secrets.read(keyIgdbClientSecret) ?? '',
    );
  }

  Future<void> save(ProviderSettings settings) async {
    await prefs.write(keyBackend, settings.backend.name);
    await prefs.write(keyOllamaUrl, settings.ollamaUrl);
    await prefs.write(keyOllamaModel, settings.ollamaModel);
    await prefs.write(keyOpenAiBaseUrl, settings.openAiBaseUrl);
    await prefs.write(keyOpenAiModel, settings.openAiModel);
    await prefs.write(keyAnthropicModel, settings.anthropicModel);
    await secrets.write(keyAnthropicApiKey, settings.anthropicApiKey);
    await secrets.write(keyOpenAiApiKey, settings.openAiApiKey);
    await secrets.write(keyIgdbClientId, settings.igdbClientId);
    await secrets.write(keyIgdbClientSecret, settings.igdbClientSecret);
  }

  /// Loading must never fail the app start: a missing keychain entry or an
  /// unreadable prefs file leaves the user with defaults and a settings
  /// screen, not a crash on a black window.
  Future<ProviderSettings> loadOrDefaults() async {
    try {
      return await load();
    } on Object {
      return ProviderSettings();
    }
  }

  /// Same posture as [loadOrDefaults]: an unreadable preference costs the
  /// user their theme choice, never the app start.
  Future<ThemeMode> loadThemeModeOrDefault() async {
    try {
      return switch (await prefs.read(keyThemeMode)) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
    } on Object {
      return ThemeMode.system;
    }
  }

  Future<void> saveThemeMode(ThemeMode mode) =>
      prefs.write(keyThemeMode, mode.name);

  static VisionBackend? _backendFrom(String? name) {
    final backend = switch (name) {
      'local' => VisionBackend.local,
      'cloud' => VisionBackend.cloud,
      'openAiCompatible' => VisionBackend.openAiCompatible,
      _ => null,
    };
    return ProviderPolicy.available.contains(backend) ? backend : null;
  }
}
