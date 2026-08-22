/// What `goggame-*.info` is allowed to become, and what it is not (T-0157).
///
/// The payloads below are the three files this parser was written against,
/// reproduced key for key; the header of `lib/src/sources/gog_metadata.dart`
/// says where each was quoted and why no vendor page pins the fields. No
/// `goggame-*.info` was available to read, so nothing here
/// reads a file -- which is also the boundary rule: `shelfscan_core` may not
/// open one (ARCHITECTURE.md), and the last group pins that it still does not.
///
/// The unhappy paths carry as much weight as the happy one. This source is
/// pointed at a games folder, where saves, patches, redistributables and DLC
/// mini-manifests outnumber the base games; a parser that guessed at any of
/// them would put a row in front of the owner for something they do not own.
library;

import 'dart:convert';
import 'dart:io';

import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

const _source = GogMetadataSource();

/// ATTIC, as the installer wrote it (lutris/lutris#4080): the seven top-level
/// keys of a generated file, `version` and `playTasks` included, so the happy
/// path is driven by a real payload rather than by the three keys it reads.
const _attic = {
  'buildId': '1100000042',
  'clientId': '1100000043',
  'gameId': '1100000022',
  'rootGameId': '1100000022',
  'language': 'English',
  'languages': ['en-US'],
  'name': 'ATTIC',
  'version': 1,
  'playTasks': [
    {
      'category': 'game',
      'isPrimary': true,
      'languages': ['en-US'],
      'name': 'ATTIC',
      'path': 'attic.exe',
      'type': 'FileTask',
    },
    {
      'category': 'document',
      'link': 'http://www.gog.com/support/attic',
      'name': 'Support',
      'type': 'URLTask',
    },
  ],
};

/// Vexen, from GOG's own forum instructions for a hand-made file: no
/// `version`, no `buildId`, no `clientId`, and `dependencyGameId` present and
/// empty. The control for "every other key is treated as absent" -- it differs
/// from [_attic] in four keys and must read identically.
const _vexen = {
  'gameId': '1100000044',
  'rootGameId': '1100000044',
  'standalone': true,
  'dependencyGameId': '',
  'language': 'English',
  'name': 'Vexen',
  'playTasks': [
    {'isPrimary': true, 'type': 'FileTask', 'path': 'Vexen.exe', 'workingDir': ''},
  ],
};

SourceEntry _entry(Object? payload,
        {String name = 'goggame-1100000022.info', String? container}) =>
    SourceEntry(
      name: name,
      container: container,
      content: payload == null ? null : jsonEncode(payload),
    );

SourceEntry _raw(String content, {String name = 'goggame-1.info'}) =>
    SourceEntry(name: name, content: content);

Map<String, Object?> _withName(String name) => {..._attic, 'name': name};

void main() {
  group('the publisher wrote the title down', () {
    test('a generated file yields one authoritative row', () {
      final reading = _source.read(_entry(_attic));
      expect(reading.declined, isEmpty);
      final detection = reading.items.single;
      expect(detection.rawTitle, 'ATTIC');
      expect(detection.origin, DetectionOrigin.metadata);
      expect(detection.origin.isAuthoritative, isTrue);
      expect(detection.sourceEntry, 'goggame-1100000022.info');
      expect(detection.sourcePhoto, isEmpty,
          reason: 'nothing was read off a photograph (T-0052)');
      expect(detection.confidence, 1.0);
      expect(detection.mediaType, MediaType.unknown);
    });

    test('a hand-made file missing four keys reads identically', () {
      // The keys `version`, `buildId` and `clientId` are in one of the two
      // real files and not the other, which is why nothing reads them.
      final vexen = _source.read(_entry(_vexen, name: 'goggame-1100000044.info'));
      expect(vexen.items.single.rawTitle, 'Vexen');
      expect(vexen.items.single.sourceId, 'gog:1100000044');
      expect(vexen.declined, isEmpty);
    });

    test('the title is taken whole, spaces and punctuation included', () {
      final reading = _source
          .read(_entry(_withName('  The Ledger of Heroes: Paths in the Void SC  ')));
      expect(reading.items.single.rawTitle,
          'The Ledger of Heroes: Paths in the Void SC');
    });
  });

  group('the platform hint is a platform, not the store', () {
    test('it is PC', () {
      expect(GogMetadataSource.platformHint, 'PC');
      expect(_source.read(_entry(_attic)).items.single.platformHint, 'PC');
    });

    test('and the resolver can turn it into an id', () {
      // The contract pc_platform_test.dart's header names: a hint the table
      // cannot map runs the query unfiltered and then answers `mismatch` on
      // every candidate, so a source emitting `GOG` would resolve nothing.
      expect(platformIds[GogMetadataSource.platformHint], {6});
      expect(platformIds['GOG'], isNull);
    });
  });

  group('the product id has a home', () {
    test('it is gameId, namespaced, on the detection', () {
      expect(_source.read(_entry(_attic)).items.single.sourceId,
          'gog:1100000022');
    });

    test('it survives a round trip through review.json', () {
      // T-0159 joins on this against IGDB `external_games`, and the join
      // happens after the document has been written and read back.
      final detection = _source.read(_entry(_attic)).items.single;
      final reparsed = Detection.fromJson(detection.toJson());
      expect(reparsed.sourceId, 'gog:1100000022');
      expect(reparsed.sourceEntry, 'goggame-1100000022.info');
      expect(reparsed.platformHint, 'PC',
          reason: 'fromJson is where a non-platform hint is confiscated');
      expect(reparsed.discardedPlatformHint, isNull);
    });

    test('a photographed row still writes no source_id key', () {
      // T-0155's byte-identical rule for a photo-only scan, extended to the
      // key added here.
      final photographed = Detection(
        rawTitle: 'Duskhollow',
        mediaType: MediaType.disc,
        confidence: 0.9,
        sourcePhoto: 'shelf_a.jpg',
      );
      expect(photographed.toJson().containsKey('source_id'), isFalse);
      expect(jsonEncode(photographed.toJson()), isNot(contains('source_id')));
    });

    test('it is not read off the file name', () {
      // The digits in the name and the digits in the file disagree here on
      // purpose: the installer's own value wins, so a renamed file cannot
      // silently retarget the join.
      final reading =
          _source.read(_entry(_attic, name: 'goggame-9999999999.info'));
      expect(reading.items.single.sourceId, 'gog:1100000022');
    });
  });

  group('several .info files in one container', () {
    // A base game and its DLC each install one, sharing a container -- the
    // seam hands them over as one entry apiece (T-0155).
    final baseGame = _entry(_attic, container: 'ATTIC');
    final dlc = _entry({
      ..._attic,
      'gameId': '1100000006',
      'rootGameId': '1100000022',
      'name': 'ATTIC - Pre-order Bonus',
    }, name: 'goggame-1100000006.info', container: 'ATTIC');

    test('the base game becomes a row and the DLC is declined by name', () {
      final rows = [baseGame, dlc].map(_source.read).toList();
      expect(rows.first.items.single.rawTitle, 'ATTIC');
      expect(rows.first.declined, isEmpty);
      expect(rows.last.items, isEmpty);
      expect(rows.last.declined.single.name, 'goggame-1100000006.info');
      expect(rows.last.declined.single.reason, GogMetadataSource.dlcNotAGame);
    });

    test('two base games in one folder are two rows', () {
      // Nothing here merges: a standalone product installed beside another is
      // two games, and stage 2 is the only thing entitled to decide otherwise.
      final second = _entry(_vexen,
          name: 'goggame-1100000044.info', container: 'ATTIC');
      final titles = [baseGame, second]
          .map((entry) => _source.read(entry).items.single.rawTitle);
      expect(titles, ['ATTIC', 'Vexen']);
    });

    test('a DLC whose rootGameId is absent is not treated as one', () {
      // Absent is absent: the rule fires on a DIFFERENT root, never on a
      // missing one, so a file without the key stays a game.
      final noRoot = {..._attic}..remove('rootGameId');
      expect(_source.read(_entry(noRoot)).items.single.rawTitle, 'ATTIC');
    });
  });

  group('a shape we have not seen is declined, never guessed', () {
    final cases = <String, (SourceEntry, String)>{
      'not JSON at all': (_raw('<?xml version="1.0"?>'), GogMetadataSource.notJson),
      'an empty file': (_raw(''), GogMetadataSource.notJson),
      'an outer array': (
        _entry([_attic]),
        GogMetadataSource.notAnObject,
      ),
      'a JSON null': (_raw('null'), GogMetadataSource.notAnObject),
      'a JSON string': (_raw('"ATTIC"'), GogMetadataSource.notAnObject),
      'name missing': (
        _entry({..._attic}..remove('name')),
        GogMetadataSource.noName,
      ),
      'name of the wrong type': (
        _entry({..._attic, 'name': 1100000022}),
        GogMetadataSource.noName,
      ),
      'name blank': (_entry(_withName('   ')), GogMetadataSource.noName),
      'gameId missing': (
        _entry({..._attic}..remove('gameId')),
        GogMetadataSource.noGameId,
      ),
      'gameId as a number': (
        _entry({..._attic, 'gameId': 1100000022}),
        GogMetadataSource.noGameId,
      ),
    };

    cases.forEach((description, expected) {
      test(description, () {
        final (entry, reason) = expected;
        final reading = _source.read(entry);
        expect(reading.items, isEmpty, reason: 'nothing is guessed');
        expect(reading.declined.single.name, entry.name);
        expect(reading.declined.single.reason, reason);
      });
    });

    test('every decline reason is a constant, carrying no per-entry value',
        () {
      // The orchestrator groups its skip warnings by the reason string
      // (`_warnDeclined`), so a reason holding an id or a title would print
      // one line per row -- the shape T-0144 removed. The entry's own name is
      // on `DeclinedEntry` for a reader that wants it.
      final reasons = [
        for (final (entry, _) in cases.values) _source.read(entry).declined.single.reason,
        _source.read(_entry(null)).declined.single.reason,
      ];
      for (final reason in reasons) {
        expect(reason, isNot(matches(RegExp(r'\d{4}'))));
        expect(reason, isNot(contains('ATTIC')));
      }
    });
  });

  group('an install with no metadata is T-0158s, not a failure here', () {
    test('no content declines with the hand-over reason', () {
      final reading = _source.read(SourceEntry(
          name: 'Marlows Gate 3', container: 'GOG Games', content: null));
      expect(reading.items, isEmpty);
      expect(reading.declined.single.reason, GogMetadataSource.noMetadata);
    });

    test('a file that is not goggame-*.info is not this source s business', () {
      // Content present, but the entry is a save game or a config: declined
      // under the same reason, so the two sources cannot both claim a row --
      // this one claims an entry only by returning an item for it.
      for (final name in const [
        'settings.json',
        'goggame-1100000022.hashdb',
        'goggame.info',
        'goggame-abc.info',
      ]) {
        expect(_source.read(_entry(_attic, name: name)).declined.single.reason,
            GogMetadataSource.noMetadata,
            reason: name);
      }
    });

    test('the file name matcher ignores case', () {
      expect(
          _source.read(_entry(_attic, name: 'GOGGAME-1100000022.INFO')).items,
          hasLength(1));
    });
  });

  group('a folder of installs, through the pipeline', () {
    test('one row, the rest named, no vision worker in the object', () async {
      // `resolveOnly` holds no vision provider at all, so a source scan
      // provably cannot make a vision call (T-0155). `SkipResolver` refuses
      // network I/O on top, so nothing here reaches IGDB either.
      final warnings = <String>[];
      final document =
          await Orchestrator.resolveOnly(resolverWorker: SkipResolver())
              .runScan(
        const [],
        sources: [
          SourceRun(_source, [
            _entry(_attic, container: 'ATTIC'),
            _entry({
              ..._attic,
              'gameId': '1100000006',
              'rootGameId': '1100000022',
              'name': 'ATTIC - Pre-order Bonus',
            }, name: 'goggame-1100000006.info', container: 'ATTIC'),
            SourceEntry(name: 'remorse.sav', container: 'ATTIC'),
            SourceEntry(name: 'settings.ini', container: 'ATTIC'),
          ])
        ],
        progress: ScanProgress(onWarning: (w) => warnings.add(w.message)),
      );

      expect([for (final game in document.games) game.detection.rawTitle],
          ['ATTIC']);
      expect(document.games.single.detection.sourceId, 'gog:1100000022');
      expect(
          {for (final entry in document.declinedEntries) entry.name},
          {'goggame-1100000006.info', 'remorse.sav', 'settings.ini'});
      expect(warnings, hasLength(2),
          reason: 'one warning per reason, not one per entry');
    });
  });

  group('the platform boundary', () {
    test('nothing under lib/ imports dart:io', () {
      // The one rule that decides whether this pipeline still runs on Android
      // (ARCHITECTURE.md). Enumerating the folder is the shell's job, which is
      // why this source takes text and never a path.
      final offenders = [
        for (final file in Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart')))
          if (RegExp(r'''^\s*import\s+['"]dart:io['"]''', multiLine: true)
              .hasMatch(file.readAsStringSync()))
            file.path,
      ];
      expect(offenders, isEmpty);
    });
  });
}
