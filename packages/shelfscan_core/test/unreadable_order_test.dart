/// Order of `Orchestrator.runScan`'s `unreadable` list (T-0073, T-0068).
///
/// Nothing on an `UnreadSpineReport` can decide the order: two spines of one
/// photo differ in no field at all when `UnreadSpineReport.titleless` made them.
/// So the order has to come from the input positions, and the only way to test
/// that is to feed the same reads back in a different order -- an assertion
/// that `List.sort` is stable would be testing a claim Dart does not make, and
/// stability would not settle this anyway: it hands back whatever order the
/// vision pool completed in.
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

UnreadSpineReport _spine(String photo, String reason) =>
    UnreadSpineReport(sourcePhoto: photo, script: SpineScript.japanese, reason: reason);

/// Reads a scripted answer per photo, after a per-photo delay.
///
/// The delays exist to make the pool answer in an order the input did not
/// have: without them these tests pass on code that never reorders anything.
class _Shelves implements VisionProvider {
  _Shelves(this.reads, {this.delays = const {}});

  /// Photo id -> what the model claims to see on it.
  final Map<int, PhotoAnalysis> reads;

  /// Photo id -> milliseconds that photo takes.
  final Map<int, int> delays;
  final completed = <int>[];

  @override
  Future<PhotoAnalysis> analyze(PhotoInput photo) async {
    final id = photo.bytes.first;
    await Future<void>.delayed(Duration(milliseconds: delays[id] ?? 0));
    completed.add(id);
    return reads[id] ?? const PhotoAnalysis();
  }
}

Future<ReviewDocument> _scan(List<PhotoInput> photos, VisionProvider provider,
        {VisionProvider? secondReader}) =>
    Orchestrator(
      visionWorker: VisionWorker(provider, secondReader: secondReader),
      resolverWorker: SkipResolver(),
      visionConcurrency: photos.length,
    ).runScan(photos);

/// Every field that reaches the file, so a reordering cannot hide in a tie.
List<String> _rows(ReviewDocument doc) =>
    [for (final spine in doc.unreadable) jsonEncode(spine.toJson())];

/// [photos] photos, [each] distinguishable unread spines on every one.
({List<PhotoInput> photos, Map<int, PhotoAnalysis> reads}) _shelf(
    int photos, int each) {
  final inputs = [for (var p = 0; p < photos; p++) _photo(p)];
  return (
    photos: inputs,
    reads: {
      for (var p = 0; p < photos; p++)
        p: PhotoAnalysis(unreadable: [
          for (var i = 0; i < each; i++) _spine(inputs[p].name, 'spine $p.$i'),
        ]),
    },
  );
}

void main() {
  group('two scans of the same photos', () {
    // 12 x 3 is the shape the hi-res control document has (3 per photo) at a
    // size the old key could not hold: measured on Dart 3.13, `List.sort`
    // leaves equal keys in input order up to n=33 and no longer does at n=40.
    final shelf = _shelf(12, 3);
    final expected = [
      for (var p = 0; p < 12; p++)
        for (var i = 0; i < 3; i++)
          jsonEncode(_spine(shelf.photos[p].name, 'spine $p.$i').toJson()),
    ];

    test('agree entry for entry however the photos come back', () async {
      final ascending = _Shelves(shelf.reads,
          delays: {for (var p = 0; p < 12; p++) p: p * 4});
      final descending = _Shelves(shelf.reads,
          delays: {for (var p = 0; p < 12; p++) p: (12 - p) * 4});

      final first = await _scan(shelf.photos, ascending);
      final second = await _scan(shelf.photos, descending);

      expect(ascending.completed, isNot(descending.completed),
          reason: 'the two scans must read the photos in different orders, '
              'or this proves nothing');
      expect(_rows(first), _rows(second));
      expect(_rows(first), expected);
    });

    test('and the photos themselves may be listed in any order', () async {
      final provider = _Shelves(shelf.reads);
      final forwards = await _scan(shelf.photos, provider);
      final backwards = await _scan(shelf.photos.reversed.toList(), provider);

      expect(_rows(backwards), _rows(forwards),
          reason: 'the photo NAME groups, so listing the same photos in '
              'another order must not move a spine');
    });
  });

  group('the ordering key', () {
    test('groups by photo, keeps read order inside a photo', () async {
      final photos = [_photo(0), _photo(1)];
      final provider = _Shelves({
        0: PhotoAnalysis(unreadable: [
          _spine('shelf_00.jpg', 'first'),
          _spine('shelf_00.jpg', 'second'),
        ]),
        1: PhotoAnalysis(unreadable: [_spine('shelf_01.jpg', 'only')]),
      }, delays: {
        0: 30
      });

      final doc = await _scan(photos, provider);

      expect(provider.completed, [1, 0]);
      expect([for (final spine in doc.unreadable) spine.reason],
          ['first', 'second', 'only']);
    });

    test('holds when one photo carries more spines than the sort is stable '
        'over', () async {
      // 45 on one photo, past the n=40 where the sort stops preserving input
      // order: the read position is the only thing left to order them.
      final spines = [
        for (var i = 0; i < 45; i++) _spine('shelf_00.jpg', 'spine $i'),
      ];
      final doc = await _scan([_photo(0)],
          _Shelves({0: PhotoAnalysis(unreadable: spines)}));

      expect([for (final spine in doc.unreadable) spine.reason],
          [for (var i = 0; i < 45; i++) 'spine $i']);
    });

    test('two photos of one name are separated by their input position',
        () async {
      // The name ties here, so nothing but the position can decide, and the
      // photo that finishes first is not the one listed first.
      final photos = [_photo(0, name: 'shelf.jpg'), _photo(1, name: 'shelf.jpg')];
      final provider = _Shelves({
        0: PhotoAnalysis(unreadable: [_spine('shelf.jpg', 'from the first')]),
        1: PhotoAnalysis(unreadable: [_spine('shelf.jpg', 'from the second')]),
      }, delays: {
        0: 30
      });

      final doc = await _scan(photos, provider);

      expect(provider.completed, [1, 0]);
      expect([for (final spine in doc.unreadable) spine.reason],
          ['from the first', 'from the second']);
    });
  });

  group('the documents that carry entries today', () {
    test('titleless detections (T-0035) order the same both ways', () async {
      // Through the real parse path: the model lists items and names nothing
      // on some of them, and those cross into `unreadable` there.
      PhotoAnalysis read(String photo, List<String> titles) =>
          parsePhotoAnalysis({
            'items': [
              for (final title in titles)
                {'raw_title': title, 'media_type': 'disc', 'confidence': 1.0},
            ],
          }, photo);
      final photos = [_photo(0), _photo(1)];
      final reads = {
        0: read('shelf_00.jpg', ['', 'DUSKHOLLOW', '  ']),
        1: read('shelf_01.jpg', ['', 'MOOR']),
      };

      final first = await _scan(photos, _Shelves(reads, delays: {0: 30}));
      final second = await _scan(photos, _Shelves(reads, delays: {1: 30}));

      expect(_rows(first), _rows(second));
      expect(first.unreadableByPhoto, {'shelf_00.jpg': 2, 'shelf_01.jpg': 1});
      expect(first.games.map((g) => g.detection.rawTitle),
          ['DUSKHOLLOW', 'MOOR']);
    });

    test('a second-reader run orders the same both ways', () async {
      // gemma3:12b answered 4 real entries on the three hi-res control photographs
      // (PhotoAnalysis.unreadable); the second read replaces the primary's.
      final photos = [_photo(0), _photo(1), _photo(2)];
      final primary = {
        for (var p = 0; p < 3; p++) p: const PhotoAnalysis(),
      };
      final second = {
        0: PhotoAnalysis(unreadable: [
          _spine('shelf_00.jpg', 'kanji, too small'),
          UnreadSpineReport(
              sourcePhoto: 'shelf_00.jpg',
              script: SpineScript.latin,
              reason: 'partially occluded'),
        ]),
        1: PhotoAnalysis(unreadable: [
          UnreadSpineReport(sourcePhoto: 'shelf_01.jpg', reason: 'only artwork'),
        ]),
        2: PhotoAnalysis(unreadable: [_spine('shelf_02.jpg', 'kanji')]),
      };

      final first = await _scan(photos, _Shelves(primary),
          secondReader: _Shelves(second, delays: {0: 30}));
      final other = await _scan(photos, _Shelves(primary),
          secondReader: _Shelves(second, delays: {2: 30}));

      expect(_rows(first), _rows(other));
      expect([for (final spine in first.unreadable) spine.reason],
          ['kanji, too small', 'partially occluded', 'only artwork', 'kanji']);
    });
  });

  test('what enters the list is untouched: every spine, once, unmoved '
      'between photos', () async {
    final shelf = _shelf(5, 3);
    final doc = await _scan(shelf.photos,
        _Shelves(shelf.reads, delays: {0: 20, 2: 10}));

    expect(doc.unreadable, hasLength(15));
    expect(doc.unreadableByPhoto,
        {for (final photo in shelf.photos) photo.name: 3});
    expect(
        {for (final spine in doc.unreadable) spine.reason},
        {for (var p = 0; p < 5; p++) for (var i = 0; i < 3; i++) 'spine $p.$i'});
    expect(doc.unreadable.map((s) => s.script),
        everyElement(SpineScript.japanese));
  });
}
