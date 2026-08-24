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

/// The page that issues both TMDB credentials -- which is the reason the
/// field below has to name the one it wants.
const tmdbApiSettingsUrl = 'https://www.themoviedb.org/settings/api';

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
  late final _tmdbToken =
      TextEditingController(text: widget.settings.tmdbToken);

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
      _tmdbToken,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _copyLink(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Link copied: $url')),
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
      ..igdbClientSecret = _igdbSecret.text.trim()
      ..tmdbToken = _tmdbToken.text.trim();

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
    final onThisMachine = ProviderPolicy.localServerIsThisMachine;
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
              onThisMachine
                  ? 'Local runs entirely on this machine and needs no keys. '
                      'Endpoint sends the photos to any OpenAI-compatible '
                      'service you name, with your own key. Cloud needs your '
                      'own Anthropic API key.'
                  : 'This device runs no vision model of its own: on-device '
                      'models are too weak for shelf spines. Local instead '
                      'sends the photos to an Ollama server you name on your '
                      'own network, and needs no keys. Endpoint sends them to '
                      'any OpenAI-compatible service you name, with your own '
                      'key; Cloud needs your own Anthropic key.',
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

            // Rendered on every platform since T-0361. Where the server is
            // another machine the paragraph below IS the field: this app has
            // no address to offer, and two of the three things needed are on
            // the other machine rather than on this screen.
            const _SectionTitle('Local (Ollama)'),
            if (!onThisMachine)
              Text(
                'This device runs no model. Local sends each photo to an '
                'Ollama server on your own network, usually the desktop, and '
                'the reading happens there. That machine needs Ollama running '
                'and listening on the network rather than on loopback only '
                '(OLLAMA_HOST=0.0.0.0), and its address goes below.',
                key: const Key('settings-ollama-lan-note'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            TextField(
              key: const Key('settings-ollama-url'),
              controller: _ollamaUrl,
              decoration: InputDecoration(
                labelText: onThisMachine
                    ? 'Ollama server URL'
                    : 'Ollama server URL (the other machine, not this one)',
                // T-0082 made the hint the default, because clearing the field
                // resolves to it. Where there is no default -- loopback on a
                // phone is the phone -- the hint may not look like one: it
                // shows the shape instead, and a cleared field stays cleared
                // and blocks the scan by name rather than resolving to an
                // address nobody chose. The port is read off the default so
                // this is not a second copy of it.
                hintText: onThisMachine
                    ? defaultOllamaUrl
                    : 'http://ADDRESS:${Uri.parse(defaultOllamaUrl).port}',
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

            const _SectionTitle('IGDB (optional)'),
            // Names the mode rather than describing a blank field, and names
            // where its control is -- the same shape as the backend line at
            // the top of this screen, and for the same reason (T-0230).
            //
            // "you fix them during review" stood here until then and was not
            // true of a run with no credentials: the resolve stage is skipped
            // outright, so those rows arrive with no candidate list and there
            // is nothing on the review screen to pick from.
            //
            // "Without them a scan is a Keyless run" stood here until T-0367
            // and stopped being true the moment a TMDB token could key one on
            // its own. What a blank pair costs is a GAME row, and the section
            // below has said exactly that about a blank token since T-0363 --
            // so the two now say the same shape of thing about their own kind,
            // and neither speaks for the whole run.
            Text(
              'Optional, and about games: needed for the Tonkatsu .xcoll '
              'export, which carries IGDB ids for them. Without the pair a '
              'game row keeps the title it was read with -- CSV yes, .xcoll '
              'no. Looking nothing up at all is the '
              '${TitleMatching.keyless.label} mode, named and chosen on the '
              'scan screen.',
              key: const Key('settings-igdb-optional'),
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
                onPressed: () => _copyLink(twitchConsoleUrl),
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

            // Films, and the third credential (T-0363). The CLI has read one
            // out of the environment since T-0308 and this screen had no
            // field, which is the split the owner called a strange dualism --
            // nobody had decided it.
            //
            // Optional in the same sense the pair above is, and said in the
            // same words: what a blank one costs is named here rather than in
            // a README, and it is what every film row costs today.
            const _SectionTitle('TMDB (optional)'),
            Text(
              'Optional, and only about films: without it a film row keeps '
              'the title it was read with -- CSV yes, Tonkatsu .xcoll no -- '
              'exactly as a game row is without the IGDB pair above. Games '
              'are unaffected either way.',
              key: const Key('settings-tmdb-optional'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('settings-tmdb-console-link'),
                onPressed: () => _copyLink(tmdbApiSettingsUrl),
                icon: const Icon(Icons.content_copy, size: 16),
                label: const Text('Get it at $tmdbApiSettingsUrl'),
              ),
            ),
            // The label and the helper both name WHICH credential, because
            // that page issues two and the wrong one answers 401 with nothing
            // to read. Why this app wants the read token is in
            // `tmdbTokenVariable` (shelfscan_core) and is a privacy argument:
            // the v3 key is accepted only as a query parameter, so it would
            // sit in every URL an error might quote.
            _SecretField(
              fieldKey: const Key('settings-tmdb-token'),
              controller: _tmdbToken,
              label: 'TMDB API Read Access Token',
              help: 'The long one that starts eyJ, not the short "API Key" on '
                  'the same page -- that one travels in the URL, so this app '
                  'does not use it. Stored in the OS keychain, never in a '
                  'file in this app.',
            ),
            // Quoted, not composed. TMDB's terms mandate this sentence word
            // for word, with only the bracketed word of "This [website,
            // program, service, application, product]" substituted -- T-0379
            // shipped a paraphrase of it and T-0383 replaced it. Do not
            // reword it to fit the screen; the test holds its own literal
            // copy rather than importing this string, so an edit here is red
            // there.
            //
            // Here rather than on the review screen: this is the only place
            // in the app a person passes through to make the API reachable at
            // all, and the review screen carries rows for every run, nearly
            // all of which touch no catalogue. The READMEs carry the same
            // sentence for a reader who never opens Settings.
            const SizedBox(height: 8),
            Text(
              'This application uses TMDB and the TMDB APIs but is not '
              'endorsed, certified, or otherwise approved by TMDB.',
              key: const Key('settings-tmdb-attribution'),
              style: Theme.of(context).textTheme.bodySmall,
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
      VisionBackend.openAiCompatible => Icons.dns,
      VisionBackend.cloud => Icons.cloud,
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
          helperMaxLines: 4,
          suffixIcon: IconButton(
            tooltip: _obscured ? 'Show' : 'Hide',
            icon: Icon(_obscured ? Icons.visibility : Icons.visibility_off),
            onPressed: () => setState(() => _obscured = !_obscured),
          ),
        ),
      );
}
