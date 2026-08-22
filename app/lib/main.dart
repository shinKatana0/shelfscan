/// shelfscan Flutter app -- thin shell over shelfscan_core.
///
/// Targets: Windows + Android. Platform folders are not committed;
/// generate them once after cloning, from `app/`:
///   flutter create --platforms=windows,android .
///   rm test/widget_test.dart README.md
///   flutter pub get
///
/// The delete is part of the step, not tidying up: `flutter create` also
/// writes the counter template's `test/widget_test.dart`, which pumps
/// `MyApp` -- ours is [ShelfscanApp] -- so `flutter test` fails to compile
/// it. Neither leftover is gitignored on purpose: if a later
/// `flutter create` brings them back, `git status` is the only warning.
///
/// Windows also needs two things `flutter doctor` does not check; they are
/// in README.md under "Windows: two prerequisites".
///
/// The app owns only: photo picking, settings (API keys, theme), progress
/// UI, the review screen, and saving/sharing the exported file. The whole
/// pipeline lives in shelfscan_core.
library;

import 'package:flutter/material.dart';

import 'provider_config.dart';
import 'screens/scan_screen.dart';
import 'settings_store.dart';
import 'title_aliases.dart';

Future<void> main() async {
  // Settings and the alias table are read once, before the first frame:
  // every screen then works with plain values instead of awaiting the
  // keychain or the asset bundle mid-scan.
  WidgetsFlutterBinding.ensureInitialized();
  const store = SettingsStore();
  final settings = await store.loadOrDefaults();
  final themeMode = await store.loadThemeModeOrDefault();
  final aliases = await loadTitleAliases();
  runApp(ShelfscanApp(
    settings: settings,
    store: store,
    aliases: aliases,
    themeMode: themeMode,
  ));
}

/// The live theme choice, published above [MaterialApp] so the settings
/// screen -- pushed several routes below it -- can change it without a
/// restart and without every screen in between passing a callback down.
class ThemeModeScope extends InheritedNotifier<ValueNotifier<ThemeMode>> {
  const ThemeModeScope({
    super.key,
    required ValueNotifier<ThemeMode> super.notifier,
    required super.child,
  });

  /// Null when the widget under test was pumped without an app around it.
  static ValueNotifier<ThemeMode>? of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ThemeModeScope>()
      ?.notifier;
}

class ShelfscanApp extends StatefulWidget {
  const ShelfscanApp({
    super.key,
    required this.settings,
    this.store = const SettingsStore(),
    this.aliases,
    this.themeMode = ThemeMode.system,
  });

  final ProviderSettings settings;
  final SettingsStore store;

  /// Regional-title aliases from the bundled data file; null leaves the
  /// resolver on its built-in fallback.
  final Map<String, String>? aliases;

  final ThemeMode themeMode;

  @override
  State<ShelfscanApp> createState() => _ShelfscanAppState();
}

class _ShelfscanAppState extends State<ShelfscanApp> {
  late final _themeMode = ValueNotifier(widget.themeMode);

  @override
  void dispose() {
    _themeMode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ThemeModeScope(
        notifier: _themeMode,
        child: _ShelfscanMaterialApp(
          settings: widget.settings,
          store: widget.store,
          aliases: widget.aliases,
        ),
      );
}

/// Split out so that reading the scope registers this widget -- and only
/// this widget -- as its dependent: a theme change then rebuilds
/// [MaterialApp] rather than the state that owns the notifier.
class _ShelfscanMaterialApp extends StatelessWidget {
  const _ShelfscanMaterialApp({
    required this.settings,
    required this.store,
    required this.aliases,
  });

  final ProviderSettings settings;
  final SettingsStore store;
  final Map<String, String>? aliases;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'shelfscan',
      theme: ThemeData(colorSchemeSeed: appSeedColor, useMaterial3: true),
      darkTheme: ThemeData(
        colorSchemeSeed: appSeedColor,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      themeMode: ThemeModeScope.of(context)?.value ?? ThemeMode.system,
      home: ScanScreen(settings: settings, store: store, aliases: aliases),
    );
  }
}

/// One seed for both schemes, so light and dark are the same app.
const appSeedColor = Colors.teal;

extension ThemeModeLabel on ThemeMode {
  String get label => switch (this) {
        ThemeMode.system => 'System',
        ThemeMode.light => 'Light',
        ThemeMode.dark => 'Dark',
      };
}
