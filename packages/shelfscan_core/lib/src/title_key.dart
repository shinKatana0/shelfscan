/// Identity of a raw title for "did we already read this spine?".
///
/// Shared by the two callers that ask it -- `VisionWorker`'s primary/fallback
/// merge (T-0011) and `Orchestrator` stage 2 (T-0018) -- so that neither can
/// drift away from the measurement recorded on [titleKey], and so that the
/// one place they are ALLOWED to differ is stated here rather than left to
/// where the code happened to live ([ReadScope]).
library;

/// Folds a raw title down to what two readers of the same spine agree on.
///
/// Punctuation and diacritics go because that is where the measurement said
/// two models disagree. Running the real photos through qwen2.5vl:7b +
/// gemma3:12b, a case-and-whitespace-only key let one of each of these
/// shapes through as a new item. The spines are not published; the rows
/// below are invented and each carries one shape:
///
///     MOONLIGHT                    vs  MOONLIGHT(tm)
///     Gilt Banner Three Spires     vs  Gilt Banner: Three Spires
///     Lumen Chorus Sessions GB ... vs  LUMEN CHORUS SESSIONS #GB ...
///     EDGE OF THE SOREN (macron)   vs  Edge of the Soren
///     FALCON'S CREED II            vs  FALCONS CREED II
///
/// The last pair is why an apostrophe is DELETED where every other
/// punctuation run becomes a space (T-0062): folded to a space it splits one
/// word into two, `falcon s creed ii` against `falcons creed ii`, which is
/// not even a truncation of the other, so both reads reached the review
/// document as separate games. Replaying the five control photos through
/// [dedupeDetections] 2026-08-15: every raw read that carries an apostrophe
/// carries it inside a word (`DIRECTOR'S CUT`, `Wren's Awakening`), and none
/// as a separator; the run's rows are identical before and after in
/// count, order and content -- the change merges nothing on this shelf on its
/// own. Adding gemma3's `FALCONS CREED II` read of that spine to the same
/// reads is what it does merge: one row fewer, and the row kept is the whole
/// `FALCON'S CREED II`.
///
/// Deliberately dumber than the resolver's normalization -- no alias table,
/// no fuzzy distance. This only has to catch one spine read twice, and
/// anything cleverer starts merging real entries in a series.
String titleKey(String title) {
  final folded = StringBuffer();
  for (final rune in title.toLowerCase().runes) {
    final char = String.fromCharCode(rune);
    folded.write(_foldedDiacritics[char] ?? char);
  }
  return folded
      .toString()
      .replaceAll(_apostrophes, '')
      // \p{L} rather than [a-z]: Japanese spines have to survive this.
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
      .trim();
}

/// The apostrophe in every spelling one spine can arrive in.
///
/// A model transcribing printed type emits U+2019, a human typing a manual
/// row emits U+0027, and both readings are of the same mark -- one spelling
/// deleted and the other folded to a space would fix the measured pair only
/// half the time. U+02BC is here for a second reason: being `\p{L}` it
/// survives the punctuation fold entirely, so it produces a third key rather
/// than the space-split one. U+FF07 is the full-width form, reachable on the
/// CJK spines already in the control set.
///
/// U+2018 is deliberately NOT here. It is the OPENING half of a quote pair,
/// and in that role it stands before a word rather than inside one -- where
/// deleting changes no key anyway, because the space beside it is folded
/// into the same run. Nothing has been observed emitting it as an
/// apostrophe.
final _apostrophes = RegExp("['’ʼ＇]");

/// How far apart the two reads being compared came from.
///
/// The only axis on which the two callers of [titleKey] are allowed to
/// differ, and they differ only in how much [isTruncatedRead] lets a cut
/// swallow. Recorded here rather than at the call sites so the asymmetry
/// stays a decision instead of an accident.
enum ReadScope {
  /// Two readings of ONE photo (`mergeAnalyses`) -- the same spines, twice.
  samePhoto,

  /// Readings of DIFFERENT photos (`dedupeDetections`, stage 2).
  acrossPhotos,
}

/// True when [fragment] can only be a cut-short reading of [full].
///
/// [titleKey] equality alone misses every truncation the model actually
/// produces: `PATH OF EM`, `Frost W`, `CHRO`, `COM` for spines read in full
/// elsewhere in the same run (T-0003), `MOONLIGHT` for a glare-occluded
/// Moonlight 3 (T-0007 baseline). Each one meets its full twin and becomes a
/// second review row.
///
/// What separates a cut from a genuinely shorter title is that a cut lands
/// INSIDE a word: nothing on a shelf is called `PATH OF EM`. The dangerous
/// class -- editions and sequels -- differs instead by whole appended words,
/// and a real shelf carries both halves of two such pairs at once
/// (`Starweave Chronicles 2` beside `Starweave Chronicles 2: Kaira - The
/// Hidden Country`, `MOONLIGHT + MOONLIGHT 2` beside `MOONLIGHT ORIGINS`).
/// So a whole-word prefix never merges at either scope, which also means the
/// observed `MOONLIGHT` truncation keeps leaking its duplicate row: a bare
/// `MOONLIGHT` is indistinguishable from a real Moonlight 1 case, and
/// T-0018-02 settled that a duplicate the human taps away beats an item that
/// silently vanishes.
///
/// [ReadScope] changes only how much may be missing BEYOND the cut word.
/// Within one photo both reads cover the same spines, so the fragment's own
/// item is in the candidate list by construction and trailing words may be
/// missing too. Across photos the candidate came off a shelf the fragment's
/// photo need not show at all, so only the last word may be cut: `PATH OF EM`
/// there is as plausibly an Ashes the run never read as the Endless Harvest
/// it would be merged into.
///
/// A loss at the OTHER end is refused, at both scopes, and that is a decision
/// rather than an oversight (T-0054). Measured on the five control photos
/// 2026-08-14: a black object in the 1200x900
/// frame covers the head of one spine, which reads `PILGRIM VII REMAKE
/// INTERBLOOM` against the 4000x3000 read `SOLAR PILGRIM(R) VII REMAKE
/// INTERBLOOM` on the same `PS5` hint, and stays a second row. It is one of
/// the two duplicates that run ends with, and the other is the `MOONLIGHT`
/// above: the same call seen from the two ends of the title.
///
/// The occluder hid a whole word, so what is left is well-formed text, and
/// stopping inside a word is the only evidence here that a read is a
/// FRAGMENT and not simply a shorter title. The rule that would catch it --
/// a whole-word suffix, unique among candidates -- merges `MOONLIGHT 2` into
/// `MOONLIGHT + MOONLIGHT 2` and `Kaira - The Hidden Country` into
/// `Starweave Chronicles 2: Kaira - The Hidden Country`, both compilations on
/// this shelf whose parts are sold separately, and unlike `PATH OF EM` the row
/// it deletes there is a real title the resolver would have matched. That is
/// exactly the cost bound [uniqueTruncationMatch] is accepted under, broken.
/// Searching every distinct key of the run for that relation found the one
/// pair above and nothing else, so the rule buys one tap per run.
///
/// A leading loss that stopped INSIDE a word would carry the same evidence a
/// trailing cut does. None has been observed, so none is coded for.
///
/// A DIGIT where the fragment stops is refused at both scopes, whatever
/// [_wholeWordFloor] says. The evidence is what the fragment is MISSING
/// rather than how much it carries, which is the only unit that survives a
/// change of script: a number appearing exactly where a read stops is a
/// sequel marker and not a cut, and that holds wherever the floor lands.
/// `そらのは 真` -> `そらのは 真2`, `ホシノカケラ 真` -> `ホシノカケラ 真2`,
/// `MOONLIGHT` -> `MOONLIGHT 3` are one shape in three scripts, and only the
/// Latin one is spelled with a space that the word-count clauses above
/// already catch. Japanese writes the number against the word, so the sequel
/// arrives INSIDE the cut word and looks exactly like a truncation.
/// Replaying the five control photos through [dedupeDetections] 2026-08-15:
/// no pair of that run's distinct keys stands in this relation at all, so the
/// refusal costs the run nothing and the そらのは spines each stay their own
/// row.
///
/// A sequel numbered in ROMAN letters is the same shape, and what refuses it
/// is BOTH words being well-formed numerals: the cut word as read, and the
/// word it would grow into (T-0059). `xv` -> `xvi` is numeral-to-numeral;
/// `crysta` -> `crystal` is not, and neither is `civ` -> `civitas`,
/// where the fragment alone is a numeral and merging is still right. Keying
/// on one side would refuse a large share of genuine cuts, because
/// `i v x l c d m` are also how an English word ends.
///
/// What that costs, measured 2026-08-15 over a corpus of real titles -- the
/// control run's raw reads and this project's IGDB search cache -- by cutting
/// every one of them at every position inside its last word, at both scopes.
/// The corpus size is a count of a private shelf and is not recorded here,
/// and nor is the truncation total: cutting every title at every position
/// inside its last word makes that total a monotone function of the corpus
/// size, so publishing it publishes the shelf (T-0246, T-0258). What the rule
/// did is recorded. Of the truncations the rule above merged, this refuses
/// 52, being 20 distinct pairs. SEVENTEEN are the fix:
/// `SOLAR PILGRIM XV` -> `XVI`, `X` -> `XVI`, `X` -> `XII`, `XI` -> `XII`,
/// `I` -> `IX`, `FALCON'S CREED I` -> `II`, `OLD DUSK RECKONINGS I` -> `II`,
/// two `9TH ORRERY`, two `PART I` -> `PART II`, six `GILT BANNER` under two
/// spellings of its name. THREE are genuine truncations now lost, every one
/// an abbreviation that happens to be a well-formed numeral: `WREN'S
/// AWAKENING D` -> `DX`, the same title again under its romanized Japanese
/// name, and `PC ENGINE C` -> `CD`. Those three cost a duplicate row each;
/// the seventeen cost a game each. The control run itself is unmoved -- no
/// pair of its distinct keys stands in this relation, and its rows are
/// identical in count, order and content before and after.
///
/// The rejected variant, recorded so it is not retried: matching the maximal
/// trailing RUN of roman letters rather than the whole word, which would also
/// catch a numeral written against its word (`SPXV` -> `SPXVI`). On the same
/// corpus it refuses two more, and both are the same pair: a romanized
/// subtitle cut one letter short, where fragment and full form are BOTH
/// well-formed numerals -- `m` is 1000 and `mi` is 1001. The title is a real
/// one and is not published. The shape it buys has never been read off a
/// spine here; the cut it breaks has.
bool isTruncatedRead(String fragment, String full, {required ReadScope scope}) {
  if (fragment.isEmpty || full.isEmpty || fragment.length >= full.length) {
    return false;
  }
  final cut = fragment.split(' ');
  final whole = full.split(' ');
  if (cut.length > whole.length) return false;
  if (scope == ReadScope.acrossPhotos && cut.length != whole.length) {
    return false;
  }

  final matched = cut.length - 1;
  for (var i = 0; i < matched; i++) {
    if (cut[i] != whole[i]) return false;
  }
  final tail = cut[matched];
  if (tail.isEmpty || tail.length >= whole[matched].length) return false;
  if (!whole[matched].startsWith(tail)) return false;
  if (_sequelNumber.hasMatch(whole[matched].substring(tail.length))) {
    return false;
  }
  if (_romanNumeral.hasMatch(tail) &&
      _romanNumeral.hasMatch(whole[matched])) {
    return false;
  }

  return cut.take(matched).join(' ').length >= _wholeWordFloor;
}

/// `\p{N}` rather than `[0-9]`: [titleKey] keeps full-width digits, so a
/// spine typeset `真２` must read as the same sequel marker as `真2`.
final _sequelNumber = RegExp(r'^\p{N}', unicode: true);

/// A WELL-FORMED numeral, not merely letters drawn from `i v x l c d m`.
///
/// Canonical spelling only -- descending value, the four subtractive pairs,
/// no more than three of a repeatable symbol -- which is what excludes most
/// of the English words spelled in these letters. `civil`, `mild`, `dim`,
/// `did`, `mil`, `vim` and `civic` all fail it. Read out in full, the 3999
/// canonical numerals from 1 to 3999 spell only `mix`, `div`, `civ` and
/// two-letter abbreviations (`cd`, `dx`, `mi`, `mc`, `md`, `cm`, `mm`, ...);
/// what those cost is counted on [isTruncatedRead].
final _romanNumeral =
    RegExp(r'^m{0,3}(cm|cd|d?c{0,3})(xc|xl|l?x{0,3})(ix|iv|v?i{0,3})$');

/// Characters of complete, exactly-matched words a fragment must carry.
///
/// Sized off the observed strings: `CHRO` (4 characters, not one complete
/// word) is a prefix of a great many titles, and `Until` -- from `Frost W` --
/// is the shortest complete word any observed truncation kept. It also rules
/// out a lone leading `a` or `the`.
///
/// It counts CHARACTERS, which is a Latin unit -- five characters of Latin is
/// about two syllables and five characters of Japanese is a whole title -- and
/// it stays that way, measured rather than by taste. Re-running the five
/// control photos 2026-08-15 with the floor dropped to 2 for a CJK fragment
/// produced exactly two new merges over the whole key set, `そらのは 真` into
/// `そらのは 真2` and into `そらのは 真3 そらのは3 別伝 Grey Tides`, and NOTHING
/// else: every relation a script-aware floor buys on a real shelf is a
/// row deletion, and none of them is a truncation. `そらのは` is the largest
/// run of numbered sequels there, so the locale where the smaller floor would
/// help is the locale where it does the damage.
///
/// The floor is therefore not what stands between that shelf and a deleted
/// row -- the digit refusal in [isTruncatedRead] is, and it holds at any
/// floor. `ホシノカケラ 真` / `ホシノカケラ 真2` is the counterexample that
/// showed the difference: a 6-character head clears this floor, so before
/// that refusal existed the pair merged and the sequel was silently deleted.
const _wholeWordFloor = 5;

/// Which of two reads a caller will accept as the cut-short one.
///
/// [either] is the plain question "is this one spine read twice". A caller
/// holding evidence beyond the two titles can narrow it, and stage 2 does:
/// it admits a pair whose platform hints disagree only when the read carrying
/// the WEAKER hint is the cut one, because a merge keeps the fuller read's
/// row and the other direction would publish a hint the surviving read did
/// not give (T-0146).
enum CutSide {
  /// Either read may be the fragment.
  either,

  /// Only `key` may be the fragment.
  key,

  /// Only the candidate may be the fragment.
  candidate,
}

/// The one entry of [candidates] that [key] is the same read as, one of the
/// two cut short; null when none or more than one qualifies.
///
/// Ambiguity must not merge: `CHRO` fits Chronos 3 and Chronos 5 equally, and
/// picking either deletes the other. Leaving both is a duplicate row, which
/// is the cheap failure (T-0018-02).
///
/// [cutSides] runs parallel to [candidates] and restricts each entry to one
/// direction; omitted, every entry is [CutSide.either], which is what the
/// same-photo caller asks. Narrowing can only refuse merges, never add them,
/// so it errs the way this whole feature errs.
///
/// What a merge can still cost, stated because it bounds the whole feature:
/// uniqueness is only uniqueness among what this run READ. If `Mythéon S` is
/// a cut of a Shield nothing else caught, and only Sword was read whole, the
/// fragment merges into Sword and the Shield copy is gone. That is accepted
/// on two grounds -- a merge only ever removes the CUT row, never a whole
/// read, so no resolvable item is lost by it; and the fragment it removes is
/// one the resolver could not have matched anyway. The moment both siblings
/// are read, the ambiguity check above blocks the merge.
int? uniqueTruncationMatch(
  String key,
  List<String> candidates, {
  required ReadScope scope,
  List<CutSide>? cutSides,
}) {
  int? found;
  for (var i = 0; i < candidates.length; i++) {
    final side = cutSides?[i] ?? CutSide.either;
    final keyIsCut = side != CutSide.candidate &&
        isTruncatedRead(key, candidates[i], scope: scope);
    final candidateIsCut = side != CutSide.key &&
        isTruncatedRead(candidates[i], key, scope: scope);
    if (!keyIsCut && !candidateIsCut) continue;
    if (found != null) return null;
    found = i;
  }
  return found;
}

/// Explicit table rather than a Unicode normalization dependency: the
/// package stays dependency-light (ARCHITECTURE.md), and what actually turns up
/// on a spine is romanized Japanese long vowels and European accents.
const _foldedDiacritics = <String, String>{
  'ā': 'a', 'á': 'a', 'à': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a',
  'ē': 'e', 'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
  'ī': 'i', 'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
  'ō': 'o', 'ó': 'o', 'ò': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o',
  'ū': 'u', 'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
  'ñ': 'n', 'ç': 'c',
};
