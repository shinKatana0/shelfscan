/// The app's own pipeline over the three HEIC control originals (T-0039).
///
/// Every step below is the code the scan screen runs: the same
/// [loadPickedPhotos] with the same [platformHeicDecoder], the same
/// [ProviderPolicy] wiring, the same [Orchestrator]. Only the button taps
/// are missing, and this is the comparison against the CLI's own detections.
///
/// Off by default -- it needs Ollama and takes ~80 s:
/// `SHELFSCAN_PHOTOS=<the photo directory> SHELFSCAN_LIVE_SCAN=1
/// flutter test test/heic_end_to_end_test.dart`
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shelfscan_app/heic_wic.dart';
import 'package:shelfscan_app/photo_files.dart';
import 'package:shelfscan_app/provider_config.dart';
import 'package:shelfscan_core/shelfscan_core.dart';

void main() {
  final photos = Platform.environment['SHELFSCAN_PHOTOS'];
  final live = Platform.environment['SHELFSCAN_LIVE_SCAN'] != null;

  test('three .heic originals scan end to end', () async {
    final heics = [
      for (final entity in Directory(photos!).listSync())
        if (entity is File && entity.path.toLowerCase().endsWith('.heic'))
          entity
    ]..sort((a, b) => a.path.compareTo(b.path));
    expect(heics, hasLength(3));

    final started = Stopwatch()..start();
    final picked = await loadPickedPhotos(
      [
        for (final file in heics)
          (name: file.uri.pathSegments.last, bytes: file.readAsBytesSync())
      ],
      decodeHeic: platformHeicDecoder,
    );
    // ignore: avoid_print
    print('converted ${picked.photos.length} in ${started.elapsedMilliseconds} '
        'ms, rejected ${picked.rejected}');
    expect(picked.rejected, isEmpty);
    for (final photo in picked.photos) {
      expect(photo.mimeType, 'image/jpeg');
    }

    final settings = ProviderSettings(backend: VisionBackend.local);
    final doc = await Orchestrator(
      visionWorker: VisionWorker(ProviderPolicy.build(settings)),
      resolverWorker: ProviderPolicy.buildResolver(settings),
      visionConcurrency: ProviderPolicy.visionConcurrency(settings.backend),
    ).runScan(picked.photos,
        progress: ScanProgress(onWarning: (w) {
          // ignore: avoid_print
          print('warning: $w');
        }));

    // ignore: avoid_print
    print('detections: ${doc.games.length}, unreadable: '
        '${doc.unreadable.length}, photos: ${doc.photos.length}, '
        '${started.elapsed.inSeconds} s');
    // ignore: avoid_print
    print('platform hints: '
        '${doc.games.where((g) => g.detection.platformHint != null).length}');
    expect(doc.photos, hasLength(3));
    expect(doc.games, isNotEmpty);
  },
      timeout: const Timeout(Duration(minutes: 15)),
      skip: live && photos != null
          ? null
          : 'needs SHELFSCAN_LIVE_SCAN and SHELFSCAN_PHOTOS');
}
