/// What the scan panel does with the two classes of line (T-0222).
///
/// The bug this pins: on seeing the panel after a real scan of three
/// photographs, a games folder and the Galaxy library, the owner asked what
/// the errors were. **Nothing had failed.** All four lines
/// under "From this scan:" were documented exclusions -- a non-GOG release,
/// DLC, releases Galaxy hides, a numbered folder -- and every one was painted
/// `colorScheme.error` under `Icons.warning_amber`, because the panel had no
/// severity to paint by.
///
/// So the three things below: a scan of nothing but silences must not present
/// as a failure, a failure among them must still be unmissable, and both
/// answers must survive the colour being taken away -- which is why the class
/// is a heading in words and not only a hue (T-0043).
///
/// The library reader is a seam for `scan_library_test.dart`'s reason: the real
/// read is an FFI query on another isolate that never completes in
/// `testWidgets`'s fake async, and the real file is a real purchases file.
/// Every title below is invented.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelfscan_app/galaxy_db.dart';
import 'package:shelfscan_app/provider_config.dart';
import 'package:shelfscan_app/screens/scan_screen.dart';
import 'package:shelfscan_app/settings_store.dart';
import 'package:shelfscan_core/shelfscan_core.dart';

import 'settings_store_test.dart' show RecordingStore;

/// A library row the source will exclude, or -- with [content] given -- one it
/// cannot read at all.
SourceEntry _row(String id, String title,
        {int isDlc = 0, int visible = 1, String? content}) =>
    SourceEntry(
      name: 'gog_$id',
      content: content ??
          galaxyRowToJson(
              'gog_$id', jsonEncode({'title': title}), isDlc, visible),
    );

Future<void> _scanLibrary(
  WidgetTester tester,
  List<SourceEntry> entries,
) async {
  await tester.pumpWidget(MaterialApp(
    home: ScanScreen(
      settings: ProviderSettings(backend: VisionBackend.local),
      store: SettingsStore(secrets: RecordingStore(), prefs: RecordingStore()),
      debugLibraryReader: () async => GalaxyLibrary(
        entries: entries,
        asOf: DateTime(2026, 8, 17, 9, 45),
        schemaVersion: galaxySchemaVersion,
      ),
    ),
  ));
  await tester.tap(find.byKey(const Key('add-gog-library')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Scan'));
  await tester.pumpAndSettle();
  // A run that finished opens review over the scan screen; the panel is what
  // the user comes back to, and it is what is under test.
  await tester.pageBack();
  await tester.pumpAndSettle();
}

final _failures = find.byKey(const Key('scan-warnings-heading'));
final _exclusions = find.byKey(const Key('scan-exclusions-heading'));

/// The colour-free reading of the panel: the headings, in the order they are
/// laid out. A screen reader gets this and nothing else, so it has to be the
/// whole answer (T-0043).
List<String> _headings(WidgetTester tester) => [
      for (final text in tester.widgetList<Text>(find.descendant(
        of: find.byKey(const Key('scan-warnings')),
        matching: find.byType(Text),
      )))
        if (text.key != null) text.data!,
    ];

void main() {
  testWidgets('a scan of nothing but silences does not present as a failure',
      (tester) async {
    // A real scan in miniature: two DLC and one connected-store release,
    // which is three of the four lines they saw.
    await _scanLibrary(tester, [
      _row('1', 'Vex DLC', isDlc: 1),
      _row('2', 'Vex Season Pass', isDlc: 1),
      SourceEntry(
          name: 'steam_9',
          content: galaxyRowToJson(
              'steam_9', jsonEncode({'title': 'Dusk-Rail'}), 0, 1)),
    ]);

    expect(_failures, findsNothing,
        reason: 'nothing failed, so the panel has no failure section at all');
    expect(_exclusions, findsOneWidget);
    expect(_headings(tester),
        ['Left out of this scan on purpose, nothing wrong:']);
    // Nothing is hidden: every skipped entry is still named on screen.
    expect(
      find.descendant(
        of: find.byKey(const Key('scan-warnings')),
        matching: find.textContaining('is DLC, not a game'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('scan-warnings')),
        matching: find.textContaining('not a GOG product'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('one real failure among the silences is still unmissable',
      (tester) async {
    await _scanLibrary(tester, [
      _row('1', 'Vex DLC', isDlc: 1),
      _row('2', 'Vex Season Pass', isDlc: 1),
      _row('3', '', content: '{'),
    ]);

    expect(_failures, findsOneWidget);
    expect(_exclusions, findsOneWidget);
    // Failures above exclusions, and that order is load-bearing: the panel is
    // capped at 120px and scrolls, and on a real scan the silences
    // outnumbered everything else many times over.
    expect(_headings(tester), [
      'Went wrong in this scan:',
      'Left out of this scan on purpose, nothing wrong:',
    ]);
    expect(
      find.descendant(
        of: find.byKey(const Key('scan-warnings')),
        matching: find.textContaining('is not JSON'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the two classes differ by more than their colour',
      (tester) async {
    await _scanLibrary(tester, [
      _row('1', 'Vex DLC', isDlc: 1),
      _row('3', '', content: '{'),
    ]);

    final scheme = Theme.of(tester.element(find.byType(Scaffold).first))
        .colorScheme;
    final icons = tester
        .widgetList<Icon>(find.descendant(
          of: find.byKey(const Key('scan-warnings')),
          matching: find.byType(Icon),
        ))
        .toList();

    // A warning triangle for one class and a struck-through filter for the
    // other, so the shape answers where colour is not available either.
    expect([for (final icon in icons) icon.icon],
        [Icons.warning_amber, Icons.filter_alt_off_outlined]);
    expect([for (final icon in icons) icon.color],
        [scheme.error, scheme.onSurfaceVariant]);
  });
}
