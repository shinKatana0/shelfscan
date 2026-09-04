/// The app's half of the Custom Cards target (T-0457).
///
/// The claim the brief makes about this screen is that registering an exporter
/// is the WHOLE of the wiring: the sheet iterates `exporters.entries` and asks
/// each one `canExport`, so a third target appears with an honest subtitle and
/// a working save without a line of screen code. Nothing here is a test of the
/// exporter's rule -- `custom_cards_contract_test.dart` in core owns that.
/// What is tested here is that the screen reached it.
///
/// Nothing opens a real dialog: the screen takes an [ExportSaver] and this
/// file injects a fake, the seam `review_screen_test.dart` already uses. The
/// GUI has not been driven (`doc/conventions.md` 3).
///
/// Every fixture value is invented.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelfscan_app/export_saver.dart';
import 'package:shelfscan_app/screens/review_screen.dart';
import 'package:shelfscan_core/shelfscan_core.dart';

class _FakeSaver extends ExportSaver {
  final List<({String extension, String content})> saves = [];

  @override
  Future<SaveOutcome> save({
    required String suggestedName,
    required String extension,
    required String content,
  }) async {
    saves.add((extension: extension, content: content));
    return const SaveOutcome.savedToFile(r'C:\out\cards.json');
  }
}

ResolvedGame _row(
  String rawTitle, {
  WorkKind kind = WorkKind.game,
  Candidate? best,
  String? platformHint,
}) =>
    ResolvedGame(
      detection: Detection(
        rawTitle: rawTitle,
        mediaType: MediaType.disc,
        confidence: 0.9,
        sourcePhoto: 'shelf_d.jpg',
        platformHint: platformHint,
        workKind: kind,
      ),
      best: best,
      status: ReviewStatus.approved,
    );

Candidate _match() => Candidate(
      externalId: 'igdb:715715',
      title: 'Mossgrave Ferry',
      platformId: 2727,
      platformName: 'Fictional Console',
      score: 1.0,
    );

ReviewDocument _doc(List<ResolvedGame> games) => ReviewDocument(
      version: 1,
      created: '2026-09-04T00:00:00.000Z',
      photos: const ['shelf_d.jpg'],
      games: games,
    );

Future<void> _pump(WidgetTester tester, ReviewDocument doc, ExportSaver saver) =>
    tester.pumpWidget(MaterialApp(
      home: ReviewScreen(document: doc, saver: saver),
    ));

Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('export-primary')));
  await tester.pumpAndSettle();
}

/// The subtitle under one target's tile in the export sheet.
String _subtitleOf(WidgetTester tester, String target) {
  final tile = tester.widget<ListTile>(find.byKey(Key('export-sheet-$target')));
  return (tile.subtitle! as Text).data!;
}

const _carriesNone = 'carries none of the marked rows';

void main() {
  testWidgets('the sheet offers the third target with no screen code',
      (tester) async {
    await _pump(tester, _doc([_row('MOSSGRAVE FERRY')]), _FakeSaver());
    await _openSheet(tester);

    // Over the registry: the tile is built from `exporters.entries`, so this
    // fails on a target the sheet cannot reach rather than on a missing
    // literal.
    for (final target in exporters.keys) {
      expect(find.byKey(Key('export-sheet-$target')), findsOneWidget,
          reason: '$target is registered and the sheet does not offer it');
    }
    expect(find.text('Export: tonkatsu-cards'), findsOneWidget);
    expect(_subtitleOf(tester, 'tonkatsu-cards'), startsWith('.json file'));
  });

  testWidgets('a fully matched shelf is told this target carries none of it',
      (tester) async {
    await _pump(tester, _doc([_row('MOSSGRAVE FERRY', best: _match())]),
        _FakeSaver());
    await _openSheet(tester);

    // The two Tonkatsu targets partition the rows, so the honest subtitle is
    // on the opposite tile from the one it is on for an unresolved shelf --
    // which is the pair of assertions, not either alone.
    expect(_subtitleOf(tester, 'tonkatsu-cards'), contains(_carriesNone));
    expect(_subtitleOf(tester, 'tonkatsu'), isNot(contains(_carriesNone)));
  });

  testWidgets('a shelf nothing resolved is told .xcoll carries none of it',
      (tester) async {
    await _pump(tester, _doc([_row('MOSSGRAVE FERRY', platformHint: 'PS4')]),
        _FakeSaver());
    await _openSheet(tester);

    expect(_subtitleOf(tester, 'tonkatsu'), contains(_carriesNone));
    expect(_subtitleOf(tester, 'tonkatsu-cards'), isNot(contains(_carriesNone)));
    expect(_subtitleOf(tester, 'csv'), isNot(contains(_carriesNone)));
  });

  testWidgets('exporting it saves a .json array of the rows .xcoll declined',
      (tester) async {
    final saver = _FakeSaver();
    await _pump(
        tester,
        _doc([
          _row('MOSSGRAVE FERRY', best: _match()),
          _row('QUARRY OF BELLS', platformHint: 'PS4'),
          _row('PELLUCID HOURS', kind: WorkKind.movie),
        ]),
        saver);
    await _openSheet(tester);

    await tester.tap(find.byKey(const Key('export-sheet-tonkatsu-cards')));
    await tester.pumpAndSettle();
    // The matched row goes to `.xcoll` instead, so this target drops it and
    // the screen says so before writing anything.
    expect(find.text('Unresolved items will be dropped'), findsOneWidget);
    await tester.tap(find.byKey(const Key('export-drop-confirm')));
    await tester.pumpAndSettle();

    expect(saver.saves, hasLength(1));
    expect(saver.saves.single.extension, 'json');
    final cards = jsonDecode(saver.saves.single.content) as List<dynamic>;
    expect(cards, [
      {'title': 'QUARRY OF BELLS', 'type': 'game', 'platform': 'PS4'},
      {'title': 'PELLUCID HOURS', 'type': 'movie'},
    ]);
    expect(find.textContaining('Saved 2 items'), findsOneWidget);
  });
}
