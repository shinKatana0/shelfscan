/// A report can describe several unread spines, so the CLI must label its
/// count as reports. Synthetic fixtures check the text a person sees.
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

/// A synthetic report that describes more than one unread spine.
UnreadSpineReport get _grouped => UnreadSpineReport(
      sourcePhoto: 'shelf-3.jpg',
      script: SpineScript.latin,
      reason: 'two or three imaginary spines in the center are blurred',
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
      // The model wording is preserved; parsing a number out of prose would
      // invent a more precise count than the report provides.
      expect(lines, contains(contains('two or three imaginary spines')));
    });

    test('the per-photo breakdown counts the same unit as the head', () {
      expect(lines, contains(contains('shelf-3.jpg: 1 report(s)')));
      expect(lines.where((l) => l.contains('unread spine')), isEmpty);
    });

    test('the script tally is unchanged and still per entry', () {
      expect(lines, contains(contains('by script: latin: 1')));
    });
  });

  test('different report counts keep the same unit',
      () {
    // Repeated reads may group the same unread area differently; report
    // counts keep the unit honest in either case.
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
