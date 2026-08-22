/// Where a spine caught on TWO photos lands in `games` (T-0085).
///
/// A detection read on one photo never left its own block, so the resolve
/// stage (T-0068) and the unreadable list (T-0073) could both be pinned
/// without this surfacing. A merged one belongs to two photos, and until this
/// task the one that placed it was whichever answered first.
///
/// The only way to test that is to feed the same reads back in a different
/// completion order. Asserting that `List.sort` is stable would test a claim
/// Dart does not make, and would not settle it anyway: what the sort receives
/// is the race.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

/// [id] rides in the bytes so two photos may share a name.
PhotoInput _photo(int id, {String? name}) => PhotoInput(
      name: name ?? 'shelf_${id.toString().padLeft(2, '0')}.jpg',
      bytes: Uint8List.fromList([id]),
    );

Detection _read(String title, String photo, {String? hint}) => Detection(
      rawTitle: title,
      mediaType: MediaType.disc,
      confidence: 1.0,
      sourcePhoto: photo,
      platformHint: hint,
    );

/// Reads a scripted answer per photo, after a per-photo delay.
///
/// The delays exist to make the pool answer in an order the input did not
/// have: without them these tests pass on code that never reorders anything.
class _Shelves implements VisionProvider {
  _Shelves(this.reads, {this.delays = const {}, this.failing = const {}});

  /// Photo id -> what the model claims to see on it.
  final Map<int, PhotoAnalysis> reads;

  /// Photo id -> milliseconds that photo takes.
  final Map<int, int> delays;

  /// Photo ids the provider throws on, so `runPool` drops them.
  final Set<int> failing;
  final completed = <int>[];

  @override
  Future<PhotoAnalysis> analyze(PhotoInput photo) async {
    final id = photo.bytes.first;
    await Future<void>.delayed(Duration(milliseconds: delays[id] ?? 0));
    if (failing.contains(id)) throw StateError('vision is down');
    completed.add(id);
    return reads[id] ?? const PhotoAnalysis();
  }
}

Future<ReviewDocument> _scan(List<PhotoInput> photos, VisionProvider provider) =>
    Orchestrator(
      visionWorker: VisionWorker(provider),
      resolverWorker: SkipResolver(),
      visionConcurrency: photos.length,
    ).runScan(photos);

List<String> _titles(ReviewDocument doc) =>
    [for (final game in doc.games) game.detection.rawTitle];

/// Every field that reaches the file, so a move cannot hide in a tie.
List<String> _rows(ReviewDocument doc) =>
    [for (final game in doc.games) jsonEncode(game.toJson())];

/// The brief's own measurement: two photos, five reads, one spine on both.
///
/// `shelf_b.jpg` yields more, so its read of the shared spine wins the merge
/// (`_photoYield`, T-0027) while `shelf_a.jpg` is where the spine is first
/// seen -- the two halves of the answer land on different photos here on
/// purpose.
({List<PhotoInput> photos, Map<int, PhotoAnalysis> reads}) _sharedSpine() {
  final photos = [_photo(0, name: 'shelf_a.jpg'), _photo(1, name: 'shelf_b.jpg')];
  return (
    photos: photos,
    reads: {
      0: PhotoAnalysis(items: [
        _read('ONLY ON A', 'shelf_a.jpg'),
        _read('Shared Spine', 'shelf_a.jpg'),
      ]),
      1: PhotoAnalysis(items: [
        _read('B ONE', 'shelf_b.jpg'),
        _read('SHARED SPINE', 'shelf_b.jpg'),
        _read('B TWO', 'shelf_b.jpg'),
      ]),
    },
  );
}

/// [photos] photos of [each] rows, every even photo sharing one spine with the
/// photo after it, and every odd photo one row longer so it wins those merges.
({List<PhotoInput> photos, Map<int, PhotoAnalysis> reads}) _shelf(
    int photos, int each) {
  final inputs = [for (var p = 0; p < photos; p++) _photo(p)];
  PhotoAnalysis read(int p) {
    final name = inputs[p].name;
    return PhotoAnalysis(items: [
      for (var i = 0; i < each + (p.isOdd ? 1 : 0); i++)
        _read('P$p ROW $i', name),
      _read('SHARED ${p.isOdd ? p - 1 : p}', name),
    ]);
  }

  return (photos: inputs, reads: {for (var p = 0; p < photos; p++) p: read(p)});
}

void main() {
  group('a spine on two photos', () {
    final shelf = _sharedSpine();

    test('lands in the same place however the photos come back', () async {
      final aFirst = _Shelves(shelf.reads, delays: {1: 30});
      final bFirst = _Shelves(shelf.reads, delays: {0: 30});

      final first = await _scan(shelf.photos, aFirst);
      final second = await _scan(shelf.photos, bFirst);

      expect(aFirst.completed, [0, 1]);
      expect(bFirst.completed, [1, 0],
          reason: 'the two scans must read the photos in different orders, '
              'or this proves nothing');
      expect(_rows(first), _rows(second));
      // Completion order gave the second list [ONLY ON A, B ONE, SHARED,
      // B TWO] before this task.
      expect(_titles(first), ['ONLY ON A', 'SHARED SPINE', 'B ONE', 'B TWO']);
    });

    test('is placed by the photo that saw it first and typed by the photo '
        'that won the merge', () async {
      final doc = await _scan(shelf.photos, _Shelves(shelf.reads, delays: {0: 30}));
      final merged = doc.games[1].detection;

      expect(merged.rawTitle, 'SHARED SPINE',
          reason: 'shelf_b yields 3 rows against shelf_a 2, so its read wins');
      expect(merged.sourcePhoto, 'shelf_b.jpg');
      // Filed under shelf_b by the winning read, ahead of shelf_b's own rows
      // by shelf_a's first sight: a merged row sits against the edge of the
      // winner's block that faces the other photo.
      expect(_titles(doc).indexOf('SHARED SPINE'),
          lessThan(_titles(doc).indexOf('B ONE')));
    });

    test('does not move when the photos are listed the other way round',
        () async {
      final provider = _Shelves(shelf.reads);

      final forwards = await _scan(shelf.photos, provider);
      final backwards = await _scan(shelf.photos.reversed.toList(), provider);

      expect(_rows(backwards), _rows(forwards),
          reason: 'the photo NAME groups the document at both ends, so '
              'listing the same photos in another order must not move a row');
    });
  });

  group('twelve photos, six merges', () {
    // Bigger than the n=33 at which Dart 3.13's sort stops handing equal keys
    // back in input order (measured in T-0073), and every odd photo wins the
    // merge it shares with the even one before it, so six rows are placed by
    // one photo and typed by another.
    final shelf = _shelf(12, 3);

    test('agree row for row however the photos come back', () async {
      final ascending = _Shelves(shelf.reads,
          delays: {for (var p = 0; p < 12; p++) p: p * 4});
      final descending = _Shelves(shelf.reads,
          delays: {for (var p = 0; p < 12; p++) p: (12 - p) * 4});

      final first = await _scan(shelf.photos, ascending);
      final second = await _scan(shelf.photos, descending);

      expect(ascending.completed, isNot(descending.completed));
      expect(_rows(first), _rows(second));
    });

    test('and however the photos are listed', () async {
      final forwards = await _scan(shelf.photos, _Shelves(shelf.reads));
      final backwards =
          await _scan(shelf.photos.reversed.toList(), _Shelves(shelf.reads));

      expect(_rows(backwards), _rows(forwards));
    });

    test('two photos of one name are separated by their input position',
        () async {
      // The name ties here, so nothing but the position can decide, and the
      // photo that finishes first is not the one listed first.
      final photos = [
        _photo(0, name: 'shelf.jpg'),
        _photo(1, name: 'shelf.jpg'),
      ];
      final provider = _Shelves({
        0: PhotoAnalysis(items: [
          _read('FIRST ONLY', 'shelf.jpg'),
          _read('SHARED', 'shelf.jpg'),
        ]),
        1: PhotoAnalysis(items: [
          _read('SECOND ONLY', 'shelf.jpg'),
          _read('SHARED', 'shelf.jpg'),
        ]),
      }, delays: {
        0: 30
      });

      final doc = await _scan(photos, provider);

      expect(provider.completed, [1, 0]);
      expect(_titles(doc), ['FIRST ONLY', 'SHARED', 'SECOND ONLY']);
    });

    test('a photo that failed leaves the rest in place', () async {
      final provider = _Shelves(shelf.reads,
          delays: {0: 30}, failing: {4});
      final warnings = <String>[];

      final doc = await Orchestrator(
        visionWorker: VisionWorker(provider),
        resolverWorker: SkipResolver(),
        visionConcurrency: 12,
      ).runScan(shelf.photos,
          progress: ScanProgress(onWarning: (w) => warnings.add(w.message)));

      expect(warnings.single, contains('shelf_04.jpg'));
      expect(_titles(doc), isNot(contains('P4 ROW 0')));
      expect(_titles(doc).where((t) => t.startsWith('P3 ')).toList(),
          ['P3 ROW 0', 'P3 ROW 1', 'P3 ROW 2', 'P3 ROW 3']);
    });
  });

  group('what merges is untouched', () {
    test('same rows, same count, whichever order they arrive in', () async {
      final shelf = _shelf(12, 3);
      // 12 photos: 6 x 3 rows + 6 x 4 rows = 42, plus 12 shared reads of 6
      // spines = 54 detections merging to 48 rows.
      final ascending = await _scan(shelf.photos,
          _Shelves(shelf.reads, delays: {for (var p = 0; p < 12; p++) p: p * 4}));
      final descending = await _scan(
          shelf.photos,
          _Shelves(shelf.reads,
              delays: {for (var p = 0; p < 12; p++) p: (12 - p) * 4}));

      expect(ascending.games, hasLength(48));
      expect(_titles(ascending).toSet(), _titles(descending).toSet());
      expect(_titles(ascending).where((t) => t.startsWith('SHARED')).toList(),
          hasLength(6));
      // The winning read is decided by photo yield, not by arrival, so a
      // merged row is typed the same way in both.
      for (final doc in [ascending, descending]) {
        expect([
          for (final game in doc.games)
            if (game.detection.rawTitle.startsWith('SHARED'))
              game.detection.sourcePhoto,
        ], [
          for (var p = 1; p < 12; p += 2) 'shelf_${p.toString().padLeft(2, '0')}.jpg',
        ]);
      }
    });

    test('a hint that differs still keeps two rows', () async {
      // The hint gate (T-0018) is what decides this, and stage 1 must not
      // reach it: the same spine read with two hints stays two rows.
      final photos = [_photo(0), _photo(1)];
      final provider = _Shelves({
        0: PhotoAnalysis(
            items: [_read('SAME TITLE', 'shelf_00.jpg', hint: 'SWITCH')]),
        1: PhotoAnalysis(
            items: [_read('SAME TITLE', 'shelf_01.jpg', hint: 'PS5')]),
      }, delays: {
        0: 30
      });

      final doc = await _scan(photos, provider);

      expect(_titles(doc), ['SAME TITLE', 'SAME TITLE']);
      expect([for (final game in doc.games) game.detection.platformHint],
          ['SWITCH', 'PS5']);
    });
  });
}
