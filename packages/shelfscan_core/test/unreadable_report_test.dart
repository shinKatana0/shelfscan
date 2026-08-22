/// What the CLI's scan summary says about spines the model could not read
/// (T-0109).
///
/// The defect was a unit, not an arithmetic bug: the type was one entry per
/// spine by construction -- its name (`UnreadableSpine`, until T-0154), its
/// doc comment, `unreadableByPhoto` and the summary line all said so -- and on
/// `gpt-4.1-mini` one entry describes several spines. Measured over 10 runs of
/// CONTROL-HIRES's shelf-3, every run answers exactly one entry
/// naming two or three middle spines against a hand count off the photograph
/// it never matches; a second photo answers one entry on 8 runs and two on 2
/// for one and the same group of spines. So the shipped line said
/// "Unreadable spines: 1" about a photograph carrying more of them than that,
/// and said 1 or 2 about a photograph that had not changed.
///
/// The case below is that measured answer, verbatim. What is asserted is the
/// text a human reads, because the text was the whole defect.
library;

import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

import '../bin/shelfscan.dart' show unreadableReport;

ReviewDocument _doc(List<UnreadSpineReport> unreadable) => ReviewDocument(
      version: 1,
      created: '2026-08-16T00:00:00Z',
      photos: const ['shelf-3.jpg'],
      games: [],
      unreadable: unreadable,
    );

/// The one entry all 10 runs answered for that photograph.
UnreadSpineReport get _grouped => UnreadSpineReport(
      sourcePhoto: 'shelf-3.jpg',
      script: SpineScript.latin,
      reason: 'two/three spines in the middle are too blurred to read',
    );

void main() {
  test('nothing unread says nothing', () {
    expect(unreadableReport(_doc([])), isEmpty);
  });

  group('one entry describing several spines', () {
    late List<String> lines;
    setUp(() => lines = unreadableReport(_doc([_grouped])));

    test('the count is not offered as a number of spines', () {
      final head = lines.first;
      expect(head, isNot(contains('Unreadable spines: 1')));
      expect(head, isNot(matches(RegExp(r'\b1 spine\b'))));
      expect(head, contains('1'));
      expect(head, contains('report'));
    });

    test('it says out loud what the number is not', () {
      expect(lines.first, contains('not a count of spines'));
      expect(lines.first, contains('several spines'));
    });

    test("the model's own wording is where the several spines are visible", () {
      // The only truthful answer to "how many?" on this photograph is the
      // sentence the model wrote; a number derived from it would be the
      // fabricated count T-0028 removed.
      expect(lines, contains(contains('two/three spines in the middle')));
    });

    test('the per-photo breakdown counts the same unit as the head', () {
      expect(lines, contains(contains('shelf-3.jpg: 1 report(s)')));
      expect(lines.where((l) => l.contains('unread spine')), isEmpty);
    });

    test('the script tally is unchanged and still per entry', () {
      expect(lines, contains(contains('by script: latin: 1')));
    });
  });

  test('the 8-of-10 and 2-of-10 answers differ only in the number of reports',
      () {
    // Same two spines on the same photograph, one report on 8 runs and two on
    // 2. Both are now reported in an honest unit, so the figure moving no
    // longer reads as the shelf changing.
    final one = unreadableReport(_doc([_grouped]));
    final two = unreadableReport(_doc([_grouped, _grouped]));
    expect(one.first, contains('reports: 1'));
    expect(two.first, contains('reports: 2'));
    for (final head in [one.first, two.first]) {
      expect(head, contains('not a count of spines'));
    }
  });

  test('a hand-edited entry belonging to no photo is still named', () {
    // UnreadSpineReport.titleless leaves sourcePhoto empty for a manual row;
    // the review screen already gives that case a label rather than a blank.
    final lines = unreadableReport(_doc([
      UnreadSpineReport(sourcePhoto: '', reason: 'listed with an empty title'),
    ]));
    expect(lines, contains(contains('not from a photo')));
    expect(lines.any((l) => l.contains(': 1 report(s)')), isTrue);
  });

  test('a reason the model omitted is named as missing, not blanked', () {
    final lines = unreadableReport(
        _doc([UnreadSpineReport(sourcePhoto: 'shelf.jpg')]));
    expect(lines, contains(contains('no reason given')));
    expect(lines, contains(contains('by script: unknown: 1')));
  });
}
