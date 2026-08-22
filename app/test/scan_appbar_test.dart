/// The app bar's own insets (T-0114).
///
/// The defect: the settings gear was the last widget in `actions` with no
/// trailing padding, so its tap target ended on the window edge -- the owner
/// asked for a minimal inset and said the other buttons were fine. It is
/// also the control they failed to find on the very first run, so its position
/// has been remarked on twice.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelfscan_app/provider_config.dart';
import 'package:shelfscan_app/screens/scan_screen.dart';
import 'package:shelfscan_app/settings_store.dart';

import 'settings_store_test.dart' show RecordingStore;

void main() {
  testWidgets('the gear is inset from the window edge by the gap it already '
      'has from the button beside it', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ScanScreen(
        settings: ProviderSettings(backend: VisionBackend.local),
        store:
            SettingsStore(secrets: RecordingStore(), prefs: RecordingStore()),
      ),
    ));

    final bar = tester.getRect(find.byType(AppBar));
    final gear = tester.getRect(find.byKey(const Key('open-settings')));
    final switcher =
        tester.getRect(find.byType(SegmentedButton<VisionBackend>));

    expect(bar.right - gear.right, 8.0);
    expect(bar.right - gear.right, gear.left - switcher.right,
        reason: 'one inset for the row, not one per widget that asked');
  });
}
