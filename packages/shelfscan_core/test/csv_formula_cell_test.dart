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

/// The `README.md` section the three assertions below are about. Named once,
/// so the section a failure quotes and the heading it asserts on are provably
/// the same one.
const _readmeSection = 'Opening the CSV in a spreadsheet';

/// Which half to suspect first when one of the three fails. The group above
/// pins the behaviour this section describes, so its colour is the thing that
/// separates a reworded page from a changed decision (T-0328).
const _decisionOrDocument =
    'If the group "the four characters are written through verbatim" above is '
    'green, the exporter still writes all four leaders through untouched and '
    'it is the page that moved: restore the sentence, or move this needle '
    'with it. If that group is red too, the T-0185 decision itself has '
    'changed, and this file and the README section then have to move together '
    '-- which is what this file exists to force.';

/// Fails unless the whitespace-flattened [readme] still carries [needle].
///
/// What these three assert is that a **published document** still says
/// something, and a red has two causes that want opposite repairs: the page
/// was reworded, or the behaviour it describes moved and the page followed.
/// So the message forks twice -- on whether the section survives at all, and
/// on [thenSuspect] (T-0328).
///
/// `fail` rather than `expect`, and the section rather than the document: the
/// flatten leaves README on one enormous line, which a matcher prints whole
/// as its `Actual`, from the top of the file and nowhere near this section
/// (T-0321, T-0325).
void _readmeStillSays(String readme, String needle,
    {required String thenSuspect}) {
  if (readme.contains(needle)) return;
  final at = readme.indexOf(_readmeSection);
  if (at < 0) {
    final held = needle == _readmeSection
        ? ''
        : ' The phrase looked for, "$needle", lived inside it.';
    fail('README.md: a scan of the whitespace-flattened document found no '
        'section "$_readmeSection" at all, so it is gone or renamed.$held '
        'Suspect the document rather than the exporter: spreadsheetNote in '
        'bin/shelfscan.dart names that heading to the user verbatim, so an '
        'export now points at a section README does not have.');
  }
  // To the next heading, and bounded anyway: a README that lost its next
  // heading would otherwise hand back the whole document this exists to stop
  // quoting.
  final rest = readme.substring(at);
  final end = RegExp(r' #+ ').firstMatch(rest)?.start ?? rest.length;
  fail('README.md: a scan of the whitespace-flattened document found the '
      'section "$_readmeSection" but not "$needle" anywhere in the document. '
      'The section is still there and no longer says this. $thenSuspect '
      'Whichever it is, the scan folds every run of whitespace to one space, '
      'so the phrase may be wrapped across two lines in the file and a grep '
      'of README.md as it stands can miss text that is still there. What the '
      'section says now:\n  ${rest.substring(0, end > 4000 ? 4000 : end)}');
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

    test('media_type and origin cannot carry one', () {
      // They bypass `_cell` entirely (T-0182) and are two enums, so the
      // decision above never has to cover them. Walked rather than asserted,
      // so a value added later fails here. `external_id` left this pair when
      // it became a namespaced string (decision 0016): it goes through `_cell`
      // now, and a catalogue name cannot begin with a formula leader anyway.
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
      _readmeStillSays(readme, _readmeSection,
          thenSuspect: _decisionOrDocument);
      _readmeStillSays(
          readme,
          'evaluate any cell whose text begins with `=`, `+`, `-` '
              'or `@` as a formula',
          thenSuspect: _decisionOrDocument);
    });

    test('and says the names are written through unchanged', () {
      _readmeStillSays(readme, 'shelfscan writes your names through unchanged',
          thenSuspect: _decisionOrDocument);
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
      'title,platform,media_type,external_id,source_photo\r\n'
      'DUSKHOLLOWE,PS4,disc,,shelf_a.jpg\r\n',
    );
  });
}
