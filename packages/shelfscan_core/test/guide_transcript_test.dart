/// The guides quote what the CLI prints; this runs the CLI and compares
/// (T-0294).
///
/// `doc/guide.md` and its two translations carry transcripts of program
/// output, typed in by hand. Nothing compared them to the program, so they
/// drifted in silence and the drift was invisible in review because each side
/// read correctly on its own. T-0162 widened the `scan-installs` contract in
/// the guides and left the banner alone -- correctly, since changing one
/// without the other publishes two statements that disagree -- and the pair
/// then sat inconsistent until somebody noticed. The fix was a hand run of the
/// command over a synthetic folder, compared against all three guides by eye;
/// that check is what this file automates. It cited the commit that made it
/// until T-0406, which the identity rewrite of 2026-08-25 turned into a name no
/// clone can resolve -- the same defect the translation markers had, and the
/// reason nothing published here names a commit.
///
/// ## How a block is known to be program output
///
/// An HTML comment on its own line directly above the block:
///
///     <!-- transcript: scan-installs-notice -->
///
/// The name resolves in [_pinned] below; a marker naming nothing fails, and a
/// case with no marked block in some guide fails. The comment is chosen over
/// the alternatives because it is the only marker that travels with the block:
/// a manifest keyed on line numbers rots at the first edit, and keying on the
/// block's own text asks the guide to be its own authority. It is invisible on
/// the rendered page, which T-0227 already ruled for the translation headers,
/// and it survives being copied into a translation unchanged -- which is why
/// the same English transcript can be identified in all three files.
///
/// ## What "the same" means when the transcript quotes an argument
///
/// The banner names the directory the run was given, and the guide's copy
/// names an illustrative one. So a case declares the values that belong to the
/// *run* rather than to the program, and every case is produced **twice**,
/// over two fixtures with different names. Blanking the declared values must
/// make the two runs identical: that is what proves the declaration complete.
/// A value the case forgot to declare -- a temp path, a count, a duration --
/// makes the two disagree and fails here, instead of being quietly absorbed
/// into the pattern. What is left is the program's own text, and the guide's
/// block must match it with anything at all in the declared holes.
///
/// A case that declares nothing is compared byte for byte.
///
/// ## What is pinned, and what is not
///
/// Pinned: the six cases in [_pinned] -- the `scan-installs` banner and its
/// refusal of a personal directory, the two IGDB-credential sentences, the two
/// unknown-option sentences, and the unknown export target. All six are
/// reachable with no photograph, no key and no network.
///
/// Not pinned, and listed by name in [_notPinned] so that no reader believes
/// this file covers the guide: everything needing a vision call or an IGDB
/// answer, everything whose figures came from a run nobody here can repeat,
/// the app's own screen text, and the excerpt of the usage banner. The
/// `Review file:` line is the one that looks pinnable and is not -- the guide
/// shows it as `scan`'s output, and pinning it against the copy
/// `scan-installs` prints would be a marker asserting something this file did
/// not check.
///
/// The census is enforced: a new block in `doc/guide.md` that is neither a
/// command the reader types nor output containing an elision must be marked or
/// listed here, or this fails. That is the guard the task exists for -- a test
/// green over six blocks while the rest drift, with everybody believing the
/// guide is pinned, is the defect and not the fix.
///
/// ## The translations
///
/// README.md, "Translations": code blocks and program output are never
/// translated. So every block in `guide.ru.md` and `guide.ja.md` must appear
/// byte for byte in `guide.md`, and that is checked here for all of them, not
/// only the marked ones.
///
/// A failure message quotes the run's own output, which carries the temp
/// directory the fixture was built in. Read it; do not paste it into a report.
@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'cli_snapshot.dart';

const _guides = ['doc/guide.md', 'doc/guide.ru.md', 'doc/guide.ja.md'];

/// What a declared run-local value is replaced by before the two runs are
/// compared. Printable, because failure messages quote it, and asserted
/// absent from the program's own output before it is used.
const _hole = '[[run]]';

/// One case: what it prints, and which of the two fixtures printed it.
typedef _Producer = Future<_Emission> Function(_Fixture fixture);

/// A transcript as the program produced it, with the parts that belong to the
/// run rather than to the program named.
class _Emission {
  const _Emission(this.text, {this.runLocal = const <String>[]});

  final String text;
  final List<String> runLocal;

  String get blanked {
    var out = text;
    for (final value in runLocal) {
      out = out.replaceAll(value, _hole);
    }
    return out;
  }
}

/// A synthetic games folder, and the two names that differ between the two
/// runs of every case.
class _Fixture {
  _Fixture(this.root, this.gamesDir, this.reviewFile);

  final Directory root;
  final String gamesDir;
  final String reviewFile;

  /// The path the CLI echoes for [name] under this fixture, built the way
  /// `absoluteFilePath` builds it. A mismatch does not pass silently: it
  /// leaves the value undeclared, and the two runs then disagree.
  String echoed(String name) =>
      Uri.file(Directory('${root.path}${Platform.pathSeparator}$name')
              .absolute
              .path)
          .normalizePath()
          .toFilePath();
}

late final Directory _repoRoot = () {
  for (var dir = Directory.current.absolute;; dir = dir.parent) {
    if (File('${dir.path}/.env.example').existsSync()) return dir;
    if (dir.path == dir.parent.path) {
      fail('no .env.example at or above ${Directory.current.path}');
    }
  }
}();

// ---------------------------------------------------------------------------
// The guides, parsed

/// An indented block, and the marker naming what produces it.
class _Block {
  const _Block(this.guide, this.line, this.marker, this.lines);

  final String guide;
  final int line;
  final String? marker;
  final List<String> lines;

  String get text => lines.join('\n');
  String get where => '$guide:$line';
}

/// Exactly this and nothing else is a marker, so the paragraph at the top of
/// each guide explaining the convention is not mistaken for one.
final _markerLine = RegExp(r'^<!-- transcript: ([a-z0-9-]+) -->$');

/// Every indented code block, with any marker above it.
///
/// Two things are deliberately not blocks. Lines inside an HTML comment: the
/// translation headers indent their continuation lines. And a block whose
/// first line is indented past four spaces: that is a list item's continuation
/// text, which Markdown does not render as code either.
List<_Block> _blocksOf(String guide) {
  final source = File('${_repoRoot.path}/$guide').readAsStringSync();
  final blocks = <_Block>[];
  final orphans = <String>[];
  var body = <String>[];
  int? start;
  String? marker;
  var inComment = false;

  void flush() {
    while (body.isNotEmpty && body.last.isEmpty) {
      body.removeLast();
    }
    if (body.isNotEmpty) {
      blocks.add(_Block(guide, start!, marker, List.of(body)));
    } else if (marker != null) {
      orphans.add('$guide: `transcript: $marker` has no block under it');
    }
    body = <String>[];
    start = null;
    marker = null;
  }

  final lines = const LineSplitter().convert(source);
  for (var i = 0; i < lines.length; i++) {
    final raw = lines[i];
    final trimmed = raw.trim();
    if (inComment) {
      if (trimmed.contains('-->')) inComment = false;
      continue;
    }
    if (trimmed.startsWith('<!--')) {
      flush();
      final named = _markerLine.firstMatch(trimmed);
      if (named != null) {
        marker = named.group(1);
      } else if (!trimmed.contains('-->')) {
        inComment = true;
      }
      continue;
    }
    if (raw.startsWith('    ') && trimmed.isNotEmpty) {
      if (body.isEmpty) {
        if (raw[4] == ' ') continue;
        start = i + 1;
      }
      body.add(raw.substring(4));
      continue;
    }
    if (trimmed.isEmpty) {
      if (body.isNotEmpty) body.add('');
      continue;
    }
    flush();
  }
  flush();

  if (orphans.isNotEmpty) fail(orphans.join('\n'));
  return blocks;
}

/// A command the reader types, not something the program said.
bool _isTyped(_Block block) => block.lines
    .where((line) => line.trim().isNotEmpty)
    .every((line) => const ['dart run ', 'dart pub ', 'cd ', 'export ', r'$env:']
        .any(line.startsWith));

/// Output with a stand-in in it -- `<reason>`, `<path>`, a bare `...` line.
/// Nothing can compare such a block byte for byte, and pretending otherwise is
/// what the marker convention has to avoid.
bool _isElided(_Block block) =>
    RegExp(r'<[^>\n]*>').hasMatch(block.text) ||
    block.lines.any((line) => line.trim() == '...');

// ---------------------------------------------------------------------------
// Running the CLI

final _runs = <String, ProcessResult>{};

Future<ProcessResult> _cli(_Fixture fixture, List<String> args) async {
  final key = [fixture.root.path, ...args].join(' ');
  final cached = _runs[key];
  if (cached != null) return cached;
  final result = await Process.run(
    Platform.resolvedExecutable,
    [cliSnapshot(), ...args],
    workingDirectory: fixture.root.path,
    // Blanked so a machine holding credentials cannot turn the two credential
    // transcripts into their other branch, or send a request. The TMDB token
    // is blanked for the same reason: with one set the run prints the
    // attribution notice, which no guide block quotes.
    environment: const {
      'IGDB_CLIENT_ID': '',
      'IGDB_CLIENT_SECRET': '',
      'SHELFSCAN_TMDB_TOKEN': '',
    },
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
  return _runs[key] = result;
}

List<String> _linesOf(String stream) =>
    const LineSplitter().convert(stream.trimRight());

/// The run every other case borrows: it also writes the review document that
/// `resolve` and `export` are then pointed at, so no case has to hand-build
/// one and none can drift from what the program actually writes.
Future<List<String>> _installsRun(_Fixture fixture) async {
  final run = await _cli(
      fixture, ['scan-installs', fixture.gamesDir, '-o', fixture.reviewFile]);
  expect(run.exitCode, 0,
      reason: 'the synthetic games folder did not scan: ${run.stderr}');
  final lines = _linesOf(run.stdout as String);
  expect(lines.length, greaterThan(2), reason: 'stdout was ${run.stdout}');
  return lines;
}

/// The review document the folder run wrote, for the commands that take
/// one. Produced rather than hand-built, so no fixture here can drift
/// from the shape the program actually writes.
Future<String> _reviewFile(_Fixture fixture) async {
  await _installsRun(fixture);
  return fixture.reviewFile;
}

Future<String> _refusal(_Fixture fixture, List<String> args) async {
  final run = await _cli(fixture, args);
  expect(run.exitCode, 2, reason: 'expected a pre-flight refusal: ${run.stdout}');
  return (run.stderr as String).trimRight();
}

// ---------------------------------------------------------------------------
// The cases

final _pinned = <String, _Producer>{
  'scan-installs-notice': (fixture) async => _Emission(
        (await _installsRun(fixture)).first,
        runLocal: [fixture.gamesDir],
      ),
  // Printed by the shared resolver factory, so `scan` and `scan-installs` say
  // it from one string and this covers the guide's copy in Step 3.
  'igdb-skipped': (fixture) async =>
      _Emission((await _installsRun(fixture))[1]),
  'scan-installs-refused': (fixture) async => _Emission(
        await _refusal(fixture, ['scan-installs', 'Downloads']),
        runLocal: [fixture.echoed('Downloads')],
      ),
  'resolve-needs-igdb': (fixture) async => _Emission(
        await _refusal(fixture, ['resolve', await _reviewFile(fixture)]),
      ),
  'unknown-export-target': (fixture) async => _Emission(
        await _refusal(fixture, [
          'export',
          await _reviewFile(fixture),
          '--target',
          'tonkatsu-box',
          '-o',
          'unwritten.xcoll',
        ]),
      ),
  // Two sentences from two runs, in the order the guide shows them: an option
  // no command has, then one that belongs to a different command. Neither run
  // reads anything, which is the claim they make, so neither needs a review
  // document to exist.
  'unknown-option': (fixture) async => _Emission([
        await _refusal(
            fixture, ['export', fixture.reviewFile, '--targt', 'csv']),
        await _refusal(fixture, ['scan', fixture.gamesDir, '--target', 'csv']),
      ].join('\n')),
};

/// The output blocks of `doc/guide.md` that are NOT pinned, by the opening of
/// their first line, each with the reason. Anything else that is neither typed
/// nor elided fails the census below until it is pinned or added here.
const _notPinned = <(String, String)>[
  ('No readable photo in D:', 'needs a photo directory fixture; pinnable'),
  ('No photo directory at D:', 'needs a photo directory fixture; pinnable'),
  ('CONVERTED: shelf-1.heic', 'durations from a run nobody can repeat'),
  ('--provider ollama', 'an excerpt of the usage banner, not one message'),
  ('Vision: local Ollama', 'needs a vision provider'),
  ('Scanned 3 photo(s):', 'figures from an illustrative run'),
  ('Review file: collection.review.json',
      'shown as `scan` output; `scan-installs` prints its own copy, and '
          'pinning against that would assert what this file did not check'),
  ('not in .xcoll -- tap', "the app's review screen, not the CLI"),
  ('Resolved 45 detection(s)', 'figures, and needs IGDB credentials'),
  ('No review file at D:', 'needs a review-path fixture; pinnable'),
  ('Exported 41 of 45', 'figures from an illustrative run'),
  ('WARN: this GOG Galaxy database', 'needs a Galaxy database fixture'),
];

// ---------------------------------------------------------------------------

/// The two fixtures. The names differ in both halves so that blanking one
/// cannot accidentally leave the other's text standing.
Future<_Fixture> _makeFixture(String prefix, String games, String review) async {
  final root = Directory.systemTemp.createTempSync('shelfscan_guide_$prefix');
  addTearDown(() {
    try {
      root.deleteSync(recursive: true);
    } on FileSystemException {
      // The Windows errno 145 race the other path suites document.
    }
  });
  final sep = Platform.pathSeparator;
  Directory('${root.path}$sep$games${sep}Ashen Verge')
      .createSync(recursive: true);
  File('${root.path}$sep$games${sep}Ashen Verge${sep}goggame-1400000001.info')
      .writeAsStringSync(jsonEncode(const {
    'gameId': '1400000001',
    'rootGameId': '1400000001',
    'name': 'Ashen Verge',
    'version': 1,
  }));
  Directory('${root.path}$sep$games${sep}Tidewalker Chronicles')
      .createSync(recursive: true);
  // Only its name matters: `gamesFolderError` refuses the leaf name.
  Directory('${root.path}${sep}Downloads').createSync();
  return _Fixture(root, games, review);
}

void main() {
  setUpAll(cliSnapshot);

  late _Fixture first;
  late _Fixture second;

  setUp(() async {
    first = await _makeFixture('a_', 'alpha-cache', 'alpha.review.json');
    second = await _makeFixture('b_', 'zulu-depot', 'zulu.review.json');
  });

  group('a marked transcript is what the program prints', () {
    for (final entry in _pinned.entries) {
      test(entry.key, () async {
        final a = await entry.value(first);
        final b = await entry.value(second);
        expect(a.text, isNot(contains(_hole)),
            reason: 'the program prints the token this test substitutes '
                'with; give `_hole` another value');
        expect(b.blanked, a.blanked,
            reason: 'two runs of `${entry.key}` differ outside the values it '
                'declares as its own. Something in this transcript belongs to '
                'the run and is not named in `runLocal`.');

        final parts = a.blanked.split(_hole);
        final pattern = RegExp('^${parts.map(RegExp.escape).join('(.+)')}\$');
        for (final guide in _guides) {
          final marked = [
            for (final block in _blocksOf(guide))
              if (block.marker == entry.key) block,
          ];
          expect(marked, isNotEmpty,
              reason: '$guide carries no `transcript: ${entry.key}` block. '
                  'All three guides quote the same transcripts, so a case '
                  'missing from one of them is a hole in that file.');
          for (final block in marked) {
            if (parts.length == 1) {
              expect(block.text, a.blanked,
                  reason: '${block.where} quotes output the program no longer '
                      'prints. Change the guide, or the program, or both -- '
                      'but not one alone.');
            } else {
              expect(pattern.hasMatch(block.text), isTrue,
                  reason: '${block.where} does not match what the program '
                      'prints. The program said:\n${a.blanked}\n'
                      'The guide says:\n${block.text}');
            }
          }
        }
      });
    }
  });

  group('the marker set', () {
    test('every marker in every guide names a case', () {
      for (final guide in _guides) {
        for (final block in _blocksOf(guide)) {
          final marker = block.marker;
          if (marker == null) continue;
          expect(_pinned.keys, contains(marker),
              reason: '${block.where} claims to be pinned and nothing here '
                  'produces `$marker`. A marker with no producer is worse '
                  'than no marker.');
        }
      }
    });
  });

  group('the census of what is not pinned', () {
    test('every output block in doc/guide.md is pinned or listed', () {
      final unaccounted = <String>[];
      for (final block in _blocksOf(_guides.first)) {
        if (block.marker != null || _isTyped(block) || _isElided(block)) {
          continue;
        }
        final listed = _notPinned
            .any((entry) => block.lines.first.startsWith(entry.$1));
        if (!listed) unaccounted.add('${block.where}: ${block.lines.first}');
      }
      expect(unaccounted, isEmpty,
          reason: 'these blocks look like program output and nothing here '
              'says what they are. Mark them, or add them to `_notPinned` '
              'with the reason:\n${unaccounted.join('\n')}');
    });

    test('every entry in the census still matches a block', () {
      final firstLines = [
        for (final block in _blocksOf(_guides.first)) block.lines.first,
      ];
      for (final (anchor, _) in _notPinned) {
        expect(firstLines.any((line) => line.startsWith(anchor)), isTrue,
            reason: '`$anchor` is listed as an unpinned block of '
                '${_guides.first} and no block begins with it any more');
      }
    });
  });

  group('the translations', () {
    test('carry the English blocks unchanged', () {
      final english = {
        for (final block in _blocksOf(_guides.first)) block.text,
      };
      for (final guide in _guides.skip(1)) {
        for (final block in _blocksOf(guide)) {
          expect(english, contains(block.text),
              reason: '${block.where} is a code block that does not appear in '
                  '${_guides.first}. README.md, "Translations": code blocks '
                  'and program output are not translated.');
        }
      }
    });
  });
}
