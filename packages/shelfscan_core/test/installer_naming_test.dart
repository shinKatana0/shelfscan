/// The rule both walks ask when a subdirectory's own name titles no game
/// (T-0178): which file inside it, if any, is handed over in its place.
///
/// Strings only. The two shells own the listing and are tested against real
/// directories of their own; what a listing MEANS is one function here, so the
/// threshold and the collision rule cannot differ between them.
library;

import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

void main() {
  group('a folder whose own name titles no game', () {
    test('is named by the one installer in it -- the reported case', () {
      expect(
          installerNamingFolder(
              'New Folder', const ['setup_harbour_lantern_1.6.15.exe']),
          'setup_harbour_lantern_1.6.15.exe');
    });

    test('takes the installer over its own data parts', () {
      expect(
          installerNamingFolder('New folder (2)', const [
            'setup_harbour_lantern_1.6.15-1.bin',
            'setup_harbour_lantern_1.6.15-2.bin',
            'setup_harbour_lantern_1.6.15.exe',
          ]),
          'setup_harbour_lantern_1.6.15.exe');
    });

    test('reads the one meaningful name in an installed game\'s folder', () {
      expect(
          installerNamingFolder('New Folder', const [
            'Sundrop Hollow.exe',
            'crack.exe',
            'unins000.exe',
            'vcredist_x64.exe',
            'steam_api64.dll',
            'data.zip',
            'readme.txt',
          ]),
          'Sundrop Hollow.exe');
    });

    test('falls to the archive a game arrived in when nothing is runnable',
        () {
      expect(installerNamingFolder('New Folder', const ['Harbour Lantern.iso']),
          'Harbour Lantern.iso');
      expect(
          installerNamingFolder('New Folder',
              const ['Tulip Hospital.part1.rar', 'Tulip Hospital.part2.rar']),
          'Tulip Hospital.part1.rar');
    });

    test('prefers what runs to what it sits beside', () {
      expect(
          installerNamingFolder('New Folder',
              const ['setup_moor_1.9_(21474).exe', 'Soundtrack.zip']),
          'setup_moor_1.9_(21474).exe');
    });

    test('reads the extension whatever its case', () {
      expect(installerNamingFolder('New Folder', const ['ASHFALL2.EXE']),
          'ASHFALL2.EXE');
    });

    test('gives up when the folder holds nothing that names a game', () {
      expect(installerNamingFolder('New Folder', const []), isNull);
      expect(
          installerNamingFolder('New Folder',
              const ['setup.exe', 'unins000.exe', 'launcher.exe', 'data.zip']),
          isNull);
    });
  });

  group('the row budget', () {
    test('two named installers are not one game', () {
      expect(
          installerNamingFolder('New Folder',
              const ['setup_moor_1.9.exe', 'setup_arcanum_1.0.exe']),
          isNull);
    });

    test('a download dump is declined by the same rule, not by a count', () {
      final dump = [for (var i = 0; i < 40; i++) 'setup_game${i}_1.0.exe'];
      expect(installerNamingFolder('New Folder', dump), isNull);
    });

    test('two spellings of one download are still one game', () {
      expect(
          installerNamingFolder('New Folder', const [
            'setup_moor_1.9_(21474).exe',
            'setup_moor_1.9_(64bit).exe',
          ]),
          'setup_moor_1.9_(21474).exe');
    });

    test('a game\'s own file tree names nothing, though its names parse', () {
      // `Marlow.pak` parses to the title `Marlow pak`: the extension gate, not
      // the parser, is what keeps an installed game's data out of the review
      // list (measured 2026-08-16).
      expect(parseMediaFileName('Marlow.pak').title, isNotNull);
      expect(
          installerNamingFolder('New Folder',
              const ['Marlow.pak', 'English.pak', 'Screenshot 1.png']),
          isNull);
    });
  });

  group('the collision the folder name wins', () {
    test('a folder whose name the installer inside agrees with keeps it', () {
      expect(
          installerNamingFolder(
              'Marlows Gate 3', const ['setup_marlows_gate_3_2.0.0.7.exe']),
          isNull);
    });

    test('a real GoG download keeps its folder name, unequal though it is', () {
      // The shape of a real folder, measured during development and not
      // published; the title is substituted (decision 0004: no name off a
      // private disk is committed). The two titles are
      // NOT equal -- the file's keeps `build 1100000045change 1100000046 0` -- so
      // only the SHARED WORDS stop T-0183's override replacing a clean folder
      // title with that. Equality as the gate would have broken this folder.
      expect(
          installerNamingFolder('Tulip_Hospital_2.1_(1100000018)_win_gog', const [
            'setup_tulip_hospital_build_1100000045change_1100000046_0_(64bit)_(1100000018).exe',
            'setup_tulip_hospital_build_1100000045change_1100000046_0_(64bit)_(1100000018)-1.bin',
          ]),
          isNull);
    });

    test('a game\'s own launcher never takes the folder name off it', () {
      // T-0178's case, and the one T-0183 must not break: `hbl2.exe` carries
      // neither a setup prefix nor a version, so it is not evidence of
      // anything and `Harbour Lantern` stands.
      expect(installerNamingFolder('Harbour Lantern', const ['hbl2.exe']), isNull);
      expect(installerNamingFolder('Harbour Lantern', const ['Harbour Lantern.exe']),
          isNull);
    });

    test('the names T-0174 declines are the ones that look inside', () {
      for (final name in const [
        'New Folder',
        'New folder (2)',
        'Games',
        'Downloads',
        'Screenshots',
        'Saves',
      ]) {
        expect(installerNamingFolder(name, const ['Sundrop Hollow.exe']),
            'Sundrop Hollow.exe',
            reason: name);
      }
    });

    test('a real one-word game title still wins its own folder', () {
      for (final name in const ['Trellis', 'Beside', 'Thaw', 'Attic']) {
        expect(installerNamingFolder(name, const ['Sundrop Hollow.exe']),
            isNull,
            reason: name);
      }
    });
  });

  group('the collision the installer wins (T-0183)', () {
    test('a Russian default folder name, measured during development', () {
      expect(
          installerNamingFolder('Новая папка',
              const ['setup_iron_march_2_ultimate_2.1.0.4.exe']),
          'setup_iron_march_2_ultimate_2.1.0.4.exe');
    });

    test('the same rule needs no entry for any of these', () {
      // Windows ships one default new-folder name per display language and
      // NONE of these is on [_genericNames] -- which is the point: the rule is
      // the file's shape, not the folder's vocabulary. Spellings written here
      // to stand for a locale, not asserted as that locale's true string.
      for (final name in const [
        'Новая папка',
        'Nouveau dossier',
        'Neuer Ordner',
        'Nueva carpeta',
        'Nova pasta',
        '新建文件夹',
        '新しいフォルダー',
      ]) {
        expect(
            installerNamingFolder(name, const ['setup_moor_1.9_(21474).exe']),
            'setup_moor_1.9_(21474).exe',
            reason: name);
      }
    });

    test('only an installer overrides, and only on a total disagreement', () {
      // The two gates, each on its own. A launcher is not evidence; a shared
      // word means the folder name is corroborated rather than contradicted.
      expect(installerNamingFolder('Moor', const ['setup_moor_1.9.exe']),
          isNull);
      expect(installerNamingFolder('Moor', const ['Blaze.exe']), isNull);
    });

    test('what the shape gate does NOT reach, pinned as the known gap', () {
      // An OS-named folder holding a weakly-named payload keeps the OS name:
      // `Harbour Lantern.iso` is a game arriving, not an installer running, and
      // nothing in either string says the folder name is meaningless. Only a
      // list entry fixes this one, and `новая папка` is deliberately not on
      // the list (T-0183 report). The English default IS on it, which is why
      // the second line differs from the first.
      expect(installerNamingFolder('Новая папка', const ['Harbour Lantern.iso']),
          isNull);
      expect(installerNamingFolder('New Folder', const ['Harbour Lantern.iso']),
          'Harbour Lantern.iso');
    });

    test('two installers are still not one game, whatever the folder', () {
      expect(
          installerNamingFolder('Новая папка',
              const ['setup_moor_1.9.exe', 'setup_arcanum_1.0.exe']),
          isNull);
    });
  });

  group('a folder the OS numbered, holding nothing that names a game (T-0189)',
      () {
    test('the measured case declines instead of becoming a row', () {
      // A numbered folder whose single file is `setup.exe`, measured during
      // development and not published. It produced the row `Новая папка`:
      // the folder name parses to a title, the file inside names no game, so
      // the shape gate had nothing to swap in.
      expect(installerNamingFolder('Новая папка (2)', const ['setup.exe']),
          isNull);

      final reading = const FilenameSource().read(
          const SourceEntry(name: 'Новая папка (2)', container: 'Downloaded games'));
      expect(reading.items, isEmpty);
      expect(reading.declined.single.name, 'Новая папка (2)');
      expect(reading.declined.single.reason,
          'a numbered copy of another name, not a title');
    });

    test('anything inside that names a game overrides the mark', () {
      // The rule fires on absence of corroboration, and the corroboration test
      // is the one T-0174 already built: a folder that titles nothing is named
      // by the one file inside that does. Nothing was added for this -- the
      // numbered folder simply joins that class.
      expect(
          installerNamingFolder(
              'Новая папка (2)', const ['setup_moor_1.9_(21474).exe']),
          'setup_moor_1.9_(21474).exe');
      expect(installerNamingFolder('Moor (2)', const ['setup_moor_1.9.exe']),
          'setup_moor_1.9.exe');
      // T-0183's known gap closes for the numbered sibling and stays open for
      // the unnumbered one: an `.iso` is a payload with no installer shape, so
      // only the folder giving up its own title lets it through.
      expect(installerNamingFolder('Новая папка (2)', const ['Harbour Lantern.iso']),
          'Harbour Lantern.iso');
      expect(installerNamingFolder('Новая папка', const ['Harbour Lantern.iso']),
          isNull);
    });

    test('a real game folder with nothing helpful inside keeps its name', () {
      // The case that says corroboration is NOT required in general.
      // `Harbour Lantern/setup.exe` is uncorroborated in exactly the same way
      // and is a correct row; what separates it is its own name, which carries
      // no mark saying the OS made it.
      expect(installerNamingFolder('Harbour Lantern', const ['setup.exe']), isNull);
      expect(parseMediaFileName('Harbour Lantern').title, 'Harbour Lantern');
      expect(
          parseMediaFileName('setup.exe', container: 'Harbour Lantern').title,
          'Harbour Lantern');
      expect(installerNamingFolder('Harbour Lantern', const []), isNull);
      expect(parseMediaFileName('Ashfall 2').title, 'Ashfall 2');
    });

    test('what it costs, pinned rather than left implicit', () {
      // A genuine `Moor (2)` holding nothing that names a game declines, and
      // that is the whole cost. Windows writes the mark only when a sibling of
      // the base name was in the same directory, so the game is normally named
      // by that sibling -- and two entries emitting one title are one row
      // after stage 2 regardless. When the sibling is gone the user gets a
      // named decline rather than a silent guess, which is the trade decision
      // 0012 already made ("a silent failure is worse than a loud one").
      expect(installerNamingFolder('Moor (2)', const ['setup.exe']), isNull);
      expect(parseMediaFileName('Moor (2)').title, isNull);
      expect(parseMediaFileName('Moor').title, 'Moor');
    });
  });

  group('the mark that separates an installer from a launcher', () {
    test('is a dropped setup prefix or a stripped version, and nothing else',
        () {
      expect(parseMediaFileName('setup_iron_march_2_ultimate_2.1.0.4.exe')
          .setupPrefix, isTrue);
      expect(parseMediaFileName('setup_iron_march_2_ultimate_2.1.0.4.exe')
          .version, '2.1.0.4');
      // GoG's own convention prints the build outside a dotted version, so the
      // prefix is the only mark this one carries (measured 2026-08-16).
      final gog = parseMediaFileName(
          'setup_tulip_hospital_build_1100000045change_1100000046_0_(64bit)_(1100000018).exe');
      expect(gog.setupPrefix, isTrue);
      expect(gog.version, isNull);
      for (final launcher in const [
        'hbl2.exe',
        'Sundrop Hollow.exe',
        'Harbour Lantern.exe',
        'ASHFALL2.EXE',
      ]) {
        final parse = parseMediaFileName(launcher);
        expect(parse.setupPrefix, isFalse, reason: launcher);
        expect(parse.version, isNull, reason: launcher);
      }
    });

    test('a declined name carries neither', () {
      final parse = parseMediaFileName('setup.exe');
      expect(parse.title, isNull);
      expect(parse.setupPrefix, isFalse);
    });
  });
}
