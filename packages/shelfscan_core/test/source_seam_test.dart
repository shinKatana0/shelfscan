/// A run that begins from something that is not a photograph (T-0155).
///
/// The seam six tasks sequence behind: T-0157 reads GoG's `goggame-*.info`,
/// T-0158 parses installer names, T-0160 and T-0161 point the two shells at a
/// folder. None of them exists yet, so everything below drives a fake source
/// -- no filesystem, no dependency, no shell, and `SkipResolver` refusing
/// network I/O on top. That is not a limitation of the test: `shelfscan_core`
/// may not open a file at all, so a source that needs one to be tested would
/// already be in the wrong package.
///
/// What is pinned here is the shape of the seam rather than any source's
/// parsing: that a run can start with no vision worker in existence, that a
/// mixed run puts photographed and installed copies of one game through one
/// dedupe, that an entry nobody could use is named rather than dropped, and
/// that a photo-only run comes out exactly as it did before any of this.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

/// A source with the filesystem replaced by the caller's own values.
///
/// Two readings in one class because that is the pair the design question is
/// about: [SourceEntry.content] present is metadata somebody wrote (T-0157's
/// case), absent is a title inferred from the name (T-0158's case).
class _FakeSource implements DetectionSource {
  @override
  SourceReading read(SourceEntry entry) {
    final content = entry.content;
    if (content != null) {
      final name = (jsonDecode(content) as Map<String, dynamic>)['name'];
      return SourceReading(items: [
        Detection.fromSource(
          rawTitle: name as String,
          origin: DetectionOrigin.metadata,
          sourceEntry: entry.name,
        ),
      ]);
    }
    final guess = _guess(entry.name) ?? _guess(entry.container);
    if (guess == null) {
      return SourceReading(declined: [
        DeclinedEntry(name: entry.name, reason: 'no title in the name'),
      ]);
    }
    return SourceReading(items: [
      Detection.fromSource(
        rawTitle: guess,
        origin: DetectionOrigin.filename,
        sourceEntry: entry.name,
      ),
    ]);
  }

  static String? _guess(String? name) {
    if (name == null) return null;
    final stripped = name
        .replaceFirst('setup', '')
        .replaceFirst('.exe', '')
        .replaceAll('_', ' ')
        .trim();
    return stripped.isEmpty ? null : stripped.toUpperCase();
  }
}

class _ThrowingSource implements DetectionSource {
  @override
  SourceReading read(SourceEntry entry) =>
      throw StateError('unreadable shape');
}

SourceEntry _installed(String name, String title) =>
    SourceEntry(name: name, content: jsonEncode({'name': title}));

SourceEntry _installer(String name, {String? container}) =>
    SourceEntry(name: name, container: container);

Detection _read(String title, {String photo = 'shelf.jpg', String? hint}) =>
    Detection(
      rawTitle: title,
      mediaType: MediaType.disc,
      confidence: 1.0,
      sourcePhoto: photo,
      platformHint: hint,
    );

PhotoInput _photo([String name = 'shelf.jpg']) =>
    PhotoInput(name: name, bytes: Uint8List.fromList([1]));

class _OnePhoto implements VisionProvider {
  _OnePhoto(this.items);

  final List<Detection> items;

  @override
  Future<PhotoAnalysis> analyze(PhotoInput photo) async =>
      PhotoAnalysis(items: items);
}

/// A source run with no vision worker in the object at all.
Future<ReviewDocument> _sourceScan(
  List<SourceEntry> entries, {
  DetectionSource? source,
  ScanProgress? progress,
}) =>
    Orchestrator.resolveOnly(resolverWorker: SkipResolver()).runScan(
      const [],
      sources: [SourceRun(source ?? _FakeSource(), entries)],
      progress: progress,
    );

/// One photo and one folder in a single run, which is what a real run has.
Future<ReviewDocument> _mixedScan(
  List<Detection> reads,
  List<SourceEntry> entries,
) =>
    Orchestrator(
      visionWorker: VisionWorker(_OnePhoto(reads)),
      resolverWorker: SkipResolver(),
    ).runScan([_photo()], sources: [SourceRun(_FakeSource(), entries)]);

List<String> _titles(ReviewDocument doc) =>
    [for (final game in doc.games) game.detection.rawTitle];

ResolvedGame _exportable(Detection detection) => ResolvedGame(
      detection: detection,
      best: Candidate(
        igdbId: 1100000054,
        title: 'The Legend of Vireo: Echo of the Hollow',
        platformId: 130,
        platformName: 'Nintendo Switch',
        score: 1.0,
      ),
      status: ReviewStatus.approved,
    );

ReviewDocument _document(List<ResolvedGame> games) => ReviewDocument(
      version: 1,
      created: '2026-08-16T00:00:00.000Z',
      photos: const [],
      games: games,
    );

String _description(ReviewDocument doc) =>
    (jsonDecode(TonkatsuExporter().export(doc)) as Map<String, dynamic>)
        ['description'] as String;

void main() {
  group('a run can begin with no photograph in it', () {
    test('detections nobody read off an image reach the review document',
        () async {
      final doc = await _sourceScan([
        _installed('goggame-1100000014.info', 'Marlow\'s Gate 3'),
        _installer('setup_sundrop_hollow.exe'),
      ]);

      expect(_titles(doc), ['Marlow\'s Gate 3', 'SUNDROP HOLLOW']);
      expect(doc.photos, isEmpty);
      expect(doc.failedPhotos, isEmpty);
    });

    test('every row says what it was read from, and claims no photo', () async {
      final doc = await _sourceScan([
        _installed('goggame-1100000014.info', 'Marlow\'s Gate 3'),
        _installer('setup_sundrop_hollow.exe'),
      ]);
      final rows = [for (final game in doc.games) game.detection];

      expect([for (final row in rows) row.origin],
          [DetectionOrigin.metadata, DetectionOrigin.filename]);
      expect([for (final row in rows) row.sourceEntry],
          ['goggame-1100000014.info', 'setup_sundrop_hollow.exe']);
      // T-0052: `source_photo` is a claim dedupe counts and csv publishes.
      expect([for (final row in rows) row.sourcePhoto], ['', '']);
      expect([for (final row in rows) row.isManual], [false, false]);
    });

    test('a title in the parent directory is reachable', () async {
      final doc = await _sourceScan(
          [_installer('setup.exe', container: 'marlows_gate_3')]);

      expect(_titles(doc), ['MARLOWS GATE 3']);
    });

    test('the vision stage is never announced, because there is none',
        () async {
      final stages = <String>[];
      final items = <(String, int, int)>[];
      await _sourceScan(
        [_installer('setup_ico.exe')],
        progress: ScanProgress(
          onStage: stages.add,
          onItem: (stage, done, total) => items.add((stage, done, total)),
        ),
      );

      expect(stages, ['source', 'dedupe', 'resolve']);
      expect(items, contains(('source', 1, 1)));
    });

    test('a photo handed to an orchestrator with no vision worker still throws',
        () {
      expect(
        () => Orchestrator.resolveOnly(resolverWorker: SkipResolver())
            .runScan([_photo()],
                sources: [SourceRun(_FakeSource(), const [])]),
        throwsStateError,
      );
    });
  });

  group('an entry that yields no row is named, not dropped', () {
    test('it lands on the document and in a warning', () async {
      final warnings = <String>[];
      final doc = await _sourceScan(
        [_installer('setup_.exe'), _installed('goggame-1.info', 'Vex')],
        progress: ScanProgress(onWarning: (w) => warnings.add(w.message)),
      );

      expect(_titles(doc), ['Vex']);
      expect([for (final entry in doc.declinedEntries) entry.name],
          ['setup_.exe']);
      expect(doc.declinedEntries.single.reason, 'no title in the name');
      expect(warnings, ['Skipped setup_.exe: no title in the name']);
    });

    test('40 entries with one reason are one warning, not 40', () async {
      final warnings = <String>[];
      final doc = await _sourceScan(
        [for (var i = 0; i < 40; i++) _installer('setup_.exe')],
        progress: ScanProgress(onWarning: (w) => warnings.add(w.message)),
      );

      expect(doc.declinedEntries, hasLength(40));
      expect(warnings, hasLength(1));
      expect(warnings.single, contains('Skipped 40 entries'));
      expect(warnings.single, contains('no title in the name'));
    });

    test('a run whose every entry declines is a document, not an exception',
        () async {
      // T-0072 draws the line at a failed CALL: an entry that was read and
      // held no game is an answer, unlike a photo nobody ever looked at.
      final doc = await _sourceScan([_installer('setup_.exe')]);

      expect(doc.games, isEmpty);
      expect(doc.declinedEntries, hasLength(1));
    });

    test('a source that throws loses its entry and not the run', () async {
      final warnings = <String>[];
      final doc = await _sourceScan(
        [_installer('setup_ico.exe')],
        source: _ThrowingSource(),
        progress: ScanProgress(onWarning: (w) => warnings.add(w.message)),
      );

      expect(doc.games, isEmpty);
      expect(doc.declinedEntries.single.name, 'setup_ico.exe');
      expect(doc.declinedEntries.single.reason, contains('unreadable shape'));
      expect(warnings.single, contains('unreadable shape'));
    });
  });

  group('a mixed run goes through one dedupe', () {
    test('photographed rows come first and keep their photo', () async {
      final doc = await _mixedScan(
        [_read('NOCTURNE 5 GOLD')],
        [_installer('setup_sundrop_hollow.exe')],
      );

      expect(_titles(doc), ['NOCTURNE 5 GOLD', 'SUNDROP HOLLOW']);
      expect(doc.games.first.detection.sourcePhoto, 'shelf.jpg');
      expect(doc.photos, ['shelf.jpg']);
    });

    test('a title the installer wrote wins the merge against a spine read',
        () async {
      final doc = await _mixedScan(
        [_read('SUNDROP HOLLOW')],
        [_installed('goggame-1100000055.info', 'Sundrop Hollow')],
      );

      expect(_titles(doc), ['Sundrop Hollow']);
      expect(doc.games.single.detection.origin, DetectionOrigin.metadata);
    });

    test('a guessed title does NOT win it, however many entries there were',
        () async {
      // The defect this pins: photo yield used to count every photoless row
      // under one empty key, so a folder of installers out-yielded a 4000x3000
      // photo by arithmetic that says nothing about either read.
      final doc = await _mixedScan(
        [_read('SUNDROP HOLLOW')],
        [
          for (var i = 0; i < 40; i++) _installer('setup_sundrop_hollow.exe'),
        ],
      );

      expect(_titles(doc), ['SUNDROP HOLLOW']);
      expect(doc.games.single.detection.origin, DetectionOrigin.vision);
      expect(doc.games.single.detection.sourcePhoto, 'shelf.jpg');
    });

    test('two different present hints stay two rows, as they do for consoles',
        () async {
      // T-0018-02 on a different pair of copies: owning a game on a disc and
      // on disk is owning two of it.
      final doc = await Orchestrator(
        visionWorker: VisionWorker(_OnePhoto([_read('MOOR', hint: 'PS4')])),
        resolverWorker: SkipResolver(),
      ).runScan(
        [_photo()],
        sources: [
          SourceRun(_HintedSource('PC'), [_installer('setup_moor.exe')])
        ],
      );

      expect(_titles(doc), ['MOOR', 'MOOR']);
    });

    test('the whole document survives a write and a read', () async {
      final doc = await _mixedScan(
        [_read('NOCTURNE 5 GOLD')],
        [_installed('goggame-1.info', 'Vex'), _installer('setup_.exe')],
      );
      final reparsed = ReviewDocument.parse(jsonEncode(doc.toJson()));

      expect(_titles(reparsed), _titles(doc));
      expect(reparsed.games.last.detection.sourceEntry, 'goggame-1.info');
      expect(reparsed.games.last.detection.origin, DetectionOrigin.metadata);
      expect(reparsed.declinedEntries.single.name, 'setup_.exe');
      expect(reparsed.toJson(), doc.toJson());
    });
  });

  group('a photo-only run is what it was', () {
    test('neither new key reaches the file', () async {
      final doc = await Orchestrator(
        visionWorker: VisionWorker(_OnePhoto([_read('NOCTURNE 5 GOLD')])),
        resolverWorker: SkipResolver(),
      ).runScan([_photo()]);
      final written = jsonEncode(doc.toJson());

      expect(written, isNot(contains('source_entry')));
      expect(written, isNot(contains('declined_entries')));
    });

    test('the .xcoll still says it came from shelf photos', () {
      final doc = _document([_exportable(_read('NOCTURNE 5 GOLD'))]);

      expect(_description(doc), 'Generated by shelfscan from shelf photos');
    });
  });

  group('the .xcoll description says what was actually read', () {
    test('a source-only export claims no photograph', () {
      final doc = _document([
        _exportable(Detection.fromSource(
          rawTitle: 'Vex',
          origin: DetectionOrigin.metadata,
          sourceEntry: 'goggame-1.info',
        )),
      ]);

      expect(_description(doc),
          'Generated by shelfscan from installed game metadata');
    });

    test('a mixed export names both, in one sentence', () {
      final doc = _document([
        _exportable(_read('NOCTURNE 5 GOLD')),
        _exportable(Detection.fromSource(
          rawTitle: 'Vex',
          origin: DetectionOrigin.metadata,
          sourceEntry: 'goggame-1.info',
        )),
        _exportable(Detection.fromSource(
          rawTitle: 'SUNDROP HOLLOW',
          origin: DetectionOrigin.filename,
          sourceEntry: 'setup_sundrop_hollow.exe',
        )),
      ]);

      expect(
          _description(doc),
          'Generated by shelfscan from shelf photos, installed game metadata '
          'and game file names');
    });

    test('an export with nothing in it claims nothing', () {
      expect(_description(_document(const [])), 'Generated by shelfscan');
    });

    test('csv carries a source row that IGDB never matched', () {
      final doc = _document([
        ResolvedGame(
          detection: Detection.fromSource(
            rawTitle: 'Vex',
            origin: DetectionOrigin.metadata,
            sourceEntry: 'goggame-1.info',
          ),
          status: ReviewStatus.approved,
        ),
      ]);

      expect(CsvExporter().export(doc), contains('Vex'));
      expect(TonkatsuExporter().select(doc), isEmpty);
    });
  });
}

/// A source that answers a platform hint, so the hint half of dedupe can be
/// exercised without T-0156's PC entry, which is in flight elsewhere.
class _HintedSource implements DetectionSource {
  _HintedSource(this.hint);

  final String hint;

  @override
  SourceReading read(SourceEntry entry) => SourceReading(items: [
        Detection.fromSource(
          rawTitle: _FakeSource._guess(entry.name)!,
          origin: DetectionOrigin.filename,
          sourceEntry: entry.name,
          platformHint: hint,
        ),
      ]);
}
