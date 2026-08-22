/// Guards the HEIC-to-JPEG step the CLI runs before the vision stage (T-0031).
///
/// Two claims, and the second matters more than the first. The tool now reads
/// the phone camera's default format on Windows -- but T-0025 exists because a
/// directory of HEIC was about to be measured as if it were the JPEGs beside
/// it, and a conversion that fails quietly re-creates exactly that. So every
/// failure route below is forced, not reasoned about: a host that cannot
/// convert, a converter that reports an error, and a file WIC itself refuses.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

import '../bin/shelfscan.dart'
    show
        HeicConversion,
        conversionReport,
        heicConversionUnsupported,
        readPhotoDirectory,
        scanScope,
        skipReport,
        windowsHeicToJpeg;

/// The signature a file called [name] carries when its name is honest.
///
/// Real headers and not a placeholder byte because the CLI decides what to
/// convert from the file's contents (T-0056): a `.heic` holding anything else
/// is a different test, and there is one below.
List<int> _honestBytes(String name) =>
    convertibleMimeTypes.containsKey(extensionOf(name))
        ? [0, 0, 0, 0x18, ...'ftyp'.codeUnits, ...'heic'.codeUnits]
        : _jpeg(0xE0);

/// A directory holding [names], removed after the test.
Directory _dirWith(List<String> names) {
  final dir = Directory.systemTemp.createTempSync('shelfscan_heic_test_');
  addTearDown(() => dir.deleteSync(recursive: true));
  for (final name in names) {
    File('${dir.path}${Platform.pathSeparator}$name')
        .writeAsBytesSync(_honestBytes(name));
  }
  return dir;
}

Uint8List _jpeg(int marker) => Uint8List.fromList([0xff, 0xd8, 0xff, marker]);

void main() {
  group('a host that can convert', () {
    late Directory dir;

    setUp(() => dir = _dirWith(['IMG_1.HEIC', 'IMG_2.heic', 'shelf.jpg']));

    test('HEIC becomes a photo, in directory order, beside the JPEGs', () {
      final listing = readPhotoDirectory(dir,
          convertHeic: (paths) => {
                for (var i = 0; i < paths.length; i++)
                  paths[i]: HeicConversion.ok(
                      _jpeg(i), Duration(milliseconds: 500 + i))
              });

      expect(listing.photos.map((p) => p.name),
          ['IMG_1.HEIC', 'IMG_2.heic', 'shelf.jpg']);
      expect(listing.skipped, isEmpty);
      expect(scanScope(listing), '3 photo(s)');
    });

    test('the converted bytes are the ones the provider gets', () {
      final listing = readPhotoDirectory(dir,
          convertHeic: (paths) => {
                for (final path in paths)
                  path: HeicConversion.ok(_jpeg(0x42), Duration.zero)
              });
      final converted = listing.photos.firstWhere((p) => p.name == 'IMG_1.HEIC');
      expect(converted.bytes, _jpeg(0x42));
      // The name still ends in .heic, so nothing downstream may infer the
      // type from it.
      expect(converted.mimeType, 'image/jpeg');
    });

    test('reports what each file cost, per photo', () {
      final listing = readPhotoDirectory(dir,
          convertHeic: (paths) => {
                for (var i = 0; i < paths.length; i++)
                  paths[i]: HeicConversion.ok(
                      _jpeg(i), Duration(milliseconds: 500 + i))
              });

      final report = conversionReport(listing).join('\n');
      expect(report, contains('IMG_1.HEIC -> jpeg in 500 ms'));
      expect(report, contains('IMG_2.heic -> jpeg in 501 ms'));
      expect(report, contains('2 file(s) converted to a temp directory'));
      expect(report, contains('Nothing was written next to the originals'));
    });

    test('a directory with nothing to convert reports nothing', () {
      final listing = readPhotoDirectory(_dirWith(['shelf.jpg']),
          convertHeic: (paths) => fail('called with $paths'));
      expect(conversionReport(listing), isEmpty);
    });
  });

  group('a host that cannot', () {
    test('names the operating system, and only excuses Windows', () {
      expect(heicConversionUnsupported('windows'), isNull);
      expect(heicConversionUnsupported('linux'), contains('linux'));
      expect(heicConversionUnsupported('macos'), contains('Windows-only'));
    });

    test('every HEIC is skipped by name, carrying that reason', () {
      final reason = heicConversionUnsupported('linux')!;
      final listing = readPhotoDirectory(
        _dirWith(['IMG_1.HEIC', 'shelf.jpg']),
        convertHeic: (paths) => {
          for (final path in paths)
            path: HeicConversion.failed(reason, Duration.zero)
        },
      );

      expect(listing.photos.map((p) => p.name), ['shelf.jpg']);
      final report = skipReport(listing, convertsHeic: false).join('\n');
      expect(report, contains('IMG_1.HEIC'));
      expect(report, contains('.heic'));
      expect(report, contains('linux'));
      expect(report, contains('convert it to .jpg'));
      // The scan is not over: whatever else the directory held is still read.
      expect(scanScope(listing), '1 of 2 file(s) (1 skipped, named above)');
    });
  });

  group('a conversion that fails', () {
    test('the failure reaches the user verbatim, not as "cannot decode"', () {
      final listing = readPhotoDirectory(
        _dirWith(['IMG_1.HEIC']),
        convertHeic: (paths) => {
          for (final path in paths)
            path: HeicConversion.failed(
                'No imaging component suitable to complete this operation was '
                'found',
                Duration.zero)
        },
      );
      expect(skipReport(listing, convertsHeic: true).join('\n'),
          contains('No imaging component suitable'));
    });

    test('one bad file does not take the good one with it', () {
      final dir = _dirWith(['IMG_1.HEIC', 'IMG_2.heic']);
      final listing = readPhotoDirectory(dir, convertHeic: (paths) {
        final sorted = [...paths]..sort();
        return {
          sorted.first: HeicConversion.ok(_jpeg(1), Duration.zero),
          sorted.last: HeicConversion.failed('corrupt', Duration.zero),
        };
      });

      expect(listing.photos.map((p) => p.name), ['IMG_1.HEIC']);
      expect(listing.skipped.map((s) => s.name), ['IMG_2.heic']);
      expect(skipReport(listing, convertsHeic: true).join('\n'),
          contains('corrupt'));
    });

    test('a converter that answers for nothing still leaves no file unnamed',
        () {
      final listing = readPhotoDirectory(_dirWith(['IMG_1.HEIC']),
          convertHeic: (paths) => const {});
      expect(listing.photos, isEmpty);
      expect(skipReport(listing, convertsHeic: true).join('\n'),
          contains('IMG_1.HEIC'));
    });
  });

  group('the real converter', () {
    // A HEIC file type box with nothing behind it: enough for the CLI to hand
    // it to the converter, and nothing WIC can decode. This is the only test
    // here that runs the actual PowerShell/WIC path, and it runs the half that
    // must never be silent.
    late Directory dir;
    late String path;

    setUp(() {
      dir = _dirWith(['broken.heic']);
      path = '${dir.path}${Platform.pathSeparator}broken.heic';
    });

    test('answers for every path it was handed, with a reason', () {
      final results = windowsHeicToJpeg([path]);
      expect(results.keys, [path]);
      expect(results[path]!.bytes, isNull);
      expect(results[path]!.error, isNotEmpty);
    });

    test('leaves the photo directory exactly as it found it', () {
      final before = dir.listSync().map((e) => e.path).toList()..sort();
      windowsHeicToJpeg([path]);
      final after = dir.listSync().map((e) => e.path).toList()..sort();
      expect(after, before);
    });

    test('an empty batch starts no process', () {
      expect(windowsHeicToJpeg(const []), isEmpty);
    });
  });
}
