/// What the scan screen does when the user picks files (T-0039).
///
/// The bug this pins: the picker asked for `FileType.image`, whose Windows
/// filter has no HEIC in it, so the three phone photos were not
/// listed at all -- the CLI had been reading the same files end to end since
/// T-0031.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelfscan_app/heic_wic.dart';
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

/// Records what the screen asked the dialog for, and hands back named bytes.
///
/// [gate], when given, holds the dialog open, which is the whole of T-0116:
/// the presses that opened a second explorer were the ones that landed while
/// the first one was still up.
class RecordingFilePicker extends FilePicker {
  RecordingFilePicker(this.files, {this.gate});

  final Map<String, Uint8List> files;
  final Completer<void>? gate;
  FileType? askedType;
  List<String>? askedExtensions;
  int calls = 0;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    calls++;
    askedType = type;
    askedExtensions = allowedExtensions;
    await gate?.future;
    return FilePickerResult([
      for (final entry in files.entries)
        PlatformFile(
            name: entry.key, size: entry.value.length, bytes: entry.value),
    ]);
  }
}

Future<RecordingFilePicker> _pick(
  WidgetTester tester,
  Map<String, Uint8List> files, {
  HeicDecoder? decoder,
}) async {
  final picker = RecordingFilePicker(files);
  FilePicker.platform = picker;
  await tester.pumpWidget(MaterialApp(
    home: ScanScreen(
      settings: ProviderSettings(backend: VisionBackend.local),
      store: SettingsStore(secrets: RecordingStore(), prefs: RecordingStore()),
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
  testWidgets('the dialog is asked for HEIC by extension, not for "images"',
      (tester) async {
    final picker = await _pick(tester, {'shelf.jpg': _jpeg});

    expect(picker.askedType, FileType.custom);
    expect(picker.askedExtensions, contains('heic'));
    expect(picker.askedExtensions, pickerExtensions);
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
    await _pick(
      tester,
      {'phone.heic': _heic},
      decoder: (_) async => throw HeicDecodeException('no codec'),
    );
    expect(_rejection('phone.heic'), findsOneWidget);

    FilePicker.platform = RecordingFilePicker({'shelf.jpg': _jpeg});
    await tester.tap(find.text('Add photos'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('rejected-photos')), findsNothing);
  });

  testWidgets('a conversion in flight says which file it is on', (tester) async {
    // ~0.4 s per phone photo, so the screen would otherwise sit unchanged
    // after the dialog closes.
    final gate = Completer<void>();
    FilePicker.platform = RecordingFilePicker({'phone.heic': _heic});
    await tester.pumpWidget(MaterialApp(
      home: ScanScreen(
        settings: ProviderSettings(backend: VisionBackend.local),
        store:
            SettingsStore(secrets: RecordingStore(), prefs: RecordingStore()),
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
    FilePicker.platform = RecordingFilePicker({'phone.heic': _heic});
    await tester.pumpWidget(MaterialApp(
      home: ScanScreen(
        settings: ProviderSettings(backend: VisionBackend.local),
        store:
            SettingsStore(secrets: RecordingStore(), prefs: RecordingStore()),
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
    final picker = RecordingFilePicker({'shelf.jpg': _jpeg}, gate: gate);
    FilePicker.platform = picker;
    await tester.pumpWidget(MaterialApp(
      home: ScanScreen(
        settings: ProviderSettings(backend: VisionBackend.local),
        store:
            SettingsStore(secrets: RecordingStore(), prefs: RecordingStore()),
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
    await _pick(tester, {'shelf1.jpg': _jpeg});
    expect(find.text('shelf1.jpg'), findsOneWidget);

    FilePicker.platform =
        RecordingFilePicker({'shelf1.jpg': _jpeg, 'shelf2.jpg': _jpeg});
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
