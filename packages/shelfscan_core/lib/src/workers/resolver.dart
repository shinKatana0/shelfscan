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

/// Yield shorter leading prefixes of a query, longest first, when the full
/// title returns no IGDB hit. Halving the token count bounds API requests;
/// a returned candidate is still scored against the original title. Treat a
/// digit as a token boundary even without a space, and preserve the query's
/// original spacing and punctuation in each prefix.
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

/// Below this score, a match remains a candidate for human review. A single
/// edit-distance threshold cannot distinguish all close titles, especially
/// across scripts and title lengths. Platform and volume checks provide the
/// independent gates before a candidate becomes the best match.
const minAutoScore = 0.85;

/// How a candidate's platform relates to the hint read off the case.
enum PlatformAgreement {
  match,
  mismatch,

  /// The detection carries no hint, so nothing about the platform is claimed.
  unknown,
}

/// Compare a case's platform hint with a candidate. A mapped hint already
/// constrains the search by platform ID. An unmapped family hint still narrows
/// by platform name without pretending to identify one console. A family
/// hint can agree with more than one generation of that console.
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

/// Require Arabic volume numbers in a detection and candidate to agree in
/// order. Edit distance alone can rank the wrong numbered sibling highly,
/// especially for short titles. This is a refusal gate, never an additional
/// reason to accept. Roman numerals remain in the separate title rules;
/// full-width digits are normalized to their Arabic equivalents.
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

  /// Join a store product ID to IGDB before title search. An exact external
  /// ID establishes game identity, but it does not establish platform: use
  /// the detection's platform hint and auto-match only when exactly one hit
  /// agrees. Otherwise retain the candidates for human review. If the ID is
  /// unknown to IGDB, return null and run the ordinary title resolver.
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

  /// Choose an automatic match only when independent checks agree. Refuse a
  /// candidate that contradicts the platform hint, and refuse equally scored
  /// candidates that disagree on platform. On one platform, a tie can stand
  /// only when release years agree; a source year may separate a tie when
  /// exactly one candidate matches it. Source years break ties but never filter
  /// the search, because a filename's year can describe something other than
  /// the release.
  ///
  /// A hit found through a shortened query or alternative name must still
  /// satisfy title identity, and numbered volumes must agree. IGDB's ordering
  /// is not evidence: a tie left unresolved goes to human review.
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
  /// Token-based similarity was considered, but it cannot help when a
  /// catalogue returns no candidate and may overmatch bundled editions.
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
/// the second is where the third breaks. A lookup is not edited at all: a
/// catalogue arrives as one more entry in [catalogues], built by the shell that
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
/// `orchestrator.dart` was outside the scope of the change that added it.
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
  /// caught later either -- an animated series answered from the film endpoint
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
  /// it. An animated film is a film in TMDB -- that catalogue has no separate
  /// animation database, and the only thing that separates the row from a
  /// live-action one is what Tonkatsu writes in `platform_id` (T-0162,
  /// decision 0016). Not [WorkKind.anime]: that is a different upstream type
  /// keyed by AniList or Kitsu, and TMDB answers neither (T-0456).
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
