/// The Android HEIC decode path (T-0346).
///
/// `flutter test` runs on flutter_tester, which has no platform channels and
/// no Android: what is testable here is the Dart half -- which decoder a host
/// gets, what crosses the channel, and that every way the Kotlin half can fail
/// arrives as a named [HeicDecodeException] rather than a null or a crash. The
/// decode itself is Android's and is checked on a device; doc/reports/T-0346.md
/// says what was and was not run.
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelfscan_app/heic_android.dart';
import 'package:shelfscan_app/heic_wic.dart';
import 'package:shelfscan_app/photo_files.dart';

/// A real HEIC file signature over invented bytes: `sniffImage` reads the
/// `ftyp` box and the brand, and nothing here decodes it.
final _heic = Uint8List.fromList([
  0, 0, 0, 24, ...'ftyp'.codeUnits, ...'heic'.codeUnits, //
  ...List.filled(12, 0),
]);
final _jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 9, 9]);

void _handler(Future<Object?> Function(MethodCall call)? handler) =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(heicMethodChannel, handler);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => _handler(null));

  group('which decoder a host gets', () {
    test('android gets the channel, windows keeps WIC', () {
      expect(heicDecoderFor('android'), equals(androidHeicToJpeg));
      expect(heicDecoderFor('windows'), equals(windowsHeicToJpeg));
    });

    test('a host with neither still names itself', () async {
      await expectLater(
        heicDecoderFor('linux')(_heic),
        throwsA(isA<HeicDecodeException>().having((e) => e.message, 'message',
            contains('Windows and Android'))),
      );
    });
  });

  group('what crosses the channel', () {
    test('the bytes go over as they are and come back as JPEG', () async {
      MethodCall? seen;
      _handler((call) async {
        seen = call;
        return _jpeg;
      });

      expect(await androidHeicToJpeg(_heic), _jpeg);
      expect(seen!.method, 'toJpeg');
      // Not a path and not base64: the standard codec carries the bytes.
      expect(seen!.arguments, isA<Uint8List>());
      expect(seen!.arguments, _heic);
    });

    test('the Kotlin half\'s reason reaches the user', () async {
      _handler((_) async => throw PlatformException(
          code: 'no-codec', message: 'this phone runs Android 8.1'));

      await expectLater(
        androidHeicToJpeg(_heic),
        throwsA(isA<HeicDecodeException>().having(
            (e) => e.message, 'message', contains('this phone runs Android'))),
      );
    });

    test('no image back is an exception, not a null', () async {
      _handler((_) async => null);

      await expectLater(
        androidHeicToJpeg(_heic),
        throwsA(isA<HeicDecodeException>()),
      );
    });

    test('an unregistered channel is named rather than crashing', () async {
      await expectLater(
        androidHeicToJpeg(_heic),
        throwsA(isA<HeicDecodeException>().having((e) => e.message, 'message',
            contains('no HEIC decoder wired up'))),
      );
    });
  });

  test('the picker path hands the scan JPEG bytes under the picked name',
      () async {
    _handler((_) async => _jpeg);

    // The seam `scan_screen.dart` uses, entered the way it enters it.
    final loaded = await loadPickedPhotos(
      [(name: 'phone.heic', bytes: _heic)],
      decodeHeic: heicDecoderFor('android'),
    );

    expect(loaded.rejected, isEmpty);
    expect(loaded.photos.single.mimeType, 'image/jpeg');
    expect(loaded.photos.single.bytes, _jpeg);
    expect(loaded.photos.single.name, 'phone.heic');
  });

  test('both halves agree on the channel name', () {
    final kotlin = File('android/app/src/main/kotlin/io/github/shinkatana0/'
            'shelfscan/HeicChannel.kt')
        .readAsStringSync();
    // The one failure invisible until a device runs it: rename one side and
    // every photo comes back MissingPluginException.
    expect(kotlin, contains('"${heicMethodChannel.name}"'));
    expect(kotlin, contains('"toJpeg"'));

    final main = File('android/app/src/main/kotlin/io/github/shinkatana0/'
            'shelfscan/MainActivity.kt')
        .readAsStringSync();
    expect(main, contains('registerHeicChannel'),
        reason: 'the channel exists but nothing registers it');
  });
}
