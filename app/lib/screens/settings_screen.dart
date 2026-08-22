/// Settings: which vision backend to use, and the user's own API keys.
///
/// BYOK (decision 0011): shelfscan ships no credentials and runs no proxy, so
/// this screen is the only way keys ever enter the app. Everything typed
/// here is persisted by [SettingsStore] -- secrets to the OS keychain, the
/// rest to preferences.
///
/// The screen knows nothing about platforms: it renders whatever
/// [ProviderPolicy] offers. That keeps the policy in one file.
///
/// It configures every backend and selects none (T-0115). Choosing one is the
/// scan screen's switch, which writes the same `vision_backend` preference
/// this screen's Save does; the copy that used to live here staged the choice
/// until Save, so one stored value had two meanings of a tap. What stays is
/// the statement of which backend is in force and what it costs.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart' show ThemeModeScope, ThemeModeLabel;
import '../provider_config.dart';
import '../settings_store.dart';

/// Where a user registers the Twitch application IGDB credentials come from.
/// Also documented in README.md; keep the two in step.
const twitchConsoleUrl = 'https://dev.twitch.tv/console/apps';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.settings,
    required this.store,
  });

  /// Edited in place on save, so the caller sees the new values without
  /// re-reading storage (same style as the review screen's document).
  final ProviderSettings settings;
  final SettingsStore store;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final _ollamaUrl =
      TextEditingController(text: widget.settings.ollamaUrl);
  late final _ollamaModel =
      TextEditingController(text: widget.settings.ollamaModel);
  late final _anthropicKey =
      TextEditingController(text: widget.settings.anthropicApiKey);
  late final _anthropicModel =
      TextEditingController(text: widget.settings.anthropicModel);
  late final _openAiUrl =
      TextEditingController(text: widget.settings.openAiBaseUrl);
  late final _openAiModel =
      TextEditingController(text: widget.settings.openAiModel);
  late final _openAiKey =
      TextEditingController(text: widget.settings.openAiApiKey);
  late final _igdbId =
      TextEditingController(text: widget.settings.igdbClientId);
  late final _igdbSecret =
      TextEditingController(text: widget.settings.igdbClientSecret);

  bool _saving = false;

  @override
  void dispose() {
    for (final c in [
      _ollamaUrl,
      _ollamaModel,
      _anthropicKey,
      _anthropicModel,
      _openAiUrl,
      _openAiModel,
      _openAiKey,
      _igdbId,
      _igdbSecret,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _copyConsoleUrl() async {
    await Clipboard.setData(const ClipboardData(text: twitchConsoleUrl));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Link copied: $twitchConsoleUrl')),
    );
  }

  /// Applied and persisted on the spot rather than on Save: the whole app
  /// has already repainted by the time the finger leaves the button, so a
  /// choice that Back would silently undo would be a lie about what the
  /// user is looking at.
  Future<void> _setThemeMode(ThemeMode mode) async {
    ThemeModeScope.of(context)?.value = mode;
    try {
      await widget.store.saveThemeMode(mode);
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Theme applied, but not saved for next time: $e')),
      );
    }
  }

  Future<void> _save() async {
    // No `backend`: this screen does not choose one, so Save carries through
    // whatever the scan screen's switch put there (T-0115).
    final settings = widget.settings
      ..ollamaUrl = _ollamaUrl.text.trim()
      ..ollamaModel = _ollamaModel.text.trim()
      ..anthropicApiKey = _anthropicKey.text.trim()
      ..anthropicModel = _anthropicModel.text.trim()
      ..openAiBaseUrl = _openAiUrl.text.trim()
      ..openAiModel = _openAiModel.text.trim()
      ..openAiApiKey = _openAiKey.text.trim()
      ..igdbClientId = _igdbId.text.trim()
      ..igdbClientSecret = _igdbSecret.text.trim();

    setState(() => _saving = true);
    String? error;
    try {
      await widget.store.save(settings);
    } on Object catch (e) {
      // A keychain that refuses to store must not look like a success:
      // the user would restart into an empty settings screen.
      error = 'Could not save settings: $e';
    }
    if (!mounted) return;
    setState(() => _saving = false);
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    Navigator.of(context).pop(true);
  }

  /// What the backend in force costs and what to do about it, asked of the
  /// policy rather than decided here (ARCHITECTURE.md keeps that in one file).
  /// [BackendCheck.backend] rather than `settings.backend`, so a stored choice
  /// this platform disallows is described as the one a scan would really use.
  ///
  /// The blocker half is deliberately unread here: every one of its strings
  /// ends "-- add it in Settings", which is where the reader already is. That
  /// half is answered on the scan screen, where the fix is a screen away.
  BackendCheck get _inForce => ProviderPolicy.check(widget.settings);

  @override
  Widget build(BuildContext context) {
    final localAllowed = ProviderPolicy.localAllowed;
    final inForce = _inForce;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      // A scroll view rather than a ListView: the form is short and every
      // field must exist even when scrolled out of sight.
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SectionTitle('Vision backend'),
            // Where the switch is, not just which backend won: the advice
            // inside the warning below says "switch to Local", and an
            // instruction whose control is on another screen has to name it.
            Row(
              children: [
                Icon(backendIcon(inForce.backend), size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Scanning with ${inForce.backend.label} -- chosen with the '
                    "switch in the scan screen's toolbar.",
                    key: const Key('settings-backend-in-force'),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              localAllowed
                  ? 'Local runs entirely on this machine and needs no keys. '
                      'Cloud needs your own Anthropic API key. Endpoint '
                      'sends the photos to any OpenAI-compatible service you '
                      'name, with your own key.'
                  : 'This device is cloud-only: on-device models are too weak '
                      'for shelf spines. Cloud needs your own Anthropic key; '
                      'Endpoint sends the photos to any OpenAI-compatible '
                      'service you name, with your own key.',
              style: Theme.of(context).textTheme.bodySmall,
            ),

            // The warning belongs where the choice is acted on, not in a
            // README (decision 0011): by the time a photo of a private home
            // has been sent to a free tier that trains on it, an explanation
            // elsewhere is too late. Every backend that uploads says so, not
            // just the endpoint one (T-0058). It stays on this screen after
            // T-0115 took the selector off it, because the key that turns the
            // upload on is typed here -- and because this was the only
            // sentence on the screen saying photos are uploaded at all, which
            // it silently was not for the whole of T-0061.
            if (inForce.warning case final warning?)
              _PrivacyWarning(warning, inForce.advice),

            // Ollama is a desktop-only capability; on a cloud-only platform
            // these fields would be dead controls, so they are not rendered.
            if (localAllowed) ...[
              const _SectionTitle('Local (Ollama)'),
              TextField(
                key: const Key('settings-ollama-url'),
                controller: _ollamaUrl,
                decoration: const InputDecoration(
                  labelText: 'Ollama server URL',
                  hintText: defaultOllamaUrl,
                ),
              ),
              TextField(
                key: const Key('settings-ollama-model'),
                controller: _ollamaModel,
                decoration: const InputDecoration(
                  labelText: 'Vision model',
                  hintText: defaultOllamaModel,
                ),
              ),
            ],

            const _SectionTitle('Cloud (Anthropic)'),
            _SecretField(
              fieldKey: const Key('settings-anthropic-key'),
              controller: _anthropicKey,
              label: 'Anthropic API key',
              help: 'Your own key from console.anthropic.com. Stored in the '
                  'OS keychain, never in a file in this app.',
            ),
            // Optional, and it has to stay optional: nobody should need to
            // know a model id to start. But a pinned cloud id is not a frozen
            // artifact -- Anthropic publishes retirement dates -- so the user
            // paying with their own key needs a way off the built-in default
            // without a new build (T-0067).
            //
            // The sampling sentence is the whole reason this field carries
            // helper text at all. Naming a model here drops the temperature
            // this app would otherwise state, because newer Claude models
            // reject the parameter outright; the alternative was a 400 the
            // user would read as "my key is broken". Where the ids come from
            // is named rather than listed, for the same reason the default is
            // not durable.
            TextField(
              key: const Key('settings-anthropic-model'),
              controller: _anthropicModel,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Claude model (optional)',
                helperText: 'Blank uses the built-in default. Current ids: the '
                    'Models overview at platform.claude.com/docs, or GET '
                    'api.anthropic.com/v1/models with the key above. A model '
                    'you name is sent without a temperature (newer Claude '
                    'models reject one), so its sampling is Anthropic\'s '
                    'rather than this app\'s -- note that with any numbers you '
                    'record.',
                helperMaxLines: 6,
              ),
            ),

            const _SectionTitle('Endpoint (any OpenAI-compatible service)'),
            Text(
              'Groq, OpenRouter, Mistral, GitHub Models, Cerebras and '
              "Gemini's OpenAI-compatible endpoint all speak the same API. "
              'Paste the base URL up to and including the version segment.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            TextField(
              key: const Key('settings-openai-url'),
              controller: _openAiUrl,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'API endpoint (base URL)',
                helperText: openAiEndpointExamples,
                helperMaxLines: 3,
              ),
            ),
            TextField(
              key: const Key('settings-openai-model'),
              controller: _openAiModel,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Vision model',
                helperText: 'Exactly as the service names it, e.g. '
                    'gemini-2.5-flash or meta-llama/llama-4-scout-17b',
                helperMaxLines: 3,
              ),
            ),
            _SecretField(
              fieldKey: const Key('settings-openai-key'),
              controller: _openAiKey,
              label: 'API key for this endpoint',
              help: 'Your own key from that service. Stored in the OS '
                  'keychain, never in a file in this app.',
            ),

            const _SectionTitle('IGDB (optional)'),
            Text(
              'Optional: needed only for the Tonkatsu .xcoll export, which '
              'carries IGDB ids. Without them the scan still runs; games '
              'arrive unresolved and you fix them during review.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            // "Where do I get this" answered in place. IGDB is
            // Twitch-authenticated, so the credentials come from a Twitch
            // application -- not obvious enough to leave to a search.
            //
            // Copy-to-clipboard rather than opening a browser: launching a
            // URL needs a plugin this shell does not depend on, and adding
            // one would mean plugin registration in the generated platform
            // folders. The address itself is the affordance.
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('settings-igdb-console-link'),
                onPressed: () => _copyConsoleUrl(),
                icon: const Icon(Icons.content_copy, size: 16),
                label: const Text('Get them at $twitchConsoleUrl'),
              ),
            ),
            _SecretField(
              fieldKey: const Key('settings-igdb-id'),
              controller: _igdbId,
              label: 'IGDB client id',
            ),
            _SecretField(
              fieldKey: const Key('settings-igdb-secret'),
              controller: _igdbSecret,
              label: 'IGDB client secret',
            ),

            const _SectionTitle('Appearance'),
            SegmentedButton<ThemeMode>(
              key: const Key('settings-theme'),
              segments: [
                for (final mode in ThemeMode.values)
                  ButtonSegment(
                    value: mode,
                    icon: Icon(themeModeIcon(mode)),
                    label: Text(mode.label),
                  ),
              ],
              // Read from the scope, not from local state: this is the one
              // control whose effect is visible outside its own screen.
              selected: {ThemeModeScope.of(context)?.value ?? ThemeMode.system},
              onSelectionChanged: (selection) => _setThemeMode(selection.first),
            ),

            const SizedBox(height: 24),
            FilledButton.icon(
              key: const Key('settings-save'),
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save),
              label: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

IconData backendIcon(VisionBackend backend) => switch (backend) {
      VisionBackend.local => Icons.computer,
      VisionBackend.cloud => Icons.cloud,
      VisionBackend.openAiCompatible => Icons.dns,
    };

IconData themeModeIcon(ThemeMode mode) => switch (mode) {
      ThemeMode.system => Icons.brightness_auto,
      ThemeMode.light => Icons.light_mode,
      ThemeMode.dark => Icons.dark_mode,
    };

/// What the backend named above costs, and what the user can do instead.
/// Both texts are [ProviderPolicy]'s, never this screen's (T-0058): the two
/// said different things for the whole of T-0040.
///
/// Heavier than the scan screen's plain coloured row, and deliberately so:
/// there the notice sits a finger's width from the Scan button and is read
/// on the way past, here it is permanent furniture among a dozen paragraphs
/// of bodySmall helper text that it must not be mistaken for. The tone is
/// the tonal `errorContainer` pair rather than `error` itself -- choosing a
/// cloud backend is a legitimate decision, not a failure (T-0045 item 22).
///
/// The advice is a second line inside the same box rather than a fourth
/// sentence of the paragraph above it (T-0070): on the endpoint branch the
/// risk is already two sentences, and the one thing the reader is meant to
/// be able to act on should not be the tail of the longest paragraph on the
/// screen. Inside the box, because an action that drifts away from the
/// warning it answers stops being an answer.
class _PrivacyWarning extends StatelessWidget {
  const _PrivacyWarning(this.text, this.advice);

  final String text;
  final String? advice;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = scheme.onErrorContainer;
    return Container(
      key: const Key('settings-privacy-warning'),
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  key: const Key('settings-privacy-risk'),
                  style: TextStyle(color: color),
                ),
                if (advice case final advice?) ...[
                  const SizedBox(height: 8),
                  Text(
                    advice,
                    key: const Key('settings-privacy-advice'),
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: color, fontWeight: FontWeight.w600),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 8),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );
}

/// Obscured by default, with a reveal toggle: keys are long and typo-prone,
/// but they must not sit on screen in plain text by default.
class _SecretField extends StatefulWidget {
  const _SecretField({
    required this.fieldKey,
    required this.controller,
    required this.label,
    this.help,
  });

  final Key fieldKey;
  final TextEditingController controller;
  final String label;
  final String? help;

  @override
  State<_SecretField> createState() => _SecretFieldState();
}

class _SecretFieldState extends State<_SecretField> {
  bool _obscured = true;

  @override
  Widget build(BuildContext context) => TextField(
        key: widget.fieldKey,
        controller: widget.controller,
        obscureText: _obscured,
        autocorrect: false,
        enableSuggestions: false,
        decoration: InputDecoration(
          labelText: widget.label,
          helperText: widget.help,
          helperMaxLines: 3,
          suffixIcon: IconButton(
            tooltip: _obscured ? 'Show' : 'Hide',
            icon: Icon(_obscured ? Icons.visibility : Icons.visibility_off),
            onPressed: () => setState(() => _obscured = !_obscured),
          ),
        ),
      );
}
