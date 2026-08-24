/// The filename parser, measured against `test/corpus/installer_names.tsv`
/// (T-0158).
///
/// The corpus is a file and not a list in this test on purpose: the brief asks
/// for a measurement rather than a regex somebody believes in, and a
/// measurement whose input lives inside the assertions that read it cannot be
/// re-run by anyone who did not write it. Replaying it costs nothing -- no
/// call, no key, no photo -- which is the one way this reader is easier than
/// the vision prompt it is the analogue of.
///
/// The headline numbers are asserted rather than printed. A parser that
/// quietly starts answering thirty more names is exactly as much of a change
/// as one that quietly stops, and neither shows up in a green suite otherwise.
library;

import 'dart:io';

import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

class _Row {
  const _Row(this.origin, this.group, this.container, this.name, this.expected,
      this.year, this.hint);

  final String origin;
  final String group;
  final String? container;
  final String name;

  /// The expected title, or null for a decline.
  final String? expected;
  final int? year;

  /// The `platformIds` key the row must carry, null for a decline (T-0168).
  final String? hint;

  bool get declines => expected == null;
}

List<_Row> _corpus() {
  final file = File('test/corpus/installer_names.tsv');
  final rows = <_Row>[];
  for (final line in file.readAsLinesSync()) {
    if (line.trim().isEmpty || line.startsWith('#')) continue;
    final cells = line.split('\t');
    if (cells.length != 7) throw FormatException('seven columns expected', line);
    rows.add(_Row(
      cells[0],
      cells[1],
      cells[2] == '-' ? null : cells[2],
      cells[3],
      cells[4] == 'DECLINE' ? null : cells[4],
      cells[5] == '-' ? null : int.parse(cells[5]),
      cells[6] == '-' ? null : cells[6],
    ));
  }
  return rows;
}

void main() {
  final corpus = _corpus();

  group('the corpus itself', () {
    test('is wholly invented, and says so', () {
      final byOrigin = <String, int>{};
      for (final row in corpus) {
        byOrigin[row.origin] = (byOrigin[row.origin] ?? 0) + 1;
      }

      // There is no `real` origin any more. The owner ruled on 2026-08-17 that
      // no folder of their machine may be published in any form, so the rows
      // T-0158 and T-0183 read off real folders are gone; what stands in their
      // place is written to exercise the same parser paths.
      //
      // The cost is stated rather than hidden: a corpus that is all invented
      // proves only that the parser matches its author's imagination. The
      // findings these rows once carried were measured, and they are now in the
      // section headers as prose, with their dates and the fact that the
      // folders are private and not published -- and with no figure at all,
      // because a figure measured on one is a count of its contents.
      //
      // Every count over this corpus is asserted here and written nowhere else
      // (T-0254). An assertion is read back against the rows on every run and
      // fails when they move; a count in prose is checked by nobody, and the
      // counted prose this suite and the corpus header used to carry is how a
      // group's size came to be a folder's size with nothing left saying so.
      expect(byOrigin.keys.toSet(), {'synthetic', 'synthetic-stem'});
      expect(byOrigin['synthetic']! + byOrigin['synthetic-stem']!, 126);
      expect(corpus, hasLength(126));
    });

    test('no name appears twice', () {
      final seen = <String>{};
      for (final row in corpus) {
        expect(seen.add('${row.container}/${row.name}'), isTrue,
            reason: 'duplicate corpus entry: ${row.name}');
      }
    });
  });

  group('the headline numbers', () {
    test('the decline rate over the whole corpus', () {
      final declined = corpus.where((r) => r.declines).length;
      // Declining is the success case here (T-0007), so this pair guards the
      // corpus in both directions at once: a parser that quietly starts
      // answering more names moves it exactly as far as one that quietly stops.
      // Both are facts about an invented file and evidence for nothing outside
      // it.
      expect(declined, 38);
      expect(corpus.length - declined, 88);
    });

    test('the rate splits by what the folder is', () {
      int declines(String group) =>
          corpus.where((r) => r.group == group && r.declines).length;
      int total(String group) =>
          corpus.where((r) => r.group == group).length;

      // The downloads group, where every EMIT is a title for an application
      // rather than a game. What these two guard is the finding stated in the
      // corpus header, which carries no figure of its own because the folder it
      // was measured on is private: nothing in a name separates
      // `NoteWellSetup.exe` from `setup_moor_1.9.exe`, and no list of known
      // applications is bounded, so the input contract has to be a games folder
      // -- T-0160 and T-0161's to enforce, and the most useful thing the
      // measurement said. The group holds one row per shape that header lists,
      // in that order, and its size is the length of that list (T-0254).
      expect(declines('downloads'), 11);
      expect(total('downloads'), 36);

      // The console group: one row per naming convention, and each convention
      // twice -- as the `.torrent` that declines, a name for a copy that is not
      // on the disk and that no hint can rescue, and as the stem it describes,
      // which is where the title and the hint are decided.
      //
      // The stems printing a Switch container or title id carry `SWITCH` and
      // the rest carry `PC`, and that split is this reader's limit rather than
      // a defect it can fix: `Sample Game E.rar`, `Sample_Game_F_Second_EUR`
      // and `SGHIJ` print no console mark of any kind, so the only thing that
      // knows they are Switch games is the folder they sit in, which is the
      // shell's contract (T-0160/T-0161) and not a name.
      expect(declines('console'), 9);
      expect(total('console'), 18);
      expect(
          corpus
              .where((r) => r.group == 'console' && r.hint == 'SWITCH')
              .length,
          6);
      expect(
          corpus.where((r) => r.group == 'console' && r.hint == 'PC').length, 3);

      // The containers that name no ONE platform decline to a row, and that is
      // the result, not a gap. T-0156 measured a hint the gate cannot honour
      // coming back `mismatch` on EVERY candidate, and T-0113 measured what
      // that costs -- the right game removed twice over. No row is strictly
      // better than a wrong one.
      //
      // This group is sized by `consolePlatformHints` and not by anything on a
      // disk: one row per null-valued key, plus the one name printing two
      // consoles at once. T-0190 moved the keys whose console was never in
      // doubt into `nameable`, and what is left spans systems.
      expect(declines('unnameable'), 6);
      expect(total('unnameable'), 6);

      // And the mirror: every container that does name one platform IGDB
      // knows emits, with that platform's key.
      expect(declines('nameable'), 0);
      expect(total('nameable'), 13);

      // The four groups this source is actually for. Every one of their
      // declines is a support file, a save, a document or an installer with no
      // title anywhere near it. Nothing here is a wrong title, which is the
      // number the brief asked for.
      final forThisSource = ['gog', 'scene', 'inside', 'archive'];
      final wanted = corpus.where((r) => forThisSource.contains(r.group));
      expect(wanted.where((r) => r.declines).length, 10);
      expect(wanted, hasLength(50));

      // T-0183's directories are their own group and stay out of the four
      // above: a directory handed over as an entry is a different population
      // from an installer file name, which is why T-0174 refused to invent any.
      // The numbered ones decline since T-0189, on the duplication mark and not
      // on the language; the unnumbered one carries no evidence of any kind and
      // is still read as a title.
      expect(total('folder'), 3);
      expect(declines('folder'), 2);
    });
  });

  group('every corpus row', () {
    for (final row in corpus) {
      test('${row.container ?? "-"} / ${row.name}', () {
        final parse = parseGameFileName(row.name, container: row.container);
        expect(parse.title, row.expected);
        if (!row.declines) {
          expect(parse.year, row.year);
          expect(parse.platformHint, row.hint);
          expect(platformIds.containsKey(parse.platformHint), isTrue);
        }
        if (row.declines) {
          expect(parse.declined, isNotNull);
        }
      });
    }
  });

  group('a version number is stripped', () {
    // T-0156, 2026-08-16: replaying these eight titles with an installer
    // version appended lost the auto-match on 8 of 8, the score falling to
    // 0.455-0.806 -- below minAutoScore -- BEFORE volumeNumbersAgree refused
    // them as well. So the strip is not a tidiness: without it this source
    // resolves nothing.
    const measuredByT0156 = <String, String>{
      'setup_the_warlock_3_moon_rite_2.0.0.7.exe': 'the warlock 3 moon rite',
      'setup_neonwatch_2077_2.1.0.4.exe': 'neonwatch 2077',
      'setup_harbour_lantern_1.6.15.exe': 'harbour lantern',
      'setup_marlows_gate_ii_shadows_of_orn_2.5.26.6.exe':
          'marlows gate ii shadows of orn',
      'setup_herald_of_frost_and_flame_iii_4.0.0.15.exe':
          'herald of frost and flame iii',
      'setup_sundrop_hollow_1.6.15.exe': 'sundrop hollow',
      'setup_ashfall_2_1.02.exe': 'ashfall 2',
      'setup_moor_1.9.exe': 'moor',
    };

    for (final entry in measuredByT0156.entries) {
      test('${entry.key} carries no version into the query', () {
        final parse = parseGameFileName(entry.key);
        expect(parse.title, entry.value);
        expect(parse.version, isNotNull);
        expect(RegExp(r'\d+\.\d').hasMatch(parse.title!), isFalse);
      });
    }

    test('the query the resolver would send has no version left in it', () {
      const name = 'setup_harbour_lantern_1.6.15_(46424).exe';
      final row = const FilenameSource()
          .read(const SourceEntry(name: name))
          .items
          .single;
      expect(row.rawTitle, 'harbour lantern');
      expect(name.contains('1.6.15'), isTrue);
      expect(row.rawTitle.contains('1.6.15'), isFalse);

      // The digits are gone from the query and still on the row, because
      // sourceEntry keeps the name the shell handed over (T-0155).
      expect(row.sourceEntry, name);
    });

    test('volumeNumbersAgree stops disagreeing once the version is off', () {
      // The second of T-0156's two conjunctive gates, driven through the real
      // function rather than described.
      expect(volumeNumbersAgree('harbour lantern 1.6.15', 'Harbour Lantern'),
          isFalse);
      expect(
          volumeNumbersAgree(
              parseGameFileName('setup_harbour_lantern_1.6.15.exe').title!,
              'Harbour Lantern'),
          isTrue);
    });
  });

  group('a version number is never read as a sequel number', () {
    // T-0055 and T-0059 refuse the mirror image of this in dedupe: a digit
    // where a read stops is a sequel marker and never a truncation, whatever
    // the character floor says, because nothing in the shape of a number tells
    // the two apart. `2.0.0.7` and `2` are both digits here, and the refusal
    // goes the same way -- the parser will not turn a lone number into a
    // version, so the game keeps it.
    const sequels = <String, String>{
      'setup_ashfall_2_1.02.exe': 'ashfall 2',
      'setup_marlows_gate_3_2.0.0.7.exe': 'marlows gate 3',
      'Dusk-Rail.2.v1.0.CODEX.iso': 'Dusk Rail 2',
      'Moonlight 3': 'Moonlight 3',
      'Starweave Chronicles 2': 'Starweave Chronicles 2',
      'Marshal & Legions Ash Siren 2.iso': 'Marshal & Legions Ash Siren 2',
      'Blaze II RTX.iso': 'Blaze II RTX',
      'Solar Pilgrim VII.iso': 'Solar Pilgrim VII',
    };

    for (final entry in sequels.entries) {
      test('${entry.key} keeps its number', () {
        expect(parseGameFileName(entry.key).title, entry.value);
      });
    }

    test('a lone number is never taken for a version', () {
      expect(parseGameFileName('Ashfall 2').version, isNull);
      expect(parseGameFileName('setup_ashfall_2_1.02.exe').version, '1.02');
    });

    test('the two are only told apart by dots, and that is the whole rule', () {
      // One title, two names, one difference. `2` survives and `2.0.0.7` does
      // not, and nothing else in the parser looks at either.
      expect(parseGameFileName('setup_mire_2.exe').title, 'mire 2');
      expect(parseGameFileName('setup_mire_2.0.0.7.exe').title, 'mire');
    });

    test('a roman numeral is a sequel too and is never stripped', () {
      // T-0059's half: `i v x l c d m` are also how an English word ends, so
      // no rule here touches them at all.
      expect(parseGameFileName('setup_marlows_gate_ii_2.5.26.6.exe').title,
          'marlows gate ii');
      expect(parseGameFileName('Regent of Aurex II Battle at Kestrel.iso').title,
          'Regent of Aurex II Battle at Kestrel');
    });
  });

  group('a title that is only in the parent directory', () {
    test('is recovered through container', () {
      final reading = const FilenameSource().read(
        const SourceEntry(name: 'setup.exe', container: "Marlow's Gate 3"),
      );
      expect(reading.declined, isEmpty);
      expect(reading.items.single.rawTitle, "Marlow's Gate 3");
      expect(parseGameFileName('setup.exe', container: "Marlow's Gate 3")
          .fromContainer, isTrue);
    });

    test('the entry wins when it has one of its own', () {
      final parse = parseGameFileName(
        'setup_harbour_lantern_1.6.15.exe',
        container: 'Downloads',
      );
      expect(parse.title, 'harbour lantern');
      expect(parse.fromContainer, isFalse);
    });

    test('a container that names no game is not a fallback', () {
      for (final container in ['Downloads', 'Games', 'Program Files (x86)']) {
        final parse = parseGameFileName('setup.exe', container: container);
        expect(parse.title, isNull, reason: container);
        expect(parse.declined, DeclineReason.noTitle);
      }
    });

    test('a support file does not fall back either', () {
      // The folder gets its own entry from the shell; emitting it once per
      // uninstaller would be a row per file in the directory.
      final parse =
          parseGameFileName('unins000.exe', container: 'Harbour Lantern');
      expect(parse.title, isNull);
      expect(parse.declined, DeclineReason.supportFile);
    });
  });

  group('a decline is reported, never guessed', () {
    test('through SourceReading.declined, with the entry named', () {
      final reading = const FilenameSource()
          .read(const SourceEntry(name: 'readme.txt', container: 'Ashfall 2'));
      expect(reading.items, isEmpty);
      expect(reading.declined.single.name, 'readme.txt');
      expect(reading.declined.single.reason, DeclineReason.notAGameFile);
    });

    test('the reasons are a closed set, so warnings group', () {
      // Orchestrator._warnDeclined groups by the reason string: 40 skipped
      // files must be one warning line, not 40.
      final reasons = <String>{};
      for (final row in corpus.where((r) => r.declines)) {
        final reading = const FilenameSource().read(
            SourceEntry(name: row.name, container: row.container));
        reasons.add(reading.declined.single.reason);
      }
      expect(reasons, {
        DeclineReason.notAGameFile,
        DeclineReason.notAPcInstaller,
        DeclineReason.supportFile,
        DeclineReason.noTitle,
        DeclineReason.numberedCopy,
      });
    });

    test('a declined entry reaches the review document by name', () async {
      final document = await Orchestrator.resolveOnly(
        resolverWorker: _NoResolver(),
      ).runScan(
        const [],
        sources: const [
          SourceRun(FilenameSource(), [
            SourceEntry(name: 'readme.txt', container: 'Ashfall 2'),
            SourceEntry(name: 'setup_moor_1.9_(21474).exe'),
          ])
        ],
      );
      expect(document.declinedEntries.single.name, 'readme.txt');
      expect(document.games.single.detection.rawTitle, 'moor');
    });
  });

  group('the row a title becomes', () {
    test('is a filename row, not authoritative, with the PC hint', () {
      final row = const FilenameSource()
          .read(const SourceEntry(name: 'setup_moor_1.9.exe'))
          .items
          .single;
      expect(row.origin, DetectionOrigin.filename);
      expect(row.origin.isAuthoritative, isFalse);
      expect(row.platformHint, 'PC');
      expect(row.sourcePhoto, isEmpty);
      expect(row.mediaType, MediaType.unknown);
    });

    test('the hint is a hint the gate knows, and is not a store name', () {
      // T-0156: `GOG` reaches no platformIds entry, the query then runs
      // unfiltered, and every candidate comes back mismatch against the
      // platform NAME. Pinned here as well because this source is the thing
      // that writes the hint.
      expect(platformIds.containsKey(filenamePlatformHint), isTrue);
      expect(platformIds[filenamePlatformHint], {6});
      expect(platformIds.containsKey('GOG'), isFalse);
    });

    test('a Switch container is a row the gate can honour (T-0168)', () {
      final row = const FilenameSource()
          .read(const SourceEntry(name: 'Sample Game A [NSP]', container: 'consoles'))
          .items
          .single;
      expect(row.rawTitle, 'Sample Game A');
      expect(row.platformHint, 'SWITCH');

      // The whole point of the hint, driven through the real gate rather than
      // asserted on the string: it agrees with both bands and disagrees with
      // the desktop, where `PC` did the opposite on the same file.
      for (final platform in [
        (130, 'Nintendo Switch'),
        (508, 'Nintendo Switch 2'),
      ]) {
        expect(
            platformAgreement(row.platformHint,
                platformId: platform.$1, platformName: platform.$2),
            PlatformAgreement.match,
            reason: platform.$2);
      }
      expect(
          platformAgreement(row.platformHint,
              platformId: 6, platformName: 'PC (Microsoft Windows)'),
          PlatformAgreement.mismatch);
      expect(
          platformAgreement(filenamePlatformHint,
              platformId: 130, platformName: 'Nintendo Switch'),
          PlatformAgreement.mismatch);
    });

    test('content is left to the source that reads it', () {
      // A GoG install's `goggame-*.info` is T-0157's; this source ignores the
      // text and reads only the name.
      final reading = const FilenameSource().read(const SourceEntry(
        name: 'setup_moor_1.9.exe',
        content: '{"name": "MOOR (1993)"}',
      ));
      expect(reading.items.single.rawTitle, 'moor');
    });
  });

  group('a console container names one platform or none (T-0168)', () {
    final tables = {
      'consolePlatformHints': consolePlatformHints,
      'consoleMarkerHints': consoleMarkerHints,
    };

    for (final table in tables.entries) {
      test('${table.key} emits nothing platformIds cannot map', () {
        // The bar the brief set: the id set has to be right, not a row has to
        // appear. A key whose value is null is a container this reader can
        // recognise and cannot name -- it declines, and the null is what says
        // so; a value that is not a key here would be the T-0156 failure
        // shipped as a feature.
        for (final entry in table.value.entries) {
          if (entry.value == null) continue;
          expect(platformIds.containsKey(entry.value), isTrue,
              reason: '${entry.key} -> ${entry.value}');
        }
      });
    }

    test('the two tables agree wherever they overlap', () {
      // One name can carry both marks -- `Sample Game T.nsz` and a bracketed
      // `[NSZ]` -- and two answers for one container would decline the file as
      // a conflict, which is exactly the wrong reason.
      for (final marker in consoleMarkerHints.entries) {
        if (!consolePlatformHints.containsKey(marker.key)) continue;
        expect(consolePlatformHints[marker.key], marker.value,
            reason: marker.key);
      }
    });

    test('an unnameable container declines rather than guessing', () {
      for (final entry in consolePlatformHints.entries) {
        if (entry.value != null) continue;
        final parse = parseGameFileName('Sample Game.${entry.key}');
        expect(parse.title, isNull, reason: entry.key);
        expect(parse.declined, DeclineReason.notAPcInstaller, reason: entry.key);
      }
    });

    test('a nameable container emits the title with that platform', () {
      for (final entry in consolePlatformHints.entries) {
        if (entry.value == null) continue;
        final parse = parseGameFileName('Sample Game.${entry.key}');
        expect(parse.title, 'Sample Game', reason: entry.key);
        expect(parse.platformHint, entry.value, reason: entry.key);
      }
    });

    test('two consoles in one name is a decline, not a first-mark-wins', () {
      expect(parseGameFileName('Sample Game NSW.wbfs').declined,
          DeclineReason.notAPcInstaller);
      expect(parseGameFileName('Sample Game [NSP].wbfs').declined,
          DeclineReason.notAPcInstaller);
      // The same mark twice is one answer, not a conflict.
      expect(parseGameFileName('Sample Game [NSP].nsz').platformHint, 'SWITCH');
    });

    test('the hint survives the container fallback', () {
      final parse =
          parseGameFileName('setup.exe', container: 'Sample Game [NSP]');
      expect(parse.title, 'Sample Game');
      expect(parse.fromContainer, isTrue);
      expect(parse.platformHint, 'SWITCH');
    });

    test('a bracketed Switch title id is the third mark', () {
      // The convention the corpus preserves byte for byte: sixteen hex digits
      // opening `01`, beside the title. It is the weakest evidence in the
      // parser and is pinned here with the shapes it must NOT read -- a build
      // id, an eight-digit hash and a tracker id all sit in brackets in this
      // same corpus.
      expect(parseGameFileName('Sample Game B [0100000000000001]').platformHint,
          'SWITCH');
      for (final name in [
        'setup_harbour_lantern_1.6.15_(46424).exe',
        'Sample Game [deadbeef]',
        'Sample Game [010000000000000]',
        'Toolkit Bundle v75 [tracker-4410295].iso',
      ]) {
        expect(parseGameFileName(name).platformHint, filenamePlatformHint,
            reason: name);
      }
    });

    test('a descriptor is still not a copy, whatever console it names', () {
      // Every declining console row is a `.torrent`, and none of them moves:
      // the outer extension decides what the file IS, and this one is a name
      // for a copy that is not on the disk.
      for (final row
          in corpus.where((r) => r.group == 'console' && r.declines)) {
        expect(row.name, endsWith('.torrent'));
        expect(const FilenameSource().read(SourceEntry(name: row.name))
            .declined.single.reason, DeclineReason.notAGameFile);
      }
    });
  });

  group('the release year', () {
    test('is emitted when the name prints one where a title cannot be', () {
      expect(parseGameFileName('Game.Name.2019.RePack-GROUP').year, 2019);
      expect(parseGameFileName('Tulip.Hospital.(1997).GOG.zip').year, 1997);
      expect(
          parseGameFileName('Mire II The Founding of a Kingdom (1992).iso').year,
          1992);
    });

    test('is refused when the four digits are the title', () {
      // The position rule: `MOOR 2016` and `Volo 2004` print the year as the
      // last word, which is what IGDB lists the game as. Nothing in the shape
      // separates it from a scene name's year -- only what follows it does.
      for (final name in ['MOOR.2016.iso', 'Volo 2004', 'Punter PFL 2005']) {
        expect(parseGameFileName(name).year, isNull, reason: name);
      }
      expect(parseGameFileName('MOOR.2016.iso').title, 'MOOR 2016');
      expect(parseGameFileName('Moor.Eternal.2020.MULTi9-ElAmigos.iso').year,
          2020);
    });

    test('a year out of range is title, not metadata', () {
      // The one that decides the bound: 2077 is not a year yet.
      expect(parseGameFileName('Neonwatch.2077.v2.1.CODEX.iso').title,
          'Neonwatch 2077');
      expect(parseGameFileName('Neonwatch.2077.v2.1.CODEX.iso').year, isNull);
    });

    test('the lower bound is 1970 here, and did not move with the film one',
        () {
      // T-0335 split the two floors. This grammar keeps 1970; the film grammar
      // needed most of a century more, and sharing one floor is what kept the
      // year inside every pre-1970 film's title.
      const old = 'Cabalists.1966.GOG-Razor1911.iso';
      expect(parseGameFileName(old).year, isNull);
      expect(parseGameFileName(old).title, 'Cabalists 1966');
      expect(parseGameFileName('Cabalists.1970.GOG-Razor1911.iso').year, 1970);
    });

    test('it reaches the row as sourceYear, never as part of the title', () {
      // T-0171 gave Detection the field this test was written before: the
      // parse result is no longer where the year stops. What the JSON key
      // assertion pins is that it is `source_year` and not `year` -- a fact
      // about the string the shell handed over, not about the game.
      final row = const FilenameSource()
          .read(const SourceEntry(name: 'Regent.of.Aurex.1993.DOSBox.GOG.zip'))
          .items
          .single;
      expect(parseGameFileName('Regent.of.Aurex.1993.DOSBox.GOG.zip').year,
          1993);
      expect(row.rawTitle, 'Regent of Aurex');
      expect(row.toJson().containsKey('year'), isFalse);
      expect(row.sourceYear, 1993);
      expect(row.sourceEntry, contains('1993'));
    });
  });

  group('a name that titles no game (T-0174)', () {
    // The five the bug was reported on. Three of them already declined as a
    // container and were emitted as titles from the entry's own name, which is
    // the whole defect: one list, read for one of the two fields.
    const measured = ['Screenshots', 'Saves', 'New Folder', 'Games',
        'Downloads'];

    for (final name in measured) {
      test('$name is not a game when the shell hands the directory over', () {
        final parse = parseGameFileName(name);
        expect(parse.title, isNull);
        expect(parse.declined, DeclineReason.noTitle);

        final reading =
            const FilenameSource().read(SourceEntry(name: name));
        expect(reading.items, isEmpty);
        expect(reading.declined.single.name, name);
      });
    }

    test('and is not a game as a container either', () {
      // The other half of the same list, unchanged. Kept beside the half above
      // so a future edit that splits them again fails here.
      for (final container in measured) {
        final parse = parseGameFileName('setup.exe', container: container);
        expect(parse.title, isNull, reason: container);
        expect(parse.declined, DeclineReason.noTitle);
      }
    });

    test('the second one Windows makes is refused too', () {
      // `New folder (2)` is what Explorer names it, and the brackets come off
      // before the title is cut -- so the list is asked again on what would be
      // emitted, not only on the raw stem. Both still decline on the LIST and
      // not on T-0189's mark: the list is consulted first, and these two are
      // the reason a reader might think the mark was never needed.
      expect(parseGameFileName('New folder (2)').declined, DeclineReason.noTitle);
      expect(parseGameFileName('Games (2)').declined, DeclineReason.noTitle);
    });

    test('a game whose folder is one ordinary word still has a title', () {
      // The line drawn: the refusal is a list of names seen doing damage, not
      // a rule about short or common-sounding words. `Trellis` and `Beside`
      // are the ones that would fall to any such rule.
      for (final name in [
        'Trellis',
        'Beside',
        'Thaw',
        'Attic',
        'Skein',
        'Gantry',
        'Errand',
        'Tinderbox',
        'Deepwarren',
        'Moor',
      ]) {
        expect(parseGameFileName(name).title, name, reason: name);
        expect(
            const FilenameSource()
                .read(SourceEntry(name: name, container: 'My Games'))
                .items
                .single
                .rawTitle,
            name);
      }
    });

    test('inside a game folder it becomes the game, exactly as data does', () {
      // Why noTitle and not a hard decline. T-0158 pinned a `data`
      // subdirectory emitting its parent's title as expected behaviour; these
      // names take the same path, so the folder the user pointed at IS the
      // title and stage 2 merges the duplicates. A hard decline would lose it:
      // `readMediaFolder` enumerates children only, so a non-GoG install has no
      // other entry carrying its own folder's name (T-0160/T-0161).
      for (final name in ['Screenshots', 'Saves', 'data']) {
        final parse = parseGameFileName(name, container: 'Dusk-Rail 2');
        expect(parse.title, 'Dusk-Rail 2', reason: name);
        expect(parse.fromContainer, isTrue);
      }
    });

    test('so one game folder is one row and no rejection at review', () async {
      final document = await Orchestrator.resolveOnly(
        resolverWorker: _NoResolver(),
      ).runScan(
        const [],
        sources: const [
          SourceRun(FilenameSource(), [
            SourceEntry(name: 'Saves', container: 'Dusk-Rail 2'),
            SourceEntry(name: 'Screenshots', container: 'Dusk-Rail 2'),
            SourceEntry(name: 'setup.exe', container: 'Dusk-Rail 2'),
          ])
        ],
      );
      expect(document.games.single.detection.rawTitle, 'Dusk-Rail 2');
      expect(document.declinedEntries, isEmpty);
    });
  });

  group('a name the OS numbered (T-0189)', () {
    test('is refused whatever language the base is written in', () {
      // The measured one is first; the rest stand for a locale each and are
      // written here as spellings, not asserted as that locale's true string.
      // The point is that not one of them is consulted -- the mark is.
      for (final name in const [
        'Новая папка (2)',
        'Nouveau dossier (2)',
        'Neuer Ordner (3)',
        '新建文件夹 (2)',
      ]) {
        final parse = parseGameFileName(name);
        expect(parse.title, isNull, reason: name);
        expect(parse.declined, DeclineReason.numberedCopy, reason: name);
      }
    });

    test('declines under its own reason, so no container lends it one', () {
      // Why this is not [DeclineReason.noTitle]. The shell hands a
      // subdirectory over with the SCAN ROOT as its container, and the
      // fallback fires on noTitle alone -- under that reason this folder would
      // have come back titled `Downloaded games`, which is a worse row than
      // the one being removed and looks just as much like a game.
      final parse =
          parseGameFileName('Новая папка (2)', container: 'Downloaded games');
      expect(parse.title, isNull);
      expect(parse.declined, DeclineReason.numberedCopy);
    });

    test('is the whole name, or the name is left alone', () {
      // The mark is read only when NOTHING else came off: every one of these
      // carries something written about a game file -- an extension, a setup
      // prefix, a version, a build, a separator no human types -- and each
      // keeps its title. Losing any of them would undo T-0183, whose whole
      // fix is reading the installer inside a folder like the one above.
      expect(parseGameFileName('Moor (2).zip').title, 'Moor');
      expect(parseGameFileName('setup_moor_1.0 (2).exe').title, 'moor');
      expect(parseGameFileName('Moor 1.9 (2)').title, 'Moor');
      expect(parseGameFileName('Tulip_Hospital (2)').title, 'Tulip Hospital');
    });

    test('is a copy number, not a year and not a build', () {
      // Three digits at most and whitespace in front, which is what tells the
      // mark apart from the other two trailing bracket groups in this corpus.
      final year =
          parseGameFileName('Mire II The Founding of a Kingdom (1992)');
      expect(year.title, 'Mire II The Founding of a Kingdom');
      expect(year.year, 1992);
      expect(parseGameFileName('Moor (21474)').title, 'Moor');
      expect(parseGameFileName('Tulip_Hospital_2.1_(1100000018)_win_gog').title,
          'Tulip Hospital');
    });
  });

  test('no dart:io reaches shelfscan_core', () {
    // The platform boundary this whole seam exists for (ARCHITECTURE.md): the
    // shell enumerates, core parses. Nothing pinned it before T-0158, and a
    // source is the first thing in this package that would be tempted.
    final offenders = <String>[];
    for (final file in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      if (RegExp(r'''^import\s+['"]dart:io['"]''', multiLine: true)
          .hasMatch(file.readAsStringSync())) {
        offenders.add(file.path);
      }
    }
    expect(offenders, isEmpty);
  });
}

/// Stage 3 with the network taken away: this suite resolves nothing and must
/// not be able to.
class _NoResolver implements ResolverWorker {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('no network in this suite');
}
