/// The keyless run offered as a mode, before the scan (T-0230).
///
/// The bug this pins: a person could reach the keyless state only by leaving
/// the two IGDB fields blank in Settings and scanning. The CLI and the README
/// had both named it a path -- "Path A -- keyless" -- for as long as the app
/// had presented it as an absence.
///
/// **And what a second catalogue did to the word (T-0367).** "Keyless" meant
/// "no IGDB" while IGDB was the only catalogue there was, and a stored TMDB
/// token then sat idle in a run the app called keyless. The mode survived the
/// widening -- it is still what the person ASKED for -- and everything
/// derived from the credentials moved to what the run can REACH, per kind.
/// The four combinations are enumerated below, once, because a sentence being
/// true of one of them is not the property under test.
///
/// Nothing here dials anything. Every sentence is decided from a
/// [ProviderSettings] in memory, which is the property [MatchingCheck] shares
/// with [BackendCheck]; the one test that runs a scan runs it against a fake
/// vision provider, and its resolver is a [SkipResolver], whose refusing http
/// client would throw if any IGDB traffic were attempted. No token here is a
/// token: every credential is an invented string, and none of them is ever
/// sent anywhere.
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

ProviderSettings _withToken() => ProviderSettings(tmdbToken: 'not-a-token');

ProviderSettings _withBoth() => ProviderSettings(
      igdbClientId: 'id',
      igdbClientSecret: 'secret',
      tmdbToken: 'not-a-token',
    );

/// The four credential combinations, in the order they are reasoned about:
/// neither, IGDB only, TMDB only, both. Named so a test that means "every
/// combination" cannot quietly mean three of them.
final _everyCombination = <String, ProviderSettings Function()>{
  'neither': ProviderSettings.new,
  'IGDB only': _withCredentials,
  'TMDB only': _withToken,
  'both': _withBoth,
};

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
    // Every combination and not two of them: what makes a chosen keyless run
    // keyless is the choice, so no credential may change any part of this
    // answer -- which is the standing obligation T-0367 was given, stated as
    // a test rather than as a sentence in a doc comment.
    test('keyless is the same answer for every credential combination', () {
      _everyCombination.forEach((name, build) {
        final check =
            ProviderPolicy.checkMatching(build(), TitleMatching.keyless);

        expect(check.keyless, isTrue, reason: name);
        expect(check.unconfigured, isFalse, reason: name);
        expect(check.consequence, keylessConsequence, reason: name);
      });
    });

    test('asking to match with nothing registered degrades, it does not fail',
        () {
      final check = ProviderPolicy.checkMatching(
          ProviderSettings(), TitleMatching.matched);

      // The difference from a backend: an unconfigured backend blocks a scan,
      // this one runs it keyless and says so.
      expect(check.keyless, isTrue);
      expect(check.unconfigured, isTrue);
      expect(check.consequence, noCatalogueNote);
      expect(check.consequence, contains('Settings'));
      expect(check.consequence, contains(TitleMatching.keyless.label));
    });

    // The four combinations against the four answers, in one place. Three of
    // them key a run and each names its own catalogues; only the fourth
    // degrades, and it is the only one that enumerates nothing -- which is
    // the rule that keeps this screen from becoming a status board.
    test('each credential combination gets its own sentence and verdict', () {
      final answers = {
        'neither': (TitleMatching.keyless, true, noCatalogueNote),
        'IGDB only': (TitleMatching.matched, false, igdbOnlyConsequence),
        'TMDB only': (TitleMatching.matched, false, tmdbOnlyConsequence),
        'both': (TitleMatching.matched, false, bothCataloguesConsequence),
      };

      _everyCombination.forEach((name, build) {
        final check =
            ProviderPolicy.checkMatching(build(), TitleMatching.matched);
        final (matching, unconfigured, consequence) = answers[name]!;

        expect(check.matching, matching, reason: name);
        expect(check.unconfigured, unconfigured, reason: name);
        expect(check.consequence, consequence, reason: name);
      });

      // Four distinct sentences, so no two combinations are described alike.
      expect(answers.values.map((a) => a.$3).toSet(), hasLength(4));
    });

    // The claim T-0367 was filed on: with a second catalogue in the language,
    // no sentence may say the run is doing something to a catalogue it cannot
    // reach. Asserted by name rather than by prose, because "IGDB" appearing
    // in a sentence shown to somebody with no Twitch application is exactly
    // the defect.
    test('no keyed sentence names a catalogue its own run cannot reach', () {
      expect(tmdbOnlyConsequence, isNot(contains('IGDB')));
      expect(tmdbOnlyConsequence, contains('TMDB'));
      expect(igdbOnlyConsequence, isNot(contains('TMDB')));
      expect(igdbOnlyConsequence, contains('IGDB'));
      expect(bothCataloguesConsequence, contains('IGDB'));
      expect(bothCataloguesConsequence, contains('TMDB'));

      // A `.xcoll` movie item carries no platform_id at all, so the films-only
      // sentence may not promise platform names (WorkKind.movie, and the
      // exporter's _PlatformId.absent).
      expect(tmdbOnlyConsequence, isNot(contains('platform')));

      // And the label is the choice rather than a catalogue: it is the one
      // string on this control that every combination sees.
      expect(TitleMatching.matched.label, isNot(contains('IGDB')));
      expect(TitleMatching.matched.label, isNot(contains('TMDB')));
    });

    // The wording may not promise keyless detection, and may not promise on a
    // phone what only a desktop can do. T-0229 is the other half; nothing
    // written here should have to be unwritten by it.
    test('no consequence claims the photos stay on the machine', () {
      final sentences = [
        keylessConsequence,
        noCatalogueNote,
        igdbOnlyConsequence,
        tmdbOnlyConsequence,
        bothCataloguesConsequence,
      ];
      for (final text in sentences) {
        for (final overclaim in ['offline', 'never leave', 'no model']) {
          expect(text, isNot(contains(overclaim)), reason: text);
        }
      }
      expect(keylessConsequence, contains('vision backend'));
    });
  });

  group('the resolver a chosen mode produces', () {
    test('keyless skips the stage for every credential combination', () {
      _everyCombination.forEach((name, build) {
        expect(
          ProviderPolicy.buildResolver(build(),
              matching: TitleMatching.keyless),
          isA<SkipResolver>(),
          reason: name,
        );
      });
    });

    // The rule every caller had before this parameter existed, widened by
    // T-0367 to the rule the CLI's `resolverFor` always had: the stage is
    // skipped when the catalogue map would be empty, not when IGDB is absent.
    test('the default keys a run on either credential and skips on neither',
        () {
      for (final settings in [_withCredentials(), _withToken(), _withBoth()]) {
        expect(
            ProviderPolicy.buildResolver(settings), isNot(isA<SkipResolver>()));
      }
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

    // The whole of what somebody with no credentials meets, pinned as one
    // screen rather than as three assertions scattered through this file: it
    // is the common path, and T-0367's brief settles that it may not change.
    // Both sentences are the ones that were on this screen before that task,
    // and neither names a catalogue the reader has not registered for.
    testWidgets('with no credentials at all, both sentences are the ones that '
        'were there before films existed', (tester) async {
      await _pump(tester, ProviderSettings());

      expect(_consequence(tester), keylessConsequence);
      expect(_consequence(tester), isNot(contains('TMDB')));
      expect(_consequence(tester), isNot(contains('film')));

      await _choose(tester, TitleMatching.matched);

      expect(_consequence(tester), noCatalogueNote);
      expect(_consequence(tester), contains('Twitch'));
      expect(
        _consequence(tester),
        isNot(contains('TMDB')),
        reason: 'Listing a second catalogue at somebody who has neither is '
            'the status board this screen must not become',
      );
    });

    testWidgets('asking for a match with nothing registered names the two '
        'ways forward', (tester) async {
      await _pump(tester, ProviderSettings());

      await _choose(tester, TitleMatching.matched);

      // Not a blocker and not silence: register, or scan now as the mode the
      // control still shows as unselected.
      expect(_consequence(tester), noCatalogueNote);
      expect(_consequence(tester), contains('Settings'));
      expect(_consequence(tester), contains(TitleMatching.keyless.label));
    });

    testWidgets('with credentials the run matches, and keyless is still one '
        'tap away', (tester) async {
      await _pump(tester, _withCredentials());

      expect(_consequence(tester), igdbOnlyConsequence);

      await _choose(tester, TitleMatching.keyless);

      expect(_consequence(tester), keylessConsequence);
    });

    // The owner's case, on the screen: *someone might be sorting only films,
    // without games*. Nothing is tapped, because the point is that a stored
    // token keys the next run by itself.
    testWidgets('a TMDB token alone selects Match and says films are looked '
        'up', (tester) async {
      await _pump(tester, _withToken());

      expect(_consequence(tester), tmdbOnlyConsequence);
      expect(_consequence(tester), contains('TMDB'));
      expect(
        _consequence(tester),
        isNot(contains('Twitch')),
        reason: 'This run is keyed, so the register-with-Twitch note would be '
            'a false statement on screen -- the defect T-0367 was filed on',
      );
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

      expect(_consequence(tester), igdbOnlyConsequence);
    });

    // The same rule, followed by the other credential (T-0367). Pasting a
    // token into Settings has to switch the next run to matching without a
    // second gesture, exactly as registering a Twitch application does --
    // that is what "follows the credentials" now means.
    testWidgets('an untouched mode follows a token arriving on its own',
        (tester) async {
      final settings = ProviderSettings();
      await _pump(tester, settings);
      expect(_consequence(tester), keylessConsequence);

      settings.tmdbToken = 'not-a-token';
      await tester.pumpWidget(MaterialApp(
        home: ScanScreen(
          settings: settings, store: _store(), picker: FakeInputPicker()),
      ));

      expect(_consequence(tester), tmdbOnlyConsequence);
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

    // The other side of the same derivation, and the third of the four
    // sentences T-0367 had to make true (scan_screen's `_HeldReview.keyless`).
    // A run keyed by a token alone is NOT keyless: films were looked up, so
    // the banner -- *nothing was looked up* -- would be false over it, and it
    // has to be absent. The game rows this fake produces are keyless per kind
    // instead, which is the state T-0308 made ordinary and which the review
    // screen marks per row. No call leaves the machine: every detection here
    // is a game, and games route to the router's SkipResolver fallback.
    testWidgets('a run keyed by a token alone does not claim nothing was '
        'looked up', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: ScanScreen(
          settings: _withToken(),
          store: _store(),
          picker: FakeInputPicker(),
          debugVisionProvider: FakeVisionProvider(),
        ),
      ));

      await tester.tap(find.text('Add photos'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Scan'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('keyless-run-banner')), findsNothing);
      // And the rows say per row what the banner no longer says of the run.
      expect(find.textContaining('not in .xcoll'), findsWidgets);
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
