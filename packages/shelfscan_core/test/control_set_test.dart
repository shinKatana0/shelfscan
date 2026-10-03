/// Checks the public control prompt fingerprint and the optional local
/// control definition. Private photographs and their measurements are never
/// embedded in this test.
library;

import 'dart:io';

import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

// Use the same parser and fingerprint as the capture tool.
import '../tool/control_capture.dart';

List<String> _list(String value) => manifestList(value);

int _int(Map<String, String> section, String key) {
  final value = section[key];
  if (value == null) fail('$manifestPath has no "$key" in this block');
  return int.parse(value);
}

/// Repository root: `dart test` runs in the package and the manifest lives two
/// levels above it.
Directory repoRoot() =>
    findRepoRoot(Directory.current) ??
    fail('no $manifestPath at or above ${Directory.current.path}');

/// Local hint counts are available only with the private control definition.
Map<String, int> _hints(Map<String, String> section) => manifestHints(section);

/// The same, counted off a review document.
Map<String, int> _hintsOf(ReviewDocument doc) {
  final counts = <String, int>{};
  for (final game in doc.games) {
    final hint = game.detection.platformHint;
    if (hint == null || hint.isEmpty) continue;
    counts[hint] = (counts[hint] ?? 0) + 1;
  }
  return counts;
}

final _manifest = readManifest(repoRoot());

/// The same sections with the private figures folded in -- or the published
/// sections alone in a clone, where every group that reads them skips.
final _withFigures = readManifestWithSizes(repoRoot());

/// Where the control photo directory is, for whoever holds the photographs.
final _photoRoot = Platform.environment['SHELFSCAN_PHOTOS'];

/// A review document freshly regenerated per doc/control-set.md. Never a path
/// inside the repository: the document is not committed and the reasons are in
/// the "Why no document is committed" section.
final _controlReview = Platform.environment['SHELFSCAN_CONTROL_REVIEW'];

const _hiRes = 'CONTROL-HIRES';
const _lowRes = 'CONTROL-LOWRES';

void main() {
  group('the manifest', () {
    test('parses both control set labels and the prompt', () {
      // Without this the checks below would all pass on an empty parse, which
      // is how a documentation check quietly stops checking.
      expect(_manifest.keys, containsAll([_hiRes, _lowRes, 'PROMPT']));
      for (final name in [_hiRes, _lowRes]) {
        expect(_manifest[name]!.containsKey('photos'), isFalse,
            reason: '$name must not publish the local photograph list');
      }
    });

    test('publishes nothing describing the shelf', () {
      // A published key must not reveal an image list, a count, or the
      // platform mix of a private control set.
      const private = [
        'detections',
        'per_photo',
        'hints',
        'hints_answered',
        'empty_titles',
        'unreadable',
        'sizes',
        'photos',
      ];
      for (final name in [_hiRes, _lowRes]) {
        for (final key in _manifest[name]!.keys) {
          expect(key, isNot(startsWith('hint_')),
              reason: '$name: "$key" is a count of one platform on a private '
                  'shelf, so it belongs in $controlSetPath');
          expect(key, isNot(isIn(private)),
              reason: '$name: "$key" describes the photographs or what is on '
                  'them, so it belongs in $controlSetPath, not in '
                  '$manifestPath');
        }
      }
    });
  });

  group('the recorded figures', () {
    test('are internally consistent', () {
      for (final name in [_hiRes, _lowRes]) {
        final section = _withFigures[name]!;
        expect(_int(section, 'detections'),
            _list(section['per_photo']!).map(int.parse).reduce((a, b) => a + b),
            reason: '$name: per_photo does not add up to detections');
        expect(_hints(section).values.reduce((a, b) => a + b),
            _int(section, 'hints_answered'),
            reason: '$name: the hint_* counts do not sum to hints_answered');
      }
    });
  },
      skip: readPrivateControlSet(repoRoot()) != null
          ? null
          : 'the figures are in $controlSetPath, which is the local control definition '
              'and is not published');

  group('the prompt the figures belong to', () {
    test('is the one the manifest recorded them against', () {
      final recorded = _manifest['PROMPT']!;
      final actual = promptFingerprint(detectionPrompt);
      expect(
        actual,
        recorded['fingerprint'],
        reason: 'detectionPrompt differs from the recorded control fingerprint. '
            'Check both local control sets against their photographs before '
            'updating the fingerprint in $manifestPath. If the photographs '
            'are unavailable, report that validation gap in the pull request. '
            'The local control definition is $controlSetPath.',
      );
      expect(detectionPrompt.length, int.parse(recorded['chars']!));
    });
  });

  group('the control photos', () {
    test('are the files the figures were measured on', () {
      for (final (name, dir) in [
        (_hiRes, '$_photoRoot/hires'),
        (_lowRes, _photoRoot!),
      ]) {
        final section = _withFigures[name]!;
        final names = _list(section['photos']!);
        // The sizes are not published -- a byte size names one exact file
        // -- so they come from the local control definition beside the
        // photographs, which is present exactly where this group runs.
        final private = readPrivateControlSet(repoRoot())?[name];
        final stated = private?['sizes'];
        expect(stated, isNotNull,
            reason: '$controlSetPath states no sizes for $name, so the check '
                'below would pass without checking anything');
        final sizes = _list(stated!).map(int.parse).toList();
        expect(names.length, sizes.length,
            reason: '$name names a different number of photos than sizes');
        for (var i = 0; i < names.length; i++) {
          final file = File('$dir/${names[i]}');
          expect(file.existsSync(), isTrue,
              reason: '$name is missing ${names[i]} -- the control set is the '
                  'photographs, so there is nothing to measure without it');
          // Size and not a hash, so this stays a dependency-free check; a
          // re-crop or a re-export moves it, which is the case worth catching
          // before a scan rather than after the count disagrees.
          expect(file.lengthSync(), sizes[i], reason: '$name: ${names[i]}');
        }
      }
    });
  },
      skip: Directory(_photoRoot ?? '').existsSync()
          ? null
          : 'needs SHELFSCAN_PHOTOS pointing at the photo directory');

  group('a regenerated control document', () {
    late ReviewDocument doc;
    late String name;
    late Map<String, String> section;

    setUp(() {
      doc = ReviewDocument.parse(File(_controlReview!).readAsStringSync());
      final photos = doc.photos.toSet();
      name = _withFigures.keys.firstWhere(
        (key) => key != 'PROMPT' && _list(_withFigures[key]!['photos']!).toSet()
            .containsAll(photos),
        orElse: () => fail('the review document does not match either '
            'defined control set; check the local control definition'),
      );
      section = _withFigures[name]!;
    });

    test('holds the detections the local control definition states', () {
      expect(doc.games.length, _int(section, 'detections'), reason: name);
      final byPhoto = <String, int>{};
      for (final game in doc.games) {
        final photo = game.detection.sourcePhoto;
        byPhoto[photo] = (byPhoto[photo] ?? 0) + 1;
      }
      expect([for (final photo in _list(section['photos']!)) byPhoto[photo] ?? 0],
          _list(section['per_photo']!).map(int.parse).toList(),
          reason: '$name: the per-photo split moved');
    });

    test('answers the platform hints the local control definition states', () {
      expect(_hintsOf(doc), _hints(section), reason: name);
    });

    test('carries no empty title and the stated unreadable count', () {
      expect(
          doc.games.where((g) => g.detection.rawTitle.trim().isEmpty).length,
          _int(section, 'empty_titles'),
          reason: '$name');
      // The one recorded figure that a byte-correct prompt can still move, so
      // the message is the whole value of this line.
      expect(doc.unreadable.length, _int(section, 'unreadable'),
          reason: '$name: before treating this as a regression, restart the model '
               'to clear its prompt cache and repeat the local control check. '
               'If other detection or hint results also move, investigate the '
               'prompt and image inputs.',
       );
    });
  },
      skip: File(_controlReview ?? '').existsSync()
          ? null
          : 'needs SHELFSCAN_CONTROL_REVIEW pointing at a review document '
              'regenerated per doc/control-set.md');
}
