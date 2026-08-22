/// A game file's NAME as a detection source (T-0158), on T-0155's seam.
///
/// The analogue of `providers/vision.dart`'s prompt for the filesystem: the
/// rules below are a measured artifact rather than a regex anyone believes in.
/// What they were measured against is `test/corpus/installer_names.tsv`,
/// replayed by `test/filename_source_test.dart`, which also holds the counts
/// so no figure can be quoted here after the corpus has moved under it.
///
/// Declining is the success case, not the gap: T-0007 forbade the vision
/// prompt to name a spine it could not read, and a folder of files is the same
/// reader with the same failure available to it.
///
/// Nothing here opens anything. `SourceEntry` arrives with the name and the
/// containing directory's name already read by the shell (ARCHITECTURE.md
/// platform boundary), and [SourceEntry.content] is ignored: metadata written
/// beside the game is T-0157's source, and a name is all this one claims to
/// read.
library;

import '../models.dart';
import '../orchestrator.dart';
import '../title_key.dart';

/// The hint a row carries when the name says nothing about a console.
///
/// T-0156 added `PC` to `platformIds` for exactly these two sources and pinned
/// three spellings against a store name reaching the gate: `GOG` matches no
/// entry, the query then runs unfiltered, and `platformAgreement` compares the
/// hint against the platform NAME -- so every candidate comes back `mismatch`
/// and the row resolves to nothing at all.
///
/// It is the default and not the only answer since T-0168: a name that prints
/// a console container gets that console's hint through
/// [consolePlatformHints], or declines when the container names no single one.
const filenamePlatformHint = 'PC';

/// Turns [SourceEntry.name], falling back to [SourceEntry.container], into at
/// most one row.
///
/// At most one, never several: a name carries one title or none, and a folder
/// holding two games under one name is a shape nobody here has seen.
class FilenameSource implements DetectionSource {
  const FilenameSource();

  @override
  SourceReading read(SourceEntry entry) {
    final parse = parseGameFileName(entry.name, container: entry.container);
    final title = parse.title;
    if (title == null) {
      return SourceReading(
        declined: [
          DeclinedEntry(
              name: entry.name,
              reason: parse.declined!,
              severity: parse.declinedSeverity!)
        ],
      );
    }
    return SourceReading(items: [
      Detection.fromSource(
        rawTitle: title,
        origin: DetectionOrigin.filename,
        sourceEntry: entry.name,
        platformHint: parse.platformHint,
        // Carried as its own field and never near the title: folding it back
        // in scores 0.750 bare and 0.682 bracketed, both under `minAutoScore`,
        // and `volumeNumbersAgree` disagrees as well (T-0165).
        sourceYear: parse.year,
      ),
    ]);
  }
}

/// Why an entry produced no row.
///
/// A closed set of five, because `Orchestrator._warnDeclined` groups its
/// warnings by this exact string: a games folder declines more entries than it
/// accepts, and a reason carrying the offending extension would turn 40
/// skipped files into 40 warning lines.
///
/// **All five are [Severity.exclusion]** (T-0222). This source is handed a
/// name and nothing else, so it has no promised shape to be disappointed by:
/// every one of these is a name that was read and held no game this collection
/// wants. The class is still stated at each `return` rather than once here --
/// see [FileNameParse.declinedSeverity].
abstract final class DeclineReason {
  static const notAGameFile = 'not a game file';

  /// Since T-0168 this is narrower than its wording: a console container that
  /// DOES name one platform now gets a row. What is left under it is a
  /// container naming several platforms, or one, or two contradicting ones --
  /// all of which reach the human as one grouped warning line, which is why
  /// the string stays as it is rather than growing a fourth reason for a
  /// distinction nobody acts on.
  ///
  /// **The one reason here whose class is a judgement (T-0222.)** Its own name
  /// and its first two sub-cases are an exclusion -- a console image is not
  /// something this collection wants. The third, two contradicting console
  /// marks in one name, is a game being lost to a name nobody can read, which
  /// is a failure. It is classed [Severity.exclusion] because the three are
  /// one string by T-0168's deliberate choice and the human can act on none of
  /// them differently; splitting the third out is a new reason constant and a
  /// separate task, not a class this file can assign to a distinction it does
  /// not carry.
  static const notAPcInstaller = 'not a PC installer';
  static const supportFile = 'installer support file, not a game';
  static const noTitle = 'no title in the name';

  /// A name that is a base plus the mark Windows appends to a duplicate, and
  /// nothing else ([_numberedCopy], T-0189).
  ///
  /// Deliberately not [noTitle], and the second of its two reasons is the one
  /// still load-bearing. [parseGameFileName] falls back to the container on
  /// [noTitle] alone, so `Новая папка (2)` under that reason took the SCAN
  /// ROOT's name -- `Downloaded games`, a worse row than the one being
  /// removed; T-0193 stopped both shells passing a scan root at all, so what
  /// that fallback can now reach is a game's own folder, where the title would
  /// have been right. What does not depend on any shell: [installerNamingFolder]
  /// asks only whether the folder titled anything, so a numbered folder joins
  /// the class T-0174 opened and is overridden by any one file inside that does
  /// name a game.
  static const numberedCopy = 'a numbered copy of another name, not a title';
}

/// What [parseGameFileName] made of one name.
///
/// [year] and [version] are on the result rather than folded into [title]
/// because each is an answer in its own right: the version is what T-0156
/// measured as fatal to the match, and the year is the only signal a filename
/// has that a spine does not.
class FileNameParse {
  const FileNameParse.declined(String this.declined, this.declinedSeverity)
      : title = null,
        year = null,
        version = null,
        fromContainer = false,
        setupPrefix = false,
        platformHint = filenamePlatformHint;

  const FileNameParse.title(
    String this.title, {
    this.year,
    this.version,
    this.fromContainer = false,
    this.setupPrefix = false,
    this.platformHint = filenamePlatformHint,
  })  : declined = null,
        declinedSeverity = null;

  /// Null exactly when [declined] is not.
  final String? title;

  /// The `platformIds` key this name earned: [filenamePlatformHint] unless it
  /// printed a console container ([consolePlatformHints]).
  ///
  /// Never null and never a spelling the gate cannot honour, which is the whole
  /// point of the field -- a hint matching no platform name comes back
  /// `mismatch` on every candidate the row has (T-0156), so a name whose
  /// container names no single platform declines instead of carrying one.
  final String platformHint;

  /// The [DeclineReason] this name got, or null when [title] has a value.
  final String? declined;

  /// Which of [Severity]'s two things [declined] is. Null exactly when
  /// [declined] is.
  ///
  /// Stated per `return` rather than once for the class, even though all five
  /// of [DeclineReason] are [Severity.exclusion] today: the compiler is then
  /// what asks the question of a sixth reason, and a reason this file cannot
  /// read a name for -- rather than one it read and did not want -- would be
  /// the first [Severity.failure] here (T-0222).
  final Severity? declinedSeverity;

  /// The release year, when the name printed one where a title cannot be.
  final int? year;

  /// The version string removed from [title]. Null when the name carried none.
  final String? version;

  /// Whether [title] came from the containing directory rather than the entry.
  final bool fromContainer;

  /// Whether a leading [_leadingNoise] token was dropped off the front.
  ///
  /// Exposed because it is the half of "this file is a DOWNLOADED installer,
  /// not a game's own launcher" that nothing else on this class records --
  /// [version] is the other half, and [installerNamingFolder] is the one
  /// caller that needs either. `hbl2.exe` and `Sundrop Hollow.exe` carry
  /// neither mark; `setup_iron_march_2_ultimate_2.1.0.4.exe` carries both and
  /// GoG's own `setup_<title>_build_<n>_(64bit)_(<build>).exe` carries only
  /// this one (measured 2026-08-16, T-0183).
  final bool setupPrefix;
}

/// The one entry point: a name, and the directory it sits in, to a title.
///
/// Pure and free, which is the whole difference from a spine read -- no call,
/// no cost, and no first-ask-versus-repeat variance to control for, so a
/// corpus replays as often as anyone wants.
FileNameParse parseGameFileName(String name, {String? container}) {
  final own = _parseOne(name);
  if (own.title != null) return own;

  // The parent is tried only when the entry itself yielded nothing, so a named
  // installer always beats the folder it happens to sit in. GoG writes both --
  // `Marlow's Gate 3/setup_marlows_gate_3_2.0.0.7_(64bit).exe` -- and the
  // folder is the better of the two strings there, keeping the apostrophe and
  // the capitals; preferring it would still be wrong, because it takes the
  // title off `Downloads` for every loose installer in the corpus.
  //
  // A generic parent needs no guard of its own here: [_parseOne] consults
  // [_genericNames] for whatever string it is handed, so `Downloads` declines
  // as a name exactly as it did as a container (T-0174). Two consultation
  // sites were the defect.
  //
  // That list is the weaker half of the guard and always was, being English
  // (T-0183). The strong half is the shell's and is not code here: a container
  // is a directory that could be a game's own folder, never the one the user
  // pointed the scan at, whose name titles no game in any language and which
  // no list can be written for. See [SourceEntry.container] (T-0193).
  if (own.declined == DeclineReason.noTitle && container != null) {
    final parent = _parseOne(container);
    final title = parent.title;
    if (title != null) {
      return FileNameParse.title(title,
          year: parent.year,
          version: parent.version,
          fromContainer: true,
          setupPrefix: parent.setupPrefix,
          platformHint: parent.platformHint);
    }
  }
  return own;
}

/// The one file inside a subdirectory that names the game the directory's own
/// name does not -- or null, meaning the directory goes over under its own
/// name, which is what happened to every subdirectory before T-0178.
///
/// A folder called `New Folder` holding `setup_harbour_lantern_1.6.15.exe` used
/// to be a wrong title; since T-0174 it declines, and the game is lost with
/// the answer one directory away. [fileNames] are the direct child FILE names
/// of [folderName], which both shells already have: each takes that listing to
/// find `goggame-*.info` (T-0160, T-0161), so nothing here reads anything and
/// no walk goes deeper. What changes is which entry is kept from a listing
/// that was made either way.
///
/// **The folder's own name is asked first and wins by default**, because both
/// strings arrive as [DetectionOrigin.filename] so authority cannot separate
/// them and order must -- exactly as in [parseGameFileName], where the
/// container is consulted only when the name yielded nothing -- and because the
/// folder name is the better string of the two when both name the same game,
/// keeping the apostrophe and the capitals
/// `setup_marlows_gate_3_2.0.0.7_(64bit).exe` has thrown away (T-0158).
///
/// **The one thing that overrides it is a contradiction, and it is measured by
/// shape rather than by vocabulary (T-0183).** T-0178 asked the folder name
/// first and stopped there, which made the rule locale-bound: it can only give
/// up a folder name that [_genericNames] lists, and that list is English. On
/// a Russian-locale Windows the default new-folder name is `Новая папка`,
/// which no list here holds, so `Новая папка/
/// setup_iron_march_2_ultimate_2.1.0.4.exe` produced the row `Новая папка` and
/// the game one file away was never read (measured on a development machine
/// 2026-08-16). Both gates below are load-bearing, and each was measured
/// against a real folder rather than argued:
///
/// - **The file must be a DOWNLOADED installer** -- [FileNameParse.setupPrefix]
///   or a stripped [FileNameParse.version]. This is what keeps
///   `Harbour Lantern/hbl2.exe` yielding `Harbour Lantern` instead of `hbl2`: a
///   game's own launcher carries neither mark, and so does `Sundrop Hollow.exe`
///   in a folder called `Trellis`. Without it the rule is the plain reversal
///   the brief forbids.
/// - **The two titles must share no word**, folded through [titleKey]. A real
///   GoG download is a folder named `<title>_<version>_
///   (<build>)_win_gog` holding `setup_<title>_build_<n>change_<n>_0_(64bit)_
///   (<build>).exe` and 27 `.bin` parts: the file carries the setup prefix, the
///   two titles are NOT equal -- the file's parses with the build words still
///   on it -- and only the shared `<title>` words stop the rule replacing a
///   clean folder title with that. Equality would not have caught it, and
///   nothing in the corpus would have shown it.
///
/// What this gives up, deliberately: a folder named after game A holding one
/// unmistakable installer for game B now yields B, where T-0178 yielded A. That
/// case was never measured -- T-0158 measured the folder name as the better
/// string for the SAME game, which the shared-word gate keeps intact -- and a
/// name the OS wrote in a language this code cannot read is weaker evidence
/// than a name the publisher wrote.
///
/// **A folder the OS numbered is asked for corroboration and declines without
/// it (T-0189).** The shape gate above needs one file inside that names a game,
/// so a folder holding only `setup.exe` had nothing to swap in and went over
/// under its own name: `Новая папка (2)/setup.exe` produced the row `Новая
/// папка`, measured on a development machine 2026-08-16. Nothing is added here
/// for it. [_numberedCopy] makes such a folder title nothing at all, which
/// drops it into the class T-0174 opened -- `folderTitle == null`, so any one
/// file inside that names a game wins, and when none does the folder declines
/// by name instead of guessing.
///
/// That answers the question this rule could not answer before, and it answers
/// it about the NAME rather than about the contents: `Harbour Lantern/setup.exe`
/// is uncorroborated in exactly the same way and still yields *Harbour Lantern*,
/// because its name carries no mark saying the OS made it. Corroboration is
/// demanded only from a name that shows how it was made.
///
/// The rule cannot ask whether a title RESOLVES: IGDB runs in stage 3, long
/// after a source has spoken, so "use the folder name unless it finds nothing"
/// is not available at this seam.
///
/// **What a file has to be**: an extension a PC installer is run from
/// ([_runnableExtensions]) or, failing that, one a game arrives in
/// ([_carrierExtensions]) -- and a name that titles a game on its own. Both
/// gates are load-bearing, measured against this parser 2026-08-16:
/// `Marlow.pak` yields the title `Marlow pak`, so the extension gate is what
/// keeps a game's own file tree out; `unins000.exe`, `setup.exe`, `crack.exe`
/// and `data.zip` all decline by name, which is what leaves one candidate in
/// an installed game's folder rather than four.
///
/// **Runnable outranks carrier rather than pooling with it**, because GoG
/// splits one download into `setup_harbour_lantern_1.6.15.exe` plus
/// `setup_harbour_lantern_1.6.15-1.bin`, `-2.bin`, and the parts parse to
/// `harbour lantern 1` and `harbour lantern 2` (same run) -- three titles for
/// one game if they are pooled, and the rule below would then decline the
/// folder it exists to save. The file you run names the game; the parts are
/// its data.
///
/// **Two named installers are not one game.** Candidates fold by [titleKey]
/// and anything but a single title leaves the folder under its own name, so
/// the threshold is one rather than a number chosen for a download dump: forty
/// installers decline here as surely as two. Whatever the directory holds,
/// this changes WHICH entry the walk hands over and never HOW MANY -- one per
/// subdirectory, before and after -- which is the budget the two-level walk
/// exists to protect.
String? installerNamingFolder(String folderName, Iterable<String> fileNames) {
  final folderTitle = parseGameFileName(folderName).title;

  final runnable = <String>[], carried = <String>[];
  final runnableTitles = <String>{}, carriedTitles = <String>{};
  for (final name in fileNames) {
    final dot = name.lastIndexOf('.');
    final extension = dot <= 0 ? '' : _fold(name.substring(dot + 1));
    final runs = _runnableExtensions.contains(extension);
    if (!runs && !_carrierExtensions.contains(extension)) continue;
    final title = parseGameFileName(name).title;
    if (title == null) continue;
    (runs ? runnable : carried).add(name);
    (runs ? runnableTitles : carriedTitles).add(titleKey(title));
  }

  final candidates = runnable.isNotEmpty ? runnable : carried;
  final titles = runnable.isNotEmpty ? runnableTitles : carriedTitles;
  if (titles.length != 1) return null;
  if (folderTitle == null) return candidates.first;
  return _contradicts(folderTitle, candidates.first) ? candidates.first : null;
}

/// Whether [fileName] names a game that [folderTitle] cannot be a name for.
///
/// Not "differs from": see [installerNamingFolder] for the two gates and the
/// folders each was measured on.
bool _contradicts(String folderTitle, String fileName) {
  final file = parseGameFileName(fileName);
  final title = file.title;
  if (title == null) return false;
  if (!file.setupPrefix && file.version == null) return false;
  return _titleWords(folderTitle).intersection(_titleWords(title)).isEmpty;
}

/// [titleKey] because it is already the project's answer to "are these two
/// strings the same title", and its fold survives a change of script -- which
/// a rule written for a Cyrillic folder name has to.
Set<String> _titleWords(String title) =>
    titleKey(title).split(' ').where((word) => word.isNotEmpty).toSet();

FileNameParse _parseOne(String raw) {
  final stem = _stripExtensions(raw.trim());
  if (stem == null) {
    return const FileNameParse.declined(
        DeclineReason.notAGameFile, Severity.exclusion);
  }
  // Every console mark the name carries, gathered before any of them is
  // honoured: one is a hint, none is `PC`, and two disagreeing ones are the
  // same failure as an unnameable container.
  final hints = <String>{};
  if (stem.console) {
    if (stem.consoleHint == null) {
      return const FileNameParse.declined(
        DeclineReason.notAPcInstaller, Severity.exclusion);
    }
    hints.add(stem.consoleHint!);
  }
  final folded = _fold(stem.text);
  if (_supportFiles.contains(folded)) {
    return const FileNameParse.declined(
        DeclineReason.supportFile, Severity.exclusion);
  }
  if (_namesNoGame(folded)) {
    return const FileNameParse.declined(
        DeclineReason.noTitle, Severity.exclusion);
  }

  // One separator per name, chosen by the name, and read off the stem BEFORE
  // anything below puts a space into it. A stem with no spaces is written in
  // the scene/GoG style, where `.`, `_` and `-` all separate words; a stem
  // that already has spaces carries its dashes as punctuation of the title
  // itself (`Old Dusk Reckonings 1-2`, `The Warlock 3 Moon Rite - Complete
  // Edition`).
  final spaced = stem.text.contains(' ');

  // Order matters here and nowhere else in this file: a version's dots have to
  // be read before dots become separators, or `2.0.0.7` reaches the tokeniser
  // as four numbers, three of which look exactly like sequel markers.
  var setupPrefix = false;
  var text = stem.text;
  var year = _yearInBrackets(text);
  for (final group in _bracketGroups.allMatches(text)) {
    final marked = _consoleMark(_fold(_inner(group[0]!)));
    if (marked == null) continue;
    if (marked.hint == null) {
      return const FileNameParse.declined(
        DeclineReason.notAPcInstaller, Severity.exclusion);
    }
    hints.add(marked.hint!);
  }
  for (final group in _bracketGroups.allMatches(text).toList().reversed) {
    text = text.replaceRange(group.start, group.end, ' ');
  }
  final version = _versionNumber.firstMatch(text)?[0];
  if (version != null) text = text.replaceAll(_versionNumber, ' ');

  text = text.replaceAll(RegExp(r'[._~]+'), ' ');
  if (!spaced) text = text.replaceAll('-', ' ');

  final tokens = text.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
  while (tokens.isNotEmpty && _leadingNoise.contains(_fold(tokens.first))) {
    tokens.removeAt(0);
    setupPrefix = true;
  }
  for (final token in tokens) {
    for (final part in _fold(token).split(RegExp(r'[-+]'))) {
      final marked = _consoleMark(part);
      if (marked == null) continue;
      if (marked.hint == null) {
        return const FileNameParse.declined(
        DeclineReason.notAPcInstaller, Severity.exclusion);
      }
      hints.add(marked.hint!);
    }
  }
  // Two consoles in one name is a name nobody here can read, and guessing
  // between them is the failure this whole table exists to refuse.
  if (hints.length > 1) {
    return const FileNameParse.declined(
        DeclineReason.notAPcInstaller, Severity.exclusion);
  }
  final cut = _metadataCut(tokens);
  year ??= _yearAt(tokens, cut);
  final title = _clean(tokens.take(cut).join(' '));

  // Asked again on what would be emitted, not only on the raw stem: Windows
  // names the second one `New folder (2)`, and the brackets come off above.
  if (title == null || _namesNoGame(_fold(title))) {
    return const FileNameParse.declined(
        DeclineReason.noTitle, Severity.exclusion);
  }
  // The emitted title plus the duplication mark IS the whole name -- nothing
  // else came off it, separators included. That is the test, rather than the
  // mark on its own, and it is what leaves every name that carries evidence of
  // being written ABOUT a game alone: `setup_moor_1.0 (2).exe` keeps its title
  // through an extension, a prefix and a version, and `Moor (2).zip` through
  // an extension (T-0189).
  final copy = _numberedCopy.firstMatch(raw.trim());
  if (copy != null && _clean(copy[1]!) == title) {
    return const FileNameParse.declined(
        DeclineReason.numberedCopy, Severity.exclusion);
  }
  return FileNameParse.title(title,
      year: year,
      version: version,
      setupPrefix: setupPrefix,
      platformHint: hints.isEmpty ? filenamePlatformHint : hints.single);
}

/// The console a mark names, or null when the name carries no console mark at
/// all. A returned record whose [_ConsoleMark.hint] is null is the third
/// answer: a console container that names no single platform.
_ConsoleMark? _consoleMark(String folded) {
  if (_switchTitleId.hasMatch(folded)) return const _ConsoleMark('SWITCH');
  if (!consoleMarkerHints.containsKey(folded)) return null;
  return _ConsoleMark(consoleMarkerHints[folded]);
}

class _ConsoleMark {
  const _ConsoleMark(this.hint);
  final String? hint;
}

/// A Nintendo Switch application id, which this naming convention prints in
/// brackets beside the title (`Title [0100000000000001]`).
///
/// Sixteen hex digits opening `01`, which is the application range every id in
/// the corpus falls in; nothing else in the corpus is bracketed hex, and the
/// bracket groups are thrown away one line later either way, so the only thing
/// this shape decides is the hint. It is one convention off one folder and the
/// weakest evidence in this file -- a Switch game whose name prints no
/// container and no id still leaves with `PC`, and some of the corpus's
/// console rows do exactly that (T-0168).
final _switchTitleId = RegExp(r'^01[0-9a-f]{14}$');

/// One list of names that title no game, consulted for whichever field the
/// name arrived in (T-0174).
///
/// The defect this closes: [_genericNames] was read for [SourceEntry.container]
/// only, so `Screenshots` and `Saves` were refused as a parent and emitted as
/// titles when the shell handed the same directory over under [SourceEntry
/// .name] -- which is how a non-GoG install is titled at all (T-0160).
///
/// Nothing here asks whether the name is a file or a directory. The two are
/// told apart by no character in a name, and the question does not arise: a
/// name that titles no game titles none either way.
bool _namesNoGame(String folded) =>
    _genericStems.contains(folded) || _genericNames.contains(folded);

/// The index the title stops at: the first token that is release metadata.
///
/// Scene names put every tag after the title -- `Title.Words.YEAR.TAG-GROUP` --
/// so one cut point answers the year, the repack marker, the language list and
/// the group suffix together. Sub-tokens are examined because `-` and `+`
/// survive the separator rule above inside a spaced name, which is where
/// `Starweave Chronicles 2 NSW-BigBlueBox-cut` hides its tag.
int _metadataCut(List<String> tokens) {
  for (var i = 0; i < tokens.length; i++) {
    final token = _fold(tokens[i]);
    if (_isYear(token) && i < tokens.length - 1) return i;
    if (token.split(RegExp(r'[-+]')).any(_releaseTags.contains)) return i;
  }
  return tokens.length;
}

/// A four-digit token is a year only when something follows it.
///
/// The rule the corpus decided. `Game.Name.2019.RePack-GROUP` prints a year
/// before its tags, while `MOOR 2016`, `Volo 2004` and `Punter 2005` print one
/// as the last word of the title, where it IS the title and is how IGDB lists
/// the game. Nothing in the shape separates the two -- both are four digits,
/// the same problem the version rule has one level down -- so the evidence
/// used is position, which is the only other thing a name offers. A year in
/// brackets is unambiguous and is read before this ([_yearInBrackets]).
int? _yearAt(List<String> tokens, int cut) {
  if (cut < tokens.length && _isYear(tokens[cut])) return int.parse(tokens[cut]);
  return null;
}

int? _yearInBrackets(String text) {
  for (final match in _bracketGroups.allMatches(text)) {
    final inner = _inner(match[0]!);
    if (_isYear(inner)) return int.parse(inner);
  }
  return null;
}

String _inner(String group) => group.substring(1, group.length - 1).trim();

/// Not in the future, and after the medium existed. The upper bound moves with
/// the clock rather than being pinned, because a pinned one goes stale in
/// silence; it is the one place this parser is allowed to know the date, and
/// the corpus stays clear of it by carrying no year past the current one.
bool _isYear(String token) {
  if (token.length != 4) return false;
  final value = int.tryParse(token);
  return value != null && value >= 1970 && value <= DateTime.now().year + 1;
}

/// A version is two or more dot-separated numbers, or any number behind a `v`.
///
/// **A bare number is never a version.** `2.0.0.7` and `2` are both digits and
/// nothing in the shape tells them apart, so the parser refuses the guess in
/// the direction that keeps the game: `Ashfall 2`, `Moonlight 3` and
/// `Marlows Gate 3` keep their number. That is T-0055 and T-0059's refusal
/// applied to a second reader -- there, a digit where a read stops is a sequel
/// marker and never a truncation; here, a lone digit is a sequel number and
/// never a version -- and it is the same trade both times: a duplicate row
/// costs one tap, a deleted number costs the game.
///
/// The other direction is not free either, and T-0156 priced it: leaving
/// `1.6.15` or `4.0.0.15` on the query loses the auto-match on every one of
/// them, with the score falling to 0.455-0.806 -- below `minAutoScore` --
/// BEFORE `volumeNumbersAgree` refuses it as well. Two conjunctive gates,
/// and this source resolves nothing at all without the strip.
final _versionNumber = RegExp(
    r'(?<=^|[ ._\-\[(])(?:v\d+(?:\.\d+)*|\d+(?:\.\d+){1,3})(?=$|[ ._\-\])])',
    caseSensitive: false);

/// Every bracketed and parenthesised group goes, whatever is in it.
///
/// What the corpus found in them, none of it title: GoG's build and
/// architecture (`(64bit)`, `(38584)`), a container marker (`[NSZ]`), a Switch
/// title id (`[0100000000000001]`), a region (`(RU)`, `(USA)`), a tracker
/// (`[tracker-4410295]`), a mod note (`(Russian Voice mod)`). Not one name
/// in the corpus carried title inside brackets, and a rule that kept some of
/// them would need a list of what belongs there rather than a list of what
/// does not.
///
/// Two of those seven are read for the PLATFORM before the group is thrown
/// away (T-0168) -- the container marker and the title id. Nothing about the
/// title changes; a bracket group is still never part of it.
final _bracketGroups = RegExp(r'[\[(][^\[\]()]*[\])]');

/// The mark Windows appends to a name that collided with one already there:
/// `Новая папка (2)`, `New folder (2)`, and a browser's `(1)` on a re-download.
///
/// One to three digits behind whitespace, which is what separates it from the
/// two other trailing bracket groups this corpus holds -- a release year is
/// four digits (`Mire II The Founding of a Kingdom (1992)`) and a GoG build is
/// five behind an underscore (`_(21474)`, `_(1100000018)`). The whitespace is
/// Explorer's own spelling and is doing that work, not decoration.
///
/// What it is evidence OF is how the name was made, never what it holds:
/// the OS writes it only when a sibling of the base name was in that same
/// directory, so a genuine `Moor (2)` is a second copy of a game the sibling
/// already names -- and two entries emitting one title are one row after stage
/// 2 either way. That is why [DeclineReason.numberedCopy] costs so little and
/// why it is still conditional on nothing inside naming a game.
final _numberedCopy = RegExp(r'^(.*\S)\s+\(\d{1,3}\)$');

/// A trailing dot-segment is an extension only when it is in one of the three
/// lists below.
///
/// Not pedantry: `Game.Name.2019.RePack-GROUP` ends in a segment shaped
/// exactly like one, so treating an unknown segment as an extension declines
/// every scene release there is.
_Stem? _stripExtensions(String raw) {
  var text = raw;
  var console = false;
  String? consoleHint;
  // Twice, for the `.rar.torrent` and `.nsp.torrent` pairs the corpus holds:
  // the outer extension decides what the file is, the inner one is then only a
  // word inside the name.
  for (var i = 0; i < 2; i++) {
    final dot = text.lastIndexOf('.');
    if (dot <= 0 || dot == text.length - 1) break;
    final ext = _fold(text.substring(dot + 1));
    if (_neverAGame.contains(ext)) return null;
    if (consolePlatformHints.containsKey(ext)) {
      console = true;
      consoleHint ??= consolePlatformHints[ext];
      text = text.substring(0, dot);
      continue;
    }
    // A multi-volume archive numbers its parts in the extension itself:
    // `.r00`, `.z01`, `.part2`. There is no list to hold those.
    if (!_carrierExtensions.contains(ext) &&
        !RegExp(r'^(r|z|part)\d+$').hasMatch(ext)) {
      break;
    }
    text = text.substring(0, dot);
    text = text.replaceFirst(RegExp(r'[._-]part\d+$', caseSensitive: false), '');
  }
  return _Stem(text, console, consoleHint);
}

class _Stem {
  const _Stem(this.text, this.console, this.consoleHint);
  final String text;

  /// Whether a console extension came off, which is the question the decline
  /// turns on -- [consoleHint] is null both for a PC name and for a container
  /// that names no single platform.
  final bool console;
  final String? consoleHint;
}

/// A floor, deliberately, and not a filter: at least two characters and at
/// least one letter.
///
/// Anything sharper would be a guess at which short strings are games.
/// `SGHIJ` is an abbreviation the corpus expects to survive as a title, and a
/// three-letter media player is not a game at all -- no rule reading only the
/// name separates them.
///
/// `\p{L}` and not `\w`: Dart's `\w` is ASCII whatever the unicode flag says,
/// and the corpus carries Cyrillic rows for a Russian-locale Windows' own
/// default new-folder name, which `\w` reduces to nothing at all.
String? _clean(String text) {
  final trimmed = text.replaceAll(RegExp(r'^[\s\-_.+]+|[\s\-_.+]+$'), '').trim();
  if (trimmed.length < 2) return null;
  if (!RegExp(r'\p{L}', unicode: true).hasMatch(trimmed)) return null;
  return trimmed;
}

String _fold(String text) => text.toLowerCase().trim();

/// What a Windows installer leaves in a game's folder, plus T-0155's own
/// examples of what else lives there. Matched whole and after the extension is
/// off, so nothing here can clip a title.
const _supportFiles = {
  'unins000',
  'unins001',
  'uninstall',
  'uninstaller',
  'vcredist_x64',
  'vcredist_x86',
  'vc_redist.x64',
  'vc_redist.x86',
  'dxsetup',
  'dxwebsetup',
  'directx',
  'oalinst',
  'physx',
  'dotnetfx',
  'unitycrashhandler32',
  'unitycrashhandler64',
  'crashhandler',
  'redist',
  'dependencies',
};

/// Names that are an installer and nothing else -- the case the parent
/// directory exists for.
const _genericStems = {
  'setup',
  'install',
  'installer',
  'autorun',
  'start',
  'launcher',
  'launch',
  'play',
  'run',
  'game',
  'main',
  'data',
  'app',
};

/// Dropped from the front rather than cut at, because GoG's own convention
/// opens with one: `setup_marlows_gate_3_2.0.0.7_(64bit)_(38584).exe`. The
/// same three words are release tags below, where a trailing `Setup` is cut;
/// cutting at the leading one would leave nothing at all.
const _leadingNoise = {'setup', 'install', 'installer'};

/// Directory names that title no game, whichever field they arrive in.
/// `downloads` is the one the corpus exercises directly: entries arrive with
/// it as their container throughout, and none takes its title from it.
///
/// **This list is English, it stays English, and it is not what makes
/// [installerNamingFolder] work (T-0183).** A Russian-locale Windows names a new
/// folder `Новая папка`; Windows ships one such name per display language, and
/// so do `Screenshots` and `Saves`. Translating the list is bounded in
/// principle and unusable in practice -- a missing entry fails SILENTLY, in
/// exactly the direction that loses a game, and nobody here can verify a
/// locale they do not run. The shape gate in [installerNamingFolder] is the
/// mechanism instead; entries are still added here when a name is measured
/// doing damage, and that is all this list is for.
///
/// What the two shape rules do NOT reach, so it is not mistaken for covered:
/// an UNNUMBERED locale-generated name holding nothing that names a game --
/// a real `Новая папка` would be that row if the installer in it were
/// ever removed. `Новая папка (2)` declines by its mark (T-0189) and this one
/// has no mark to read; no locale-independent evidence exists for it, which is
/// the whole of why the entry below is `new folder` and nothing else.
///
/// Two names were added by T-0174 and no more, because a list of words is
/// wrong for somebody and only a name that has been seen doing damage earns a
/// place on it. Both are written INTO a game's own folder by the game or the
/// store, which is the folder T-0161's control points at:
/// `screenshots` (Steam, GOG Galaxy and the games themselves) and `saves`.
/// Neither titles anything IGDB lists.
///
/// Not added, and named so the next reader knows they were considered rather
/// than missed: `bin`, `logs`, `config`, `mods`, `content`, `binaries`,
/// `engine`, `_commonredist`, `savegames`. Every one is plausible and none is
/// measured here -- no games folder was available to measure against (T-0158
/// found the same) -- and `data`, `redist` and `dependencies` already decline through
/// [_genericStems] and [_supportFiles].
const _genericNames = {
  'downloads',
  'download',
  'desktop',
  'documents',
  'temp',
  'tmp',
  'games',
  'my games',
  'program files',
  'program files (x86)',
  'steamapps',
  'common',
  'install',
  'installers',
  'setup',
  'new folder',
  'gog games',
  'roms',
  'iso',
  'screenshots',
  'saves',
};

/// Release metadata: everything from the first of these onward is not title.
///
/// Edition words are deliberately absent -- `Deluxe`, `Definitive`,
/// `Complete`, `Remastered`, `GOTY` are what the publisher called the product
/// and what IGDB lists it as, so cutting there loses the match rather than
/// cleaning it. Two-letter region codes are absent for the same reason: `us`
/// and `ru` clip real titles, and the corpus prints the three-letter forms.
const _releaseTags = {
  'repack', 'rip', 'dlrip', 'proper', 'readnfo', 'internal', 'cracked',
  'crack', 'crackfix', 'nodvd', 'nocd', 'keygen', 'patch', 'update',
  'hotfix', 'trainer', 'portable', 'preinstalled', 'unrated',
  'incl', 'multi', 'multi2', 'multi3', 'multi4', 'multi5', 'multi6', 'multi7',
  'multi8', 'multi9', 'multi10', 'multi11', 'multi12', 'multi13', 'multi14',
  'multi15', 'multi16', 'undub',
  'x64', 'x86', 'x86_64', 'amd64', 'win32', 'win64', 'win', 'windows',
  '32bit', '64bit', 'retail', 'digital', 'web',
  'setup', 'install', 'installer',
  'eur', 'usa', 'jpn', 'rus', 'kor', 'chn', 'ntsc', 'pal',
  'gog', 'steam', 'origin', 'uplay', 'epic', 'nsw', 'ps2', 'ps3', 'psp',
  'fitgirl', 'dodi', 'elamigos', 'razor1911', 'reloaded', 'skidrow', 'codex',
  'plaza', 'tenoke', 'rune', 'empress', 'cpy', 'hoodlum', 'flt', 'tinyiso',
  'goldberg', 'darksiders', 'seyter', 'kaos', 'chronos', 'prophet',
};

/// A console container extension -> the `platformIds` key it can honestly
/// claim, or **null for a container that names no single platform** (T-0168).
///
/// The key is a lookup, not a vocabulary: membership is what marks the file as
/// a console container, and the value is what decides whether it gets a row or
/// a `not a PC installer` decline. Two ways to be null and both ship as
/// declines, because a hint the gate cannot honour comes back `mismatch` on
/// every candidate and is worse than no row at all (T-0156, T-0113):
///
///  - **the container spans systems.** `.chd` is MAME's and RetroArch's
///    compressed disc image and is not a PlayStation format at all; `.pkg` is a
///    PlayStation package across PS3, PS4 and Vita; `.cso` is a compressed ISO
///    for PSP and for PS2; `.rvz` is Dolphin's and covers GameCube and Wii.
///    `.vpk` is worse than ambiguous -- it is a Vita package *and* a Valve
///    Source archive, so the one hint it might carry is contradicted by a PC
///    file of the same name. These five are the whole of the list and always
///    should be.
///  - a value here that is not a `platformIds` key, which the test forbids.
///
/// The third way closed on 2026-08-16: `.3ds`, `.cia`, `.nds`, `.wud` and
/// `.wux` each name one console and declined only because `platformIds` had no
/// id for it. T-0190 read the four ids off the live `platforms` endpoint, so
/// they now emit `3DS`, `DS` and `WIIU` -- both handheld keys being unions for
/// the reason `SWITCH` is one, measured on `igdb.dart`.
///
/// `SWITCH` is the union `{130, 508}` because a container carries no band: a
/// `.nsp` is written the same way for both, and T-0074 measured thirteen
/// prompt wordings failing to read the band off a case for the same reason.
/// What the union costs is on `ResolverWorker._best` -- rows refused as
/// cross-band ties, and since T-0165 re-measured it live on 2026-08-16 nearly
/// every one of them is **a wrong auto-match refused rather than a right one
/// lost**, the inverse of what T-0023 originally measured.
const consolePlatformHints = <String, String?>{
  'nsp': 'SWITCH', 'nsz': 'SWITCH', 'xci': 'SWITCH', 'xcz': 'SWITCH',
  'gb': 'GB', 'gbc': 'GBC', 'gba': 'GBA',
  'nes': 'NES', 'sfc': 'SNES', 'smc': 'SNES',
  'n64': 'N64', 'z64': 'N64', 'gcm': 'GAMECUBE', 'wbfs': 'WII',
  '3ds': '3DS', 'cia': '3DS', 'nds': 'DS', 'wud': 'WIIU', 'wux': 'WIIU',
  'rvz': null, 'chd': null, 'pkg': null, 'cso': null, 'vpk': null,
};

/// The same evidence when it is not the extension, and the same three-way
/// answer.
///
/// The names this was measured on print the container in brackets (the
/// examples here are substituted, decision 0004) -- `Gilt Banner [NSZ]`,
/// `Moonlight 3 [NSP]` -- or as a bare word inside a scene name (`Starweave
/// Chronicles 2 NSW-BigBlueBox-cut`), so the extension rule alone catches
/// almost none of them. A short list, and only the unambiguous members of
/// it: `gb` and `nes` are words, `nsz` and `xci` are not. `nsw` is here and
/// in no extension, because it is a scene tag rather than a container.
///
/// The five T-0190 named move here too, and not for tidiness: the two tables
/// are asserted to agree on every shared key, because `Title [3DS].3ds` reads
/// both and two answers for one container decline it as a conflict -- the file
/// with MORE evidence losing to the file with less. `cia` is the one value here
/// that is also an English word, and it was already a console mark before it
/// had an id: `Operation CIA.exe` declined as a console container and now
/// emits under a 3DS hint instead, which review can fix and a decline cannot.
const consoleMarkerHints = <String, String?>{
  'nsp': 'SWITCH', 'nsz': 'SWITCH', 'xci': 'SWITCH', 'xcz': 'SWITCH',
  'nsw': 'SWITCH', 'wbfs': 'WII', 'gcm': 'GAMECUBE',
  '3ds': '3DS', 'cia': '3DS', 'nds': 'DS', 'rvz': null,
  'wud': 'WIIU', 'wux': 'WIIU',
};

/// The subset of [_carrierExtensions] that is a program rather than a payload,
/// ranked above the rest by [installerNamingFolder] for the reason recorded
/// there: a GoG download's `-1.bin` parts carry the same name as the `.exe`
/// beside them and parse to `<title> 1`, `<title> 2`.
///
/// `gog` is deliberately not here: it is a disc image GoG ships beside an
/// installer, not the installer.
const _runnableExtensions = {'exe', 'msi', 'sh', 'msix', 'appx'};

/// Extensions a PC game arrives in.
const _carrierExtensions = {
  'exe', 'msi', 'iso', 'bin', 'rar', 'zip', '7z', 'cab', 'gog', 'sh',
  'mdf', 'mds', 'cue', 'img', 'daa', 'nrg', 'tar', 'gz', 'msix', 'appx',
};

/// Extensions that are never a game, declining the entry before a title is
/// parsed out of a name that may read exactly like one.
///
/// `.torrent` is here on real evidence -- a real download folder, measured
/// during development; not published: a download descriptor named after a game
/// is not a copy of anything. The same argument covers `.nfo` and `.sfv`, which
/// sit beside a release carrying its name.
///
/// `.info` is here for a different reason -- it IS a game's metadata, and
/// reading it is T-0157's source, not this one. Both run over the same folder
/// (T-0160), so this one has to hand it over rather than parse a product id
/// out of `goggame-1100000001`.
const _neverAGame = {
  'torrent', 'nfo', 'sfv', 'md5', 'sha1', 'par2', 'url', 'lnk', 'ini', 'info',
  'log', 'txt', 'sav', 'save', 'bak', 'tmp', 'part', 'crdownload',
  'jpg', 'jpeg', 'png', 'gif', 'webp', 'heic', 'bmp', 'ico', 'svg',
  'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'csv', 'md', 'html',
  'json', 'xml', 'yml', 'yaml', 'dll', 'bat', 'ps1', 'reg', 'sys', 'dat',
  'mp3', 'mp4', 'mkv', 'avi', 'flac', 'wav', 'ttf', 'otf', 'apk', 'ipa',
  'winmd', 'safetensors', 'vbox-extpack', 'db', 'cfg', 'conf',
};
