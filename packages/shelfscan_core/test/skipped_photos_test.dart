/// The photos a run did not cover, carried as a value (T-0145).
///
/// The defect this closes is not in core: the app recovered the difference
/// between "the read failed" and "your Stop got there first" by matching the
/// orchestrator's warning sentence with `startsWith`, and anything it did not
/// recognise fell into the failed list -- so rewording that line in core, or
/// any other warning that happened to open the same way, silently degraded a
/// stopped photo back into T-0140's "could not be scanned".
///
/// So the tests come in two halves: the orchestrator fills the two lists, and
/// the sentence is written FROM one of them, which is what stops the value and
/// the prose drifting apart.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

PhotoInput _photo(String name) =>
    PhotoInput(name: name, bytes: Uint8List.fromList([1]));

/// Fails the photos in [failing]; stops [stop] as the nth photo is read, so
/// the stop lands at a known point rather than at a wall-clock guess.
class _StagedVision implements VisionProvider {
  _StagedVision({this.stopAfter, this.stop, this.failing = const {}});

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
    return PhotoAnalysis(items: [
      Detection(
        rawTitle: 'TITLE ${photo.name}',
        mediaType: MediaType.disc,
        confidence: 1.0,
        sourcePhoto: photo.name,
      ),
    ]);
  }
}

Orchestrator _orchestrator(VisionProvider vision) => Orchestrator(
      visionWorker: VisionWorker(vision),
      resolverWorker: SkipResolver(),
      // One at a time, so what had started when the stop arrived is a fact of
      // the test rather than a race.
      visionConcurrency: 1,
      resolverConcurrency: 1,
    );

/// The document a run over [names] produces, and every warning it wrote.
Future<(ReviewDocument, List<String>)> _scan(
  List<String> names, {
  int? stopAfter,
  Set<String> failing = const {},
}) async {
  final stop = StopToken();
  final warnings = <String>[];
  final doc = await _orchestrator(
    _StagedVision(stopAfter: stopAfter, stop: stop, failing: failing),
  ).runScan(
    [for (final name in names) _photo(name)],
    stop: stop,
    progress: ScanProgress(onWarning: (w) => warnings.add(w.message)),
  );
  return (doc, warnings);
}

/// A document as `review.json` holds it, round-tripped through text.
ReviewDocument _reparse(ReviewDocument doc) =>
    ReviewDocument.parse(jsonEncode(doc.toJson()));

/// The smallest document that parses, as one written before T-0145 was.
Map<String, dynamic> _legacyDocument() => {
      'version': 1,
      'created': '2026-08-16T00:00:00.000Z',
      'photos': ['shelf1.jpg', 'shelf2.jpg'],
      'games': [
        {
          'detection': {'raw_title': 'DUSKHOLLOW', 'source_photo': 'shelf1.jpg'}
        },
      ],
    };

void main() {
  group('the document names what it does not cover', () {
    test('a clean run names nothing', () async {
      final (doc, _) = await _scan(['shelf1.jpg', 'shelf2.jpg']);
      expect(doc.failedPhotos, isEmpty);
      expect(doc.notLookedAtPhotos, isEmpty);
    });

    test('a stop names the photos it kept out of the run', () async {
      final (doc, _) = await _scan(
        ['shelf1.jpg', 'shelf2.jpg', 'shelf3.jpg'],
        stopAfter: 1,
      );
      expect(doc.notLookedAtPhotos, ['shelf2.jpg', 'shelf3.jpg']);
      expect(doc.failedPhotos, isEmpty);
    });

    test('a dead photo is a failure, not a photo nobody looked at', () async {
      final (doc, _) = await _scan(
        ['shelf1.jpg', 'shelf2.jpg'],
        failing: {'shelf1.jpg'},
      );
      expect(doc.failedPhotos, ['shelf1.jpg']);
      expect(doc.notLookedAtPhotos, isEmpty);
    });

    test('a failure and a stop in one run fill their own lists', () async {
      // The both-at-once case the app renders as two banners (T-0140): the
      // first photo dies, the second is read, the stop reaches the third.
      final (doc, _) = await _scan(
        ['shelf1.jpg', 'shelf2.jpg', 'shelf3.jpg'],
        stopAfter: 2,
        failing: {'shelf1.jpg'},
      );
      expect(doc.failedPhotos, ['shelf1.jpg']);
      expect(doc.notLookedAtPhotos, ['shelf3.jpg']);
      expect(doc.photos, ['shelf1.jpg', 'shelf2.jpg', 'shelf3.jpg'],
          reason: 'every chosen photo is still listed');
    });

    test('both lists are in the order the photos were passed', () async {
      // The pool answers in completion order and a stop is not an ordering, so
      // input order is a claim that has to be tested rather than assumed.
      final (doc, _) = await _scan(
        ['a.jpg', 'b.jpg', 'c.jpg', 'd.jpg', 'e.jpg'],
        stopAfter: 3,
        failing: {'a.jpg', 'c.jpg'},
      );
      expect(doc.failedPhotos, ['a.jpg', 'c.jpg']);
      expect(doc.notLookedAtPhotos, ['d.jpg', 'e.jpg']);
    });
  });

  group('the sentence and the value cannot drift', () {
    test('one warning per entry, written from the list itself', () async {
      final (doc, warnings) = await _scan(
        ['shelf1.jpg', 'shelf2.jpg', 'shelf3.jpg'],
        stopAfter: 1,
      );
      expect(
        warnings.where((w) => w.endsWith('it was not looked at.')).toList(),
        [
          for (final name in doc.notLookedAtPhotos)
            'Stopped before $name: it was not looked at.',
        ],
      );
    });

    test('a dead photo is named to the user too, in its own words', () async {
      final (doc, warnings) = await _scan(
        ['shelf1.jpg', 'shelf2.jpg'],
        failing: {'shelf1.jpg'},
      );
      expect(doc.failedPhotos, ['shelf1.jpg']);
      expect(warnings.where((w) => w.startsWith('Vision failed for shelf1.jpg')),
          hasLength(1));
      expect(warnings.any((w) => w.contains('not looked at')), isFalse);
    });
  });

  group('review.json', () {
    test('both lists round-trip', () async {
      final (doc, _) = await _scan(
        ['shelf1.jpg', 'shelf2.jpg', 'shelf3.jpg'],
        stopAfter: 2,
        failing: {'shelf1.jpg'},
      );
      final reparsed = _reparse(doc);
      expect(reparsed.failedPhotos, doc.failedPhotos);
      expect(reparsed.notLookedAtPhotos, doc.notLookedAtPhotos);
      expect(_reparse(reparsed).toJson(), reparsed.toJson());
    });

    test('a document written before the keys existed still parses', () {
      final doc = ReviewDocument.parse(jsonEncode(_legacyDocument()));
      expect(doc.failedPhotos, isEmpty);
      expect(doc.notLookedAtPhotos, isEmpty);
      expect(doc.games, hasLength(1));
      expect(doc.version, 1, reason: 'nothing about the old shape changed');
    });

    test('a titleless row still heals beside the new keys (T-0035)', () {
      final json = _legacyDocument()
        ..['failed_photos'] = ['shelf2.jpg']
        ..['not_looked_at_photos'] = <String>[];
      (json['games'] as List<Object?>).add({
        'detection': {'raw_title': '  ', 'source_photo': 'shelf1.jpg'},
      });
      final doc = ReviewDocument.parse(jsonEncode(json));
      expect(doc.games, hasLength(1));
      expect(doc.unreadable, hasLength(1));
      expect(doc.unreadable.single.sourcePhoto, 'shelf1.jpg');
      expect(doc.failedPhotos, ['shelf2.jpg']);
    });

    test('a wrong shape is named at the level that is wrong', () {
      Object? errorOf(Map<String, dynamic> json) {
        try {
          ReviewDocument.parse(jsonEncode(json));
        } on ReviewFormatException catch (e) {
          return e.toString();
        }
        return null;
      }

      expect(errorOf(_legacyDocument()..['failed_photos'] = 3),
          allOf(contains('failed_photos'), contains('a number')));
      expect(
          errorOf(_legacyDocument()..['not_looked_at_photos'] = [1]),
          allOf(contains('not_looked_at_photos[0]'),
              contains('a photo file name')));
    });
  });
}
