/// Tests for the desktop save path of [PlatformExportSaver].
///
/// The OS dialog itself cannot run in a test, but everything around it can:
/// the platform interface is swapped for a fake, so we still verify the
/// suggested file name, the type filter, cancellation, and that the chosen
/// path really receives the rendered string.
///
/// The Android share sheet itself is still NOT driven here -- that needs a
/// device, see T-0005 and T-0015. What is covered is the one decision that
/// branch makes: which share results mean the export was saved and which mean
/// the user backed out. [shareOutcome] exists to be reachable
/// from here, because reporting a cancelled export as a saved one is the worst
/// thing this file can do and a device test is not available to catch it.
library;

import 'dart:io';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shelfscan_app/export_saver.dart';

/// The flattened source around [needle], so a failure can quote the shape that
/// is there instead of printing the whole file as its `Actual` (T-0324).
String _flattenedAround(String flattened, String needle) {
  final at = flattened.indexOf(needle);
  if (at < 0) return '(not present)';
  final from = at > 140 ? at - 140 : 0;
  var to = at + needle.length + 40;
  if (to > flattened.length) to = flattened.length;
  return '...${flattened.substring(from, to)}...';
}

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
      const path = 'app/lib/export_saver.dart';
      // Flattened: what is asserted below is a sequence of tokens, and a line
      // break between two of them is the one difference Dart does not carry.
      // Unflattened, a hand-rewrap of the call failed this with the whole file
      // as the matcher's Actual and no sentence saying a source scan had run
      // (T-0324).
      final source = File('lib/export_saver.dart')
          .readAsStringSync()
          .replaceAll(RegExp(r'\s+'), ' ');

      if (!source.contains('SharePlus.instance.share(')) {
        fail('$path: a source scan of the whitespace-flattened file found no '
            'SharePlus.instance.share(, so nothing here opens the share sheet '
            'and the routing checked below would pass on a file that shares '
            'nothing.');
      }
      // The optional space is a line break after the paren, which the flatten
      // turns into a space -- the only wrap of this statement that survives
      // the flatten. A changed argument still fails, on purpose.
      final routed = RegExp(r'return shareOutcome\( ?result, file\.path\);');
      if (!routed.hasMatch(source)) {
        // A branch that maps the result itself and one that merely wraps the
        // call differently send a reader to opposite ends of the file, so they
        // do not share a sentence.
        fail(source.contains('return shareOutcome(')
            ? '$path: a source scan found return shareOutcome( but not the '
                'shape ${routed.pattern} in the whitespace-flattened file, so '
                'the sheet result reaches the mapping under other arguments. '
                'What is there:\n  '
                '${_flattenedAround(source, 'return shareOutcome(')}'
            : '$path: a source scan of the whitespace-flattened file found no '
                'return shareOutcome(, so the Android branch decides saved '
                'from cancelled itself and the three tests above pin a '
                'function that branch does not use.');
      }
    });
  });
}
