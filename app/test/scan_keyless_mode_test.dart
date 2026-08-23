/// The keyless run offered as a mode, before the scan (T-0230).
///
/// The bug this pins: a person could reach the keyless state only by leaving
/// the two IGDB fields blank in Settings and scanning. The CLI and the README
/// had both named it a path -- "Path A -- keyless" -- for as long as the app
/// had presented it as an absence.
///
/// Nothing here dials anything. Every sentence is decided from a
/// [ProviderSettings] in memory, which is the property [MatchingCheck] shares
/// with [BackendCheck]; the one test that runs a scan runs it against a fake
/// vision provider, and its resolver is a [SkipResolver], whose refusing http
/// client would throw if any IGDB traffic were attempted.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelfscan_app/provider_config.dart';
import 'package:shelfscan_app/screens/scan_screen.dart';
import 'package:shelfscan_app/settings_store.dart';
import 'package:shelfscan_core/shelfscan_core.dart';

import 'scan_wiring_test.dart' show FakeInputPicker, FakeVisionProvider;
import 'settings_store_test.dart' show RecordingStore;

SettingsStore _store() =>
    SettingsStore(secrets: RecordingStore(), prefs: RecordingStore());

ProviderSettings _withCredentials() =>
    ProviderSettings(igdbClientId: 'id', igdbClientSecret: 'secret');

Future<void> _pump(WidgetTester tester, ProviderSettings settings) =>
    tester.pumpWidget(MaterialApp(
      home: ScanScreen(
          settings: settings, store: _store(), picker: FakeInputPicker()),
    ));

/// The control is labelled, so the label is the handle -- and asserting on it
/// is also the check that the mode is named rather than described.
Future<void> _choose(WidgetTester tester, TitleMatching mode) async {
  await tester.tap(find.text(mode.label));
  // One pump: the consequence has to be on screen in the frame after the tap,
  // which it cannot be if anything was awaited to produce it.
  await tester.pump();
}

String _consequence(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const Key('title-matching-consequence')))
    .data!;

void main() {
  group('what the choice can know without spending anything', () {
    test('keyless is the same answer whether or not credentials exist', () {
      for (final settings in [ProviderSettings(), _withCredentials()]) {
        final check =
            ProviderPolicy.checkMatching(settings, TitleMatching.keyless);

        expect(check.keyless, isTrue);
        expect(check.unconfigured, isFalse);
        expect(check.consequence, keylessConsequence);
      }
    });

    test('asking to match with nothing registered degrades, it does not fail',
        () {
      final check =
          ProviderPolicy.checkMatching(ProviderSettings(), TitleMatching.igdb);

      // The difference from a backend: an unconfigured backend blocks a scan,
      // this one runs it keyless and says so.
      expect(check.keyless, isTrue);
      expect(check.unconfigured, isTrue);
      expect(check.consequence, contains('Settings'));
      expect(check.consequence, contains(TitleMatching.keyless.label));
    });

    test('asking to match with both halves present matches', () {
      final check =
          ProviderPolicy.checkMatching(_withCredentials(), TitleMatching.igdb);

      expect(check.matching, TitleMatching.igdb);
      expect(check.unconfigured, isFalse);
      expect(check.consequence, igdbConsequence);
    });

    // The wording may not promise keyless detection, and may not promise on a
    // phone what only a desktop can do. T-0229 is the other half; nothing
    // written here should have to be unwritten by it.
    test('no consequence claims the photos stay on the machine', () {
      for (final text in [keylessConsequence, igdbConsequence]) {
        for (final overclaim in ['offline', 'never leave', 'no model']) {
          expect(text, isNot(contains(overclaim)));
        }
      }
      expect(keylessConsequence, contains('vision backend'));
    });
  });

  group('the resolver a chosen mode produces', () {
    test('keyless skips the stage even with both credentials stored', () {
      expect(
        ProviderPolicy.buildResolver(_withCredentials(),
            matching: TitleMatching.keyless),
        isA<SkipResolver>(),
      );
    });

    // The rule every caller had before this parameter existed.
    test('the default still asks IGDB when it can, and skips when it cannot',
        () {
      expect(ProviderPolicy.buildResolver(_withCredentials()),
          isNot(isA<SkipResolver>()));
      expect(ProviderPolicy.buildResolver(ProviderSettings()),
          isA<SkipResolver>());
    });
  });

  group('the choice on the scan screen', () {
    testWidgets('both modes are named before anything is scanned',
        (tester) async {
      await _pump(tester, ProviderSettings());

      expect(find.byKey(const Key('title-matching')), findsOneWidget);
      for (final mode in TitleMatching.values) {
        expect(find.text(mode.label), findsOneWidget);
      }
    });

    testWidgets('with nothing registered the run is keyless and says what it '
        'costs, on the first frame', (tester) async {
      await _pump(tester, ProviderSettings());

      // Reached without opening Settings and without leaving a field blank:
      // the mode is named on the screen the scan starts from, and its cost is
      // there before anything is tapped.
      expect(_consequence(tester), keylessConsequence);
      expect(_consequence(tester), contains('.xcoll'));
      expect(_consequence(tester), contains('CSV'));
    });

    testWidgets('asking for a match with nothing registered names the two '
        'ways forward', (tester) async {
      await _pump(tester, ProviderSettings());

      await _choose(tester, TitleMatching.igdb);

      // Not a blocker and not silence: register, or scan now as the mode the
      // control still shows as unselected.
      expect(_consequence(tester), igdbUnconfiguredNote);
      expect(_consequence(tester), contains('Settings'));
      expect(_consequence(tester), contains(TitleMatching.keyless.label));
    });

    testWidgets('with credentials the run matches, and keyless is still one '
        'tap away', (tester) async {
      await _pump(tester, _withCredentials());

      expect(_consequence(tester), igdbConsequence);

      await _choose(tester, TitleMatching.keyless);

      expect(_consequence(tester), keylessConsequence);
    });

    testWidgets('a picked mode survives credentials arriving later',
        (tester) async {
      // An unpicked mode follows the credentials; a picked one does not. The
      // settings screen edits this same object in place, so adding a Twitch
      // application mid-session looks exactly like this.
      final settings = ProviderSettings();
      await _pump(tester, settings);
      await _choose(tester, TitleMatching.keyless);

      settings
        ..igdbClientId = 'id'
        ..igdbClientSecret = 'secret';
      await tester.pump();

      expect(_consequence(tester), keylessConsequence);
    });

    testWidgets('an untouched mode follows the credentials', (tester) async {
      final settings = ProviderSettings();
      await _pump(tester, settings);
      expect(_consequence(tester), keylessConsequence);

      settings
        ..igdbClientId = 'id'
        ..igdbClientSecret = 'secret';
      // A rebuild is what returning from Settings produces; nothing here taps
      // the control, so the default rule is what is under test.
      await tester.pumpWidget(MaterialApp(
        home: ScanScreen(
          settings: settings, store: _store(), picker: FakeInputPicker()),
      ));

      expect(_consequence(tester), igdbConsequence);
    });

    // The whole path, once: choose it, scan, and land on a review screen that
    // knows which mode produced the document. Credentials ARE stored here, so
    // nothing but the choice can be what made the run keyless -- and no IGDB
    // client is ever constructed, which [SkipResolver]'s refusing http client
    // would turn into a StateError if it were.
    testWidgets('choosing it, scanning, and arriving at a review that says so',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: ScanScreen(
          settings: _withCredentials(),
          store: _store(),
          picker: FakeInputPicker(),
          debugVisionProvider: FakeVisionProvider(),
        ),
      ));

      await _choose(tester, TitleMatching.keyless);
      await tester.tap(find.text('Add photos'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Scan'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('keyless-run-banner')), findsOneWidget);
      // The mark T-0223 puts on the minority is absent, because here it would
      // be on everything.
      expect(find.textContaining('not in .xcoll'), findsNothing);
    });

    // Above the Scan button and below everything the last run had to say:
    // inserted higher up it pushed the resume-review button and the status
    // line's own shortcut out of the viewport, where a finder still found
    // them and a tap landed on the button bar underneath (2026-08-22).
    testWidgets('the control sits below the run panels, not above them',
        (tester) async {
      await _pump(tester, ProviderSettings());

      expect(
        tester.getTopLeft(find.byKey(const Key('title-matching'))).dy,
        greaterThan(tester.getTopLeft(find.text('Pick shelf photos to begin')).dy),
      );
    });
  });
}
