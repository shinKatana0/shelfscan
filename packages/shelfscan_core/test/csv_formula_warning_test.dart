/// The warning at the point of export (T-0187).
///
/// T-0185 decided not to rewrite a cell a spreadsheet reads as a formula and
/// put the explanation in `README.md`; `csv_formula_cell_test.dart` pins that
/// decision and is not touched here. This file pins the half T-0185 could not
/// build: decision 0011's precedent is that *"the warning belongs at the point
/// of selection ... not in a README nobody opens"*, so the export itself has to
/// say it.
///
/// Three things, in order: the rule on the exporter, the sentence the CLI
/// builds from it, and a real `dart run bin/shelfscan.dart export` that prints
/// it -- and, in every group, the silence on an export that has no such cell.
/// The silence is the load-bearing half: a warning that fires on every export
/// is one people learn to ignore.
@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';

import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

import '../bin/shelfscan.dart' show formulaCellsShown, spreadsheetNote;

ResolvedGame _game(
  String rawTitle, {
  String? sourceEntry,
  String sourcePhoto = 'shelf_a.jpg',
  Candidate? best,
}) =>
    ResolvedGame(
      detection: Detection(
        rawTitle: rawTitle,
        mediaType: MediaType.disc,
        confidence: 1.0,
        sourcePhoto: sourcePhoto,
        platformHint: 'PS4',
        sourceEntry: sourceEntry,
        origin:
            sourceEntry == null ? DetectionOrigin.vision : DetectionOrigin.filename,
      ),
      best: best,
      status: ReviewStatus.approved,
    );

ReviewDocument _doc(List<ResolvedGame> games) => ReviewDocument(
      version: 1,
      created: '2026-08-13T00:00:00Z',
      photos: const ['shelf_a.jpg'],
      games: games,
    );

Directory _tempDir(String prefix) {
  final dir = Directory.systemTemp.createTempSync(prefix);
  addTearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // The Windows errno 145 race the other path suites document.
    }
  });
  return dir;
}

String _join(String dir, String name) => '$dir${Platform.pathSeparator}$name';

Future<ProcessResult> _runCli(List<String> args) => Process.run(
      Platform.resolvedExecutable,
      ['run', 'bin/shelfscan.dart', ...args],
      environment: {'IGDB_CLIENT_ID': '', 'IGDB_CLIENT_SECRET': ''},
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );

Directory _repoRoot() {
  for (var dir = Directory.current.absolute;; dir = dir.parent) {
    if (File('${dir.path}/.env.example').existsSync()) return dir;
    if (dir.path == dir.parent.path) {
      fail('no .env.example at or above ${Directory.current.path}');
    }
  }
}

void main() {
  group('CsvExporter.formulaCells', () {
    test('says nothing about an ordinary export', () {
      final doc = _doc([
        _game('DUSKHOLLOWE', sourceEntry: 'Duskhollow'),
        _game('FROST WAKE'),
      ]);
      expect(CsvExporter().formulaCells(doc), isEmpty);
    });

    test('names the cell and the column it is in', () {
      // The measured ordinary case (T-0185): `parseGameFileName` drops a
      // leading `-`, so a folder named `-Tactics` reaches `source_entry` and
      // nothing else.
      final doc = _doc([_game('Tactics', sourceEntry: '-Tactics')]);

      expect(CsvExporter().formulaCells(doc),
          [(column: 'source_entry', value: '-Tactics')]);
    });

    test('all four leaders, in title and in source_entry', () {
      for (final lead in CsvExporter.formulaLeaders) {
        final doc = _doc([_game('${lead}Anima', sourceEntry: '${lead}Anima')]);
        expect(
            CsvExporter().formulaCells(doc).map((c) => c.column).toList(),
            ['title', 'source_entry'],
            reason: lead);
      }
    });

    test('a quoted cell is still one: quoting does not defuse it', () {
      // The whole reason the rule reads the value rather than the emitted
      // field. `=1,2` holds a comma, so `_cell` wraps it -- and a spreadsheet
      // strips the quotes before it looks at the first character.
      final doc = _doc([_game('=1,2')]);
      final csv = CsvExporter().export(doc);

      expect(csv, contains('"=1,2"'));
      expect(CsvExporter().formulaCells(doc),
          [(column: 'title', value: '=1,2')]);
    });

    test('only cells that are actually written', () {
      // A pending row is not in the file, so it is not in the warning.
      final doc = ReviewDocument(
        version: 1,
        created: '',
        photos: const [],
        games: [
          ResolvedGame(
            detection: Detection(
                rawTitle: '=Nothing',
                mediaType: MediaType.disc,
                confidence: 1.0,
                sourcePhoto: ''),
            status: ReviewStatus.pending,
          ),
        ],
      );
      expect(CsvExporter().formulaCells(doc), isEmpty);
      expect(CsvExporter().export(doc), isNot(contains('=Nothing')));
    });

    test('the provenance columns exist only when the export has them', () {
      // `source_entry` is appended only to an export with provenance to
      // publish (T-0166), so a photograph-only run cannot report a cell that
      // is not in its five columns.
      final doc = _doc([_game('=Nothing')]);
      expect(CsvExporter().formulaCells(doc).map((c) => c.column),
          isNot(contains('source_entry')));
    });

    test('.xcoll has none, because JSON is not read as a spreadsheet', () {
      final doc = _doc([
        _game('=Nothing',
            sourceEntry: '-Tactics',
            best: Candidate(
                igdbId: 1,
                title: '=Nothing',
                platformId: 48,
                platformName: 'PlayStation 4',
                score: 1.0)),
      ]);
      expect(TonkatsuExporter().formulaCells(doc), isEmpty);
    });
  });

  group('spreadsheetNote', () {
    test('is empty when there is nothing to say', () {
      expect(spreadsheetNote(const [], 'shelf.csv'), isEmpty);
    });

    test('names what a spreadsheet does, the cells, and a remedy', () {
      final note = spreadsheetNote(const [
        (column: 'source_entry', value: '-Tactics'),
        (column: 'title', value: '=Nothing'),
      ], r'C:\out\shelf.csv');

      expect(note.first, startsWith('2 cell(s) begin with =, +, - or @'));
      expect(note.first, contains('read as a formula rather than as text'));
      expect(note, contains('    source_entry: -Tactics'));
      expect(note, contains('    title: =Nothing'));
      // The remedy, and the reason it is a remedy rather than an alarm: the
      // documented consumer is unaffected and nothing was rewritten.
      expect(note.last, contains('an import dialog is unaffected'));
      expect(note.last, contains('columns set to Text'));
      expect(note.last, contains(r'C:\out\shelf.csv'));
    });

    test('stops naming at $formulaCellsShown and counts the rest', () {
      final note = spreadsheetNote([
        for (var i = 0; i < 20; i++) (column: 'title', value: '=row$i'),
      ], 'shelf.csv');

      // Header, six names, the count, the remedy.
      expect(note, hasLength(formulaCellsShown + 3));
      expect(note.first, startsWith('20 cell(s)'));
      expect(note, contains('    ... and ${20 - formulaCellsShown} more'));
      expect(note, isNot(contains('    title: =row${formulaCellsShown + 1}')));
    });
  });

  group('the CLI prints it, off a real export', () {
    late String reviewPath;
    late String outPath;

    void write(ReviewDocument doc) =>
        File(reviewPath).writeAsStringSync(jsonEncode(doc.toJson()));

    setUp(() {
      final dir = _tempDir('shelfscan_formula_');
      reviewPath = _join(dir.path, 'collection.review.json');
      outPath = _join(dir.path, 'shelf.csv');
    });

    test('an export with a formula cell warns and names it', () async {
      write(_doc([
        _game('Duskhollow', sourceEntry: 'Duskhollow'),
        _game('Tactics', sourceEntry: '-Tactics'),
      ]));

      final result =
          await _runCli(['export', reviewPath, '--target', 'csv', '-o', outPath]);

      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      expect(result.stdout, contains('Exported 2 of 2'));
      expect(result.stdout, contains('1 cell(s) begin with =, +, - or @'));
      expect(result.stdout, contains('source_entry: -Tactics'));
      expect(result.stdout, contains('columns set to Text'));
      // The file itself is untouched by any of this.
      expect(File(outPath).readAsStringSync(), contains(',-Tactics,'));
    });

    test('an export with none says nothing extra', () async {
      write(_doc([
        _game('Duskhollow', sourceEntry: 'Duskhollow'),
        _game('Frost Wake', sourceEntry: 'Frost Wake'),
      ]));

      final result =
          await _runCli(['export', reviewPath, '--target', 'csv', '-o', outPath]);

      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      expect(result.stdout, contains('Exported 2 of 2'));
      expect(result.stdout, isNot(contains('cell(s) begin with')));
      expect(result.stdout, isNot(contains('spreadsheet')));
    });

    test('the same document exported to .xcoll says nothing', () async {
      write(_doc([
        _game('Tactics',
            sourceEntry: '-Tactics',
            best: Candidate(
                igdbId: 1,
                title: 'Tactics',
                platformId: 48,
                platformName: 'PlayStation 4',
                score: 1.0)),
      ]));

      final result = await _runCli(
          ['export', reviewPath, '--target', 'tonkatsu', '-o', outPath]);

      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      expect(result.stdout, isNot(contains('cell(s) begin with')));
    });
  });

  group('the remedy the note points at', () {
    // The note ends at README's "Opening the CSV in a spreadsheet" rather than
    // spelling out two dialogs in two applications on a terminal line, so the
    // check that the remedy exists is that the section still gives it. The
    // behaviour of the spreadsheets themselves is documented rather than
    // measured here (T-0185): this repository holds no spreadsheet.
    test('README still gives the import-as-text remedy the note names', () {
      final readme = File('${_repoRoot().path}/README.md')
          .readAsStringSync()
          .replaceAll(RegExp(r'\s+'), ' ');

      expect(readme, contains('Opening the CSV in a spreadsheet'));
      expect(readme, contains('import it rather than double-click it'));
      expect(readme, contains('Data → From Text/CSV'));
      expect(readme, contains('Evaluate formulas'));
    });
  });
}
