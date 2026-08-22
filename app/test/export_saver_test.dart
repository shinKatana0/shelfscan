/// Tests for the desktop save path of [PlatformExportSaver].
///
/// The OS dialog itself cannot run in a test, but everything around it can:
/// the platform interface is swapped for a fake, so we still verify the
/// suggested file name, the type filter, cancellation, and that the chosen
/// path really receives the rendered string.
///
/// The Android branch (temp file + share sheet) is NOT covered here: it
/// needs a device/emulator, see the T-0005 worker report.
library;

import 'dart:io';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelfscan_app/export_saver.dart';

class FakeFileSelector extends FileSelectorPlatform {
  FakeFileSelector(this.chosenPath);

  /// Null models the user cancelling the dialog.
  final String? chosenPath;
  SaveDialogOptions? lastOptions;
  List<XTypeGroup>? lastTypeGroups;

  @override
  Future<FileSaveLocation?> getSaveLocation({
    List<XTypeGroup>? acceptedTypeGroups,
    SaveDialogOptions options = const SaveDialogOptions(),
  }) async {
    lastOptions = options;
    lastTypeGroups = acceptedTypeGroups;
    return chosenPath == null ? null : FileSaveLocation(chosenPath!);
  }
}

void main() {
  late Directory tempDir;

  setUp(() => tempDir = Directory.systemTemp.createTempSync('shelfscan_test'));
  tearDown(() => tempDir.deleteSync(recursive: true));

  test('save dialog defaults to shelf.<extension> and writes the file',
      () async {
    final target = '${tempDir.path}${Platform.pathSeparator}shelf.xcoll';
    final selector = FakeFileSelector(target);
    FileSelectorPlatform.instance = selector;

    final outcome = await const PlatformExportSaver().save(
      suggestedName: 'shelf.xcoll',
      extension: 'xcoll',
      content: '{"version": 2}',
    );

    expect(selector.lastOptions?.suggestedName, 'shelf.xcoll');
    expect(selector.lastTypeGroups?.single.extensions, ['xcoll']);
    expect(outcome.kind, SaveKind.savedToFile);
    expect(outcome.path, target);
    expect(File(target).readAsStringSync(), '{"version": 2}');
  });

  test('cancelling the dialog writes nothing', () async {
    FileSelectorPlatform.instance = FakeFileSelector(null);

    final outcome = await const PlatformExportSaver().save(
      suggestedName: 'shelf.csv',
      extension: 'csv',
      content: 'title,platform\r\n',
    );

    expect(outcome.kind, SaveKind.cancelled);
    expect(tempDir.listSync(), isEmpty);
  });

  test('a failing dialog is reported, not thrown', () async {
    FileSelectorPlatform.instance =
        FakeFileSelector('${tempDir.path}/no/such/dir/shelf.csv');

    final outcome = await const PlatformExportSaver()
        .save(suggestedName: 'shelf.csv', extension: 'csv', content: 'x');

    expect(outcome.kind, SaveKind.failed);
    expect(outcome.error, isNotNull);
  });

  test('mime types match what each target actually is', () {
    expect(mimeTypeFor('csv'), 'text/csv');
    expect(mimeTypeFor('xcoll'), 'application/json'); // external contract
    expect(mimeTypeFor('zzz'), 'application/octet-stream');
  });
}
