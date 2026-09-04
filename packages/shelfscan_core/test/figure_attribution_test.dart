/// A published figure names the model it was measured on (T-0467).
///
/// T-0466 moved the default local model and re-attached every measurement to
/// the model it was taken on by hand. Its own negative control then found
/// that nothing would have caught the mistake: two false re-attributions were
/// planted in `README.md` -- the "What to expect" sentence and the comparison
/// table's local column -- and all ten page-reading suites stayed green.
///
/// `documented_lists_test.dart` guards the opposite direction and is working:
/// a stated *default* must FOLLOW [defaultOllamaModel]. A figure's
/// attribution must not follow it, and nothing asserted that. So a
/// find-and-replace of a model id across the documentation would move every
/// published measurement onto a model it was never taken on, in silence.
///
/// ## The marker, and why it is not a parser
///
/// The figure surface is heterogeneous -- tables, prose, transcripts, cost
/// figures, codec timings, image dimensions -- so a regular expression over
/// "numbers near a model id" would either miss the case that matters or
/// reject ordinary numbers forever. Nothing here parses prose. A region is
/// declared instead, in the idiom `doc/guide.md` already uses for its pinned
/// transcripts:
///
///     <!-- measured-on: qwen2.5vl:7b -->
///     ... the figures ...
///     <!-- /measured-on -->
///
/// Both forms are HTML comments, invisible on the rendered page, and they
/// travel with the text they bound rather than with a line number.
///
/// ## What is asserted, and the failure each one catches
///
/// 1. **The count, per page.** [_expected] pins it. Deleting a marker fails
///    rather than shrinking the guard in silence, and a zero there is a
///    statement about a page rather than an omission.
/// 2. **A marker names a model this repository declares** -- read from the
///    three constants, never typed here. A marker naming a model no constant
///    holds is a typo. And it names the one the control sets are *defined*
///    on, which is the rule that survives a find-and-replace: a sweep across
///    the documentation moves the marker and the sentence under it together,
///    so the page ends up internally consistent and no rule reading only the
///    page can see it. The anchor has to be outside the page, and the code
///    already holds it -- `controlSetModel` states, rather than inherits,
///    the model every figure here was measured on.
/// 3. **A region names its model in the visible text too.** The marker is for
///    this file; the sentence is for the reader. A region whose prose stops
///    naming the model fails.
/// 4. **A region names one model and no other.** Stated that way rather than
///    as a list of forbidden strings: the region declares which model its
///    figures belong to, so every *other* declared id is a claim the region
///    is not entitled to make. That is the load-bearing one -- it is what
///    turns "the local column now says the shipped default" red.
/// 5. **No marker can change what the page renders.** A marker alone on a
///    line sits between blocks, surrounded by blank lines; a marker inside a
///    paragraph has text before it on its own line. Those are exactly the two
///    CommonMark positions in which the comment is invisible AND splits no
///    paragraph -- a bare opener at the start of a line interrupts a
///    paragraph, which moves the text on the rendered page.
///
/// ## What this does not cover
///
/// Only the pages in [_expected]. It does not walk the repository for
/// markers, so a marked region in a file nobody listed is not counted here --
/// `doc/measurements.md` in particular is full of figures and carries no
/// marker. It reads no numbers and knows nothing about whether a figure is
/// true; it asserts only which model a page says a figure belongs to.
library;

import 'dart:convert';
import 'dart:io';

import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

import '../tool/control_capture.dart';

/// The pages read here, and how many marked regions each must hold.
///
/// A zero says the page was surveyed and guards nothing, so a marker
/// appearing in it later fails until somebody decides what it means.
/// `CHANGELOG.md` is that case: its model entry carries no figure of its own,
/// and the one number in it -- the pull size -- is a property of the shipped
/// default and true of it.
///
/// The translations carry the same tables and the same figures, and the
/// marker travels into them unchanged: it is an HTML comment in Latin
/// characters, so it needs no translating and moves no translated sentence.
/// They hold fewer regions than the English only because they are `STALE` and
/// two English sections have no counterpart in them -- `doc/guide.md`'s
/// density ceiling is the one that matters here.
const _expected = <String, int>{
  'README.md': 4,
  'README.ru.md': 4,
  'README.ja.md': 4,
  'doc/guide.md': 4,
  'doc/guide.ru.md': 3,
  'doc/guide.ja.md': 3,
  'CHANGELOG.md': 0,
};

/// Every model id this repository declares, by the constant holding it.
///
/// Read from the code so that the day a constant moves this file follows it
/// without being edited. Two of the three hold one string today, which is a
/// decision `vision.dart` argues at its own site and not one to collapse here.
const _declared = <String, String>{
  'defaultOllamaModel': defaultOllamaModel,
  'testedOllamaInstructModel': testedOllamaInstructModel,
  'controlSetModel': controlSetModel,
};

final _newline = String.fromCharCode(10);

/// The canonical marker pair. Anything else that reads as one is caught by
/// [_looksLikeMarker], so a typo fails loudly instead of shrinking the count.
final _openMarker = RegExp('<!-- measured-on: ([^ ]+) -->');
final _closeMarker = RegExp('<!-- /measured-on -->');
final _htmlComment = RegExp('<!--.*?-->', dotAll: true);

bool _looksLikeMarker(String line) =>
    line.contains('<!--') && line.contains('measured-on');

/// One marked region: what it says its figures were measured on, and the text
/// between its two markers.
class _Region {
  const _Region(this.file, this.model, this.line, this.content);

  final String file;
  final String model;

  /// 1-based line of the opening marker, so a failure names a place.
  final int line;

  /// Everything between the markers, the markers themselves excluded.
  final String content;

  /// What a reader of the rendered page sees inside the region.
  String get visible => content.replaceAll(_htmlComment, '');

  String get where => '$file:$line (measured-on: $model)';
}

Directory _repoRoot() {
  for (var dir = Directory.current.absolute;; dir = dir.parent) {
    if (File('${dir.path}/.env.example').existsSync()) return dir;
    if (dir.path == dir.parent.path) {
      fail('no .env.example at or above ${Directory.current.path}');
    }
  }
}

String _pageText(String relative) {
  final file = File('${_repoRoot().path}/$relative');
  if (!file.existsSync()) fail('$relative is not where this file looks');
  final text = file.readAsStringSync();
  // A page that could not be read reads as zero regions, which is the one
  // answer that passes every rule below without proving anything.
  if (text.trim().isEmpty) fail('$relative is empty');
  return text;
}

int _lineOf(String text, int offset) =>
    text.substring(0, offset).codeUnits.where((c) => c == 10).length + 1;

/// The regions [text] declares, in order, or a failure naming the marker that
/// does not pair up.
List<_Region> _regionsIn(String file, String text) {
  final opens = _openMarker.allMatches(text).toList();
  final closes = _closeMarker.allMatches(text).toList();
  if (opens.length != closes.length) {
    fail('$file: ${opens.length} opening and ${closes.length} closing '
        'markers, so at least one region has no bound to read');
  }
  final regions = <_Region>[];
  for (var i = 0; i < opens.length; i++) {
    final open = opens[i];
    final close = closes[i];
    if (close.start < open.end) {
      fail('$file:${_lineOf(text, close.start)}: a closing marker before the '
          'region it should close -- the two forms have to alternate');
    }
    if (i + 1 < opens.length && opens[i + 1].start < close.start) {
      fail('$file:${_lineOf(text, open.start)}: this region is still open '
          'where the next one begins, and regions do not nest');
    }
    regions.add(_Region(file, open.group(1)!, _lineOf(text, open.start),
        text.substring(open.end, close.start)));
  }
  return regions;
}

/// Every declared id other than [model] -- the ones a region marked [model] is
/// not entitled to carry.
Set<String> _otherModels(String model) =>
    _declared.values.where((value) => value != model).toSet();

/// What is wrong with [region], as sentences, or nothing.
///
/// A list rather than an `expect` so the same rules run over the real pages
/// and over the synthetic documents below, which is the only way to know they
/// can still fail.
List<String> _complaintsAbout(_Region region) {
  final complaints = <String>[];
  if (!_declared.values.contains(region.model)) {
    complaints.add('${region.where}: no constant in this repository holds '
        '"${region.model}", so the marker names either a model nobody ships '
        'or a typo, and nothing can tell which');
  } else if (region.model != controlSetModel) {
    complaints.add('${region.where}: every figure this project publishes was '
        'measured on $controlSetModel -- the model the control sets are '
        'defined on, stated in tool/control_capture.dart. A region handed to '
        'another id is a re-attribution, unless a second model has actually '
        'been measured, in which case this rule is where to say so.');
  }
  if (!region.visible.contains(region.model)) {
    complaints.add('${region.where}: the marker says these figures were '
        'measured on ${region.model} and the text a reader sees no longer '
        'says so anywhere -- the attribution is gone from the page');
  }
  for (final other in _otherModels(region.model)) {
    if (region.content.contains(other)) {
      complaints.add('${region.where}: "$other" appears inside a region whose '
          'figures were measured on ${region.model}, so a measurement is '
          'being attributed to a model it was never taken on');
    }
  }
  return complaints;
}

/// What is wrong with where the markers in [text] sit, as sentences.
///
/// The two positions that render as nothing and move nothing: alone on a line
/// between blocks, or after text inside a paragraph. A bare opener at the
/// start of a line in the middle of a paragraph is an HTML block -- it ends
/// that paragraph and starts a second one, which a reader sees.
List<String> _placementComplaints(String file, String text) {
  final complaints = <String>[];
  final lines = const LineSplitter().convert(text);
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final marks = <RegExpMatch>[
      ..._openMarker.allMatches(line),
      ..._closeMarker.allMatches(line),
    ]..sort((a, b) => a.start.compareTo(b.start));
    if (marks.isEmpty) {
      if (_looksLikeMarker(line)) {
        complaints.add('$file:${i + 1}: this reads as a marker and matches '
            'neither form exactly, so the count above cannot see it');
      }
      continue;
    }
    final before = line.substring(0, marks.first.start);
    final after = line.substring(marks.last.end);
    if (before.isEmpty) {
      final previous = i == 0 ? '' : lines[i - 1];
      final next = i + 1 == lines.length ? '' : lines[i + 1];
      if (after.trim().isNotEmpty) {
        complaints.add('$file:${i + 1}: a marker opening a line makes the '
            'whole line an HTML block, so the text after it on that line '
            'renders as nothing');
      }
      if (previous.trim().isNotEmpty || next.trim().isNotEmpty) {
        complaints.add('$file:${i + 1}: a marker alone on a line inside a '
            'paragraph ends that paragraph and starts another, which moves '
            'the text on the rendered page -- leave a blank line either side, '
            'or put the marker after text on a line of the paragraph itself');
      }
    } else if (before.trim().isEmpty) {
      complaints.add('$file:${i + 1}: an indented marker still starts an HTML '
          'block, with the same effect on the paragraph around it');
    }
  }
  return complaints;
}

void main() {
  group('the marked regions on the published pages', () {
    final found = <String, List<_Region>>{
      for (final page in _expected.keys)
        page: _regionsIn(page, _pageText(page)),
    };

    test('there are marked regions at all', () {
      final total = found.values.fold(0, (sum, list) => sum + list.length);
      expect(total, greaterThan(0),
          reason: 'an extractor that matches nothing passes every rule below '
              'without having read a page');
      expect(total, _expected.values.reduce((a, b) => a + b));
    });

    for (final page in _expected.keys) {
      test('$page carries ${_expected[page]} of them', () {
        expect(found[page], hasLength(_expected[page]),
            reason: 'a marker was added or deleted; decide what the page '
                'guards and say so here');
      });
    }

    test('every marker names a model, and only its own', () {
      final complaints = [
        for (final regions in found.values)
          for (final region in regions) ..._complaintsAbout(region),
      ];
      expect(complaints, isEmpty, reason: complaints.join(_newline));
    });

    test('no marker can change what a page renders', () {
      final complaints = [
        for (final page in _expected.keys)
          ..._placementComplaints(page, _pageText(page)),
      ];
      expect(complaints, isEmpty, reason: complaints.join(_newline));
    });

    test('the declared ids still differ, so the rule can fail at all', () {
      // Two of the three hold one string. If the third ever joined them,
      // every region would have an empty set of ids it may not carry and the
      // load-bearing rule would pass on any page at all.
      expect(_otherModels(controlSetModel), isNotEmpty,
          reason: 'every declared model id is now the same string, so a '
              'region can no longer name a model that is not its own');
    });
  });

  group('the rules, on documents written to break them', () {
    // Synthetic pages, so the controls this guard exists for run on every
    // suite rather than once by hand: an honest page passes, a re-attributed
    // figure fails, a page that stops naming its model fails, and ordinary
    // numbers make none of it fail.
    String page(List<String> lines) => lines.join(_newline);

    final ordinary = [
      'Runs on port 4571, version 2 of the format, since 2026.',
      'A cloud pass costs about 9 dollars 50 and takes 400 ms to start.',
    ];

    final honest = page([
      ...ordinary,
      '',
      '<!-- measured-on: $controlSetModel -->',
      '',
      'Measured on $controlSetModel: about 7 s a photo, 41% of spines.',
      '',
      '<!-- /measured-on -->',
      '',
      'The default is $defaultOllamaModel and nothing here has timed it.',
    ]);

    test('an honest page is read, and its ordinary numbers pass', () {
      final regions = _regionsIn('honest.md', honest);
      expect(regions, hasLength(1));
      expect(regions.single.model, controlSetModel);
      expect(_complaintsAbout(regions.single), isEmpty);
      expect(_placementComplaints('honest.md', honest), isEmpty);
    });

    test('a page that marks nothing yields no region', () {
      expect(_regionsIn('plain.md', page(ordinary)), isEmpty);
    });

    test('re-attributing the figure to the shipped default is caught', () {
      final moved = honest.replaceAll(
          'Measured on $controlSetModel', 'Measured on $defaultOllamaModel');
      final complaints = _complaintsAbout(_regionsIn('moved.md', moved).single);
      expect(complaints, isNotEmpty);
      expect(complaints.join(' '), contains(defaultOllamaModel));
    });

    test('replacing the id on the marker as well is caught', () {
      // The find-and-replace shape, and the one no rule reading only the page
      // can catch: both halves move together, so the page agrees with itself
      // afterwards. What catches it is the anchor outside the page --
      // controlSetModel, which the sweep did not touch.
      final swept = honest.replaceAll(controlSetModel, defaultOllamaModel);
      final regions = _regionsIn('swept.md', swept);
      expect(regions.single.model, defaultOllamaModel);
      final complaints = _complaintsAbout(regions.single);
      expect(complaints, isNotEmpty);
      expect(complaints.join(' '), contains(controlSetModel));
    });

    test('removing the attribution from the prose is caught', () {
      final stripped =
          honest.replaceAll('Measured on $controlSetModel:', 'Measured:');
      final complaints =
          _complaintsAbout(_regionsIn('stripped.md', stripped).single);
      expect(complaints, isNotEmpty);
      expect(complaints.join(' '), contains('the attribution is gone'));
    });

    test('a marker naming a model no constant holds is caught', () {
      final typo = honest.replaceAll(
          '<!-- measured-on: $controlSetModel -->',
          '<!-- measured-on: not-a-model -->');
      expect(_complaintsAbout(_regionsIn('typo.md', typo).single), isNotEmpty);
    });

    test('a marker dropped into the middle of a paragraph is caught', () {
      final split = page([
        'A paragraph whose first line says nothing about any model,',
        '<!-- measured-on: $controlSetModel -->',
        'and whose second line names $controlSetModel and 7 s.',
        '',
        '<!-- /measured-on -->',
      ]);
      expect(_placementComplaints('split.md', split), isNotEmpty);
    });

    test('an unpaired marker is a failure and not a smaller guard', () {
      final unpaired = honest.replaceAll('<!-- /measured-on -->', '');
      expect(() => _regionsIn('unpaired.md', unpaired), throwsA(anything));
    });
  });
}
