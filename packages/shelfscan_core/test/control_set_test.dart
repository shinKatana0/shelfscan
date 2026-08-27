/// Keeps the control-set manifest honest (T-0081).
///
/// The defect: four separate documents and the project's own front page
/// measured the resolver against "the control document", which was on no disk.
/// The prompt had moved three times under the figures and nothing said so, so
/// it was rediscovered again and again -- twice by paying for a live IGDB
/// run.
///
/// The fix has to work without the photographs, since they are a private home
/// and are gitignored. So the check that matters is `the prompt the figures
/// belong to` below: the recorded figures are pinned to a fingerprint of the
/// prompt that produced them, and editing `detectionPromptRules` or
/// `detectionJsonSchema` fails the suite everywhere, with no photo, no Ollama
/// and no network. The other groups are a development machine checking the
/// rest, on the `SHELFSCAN_PHOTOS` convention `documented_lists_test.dart` and
/// `app/test/heic_wic_test.dart` already use.
///
/// **The figures left the published manifest under T-0246 and the hint names
/// followed under T-0260.** A detection count is a count of one household's
/// possessions and the `hint_*` split is the list of consoles it owns. The
/// names alone read as safe -- a hint name is a token this project's own prompt
/// offers the model -- until it was noticed that the published set was
/// exhaustive, which is that same list of consoles with the counting already
/// done. All of it is in `doc/control-set.md` beside the photographs, joining
/// the byte sizes T-0234 had already put there. What stays published -- and
/// therefore what still runs in a clone -- is the fingerprint check, which was
/// always the only group that ran there, plus the set labels and their photo
/// lists.
///
/// **"Everywhere" was one machine until T-0231.** The figures were read out of
/// `doc/control-set.md`, which is not in a clone, so the first group and the
/// whole of `platform_hint_is_a_platform_test.dart` failed there rather than
/// running -- four reds under a message about a missing file, in the one place
/// the guard was advertised to work. The blocks are now [manifestPath], which
/// is tracked; the prose that identifies the photographs stayed unpublished.
///
/// Nothing here quotes a title, and since T-0246 nothing here counts one
/// either. The reason the working record counts rather than compares is
/// measured, and is in that document under "What is stable between runs, and
/// what is not".
library;

import 'dart:io';

import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

// The manifest is the single source: nothing below retypes a figure, the same
// way `documented_lists_test.dart` reads `.env.example` rather than restating
// it. `promptFingerprint` and `parseManifest` moved to the capture tool under
// T-0131, which keys a capture on the same number this pins.
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

/// The hint counts a section states, as `{hint: count}`. Private since T-0246
/// and the only place the names live since T-0260, so this answers only where
/// [readPrivateControlSet] found the document.
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
    test('parses, and holds both control sets and the prompt', () {
      // Without this the checks below would all pass on an empty parse, which
      // is how a documentation check quietly stops checking.
      expect(_manifest.keys, containsAll([_hiRes, _lowRes, 'PROMPT']));
      for (final name in [_hiRes, _lowRes]) {
        expect(_list(_manifest[name]!['photos']!), isNotEmpty,
            reason: '$name names no photographs');
      }
    });

    test('publishes nothing describing the shelf (T-0246, T-0260)', () {
      // The removal is itself the check. Every key below reconstructs part of
      // a private collection, and re-adding one here publishes it -- which is
      // the whole defect, not a style question. `hints` joined the list under
      // T-0260: a name is not a count, but the whole set of names answered
      // across a shelf is that shelf's platform mix with the counting done.
      const private = [
        'detections',
        'per_photo',
        'hints',
        'hints_answered',
        'empty_titles',
        'unreadable',
        'sizes',
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
          : 'the figures are in $controlSetPath, which is the working record '
              'and is not published (T-0246)');

  group('the prompt the figures belong to', () {
    test('is the one the manifest recorded them against', () {
      final recorded = _manifest['PROMPT']!;
      final actual = promptFingerprint(detectionPrompt);
      expect(
        actual,
        recorded['fingerprint'],
        reason: 'detectionPrompt has changed since the control figures were '
            'measured, so every figure in $controlSetPath, every number in '
            'doc/measurements.md and anything quoting one is now about a '
            'different system (T-0053). '
            'This is the intended failure, not a broken test. Re-run both '
            'control sets, check them against the photographs by eye, then '
            'update the two control-set blocks in $controlSetPath AND this '
            'fingerprint in $manifestPath to $actual '
            '(${detectionPrompt.length} chars). Two files since T-0246: the '
            'figures count a private collection and are not published, and '
            'this hash is the half that can be, which is why it is what fails '
            'here and on every other machine. Updating the fingerprint alone '
            'is worse than leaving it stale. The control photographs are a '
            'private home and are not published, so a fork cannot re-measure: '
            'say so in the pull request rather than moving the hash. The '
            'regeneration recipe is $controlSetPath, which is the working '
            'record and is not published.',
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
        final section = _manifest[name]!;
        final names = _list(section['photos']!);
        // The sizes are not published -- a byte size names one exact file
        // (T-0234) -- so they come from the working record beside the
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
      name = _manifest.keys.firstWhere(
        (key) => key != 'PROMPT' && _list(_manifest[key]!['photos']!).toSet()
            .containsAll(photos),
        orElse: () => fail('$_controlReview names photos that are neither '
            'control set: ${photos.join(', ')}. Scanning photos/ whole is all '
            'five photographs and is not a control set -- see '
            'doc/control-set.md.'),
      );
      section = _withFigures[name]!;
    });

    test('holds the detections the working record states', () {
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

    test('answers the platform hints the working record states', () {
      expect(_hintsOf(doc), _hints(section), reason: name);
    });

    test('carries no empty title and the stated unreadable count', () {
      expect(
          doc.games.where((g) => g.detection.rawTitle.trim().isEmpty).length,
          _int(section, 'empty_titles'),
          reason: '$name (T-0035)');
      // The one recorded figure that a byte-correct prompt can still move, so
      // the message is the whole value of this line (T-0106).
      expect(doc.unreadable.length, _int(section, 'unreadable'),
          reason: '$name: before treating this as a regression, check the '
              'cache state. A regeneration on a server that has already '
              'answered these photographs under a DIFFERENT prompt text -- '
              'the second pass of any prompt A/B -- lands in the third cache '
              'state, where shelf-2.jpg answers 3 phantom entries '
              '(one `unknown`, two byte-identical `japanese`) against a '
              'hand-counted truth of 0: 3 on 18 of 34 asks in that state, and '
              '3 on 2 of 2 whole-set A/B runs (T-0106). The check that tells '
              'the two apart: run `ollama stop qwen2.5vl:7b` and re-scan with '
              'nothing in between, and read the other figures beside it. If '
              'the count returns to the record it was the cache; if it '
              'survives '
              'the stop, or any of detections / per-photo / hints moved too, '
              'it is a real regression. Recipe in doc/control-set.md, "What a '
              'regeneration is allowed to differ in"; the 34 asks behind it in '
              'doc/measurements.md, "A third cache state".');
    });
  },
      skip: File(_controlReview ?? '').existsSync()
          ? null
          : 'needs SHELFSCAN_CONTROL_REVIEW pointing at a review document '
              'regenerated per doc/control-set.md');
}
