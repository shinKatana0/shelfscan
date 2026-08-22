/// What the app accepts from the picker, and what it declares those bytes to
/// be (T-0039, T-0036, T-0056).
///
/// The tables and the sniffer live in `shelfscan_core` and are tested there.
/// What is tested here is the app's half of the invariant: every extension the
/// dialog offers reaches a provider with a type of its own, and a file whose
/// name lies about its contents is treated as its contents.
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shelfscan_app/heic_wic.dart';
import 'package:shelfscan_app/photo_files.dart';
import 'package:shelfscan_core/shelfscan_core.dart';

/// A real leading signature per mime type, so a fixture named `.png` holds PNG.
///
/// Keyed by mime type and not by extension on purpose: an extension added to
/// the core table with a type nothing here can write fails at [_bytesFor],
/// which is the app-side half of "an accepted extension gains no type".
final _signatures = <String, List<int>>{
  'image/jpeg': const [0xFF, 0xD8, 0xFF, 0xE0],
  'image/png': const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
  'image/webp': [...'RIFF'.codeUnits, 0, 0, 0, 0, ...'WEBP'.codeUnits],
  heicMimeType: [0, 0, 0, 0x18, ...'ftyp'.codeUnits, ...'heic'.codeUnits],
};

Uint8List _bytesFor(String mimeType) {
  final signature = _signatures[mimeType];
  if (signature == null) {
    fail('no sample header for $mimeType, so nothing here can hand the app a '
        'file of that type -- it could only ever be rejected');
  }
  return Uint8List.fromList([...signature, ...List.filled(32, 0)]);
}

final _jpeg = _bytesFor('image/jpeg');
final _png = _bytesFor('image/png');
final _webp = _bytesFor('image/webp');
final _heic = _bytesFor(heicMimeType);

Future<Uint8List> _neverCalled(Uint8List _) async =>
    throw StateError('no conversion expected');

Future<Uint8List> _toJpeg(Uint8List _) async => _jpeg;

void main() {
  group('the picker filter', () {
    test('offers HEIC as well as the formats providers already take', () {
      expect(pickerExtensions, containsAll(['jpg', 'jpeg', 'png', 'webp']));
      expect(pickerExtensions, containsAll(['heic', 'heif', 'hif']));
    });

    test('it offers exactly what the core table names, dots stripped', () {
      expect(pickerExtensions,
          [for (final extension in scannableExtensions) extension.substring(1)]);
      for (final extension in pickerExtensions) {
        expect(extension, isNot(startsWith('.')));
      }
    });

    test('every extension it offers is either mapped or convertible', () {
      for (final extension in pickerExtensions) {
        expect(
          photoMimeTypes.containsKey('.$extension') ||
              convertibleMimeTypes.containsKey('.$extension'),
          isTrue,
          reason: '.$extension would reach a provider with no mime type',
        );
      }
    });
  });

  group('no offered extension can reach a provider unlabelled', () {
    test('a file of each accepted type arrives as its own type', () async {
      final loaded = await loadPickedPhotos(
        [
          for (final entry in photoMimeTypes.entries)
            (name: 'shelf${entry.key}', bytes: _bytesFor(entry.value))
        ],
        decodeHeic: _neverCalled,
      );

      expect(loaded.rejected, isEmpty);
      expect(loaded.photos, hasLength(photoMimeTypes.length));
      for (final photo in loaded.photos) {
        expect(photo.mimeType, photoMimeTypes[extensionOf(photo.name)],
            reason: '${photo.name} has no mime type of its own');
        expect(photo.mimeType, startsWith('image/'));
      }
    });

    test('a file of each convertible type is converted, not rejected',
        () async {
      final loaded = await loadPickedPhotos(
        [
          for (final entry in convertibleMimeTypes.entries)
            (name: 'shelf${entry.key}', bytes: _bytesFor(entry.value))
        ],
        decodeHeic: _toJpeg,
      );

      expect(loaded.rejected, isEmpty);
      expect(loaded.photos, hasLength(convertibleMimeTypes.length));
      for (final photo in loaded.photos) {
        expect(photo.mimeType, 'image/jpeg');
      }
    });
  });

  group('loading picked files', () {
    test('each photo is declared as the type its bytes are', () async {
      final loaded = await loadPickedPhotos(
        [
          (name: 'a.jpg', bytes: _jpeg),
          (name: 'b.png', bytes: _png),
          (name: 'c.webp', bytes: _webp),
        ],
        decodeHeic: _neverCalled,
      );

      expect(loaded.rejected, isEmpty);
      expect([for (final p in loaded.photos) p.mimeType],
          ['image/jpeg', 'image/png', 'image/webp']);
    });

    test('a HEIC arrives as JPEG bytes under its own name', () async {
      final loaded = await loadPickedPhotos(
        [(name: 'IMG_0001.HEIC', bytes: _heic)],
        decodeHeic: _toJpeg,
      );

      expect(loaded.rejected, isEmpty);
      expect(loaded.photos.single.name, 'IMG_0001.HEIC');
      expect(loaded.photos.single.mimeType, 'image/jpeg');
      expect(loaded.photos.single.bytes, _jpeg);
    });

    test('a HEIC renamed .jpg is still converted, not declared JPEG', () async {
      // Phones and messaging apps do this, and the extension is what T-0036
      // stopped trusting. The CLI answers this case identically since T-0056.
      final loaded = await loadPickedPhotos(
        [(name: 'shelf.jpg', bytes: _heic)],
        decodeHeic: _toJpeg,
      );

      expect(loaded.photos.single.mimeType, 'image/jpeg');
      expect(loaded.photos.single.bytes, _jpeg);
    });

    test('a PNG renamed .jpg is declared image/png', () async {
      final loaded = await loadPickedPhotos(
        [(name: 'shelf.jpg', bytes: _png)],
        decodeHeic: _neverCalled,
      );

      expect(loaded.photos.single.mimeType, 'image/png');
    });

    test('a HEIC the host cannot decode is named with the reason, and the '
        'rest of the pick survives', () async {
      final loaded = await loadPickedPhotos(
        [
          (name: 'good.jpg', bytes: _jpeg),
          (name: 'phone.heic', bytes: _heic),
        ],
        decodeHeic: (_) async =>
            throw HeicDecodeException('Windows has no HEIC codec installed'),
      );

      expect([for (final p in loaded.photos) p.name], ['good.jpg']);
      expect(loaded.rejected.single.name, 'phone.heic');
      expect(loaded.rejected.single.reason, contains('no HEIC codec'));
    });

    test('a file that is not an image is named, not silently dropped',
        () async {
      final loaded = await loadPickedPhotos(
        [(name: 'notes.txt', bytes: Uint8List.fromList([1, 2, 3]))],
        decodeHeic: _neverCalled,
      );

      expect(loaded.photos, isEmpty);
      expect(loaded.rejected.single.name, 'notes.txt');
      expect(loaded.rejected.single.reason, contains('.txt'));
    });

    test('a .jpg that is no image at all is named for the mismatch, not told '
        'to convert itself to .jpg', () async {
      final loaded = await loadPickedPhotos(
        [
          (
            name: 'shelf.jpg',
            bytes: Uint8List.fromList([0x49, 0x49, 0x2A, 0x00, 8, 0, 0, 0])
          )
        ],
        decodeHeic: _neverCalled,
      );

      expect(loaded.photos, isEmpty);
      expect(loaded.rejected.single.reason,
          contains('the contents decide here, not the name'));
      expect(loaded.rejected.single.reason, isNot(contains('convert it to')));
    });

    test('a file with no extension at all is still named', () async {
      final loaded = await loadPickedPhotos(
        [(name: 'shelf-1', bytes: Uint8List.fromList([1, 2, 3]))],
        decodeHeic: _neverCalled,
      );

      expect(loaded.rejected.single.reason, 'not a photo this app can read');
    });

    test('an extensionless file that is a real photo is still read', () async {
      final loaded = await loadPickedPhotos(
        [(name: 'shelf-1', bytes: _png)],
        decodeHeic: _neverCalled,
      );

      expect(loaded.rejected, isEmpty);
      expect(loaded.photos.single.mimeType, 'image/png');
    });

    test('the conversion announces itself per file', () async {
      final announced = <String>[];
      await loadPickedPhotos(
        [(name: 'a.jpg', bytes: _jpeg), (name: 'b.heic', bytes: _heic)],
        decodeHeic: _toJpeg,
        onConverting: announced.add,
      );

      expect(announced, ['b.heic']);
    });
  });

  test('a non-Windows host rejects HEIC by name rather than trying', () async {
    final loaded = await loadPickedPhotos(
      [(name: 'phone.heic', bytes: _heic)],
      decodeHeic: (_) => Future.error(
          HeicDecodeException(heicDecodeUnsupported('android')!)),
    );

    expect(loaded.photos, isEmpty);
    expect(loaded.rejected.single.reason, contains('Windows-only'));
  });
}
