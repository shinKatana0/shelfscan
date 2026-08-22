/// Turning picked files into [PhotoInput]s, with the mime type their bytes
/// actually are.
///
/// Which extensions are offered and what each byte sequence is called are not
/// decided here: they come from `shelfscan_core`, which the CLI reads too, so
/// the two shells cannot drift apart again (T-0056). What is left in this file
/// is what is genuinely the app's -- the picker's spelling of an extension,
/// and calling out to a HEIC decoder.
library;

import 'dart:typed_data';

import 'package:shelfscan_core/shelfscan_core.dart';

import 'heic_wic.dart';

/// What the file dialog offers, dots stripped the way `file_picker` wants.
///
/// The Windows dialog's own `FileType.image` filter has no HEIC in it, which
/// is why the phone's HEIC photos were not merely unreadable but invisible
/// (T-0039).
List<String> get pickerExtensions =>
    [for (final extension in scannableExtensions) extension.substring(1)];

/// Why a picked file is not a photo.
///
/// The middle case is what sniffing the bytes exposes: the old wording told
/// the owner of an unreadable `.jpg` to convert it to `.jpg`, because the one
/// thing wrong with the file is its name. The CLI answers the same file in the
/// same terms (T-0056).
String _rejectReason(String fileName) {
  final extension = extensionOf(fileName);
  if (extension.isEmpty) return 'not a photo this app can read';
  if (photoMimeTypes.containsKey(extension) ||
      convertibleMimeTypes.containsKey(extension)) {
    return 'named $extension but the bytes are not a photo this app reads; '
        'the contents decide here, not the name';
  }
  return 'a $extension this app cannot read; convert it to .jpg or .png first';
}

/// A file the user chose and the app will not scan, with the reason.
class RejectedPhoto {
  RejectedPhoto({required this.name, required this.reason});

  final String name;
  final String reason;

  @override
  String toString() => '$name -- $reason';
}

/// The outcome of one "Add photos": what the scan can use, and what it
/// cannot, named.
class PickedPhotos {
  PickedPhotos({required this.photos, required this.rejected});

  final List<PhotoInput> photos;
  final List<RejectedPhoto> rejected;
}

/// A file as the picker handed it over.
typedef PickedFile = ({String name, Uint8List bytes});

/// Converts what needs converting and names the rest, so a file the app
/// cannot read is reported when the user picks it rather than at a provider
/// call minutes later (decision 0012: a silent failure is worse than a loud
/// one).
///
/// [onConverting] fires before each conversion, which blocks for ~0.4 s per
/// phone photo.
Future<PickedPhotos> loadPickedPhotos(
  List<PickedFile> picked, {
  required HeicDecoder decodeHeic,
  void Function(String name)? onConverting,
}) async {
  final photos = <PhotoInput>[];
  final rejected = <RejectedPhoto>[];
  for (final file in picked) {
    final kind = sniffImage(file.bytes);
    if (kind == null) {
      rejected.add(
          RejectedPhoto(name: file.name, reason: _rejectReason(file.name)));
      continue;
    }
    if (!needsConversion(kind)) {
      photos.add(
          PhotoInput(name: file.name, bytes: file.bytes, mimeType: kind));
      continue;
    }
    onConverting?.call(file.name);
    try {
      final jpeg = await decodeHeic(file.bytes);
      // Keeps the picked name -- that is the file the user has, and what
      // `source_photo` should point at -- so the extension still says .heic
      // while the bytes are JPEG.
      photos.add(
          PhotoInput(name: file.name, bytes: jpeg, mimeType: 'image/jpeg'));
    } on Object catch (e) {
      rejected.add(RejectedPhoto(name: file.name, reason: '$e'));
    }
  }
  return PickedPhotos(photos: photos, rejected: rejected);
}
