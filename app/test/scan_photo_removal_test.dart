/// Taking a picked photo back out of the list (T-0138).
///
/// `_photos` was append-only and the rows carried no action, so a mis-picked
/// file had one exit: restart the app. What it costs to leave it in is a
/// vision call -- ~25 s on the local model, money on a cloud one -- and a
/// shelf's worth of rows to reject one by one at review.
///
/// The other half is when removal must be impossible. It is behind `_busy`,
/// the same gate Add photos is behind (T-0116): a run walks the list, and a
/// pick appends to it after an await having already checked it for
/// duplicates.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelfscan_app/provider_config.dart';
import 'package:shelfscan_app/screens/scan_screen.dart';
import 'package:shelfscan_app/settings_store.dart';
import 'package:shelfscan_core/shelfscan_core.dart';

import 'scan_picker_test.dart' show RecordingFilePicker;
import 'settings_store_test.dart' show RecordingStore;

final _jpeg =
    Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, ...List.filled(32, 0)]);

/// Records the photos the pipeline was actually handed -- the point of a
/// removal is the call that is never made, which no assertion about the list
/// on screen can reach.
class _RecordingVision implements VisionProvider {
  _RecordingVision({this.gates = const {}});

  final Map<String, Completer<void>> gates;
  final seen = <String>[];

  @override
  Future<PhotoAnalysis> analyze(PhotoInput photo) async {
    seen.add(photo.name);
    await gates[photo.name]?.future;
    return PhotoAnalysis(
      items: [
        Detection(
          rawTitle: 'READ ${photo.name}',
          mediaType: MediaType.disc,
          confidence: 1.0,
          sourcePhoto: photo.name,
        ),
      ],
      unreadable: const [],
    );
  }
}

Finder _remove(String name) => find.byKey(Key('remove-photo-$name'));

bool _enabled(WidgetTester tester, Finder button) =>
    tester.widget<IconButton>(button).onPressed != null;

Future<_RecordingVision> _pumpWithPhotos(
  WidgetTester tester,
  List<String> names, {
  Map<String, Completer<void>> gates = const {},
}) async {
  final vision = _RecordingVision(gates: gates);
  FilePicker.platform =
      RecordingFilePicker({for (final name in names) name: _jpeg});
  await tester.pumpWidget(MaterialApp(
    home: ScanScreen(
      settings: ProviderSettings(backend: VisionBackend.local),
      store: SettingsStore(secrets: RecordingStore(), prefs: RecordingStore()),
      debugVisionProvider: vision,
    ),
  ));
  await tester.tap(find.text('Add photos'));
  await tester.pumpAndSettle();
  return vision;
}

void main() {
  testWidgets('a removed photo is never sent to the model', (tester) async {
    final vision = await _pumpWithPhotos(tester, ['shelf1.jpg', 'shelf2.jpg']);

    await tester.tap(_remove('shelf1.jpg'));
    await tester.pump();
    expect(find.text('shelf1.jpg'), findsNothing);
    expect(find.text('shelf2.jpg'), findsOneWidget);

    await tester.tap(find.text('Scan'));
    await tester.pumpAndSettle();
    expect(vision.seen, ['shelf2.jpg']);
  });

  testWidgets('removing the last photo leaves nothing to scan', (tester) async {
    await _pumpWithPhotos(tester, ['shelf1.jpg']);

    await tester.tap(_remove('shelf1.jpg'));
    await tester.pump();

    expect(find.text('Pick shelf photos to begin'), findsOneWidget);
    final scan = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(scan.onPressed, isNull);
  });

  testWidgets('a run holds the list still until it returns', (tester) async {
    final gates = {'shelf1.jpg': Completer<void>()};
    final vision = await _pumpWithPhotos(
        tester, ['shelf1.jpg', 'shelf2.jpg'], gates: gates);

    await tester.tap(find.text('Scan'));
    await tester.pump();
    expect(_enabled(tester, _remove('shelf2.jpg')), isFalse,
        reason: 'the run is walking this list');

    await tester.tap(_remove('shelf2.jpg'), warnIfMissed: false);
    await tester.pump();
    expect(find.text('shelf2.jpg'), findsOneWidget);

    gates['shelf1.jpg']!.complete();
    await tester.pumpAndSettle();
    // Both photos were read: the press during the run changed nothing.
    expect(vision.seen, ['shelf1.jpg', 'shelf2.jpg']);
  });

  testWidgets('an open file dialog holds it still too -- one guard, not two',
      (tester) async {
    await _pumpWithPhotos(tester, ['shelf1.jpg']);

    final gate = Completer<void>();
    FilePicker.platform =
        RecordingFilePicker({'shelf2.jpg': _jpeg}, gate: gate);
    await tester.tap(find.text('Add photos'));
    await tester.pump();
    expect(_enabled(tester, _remove('shelf1.jpg')), isFalse,
        reason: 'the pick checks this list for duplicates before it appends');

    gate.complete();
    await tester.pumpAndSettle();
    expect(_enabled(tester, _remove('shelf1.jpg')), isTrue);
    expect(find.text('shelf2.jpg'), findsOneWidget);
  });
}
