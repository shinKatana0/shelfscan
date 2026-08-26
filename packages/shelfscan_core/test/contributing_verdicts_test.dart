/// `CONTRIBUTING.md`'s "Cutting a release" section quotes, verbatim, the
/// verdict words `tool/check-release-order.dart` prints and the exit code
/// each of them answers with. Nothing held any of it to the tool (T-0417):
/// rename a verdict and the page keeps teaching the old word, while no suite,
/// no analyzer and no CI job says otherwise. That page is read a few times a
/// year, on the one occasion when being wrong costs most -- and its value is
/// concentrated in one claim, that `CHANGELOG: NOTE` is exit 0 and still
/// means the middle step is owed.
///
/// **The list is derived from the page and never carried here.** A test
/// holding its own copy of the eight words would be a third place to drift,
/// which is the defect this guards against rather than a guard. So nothing
/// below names a verdict word, a label or a script: the extractor matches a
/// shape -- an all-caps label, a colon, an all-caps verdict, inside a code
/// span -- and the page is the source of truth about what it claims. Every
/// assertion only ever asks whether the claim is still true.
///
/// **The counts are what stop that from guarding nothing.** A regex that
/// finds nothing passes vacuously, so the number of quotes, of labels, of
/// exit claims and of scripts is asserted, and the extractor carries a
/// control in each direction (`doc/conventions.md` 4a, fifth shape).
///
/// **Nothing here invokes `git`.** All three files ship in every clone, so
/// this is a text comparison over them plus calls into the tool's own pure
/// `judge` -- the T-0231 class, and the reason that check lives outside the
/// suite at all.
///
/// `tool/check-bundle-assets.dart`'s exit codes are deliberately not pinned.
/// The page states them in a running sentence that says more than the tool's
/// own one-line contract does, so extracting a mapping needs a regex written
/// for that single sentence; `doc/reports/T-0417.md` carries the attempt and
/// why it was dropped. The verdict words are held for both tools, because a
/// quoted string is looked for in every script the section names.
library;

import 'dart:io';

import 'package:test/test.dart';

import '../../../tool/check-release-order.dart';

const _heading = '## Cutting a release';

/// An all-caps label, a colon, an all-caps verdict, alone inside a code span.
final _verdictSpan = RegExp(r'`([A-Z][A-Z ]*: [A-Z][A-Z ]*)`');

/// The two forms the section states an exit code in: `(exit 1)` beside the
/// verdict, and "the exit code is still 0" inside the prose of one bullet.
final _exitClaim = RegExp(r'exit(?: code)?(?: is still)? (\d+)');

/// A script the section tells the reader to run.
final _scriptRun = RegExp(r'dart run (tool/[A-Za-z0-9._-]+\.dart)');

/// A verdict word the page quotes, with the exit code its bullet claims for
/// it -- null where that bullet claims none.
class _Quote {
  _Quote(this.text, this.exitClaim);

  final String text;
  final int? exitClaim;

  String get label => text.substring(0, text.indexOf(':'));
}

/// The section's list bullets, each folded into one line: the `- ` line plus
/// the indented lines continuing it.
List<String> _bullets(String section) {
  final bullets = <String>[];
  final buffer = StringBuffer();
  void flush() {
    if (buffer.isNotEmpty) bullets.add(buffer.toString());
    buffer.clear();
  }

  for (final line in section.split('\n')) {
    if (line.startsWith('- ')) {
      flush();
      buffer.write(line);
    } else if (buffer.isNotEmpty && line.startsWith('  ')) {
      buffer.write(' ${line.trim()}');
    } else {
      flush();
    }
  }
  flush();
  return bullets;
}

List<_Quote> _quotes(String section) {
  final quotes = <_Quote>[];
  for (final bullet in _bullets(section)) {
    final spans =
        _verdictSpan.allMatches(bullet).map((m) => m[1]!).toList();
    if (spans.isEmpty) continue;
    final claims = _exitClaim
        .allMatches(bullet)
        .map((m) => int.parse(m[1]!))
        .toSet();
    if (claims.length > 1) {
      fail('CONTRIBUTING.md, "Cutting a release": the bullet quoting '
          '`${spans.first}` states more than one exit code ($claims), so '
          'which one it claims for that verdict cannot be read.');
    }
    for (final span in spans) {
      quotes.add(_Quote(span, claims.isEmpty ? null : claims.first));
    }
  }
  return quotes;
}

String _section(String page) {
  final lines = page.split('\n');
  final start = lines.indexWhere((line) => line.trimRight() == _heading);
  if (start < 0) fail('CONTRIBUTING.md carries no "$_heading" section');
  final rest = lines.skip(start + 1).toList();
  final end = rest.indexWhere((line) => line.startsWith('## '));
  return (end < 0 ? rest : rest.take(end)).join('\n');
}

/// Walks up to the directory holding `LICENSE`, the same shape
/// `tmdb_attribution_test.dart` uses to reach a file at the repository root.
String _repoFile(String name) {
  for (var dir = Directory.current.absolute;; dir = dir.parent) {
    if (File('${dir.path}/LICENSE').existsSync()) {
      final file = File('${dir.path}/$name');
      if (!file.existsSync()) fail('no $name beside LICENSE in ${dir.path}');
      return file.readAsStringSync();
    }
    if (dir.path == dir.parent.path) {
      fail('no LICENSE at or above ${Directory.current.path}');
    }
  }
}

String _pubspec(String version) => 'name: planted\n'
    'version: $version\n';

/// A Keep a Changelog file naming [released] under an open `[Unreleased]`.
String _changelog(Iterable<String> released) => [
      '# Changelog',
      '',
      '## [Unreleased]',
      '',
      '- planted',
      '',
      for (final version in released) ...[
        '## [$version] - 2001-01-01',
        '',
        '- planted',
        '',
      ],
    ].join('\n');

/// Six runs of the tool's own `judge` over invented text, covering every
/// verdict the page attaches an exit code to.
///
/// Each is built so that exactly one bullet's claim appears in its lines. Two
/// claims in one verdict would both be asserted against the same code, and
/// the folded answer belongs to the run rather than to either half -- a
/// refused changelog raises the exit code of an otherwise clean version
/// check. A scenario that stops isolating fails here rather than lying.
List<Verdict> _scenarios() {
  const tree = '1.0.0+2';
  const older = '0.9.0+1';
  final ordered = PublishedTag('v0.9.0', _pubspec(older),
      changelog: _changelog(const ['0.9.0']));
  return [
    judge(
        app: _pubspec(tree),
        core: _pubspec('1.0.1+2'),
        tags: const [],
        changelog: null),
    judge(
        app: null,
        core: _pubspec(tree),
        tags: const [],
        changelog: null),
    judge(
        app: _pubspec(tree),
        core: _pubspec(tree),
        tags: const [],
        changelog: _changelog(const ['1.0.0'])),
    judge(
        app: _pubspec(tree),
        core: _pubspec(tree),
        tags: [ordered],
        changelog: _changelog(const [])),
    judge(
        app: _pubspec(tree),
        core: _pubspec(tree),
        tags: [ordered],
        changelog: null),
    judge(
        app: _pubspec(tree),
        core: _pubspec(tree),
        tags: [
          PublishedTag('v0.9.0', _pubspec(older),
              changelog: _changelog(const [])),
        ],
        changelog: _changelog(const ['1.0.0'])),
  ];
}

void main() {
  late String section;
  late List<_Quote> quotes;

  setUpAll(() {
    section = _section(_repoFile('CONTRIBUTING.md'));
    quotes = _quotes(section);
  });

  group('the extractor, controlled in both directions', () {
    const planted = '- `PLANTED LABEL: FIRST` (exit 1) -- a bullet naming a\n'
        '  code the way most of them do.\n'
        '- `PLANTED LABEL: SECOND` -- it does not, **and the exit code is\n'
        '  still 0.** Read the word and not the exit code.\n'
        '- `OTHER: THIRD` -- a bullet claiming no code at all.\n';

    test('it reads the shape, the label and both forms of the claim', () {
      final read = _quotes(planted);
      expect(read.map((q) => q.text), [
        'PLANTED LABEL: FIRST',
        'PLANTED LABEL: SECOND',
        'OTHER: THIRD',
      ]);
      expect(read.map((q) => q.exitClaim), [1, 0, null]);
      expect(read.map((q) => q.label),
          ['PLANTED LABEL', 'PLANTED LABEL', 'OTHER']);
    });

    // The other direction: it can answer zero, which is why every count
    // below is asserted rather than assumed.
    test('a bullet carrying no verdict extracts nothing', () {
      expect(_quotes('- prose only, and `lower: case` is not a verdict.\n'),
          isEmpty);
      expect(_quotes('- `## [VERSION]` is not one either.\n'), isEmpty);
    });
  });

  test('the section quotes eight verdicts, four under each of two labels', () {
    expect(quotes.length, 8,
        reason: 'CONTRIBUTING.md, "Cutting a release", no longer quotes the '
            'eight verdicts this file guards. If the section was rewritten, '
            'the extractor here has to be rewritten with it -- a count that '
            'silently fell to zero would leave the page guarded by nothing.');

    final perLabel = <String, int>{};
    for (final quote in quotes) {
      perLabel[quote.label] = (perLabel[quote.label] ?? 0) + 1;
    }
    expect(perLabel.length, 2,
        reason: 'the section answers in two voices, one per question; it now '
            'quotes ${perLabel.keys.join(', ')}');
    expect(perLabel.values, everyElement(4),
        reason: 'each voice has four answers; the section now quotes '
            '$perLabel');

    expect(quotes.where((q) => q.exitClaim != null).length, 6,
        reason: 'six of the eight bullets state an exit code, and each one '
            'is asserted below against the code the tool answers with');
  });

  test('the section names two tools, and both ship in this clone', () {
    final scripts = _scriptRun.allMatches(section).map((m) => m[1]!).toSet();
    expect(scripts.length, 2,
        reason: 'the release section tells the reader to run two scripts; it '
            'now names $scripts');
    for (final script in scripts) {
      expect(() => _repoFile(script), returnsNormally,
          reason: 'CONTRIBUTING.md, "Cutting a release", tells the reader to '
              'run $script, and no such file is in this clone');
    }
  });

  test('every verdict the page quotes is a string one of those tools prints',
      () {
    final scripts = _scriptRun.allMatches(section).map((m) => m[1]!).toSet();
    final sources = {for (final s in scripts) s: _repoFile(s)};

    for (final quote in quotes) {
      final printedBy = sources.entries
          .where((entry) => entry.value.contains(quote.text))
          .map((entry) => entry.key)
          .toList();
      expect(printedBy, isNotEmpty,
          reason: 'CONTRIBUTING.md, "Cutting a release", quotes '
              '"${quote.text}" as a verdict one of these tools prints, and '
              'none of them contains that string: ${sources.keys.join(', ')}. '
              'Either the message moved and CONTRIBUTING.md still teaches the '
              'old word, or the section was reworded. The document to fix is '
              'CONTRIBUTING.md.');
    }
  });

  test('every exit code the page claims is the one the tool answers with',
      () {
    final claimed = quotes.where((q) => q.exitClaim != null).toList();
    final exercised = <String>{};

    for (final verdict in _scenarios()) {
      final printed = verdict.lines.join('\n');
      for (final quote in claimed) {
        if (!printed.contains(quote.text)) continue;
        exercised.add(quote.text);
        expect(verdict.outcome.exitCode, quote.exitClaim,
            reason: 'CONTRIBUTING.md, "Cutting a release", says '
                '"${quote.text}" is exit ${quote.exitClaim}. '
                'tool/check-release-order.dart answered it with exit '
                '${verdict.outcome.exitCode}. The document to fix is '
                'CONTRIBUTING.md.');
      }
    }

    expect(exercised.length, claimed.length,
        reason: 'each verdict the page attaches an exit code to must be '
            'produced by one of the runs above, or its code is asserted '
            'against nothing. Not produced: '
            '${claimed.map((q) => q.text).where((t) => !exercised.contains(t))}'
            '. If the test above is also red, that one names the real cause '
            'and this follows from it; if it is green, the page has gained a '
            'verdict no run here reaches -- add a case to _scenarios().');
  });
}
