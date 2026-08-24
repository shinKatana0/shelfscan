/// Resolver worker: raw detection -> canonical IGDB match.
///
/// This is the highest-value part of the pipeline. OCR output from spines
/// is noisy, and regional titles differ from canonical IGDB names
/// (e.g. "Biohazard" vs "Resident Evil"). The resolver's job is to turn
/// that noise into a confident IGDB id -- or an honest list of candidates
/// for the human to pick from during review.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../models.dart';
import '../providers/igdb.dart';
import '../providers/tmdb.dart';
import 'base.dart';

/// Fallback alias table, used when a shell supplies none.
///
/// The growing table lives in `app/assets/data/title_aliases.json`; this
/// exists only so that a run with a missing or malformed data file still
/// gets the three aliases the pipeline has always had, rather than none.
const builtinTitleAliases = <String, String>{
  'biohazard': 'resident evil',
  'rockman': 'mega man',
  'seiken densetsu': 'mana',
};

/// Successively shorter leading prefixes of [query], longest first, for the
/// retry [ResolverWorker] makes when IGDB answers a query with nothing at all.
///
/// A long compound title is IGDB's own failure mode, not this project's:
/// measured live 2026-08-15 with no platform filter, `そらのは 真3 そらのは3 別伝
/// grey tides` returns **0**, `そらのは 真` returns **1** (Path of Ember: True, which
/// carries `そらのは 真` in its `alternative_names`) and `そらのは` returns
/// **4**. It is not a Japanese problem: `solar pilgrim i-vi collection edition
/// anniversaire / anniversary edition` returns 0 under a Switch filter and
/// `solar pilgrim i-vi collection` returns the right game.
///
/// **Halving rather than dropping one token at a time.** Dropping one is more
/// precise -- the longest prefix that answers is the least generic one -- and
/// costs a request per token: the `solar pilgrim i-vi` read needed 5 drops to
/// reach a hit, and one control set has 9-token titles in it. Halving
/// reaches the same forms in `log2` requests (at most 3 for a 9-token title)
/// and the extra genericness costs nothing, because the shortened form is
/// never scored -- see [ResolverWorker.process].
///
/// **A digit starts a token even without a space.** The vision model types the
/// volume number both ways on the same shelf, and which one comes back is the
/// prompt cache (T-0086, correcting T-0053's cold/warm reading): a repeat ask
/// reads `そらのは 真2`, the first-ask read in this task's filing was
/// `そらのは0 約束の丘`. Measured live, `そらのは0` returns **0 hits**
/// unfiltered, so a whitespace-only split leaves the first-ask spelling with
/// nothing shorter to try.
///
/// Prefixes are cut out of [query] itself rather than rejoined from tokens, so
/// the retry carries the spacing and punctuation IGDB was going to be sent --
/// phrase structure is load-bearing for this endpoint (see [stripLegalMarks]).
Iterable<String> shortenedQueries(String query) sync* {
  final starts = _tokenStarts(query);
  final seen = <String>{};
  for (var take = starts.length ~/ 2; take >= 1; take ~/= 2) {
    final form = query.substring(0, starts[take]).trim();
    if (form.isNotEmpty && seen.add(form)) yield form;
  }
}

/// Offsets in [text] at which a token begins: after whitespace, or where a run
/// of digits starts.
List<int> _tokenStarts(String text) {
  final starts = <int>[];
  var previous = ' ';
  for (var i = 0; i < text.length; i++) {
    final char = text[i];
    final isSpace = char.trim().isEmpty;
    if (!isSpace &&
        (previous.trim().isEmpty ||
            (_isDigit(char) && !_isDigit(previous)))) {
      starts.add(i);
    }
    previous = char;
  }
  return starts;
}

bool _isDigit(String char) {
  final code = char.codeUnitAt(0);
  return code >= 0x30 && code <= 0x39;
}

/// Below this the match stays a candidate, not "best".
///
/// Re-measured live 2026-08-15 on both control sets (T-0100): auto-match
/// scores cluster hard at 1.000 on both sets, thin out through 0.95-0.99 and
/// again through 0.90-0.95, and the lowest auto-match on either set is 0.905.
/// The band sizes are counts of a private shelf and are in the control record
/// (T-0246). Moving this to 0.90 still changes no outcome; 0.95 demotes
/// correct matches across the two sets and removes no false positive.
///
/// **What no longer holds is the argument, not the number.** T-0008 read
/// "nothing at all sits between 0.85 and 0.90" as a gap the threshold could
/// live in; that was measured on Latin full-title reads, and a normalised edit
/// distance has no such resolution anywhere else. Rows of the same two
/// control sets, all right or wrong by eye against the photographs:
///
/// | read | matched | score | |
/// |---|---|---|---|
/// | `PILGRIM VII REMAKE INTERBLOOM` | Solar Pilgrim VII Remake Interbloom | 0.829 | right, below |
/// | `そらのは 真3 そらのは3 別伝 Grey Tides` | Path of Ember: True 3 & Grey Ties | 0.852 | right, above |
/// | `そらのは 真2` | Path of Ember: True | 0.857 | **wrong**, above |
///
/// One character of a 6-character Japanese title is 0.143 and one character of
/// a 30-character Latin one is 0.033, so the same threshold cannot mean the
/// same thing for both, and the wrong row here outscores a right one: no value
/// of this constant separates the last two. What does separate them is not a
/// score at all -- see [volumeNumbersAgree] -- which is the same conclusion
/// T-0002 reached for the console: the threshold is not the knob, the gates
/// on [ResolverWorker._best] are.
const minAutoScore = 0.85;

/// How a candidate's platform relates to the hint read off the case.
enum PlatformAgreement {
  match,
  mismatch,

  /// The detection carries no hint, so nothing about the platform is claimed.
  unknown,
}

/// Compares the detection's platform hint with one candidate's platform.
///
/// A hint that [platformIds] can turn into ids already constrains the IGDB
/// query, so this only re-states that. The load-bearing case is the hint it
/// cannot: "NINTENDO" is left unmapped on purpose (it is equally an NES, an
/// N64 and a Wii), the query then runs unfiltered, and IGDB answers with one
/// hit per (game, platform) pair -- a dozen of which tie at 1.000. Measured on
/// T-0008's Run A: all but one of its confident false positives were the right
/// game on the wrong console, picked by IGDB's ordering alone -- a Switch
/// title answered as Android, and the rest of that group the same way.
///
/// The unmapped case falls back to the platform *name*, which is what such a
/// hint is: "NINTENDO" is a subset of "Nintendo Switch" and of "Nintendo
/// Switch 2", but not of "Xbox Series X|S". A family hint therefore narrows
/// without pretending to pick a console.
///
/// A mapped hint agrees with any console it can mean, so `SWITCH` agrees with
/// both 130 and 508 rather than sinking the Switch 2 one. Sinking it is what
/// made the console un-pickable: [ResolverWorker._best] refuses a mismatch, so
/// a hint that named the wrong half of the family would have taken every
/// Switch 2 exclusive to no auto-match at all.
PlatformAgreement platformAgreement(
  String? hint, {
  required int platformId,
  required String platformName,
}) {
  final raw = hint?.trim() ?? '';
  if (raw.isEmpty) return PlatformAgreement.unknown;
  final hinted = platformIds[raw.toUpperCase().replaceAll(' ', '')];
  if (hinted != null) {
    return hinted.contains(platformId)
        ? PlatformAgreement.match
        : PlatformAgreement.mismatch;
  }
  final hintWords = _words(raw);
  if (hintWords.isEmpty) return PlatformAgreement.unknown;
  final platformWords = _words(platformName);
  return hintWords.every(platformWords.contains)
      ? PlatformAgreement.match
      : PlatformAgreement.mismatch;
}

Set<String> _words(String text) => text
    .toLowerCase()
    .split(RegExp(r'[^a-z0-9]+'))
    .where((word) => word.isNotEmpty)
    .toSet();

/// Whether the spine and the IGDB name it matched print the same numbers, in
/// the same order -- the one thing a length-normalised edit distance throws
/// away and this project has twice concluded is a volume marker rather than a
/// variation (T-0055 for arabic digits, T-0059 for roman numerals, both in
/// `isTruncatedRead` in `title_key.dart`, both about dedupe).
///
/// It transfers because the failure has the same shape and, unlike a score, it
/// does not shrink with the title. `そらのは 真2` against IGDB's `そらのは 真`
/// is 0.857 -- above [minAutoScore], and the wrong game, a separate case on
/// the same shelf. `MOONLIGHT` against `Moonlight 2` is the identical relation
/// in Latin and scores 0.818, below it. Nothing about the two claims differs
/// except that one title is 6 characters and the other 9, which is a fact
/// about the metric and not about the shelf.
///
/// Measured on every candidate of both control sets and of the hi-res set with
/// the そらのは `PS2` hints hand-written to the band, 2026-08-15: of the
/// candidate observations that carry a digit on either side, a minority
/// disagree, and **exactly one of those disagreements scores at or above
/// [minAutoScore]** -- the sibling above. Every other one is a DLC or edition
/// name (`Chronos 3 Remade: Nocturne 5 Gold EX BGM Set` against a
/// `CHRONOS 3 REMADE` spine), i.e. this disagrees with the answer where the
/// answer is wrong anyway. Cost on the auto-matches: **none, on the hi-res
/// set, the low-res set and the corrected hints alike.** (The candidate and
/// row counts behind that are counts of a private shelf and are in the control
/// record, T-0246.)
///
/// **Arabic digits only, deliberately.** Roman numerals are the harder half of
/// that rule (T-0059: `i/v/x/l/c/d/m` are also how a genuine cut ends) and
/// folding them is not needed here: `FALCON'S CREED II` auto-matches at 1.000
/// against IGDB's own `Falcon's Creed II`, and its arabic sibling name
/// `Falcon's Creed 2: Deluxe Edition` is a different candidate scoring 0.531.
/// Full-width digits are folded, because a first ask reads one of these spines
/// as `そらのは０ 約束の丘` (T-0065) and ０ and 0 are one volume, not two.
///
/// Identity implies agreement, so this cannot narrow T-0065's `score == 1.0`
/// bar -- it is a second reason to refuse, never a new reason to accept.
bool volumeNumbersAgree(String spine, String candidateName) =>
    _volumeKey(spine) == _volumeKey(candidateName);

String _volumeKey(String text) {
  final halfWidth = String.fromCharCodes([
    for (final unit in text.codeUnits)
      unit >= 0xFF10 && unit <= 0xFF19 ? unit - 0xFEE0 : unit,
  ]);
  return RegExp(r'\d+')
      .allMatches(halfWidth)
      .map((match) => match[0])
      .join(' ');
}

/// Parses the alias table's contents: a flat JSON object mapping
/// a regional title fragment to its IGDB-canonical equivalent.
///
/// Only parsing -- reading the bytes belongs to the shell, because
/// `shelfscan_core` runs on Android where a package-relative file read has no
/// meaning (ARCHITECTURE.md platform boundary).
///
/// Keys and values are lower-cased here so the file can be written in the
/// spelling a human reads on a spine while [ResolverWorker] keeps matching on
/// a lower-cased title.
///
/// Throws [FormatException] on anything that is not that shape; the shell
/// turns that into a warning and falls back to [builtinTitleAliases].
Map<String, String> parseTitleAliases(String json) {
  final decoded = jsonDecode(json);
  if (decoded is! Map<String, dynamic>) {
    throw FormatException('title aliases must be a JSON object, '
        'got ${decoded.runtimeType}');
  }
  final aliases = <String, String>{};
  decoded.forEach((alias, canonical) {
    if (canonical is! String) {
      throw FormatException('alias "$alias" must map to a string, '
          'got ${canonical.runtimeType}');
    }
    final key = alias.trim().toLowerCase();
    if (key.isEmpty || canonical.trim().isEmpty) {
      throw FormatException('alias "$alias" has an empty side');
    }
    aliases[key] = canonical.trim().toLowerCase();
  });
  return aliases;
}

/// A catalogue that states which kinds of work its own search can answer.
///
/// **The kind a row is registered under and the question the catalogue's
/// search actually asks are two different things, and nothing before T-0369
/// compared them.** Decision 0016 made a row's identity the pair
/// `(catalogue, id)` and had `TonkatsuExporter` refuse a row whose namespace
/// disagreed with what its kind implies -- which catches an IGDB id under a
/// film kind and cannot catch a film id under a series kind, because both
/// carry `tmdb:`. The namespace names the service; it does not name the
/// endpoint, and TMDB tells a film from a series by endpoint.
///
/// So the catalogue says it instead, and [registrationsOf] is how a shell
/// builds [CatalogueRouter.catalogues] from that statement rather than from a
/// kind it typed out itself. A shell that never names a kind cannot name the
/// wrong one.
abstract class CatalogueWorker extends Worker<Detection, ResolvedGame> {
  /// The kinds this catalogue's search answers -- never a kind it would
  /// answer with an id for a different sort of thing.
  Set<WorkKind> get answers;
}

/// [catalogue] as [CatalogueRouter.catalogues] entries: one per kind it says
/// it answers, and none it does not.
///
/// The whole of a shell's registration step, so that the map is derived rather
/// than typed. `{WorkKind.animationSeries: TmdbResolverWorker.movies(c)}` is
/// the one-line mistake this task exists to make unwritable, and it is
/// unwritable here because no kind is written at all.
Map<WorkKind, Worker<Detection, ResolvedGame>> registrationsOf(
        CatalogueWorker catalogue) =>
    {for (final kind in catalogue.answers) kind: catalogue};

class ResolverWorker extends CatalogueWorker {
  ResolverWorker(this.igdb, {Map<String, String>? aliases})
      : aliases = aliases ?? builtinTitleAliases;

  final IgdbClient igdb;

  /// IGDB is a games catalogue and answers nothing else. The narrowest of the
  /// three statements on this seam, and the one that was always implicit --
  /// registering this worker for any other kind is the defect T-0308's
  /// required fallback was added to make visible.
  @override
  Set<WorkKind> get answers => const {WorkKind.game};

  /// Regional title fragment -> IGDB-canonical fragment, injected by the
  /// shell from `app/assets/data/title_aliases.json`.
  final Map<String, String> aliases;

  @override
  Future<ResolvedGame> process(Detection task) async {
    // Before the search rather than after it, and it is the only branch a row
    // with no `sourceId` ever sees -- every photograph row skips the whole of
    // [_joinExternalId] on a null check.
    final sourceId = task.sourceId;
    if (sourceId != null) {
      final joined = await _joinExternalId(task, sourceId);
      if (joined != null) return joined;
    }

    final raw = task.rawTitle.trim().toLowerCase();
    // Before the aliases, so an alias fragment is matched against the same
    // text IGDB will be asked for.
    final searchable = stripLegalMarks(raw);
    final query = _applyAliases(searchable);
    // Every spelling is scored against every name IGDB knows: the alias table
    // rewrites the query so IGDB can find the game at all, but the raw spine
    // text is what an alternative name will match exactly. Scoring only the
    // rewritten form would leave "Biohazard RE:4" at 0.83 against "Resident
    // Evil 4" -- found, yet below the auto-match threshold. The stripped
    // spelling earns its place for a different reason: a mark is also
    // Levenshtein distance, so without it rows of the hi-res run kept the
    // same match at a lower score (`Frost Wake™` 0.909 against 1.000,
    // `Super Pippo Maker™ 2` 0.950) -- the first-ask/repeat dependency this
    // task removes, reappearing one field further down.
    //
    // The shortened retry form is deliberately NOT one of them: it is how the
    // game was found, never a claim about what the spine says. Scoring it
    // would hand every retry hit a near-1.0 against the fragment it was
    // fetched by.
    final queries = {raw, searchable, query};

    // The hint narrows the search only when [platformIds] knows ids for it;
    // otherwise this returns every platform the game is on and the gate below
    // is the only thing standing between them and `best`.
    var hits = await igdb.search(query, platformHint: task.platformHint);

    // Two fallbacks, both firing only where IGDB answered the title with
    // nothing at all, so the cost falls on rows that were already lost.
    //
    // The field filter goes first because it is the stronger claim of the two:
    // a stored name *containing the whole spine read* is nearly identity,
    // while a shortened query is a prefix of it and comes back with the series
    // (`そらのは` -> 16 games). It also keeps its answer only when one of those
    // rows *is* the spine, so a row it cannot place is left exactly as the
    // ladder alone would leave it -- see [IgdbClient.searchAlternativeNames].
    var fromFallbackQuery = false;
    if (hits.isEmpty) {
      final byName = await igdb.searchAlternativeNames(query,
          platformHint: task.platformHint);
      if (byName.any((hit) => _isExactly(queries, hit))) {
        hits = byName;
        fromFallbackQuery = true;
      }
    }

    // Measured on `CONTROL-HIRES`: a handful of rows retried, and slightly
    // more extra requests than rows.
    if (hits.isEmpty) {
      for (final shortened in shortenedQueries(query)) {
        hits = await igdb.search(shortened, platformHint: task.platformHint);
        if (hits.isNotEmpty) {
          fromFallbackQuery = true;
          break;
        }
      }
    }

    final scored = hits.map((h) {
      var score = _bestScore(queries, h.title);
      var matchedName = h.title;
      String? matchedAlternative;
      for (final alternative in h.alternativeNames) {
        final alternativeScore = _bestScore(queries, alternative);
        if (alternativeScore > score) {
          score = alternativeScore;
          matchedAlternative = alternative;
          matchedName = alternative;
        }
      }
      return (
        candidate: Candidate(
          externalId: '$igdbCatalogue:${h.igdbId}',
          title: h.title,
          platformId: h.platformId,
          platformName: h.platformName,
          score: score,
          matchedAlternativeName: matchedAlternative,
          releaseYear: h.releaseYear,
        ),
        agreement: platformAgreement(
          task.platformHint,
          platformId: h.platformId,
          platformName: h.platformName,
        ),
        // Against the name that won the score, and satisfied by any spelling
        // the score was allowed to use: an alias that rewrote a numbered
        // fragment must not read as a different volume.
        sameVolume: queries.any((q) => volumeNumbersAgree(q, matchedName)),
      );
    }).toList()
      // A candidate contradicting the hint sinks but is never dropped: it is
      // the right game on the wrong console, which is exactly what a reviewer
      // needs to see. Before this, the agreeing row was outside `take(5)` in
      // 5 of T-0008's 10 platform false positives, so the review screen could
      // not fix them either.
      ..sort((a, b) {
        final byPlatform =
            _sinkMismatch(a.agreement).compareTo(_sinkMismatch(b.agreement));
        if (byPlatform != 0) return byPlatform;
        return b.candidate.score.compareTo(a.candidate.score);
      });

    final best = _best(scored,
        fromFallbackQuery: fromFallbackQuery, sourceYear: task.sourceYear);
    return ResolvedGame(
      detection: task,
      best: best,
      candidates: _window([for (final entry in scored) entry.candidate], best),
    );
  }

  // ------------------------------------------------------------------ //

  /// The rows the review sheet is built around -- the first five -- plus
  /// [best] where those five would have cut it (T-0322).
  ///
  /// The pick is drawn from the whole scored list while the window is its
  /// first five, and [_separatedBySourceYear] searches every entry tied at
  /// the top score rather than the window, so a tie more than five deep can
  /// name a row outside it. The window is what gives way and not the pick:
  /// among identically scoring entries the order is IGDB's, and T-0165
  /// measured that order changing under this project with nothing here
  /// changed -- so confining the pick to an index would decide an auto-match
  /// by a third party's arrangement, which is what the tie rule exists to
  /// refuse.
  ///
  /// It widens rather than evicting. In the only case it fires, the five it
  /// joins are all rows agreeing with the hint and tied at the top score --
  /// every one of them something the human is being asked to choose between
  /// -- and nothing is removed, so T-0008's sunk-but-never-dropped ordering
  /// is reached exactly as before.
  static List<Candidate> _window(List<Candidate> ordered, Candidate? best) {
    final window = ordered.take(5).toList();
    if (best == null || window.any((row) => _sameMatch(row, best))) {
      return window;
    }
    return [...window, best];
  }

  /// The key the review sheet marks the pick by: a candidate is a (catalogue
  /// entry, platform) pair, so one game on two consoles is two of them and
  /// the id alone does not identify a row.
  static bool _sameMatch(Candidate a, Candidate b) =>
      a.externalId == b.externalId && a.platformId == b.platformId;

  /// The store product id joined to IGDB, or null for "carry on as usual"
  /// (T-0159).
  ///
  /// **Where it runs: first, instead of the search, never as a confirmation.**
  /// Running it as a tiebreak would pay the search anyway and would then have
  /// to reconcile a disagreement between a guess and a fact, which is a failure
  /// mode this path exists to not have. Running it first costs a row that
  /// joins exactly one request where the ordinary path costs one search plus up
  /// to four more on `shortenedQueries`' ladder, and costs a row that does not
  /// join one request more than today.
  ///
  /// **What an exact join means for the gates: none of them apply.**
  /// [minAutoScore], [platformAgreement], [volumeNumbersAgree] and the tie rule
  /// all make a *string* match safe, and there is no string here -- IGDB itself
  /// says this uid is this game. `score` is 1.0 because identity is the honest
  /// reading of it; nothing scores it, and [MatchMethod.externalId] is what
  /// says so downstream, because 1.0 alone reads as a string measurement and on
  /// 18 of the 394 joins it would be a false one (T-0170).
  ///
  /// **How `platformId` is picked, which is the one real question, because
  /// 270 of the 394 joined games below are listed on more than one platform.**
  /// The `external_games` row carries no platform of its own
  /// ([externalGameSources]), so it comes from the detection's own hint through
  /// [platformIds] -- `GogMetadataSource.platformHint` is `PC` -> {6}, the same
  /// table and the same answer T-0156 measured for this source. Exactly one hit
  /// on those ids auto-matches; anything else refuses and hands the human every
  /// platform IGDB lists, sorted by id because IGDB's own order is not stable.
  ///
  /// Measured live 2026-08-16 on the 394 joins: **385 are listed on 6 and
  /// auto-match; 9 are not.** Five of the nine are listed only somewhere else
  /// (two on 13 DOS, two on VR platforms, one on 150 TurboGrafx; the library is
  /// a real one, not published, and the rows are not named) and reach review
  /// with the right game and the platforms it
  /// really has; four are listed on nothing at all and never get here, because
  /// a hit is a (game, platform) pair and [IgdbClient.gamesByExternalId]
  /// returns none.
  ///
  /// Claiming 6 for those nine would be the silent failure decision 0012
  /// names: a `.xcoll` row asserting a Windows release IGDB does not record, on
  /// the one path in this product whose whole claim is that it does not guess.
  ///
  /// **A uid IGDB does not know is not a dead end.** Null here and the ordinary
  /// resolver runs on `rawTitle`, which for this source is the title the
  /// installer wrote -- the same row the product would have produced with no
  /// join at all, one request later. 86 of the 480 sampled ids take it.
  Future<ResolvedGame?> _joinExternalId(Detection task, String sourceId) async {
    // `gog:1100000022` -- the namespace is the source's own prefix and the rest
    // is the store's id verbatim, so this splits at the FIRST colon only.
    final colon = sourceId.indexOf(':');
    if (colon <= 0) return null;
    final hits = await igdb.gamesByExternalId(
      source: sourceId.substring(0, colon),
      uid: sourceId.substring(colon + 1),
    );
    if (hits.isEmpty) return null;

    final wanted =
        platformIds[(task.platformHint ?? '').toUpperCase().replaceAll(' ', '')];
    final onHint =
        hits.where((hit) => wanted?.contains(hit.platformId) ?? false).toList();
    final chosen = onHint.length == 1 ? onHint : hits;
    final candidates = [
      for (final hit in chosen)
        Candidate(
          externalId: '$igdbCatalogue:${hit.igdbId}',
          title: hit.title,
          platformId: hit.platformId,
          platformName: hit.platformName,
          score: 1.0,
          releaseYear: hit.releaseYear,
          matchMethod: MatchMethod.externalId,
        ),
    ]..sort((a, b) => switch ((a.platformId, b.platformId)) {
        (final x?, final y?) => x.compareTo(y),
        (null, null) => 0,
        (null, _) => -1,
        (_, null) => 1,
      });
    final best = onHint.length == 1 ? candidates.single : null;
    return ResolvedGame(
      detection: task,
      best: best,
      candidates: _window(candidates, best),
    );
  }

  static int _sinkMismatch(PlatformAgreement agreement) =>
      agreement == PlatformAgreement.mismatch ? 1 : 0;

  /// Whether one of the spine's spellings *is* a name IGDB knows [hit] under.
  ///
  /// The same bar [_best] applies to a fallback hit, checked one step earlier:
  /// it is what entitles the field filter's substring answer to be used at all
  /// (T-0094).
  static bool _isExactly(Set<String> queries, IgdbHit hit) =>
      _bestScore(queries, hit.title) == 1.0 ||
      hit.alternativeNames.any((name) => _bestScore(queries, name) == 1.0);

  /// The auto-match, or null when the pipeline is not entitled to one.
  ///
  /// Two rejections beyond the score. A candidate contradicting the hint is
  /// never `best`: a wrong auto-match reads plausibly and survives review,
  /// while a missing one forces the human to look (decision 0007, "the
  /// resolver refuses what it cannot decide").
  ///
  /// And nothing auto-matches while two equally scored candidates disagree
  /// about the console, because then `best` is IGDB's ordering rather than a
  /// judgement -- a Switch-family title scores 1.000 on both Switch and
  /// Switch 2 under a "NINTENDO" hint, and the sort takes the Switch 2 row
  /// whether or not that is the case on the shelf: it was right on a minority
  /// of the group. Measured with the hints stripped from every hi-res
  /// detection, which is the state T-0001 measured:
  /// the tie rule refuses every wrong-console auto-match and costs correct
  /// ones that are themselves coin tosses -- a title tied 1.000 on PS5 and on
  /// the PS3 original is decided by nothing but the order they arrive in.
  ///
  /// Since T-0023 this fires on the hint the model actually produces, not only
  /// on a stripped or coarse one: `SWITCH` covers both consoles, so a game
  /// IGDB lists on both ties across them. Measured on the same set: it refuses
  /// the one wrong auto-match this project had left (a back-catalogue title
  /// read off a Switch 2 band) and costs correct ones -- back-catalogue titles
  /// IGDB lists on both consoles, and the others like them on the same
  /// photograph.
  /// The two groups are the same shape in the IGDB data; what
  /// separates them is printed on the case and is not in the hint. A hint that
  /// named the console -- `NINTENDO SWITCH 2` -- takes the same run to a band
  /// of further auto-matches, still none wrong.
  ///
  /// **Both figures re-measured live 2026-08-16 (T-0165), replayed through
  /// this code on the control capture's own detections.** Hints stripped:
  /// without the rule more than half the auto-matches are on the wrong
  /// console; with it, none are. So it still refuses every one of them, and it
  /// now costs more correct ones than it did. Under the model's own hints
  /// it refuses the same rows as T-0023 measured -- but IGDB now returns
  /// 508 before 130 for all of them, so what it refuses today is wrong almost
  /// everywhere T-0023 saw it refusing right, and right where T-0023 saw it
  /// wrong: the verdict inverted. Nothing here
  /// changed; a third party's ordering did, which is the argument for the rule
  /// rather than against it.
  ///
  /// **A tie on ONE platform is refused too, unless the two rows carry the
  /// same release year** (T-0165). A hint mapping to a single id -- `PC` ->
  /// {6}, `PS4` -> {48}, `PS5` -> {167}, `SWITCH2` -> {508} -- leaves every
  /// surviving row on that id, so the clause above can never fire and two
  /// *different games* at an identical score were decided by IGDB's ordering.
  /// Measured live on the desktop titles of T-0156: `moor` auto-matched
  /// Moor (2016) while The Ultimate Moor (1995) tied at 1.000 on an
  /// alternative name, and `regent of aurex` and `cabalists` each returned two
  /// identically named games, 1993 against 2016 and 1993 against 2012.
  ///
  /// **The year is what makes refusing them affordable.** Refusing every
  /// same-platform tie costs auto-matches on the hi-res set and on the
  /// low-res set (Solar Pilgrim XVI against its own Collector's Edition,
  /// the same 2023-06-22 release on PS5), and more with every Switch-family
  /// hint forced to 508 (that pair, plus IGDB's two separate 2023-08-17
  /// entries for Old Dusk Reckonings). Every row that costs is one release
  /// under two entries; every collision it catches is two releases. Exempting
  /// an equal year therefore refuses every desktop collision and costs
  /// **no rows at all on any of the four console conditions**. An absent year
  /// -- a small fraction of the games one control run touches -- refuses, like
  /// any other unanswered question here.
  ///
  /// **A year the SOURCE carries separates rather than refuses, and since
  /// T-0171 it reaches here** on [Detection.sourceYear]. Off a photograph
  /// there is still none: no read of either control set contains a
  /// four-digit year, because no spine prints one, so every photographed row
  /// takes the branch above unchanged. Off a filename there is one, and it
  /// answers two of the three collisions above — T-0158's corpus parses
  /// `Regent.of.Aurex.1993.DOSBox.GOG.zip` and `Cabalists.1993.GOG-Razor1911`
  /// to 1993, the year of the release a GoG install of each actually is, while
  /// `setup_moor_1.9_(21474).exe` carries no year and stays refused.
  /// Folding it into the title instead is not the shortcut it looks like:
  /// `regent of aurex 1993` scores 0.750 and `regent of aurex (1993)` 0.682,
  /// both under [minAutoScore], and [volumeNumbersAgree] disagrees as well, so
  /// such a read is refused two gates before this one — and exempting
  /// four-digit numbers from that key would break the case where the number
  /// *is* the volume (`Punter PFL 2004` against `Punter PFL 2005`, a
  /// distinction T-0158's own corpus turns on).
  ///
  /// **It breaks a tie and it never filters** (T-0171). The parse rule is
  /// positional, so the value is whatever the namer put in that slot — a rip
  /// year rather than a release year is a shape nobody has measured a rate
  /// for. Narrowing the IGDB query or dropping candidates on it would put
  /// every filename row at the mercy of that claim, including the rows that
  /// resolve correctly today; deciding a tie with it can only act where this
  /// method already returns null, so a wrong year costs the refusal that was
  /// happening anyway. The tie-break is deliberately narrower than the
  /// exemption beside it: it fires only when the tied rows sit on one platform
  /// (where they sit on two it is the console the human has to decide, and a
  /// year cannot answer that) and only when **exactly one** of them carries
  /// the source's year, so a wrong claim matching nothing, or matching two
  /// rows, leaves the refusal in place.
  ///
  /// A hit reached through [shortenedQueries] or through
  /// [IgdbClient.searchAlternativeNames] faces string identity instead of
  /// [minAutoScore]. Both fire only where IGDB could not find the title at
  /// all, so a fallback form that comes back with something scoring 0.9
  /// against the spine has, by construction, found a title IGDB holds that is
  /// **not** the spine's -- which is the definition of a sibling.
  ///
  /// **[minAutoScore] cannot do this job, and since T-0095 it demonstrably
  /// does not.** Re-measured live with hints hand-written to the band so the
  /// platform gate is out of the way: `そらのは 真` -> Path of Ember: True **1.000**
  /// (right game, and identity only because the candidate is trimmed),
  /// `そらのは 真2` -> Path of Ember: True **0.857** (wrong sibling, one character of
  /// title away), `そらのは 真3 そらのは3 別伝 Grey Tides` -> Path of Ember: True 3 &
  /// Grey Ties **0.852** (right game). The wrong answer now outscores a right
  /// one and both straddle 0.85, so no threshold on this metric separates
  /// them -- a 6-character Japanese title spends 0.143 on one character, while
  /// a 30-character Latin title differing by one digit scores 0.967.
  ///
  /// So the bar is 1.000: one of the spine's own spellings equal to a name
  /// IGDB knows the game under. The price is the 0.852 row, refused although
  /// it is right; against it, T-0002 spent a whole task removing eleven
  /// confident wrong matches and this is the door they would come back
  /// through. On `CONTROL-HIRES` as it actually reads the price is zero: the
  /// hint on all four is `PS2` (T-0029), so no retry hit passes
  /// [platformAgreement] either way.
  ///
  /// **The third rejection is [volumeNumbersAgree], and it is what actually
  /// separates the two siblings** (T-0100). The identity bar above refuses the
  /// 0.857 row only for as long as it arrives through the retry: let IGDB
  /// answer `そらのは 真2` with anything at all -- one indexing change on a
  /// third party's catalogue -- and `fromFallbackQuery` is false, 0.857 clears
  /// [minAutoScore], and the wrong sibling auto-matches. Refusing it on the
  /// volume number instead holds whichever path it arrives by, and it does not
  /// touch the 0.852 row, whose numbers agree: that one stays a candidate for
  /// the human, refused by the identity bar and for the identity bar's reason.
  /// Measured cost on the auto-matches: none, on the hi-res set, the low-res
  /// set and the hand-corrected hints alike. It sinks nothing and hides
  /// nothing --
  /// IGDB holds no Japanese name for True 2, only Chinese ones, confirmed
  /// under T-0094 against the 12 games whose alternative names carry
  /// `そらのは`, so the sibling is the whole of what the review screen has to
  /// offer that row.
  ///
  /// Relaxing the identity bar to [minAutoScore] for retry hits whose volume
  /// numbers agree was measured here and not taken: it promotes exactly one
  /// row, the 0.852 above, and only under the corrected hints -- one example
  /// against the eleven confident wrong matches T-0002 removed, on a path that
  /// exists because IGDB could not find the title at all.
  static Candidate? _best(
      List<
              ({
                Candidate candidate,
                PlatformAgreement agreement,
                bool sameVolume
              })>
          scored,
      {required bool fromFallbackQuery, int? sourceYear}) {
    if (scored.isEmpty) return null;
    final top = scored.first;
    if (top.candidate.score < (fromFallbackQuery ? 1.0 : minAutoScore)) {
      return null;
    }
    if (top.agreement == PlatformAgreement.mismatch) return null;
    if (!top.sameVolume) return null;
    final ambiguous = scored.skip(1).any((entry) {
      if (entry.agreement == PlatformAgreement.mismatch) return false;
      if (entry.candidate.score != top.candidate.score) return false;
      if (entry.candidate.platformId != top.candidate.platformId) return true;
      return top.candidate.releaseYear == null ||
          entry.candidate.releaseYear != top.candidate.releaseYear;
    });
    if (!ambiguous) return top.candidate;
    return _separatedBySourceYear(scored, top, sourceYear);
  }

  /// The one tied row the source's own year names, or null for "refuse, as
  /// before" (T-0171). Reached only from the refusal above, which is what
  /// bounds the cost of a wrong year to a refusal that was already happening.
  static Candidate? _separatedBySourceYear(
      List<
              ({
                Candidate candidate,
                PlatformAgreement agreement,
                bool sameVolume
              })>
          scored,
      ({Candidate candidate, PlatformAgreement agreement, bool sameVolume}) top,
      int? sourceYear) {
    if (sourceYear == null) return null;
    final tied = [
      for (final entry in scored)
        if (entry.agreement != PlatformAgreement.mismatch &&
            entry.candidate.score == top.candidate.score)
          entry,
    ];
    if (tied.any((e) => e.candidate.platformId != top.candidate.platformId)) {
      return null;
    }
    final named = [
      for (final entry in tied)
        if (entry.sameVolume && entry.candidate.releaseYear == sourceYear)
          entry,
    ];
    return named.length == 1 ? named.single.candidate : null;
  }

  String _applyAliases(String lowerCasedTitle) {
    var t = lowerCasedTitle;
    aliases.forEach((alias, canonical) {
      t = t.replaceAll(alias, canonical);
    });
    return t;
  }

  static double _bestScore(Iterable<String> queries, String name) =>
      queries.map((q) => _score(q, name)).reduce(math.max);

  /// Normalized Levenshtein similarity, 0..1.
  ///
  /// A token-based metric (rapidfuzz `token_set_ratio`) was this task's
  /// original scope and the measurement withdrew it: across T-0008's
  /// detections, word order, subtitle noise and regional titles caused zero
  /// misses, all but one of the misses never reached the scorer at all (IGDB
  /// returned nothing), and the one row a token metric would move is a bundle
  /// it would probably get wrong. The platform, not the string, was the failure.
  ///
  /// **Surrounding whitespace is not part of a title, and IGDB stores some.**
  /// An alternative name of game 1100000003 is `" そらのは 真"` with a leading
  /// space, so the spine that reads exactly that scored `1 - 1/7 = 0.857`. The
  /// cost is a function of length, which is why it surfaced in Japanese: 0.143
  /// on a 6-character title, 0.03 on a 30-character Latin one. The query side
  /// arrives trimmed from [ResolverWorker.process]; the candidate side is
  /// IGDB's string as stored, and is the one this fixes.
  static double _score(String query, String candidateTitle) {
    final a = query.trim();
    final b = candidateTitle.trim().toLowerCase();
    if (a == b) return 1.0;
    if (a.isEmpty || b.isEmpty) return 0.0;
    final distance = _levenshtein(a, b);
    return 1.0 - distance / math.max(a.length, b.length);
  }

  static int _levenshtein(String a, String b) {
    var previous = List<int>.generate(b.length + 1, (i) => i);
    final current = List<int>.filled(b.length + 1, 0);
    for (var i = 1; i <= a.length; i++) {
      current[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        current[j] = math.min(
          math.min(current[j - 1] + 1, previous[j] + 1),
          previous[j - 1] + cost,
        );
      }
      previous = List<int>.from(current);
    }
    return previous[b.length];
  }
}

/// Pass-through resolver for keyless runs (the IGDB stage is optional --
/// see decision 0011, "BYOK"). Every detection comes back unresolved, exactly
/// as a failed resolution would, and the human fixes it during review.
///
/// It lives here rather than in a shell so the CLI and the Flutter app share
/// one implementation: "no IGDB credentials" must mean the same thing in
/// both. Both front ends pick it *instead of* a real [ResolverWorker], so
/// nothing is even asked of IGDB -- no Twitch token request, no search.
///
/// The default client refuses every request, so "zero IGDB traffic" is a
/// property of the type, not of how carefully callers use it. [igdbForTest]
/// exists only so a test can pass a counting fake and assert it stays at
/// zero (same seam as [IgdbClient.new]'s `client` parameter).
class SkipResolver extends ResolverWorker {
  SkipResolver({IgdbClient? igdbForTest})
      : super(igdbForTest ??
            IgdbClient(
              clientId: '',
              clientSecret: '',
              client: _RefusingClient(),
            ));

  /// Every kind, because this one answers any row and matches none of them.
  /// Overridden rather than inherited: [ResolverWorker]'s `{game}` is a claim
  /// about IGDB, and nothing here asks IGDB anything.
  @override
  Set<WorkKind> get answers => WorkKind.values.toSet();

  @override
  Future<ResolvedGame> process(Detection task) async =>
      ResolvedGame(detection: task);
}

/// Turns "this resolver must not do network I/O" from a convention into a
/// loud failure.
class _RefusingClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      throw StateError('SkipResolver must never perform network I/O '
          '(attempted ${request.method} ${request.url})');
}

/// Stage 3's seam: **which catalogue answers a row is a property of the row.**
///
/// Decision 0015 put `workKind` on the detection and named this the stage that
/// has to honour it. This is that stage, and it is a lookup rather than a
/// branch on purpose -- the difference is what the next catalogue costs.
///
/// A branch (`if (kind == movie) ... else ...`) is edited by every kind that
/// is added, so the third one edits code the second one wrote and the test for
/// the second is where the third breaks. A lookup is not edited at all: anime
/// arrives as one more entry in [catalogues], built by the shell that already
/// builds the clients, and nothing in this file moves. That is the whole of
/// the claim -- a seam is a thing you *pass* an implementation to, and the
/// test for it is whether adding one requires editing it.
///
/// **It extends [ResolverWorker] rather than being a plain [Worker] only
/// because `Orchestrator.resolverWorker` is typed [ResolverWorker].** That is
/// the same accommodation [SkipResolver] makes, and it inherits the same
/// refusing IGDB client, so a router that somehow reached the network fails
/// loudly rather than resolving a film against IGDB. Widening the
/// orchestrator's field to `Worker<Detection, ResolvedGame>` would remove the
/// inheritance entirely and is the tidier shape; it was left alone because
/// `orchestrator.dart` is outside this task's brief.
class CatalogueRouter extends ResolverWorker {
  CatalogueRouter({required this.catalogues, required this.fallback})
      : super(IgdbClient(
          clientId: '',
          clientSecret: '',
          client: _RefusingClient(),
        )) {
    for (final entry in catalogues.entries) {
      final catalogue = entry.value;
      if (catalogue is CatalogueWorker &&
          !catalogue.answers.contains(entry.key)) {
        throw ArgumentError.value(
            catalogue.runtimeType.toString(),
            entry.key.key,
            'this catalogue answers ${catalogue.answers.map((k) => k.key)} '
                'and would answer this kind with an id for one of those '
                'instead');
      }
    }
  }

  /// The catalogue for each kind. A kind absent here goes to [fallback].
  ///
  /// **A [CatalogueWorker] here must answer the kind it is filed under, and
  /// the constructor throws rather than asserts** (T-0369). A wrong entry is a
  /// shell's typo, so it is a developer error and [ArgumentError] is what that
  /// is; an `assert` would be stripped from a release build, which is the one
  /// build where a wrong id reaches somebody's collection file. It cannot be
  /// caught later either -- an anime series answered from the film endpoint
  /// carries a `tmdb:` id like the right one, and decision 0016's namespace
  /// check in `TonkatsuExporter` compares namespaces.
  ///
  /// A plain [Worker] states nothing and is checked against nothing: a test
  /// double that answers a label is not claiming to be a catalogue. What
  /// closes that gap for the two shells is that they build this map with
  /// [registrationsOf], which cannot produce a mismatched entry, and a test
  /// per shell asserts they do.
  final Map<WorkKind, Worker<Detection, ResolvedGame>> catalogues;

  /// The kinds this router has a catalogue for. Not [ResolverWorker]'s
  /// `{game}`, which would be a claim about an IGDB client this class holds
  /// only to satisfy its supertype and never calls.
  @override
  Set<WorkKind> get answers => catalogues.keys.toSet();

  /// What answers a kind no catalogue is registered for.
  ///
  /// Required rather than defaulted, because both plausible defaults are wrong
  /// in a way that hides itself: resolving an unknown kind against IGDB
  /// matches films to games, and silently returning no match makes a missing
  /// registration look like a catalogue miss. The shell knows which it means
  /// and has to say.
  final Worker<Detection, ResolvedGame> fallback;

  /// Delegates to [Worker.process], not [Worker.run].
  ///
  /// The retry policy is applied once, by whichever `run` called this -- the
  /// orchestrator's. Calling the delegate's `run` here would nest one backoff
  /// schedule inside another and turn four attempts into sixteen, each of the
  /// inner ones sleeping. The cost is that a delegate's own `maxRetries` and
  /// `backoffBase` are not honoured: every catalogue on this seam retries on
  /// this class's schedule, which is [ResolverWorker]'s.
  @override
  Future<ResolvedGame> process(Detection task) =>
      (catalogues[task.workKind] ?? fallback).process(task);
}

/// A film or series detection to a TMDB match (T-0162, T-0369).
///
/// **One worker, two endpoints, and which one it is is fixed at
/// construction.** [TmdbResolverWorker.movies] searches films and
/// [TmdbResolverWorker.series] searches television; everything between the
/// request and the [Candidate] is the same code on both, which is deliberate.
/// The tv search has never been run against the service, so the smaller the
/// unrun surface the better: it is one path, three response keys and one
/// query parameter ([TmdbSearch]), and no scoring, gate or retry of its own.
///
/// Reuses [ResolverWorker]'s scorer and [minAutoScore] deliberately: the
/// measured behaviour of the Levenshtein scorer is not a property of IGDB, and
/// a second threshold would be a second thing to tune with nothing measured
/// behind it.
///
/// **What it does not reuse is the platform gate**, because a film has no
/// platform. `platformAgreement`, `volumeNumbersAgree` and the cross-band tie
/// rule all exist to make a guess about a console safe, and none of them has
/// anything to say here. What replaces the gate as the second signal is the
/// release year: a filename carries one far more often than a spine does, and
/// two films sharing a title are separated by it almost by definition.
class TmdbResolverWorker extends CatalogueWorker {
  /// TMDB's film search: [WorkKind.movie], and [WorkKind.animationFilm] with
  /// it. An anime film is a film in TMDB -- that catalogue has no separate
  /// animation database, and the only thing that makes the row an anime is
  /// what Tonkatsu writes in `platform_id` (T-0162, decision 0016).
  TmdbResolverWorker.movies(this.tmdb) : search = TmdbSearch.movie;

  /// TMDB's television search: [WorkKind.animationSeries] and nothing else.
  ///
  /// Not [WorkKind.movie] and not [WorkKind.animationFilm], which is the
  /// whole point of there being two constructors. And not
  /// [WorkKind.animation]: that kind is the film-or-series question still
  /// unanswered, so neither endpoint is the right one for it and picking
  /// either would answer a question the person has not.
  TmdbResolverWorker.series(this.tmdb) : search = TmdbSearch.series;

  final TmdbClient tmdb;

  /// Which endpoint this worker asks. Fixed at construction rather than
  /// derived per row from `task.workKind`: deriving it would put the
  /// kind-to-endpoint mapping inside this class, where no shell and no test
  /// can see what it registered, and the mapping is exactly the thing that
  /// has to be visible.
  final TmdbSearch search;

  @override
  Set<WorkKind> get answers => switch (search) {
        TmdbSearch.movie => const {WorkKind.movie, WorkKind.animationFilm},
        TmdbSearch.series => const {WorkKind.animationSeries},
      };

  @override
  Future<ResolvedGame> process(Detection task) async {
    final raw = task.rawTitle.trim();
    if (raw.isEmpty) return ResolvedGame(detection: task);

    final year = task.sourceYear;
    var hits = await tmdb.search(search, raw, year: year);

    // The film-shaped zero-result retry, and the second one on this seam
    // (T-0336). TMDB's `year` is a filter rather than a preference -- measured
    // live, see [TmdbClient.search] -- so a filename year one off the
    // catalogued one answers zero rows instead of the film, and the comment
    // that used to rule that out named the very case that causes it: a
    // festival release against a general one, a territory date.
    //
    // Shaped after [ResolverWorker.process]'s two fallbacks in the one respect
    // that matters: it fires ONLY where the first query found nothing at all,
    // so the cost is one extra request on rows that were already lost, and
    // none on any row that resolved. There is nothing to drop when the
    // filename carried no year, so that row asks once and stops.
    var withoutYear = false;
    if (hits.isEmpty && year != null) {
      hits = await tmdb.search(search, raw);
      withoutYear = hits.isNotEmpty;
    }
    if (hits.isEmpty) return ResolvedGame(detection: task);

    final folded = raw.toLowerCase();
    final queries = {folded, stripLegalMarks(folded)};

    final scored = [
      for (final hit in hits)
        (hit: hit, score: _scoreOf(queries, hit)),
    ]..sort((a, b) => b.score.compareTo(a.score));

    return ResolvedGame(
      detection: task,
      best: _bestFilm(scored, year, withoutYear: withoutYear),
      candidates: [
        for (final entry in scored)
          _candidate(entry.hit, entry.score,
              alternative: _matchedOriginal(queries, entry.hit)
                  ? entry.hit.originalTitle
                  : null,
              withoutYear: withoutYear)
      ],
    );
  }

  /// The better of the two names TMDB gives a film.
  ///
  /// A release filename is often the original-language name while TMDB's
  /// canonical title is the localised one, so scoring only the canonical form
  /// loses the match without saying so -- the same reason
  /// [ResolverWorker.process] scores IGDB's alternative names.
  static double _scoreOf(Set<String> queries, TmdbHit hit) => math.max(
        ResolverWorker._bestScore(queries, hit.title),
        hit.originalTitle == null
            ? 0.0
            : ResolverWorker._bestScore(queries, hit.originalTitle!),
      );

  /// Whether the original-language title is what actually matched, so review
  /// can show it rather than leaving a match nobody can check.
  static bool _matchedOriginal(Set<String> queries, TmdbHit hit) =>
      hit.originalTitle != null &&
      ResolverWorker._bestScore(queries, hit.originalTitle!) >
          ResolverWorker._bestScore(queries, hit.title);

  static Candidate _candidate(TmdbHit hit, double score,
          {String? alternative, required bool withoutYear}) =>
      Candidate(
        externalId: '$tmdbCatalogue:${hit.tmdbId}',
        title: hit.title,
        score: score,
        matchedAlternativeName: alternative,
        releaseYear: hit.releaseYear,
        // Every row of a retry is a row the year could not corroborate, not
        // just the one that wins, so the mark is on the list and not on the
        // pick: a human choosing among five candidates is owed the same fact
        // the auto-match gate acted on.
        matchMethod:
            withoutYear ? MatchMethod.yearlessRetry : MatchMethod.fuzzy,
      );

  /// The auto-match, or null for the human.
  ///
  /// Two gates, and the second is the film-shaped half of the tie rule. A
  /// score below [minAutoScore] is never automatic -- [ResolverWorker]'s rule
  /// unchanged. A top score TIED with the runner-up is refused **unless the
  /// detection carried a year and exactly one of the tied films matches it**:
  /// a remake shares its title with its original exactly and scores 1.000
  /// against it, and the year is the only thing separating the two. Refusing a
  /// tie the year could have settled is what T-0165 measured as the cost of a
  /// gate that cannot see the year, on the games side.
  ///
  /// **[withoutYear] withdraws the tie-break, and withdraws nothing else**
  /// (T-0336). A hit reached only after the year was dropped has had the
  /// year's corroboration taken out from under it: TMDB has just answered that
  /// no film of this title carries the year the filename claims. So the one
  /// gate that spends the year is the one that cannot be trusted to hold, and
  /// the score has to stand on its own -- exactly one film at the top, at or
  /// above [minAutoScore], or the human decides.
  ///
  /// **The IGDB retry's identity bar is deliberately NOT copied here**, and
  /// the reason is that the two retries loosen different things.
  /// [ResolverWorker]'s ladder shortens the query STRING, so a retry hit
  /// scoring high against the whole spine has by construction found a title
  /// that is not the spine's -- a sibling -- and 1.000 is the only honest bar
  /// for it. This retry changes no character of the query: the title asked for
  /// is the title asked for the first time. Demanding 1.000 would answer a
  /// question this retry never raised, and would admit precisely the row that
  /// is dangerous -- three films sharing one title all score 1.000, and the
  /// year that used to separate them is exactly what has just been spent. The
  /// risk sits in the tie, so the tie is what closes.
  ///
  /// Two alternatives were weighed and not taken. **Refusing every retry hit**
  /// leaves the case the retry exists for -- one film, one title, a year off
  /// by one -- as a row the human must approve by hand, which is barely better
  /// than the silence it replaces. **Raising the score bar** instead of
  /// closing the tie fails for the reason this class reuses [minAutoScore] at
  /// all: there is nothing measured behind a second number.
  ///
  /// The score itself is untouched either way. It measures two strings, both
  /// queries send the same one, and a fact about the match belongs on
  /// [MatchMethod] -- where the argument for that split already is.
  static Candidate? _bestFilm(List<({TmdbHit hit, double score})> scored,
      int? year, {required bool withoutYear}) {
    final top = scored.first;
    if (top.score < minAutoScore) return null;

    final tied =
        scored.where((e) => (e.score - top.score).abs() < 1e-9).toList();
    if (tied.length == 1) {
      return _candidate(top.hit, top.score, withoutYear: withoutYear);
    }

    if (withoutYear || year == null) return null;
    final byYear = tied.where((e) => e.hit.releaseYear == year).toList();
    if (byYear.length != 1) return null;
    return _candidate(byYear.first.hit, byYear.first.score,
        withoutYear: false);
  }
}
