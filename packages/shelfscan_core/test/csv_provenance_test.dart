/// What the CSV says about where a row came from (T-0166).
///
/// A row a non-photograph source produced carries `source_photo` '' by design
/// (T-0052), so until this task the only export the app ever writes said
/// nothing at all about a folder of 300 installs. The app holds its review
/// document in memory and deliberately never writes one
/// (`scan_screen.dart`, `_HeldReview`), so the CSV is not a lesser view of a
/// file the reader also has -- for that half of the product it is the only
/// durable record of the run.
///
/// Pinned here:
///   1. a photograph-only export is byte-identical to before this task --
///      same header, same five columns, no empty ones added;
///   2. a GoG-metadata row, a filename row and a photograph row read back
///      out of one file, each saying which of the three it is;
///   3. the cells survive a spreadsheet: a comma, a double quote, and a
///      Windows path with backslashes.
library;

import 'dart:convert';

import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

const _baseHeader = 'title,platform,media_type,igdb_id,source_photo';
const _fullHeader = '$_baseHeader,source_entry,origin,source_id';

ReviewDocument _doc(List<ResolvedGame> games) => ReviewDocument(
      version: 1,
      created: '2026-08-13T00:00:00Z',
      photos: const ['shelf_a.jpg'],
      games: games,
    );

ResolvedGame _approved(Detection detection, {Candidate? best}) =>
    ResolvedGame(
      detection: detection,
      best: best,
      status: ReviewStatus.approved,
    );

Detection _photographed(String title, {String photo = 'shelf_a.jpg'}) =>
    Detection(
      rawTitle: title,
      platformHint: 'PS4',
      mediaType: MediaType.disc,
      confidence: 0.9,
      sourcePhoto: photo,
    );

List<String> _rows(ReviewDocument doc) => const LineSplitter()
    .convert(CsvExporter().export(doc))
    .where((l) => l.isNotEmpty)
    .toList();

void main() {
  group('a photograph-only export does not change', () {
    test('header and row are exactly what they were before T-0166', () {
      final rows = _rows(_doc([
        _approved(_photographed('DUSKHOLLOWE'),
            best: Candidate(
              igdbId: 7,
              title: 'Duskhollow',
              platformId: 48,
              platformName: 'PlayStation 4',
              score: 1.0,
            )),
      ]));

      expect(rows, hasLength(2));
      expect(rows[0], _baseHeader);
      expect(rows[1], 'Duskhollow,PlayStation 4,disc,7,shelf_a.jpg');
      expect(rows[1].split(',').length, 5,
          reason: 'no empty provenance columns on a run that has none');
    });

    test('nor does a document whose photoless rows are typed by hand', () {
      // A manual row has no `source_entry` and no `source_id`: T-0052 settled
      // what the CSV says about it, and this task is not that question.
      final rows = _rows(_doc([
        _approved(Detection.manual(
          rawTitle: 'Nocturne 5 Gold',
          platformHint: 'PS4',
          mediaType: MediaType.disc,
          addedFromPhoto: 'shelf_a.jpg',
        )),
      ]));

      expect(rows[0], _baseHeader);
      expect(rows[1], 'Nocturne 5 Gold,PS4,disc,,');
    });
  });

  group('three kinds of row in one file', () {
    late List<String> rows;

    setUp(() {
      rows = _rows(_doc([
        _approved(Detection.fromSource(
          rawTitle: 'Marlow\'s Gate 3',
          origin: DetectionOrigin.metadata,
          sourceEntry: 'goggame-1100000008.info',
          sourceId: 'gog:1100000008',
        )),
        _approved(Detection.fromSource(
          rawTitle: 'Harbour Lantern',
          origin: DetectionOrigin.filename,
          sourceEntry: 'setup_harbour_lantern_1.0.exe',
        )),
        _approved(_photographed('Duskhollow')),
      ]));
    });

    test('the header gains the three columns, appended', () {
      expect(rows[0], _fullHeader);
      expect(rows[0], startsWith(_baseHeader),
          reason: 'columns 0-4 stay where a positional reader expects them');
    });

    test('the installer-written row names its file, its kind and its id', () {
      expect(rows[1],
          'Marlow\'s Gate 3,,unknown,,,goggame-1100000008.info,metadata,gog:1100000008');
    });

    test('the guessed row says so, and claims no store id', () {
      expect(rows[2],
          'Harbour Lantern,,unknown,,,setup_harbour_lantern_1.0.exe,filename,');
    });

    test('the photographed row keeps source_photo and adds nothing', () {
      expect(rows[3], 'Duskhollow,PS4,disc,,shelf_a.jpg,,vision,');
    });

    test('every row has the same number of cells as the header', () {
      for (final row in rows) {
        expect(_cells(row), hasLength(8), reason: row);
      }
    });
  });

  test('a source id alone is enough to publish the columns', () {
    // The trigger is either field, not `sourceEntry` alone: a hand-written
    // review.json may carry the join key and nothing else, and dropping it
    // would be the same silent loss this task exists to end.
    final rows = _rows(_doc([
      _approved(Detection(
        rawTitle: 'Vex',
        mediaType: MediaType.unknown,
        confidence: 0.0,
        sourcePhoto: '',
        origin: DetectionOrigin.metadata,
        sourceId: 'gog:1100000014',
      )),
    ]));

    expect(rows[0], _fullHeader);
    expect(rows[1], 'Vex,,unknown,,,,metadata,gog:1100000014');
  });

  group('the cells survive a spreadsheet', () {
    test('a folder name with a comma is quoted', () {
      final rows = _rows(_doc([
        _approved(Detection.fromSource(
          rawTitle: 'Ashfall',
          origin: DetectionOrigin.filename,
          sourceEntry: 'Ashfall 1, 2 and Tactics',
        )),
      ]));

      expect(rows[1], 'Ashfall,,unknown,,,"Ashfall 1, 2 and Tactics",filename,');
      expect(_cells(rows[1])[5], 'Ashfall 1, 2 and Tactics',
          reason: 'the comma stays inside one cell');
      expect(_cells(rows[1]), hasLength(8));
    });

    test('a double quote is doubled, not dropped', () {
      final rows = _rows(_doc([
        _approved(Detection.fromSource(
          rawTitle: 'Blaze',
          origin: DetectionOrigin.filename,
          sourceEntry: 'Blaze "Dim Reaches" build',
        )),
      ]));

      expect(rows[1], contains('"Blaze ""Dim Reaches"" build"'));
      expect(_cells(rows[1])[5], 'Blaze "Dim Reaches" build');
    });

    test('a Windows path passes through unquoted and unescaped', () {
      // Backslash is not an escape character in CSV (RFC 4180), so a path
      // needs no quoting and must not gain any: a reader that unescaped it
      // would turn `\Games\` into a tab.
      const path = r'C:\Games\GOG Galaxy\Marlows Gate 3\goggame-1100000008.info';
      final rows = _rows(_doc([
        _approved(Detection.fromSource(
          rawTitle: 'Marlows Gate 3',
          origin: DetectionOrigin.metadata,
          sourceEntry: path,
          sourceId: 'gog:1100000008',
        )),
      ]));

      expect(rows[1], endsWith('$path,metadata,gog:1100000008'));
      expect(_cells(rows[1])[5], path);
    });

    test('a comma in a path is quoted with the backslashes intact', () {
      const path = r'C:\Games\Pip and Rex, Chapter 1\setup.exe';
      final rows = _rows(_doc([
        _approved(Detection.fromSource(
          rawTitle: 'Pip and Rex',
          origin: DetectionOrigin.filename,
          sourceEntry: path,
        )),
      ]));

      expect(_cells(rows[1])[5], path);
      expect(_cells(rows[1]), hasLength(8));
    });
  });

  test('the exporter still refuses a titleless row and keeps its extension',
      () {
    final blank = _approved(Detection.fromSource(
      rawTitle: '   ',
      origin: DetectionOrigin.filename,
      sourceEntry: 'setup_nothing.exe',
    ));

    expect(CsvExporter().canExport(blank), isFalse);
    expect(_rows(_doc([blank])), [_baseHeader],
        reason: 'a row that is not written cannot trigger the columns');
  });
}

/// Splits one CSV record the way a reader does, honouring quotes.
///
/// Hand-rolled rather than pulled in as a dependency: `shelfscan_core` is
/// kept to `http` alone (ARCHITECTURE.md), and the tests share its pubspec.
List<String> _cells(String row) {
  final cells = <String>[];
  final cell = StringBuffer();
  var quoted = false;
  for (var i = 0; i < row.length; i++) {
    final ch = row[i];
    if (quoted) {
      if (ch != '"') {
        cell.write(ch);
      } else if (i + 1 < row.length && row[i + 1] == '"') {
        cell.write('"');
        i++;
      } else {
        quoted = false;
      }
    } else if (ch == '"') {
      quoted = true;
    } else if (ch == ',') {
      cells.add(cell.toString());
      cell.clear();
    } else {
      cell.write(ch);
    }
  }
  cells.add(cell.toString());
  return cells;
}
