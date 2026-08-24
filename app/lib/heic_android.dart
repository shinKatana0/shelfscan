/// HEIC -> JPEG on Android, through the platform's own decoder.
///
/// A platform channel rather than a pub plugin, and the argument is cost
/// rather than taste. `BitmapFactory` has decoded HEIF since API 28, so the
/// codec is already on the device and the channel adds **no dependency at
/// all**: no Kotlin Gradle Plugin posture to check against Flutter's Built-in
/// Kotlin migration, and nothing to drag into version solving. That is the
/// price this tree has already paid twice -- T-0304 moved three plugins and
/// 23 packages to get off KGP because one shared transitive major bound them
/// together, and T-0293/`doc/android-build.md` record what a plugin's Kotlin
/// posture costs when it goes wrong. The app module already compiles Kotlin
/// (`MainActivity.kt`), so the channel's Kotlin half costs one file and no
/// Gradle change.
///
/// The decode runs on a background task queue on the Android side, off the
/// platform thread, for the same reason the Windows path runs in an isolate.
library;

import 'package:flutter/services.dart';

import 'heic_decoder.dart';

/// The Kotlin half is `android/app/src/main/kotlin/.../HeicChannel.kt`.
const heicMethodChannel = MethodChannel('io.github.shinkatana0.shelfscan/heic');

/// Turns HEIC bytes into JPEG bytes on Android, or throws
/// [HeicDecodeException].
///
/// Bytes both ways: the standard codec carries a `Uint8List` as a Kotlin
/// `ByteArray` without encoding it, and a file path would not survive the
/// boundary anyway (ARCHITECTURE.md -- photos travel as bytes).
Future<Uint8List> androidHeicToJpeg(Uint8List heic) async {
  final Uint8List? jpeg;
  try {
    jpeg = await heicMethodChannel.invokeMethod<Uint8List>('toJpeg', heic);
  } on PlatformException catch (e) {
    throw HeicDecodeException(e.message ?? 'Android could not decode the HEIC');
  } on MissingPluginException {
    throw HeicDecodeException(
        'this build has no HEIC decoder wired up on Android');
  }
  if (jpeg == null) {
    throw HeicDecodeException('the Android decoder produced no image');
  }
  return jpeg;
}
