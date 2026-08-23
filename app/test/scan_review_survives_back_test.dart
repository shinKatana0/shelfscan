/// What Back costs, and what a second scan costs (T-0117).
///
/// The owner hit this on their second real use: `ReviewScreen` was pushed
/// from `_runScan` and the document lived only in that call frame, so Back
/// popped the route and took every approve/reject with it. Recovering one
/// costs a full rescan -- ~80 s locally on three photos, or cloud money --
/// which makes it the one defect in its group that destroys work already
/// done.
///
/// Pinned here: Back is a pop and asks nothing, the scan screen keeps the
/// document, re-entering shows the same marks, and the only moment a review
/// is replaced -- a second scan that produces a document -- is the only
/// moment the user is asked.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelfscan_app/provider_config.dart';
import 'package:shelfscan_app/screens/scan_screen.dart';
import 'package:shelfscan_app/settings_store.dart';
import 'package:shelfscan_core/shelfscan_core.dart';

import 'scan_all_failed_test.dart' show ScriptedVision;
import 'scan_wiring_test.dart' show FakeInputPicker, FakeVisionProvider;
import 'settings_store_test.dart' show RecordingStore;

Widget _screen(VisionProvider vision) => MaterialApp(
      home: ScanScreen(
        settings: ProviderSettings(backend: VisionBackend.local),
        store: SettingsStore(secrets: RecordingStore(), prefs: RecordingStore()),
        picker: FakeInputPicker(),
        debugVisionProvider: vision,
      ),
    );

Future<void> _scan(WidgetTester tester) async {
  await tester.tap(find.text('Add photos'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Scan'));
  await tester.pumpAndSettle();
}

Future<void> _mark(WidgetTester tester, int row, IconData mark) async {
  await tester.tap(find.descendant(
    of: find.byKey(Key('review-row-$row')),
    matching: find.byIcon(mark),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Back keeps every decision, and Resume review is the way in',
      (tester) async {
    await tester.pumpWidget(_screen(FakeVisionProvider()));
    await _scan(tester);

    expect(find.text('Review (0/2 to export)'), findsOneWidget);
    await _mark(tester, 0, Icons.check_circle);
    await _mark(tester, 1, Icons.cancel);
    expect(find.text('Review (1/2 to export)'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    // Back costs nothing, so it asks nothing: a confirm on every exit is the
    // kind people learn to dismiss unread.
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('shelfscan'), findsOneWidget);
    expect(find.byKey(const Key('resume-review')), findsOneWidget);
    expect(find.text('Last scan: 2 items, 2 marked'), findsOneWidget);

    await tester.tap(find.byKey(const Key('resume-review-button')));
    await tester.pumpAndSettle();

    // The same document, not a rebuilt one: the counter and both statuses
    // are where they were left.
    expect(find.text('Review (1/2 to export)'), findsOneWidget);
    expect(find.textContaining('approved'), findsOneWidget);
    expect(find.textContaining('rejected'), findsOneWidget);
  });

  testWidgets('a second scan asks first, and Keep it runs nothing',
      (tester) async {
    final vision = FakeVisionProvider();
    await tester.pumpWidget(_screen(vision));
    await _scan(tester);
    await _mark(tester, 0, Icons.check_circle);
    await _mark(tester, 1, Icons.check_circle);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Scan'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('rescan-confirm')), findsOneWidget);
    expect(find.textContaining('You have marked 2 items'), findsOneWidget);

    await tester.tap(find.byKey(const Key('rescan-keep')));
    await tester.pumpAndSettle();

    expect(vision.calls, 1, reason: 'the declined scan never ran');
    expect(find.text('Last scan: 2 items, 2 marked'), findsOneWidget);
  });

  testWidgets('a confirmed second scan replaces the review', (tester) async {
    final vision = FakeVisionProvider();
    await tester.pumpWidget(_screen(vision));
    await _scan(tester);
    await _mark(tester, 0, Icons.check_circle);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Scan'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('rescan-replace')));
    await tester.pumpAndSettle();

    expect(vision.calls, 2);
    // The new document wins whole: the user asked for this scan by name, and
    // carrying marks across two different reads of the shelf would be a merge
    // nobody asked for.
    expect(find.text('Review (0/2 to export)'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Last scan: 2 items, 0 marked'), findsOneWidget);
  });

  testWidgets('a second scan that fails every photo replaces nothing',
      (tester) async {
    final errors = <String, Object>{};
    await tester.pumpWidget(_screen(ScriptedVision(errors)));
    await _scan(tester);
    await _mark(tester, 0, Icons.check_circle);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Last scan: 1 item, 1 marked'), findsOneWidget);

    errors['shelf1.jpg'] = visionApiFailure(
      service: 'Anthropic',
      model: 'claude-not-a-model',
      statusCode: 401,
      body: '{"type":"error","error":{"type":"authentication_error"}}',
      retryable: false,
    );
    await tester.tap(find.text('Scan'));
    await tester.pumpAndSettle();
    expect(find.textContaining('You have marked 1 item'), findsOneWidget);
    await tester.tap(find.byKey(const Key('rescan-replace')));
    await tester.pumpAndSettle();

    // The run said so, and the held review is still the only one there is.
    expect(find.byKey(const Key('scan-status')), findsOneWidget);
    expect(find.text('Last scan: 1 item, 1 marked'), findsOneWidget);
  });
}
