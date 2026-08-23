/// What Stop stops, and what the user keeps when it does (T-0121).
///
/// Every assertion here is about calls that did NOT happen, not about a future
/// that completed: the defect is a run that cost money after the user asked it
/// to stop, and a stopped future proves nothing about that. So the fakes record
/// what they were asked for and the tests read those lists.
library;

import 'dart:typed_data';

import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

PhotoInput _photo(int id) => PhotoInput(
      name: 'shelf_$id.jpg',
      bytes: Uint8List.fromList([id]),
    );

Detection _read(String title, String photo) => Detection(
      rawTitle: title,
      mediaType: MediaType.disc,
      confidence: 1.0,
      sourcePhoto: photo,
    );

/// Reads one row per photo and records every photo it was handed.
class _RecordingVision implements VisionProvider {
  _RecordingVision({this.stopAfter, this.stop, this.failing = const {}});

  /// Stops [stop] as the nth photo is read, so the stop lands mid-run at a
  /// known point instead of at a wall-clock guess.
  final int? stopAfter;
  final StopToken? stop;
  final Set<String> failing;
  final asked = <String>[];

  @override
  Future<PhotoAnalysis> analyze(PhotoInput photo) async {
    asked.add(photo.name);
    if (asked.length == stopAfter) stop?.stop();
    await Future<void>.delayed(Duration.zero);
    if (failing.contains(photo.name)) throw StateError('vision is down');
    return PhotoAnalysis(items: [_read('TITLE ${photo.name}', photo.name)]);
  }
}

/// Answers every detection with a match, counts them, and never touches IGDB.
class _RecordingResolver extends SkipResolver {
  _RecordingResolver({this.stopAfter, this.stop});

  final int? stopAfter;
  final StopToken? stop;
  final asked = <String>[];

  @override
  Future<ResolvedGame> process(Detection task) async {
    asked.add(task.rawTitle);
    if (asked.length == stopAfter) stop?.stop();
    return ResolvedGame(
      detection: task,
      best: Candidate(
        externalId: 'igdb:${asked.length}',
        title: task.rawTitle,
        platformId: 48,
        platformName: 'PlayStation 4',
        score: 1.0,
      ),
    );
  }
}

Orchestrator _orchestrator(VisionProvider vision, ResolverWorker resolver) =>
    Orchestrator(
      visionWorker: VisionWorker(vision),
      resolverWorker: resolver,
      // One at a time on both stages, so "what had started when the stop
      // arrived" is a fact of the test rather than a race.
      visionConcurrency: 1,
      resolverConcurrency: 1,
    );

void main() {
  group('the pool', () {
    test('pulls nothing more once it is stopped', () async {
      final stop = StopToken();
      final started = <int>[];

      final results = await runPool<int, int>(
        [0, 1, 2, 3, 4, 5],
        (item) async {
          started.add(item);
          if (item == 1) stop.stop();
          await Future<void>.delayed(Duration.zero);
          return item;
        },
        concurrency: 1,
        stop: stop,
      );

      expect(started, [0, 1]);
      expect(results, [0, 1]);
    });

    test('lets the lanes already holding an item finish it', () async {
      final stop = StopToken();
      final started = <int>[];
      final finished = <int>[];

      await runPool<int, int>(
        [0, 1, 2, 3, 4, 5],
        (item) async {
          started.add(item);
          // The third lane stops it, so all three are holding an item: a lane
          // that has not pulled yet returns on the check instead.
          if (item == 2) stop.stop();
          await Future<void>.delayed(const Duration(milliseconds: 5));
          finished.add(item);
          return item;
        },
        concurrency: 3,
        stop: stop,
      );

      // All three in-flight items finish, and nothing beyond them begins.
      expect(started, [0, 1, 2]);
      expect(finished..sort(), [0, 1, 2]);
    });

    test('a token that is never stopped changes nothing', () async {
      final results = await runPool<int, int>(
        [0, 1, 2, 3],
        (item) async => item * 2,
        concurrency: 2,
        stop: StopToken(),
      );

      expect(results..sort(), [0, 2, 4, 6]);
    });
  });

  group('a scan stopped during vision', () {
    test('sends no further photo, and names the ones it did not', () async {
      final stop = StopToken();
      final vision = _RecordingVision(stopAfter: 2, stop: stop);
      final resolver = _RecordingResolver();
      final warnings = <String>[];

      final doc = await _orchestrator(vision, resolver).runScan(
        [for (var i = 0; i < 5; i++) _photo(i)],
        progress: ScanProgress(onWarning: (w) => warnings.add(w.message)),
        stop: stop,
      );

      expect(vision.asked, ['shelf_0.jpg', 'shelf_1.jpg']);
      expect(doc.games, hasLength(2));
      expect([for (final game in doc.games) game.detection.sourcePhoto],
          ['shelf_0.jpg', 'shelf_1.jpg']);
      // The document still lists every photo the user chose, so the review
      // screen can group the missing shelves as empty rather than forget them.
      expect(doc.photos, hasLength(5));
      for (final name in ['shelf_2.jpg', 'shelf_3.jpg', 'shelf_4.jpg']) {
        expect(warnings.where((w) => w.contains(name)), hasLength(1),
            reason: '$name must be named exactly once as not looked at');
      }
    });

    test('starts no IGDB request afterwards, and keeps the reads unmatched',
        () async {
      final stop = StopToken();
      final vision = _RecordingVision(stopAfter: 1, stop: stop);
      final resolver = _RecordingResolver();
      final warnings = <String>[];

      final doc = await _orchestrator(vision, resolver).runScan(
        [for (var i = 0; i < 3; i++) _photo(i)],
        progress: ScanProgress(onWarning: (w) => warnings.add(w.message)),
        stop: stop,
      );

      expect(resolver.asked, isEmpty,
          reason: 'a stop that only stopped vision would answer the user by '
              'starting the next stage');
      expect(doc.games.single.detection.rawTitle, 'TITLE shelf_0.jpg');
      expect(doc.games.single.best, isNull);
      expect(warnings.where((w) => w.contains('unmatched')), hasLength(1));
    });

    test('throws when nothing was read, rather than claiming an empty shelf',
        () async {
      final stop = StopToken()..stop();
      final vision = _RecordingVision();

      await expectLater(
        _orchestrator(vision, _RecordingResolver())
            .runScan([for (var i = 0; i < 3; i++) _photo(i)], stop: stop),
        throwsA(isA<ScanStoppedException>()
            .having((e) => e.notLookedAt, 'notLookedAt',
                ['shelf_0.jpg', 'shelf_1.jpg', 'shelf_2.jpg'])
            .having((e) => e.message, 'message', contains('shelf_2.jpg'))),
      );
      expect(vision.asked, isEmpty);
    });

    test('says the run was stopped even when a photo failed before it',
        () async {
      // Both things are true and the stop is the one that decides the type:
      // "all 1 photo(s) failed" would be a false account of a five-photo run.
      final stop = StopToken();
      final vision = _RecordingVision(
          stopAfter: 1, stop: stop, failing: {'shelf_0.jpg'});

      try {
        await _orchestrator(vision, _RecordingResolver())
            .runScan([for (var i = 0; i < 5; i++) _photo(i)], stop: stop);
        fail('a run that read nothing must not return a document');
      } on ScanStoppedException catch (e) {
        expect(e.failures.single.$1, 'shelf_0.jpg');
        expect(e.notLookedAt, hasLength(4));
        expect(e.message, contains('1 photo(s) failed before the stop'));
      }
    });
  });

  test('a scan stopped during resolve keeps every read it paid for', () async {
    final stop = StopToken();
    final vision = _RecordingVision();
    final resolver = _RecordingResolver(stopAfter: 2, stop: stop);
    final warnings = <String>[];

    final doc = await _orchestrator(vision, resolver).runScan(
      [for (var i = 0; i < 4; i++) _photo(i)],
      progress: ScanProgress(onWarning: (w) => warnings.add(w.message)),
      stop: stop,
    );

    expect(vision.asked, hasLength(4), reason: 'vision finished before the stop');
    expect(resolver.asked, hasLength(2));
    // Every row is present and in document order; the two the stop kept out
    // are the unresolved shape a failed resolution already takes.
    expect([for (final game in doc.games) game.detection.sourcePhoto],
        ['shelf_0.jpg', 'shelf_1.jpg', 'shelf_2.jpg', 'shelf_3.jpg']);
    expect([for (final game in doc.games) game.best != null],
        [true, true, false, false]);
    expect(warnings.single, contains('2 detection(s)'));
  });

  test('a token that is never stopped scans exactly as no token does',
      () async {
    final photos = [for (var i = 0; i < 4; i++) _photo(i)];

    final withToken = await _orchestrator(_RecordingVision(), _RecordingResolver())
        .runScan(photos, stop: StopToken());
    final without = await _orchestrator(_RecordingVision(), _RecordingResolver())
        .runScan(photos);

    expect([for (final game in withToken.games) game.toJson().toString()],
        [for (final game in without.games) game.toJson().toString()]);
    expect(withToken.games, hasLength(4));
  });
}
