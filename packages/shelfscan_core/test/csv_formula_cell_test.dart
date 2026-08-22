/// A CSV cell beginning `=`, `+`, `-` or `@` is a formula to a spreadsheet
/// (T-0185), and this file pins the decision not to rewrite it.
///
/// T-0182 settled the quoting class against RFC 4180. This is the boundary of
/// what quoting can do: quoting settles where a cell ENDS, not what the reader
/// does with what is inside it, so no widening of that class reaches this.
///
/// The decision is "do nothing in the exporter, tell the user in README"
/// (T-0185). Both halves are pinned here, because a decision
/// with nothing watching it is the state this file exists to leave:
///
///   1. the four characters are written through verbatim -- unprefixed,
///      unstripped and (absent an RFC 4180 character) unquoted, in every cell
///      that goes through `_cell`;
///   2. the reachable set, measured rather than assumed -- and the three
///      columns that bypass `_cell` cannot reach it at all;
///   3. README carries the warning that stands in for the code change.
///
/// A future task that adds a prefix fails group 1 and must move this file and
/// the README section together, which is the point.
library;

import 'dart:convert';
import 'dart:io';

import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

const _formulaLeaders = ['=', '+', '-', '@'];

ReviewDocument _doc(List<ResolvedGame> games) => ReviewDocument(
      version: 1,
      created: '2026-08-13T00:00:00Z',
      photos: const ['shelf_a.jpg'],
      games: games,
    );

ResolvedGame _approved(Detection detection, {Candidate? best}) => ResolvedGame(
      detection: detection,
      best: best,
      status: ReviewStatus.approved,
    );

List<String> _records(String csv) => const LineSplitter()
    .convert(csv)
    .where((l) => l.isNotEmpty)
    .toList();

Directory _repoRoot() {
  for (var dir = Directory.current.absolute;; dir = dir.parent) {
    if (File('${dir.path}/.env.example').existsSync()) return dir;
    if (dir.path == dir.parent.path) {
      fail('no .env.example at or above ${Directory.current.path}');
    }
  }
}

void main() {
  group('the four characters are written through verbatim', () {
    for (final lead in _formulaLeaders) {
      test('$lead in source_entry, the column a real disk name reaches', () {
        final csv = CsvExporter().export(_doc([
          _approved(Detection.fromSource(
            rawTitle: 'Tactics',
            origin: DetectionOrigin.filename,
            sourceEntry: '${lead}Tactics',
          )),
        ]));
        expect(_records(csv)[1], 'Tactics,,unknown,,,${lead}Tactics,filename,');
      });

      test('$lead in title, and it is not quoted for being one', () {
        final csv = CsvExporter().export(_doc([
          _approved(Detection(
            rawTitle: '${lead}Anima',
            mediaType: MediaType.cartridge,
            confidence: 0.9,
            sourcePhoto: 'shelf_a.jpg',
          )),
        ]));
        expect(_records(csv)[1], '${lead}Anima,,cartridge,,shelf_a.jpg');
      });
    }

    test('the other three _cell columns behave the same way', () {
      final csv = CsvExporter().export(_doc([
        _approved(Detection(
          rawTitle: 'Anima',
          platformHint: '=PC',
          mediaType: MediaType.cartridge,
          confidence: 0.9,
          sourcePhoto: '-shelf.jpg',
          sourceEntry: '+entry',
          sourceId: '@sid',
          origin: DetectionOrigin.metadata,
        )),
      ]));
      expect(_records(csv)[1],
          'Anima,=PC,cartridge,,-shelf.jpg,+entry,metadata,@sid');
    });

    test('an RFC 4180 character still quotes, and the leader stays inside', () {
      final csv = CsvExporter().export(_doc([
        _approved(Detection(
          rawTitle: '=Ashfall 1, 2 and Tactics',
          mediaType: MediaType.disc,
          confidence: 0.9,
          sourcePhoto: 'shelf_a.jpg',
        )),
      ]));
      expect(_records(csv)[1],
          '"=Ashfall 1, 2 and Tactics",,disc,,shelf_a.jpg');
    });
  });

  group('the reachable set', () {
    // Measured, not assumed: the installer-name parser treats a leading `-`
    // and `+` as separators and drops them, but passes `=` and `@` into the
    // title. So the ordinary case -- a folder named `-Tactics` -- reaches
    // `source_entry` only, and `title` is reachable from a filename source by
    // two of the four characters rather than all of them.
    const reachesTitle = {'=': true, '@': true, '-': false, '+': false};

    for (final lead in _formulaLeaders) {
      test('a folder named ${lead}Tactics: title ${reachesTitle[lead]!}', () {
        final reading = const FilenameSource()
            .read(SourceEntry(name: '${lead}Tactics', container: 'C:/Games'));
        expect(reading.items, hasLength(1));
        final d = reading.items.single;
        expect(d.sourceEntry, '${lead}Tactics',
            reason: 'the name off disk is carried unedited');
        expect(d.rawTitle.startsWith(lead), reachesTitle[lead]!);
      });
    }

    test('media_type, igdb_id and origin cannot carry one', () {
      // They bypass `_cell` entirely (T-0182) and are two enums and an int, so
      // the decision above never has to cover them. Walked rather than
      // asserted, so a value added later fails here.
      for (final name in [
        ...MediaType.values.map((v) => v.name),
        ...DetectionOrigin.values.map((v) => v.name),
      ]) {
        expect(_formulaLeaders.any(name.startsWith), isFalse, reason: name);
      }
    });
  });

  group('the warning that stands in for the code change', () {
    late String readme;

    setUpAll(() {
      // Whitespace-collapsed: the sentence below wraps in the file, and a
      // reflow of the paragraph must not fail this.
      readme = File('${_repoRoot().path}/README.md')
          .readAsStringSync()
          .replaceAll(RegExp(r'\s+'), ' ');
    });

    test('README tells the reader what a spreadsheet does with the cell', () {
      expect(readme, contains('Opening the CSV in a spreadsheet'));
      expect(
          readme,
          contains('evaluate any cell whose text begins with `=`, `+`, `-` '
              'or `@` as a formula'));
    });

    test('and says the names are written through unchanged', () {
      expect(readme, contains('shelfscan writes your names through unchanged'));
    });
  });

  test('a photograph-only export is byte-identical', () {
    // The guarantee T-0053, T-0068, T-0155 and T-0166 each paid for
    // separately, and the reason nothing above rewrites a cell.
    expect(
      CsvExporter().export(_doc([
        _approved(Detection(
          rawTitle: 'DUSKHOLLOWE',
          platformHint: 'PS4',
          mediaType: MediaType.disc,
          confidence: 0.9,
          sourcePhoto: 'shelf_a.jpg',
        )),
      ])),
      'title,platform,media_type,igdb_id,source_photo\r\n'
      'DUSKHOLLOWE,PS4,disc,,shelf_a.jpg\r\n',
    );
  });
}
