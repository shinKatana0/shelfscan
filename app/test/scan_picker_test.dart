/// What the scan screen does when the user picks files (T-0039).
///
/// The bug this pins: the picker asked for `FileType.image`, whose Windows
/// filter has no HEIC in it, so the three phone photos were not
/// listed at all -- the CLI had been reading the same files end to end since
/// T-0031.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelfscan_app/heic_wic.dart';
import 'package:shelfscan_app/input_picker.dart';
import 'package:shelfscan_app/photo_files.dart';
import 'package:shelfscan_app/provider_config.dart';
import 'package:shelfscan_app/screens/scan_screen.dart';
import 'package:shelfscan_app/settings_store.dart';
import 'package:shelfscan_core/shelfscan_core.dart';

import 'scan_wiring_test.dart' show FakeVisionProvider;
import 'settings_store_test.dart' show RecordingStore;

Uint8List _bytes(List<int> head) =>
    Uint8List.fromList([...head, ...List.filled(32, 0)]);

final _jpeg = _bytes(const [0xFF, 0xD8, 0xFF, 0xE0]);
final _heic = _bytes([0, 0, 0, 0x18, ...'ftyp'.codeUnits, ...'heic'.codeUnits]);

/// Counts the picks and hands back named bytes.
///
/// [files] and [gate] are settable, because a test that picks twice is asking
/// the second dialog for something else and the screen holds one picker for
/// its lifetime.
///
/// [gate], when set, holds the dialog open, which is the whole of T-0116:
/// the presses that opened a second explorer were the ones that landed while
/// the first one was still up.
class RecordingInputPicker extends InputPicker {
  RecordingInputPicker(this.files, {this.gate});

  Map<String, Uint8List> files;
  Completer<void>? gate;
  int calls = 0;

  @override
  Future<List<PickedFile>?> pickPhotos() async {
    calls++;
    await gate?.future;
    return [
      for (final entry in files.entries) (name: entry.key, bytes: entry.value)
    ];
  }

  @override
  Future<String?> pickFolder({required String prompt}) async => null;
}

Future<RecordingInputPicker> _pick(
  WidgetTester tester,
  Map<String, Uint8List> files, {
  HeicDecoder? decoder,
}) async {
  final picker = RecordingInputPicker(files);
  await tester.pumpWidget(MaterialApp(
    home: ScanScreen(
      settings: ProviderSettings(backend: VisionBackend.local),
      store: SettingsStore(secrets: RecordingStore(), prefs: RecordingStore()),
      picker: picker,
      debugVisionProvider: FakeVisionProvider(),
      debugHeicDecoder: decoder ?? (_) async => _jpeg,
    ),
  ));
  await tester.tap(find.text('Add photos'));
  await tester.pumpAndSettle();
  return picker;
}

Finder _rejection(String text) => find.descendant(
      of: find.byKey(const Key('rejected-photos')),
      matching: find.textContaining(text),
    );

void main() {
  test('the dialog is asked for HEIC by extension, not for "images"', () {
    // Read as text rather than driven: since T-0305 the screen asks for
    // photographs and the picker decides how, so the plugin has one caller
    // and a widget test can no longer see these arguments without naming it
    // again.
    final source = File('lib/input_picker.dart').readAsStringSync();

    expect(source, contains('pickFiles('),
        reason: 'the source scan found no call, so the checks below would '
            'pass on a file that picks nothing');
    expect(source, contains('type: FileType.custom'));
    expect(source, contains('allowedExtensions: pickerExtensions'));
    expect(pickerExtensions, contains('heic'));
  });

  testWidgets('a chosen HEIC becomes a scannable photo', (tester) async {
    await _pick(tester, {'shelf-1.heic': _heic});

    expect(find.text('shelf-1.heic'), findsOneWidget);
    expect(find.byKey(const Key('rejected-photos')), findsNothing);
    // The Scan button is live, so the file is not merely listed.
    final scan = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(scan.onPressed, isNotNull);
  });

  testWidgets('a HEIC that cannot be decoded is named at the moment it is '
      'chosen, with the reason', (tester) async {
    await _pick(
      tester,
      {'good.jpg': _jpeg, 'phone.heic': _heic},
      decoder: (_) async => throw HeicDecodeException(
          'Windows has no HEIC codec installed -- install "HEIF Image '
          'Extensions" from the Microsoft Store'),
    );

    expect(_rejection('phone.heic'), findsOneWidget);
    expect(_rejection('HEIF Image Extensions'), findsOneWidget);
    // Loud, but not fatal: the readable photo is still queued.
    expect(find.text('good.jpg'), findsOneWidget);
    final scan = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(scan.onPressed, isNotNull);
  });

  testWidgets('a rejected file is not carried into the scan', (tester) async {
    await _pick(
      tester,
      {'phone.heic': _heic},
      decoder: (_) async => throw HeicDecodeException('no codec'),
    );

    final scan = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(scan.onPressed, isNull, reason: 'nothing scannable was chosen');
  });

  testWidgets('a clean pick shows no rejection panel', (tester) async {
    await _pick(tester, {'a.jpg': _jpeg, 'b.jpg': _jpeg});

    expect(find.byKey(const Key('rejected-photos')), findsNothing);
    expect(find.byKey(const Key('converting-photo')), findsNothing);
  });

  testWidgets('the second pick replaces the first pick\'s complaints',
      (tester) async {
    final picker = await _pick(
      tester,
      {'phone.heic': _heic},
      decoder: (_) async => throw HeicDecodeException('no codec'),
    );
    expect(_rejection('phone.heic'), findsOneWidget);

    picker.files = {'shelf.jpg': _jpeg};
    await tester.tap(find.text('Add photos'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('rejected-photos')), findsNothing);
  });

  testWidgets('a conversion in flight says which file it is on', (tester) async {
    // ~0.4 s per phone photo, so the screen would otherwise sit unchanged
    // after the dialog closes.
    final gate = Completer<void>();
    await tester.pumpWidget(MaterialApp(
      home: ScanScreen(
        settings: ProviderSettings(backend: VisionBackend.local),
        store:
            SettingsStore(secrets: RecordingStore(), prefs: RecordingStore()),
        picker: RecordingInputPicker({'phone.heic': _heic}),
        debugVisionProvider: FakeVisionProvider(),
        debugHeicDecoder: (_) async {
          await gate.future;
          return _jpeg;
        },
      ),
    ));
    await tester.tap(find.text('Add photos'));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('converting-photo')), findsOneWidget);
    expect(find.textContaining('phone.heic'), findsOneWidget);
    final add = tester.widget<TextButton>(find.ancestor(
        of: find.text('Add photos'), matching: find.byType(TextButton)));
    expect(add.onPressed, isNull,
        reason: 'a second pick cannot start on top of a conversion');

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('converting-photo')), findsNothing);
  });

  testWidgets('the converted bytes are what the pipeline reads', (tester) async {
    // The vision provider sees JPEG bytes and an image/jpeg label even though
    // the file is called .heic -- the name stays the user's file, the type
    // describes the bytes (T-0036).
    final seen = <PhotoInput>[];
    await tester.pumpWidget(MaterialApp(
      home: ScanScreen(
        settings: ProviderSettings(backend: VisionBackend.local),
        store:
            SettingsStore(secrets: RecordingStore(), prefs: RecordingStore()),
        picker: RecordingInputPicker({'phone.heic': _heic}),
        debugVisionProvider: _RecordingVision(seen),
        debugHeicDecoder: (_) async => _jpeg,
      ),
    ));
    await tester.tap(find.text('Add photos'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan'));
    await tester.pumpAndSettle();

    expect(seen.single.name, 'phone.heic');
    expect(seen.single.mimeType, 'image/jpeg');
    expect(seen.single.bytes, _jpeg);
  });

  testWidgets('a second press while the dialog is open never reaches the '
      'picker', (tester) async {
    final gate = Completer<void>();
    final picker = RecordingInputPicker({'shelf.jpg': _jpeg}, gate: gate);
    await tester.pumpWidget(MaterialApp(
      home: ScanScreen(
        settings: ProviderSettings(backend: VisionBackend.local),
        store:
            SettingsStore(secrets: RecordingStore(), prefs: RecordingStore()),
        picker: picker,
        debugVisionProvider: FakeVisionProvider(),
      ),
    ));

    // Both presses inside one frame, which is where a real stack of
    // explorers came from: the button cannot be disabled until the next one.
    await tester.tap(find.text('Add photos'));
    await tester.tap(find.text('Add photos'));
    expect(picker.calls, 1);

    await tester.pump();
    final add = tester.widget<TextButton>(find.ancestor(
        of: find.text('Add photos'), matching: find.byType(TextButton)));
    expect(add.onPressed, isNull, reason: 'and the button is out as well');

    gate.complete();
    await tester.pumpAndSettle();
    expect(picker.calls, 1);
    expect(find.text('shelf.jpg'), findsOneWidget);
  });

  testWidgets('the same file picked twice is listed once, and the copy is '
      'named', (tester) async {
    final picker = await _pick(tester, {'shelf1.jpg': _jpeg});
    expect(find.text('shelf1.jpg'), findsOneWidget);

    picker.files = {'shelf1.jpg': _jpeg, 'shelf2.jpg': _jpeg};
    await tester.tap(find.text('Add photos'));
    await tester.pumpAndSettle();

    expect(find.text('shelf1.jpg'), findsOneWidget,
        reason: 'two rows for one name are two shelves to the pipeline');
    expect(find.text('shelf2.jpg'), findsOneWidget);
    expect(_rejection('shelf1.jpg'), findsOneWidget);
    expect(_rejection('already in the list'), findsOneWidget);
  });
}

class _RecordingVision implements VisionProvider {
  _RecordingVision(this.seen);

  final List<PhotoInput> seen;

  @override
  Future<PhotoAnalysis> analyze(PhotoInput photo) async {
    seen.add(photo);
    return const PhotoAnalysis(items: [], unreadable: []);
  }
}
