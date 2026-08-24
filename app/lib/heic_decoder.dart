/// What a HEIC decoder is, and how it fails.
///
/// Its own file only so the two implementations -- `heic_wic.dart` (Windows,
/// WIC over `dart:ffi`) and `heic_android.dart` (Android, a platform channel)
/// -- can share the vocabulary without importing each other. `heic_wic.dart`
/// re-exports it, so every existing importer of that file is unaffected.
library;

import 'dart:typed_data';

/// A HEIC that could not be turned into JPEG bytes, and why.
class HeicDecodeException implements Exception {
  HeicDecodeException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Turns HEIC bytes into JPEG bytes, or throws [HeicDecodeException].
typedef HeicDecoder = Future<Uint8List> Function(Uint8List heic);
