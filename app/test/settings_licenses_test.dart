/// The route to the third-party licence notices, and the notices behind it
/// (T-0388).
///
/// **A widget test cannot see the licence page populated, and that is a
/// property of the harness rather than of the app.**
/// `TestWidgetsFlutterBinding.initLicenses()` is an explicit no-op -- "Do not
/// include any licenses, because we're a test" -- so [LicenseRegistry] is
/// empty under `flutter test` and under `integration_test`, which inherits the
/// same binding. Every test here that pumps a page therefore sees an empty
/// one, and asserting on what it renders would assert the harness.
///
/// So the population is measured on the artefact instead: `NOTICES.Z`, read
/// through [rootBundle] and parsed the way `ServicesBinding` parses it. That
/// is the same bytes the running app reads and the same split it applies, so
/// the count below is the app's, not a test fixture's.
///
/// **Why reading a bundled file in a test is trustworthy here, when T-0386
/// says it is not.** That hazard is about a declared asset whose key begins
/// `../`: it escapes the bundle during a build and still resolves under
/// `build/unit_test_assets/`. `NOTICES.Z` is not a declared asset at all --
/// the Flutter tool writes it as a top-level key of every bundle it
/// generates -- so there is no key to escape and nothing for the test bundle
/// to resolve differently.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelfscan_app/provider_config.dart';
import 'package:shelfscan_app/screens/settings_screen.dart';
import 'package:shelfscan_app/settings_store.dart';

import 'settings_store_test.dart' show RecordingStore;

Future<void> _pumpSettings(WidgetTester tester) =>
    tester.pumpWidget(MaterialApp(
      home: SettingsScreen(
        settings: ProviderSettings(),
        store: SettingsStore(
          secrets: RecordingStore(),
          prefs: RecordingStore(),
        ),
      ),
    ));

/// What `ServicesBinding._addLicenses` does to the bundled bytes, reproduced:
/// gunzip, split on a line of exactly 80 hyphens, and take the lines before
/// the first blank line of each block as that block's package names.
({int entries, Set<String> packages}) parseNotices(List<int> gzipped) {
  final raw = utf8.decode(gzip.decode(gzipped));
  final blocks = raw.split('\n${'-' * 80}\n');
  final packages = <String>{};
  var entries = 0;
  for (final block in blocks) {
    entries++;
    final split = block.indexOf('\n\n');
    if (split < 0) continue;
    for (final name in block.substring(0, split).split('\n')) {
      if (name.isNotEmpty) packages.add(name);
    }
  }
  return (entries: entries, packages: packages);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the settings screen routes to the licence page', (tester) async {
    await _pumpSettings(tester);

    final entry = find.byKey(const Key('settings-licenses'));
    // The form is taller than the test viewport and About is last on it;
    // the unfocus is the same guard settings_screen_test.dart documents.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.ensureVisible(entry);
    await tester.pumpAndSettle();
    expect(find.text('Open-source licences'), findsOneWidget);

    await tester.tap(entry);
    await tester.pumpAndSettle();

    expect(find.byType(LicensePage), findsOneWidget);
    // The header is this app's own statement -- see [appLegalese]; nothing in
    // the generated notices covers the application itself.
    expect(find.text('shelfscan'), findsWidgets);
    expect(find.text(appLegalese), findsOneWidget);
  });

  testWidgets('the notices the page reads are present and populated',
      (tester) async {
    final bytes = await rootBundle.load('NOTICES.Z');
    final parsed = parseNotices(bytes.buffer.asUint8List());

    // Floors, not the measured figures: the exact counts move with every
    // dependency edit and with the engine's own third-party set, and a test
    // that pins them would be red for a reason nobody caused. What is being
    // guarded is the difference between a populated page and a handful of
    // entries -- the failure mode where the route exists and asserts a
    // compliance it does not deliver.
    expect(parsed.entries, greaterThan(100));
    expect(parsed.packages.length, greaterThan(100));

    // And the page must name what this app actually pulls in, not only what
    // the engine carries: every direct third-party dependency of `app/`.
    for (final package in const [
      'ffi',
      'file_picker',
      'file_selector',
      'flutter',
      'flutter_secure_storage',
      'flutter_svg',
      'path_provider',
      'share_plus',
      'shared_preferences',
    ]) {
      expect(parsed.packages, contains(package),
          reason: '$package ships and its notice is owed');
    }
  });

  test('the legalese copyright clause is the one in LICENSE', () {
    // The suite runs in `app/`; the licence is at the repository root.
    final licence = File('../LICENSE').readAsStringSync();
    final clause = RegExp(r'Copyright \(c\) \d{4} \S+').firstMatch(licence);
    expect(clause, isNotNull, reason: 'LICENSE carries no copyright line');
    expect(appLegalese, contains(clause![0]!));
  });

  test('the test binding still refuses to populate the registry', () async {
    // A tripwire, not a requirement. If Flutter ever drops the no-op override
    // this file opens with, the two widget tests above can assert on the real
    // page instead of on the artefact behind it -- and this is the only thing
    // that would say so.
    expect(await LicenseRegistry.licenses.length, 0,
        reason: 'the harness now collects licences: '
            'settings_licenses_test.dart can measure the rendered page');
  });
}
