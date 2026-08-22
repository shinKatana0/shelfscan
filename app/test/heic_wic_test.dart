/// The Windows HEIC decode path (T-0039).
///
/// The control photographs are gitignored and live outside any worktree, so the
/// real-file cases run only when `SHELFSCAN_PHOTOS` points at them; the
/// failure cases run everywhere.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shelfscan_app/heic_wic.dart';

final _photos = Platform.environment['SHELFSCAN_PHOTOS'];

List<File> _heics() {
  final path = _photos;
  final dir = path == null ? null : Directory(path);
  return dir == null || !dir.existsSync()
      ? const []
      : [
        for (final entity in dir.listSync())
          if (entity is File && entity.path.toLowerCase().endsWith('.heic'))
            entity
        ];
}

void main() {
  test('a non-Windows host names itself rather than failing obscurely', () {
    expect(heicDecodeUnsupported('windows'), isNull);
    for (final os in ['android', 'linux', 'macos']) {
      expect(heicDecodeUnsupported(os), contains('Windows-only'));
    }
  });

  test('bytes that are not HEIC fail with a reason, not a crash', () async {
    await expectLater(
      windowsHeicToJpeg(Uint8List.fromList(List.filled(64, 7))),
      throwsA(isA<HeicDecodeException>()),
    );
  }, skip: Platform.isWindows ? null : 'WIC is Windows-only');

  group('the real photo files', () {
    final files = _heics();

    test('every .heic in photos/ becomes decodable JPEG bytes', () async {
      for (final file in files) {
        final watch = Stopwatch()..start();
        final jpeg = await windowsHeicToJpeg(file.readAsBytesSync());
        watch.stop();

        expect(jpeg.sublist(0, 3), [0xFF, 0xD8, 0xFF],
            reason: '${file.path} did not come back as JPEG');
        expect(jpeg.length, greaterThan(100000));
        // ignore: avoid_print
        print('${file.uri.pathSegments.last}: ${jpeg.length} bytes in '
            '${watch.elapsedMilliseconds} ms');
      }
    });
  },
      skip: Platform.isWindows && _heics().isNotEmpty
          ? null
          : 'needs SHELFSCAN_PHOTOS pointing at .heic files, on Windows');
}
