/// A cell holding a bare carriage return (T-0182).
///
/// `CsvExporter` terminates every record `\r\n`, so before this task a lone
/// `\r` inside a cell ended the record for any reader that scans for one:
/// one row became two and every column after the break shifted. RFC 4180
/// requires a field containing CR, LF or a double quote to be quoted.
///
/// Reachable rather than theoretical: `source_entry` is a real file or
/// directory name (T-0155/T-0166), POSIX filesystems allow CR in one, and
/// `shelfscan_core` runs on Android.
///
/// The output is parsed back as RECORDS here, not compared as a string:
/// asserting on the emitted text alone would pass for a reader that does not
/// exist. `_records` is the same quote-aware splitter `csv_provenance_test`
/// uses, extended to find the record boundaries itself instead of taking
/// them from `LineSplitter` -- which is not quote-aware and would split a
/// correctly quoted cell too.
library;

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

List<List<String>> _export(List<ResolvedGame> games) =>
    _records(CsvExporter().export(_doc(games)));

void main() {
  group('the parser can see the defect', () {
    // Without this the tests below would pass against a reader that ignores
    // CR, which is the failure mode the brief names.
    test('an unquoted CR splits a record in two', () {
      expect(_records('a,b\rc,d\r\n'), [
        ['a', 'b'],
        ['c', 'd'],
      ]);
    });

    test('a quoted CR does not', () {
      expect(_records('a,"b\rc",d\r\n'), [
        ['a', 'b\rc', 'd'],
      ]);
    });

    test('a quoted CRLF does not', () {
      expect(_records('a,"b\r\nc"\r\n'), [
        ['a', 'b\r\nc'],
      ]);
    });
  });

  group('a bare carriage return stays inside its cell', () {
    test('in source_entry, one row and not two', () {
      const entry = 'Ashfall\r2 and Tactics';
      final records = _export([
        _approved(Detection.fromSource(
          rawTitle: 'Ashfall',
          origin: DetectionOrigin.filename,
          sourceEntry: entry,
        )),
      ]);

      expect(records, hasLength(2), reason: 'header and exactly one row');
      expect(records[0].join(','), _fullHeader);
      expect(records[1], hasLength(8),
          reason: 'no column shifted past the break');
      expect(records[1][5], entry, reason: 'the CR survives the round trip');
      expect(records[1][6], 'filename',
          reason: 'the cells after the CR are still their own cells');
    });

    test('in raw_title, on a five-column export', () {
      // A hand-edited review.json is the reachable path for this one: the
      // title is written before `source_entry` exists, so the defect is not
      // confined to the provenance columns.
      const title = 'Vex\rVessel of the Monolith';
      final records = _export([
        _approved(Detection(
          rawTitle: title,
          mediaType: MediaType.disc,
          confidence: 0.9,
          sourcePhoto: 'shelf_a.jpg',
        )),
      ]);

      expect(records, hasLength(2));
      expect(records[0].join(','), _baseHeader);
      expect(records[1], hasLength(5));
      expect(records[1][0], title);
      expect(records[1][4], 'shelf_a.jpg');
    });

    test('in source_photo and in a matched title', () {
      final records = _export([
        _approved(
          Detection(
            rawTitle: 'DUSKHOLLOWE',
            mediaType: MediaType.disc,
            confidence: 0.9,
            sourcePhoto: 'shelf\ra.jpg',
          ),
          best: Candidate(
            igdbId: 7,
            title: 'Dusk\rhollow',
            platformId: 48,
            platformName: 'PlayStation\r4',
            score: 1.0,
          ),
        ),
      ]);

      expect(records, hasLength(2));
      expect(records[1], hasLength(5));
      expect(records[1][0], 'Dusk\rhollow');
      expect(records[1][1], 'PlayStation\r4');
      expect(records[1][4], 'shelf\ra.jpg');
    });

    test('a CR beside a comma and a quote in one cell', () {
      const entry = 'Pip and Rex, "Chapter 1"\r\r\nbuild';
      final records = _export([
        _approved(Detection.fromSource(
          rawTitle: 'Pip and Rex',
          origin: DetectionOrigin.filename,
          sourceEntry: entry,
          sourceId: 'gog:1100000014',
        )),
      ]);

      expect(records, hasLength(2));
      expect(records[1], hasLength(8));
      expect(records[1][5], entry);
      expect(records[1][7], 'gog:1100000014');
    });

    test('a lone LF is quoted too, and always was', () {
      final records = _export([
        _approved(Detection.fromSource(
          rawTitle: 'Aeon Ex',
          origin: DetectionOrigin.filename,
          sourceEntry: 'Aeon\nEx GOTY',
        )),
      ]);

      expect(records, hasLength(2));
      expect(records[1][5], 'Aeon\nEx GOTY');
    });
  });

  group('what T-0166 pinned still behaves', () {
    test('a comma is quoted and a doubled quote round-trips', () {
      final records = _export([
        _approved(Detection.fromSource(
          rawTitle: 'Ashfall',
          origin: DetectionOrigin.filename,
          sourceEntry: 'Ashfall 1, 2 and Tactics',
        )),
        _approved(Detection.fromSource(
          rawTitle: 'Blaze',
          origin: DetectionOrigin.filename,
          sourceEntry: 'Blaze "Dim Reaches" build',
        )),
      ]);

      expect(records, hasLength(3));
      expect(records[1][5], 'Ashfall 1, 2 and Tactics');
      expect(records[2][5], 'Blaze "Dim Reaches" build');
    });

    test('a Windows path gains neither quotes nor escapes', () {
      const path = r'C:\Games\GOG Galaxy\Marlows Gate 3\goggame-1100000008.info';
      final text = CsvExporter().export(_doc([
        _approved(Detection.fromSource(
          rawTitle: 'Marlows Gate 3',
          origin: DetectionOrigin.metadata,
          sourceEntry: path,
          sourceId: 'gog:1100000008',
        )),
      ]));

      expect(text, contains(',$path,metadata,'),
          reason: 'backslash is not an RFC 4180 escape, and CR did not widen '
              'the class to it');
      expect(_records(text)[1][5], path);
    });

    test('a tab and a semicolon are not quoted', () {
      // The class is the three characters RFC 4180 names plus this writer's
      // separator -- not "anything a spreadsheet might dislike". A tab is a
      // legal unquoted field character and quoting it would change the bytes
      // of an export that has one.
      final text = CsvExporter().export(_doc([
        _approved(Detection.fromSource(
          rawTitle: 'Heroes',
          origin: DetectionOrigin.filename,
          sourceEntry: 'Heroes\tIII; Complete',
        )),
      ]));

      expect(text, contains(',Heroes\tIII; Complete,filename,'));
      expect(_records(text)[1][5], 'Heroes\tIII; Complete');
    });
  });

  group('a photograph-only export is byte-identical', () {
    test('the exact bytes, header and row', () {
      final text = CsvExporter().export(_doc([
        _approved(
          Detection(
            rawTitle: 'DUSKHOLLOWE',
            platformHint: 'PS4',
            mediaType: MediaType.disc,
            confidence: 0.9,
            sourcePhoto: 'shelf_a.jpg',
          ),
          best: Candidate(
            igdbId: 7,
            title: 'Duskhollow',
            platformId: 48,
            platformName: 'PlayStation 4',
            score: 1.0,
          ),
        ),
      ]));

      expect(
          text,
          '$_baseHeader\r\n'
          'Duskhollow,PlayStation 4,disc,7,shelf_a.jpg\r\n');
    });

    test('the unquoted columns cannot carry the class', () {
      // `media_type`, `igdb_id` and `origin` are written without going
      // through the quoting at all. That is safe only because they are enum
      // names and an int; if a future value stopped being one, this fails
      // here rather than in a spreadsheet.
      final unquotable = RegExp(r'[",\r\n]');
      for (final name in [
        ...MediaType.values.map((e) => e.name),
        ...DetectionOrigin.values.map((e) => e.name),
      ]) {
        expect(unquotable.hasMatch(name), isFalse, reason: name);
      }
    });
  });
}

/// Splits CSV text into records the way a reader does, honouring quotes.
///
/// Hand-rolled rather than pulled in as a dependency: `shelfscan_core` is
/// kept to `http` alone (ARCHITECTURE.md), and the tests share its pubspec.
///
/// Outside quotes, CRLF, a lone CR and a lone LF each end the record -- that
/// is the tolerant reading a spreadsheet applies, and it is what makes an
/// unquoted CR visible here as a split record rather than as a stray
/// character inside a cell.
List<List<String>> _records(String text) {
  final records = <List<String>>[];
  var cells = <String>[];
  final cell = StringBuffer();
  var quoted = false;

  void endRecord() {
    cells.add(cell.toString());
    cell.clear();
    records.add(cells);
    cells = <String>[];
  }

  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (quoted) {
      if (ch != '"') {
        cell.write(ch);
      } else if (i + 1 < text.length && text[i + 1] == '"') {
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
    } else if (ch == '\r' || ch == '\n') {
      if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      endRecord();
    } else {
      cell.write(ch);
    }
  }
  if (cell.isNotEmpty || cells.isNotEmpty) endRecord();
  return records;
}
