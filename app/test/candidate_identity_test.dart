/// The picker, on the rows it exists for: two candidates a human is asked to
/// choose between (T-0170, folding T-0172).
///
/// T-0165's refused ties reach review as two rows identical in every field
/// `Candidate` used to carry, `score` at 1.000 on both, and T-0159's exact join
/// arrives byte-identical to a spine that happened to Levenshtein-match at
/// 1.000. The pairs below are the collisions measured live 2026-08-16 on
/// T-0156's desktop titles (doc/measurements.md, "The tie nobody could
/// see").
///
/// T-0337 adds the third clause, and it is the one the ROW has to carry: a
/// film TMDB answered only once the year was dropped scores exactly what a
/// corroborated one scores, so the number cannot be what tells the two apart
/// and a person scanning the list has nothing else. Those fixtures are films
/// and carry no platform, which is why they are built by `_film` rather than
/// by `_candidate`.
///
/// Nothing here opens a save dialog, a share sheet or a network connection: no
/// exporter is reached and the screen is handed a document, not a resolver.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelfscan_app/export_saver.dart';
import 'package:shelfscan_app/screens/review_screen.dart';
import 'package:shelfscan_core/shelfscan_core.dart';

class _NoSaver extends ExportSaver {
  @override
  Future<SaveOutcome> save({
    required String suggestedName,
    required String extension,
    required String content,
  }) async =>
      throw StateError('no test here exports anything');
}

Candidate _candidate(
  int id,
  String title, {
  int? releaseYear,
  String platform = 'PC (Microsoft Windows)',
  int platformId = 6,
  double score = 1.0,
  MatchMethod matchMethod = MatchMethod.fuzzy,
}) =>
    Candidate(
      externalId: 'igdb:$id',
      title: title,
      platformId: platformId,
      platformName: platform,
      score: score,
      releaseYear: releaseYear,
      matchMethod: matchMethod,
    );

ReviewDocument _doc(
  String rawTitle, {
  Candidate? best,
  required List<Candidate> candidates,
}) =>
    ReviewDocument(
      version: 1,
      created: '2026-08-16T00:00:00Z',
      photos: const ['shelf1.jpg'],
      games: [
        ResolvedGame(
          detection: Detection(
            rawTitle: rawTitle,
            platformHint: 'PC',
            mediaType: MediaType.unknown,
            confidence: 1.0,
            sourcePhoto: 'shelf1.jpg',
          ),
          best: best,
          candidates: candidates,
        ),
      ],
      unreadable: const [],
    );

/// One film row of the shape T-0336's retry produces, or the corroborated row
/// it has to be told apart from.
///
/// Neither candidate carries a platform, because a film has none (decision
/// 0016): the row opens on `?` where a game row opens on a catalogue platform
/// name, and the picker line omits the clause altogether.
ResolvedGame _film(
  String rawTitle, {
  required String title,
  required int tmdbId,
  required int catalogueYear,
  required int filenameYear,
  required MatchMethod matchMethod,
}) {
  final candidate = Candidate(
    externalId: '$tmdbCatalogue:$tmdbId',
    title: title,
    score: 1.0,
    releaseYear: catalogueYear,
    matchMethod: matchMethod,
  );
  return ResolvedGame(
    detection: Detection.fromSource(
      rawTitle: rawTitle,
      origin: DetectionOrigin.filename,
      sourceEntry: '$rawTitle.mkv',
      sourceYear: filenameYear,
      workKind: WorkKind.movie,
    ),
    best: candidate,
    candidates: [candidate],
  );
}

ReviewDocument _films(List<ResolvedGame> games) => ReviewDocument(
      version: 1,
      created: '2026-08-16T00:00:00Z',
      photos: const [],
      games: games,
      unreadable: const [],
    );

Future<void> _pump(WidgetTester tester, ReviewDocument doc) =>
    tester.pumpWidget(MaterialApp(
      home: ReviewScreen(document: doc, saver: _NoSaver()),
    ));

Future<void> _openPicker(WidgetTester tester, ReviewDocument doc) async {
  await _pump(tester, doc);
  await tester.tap(find.byKey(const Key('review-row-0')));
  await tester.pumpAndSettle();
}

void main() {
  group('two same-name candidates are told apart by their release year', () {
    // Each pair is a refused tie: `best` is null, both rows score 1.000, and
    // before T-0170 the two lines were character for character the same.
    for (final (raw, pair) in <(String, List<Candidate>)>[
      (
        'REGENT OF AUREX',
        [
          _candidate(1100000058, 'Regent of Aurex', releaseYear: 1993),
          _candidate(1100000009, 'Regent of Aurex', releaseYear: 2016),
        ]
      ),
      (
        'CABALISTS',
        [
          _candidate(1100000059, 'Cabalists', releaseYear: 1993),
          _candidate(1100000010, 'Cabalists', releaseYear: 2012),
        ]
      ),
      (
        'MOOR',
        [
          _candidate(1100000011, 'Moor', releaseYear: 2016),
          _candidate(1100000012, 'The Ultimate Moor', releaseYear: 1995),
        ]
      ),
    ]) {
      testWidgets('$raw offers two rows that differ', (tester) async {
        await _openPicker(tester, _doc(raw, candidates: pair));

        final subtitles = [
          for (final candidate in pair)
            'PC (Microsoft Windows) - ${candidate.releaseYear} - score 100%',
        ];
        for (final subtitle in subtitles) {
          expect(find.text(subtitle), findsOneWidget);
        }
        expect(subtitles.first, isNot(subtitles.last));
      });
    }
  });

  testWidgets('a candidate IGDB has no date for implies no year',
      (tester) async {
    // A small fraction of the games one control run touches (T-0165). An
    // absent year
    // prints nothing rather than a placeholder: a row must not read as a claim
    // about a date nobody has.
    await _openPicker(
        tester,
        _doc('CABALISTS', candidates: [
          _candidate(1100000059, 'Cabalists'),
          _candidate(1100000010, 'Cabalists', releaseYear: 2012),
        ]));

    expect(find.text('PC (Microsoft Windows) - score 100%'), findsOneWidget);
    expect(find.text('PC (Microsoft Windows) - 2012 - score 100%'),
        findsOneWidget);
    for (final placeholder in ['unknown', 'n/a', '----', '?']) {
      expect(find.textContaining('- $placeholder -'), findsNothing);
    }
  });

  testWidgets('an exact join does not claim a score it never earned',
      (tester) async {
    // Both are 1.0, and only one of them was measured against a string:
    // 18 of T-0159's 394 live joins carry a store title that is not IGDB's
    // canonical name, so a percentage on a joined row is a claim nobody made.
    final joined = _candidate(1100000012, 'The Ultimate Moor',
        releaseYear: 1995, matchMethod: MatchMethod.externalId);
    final fuzzy = _candidate(1100000011, 'Moor', releaseYear: 2016);
    await _openPicker(
        tester, _doc('MOOR', best: joined, candidates: [joined, fuzzy]));

    expect(find.text('PC (Microsoft Windows) - 1995 - matched by store id'),
        findsOneWidget);
    expect(
        find.text('PC (Microsoft Windows) - 2016 - score 100%'), findsOneWidget);
    expect(find.textContaining('1995 - score'), findsNothing);
  });

  testWidgets('and the review row behind it says the same thing',
      (tester) async {
    final joined = _candidate(1100000012, 'The Ultimate Moor',
        releaseYear: 1995, matchMethod: MatchMethod.externalId);
    await _pump(tester, _doc('MOOR', best: joined, candidates: [joined]));

    // Clause order is T-0041's: platform, raw, then what the match is.
    expect(
        find.text('PC (Microsoft Windows) - raw: "MOOR" - 1995 - '
            'matched by store id'),
        findsOneWidget);
  });

  group('a film found only after the year was dropped is not an ordinary '
      'match (T-0337)', () {
    // The retry sends the SAME title a second time, so the percentage is the
    // identical number on both rows below and the clause is the whole of the
    // difference between them. Built per test rather than shared: the screen
    // writes `status` on the rows it is handed.
    ResolvedGame retried() => _film('TIDEWRACK 1998',
        title: 'Tidewrack',
        tmdbId: 770001,
        catalogueYear: 2001,
        filenameYear: 1998,
        matchMethod: MatchMethod.yearlessRetry);
    ResolvedGame corroborated() => _film('PALE ANCHOR 1994',
        title: 'Pale Anchor',
        tmdbId: 770002,
        catalogueYear: 1994,
        filenameYear: 1994,
        matchMethod: MatchMethod.fuzzy);

    testWidgets('the row says so without anything being opened',
        (tester) async {
      await _pump(tester, _films([retried(), corroborated()]));

      expect(
          find.text('? - raw: "TIDEWRACK 1998" - 2001 - score 100% - '
              'year did not match - Film'),
          findsOneWidget);
      expect(
          find.text('? - raw: "PALE ANCHOR 1994" - 1994 - score 100% - Film'),
          findsOneWidget);
      // The negative half, on the list rather than on one row: the clause
      // marks the film the year could not corroborate and not every film.
      expect(find.textContaining('year did not match'), findsOneWidget);
    });

    testWidgets('so does its line in the picker', (tester) async {
      await _openPicker(tester, _films([retried(), corroborated()]));

      expect(find.text('2001 - score 100% - year did not match'),
          findsOneWidget);
    });

    testWidgets('a corroborated film gains no new text', (tester) async {
      await _openPicker(tester, _films([corroborated()]));

      expect(find.text('1994 - score 100%'), findsOneWidget);
      expect(find.textContaining('year did not match'), findsNothing);
    });
  });
}
