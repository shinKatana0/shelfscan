/// Guards the "never skip an image silently" rule on `scan` input (T-0025).
///
/// The failure being pinned down is not a crash: three 4000x3000 HEIC photos
/// were dropped into `photos/` for a re-measurement, and the scan would have
/// read only the two old 1200x900 JPEGs beside them and printed a summary
/// that looked exactly like a real measurement. So the claims worth testing
/// are about what reaches the human:
///   1. every file not taken is named, with its extension;
///   2. a directory that yields nothing is an error, not an empty success;
///   3. the summary line cannot be quoted without the skips coming with it.
///
/// The mime group below guards the other half of the same list (T-0036): a
/// file the scan does take is declared to the cloud providers by its
/// `PhotoInput.mimeType`, so a file accepted with no type would be uploaded as
/// a JPEG whatever its bytes are. Since T-0056 that type comes from the file's
/// signature, out of the one table in `shelfscan_core`, which is why the
/// fixtures below write real headers and why a file whose name lies about its
/// contents has its own tests.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

import '../bin/shelfscan.dart'
    show
        HeicConversion,
        PhotoDirectory,
        noPhotosMessage,
        readPhotoDirectory,
        scanScope,
        skipReport;

/// A real leading signature per mime type, so a fixture named `.png` holds PNG.
///
/// Keyed by mime type rather than by extension deliberately: an extension
/// added to [photoMimeTypes] with a type nothing here can write fails at
/// [_signatureFor] instead of quietly becoming an untested row.
final _signatures = <String, List<int>>{
  'image/jpeg': const [0xFF, 0xD8, 0xFF, 0xE0],
  'image/png': const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
  'image/webp': [...'RIFF'.codeUnits, 0, 0, 0, 0, ...'WEBP'.codeUnits],
  heicMimeType: [0, 0, 0, 0x18, ...'ftyp'.codeUnits, ...'heic'.codeUnits],
};

List<int> _signatureFor(String mimeType) {
  final signature = _signatures[mimeType];
  if (signature == null) {
    fail('no sample header for $mimeType, so no file here can be written as '
        'one -- the scan identifies photos by signature since T-0056');
  }
  return [...signature, ...List.filled(32, 0)];
}

/// The bytes a file called [name] holds when its name is honest: the signature
/// its extension promises, or something that is no image at all.
List<int> _honestBytes(String name) {
  final extension = extensionOf(name);
  final mimeType =
      photoMimeTypes[extension] ?? convertibleMimeTypes[extension];
  return mimeType == null ? const [0] : _signatureFor(mimeType);
}

/// A directory holding [files] by name, removed after the test.
Directory _dirOf(Map<String, List<int>> files) {
  final dir = Directory.systemTemp.createTempSync('shelfscan_photos_');
  // Swallowed: on Windows the delete races the handles just closed and
  // throws errno 145 "directory not empty" -- measured 2 red in 7 full runs
  // (T-0048). A leaked temp directory is cheaper than a coin-toss suite.
  addTearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // ignore
    }
  });
  for (final entry in files.entries) {
    File('${dir.path}${Platform.pathSeparator}${entry.key}')
        .writeAsBytesSync(entry.value);
  }
  return dir;
}

/// A directory where every name tells the truth about its contents.
Directory _dirWith(List<String> names) =>
    _dirOf({for (final name in names) name: _honestBytes(name)});

/// No converter is passed anywhere below, so every listing here describes a
/// host that skips HEIC; `documented_lists_test.dart` owns the accepted list
/// itself, on both hosts.
String _report(PhotoDirectory listing) =>
    skipReport(listing, convertsHeic: false).join('\n');

void main() {
  group('mixed directory', () {
    late PhotoDirectory listing;

    setUp(() {
      listing = readPhotoDirectory(_dirWith([
        'shelf-1.HEIC',
        'shelf-2.heic',
        'shelf_a.jpg',
        'shelf_b.JPG',
      ]));
    });

    test('scans the JPEGs and skips the rest', () {
      expect(listing.photos.map((p) => p.name), ['shelf_a.jpg', 'shelf_b.JPG']);
      expect(listing.skipped.map((s) => s.name),
          ['shelf-1.HEIC', 'shelf-2.heic']);
      expect(listing.fileCount, 4);
    });

    test('names every skipped file with its extension', () {
      final report = _report(listing);
      expect(report, contains('shelf-1.HEIC'));
      expect(report, contains('shelf-2.heic'));
      expect(report, contains('.heic'));
    });

    test('tells the user what to do about a HEIC', () {
      expect(_report(listing), contains('convert'));
    });

    test('banners the count so it survives a scrollback', () {
      expect(_report(listing), contains('2 of 4 file(s)'));
      expect(_report(listing), contains('NOT be scanned'));
    });

    test('the summary line carries the files that were left out', () {
      expect(scanScope(listing), '2 of 4 file(s) (2 skipped, named above)');
    });
  });

  test('a clean directory reports no skips and a plain summary', () {
    final listing = readPhotoDirectory(_dirWith(['a.jpg', 'b.png', 'c.webp']));
    expect(listing.skipped, isEmpty);
    expect(skipReport(listing, convertsHeic: false), isEmpty);
    expect(scanScope(listing), '3 photo(s)');
  });

  group('all skipped', () {
    test('HEIC-only directory names the extensions it found', () {
      final dir = _dirWith(['shelf-1.HEIC', 'shelf-2.HEIC', 'shelf-3.HEIC']);
      final listing = readPhotoDirectory(dir);
      expect(listing.photos, isEmpty);

      final message = noPhotosMessage(listing, dir.path, convertsHeic: false);
      expect(message, contains('.heic x3'));
      expect(message, contains('all 3 file(s)'));
      expect(message, contains('.jpg'));
      // The banner belongs to a partial run; here the error says it all.
      expect(_report(listing), isNot(contains('NOT be scanned')));
    });

    test('a directory with no image-like file at all still names them', () {
      final dir = _dirWith(['notes.txt', 'collection.review.json', 'README']);
      final listing = readPhotoDirectory(dir);
      expect(listing.photos, isEmpty);
      expect(listing.skipped.map((s) => s.name),
          containsAll(['notes.txt', 'collection.review.json', 'README']));

      final message = noPhotosMessage(listing, dir.path, convertsHeic: false);
      expect(message, contains('.txt x1'));
      expect(message, contains('.json x1'));
      expect(message, contains('(no extension) x1'));
      expect(_report(listing), contains('README (no extension)'));
    });

    test('an empty directory says so rather than naming nothing', () {
      final dir = _dirWith([]);
      final listing = readPhotoDirectory(dir);
      expect(listing.fileCount, 0);
      expect(noPhotosMessage(listing, dir.path, convertsHeic: false),
          contains('No files to scan'));
    });
  });

  group('declared mime type', () {
    test('every accepted extension arrives labelled as its own format', () {
      final listing = readPhotoDirectory(
          _dirWith(['a.jpg', 'b.jpeg', 'c.png', 'd.webp']));
      expect(
        {for (final photo in listing.photos) photo.name: photo.mimeType},
        {
          'a.jpg': 'image/jpeg',
          'b.jpeg': 'image/jpeg',
          'c.png': 'image/png',
          'd.webp': 'image/webp',
        },
      );
    });

    test('no accepted extension can reach a provider unlabelled', () {
      final listing = readPhotoDirectory(_dirWith([
        for (final extension in photoMimeTypes.keys) 'shelf$extension',
      ]));
      expect(listing.skipped, isEmpty);
      expect(listing.photos, hasLength(photoMimeTypes.length));
      for (final photo in listing.photos) {
        expect(photo.mimeType, photoMimeTypes[extensionOf(photo.name)],
            reason: '${photo.name} has no mime type of its own');
        expect(photo.mimeType, startsWith('image/'));
      }
    });

    test('no convertible extension is skipped as unknown instead of converted',
        () {
      final names = [
        for (final extension in convertibleMimeTypes.keys) 'shelf$extension'
      ];
      final listing = readPhotoDirectory(_dirWith(names),
          convertHeic: (paths) => {
                for (final path in paths)
                  path: HeicConversion.ok(
                      Uint8List.fromList(_signatureFor('image/jpeg')),
                      Duration.zero)
              });
      expect(listing.skipped, isEmpty);
      expect(listing.photos.map((p) => p.name), names);
      for (final photo in listing.photos) {
        expect(photo.mimeType, 'image/jpeg');
      }
    });

    test('an upper-case extension is labelled like its lower-case twin', () {
      final listing = readPhotoDirectory(_dirWith(['SHELF.PNG']));
      expect(listing.photos.single.mimeType, 'image/png');
    });

    // The accepted list moved to documented_lists_test.dart: the test that
    // used to sit here asserted the message named every photoMimeTypes key
    // and nothing more, which is exactly what the message did wrong (T-0077).
  });

  group('a name that lies about its contents', () {
    test('a HEIC renamed .jpg is converted, not declared image/jpeg', () {
      // The drift T-0056 closed: the app converted this file and the CLI
      // uploaded it to Anthropic labelled JPEG. Phones and messaging apps
      // rename HEIC this way.
      var handed = <String>[];
      final listing = readPhotoDirectory(
        _dirOf({'shelf.jpg': _signatureFor(heicMimeType)}),
        convertHeic: (paths) {
          handed = paths;
          return {
            for (final path in paths)
              path: HeicConversion.ok(
                  Uint8List.fromList(_signatureFor('image/jpeg')),
                  const Duration(milliseconds: 500))
          };
        },
      );

      expect(handed, hasLength(1));
      expect(listing.photos.single.name, 'shelf.jpg');
      expect(listing.photos.single.mimeType, 'image/jpeg');
      expect(listing.photos.single.bytes, _signatureFor('image/jpeg'));
      expect(listing.converted.single.name, 'shelf.jpg');
    });

    test('a PNG renamed .jpg is declared image/png', () {
      final listing = readPhotoDirectory(
          _dirOf({'shelf.jpg': _signatureFor('image/png')}));
      expect(listing.photos.single.mimeType, 'image/png');
    });

    test('a JPEG named .heic is read straight through, not sent to convert',
        () {
      final listing = readPhotoDirectory(
        _dirOf({'shelf-1.heic': _signatureFor('image/jpeg')}),
        convertHeic: (paths) => fail('called with $paths'),
      );
      expect(listing.photos.single.mimeType, 'image/jpeg');
      expect(listing.converted, isEmpty);
    });

    test('a .jpg that is no image at all is skipped naming the mismatch', () {
      final listing = readPhotoDirectory(_dirOf({
        'shelf.jpg': const [0x49, 0x49, 0x2A, 0x00, 8, 0, 0, 0],
      }));
      expect(listing.photos, isEmpty);
      final report = _report(listing);
      expect(report, contains('shelf.jpg'));
      expect(report, contains('.jpg'));
      expect(report, contains('the contents decide here, not the name'));
    });

    test('an extensionless file that is a real photo is still read', () {
      final listing =
          readPhotoDirectory(_dirOf({'shelf-1': _signatureFor('image/png')}));
      expect(listing.photos.single.name, 'shelf-1');
      expect(listing.photos.single.mimeType, 'image/png');
    });
  });

  test('a sub-directory is not reported as a skipped file', () {
    final dir = _dirWith(['shelf_a.jpg']);
    Directory('${dir.path}${Platform.pathSeparator}hires').createSync();
    final listing = readPhotoDirectory(dir);
    expect(listing.photos.map((p) => p.name), ['shelf_a.jpg']);
    expect(listing.skipped, isEmpty);
  });
}
