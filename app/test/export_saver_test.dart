/// Tests for the desktop save path of [PlatformExportSaver].
///
/// The OS dialog itself cannot run in a test, but everything around it can:
/// the platform interface is swapped for a fake, so we still verify the
/// suggested file name, the type filter, cancellation, and that the chosen
/// path really receives the rendered string.
///
/// The Android share sheet itself is still NOT driven here -- that needs a
/// device, see the T-0005 worker report and T-0015. What is covered is the one
/// decision that branch makes: which share results mean the export was saved
/// and which mean the user backed out. [shareOutcome] exists to be reachable
/// from here, because reporting a cancelled export as a saved one is the worst
/// thing this file can do and a device test is not available to catch it.
library;

import 'dart:io';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';
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

  group('what the share sheet answered decides saved from cancelled', () {
    const somewhere = '/tmp/shelf.csv';

    test('a dismissed sheet is a cancelled export, never a saved one', () {
      final outcome = shareOutcome(
          const ShareResult('', ShareResultStatus.dismissed), somewhere);

      expect(outcome.kind, SaveKind.cancelled);
      expect(outcome.path, isNull);
    });

    test('a selected action is a share, carrying the temp path', () {
      final outcome = shareOutcome(
          const ShareResult('an.app', ShareResultStatus.success), somewhere);

      expect(outcome.kind, SaveKind.shared);
      expect(outcome.path, somewhere);
    });

    test('an unavailable result is not read as a cancellation', () {
      // The sheet could not report what the user did. Only `dismissed` is a
      // refusal, and answering `cancelled` here would claim a certainty the
      // platform never gave.
      expect(shareOutcome(ShareResult.unavailable, somewhere).kind,
          SaveKind.shared);
    });

    test('the Android branch routes its result through shareOutcome', () {
      // Read as text: the branch is behind Platform.isAndroid, so a host test
      // cannot enter it, and pinning the mapping proves nothing unless the
      // branch is what uses it.
      final source = File('lib/export_saver.dart').readAsStringSync();

      expect(source, contains('SharePlus.instance.share('),
          reason: 'the source scan found no share call, so the check below '
              'would pass on a file that shares nothing');
      expect(source, contains('return shareOutcome(result, file.path);'));
    });
  });
}
