/// The four translation markers, and the property that keeps them answerable
/// (T-0406).
///
/// Each translated file records what its English original said when it was
/// written. It recorded a *commit* until T-0406, and a commit answers wrongly
/// twice over. Two branches translating from one base merge into a history
/// where neither branch's hash carries the other's work, so each marker reports
/// the other branch's commits as English it never caught up with. And a history
/// rewrite replaces every commit object, so the recorded hash names nothing a
/// clone holds: the documented check comes back `fatal: bad object`, from the
/// only view a stranger ever gets. Six of the seven hashes published across
/// these files were in that state when this file was written.
///
/// So a marker names the English file's git blob -- its content -- and carries
/// its own claim about itself, in one form in all four files:
///
///     TRANSLATED-FROM: README.md blob <40 hex> CURRENT
///
/// Neither a merge nor a rewrite changes what a file says, so the name keeps
/// answering. The rule in full is README.md, "Translations".
///
/// ## What is asserted, and which direction it fails in
///
/// A marker saying `CURRENT` must carry the blob name its English source has
/// now. A marker saying `STALE` is not held to that -- an old name is the whole
/// point of the word, and both guides are legitimately stale. So this file
/// catches exactly one failure, a translation claiming a currency it lost, and
/// the fix it asks for is one word, in a language the person fixing it need not
/// read. That is what separates it from the CI check README.md carried as
/// considered-and-rejected: the rejected one left a contributor no honest exit
/// but to translate.
///
/// The direction matters more than the check. Any edit to an English file
/// changes its blob name, so a typo fix turns every `CURRENT` marker red. It
/// over-reports staleness and cannot under-report it: nothing short of an exact
/// revert of the English brings a blob name back.
///
/// What it cannot see: whether a `STALE` file is still stale, whether a
/// `CURRENT` one is complete rather than merely contemporary, and a marker
/// bumped without the translation being touched, which is forgery.
library;

import 'dart:io';

import 'package:test/test.dart';

/// Translated file -> the English file it follows.
const _sources = <String, String>{
  'README.ru.md': 'README.md',
  'README.ja.md': 'README.md',
  'doc/guide.ru.md': 'doc/guide.md',
  'doc/guide.ja.md': 'doc/guide.md',
};

final _marker =
    RegExp(r'TRANSLATED-FROM: (\S+) blob ([0-9a-f]{40}) (CURRENT|STALE)');

class _Marker {
  const _Marker(this.source, this.blob, this.current);

  final String source;
  final String blob;
  final bool current;
}

List<_Marker> _markersIn(String text) => _marker
    .allMatches(text)
    .map((m) => _Marker(m[1]!, m[2]!, m[3] == 'CURRENT'))
    .toList();

/// git's own name for the content of [path], read from the working tree rather
/// than from a commit -- which is why a marker can be written in the same
/// commit as the English it names.
String _blobName(String path) {
  final run = Process.runSync('git', ['hash-object', path]);
  if (run.exitCode != 0) {
    fail('git hash-object $path: ${run.stdout}${run.stderr}');
  }
  return (run.stdout as String).trim();
}

/// Whether [translated] still claims what it can support: a `CURRENT` marker
/// must name what [english] says now, a `STALE` one is exempt.
bool _claimHolds(File translated, File english) {
  final markers = _markersIn(translated.readAsStringSync());
  if (markers.length != 1) {
    fail('${translated.path}: ${markers.length} markers, expected one');
  }
  final marker = markers.single;
  return !marker.current || marker.blob == _blobName(english.path);
}

void main() {
  setUpAll(
      () => _scratch = Directory.systemTemp.createTempSync('translation-'));
  tearDownAll(() => _scratch.deleteSync(recursive: true));

  group('the tool the check is built on', () {
    test('git is on PATH, which every case below needs', () {
      final run = Process.runSync('git', const ['--version']);
      expect(run.exitCode, 0,
          reason: 'without git these cases fail for a reason that has '
              'nothing to do with the markers');
    });

    test('hash-object answers git blob names, not some other digest', () {
      final empty = File('${_scratch.path}/empty');
      empty.writeAsStringSync('');

      // The blob name of zero bytes, which is the one git value everyone can
      // check against a published constant.
      expect(_blobName(empty.path),
          'e69de29bb2d1d6434b8b29ae775ad8c2e48c5391');
    });
  });

  group('the four markers', () {
    for (final entry in _sources.entries) {
      test('${entry.key} carries one marker, naming ${entry.value}', () {
        final file = File('${_repoRoot.path}/${entry.key}');
        final markers = _markersIn(file.readAsStringSync());

        expect(markers, hasLength(1),
            reason: '${entry.key} must carry exactly one TRANSLATED-FROM '
                'line; README.md, "Translations" has the form');
        expect(markers.single.source, entry.value,
            reason: '${entry.key} follows ${entry.value}');
      });

      test('${entry.key} does not claim a currency it lost', () {
        final english = File('${_repoRoot.path}/${entry.value}');

        expect(_claimHolds(File('${_repoRoot.path}/${entry.key}'), english),
            isTrue,
            reason: '${entry.value} no longer says what ${entry.key} was '
                'translated from. Either update the translation and set the '
                'blob name to `git hash-object ${entry.value}`, or change the '
                "marker's last word to STALE");
      });
    }
  });

  // Both directions on files this test writes, because a check that can only
  // be watched passing proves nothing about what it would refuse.
  group('the claim, controlled both ways', () {
    late File english;
    late File translated;

    setUp(() {
      english = File('${_scratch.path}/english.md')
        ..writeAsStringSync('the English, as translated\n');
      translated = File('${_scratch.path}/translated.md');
    });

    void mark(String word, String blob) =>
        translated.writeAsStringSync('TRANSLATED-FROM: english.md blob $blob '
            '$word\nprose\n');

    test('CURRENT holds while the English says what it said', () {
      mark('CURRENT', _blobName(english.path));

      expect(_claimHolds(translated, english), isTrue);
    });

    test('CURRENT fails once the English moves', () {
      mark('CURRENT', _blobName(english.path));
      english.writeAsStringSync('the English, one word later\n');

      expect(_claimHolds(translated, english), isFalse);
    });

    test('STALE is exempt, which is what makes one word the fix', () {
      mark('CURRENT', _blobName(english.path));
      english.writeAsStringSync('the English, one word later\n');
      final marked =
          translated.readAsStringSync().replaceAll('CURRENT', 'STALE');
      translated.writeAsStringSync(marked);

      expect(_claimHolds(translated, english), isTrue);
    });
  });

  // The rule is published and the check is here; pinning the commands stops
  // the two describing different mechanisms, which is how the marker rotted.
  group('README.md, "Translations", and this file agree', () {
    late String rule;

    setUp(() => rule = File('${_repoRoot.path}/README.md').readAsStringSync());

    test('it names the form the markers are in', () {
      expect(rule, contains('TRANSLATED-FROM: README.md blob'));
    });

    test('it names the command a reader checks a marker with', () {
      expect(rule, contains('git rev-parse HEAD:README.md'));
    });

    test('it names the command an editor bumps a marker with', () {
      expect(rule, contains('git hash-object README.md'));
    });
  });
}

late final Directory _repoRoot = () {
  for (var dir = Directory.current.absolute;; dir = dir.parent) {
    if (File('${dir.path}/.env.example').existsSync()) return dir;
    if (dir.parent.path == dir.path) {
      fail('no .env.example at or above ${Directory.current.path}');
    }
  }
}();

late Directory _scratch;
