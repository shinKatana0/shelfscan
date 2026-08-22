/// What a photo's bytes are, and which file names a shell offers to read.
///
/// This is core rather than shell code because the answer is a property of the
/// bytes, not of the platform: `PhotoInput.mimeType` is what both cloud
/// providers label the upload with, and both fall back to `image/jpeg` when it
/// is null. Nothing here reads a file, decodes an image or needs a package, so
/// the boundary ARCHITECTURE.md draws is untouched -- naming bytes is not
/// decoding them, and HEIC conversion stays in the shells (WIC over FFI in the
/// app, PowerShell in the CLI).
///
/// It lives in one place because it used to live in two. T-0036 made the
/// accepted extensions and their types a single table so an extension could
/// not be accepted with no type to declare; T-0039 then built a second table
/// in the app, and the two drifted -- the app's read the file signature, the
/// CLI's trusted the extension, so a HEIC renamed `.jpg` was converted by one
/// shell and declared `image/jpeg` by the other (T-0056).
library;

import 'dart:typed_data';

/// Extensions a shell offers to read, each with the type those bytes carry
/// when the name is honest.
///
/// One table rather than a list of accepted extensions plus a mapping
/// elsewhere: an extension accepted with no entry here would send PNG or WebP
/// bytes to Anthropic under a JPEG label (T-0036). The name only decides what
/// a shell offers -- [sniffImage] decides what a file actually is.
const photoMimeTypes = {
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.png': 'image/png',
  '.webp': 'image/webp',
};

/// The one type this project can name but no provider takes.
const heicMimeType = 'image/heic';

/// Extensions that name [heicMimeType] bytes.
///
/// HEIC only, though the Windows codec would also decode `.tif` and the raw
/// formats: none of those is what a phone camera produces by default, and
/// each would need its own equivalence measurement first.
const convertibleMimeTypes = {
  '.heic': heicMimeType,
  '.heif': heicMimeType,
  '.hif': heicMimeType,
};

/// Every type [sniffImage] can answer with.
const knownImageMimeTypes = {
  'image/jpeg',
  'image/png',
  'image/webp',
  heicMimeType,
};

/// Image formats nameable from a file name but not readable here.
///
/// Kept apart from "not an image at all" only so a shell's warning can tell
/// the user what to do about it (T-0025).
const undecodableImageExtensions = {
  '.heic',
  '.heif',
  '.hif',
  '.avif',
  '.tif',
  '.tiff',
  '.bmp',
  '.gif',
  '.dng',
  '.cr2',
  '.nef',
  '.arw',
};

/// Every extension a shell offers: those a provider takes as they are, then
/// those it has to convert first.
List<String> get scannableExtensions =>
    [...photoMimeTypes.keys, ...convertibleMimeTypes.keys];

/// Whether a shell must convert [mimeType] before a provider will take it.
///
/// Neither Anthropic nor the OpenAI-compatible endpoints accept
/// [heicMimeType], so those bytes cannot be forwarded as they are.
bool needsConversion(String mimeType) => mimeType == heicMimeType;

/// How many leading bytes [sniffImage] looks at.
///
/// A shell classifying a file on disk need read no more than this. The longest
/// checks are the ISO base media brand and the `WEBP` tag, both ending at
/// offset 12.
const imageSignatureLength = 12;

/// ISO base media brands meaning "HEVC still image", plus the two generic ones
/// a phone writes for a single-image or burst HEIC.
const _heifBrands = {
  'heic', 'heix', 'heim', 'heis', 'hevc', 'hevx', 'hevm', 'hevs',
  'mif1', 'msf1',
};

/// What [bytes] are, from the file signature, or null when this project cannot
/// name them.
///
/// The signature and not the file name decides, because the type must describe
/// the bytes: phones and messaging apps rename HEIC to `.jpg`, and declaring
/// those `image/jpeg` is exactly the failure T-0036 fixed one level down.
/// Fewer than [imageSignatureLength] bytes is not an error -- a short file
/// simply matches nothing.
String? sniffImage(Uint8List bytes) {
  bool at(int offset, List<int> signature) {
    if (bytes.length < offset + signature.length) return false;
    for (var i = 0; i < signature.length; i++) {
      if (bytes[offset + i] != signature[i]) return false;
    }
    return true;
  }

  bool ascii(int offset, String text) => at(offset, text.codeUnits);

  if (at(0, const [0xFF, 0xD8, 0xFF])) return 'image/jpeg';
  if (at(0, const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) {
    return 'image/png';
  }
  if (ascii(0, 'RIFF') && ascii(8, 'WEBP')) return 'image/webp';
  if (ascii(4, 'ftyp') && bytes.length >= 12) {
    final brand = String.fromCharCodes(bytes.sublist(8, 12)).toLowerCase();
    if (_heifBrands.contains(brand)) return heicMimeType;
  }
  return null;
}

/// Lower-cased extension of [fileName], dot included, or `''` if it has none.
String extensionOf(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot <= 0 || dot == fileName.length - 1) return '';
  return fileName.substring(dot).toLowerCase();
}
