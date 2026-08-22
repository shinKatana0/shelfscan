/// Which class every decline reason is, one row per constant (T-0222).
///
/// The defect: a scan's documented exclusions reached the scan screen painted
/// in `colorScheme.error` under one heading, and the owner read them as
/// errors. Nothing had failed -- every line was a filter `GogLibrarySource`
/// documents, reporting itself.
///
/// This file is the classification itself, executable. Every reason constant
/// in every source appears below exactly once, so a new one has to be added
/// here to pass `the set below is every reason each source can give`, and
/// adding it there is the moment somebody decides its class.
///
/// The rule the rows are assigned by: **could the entry have been a game the
/// user wanted?** A row whose shape is not the shape its schema promises could
/// have been -- it is a failure, and the reader or the schema is what changes.
/// A row read and understood and left out on purpose could not have been -- it
/// is an exclusion, and nothing is wrong.
library;

import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

/// One decline the source under test can produce.
typedef Row = ({String label, SourceEntry entry, String reason, Severity class_});

void main() {
  group('GogLibrarySource', () {
    final rows = <Row>[
      (
        label: 'content the shell never filled in',
        entry: const SourceEntry(name: 'gog_1'),
        reason: GogLibrarySource.notJson,
        class_: Severity.failure,
      ),
      (
        label: 'a row that does not parse',
        entry: const SourceEntry(name: 'gog_1', content: '{'),
        reason: GogLibrarySource.notJson,
        class_: Severity.failure,
      ),
      (
        label: 'a row that is not an object',
        entry: const SourceEntry(name: 'gog_1', content: '[]'),
        reason: GogLibrarySource.notAnObject,
        class_: Severity.failure,
      ),
      (
        label: 'a row with no release key',
        entry: const SourceEntry(name: 'gog_1', content: '{"title":"Vex"}'),
        reason: GogLibrarySource.noReleaseKey,
        class_: Severity.failure,
      ),
      (
        label: 'a row with no title',
        entry: const SourceEntry(name: 'gog_1', content: '{"releaseKey":"gog_1"}'),
        reason: GogLibrarySource.noTitle,
        class_: Severity.failure,
      ),
      (
        label: 'a connected store\'s release',
        entry: const SourceEntry(
            name: 'steam_1', content: '{"releaseKey":"steam_1","title":"Vex"}'),
        reason: GogLibrarySource.notGogProduct,
        class_: Severity.exclusion,
      ),
      (
        // The biggest single line on the panel.
        label: 'a DLC',
        entry: const SourceEntry(
            name: 'gog_1',
            content: '{"releaseKey":"gog_1","title":"Vex DLC","isDlc":1}'),
        reason: GogLibrarySource.dlcNotAGame,
        class_: Severity.exclusion,
      ),
      (
        label: 'a release Galaxy itself hides',
        entry: const SourceEntry(
            name: 'gog_1',
            content: '{"releaseKey":"gog_1","title":"Vex",'
                '"isVisibleInLibrary":0}'),
        reason: GogLibrarySource.hiddenInLibrary,
        class_: Severity.exclusion,
      ),
    ];

    _classifies(const GogLibrarySource(), rows, {
      GogLibrarySource.notJson,
      GogLibrarySource.notAnObject,
      GogLibrarySource.noReleaseKey,
      GogLibrarySource.noTitle,
      GogLibrarySource.notGogProduct,
      GogLibrarySource.dlcNotAGame,
      GogLibrarySource.hiddenInLibrary,
    });
  });

  group('GogMetadataSource', () {
    final rows = <Row>[
      (
        // The hand-over to FilenameSource, and the source's own doc comment
        // already calls it "not a failure".
        label: 'an entry with no manifest beside it',
        entry: const SourceEntry(name: 'setup_ico.exe', content: '{}'),
        reason: GogMetadataSource.noMetadata,
        class_: Severity.exclusion,
      ),
      (
        label: 'a manifest that does not parse',
        entry: const SourceEntry(name: 'goggame-1.info', content: '{'),
        reason: GogMetadataSource.notJson,
        class_: Severity.failure,
      ),
      (
        label: 'a manifest that is not an object',
        entry: const SourceEntry(name: 'goggame-1.info', content: '[]'),
        reason: GogMetadataSource.notAnObject,
        class_: Severity.failure,
      ),
      (
        label: 'a manifest with no name',
        entry: const SourceEntry(
            name: 'goggame-1.info', content: '{"gameId":"1"}'),
        reason: GogMetadataSource.noName,
        class_: Severity.failure,
      ),
      (
        label: 'a manifest with no game id',
        entry: const SourceEntry(
            name: 'goggame-1.info', content: '{"name":"Vex"}'),
        reason: GogMetadataSource.noGameId,
        class_: Severity.failure,
      ),
      (
        label: 'a DLC manifest',
        entry: const SourceEntry(
            name: 'goggame-2.info',
            content: '{"name":"Vex DLC","gameId":"2","rootGameId":"1"}'),
        reason: GogMetadataSource.dlcNotAGame,
        class_: Severity.exclusion,
      ),
    ];

    _classifies(const GogMetadataSource(), rows, {
      GogMetadataSource.noMetadata,
      GogMetadataSource.notJson,
      GogMetadataSource.notAnObject,
      GogMetadataSource.noName,
      GogMetadataSource.noGameId,
      GogMetadataSource.dlcNotAGame,
    });
  });

  group('FilenameSource', () {
    // All five are exclusions, and the source's shape is the argument: it is
    // handed a name and nothing else, so it has no promised structure to be
    // disappointed by. Every one of these is a name that was read and held no
    // game this collection wants.
    final rows = <Row>[
      (
        label: 'a file that is not a game file',
        entry: const SourceEntry(name: 'notes.txt'),
        reason: DeclineReason.notAGameFile,
        class_: Severity.exclusion,
      ),
      (
        label: 'a name carrying two contradicting consoles',
        entry: const SourceEntry(name: 'Sample Game NSW.wbfs'),
        reason: DeclineReason.notAPcInstaller,
        class_: Severity.exclusion,
      ),
      (
        label: 'an installer support file',
        entry: const SourceEntry(name: 'unins000.exe'),
        reason: DeclineReason.supportFile,
        class_: Severity.exclusion,
      ),
      (
        label: 'a name that titles nothing',
        entry: const SourceEntry(name: 'crack.exe'),
        reason: DeclineReason.noTitle,
        class_: Severity.exclusion,
      ),
      (
        // The fourth line on a real scan, and the one that did not come
        // from Galaxy.
        label: 'the mark Windows appends to a duplicate',
        entry: const SourceEntry(name: 'Новая папка (2)'),
        reason: DeclineReason.numberedCopy,
        class_: Severity.exclusion,
      ),
    ];

    _classifies(const FilenameSource(), rows, {
      DeclineReason.notAGameFile,
      DeclineReason.notAPcInstaller,
      DeclineReason.supportFile,
      DeclineReason.noTitle,
      DeclineReason.numberedCopy,
    });
  });

  group('the warning the orchestrator writes', () {
    test('a scan of nothing but silences reports no failure at all', () async {
      // A real scan, in shape: every line an exclusion, so the panel has
      // nothing to put under its failure heading.
      final warnings = <ScanWarning>[];
      final doc = await _scan([
        _library('gog_1', '{"releaseKey":"gog_1","title":"Vex","isDlc":1}'),
        _library('gog_2', '{"releaseKey":"gog_2","title":"Vex 2","isDlc":1}'),
        _library('steam_9', '{"releaseKey":"steam_9","title":"Dusk-Rail"}'),
      ], warnings);

      expect(warnings, isNotEmpty);
      expect([for (final w in warnings) w.severity],
          everyElement(Severity.exclusion));
      // Nothing is hidden by being reclassified: every entry is still on the
      // document and still counted in a line.
      expect(doc.declinedEntries, hasLength(3));
      expect(warnings.map((w) => w.message).join(' '), contains('Skipped'));
    });

    test('one malformed row among the silences is still a failure', () async {
      final warnings = <ScanWarning>[];
      await _scan([
        _library('gog_1', '{"releaseKey":"gog_1","title":"Vex","isDlc":1}'),
        _library('gog_2', '{'),
      ], warnings);

      expect(
        [for (final w in warnings) (w.severity, w.message.contains('not JSON'))],
        containsAll([(Severity.failure, true), (Severity.exclusion, false)]),
      );
    });

    test('a group takes the worst class among its members, not the first',
        () async {
      // Two entries, one reason string, two classes -- the fold the grouping
      // needs so a failure cannot be quietened by the silences beside it.
      final warnings = <ScanWarning>[];
      await _scan([
        _library('a', ''),
        _library('b', ''),
      ], warnings, source: _OneReasonTwoClasses());

      expect(warnings.single.severity, Severity.failure);
      expect(warnings.single.message, contains('2 entries'));
    });
  });

  group('the review document', () {
    test('carries the class through JSON', () {
      final doc = ReviewDocument(
        version: 1,
        created: '2026-08-17T00:00:00.000Z',
        photos: const [],
        games: const [],
        declinedEntries: const [
          DeclinedEntry(
              name: 'a', reason: 'left out', severity: Severity.exclusion),
          DeclinedEntry(
              name: 'b', reason: 'broke', severity: Severity.failure),
        ],
      );
      final back = ReviewDocument.fromJson(doc.toJson());

      expect([for (final e in back.declinedEntries) e.severity],
          [Severity.exclusion, Severity.failure]);
    });

    test('a document written before the field existed reads as a failure', () {
      // The loud side is the safe default: an unstated class is not a claim
      // that nothing went wrong.
      final entry = DeclinedEntry.fromJson(
          const {'name': 'a', 'reason': 'no title in the name'});

      expect(entry.severity, Severity.failure);
    });
  });
}

/// The two tests every source gets: each row is classed as the table says, and
/// the table is the whole set of reasons the source can give.
void _classifies(DetectionSource source, List<Row> rows, Set<String> reasons) {
  for (final row in rows) {
    test('${row.label} is ${row.class_.name}', () {
      final declined = source.read(row.entry).declined;

      expect(declined, hasLength(1), reason: row.label);
      expect(declined.single.reason, row.reason);
      expect(declined.single.severity, row.class_);
    });
  }

  test('the set below is every reason each source can give', () {
    // A sixth constant added without a row above fails here, which is where
    // somebody decides its class.
    expect({for (final row in rows) row.reason}, reasons);
  });
}

SourceEntry _library(String name, String content) =>
    SourceEntry(name: name, content: content);

Future<ReviewDocument> _scan(
  List<SourceEntry> entries,
  List<ScanWarning> warnings, {
  DetectionSource source = const GogLibrarySource(),
}) =>
    Orchestrator.resolveOnly(resolverWorker: SkipResolver()).runScan(
      const [],
      sources: [SourceRun(source, entries)],
      progress: ScanProgress(onWarning: warnings.add),
    );

/// One reason string covering both classes -- the shape `_warnDeclined`'s fold
/// exists for. No real source does this today; the fold is not written on that
/// holding.
class _OneReasonTwoClasses implements DetectionSource {
  var _next = Severity.exclusion;

  @override
  SourceReading read(SourceEntry entry) {
    final severity = _next;
    _next = Severity.failure;
    return SourceReading(declined: [
      DeclinedEntry(name: entry.name, reason: 'one reason', severity: severity)
    ]);
  }
}
