/// Tests for the theme preference (T-0043).
///
/// The three things that can silently break: the default quietly stops
/// being System, the settings screen changes a value nobody rebuilds on,
/// and the choice does not survive a restart.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelfscan_app/main.dart';
import 'package:shelfscan_app/provider_config.dart';
import 'package:shelfscan_app/settings_store.dart';

import 'settings_store_test.dart' show RecordingStore;

MaterialApp _app(WidgetTester tester) =>
    tester.widget<MaterialApp>(find.byType(MaterialApp));

/// The scheme the app is actually painting with, read from a context below
/// [MaterialApp] rather than from its `theme` field -- that is what decides
/// whether the user sees a dark screen.
ColorScheme _liveScheme(WidgetTester tester) =>
    Theme.of(tester.element(find.byType(Scaffold).first)).colorScheme;

Future<void> _openSettings(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('open-settings')));
  await tester.pumpAndSettle();
}

/// The form is taller than the test viewport; the theme control lives at
/// the bottom of it.
Future<void> _tapSegment(WidgetTester tester, String label) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  final target = find.descendant(
    of: find.byKey(const Key('settings-theme')),
    matching: find.text(label),
  );
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() => ProviderPolicy.debugLocalAllowedOverride = null);

  _contrastGroup();

  group('the app theme', () {
    testWidgets('defaults to System and offers a dark scheme from the same '
        'seed', (tester) async {
      await tester.pumpWidget(ShelfscanApp(settings: ProviderSettings()));
      await tester.pumpAndSettle();

      final app = _app(tester);
      expect(app.themeMode, ThemeMode.system);
      expect(app.darkTheme, isNotNull);
      expect(app.theme!.brightness, Brightness.light);
      expect(app.darkTheme!.brightness, Brightness.dark);
      // Same app in both: one seed, two schemes.
      expect(app.theme!.colorScheme.primary,
          ThemeData(colorSchemeSeed: appSeedColor).colorScheme.primary);
      expect(
          app.darkTheme!.colorScheme.primary,
          ThemeData(colorSchemeSeed: appSeedColor, brightness: Brightness.dark)
              .colorScheme
              .primary);
    });

    testWidgets('a stored choice is the one the first frame uses',
        (tester) async {
      await tester.pumpWidget(ShelfscanApp(
        settings: ProviderSettings(),
        themeMode: ThemeMode.dark,
      ));
      await tester.pumpAndSettle();

      expect(_app(tester).themeMode, ThemeMode.dark);
      expect(_liveScheme(tester).brightness, Brightness.dark);
    });
  });

  group('choosing a theme', () {
    testWidgets('Dark repaints the app immediately, without a restart or '
        'leaving the screen', (tester) async {
      ProviderPolicy.debugLocalAllowedOverride = true;
      final prefs = RecordingStore();
      await tester.pumpWidget(ShelfscanApp(
        settings: ProviderSettings(),
        store: SettingsStore(secrets: RecordingStore(), prefs: prefs),
      ));
      await tester.pumpAndSettle();
      expect(_liveScheme(tester).brightness, Brightness.light,
          reason: 'the test platform reports a light system theme');

      await _openSettings(tester);
      await _tapSegment(tester, 'Dark');

      // Still on the settings screen, and it is already dark.
      expect(find.byKey(const Key('settings-theme')), findsOneWidget);
      expect(_app(tester).themeMode, ThemeMode.dark);
      expect(_liveScheme(tester).brightness, Brightness.dark);
      expect(prefs.values[SettingsStore.keyThemeMode], 'dark');
    });

    testWidgets('all three modes are offered and Light comes back',
        (tester) async {
      ProviderPolicy.debugLocalAllowedOverride = true;
      final prefs = RecordingStore();
      await tester.pumpWidget(ShelfscanApp(
        settings: ProviderSettings(),
        store: SettingsStore(secrets: RecordingStore(), prefs: prefs),
        themeMode: ThemeMode.dark,
      ));
      await tester.pumpAndSettle();
      await _openSettings(tester);

      for (final label in ['System', 'Light', 'Dark']) {
        expect(
            find.descendant(
              of: find.byKey(const Key('settings-theme')),
              matching: find.text(label),
            ),
            findsOneWidget);
      }

      await _tapSegment(tester, 'Light');
      expect(_liveScheme(tester).brightness, Brightness.light);
      expect(prefs.values[SettingsStore.keyThemeMode], 'light');

      await _tapSegment(tester, 'System');
      expect(_app(tester).themeMode, ThemeMode.system);
      expect(prefs.values[SettingsStore.keyThemeMode], 'system');
    });

    testWidgets('the choice is applied even when it cannot be stored',
        (tester) async {
      ProviderPolicy.debugLocalAllowedOverride = true;
      await tester.pumpWidget(ShelfscanApp(
        settings: ProviderSettings(),
        store: const SettingsStore(
            secrets: _ThrowingStore(), prefs: _ThrowingStore()),
      ));
      await tester.pumpAndSettle();
      await _openSettings(tester);
      await _tapSegment(tester, 'Dark');

      expect(_liveScheme(tester).brightness, Brightness.dark);
      // Loud, not silent (decision 0012): a preference that did not persist is
      // named rather than discovered at the next launch.
      expect(find.textContaining('not saved for next time'), findsOneWidget);
    });
  });

  group('the stored preference', () {
    test('round-trips through the plain preferences backend', () async {
      for (final mode in ThemeMode.values) {
        final secrets = RecordingStore();
        final prefs = RecordingStore();
        await SettingsStore(secrets: secrets, prefs: prefs)
            .saveThemeMode(mode);

        expect(
          await SettingsStore(secrets: secrets, prefs: prefs)
              .loadThemeModeOrDefault(),
          mode,
        );
        // A theme is not a credential and must never be written as one.
        expect(secrets.writes, isEmpty);
        expect(prefs.values.keys, [SettingsStore.keyThemeMode]);
      }
    });

    test('nothing stored means System', () async {
      expect(
        await SettingsStore(secrets: RecordingStore(), prefs: RecordingStore())
            .loadThemeModeOrDefault(),
        ThemeMode.system,
      );
    });

    test('a garbled value falls back to System', () async {
      final prefs = RecordingStore();
      await prefs.write(SettingsStore.keyThemeMode, 'midnight');

      expect(
        await SettingsStore(secrets: RecordingStore(), prefs: prefs)
            .loadThemeModeOrDefault(),
        ThemeMode.system,
      );
    });

    test('an unreadable preference never blocks app start', () async {
      const store =
          SettingsStore(secrets: _ThrowingStore(), prefs: _ThrowingStore());

      expect(await store.loadThemeModeOrDefault(), ThemeMode.system);
    });
  });
}

/// WCAG relative luminance.
double _luminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) +
      0.7152 * channel(c.g) +
      0.0722 * channel(c.b);
}

double _contrast(Color a, Color b) {
  final la = _luminance(a), lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// Guards what a running app would otherwise have to be squinted at:
/// the review screen's approve/reject icons are the only marks in the app
/// picked for meaning rather than taken from the scheme.
void _contrastGroup() {
  group('the review approve/reject marks', () {
    test('clear the 3:1 bar for a non-text control on both surfaces', () {
      for (final brightness in Brightness.values) {
        final scheme =
            ThemeData(colorSchemeSeed: appSeedColor, brightness: brightness)
                .colorScheme;

        for (final role in {
          'primary (approved)': scheme.primary,
          'error (rejected)': scheme.error,
        }.entries) {
          expect(_contrast(role.value, scheme.surface), greaterThan(3.0),
              reason: '${role.key} on $brightness surface');
        }
      }
    });

    test('Colors.green -- the value they used to be -- would not', () {
      // Measured 2.65:1 on the light surface, which is why this moved to
      // scheme roles rather than being left alone (T-0043).
      final light = ThemeData(colorSchemeSeed: appSeedColor).colorScheme;
      expect(_contrast(Colors.green, light.surface), lessThan(3.0));
    });
  });

  group('the scan panel\'s two classes of line', () {
    test('both clear the 4.5:1 text bar on both surfaces', () {
      // These are text and their icons, so the bar taken is the text one and
      // not the 3:1 a bare control gets. Measured 2026-08-17 on the seed's own
      // schemes (T-0222):
      //
      // | role | light (#f4fbf8) | dark (#0e1513) |
      // | --- | --- | --- |
      // | error -- a failure | 6.15:1 | 10.89:1 |
      // | onSurfaceVariant -- an exclusion | 8.87:1 | 10.89:1 |
      //
      // The exclusion line is the higher of the two on the light surface,
      // which is deliberate and is not the failure being outshouted: what
      // separates them is a heading in words first, a warning triangle
      // against a struck-through filter second, and hue third. Legibility is
      // not the axis either is quieter on -- neither line may be hard to read.
      for (final brightness in Brightness.values) {
        final scheme =
            ThemeData(colorSchemeSeed: appSeedColor, brightness: brightness)
                .colorScheme;

        for (final role in {
          'error (a failure)': scheme.error,
          'onSurfaceVariant (an exclusion)': scheme.onSurfaceVariant,
        }.entries) {
          expect(_contrast(role.value, scheme.surface), greaterThan(4.5),
              reason: '${role.key} on $brightness surface');
        }
      }
    });

    test('outline -- the dimmer role an exclusion could have taken -- would not',
        () {
      // 4.28:1 on the light surface, under the text bar. Recorded so the next
      // person reaching for a quieter grey knows this one was measured and
      // refused (T-0222).
      final light = ThemeData(colorSchemeSeed: appSeedColor).colorScheme;
      expect(_contrast(light.outline, light.surface), lessThan(4.5));
    });
  });
}

class _ThrowingStore implements SecretStore, PrefsStore {
  const _ThrowingStore();

  @override
  Future<String?> read(String key) async => throw StateError('prefs corrupt');

  @override
  Future<void> write(String key, String value) async =>
      throw StateError('prefs read-only');
}
