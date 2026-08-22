/// The one table both shells read, and the invariant it exists to hold
/// (T-0036, T-0056).
///
/// The claim being pinned down is not "sniffing works". It is that no
/// extension can be offered to a user with a type nothing can produce, and no
/// type can be produced that the shells have no plan for -- the two halves
/// that drifted apart while the table lived in `bin/` and in `app/lib/` at
/// once. Every test below is driven off the tables themselves, so adding a row
/// to one of them without the rest of the machinery fails here rather than at
/// a provider call.
library;

import 'dart:typed_data';

import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

/// A real leading signature for every type [sniffImage] claims to name.
///
/// Deliberately keyed by mime type rather than by extension: a new entry in
/// [knownImageMimeTypes] with no sample here fails the first test below, which
/// is the point -- a type nobody can demonstrate is a type nothing produces.
final _signatures = <String, List<int>>{
  'image/jpeg': const [0xFF, 0xD8, 0xFF, 0xE0],
  'image/png': const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
  'image/webp': [...'RIFF'.codeUnits, 0, 0, 0, 0, ...'WEBP'.codeUnits],
  heicMimeType: [0, 0, 0, 0x18, ...'ftyp'.codeUnits, ...'heic'.codeUnits],
};

Uint8List _headerFor(String mimeType) {
  final signature = _signatures[mimeType];
  if (signature == null) {
    fail('no sample signature for $mimeType -- nothing here can show that '
        'sniffImage ever produces it');
  }
  return Uint8List.fromList([...signature, ...List.filled(32, 0)]);
}

void main() {
  group('the tables agree with the sniffer', () {
    test('every type the sniffer claims is one it actually returns', () {
      for (final mimeType in knownImageMimeTypes) {
        expect(sniffImage(_headerFor(mimeType)), mimeType);
      }
    });

    test('no accepted extension has a type nothing can produce', () {
      for (final entry in photoMimeTypes.entries) {
        expect(knownImageMimeTypes, contains(entry.value),
            reason: '${entry.key} is offered as ${entry.value}, which '
                'sniffImage never returns, so such a file could only ever be '
                'skipped');
      }
    });

    test('no convertible extension has a type nothing can produce', () {
      for (final entry in convertibleMimeTypes.entries) {
        expect(knownImageMimeTypes, contains(entry.value));
        expect(needsConversion(entry.value), isTrue,
            reason: '${entry.key} is listed as convertible but no shell would '
                'convert it');
      }
    });

    test('an extension is offered as exactly one of the two', () {
      expect(
        photoMimeTypes.keys.toSet().intersection(convertibleMimeTypes.keys.toSet()),
        isEmpty,
      );
      expect(scannableExtensions,
          hasLength(photoMimeTypes.length + convertibleMimeTypes.length));
    });

    test('a type a provider takes is never one a shell must convert', () {
      for (final mimeType in photoMimeTypes.values) {
        expect(needsConversion(mimeType), isFalse);
      }
      expect(needsConversion(heicMimeType), isTrue);
    });

    test('every offered extension is lower-case with a leading dot', () {
      for (final extension in scannableExtensions) {
        expect(extension, startsWith('.'));
        expect(extension, extension.toLowerCase());
        expect(extensionOf('shelf$extension'), extension);
      }
    });

    test('a convertible extension is also nameable as undecodable, so a shell '
        'without a converter still explains itself', () {
      expect(undecodableImageExtensions,
          containsAll(convertibleMimeTypes.keys));
    });
  });

  group('sniffImage', () {
    test('an honest name and a lying one give the same answer', () {
      // The whole reason the type comes from the bytes: this is what phones
      // and messaging apps do.
      final heic = _headerFor(heicMimeType);
      expect(sniffImage(heic), heicMimeType);
      expect(extensionOf('shelf.jpg'), '.jpg');
      expect(sniffImage(heic), isNot(photoMimeTypes['.jpg']));
    });

    test('anything it cannot name comes back null rather than guessed', () {
      expect(sniffImage(Uint8List(0)), isNull);
      expect(sniffImage(Uint8List.fromList([1, 2, 3])), isNull);
      // An AVIF is an ISO base media file too, and nothing here decodes it.
      expect(
        sniffImage(Uint8List.fromList(
            [0, 0, 0, 0x18, ...'ftyp'.codeUnits, ...'avif'.codeUnits])),
        isNull,
      );
      // A RIFF container that is not WebP (a .wav starts this way).
      expect(
        sniffImage(Uint8List.fromList(
            [...'RIFF'.codeUnits, 0, 0, 0, 0, ...'WAVE'.codeUnits])),
        isNull,
      );
    });

    test('it reads no further than it says it does', () {
      for (final mimeType in knownImageMimeTypes) {
        final header = Uint8List.fromList(
            _headerFor(mimeType).sublist(0, imageSignatureLength));
        expect(sniffImage(header), mimeType,
            reason: '$mimeType needs more than imageSignatureLength bytes, so '
                'a shell reading that many would misclassify it');
      }
    });

    test('a truncated file is named nothing, not named wrongly', () {
      for (final mimeType in knownImageMimeTypes) {
        final header = _headerFor(mimeType);
        for (var length = 0; length < 3; length++) {
          expect(sniffImage(Uint8List.sublistView(header, 0, length)),
              anyOf(isNull, mimeType));
        }
      }
    });
  });

  group('extensionOf', () {
    test('lower-cases and keeps the dot', () {
      expect(extensionOf('shelf-1.HEIC'), '.heic');
      expect(extensionOf('shelf_a.JPG'), '.jpg');
    });

    test('a name with no extension does not blow up', () {
      expect(extensionOf('README'), '');
      expect(extensionOf('.gitignore'), '');
      expect(extensionOf('trailing.'), '');
    });
  });
}
