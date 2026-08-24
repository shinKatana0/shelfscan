/// Minimal IGDB client (via Twitch OAuth client-credentials flow).
///
/// Register a Twitch application to obtain client id/secret:
/// https://api-docs.igdb.com/#getting-started
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../http_timeout.dart';
import '../unreachable.dart';
import '../workers/base.dart';

const _tokenUrl = 'https://id.twitch.tv/oauth2/token';
const _igdbUrl = 'https://api.igdb.com/v4';

/// IGDB's documented ceiling (https://api-docs.igdb.com/#rate-limits), and
/// what [IgdbClient] holds itself to regardless of how many lanes call it.
///
/// Exceeding it lost nothing and was not free. Measured against live IGDB
/// 2026-08-15 on the hi-res control document, this client counting its own
/// requests (T-0064). Every request count here is a multiple of the document's
/// rows and no wall clock is stated at all: a request is one per row, so a
/// count of either -- or a duration divided by the rate below -- is the size
/// of a private collection (T-0246, T-0266).
///
/// | | searches | 429 | busiest rolling second |
/// |---|---|---|---|
/// | 8 lanes, unlimited (old default) | 1.16 x rows | 0.16 x rows | **24** |
/// | 8 lanes, this limit | **1.00 x rows** | **0** | 4 |
/// | 4 lanes, this limit | **1.00 x rows** | **0** | 4 |
///
/// `Worker.run` retries a 429, so all three resolved every row and wrote
/// byte-identical documents -- which is why the defect never showed in a run's
/// own summary. What it cost was that sixth of the run in refused requests off
/// a personal Twitch application quota (BYOK, decision 0011), on a burst six
/// times the documented rate; T-0064's brief measured the same shape worse on
/// a worse day.
///
/// Holding the rate costs wall clock and nothing else, and that cost is
/// arithmetic rather than overhead: one request per row cannot start faster
/// than 4 a second, so the floor is the row count over that rate and it grows
/// with the collection. Bursting finished under that floor. The brief expected
/// the fix to be free because its two lane rows came out the other way round
/// -- that ordering is a function of how many 429s the day hands out and did
/// not reproduce here.
const igdbRequestsPerSecond = 4;

/// Keys are hints uppercased with spaces stripped, so a spelling the model
/// actually produces has to be a key of its own -- T-0021 measured Switch
/// cases answering `NINTENDO SWITCH` (the branding as printed) on every row,
/// which `SWITCH` alone does not match, silently dropping the platform filter.
/// Full list: https://api-docs.igdb.com/#platform
///
/// A hint maps to every console it can mean, not to one. The model reads the
/// branding and answers `SWITCH` off a **Nintendo Switch 2** band as readily as
/// off a Switch 1 one -- a `SWITCH` hint in the hi-res control run may have
/// been read off either band, checked against the photographs -- so a hint
/// that means one of two consoles has to be filtered as one of two. Verified
/// live 2026-08-15: **130 Nintendo Switch, 508 Nintendo Switch 2.**
///
/// Constraining `SWITCH` to 130 alone returned **0 rows** for
/// `solar pilgrim vii resurge` and `solar pilgrim vii remake interbloom`,
/// which IGDB lists on 508 and not on 130 -- a wrong filter costing the human
/// a candidate they could have picked.
///
/// `SWITCH` stays a union until the vision stage can tell the two bands apart,
/// and T-0074 measured that it cannot: thirteen prompt wordings, none of which
/// got the printed `2` into a hint without answering it for Switch 1 cases too
/// (table on [detectionPromptRules]). What narrowing would be worth is not in
/// doubt -- both halves re-measured live at concurrency 2, 2026-08-15, on the
/// same detections, every row checked against the photographs. The bucket
/// counts are in the control record (doc/control-set.md); what they say is:
///   as it ships, `SWITCH` -> (130,508): none wrong. The candidates-only rows
///     are ties the T-0002 rule correctly refuses -- Switch-family titles
///     IGDB lists on both bands -- plus the Moonlight bundle, which is a
///     title problem and not a platform one.
///   hints hand-written to the band, `SWITCH` -> {130}: **more of them
///     auto-matched correctly, still none wrong**, and そらのは 真 resolves to
///     Path of Ember True on Nintendo Switch 2 for free.
/// Narrowing without the read is the pre-T-0023 state and was measured there:
/// one more auto-match than as it ships, and **one of them wrong**. It buys
/// that auto-match by re-admitting the wrong-console guess this project spent
/// T-0002 and T-0023 removing, so the union stays.
///
/// **`PC` is the one hint that is a single id, and it is one for T-0023's own
/// reason** (T-0156). IGDB splits the desktop into 6 PC (Microsoft Windows),
/// 3 Linux, 14 Mac and 13 DOS, and a GoG catalogue crosses all four -- but a
/// desktop union meets the T-0002 tie rule far harder than the Switch one
/// does, because here it is one *game* that is listed on each of them: its
/// rows carry one title, so one score, differing only in platform id, which is
/// exactly what `ResolverWorker._best` refuses to guess between. Measured
/// 2026-08-16 by replaying one live answer per title through the resolver
/// under each mapping, so both see identical rows:
///
/// | mapping | 8 GoG-typical titles | 6 DOS-era classics |
/// |---|---|---|
/// | `{6}` | **every row auto-matched, no tie** | **auto-matched but one, which
///   had no candidates** |
/// | `{6,3,14}` | one auto-matched, the rest **ties** | -- |
/// | `{6,13}` | -- | one auto-matched, the rest **ties** |
///
/// Each union buys exactly one row and loses several, and the one it
/// buys is the only kind the narrow mapping can lose: a title IGDB does not
/// list on 6 at all. There were none of those in the first group (nothing is
/// on Linux or Mac and not on Windows) and one in the second -- Mire II,
/// which `(6)` answers with
/// 0 rows, so that row reaches review with no candidates rather than sunk
/// ones: the query never asks for DOS. It is the same arithmetic that made
/// `SWITCH` a union and it comes out the other way: there the union rescued
/// rows IGDB had answered with nothing and removed the last wrong auto-match,
/// for a handful of ties; here it rescues one for several.
///
/// The gate also narrows less here, which the scoring has to carry: over the
/// same queries the filter leaves **four fifths** of the games the unfiltered
/// search returned, against under a third for `PS5` -> {167} (report T-0156).
///
/// **The four T-0168 could not name, read off `platforms` live 2026-08-16**,
/// one request for the whole 220-row listing: `37 Nintendo 3DS`,
/// `137 New Nintendo 3DS`, `20 Nintendo DS`, `159 Nintendo DSi`, `41 Wii U`,
/// `46 PlayStation Vita`. Nothing in the listing is a second Wii U or a second
/// Vita, so those two are one id and the question does not arise; the handhelds
/// are each a pair, and the pair is the T-0023 trade again -- with the opposite
/// answer to `PC` because the overlap is tiny rather than universal. **Of
/// IGDB's 99 games on 137, 37 are also on 37; of the 698 on 159, 40 are also on
/// 20** -- 1.6% and 1.0% of those catalogues, where a desktop game is on 6 and
/// 3 and 14 as a matter of course. Replayed through the real `ResolverWorker`
/// against live IGDB the same day, one search per title per mapping:
///
/// | | `{37}` / `{20}` | union |
/// |---|---|---|
/// | 8 3DS titles | 7 auto, 1 lost | **7 auto**, 1 cross-id tie |
/// | 6 DS cartridge titles | **6 auto** | 5 auto, 1 cross-id tie |
/// | 4 DSiWare titles | **0 auto** (2 none, 2 junk) | **4 auto** |
///
/// The 3DS row is a straight swap and the failures are not equal: the narrow
/// mapping loses `super nebulae` to five wrong candidates (its only 3DS-family
/// listing is 137), while the union costs `starweave chronicles 3d` a tie
/// between the same title on 37 and on 137 -- one tap, and no wrong game
/// reachable. The DS row is not a swap at all: `flipnote studio`, `x-scape`,
/// `mighty milky way` and `dr mario express` are on 159 and not on 20, so
/// `{20}` answers a real `.nds` dump with nothing or with junk.
///
/// No `NEW3DS` or `DSI` key, unlike `SWITCH2`: that one exists because it is a
/// hint this pipeline has been measured answering, and these two are not.
/// Nothing here has measured a name or a case that prints "New Nintendo 3DS".
///
/// **`VITA` has no container behind it and is here for the vision path**
/// (T-0168 lists it for a Vita half of `.pkg`/`.vpk`, and both of those decline
/// on purpose). Without a key, `PS VITA` -- the branding as a case prints it,
/// which is the spelling T-0021 measured the model answering on every row for
/// the Switch -- folds to the words {ps, vita}, which is not a subset of
/// {playstation, vita}, so `platformAgreement` returns `mismatch` on every
/// candidate and the row resolves to nothing. That is T-0156's failure already
/// shipping, and three keys close it.
const platformIds = <String, Set<int>>{
  'NES': {18}, 'SNES': {19}, 'N64': {4}, 'GB': {33}, 'GBC': {22}, 'GBA': {24},
  'GAMECUBE': {21}, 'WII': {5},
  'SWITCH': {130, 508}, 'NINTENDOSWITCH': {130, 508},
  'SWITCH2': {508}, 'NINTENDOSWITCH2': {508},
  'PS1': {7}, 'PS2': {8}, 'PS3': {9}, 'PS4': {48}, 'PS5': {167}, 'PSP': {38},
  'GENESIS': {29}, 'MEGADRIVE': {29}, 'SATURN': {32}, 'DREAMCAST': {23},
  'XBOX': {11}, 'XBOX360': {12},
  // Three spellings because no model reads these off a case: a GoG or
  // installer source (T-0157, T-0158) writes the hint itself, and a store
  // name is not one of them -- `GOG` would reach no platform and
  // `platformAgreement` would refuse every candidate the row has.
  'PC': {6}, 'WINDOWS': {6}, 'PCWINDOWS': {6},
  '3DS': {37, 137}, 'NINTENDO3DS': {37, 137},
  'DS': {20, 159}, 'NINTENDODS': {20, 159},
  'WIIU': {41}, 'NINTENDOWIIU': {41},
  'VITA': {46}, 'PSVITA': {46}, 'PLAYSTATIONVITA': {46},
};

/// `Detection.sourceId` namespace -> the IGDB `external_games` source that
/// holds that store's product ids (T-0159).
///
/// **The premise, verified live 2026-08-16 against `external_game_sources`:
/// GOG is source `5`.** The endpoint answers 22 sources, `1 Steam`, `3
/// GiantBomb`, **`5 GOG`**, `26 Epic Games Store`, `36 Playstation Store US`
/// and so on, and a GOG row carries the store's own product id as `uid`:
/// `1100000013` -> game 1100000019, Kaldreth: Book II. The deprecated `category`
/// field still answers `where category = 5` with the same rows; the query here
/// asks for `external_game_source` because that is the field IGDB now returns.
///
/// One entry, because one source in this product writes a `sourceId`
/// (`GogMetadataSource.idPrefix`). A namespace that is not a key here is not an
/// error -- the row simply resolves the ordinary way, which is also what a
/// future store gets until its number is measured and added.
///
/// **A GOG row carries no `platform`** -- absent on all 10 sampled and on all
/// 394 joined below -- so the platform for the `.xcoll` row comes from the
/// joined game and never from this endpoint (`ResolverWorker.process`).
const externalGameSources = <String, int>{'gog': 5};

/// Removes the legal marks a game case prints on its title. Three of the five
/// make IGDB's `search` return nothing at all.
///
/// Measured against live IGDB 2026-08-15, one mark injected into
/// `solar pilgrim xii the cinder age` under a `SWITCH` filter, which returns
/// 1 hit clean: ® U+00AE **0**, © U+00A9 **0**, ℗ U+2117 **0**, ™ U+2122 1,
/// ℠ U+2120 1. The hi-res detections that carried a ® returned nothing for
/// that reason alone -- a third of that run's misses -- and every one of them
/// now auto-matches the right game.
///
/// ™ and ℠ go too, though 9 titles carrying one returned the same hit count
/// and the same top hit either way: whether a title carries a mark at all is
/// the first-ask/repeat difference in the vision model, and it also costs
/// Levenshtein distance, so leaving them in leaves the resolver's answer
/// depending on whether that server process had already been asked for this
/// photo. T-0053 recorded the condition as a freshly loaded model and T-0086
/// measured that wrong: the prompt cache decides it, and an unload correlates
/// only because it drops the cache with the model (run counts and cache
/// figures on `OllamaVisionProvider`). Ollama unloads an idle model after 5
/// minutes, so two scans an hour apart are two first asks and the marks come
/// back.
///
/// Folded to a space rather than deleted, and only these five characters are
/// touched, so that [titleKey] -- which folds every punctuation run to a space
/// -- gives the same key before and after. `legal_marks_test.dart` pins that
/// over the control run's raw titles; it is what stops this drifting into a
/// second, disagreeing normalization (T-0056's defect class).
///
/// Deliberately NOT the whole of [titleKey]: folding every punctuation run
/// takes `solar pilgrim x/x-2 hd remaster` to `solar pilgrim x x 2 hd
/// remaster`, which returns **0 hits** where the slashed form returns the
/// right game. Phrase structure is load-bearing for this endpoint.
String stripLegalMarks(String title) => title
    .replaceAll(_legalMarks, ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

final _legalMarks = RegExp('[®©℗™℠]');

/// Characters that mean something to IGDB's `where ... ~ *"..."*` rather than
/// to the title: the quote ends the pattern, the star widens it.
final _patternMeta = RegExp(r'["*]');

/// A resolve request that ran out of time (T-0104).
///
/// Its own class rather than a reuse of the vision vocabulary, because the two
/// halves of that vocabulary are a key and a model id and this path has
/// neither: what it carries is which of the two hosts a resolve talks to went
/// quiet. Only the frame is shared ([timedOutMessage]), which is the whole of
/// what T-0105 is filed about.
///
/// Not retryable, and the arithmetic is the resolver's rather than the vision
/// pool's: `Worker` would turn one stalled row into 4 x 20 s + 14 s = 94 s, and
/// a stall that is the endpoint rather than the row multiplies that by every
/// detection in the document, divided by `resolverConcurrency` -- so a real
/// hi-res document waits out that stall row by row, in a run that has already
/// been told the answer.
class IgdbTimeoutException implements Exception {
  IgdbTimeoutException(this.service, this.endpoint, this.waited);

  /// `IGDB` for a search, `Twitch` for the OAuth token: two different hosts,
  /// and naming the wrong one sends the user to the wrong status page.
  final String service;
  final String endpoint;
  final Duration waited;

  String get message => timedOutMessage(
        service: service,
        endpoint: endpoint,
        waited: waited,
        advice: 'A search answers in milliseconds and this client already holds '
            'itself to $igdbRequestsPerSecond a second, so silence for that '
            'long is the endpoint or the network in front of it rather than a '
            'slow query. The scan is unaffected -- this stage only adds '
            'canonical ids to titles that have already been read.',
      );

  @override
  String toString() => message;
}

/// The two hosts a resolve talks to.
///
/// They are not interchangeable and the distinction is the whole reason this
/// exists: they run on separate infrastructure with separate status pages, and
/// a sentence that names the wrong one is worse than a raw body, because it
/// looks authoritative. [IgdbTimeoutException] makes the same distinction with
/// bare strings (T-0104); this carries the endpoint with the name so a new
/// sentence cannot pair one host with the other's URL.
enum IgdbHost {
  twitch('Twitch', _tokenUrl),
  igdb('IGDB', _igdbUrl);

  const IgdbHost(this.service, this.endpoint);

  /// Leads every sentence, as `service` does in [visionApiMessage].
  final String service;
  final String endpoint;
}

/// Where both halves of the credential pair are managed. Same URL as the app's
/// `twitchConsoleUrl`, repeated rather than shared: `shelfscan_core` may not
/// import `app/` (ARCHITECTURE.md platform boundary).
const _twitchConsole = 'https://dev.twitch.tv/console/apps';

/// What a resolve failure costs, said in every sentence that reports one.
///
/// It is the least obvious thing about this whole stage and it is the part
/// that decides whether the user has to do anything at once: the photographs
/// have already been read, and `Orchestrator.runResolve` degrades a failure to
/// an unresolved row rather than losing it.
const _rowsSurvive = 'Nothing read off the photographs is lost: this stage only '
    'adds canonical ids, so the row is in the review unmatched and can be '
    'matched by hand there.';

/// The credentials, named the way each surface names them.
const _checkBothHalves = 'Check the IGDB client id and secret you configured -- '
    'IGDB_CLIENT_ID and IGDB_CLIENT_SECRET for the CLI, the two IGDB fields in '
    'Settings for the app.';

/// A non-2xx answer from one of the two hosts (T-0107).
///
/// Its own class rather than a [VisionApiException] carrying an IGDB sentence,
/// for the reason [OllamaUnreachableException] is not one either: the app reads
/// that type to decide whether to offer a route into the vision half of
/// Settings (`_settingsCanFix`, T-0102), and a failed resolve offering to fix a
/// vision key is a worse answer than none.
class IgdbApiException implements Exception {
  IgdbApiException(
    this.message, {
    required this.host,
    required this.statusCode,
    required this.body,
  });

  final String message;
  final IgdbHost host;
  final int statusCode;

  /// The raw answer, kept for a bug report and deliberately kept out of
  /// [message]: it is what the user used to be given instead of an
  /// explanation.
  final String body;

  @override
  String toString() => message;
}

/// The same explanation for the one status `Worker.run` retries.
///
/// A [RetryableException] subclass so `Worker.run`'s policy is untouched, and
/// [toString] so the line that finally reaches the user once the four attempts
/// are spent is the sentence rather than `RetryableException: IGDB rate limit`
/// -- which is T-0072's defect class with a different body in it.
///
/// Nothing on the token path may ever be one of these, and that is a guard
/// rather than an omission: T-0144 remembers the first token failure, so a
/// retryable token error would make every row sleep `Worker`'s 14 s to be
/// handed the same cached error with no request going out. The token retries
/// where the status is known instead ([_tokenRetryable]).
class RetryableIgdbException extends RetryableException {
  RetryableIgdbException(super.message);

  @override
  String toString() => message;
}

/// Neither host answered at all: no status, no body (T-0107).
///
/// An [UnreachableEndpoint], with the vision classes T-0105 folded it into: the
/// app asks one question of all three and gets `false` from this one, because
/// both of these hosts are fixed in the build.
///
/// Not retryable, for the arithmetic on `VisionUnreachableException`: a refused
/// connection and a name that does not resolve are settled facts about the
/// network for as long as a scan lasts, and the resolve stage would
/// re-learn each of them once per detection -- every row of the hi-res control
/// set, each paying `Worker`'s 2+4+8 s of backoff.
class IgdbUnreachableException extends UnreachableEndpoint {
  IgdbUnreachableException(this.host, http.ClientException error)
      : reason = error.message;

  final IgdbHost host;

  @override
  String get endpoint => host.endpoint;

  /// Never: both hosts are constants in this file, and the credentials the user
  /// does own are not addresses. The app offering a Settings route here would
  /// point at the vision fields, which is the wrong half of Settings for a
  /// failed resolve.
  @override
  bool get endpointIsUserSet => false;

  /// `http.ClientException.message`, never `'$e'`: the toString carries the
  /// request URI and, on a refused connection, an ephemeral local port. Kept in
  /// parentheses at the end because it is the socket's sentence, localized into
  /// the OS display language, and can never be the one the user reads.
  final String reason;

  @override
  String get message =>
      'Cannot reach ${host.service} at ${host.endpoint} -- no answer came back, '
      'so neither the IGDB client id nor the secret is what failed. That '
      'address is fixed in this build rather than typed by you, so there is '
      'nothing to correct in your settings. $_checkOutsideThisApp '
      '$_rowsSurvive ($reason)';
}

/// The check that runs without this application (T-0354, extended here).
///
/// The vision family's other half -- `check that base URL first: it is yours
/// to set` -- has no counterpart on this path and is dropped rather than
/// reworded: both hosts are fixed in the build, so there is no address here a
/// user could have got wrong. The check survives the difference because a host
/// is nameable whether or not it is settable.
///
/// `at the lookup` where the vision copy says `at the scan`: this is the
/// resolve stage, and `resolve` is also a command of its own that scans
/// nothing. `any answer at all` because both of these are POST endpoints --
/// the search and the token request -- so a browser reaching either gets an
/// error page rather than anything friendly, and an error page is the host
/// answering.
const _checkOutsideThisApp =
    'Open that address in a browser on this device: any answer at all, even an '
    'error page, means the host is reachable from here. A browser refused the '
    'same way points outside this app rather than at the lookup -- usually '
    'this machine being offline, or a proxy or a firewall in the way.';

/// The exception for a non-2xx from either host.
///
/// The search's 429 is the only status `Worker.run` retries, and T-0143 kept it
/// that way: the token's 429 and 5xx are retried inside [IgdbClient] instead
/// ([_tokenRetryable]), so nothing here may make a token failure a
/// [RetryableException]. No sentence claims retries were spent unless they
/// were, which is why [igdbFailureMessage] splits 5xx by host.
Exception igdbFailure({
  required IgdbHost host,
  required int statusCode,
  required String body,
}) {
  final message = igdbFailureMessage(host: host, statusCode: statusCode);
  return host == IgdbHost.igdb && statusCode == 429
      ? RetryableIgdbException(message)
      : IgdbApiException(message,
          host: host, statusCode: statusCode, body: body);
}

/// What [statusCode] from [host] means for the person who registered the Twitch
/// application.
///
/// Shaped like [ollamaFailureMessage] and deliberately not a translation of
/// [visionApiMessage]: there is no model id here and no single key, and the two
/// things that actually break are halves of one credential pair issued by one
/// host and presented to another. So the axis this switch turns on is which
/// host answered, not only what it answered.
///
/// **No body is ever quoted, which is the one place this departs from both
/// vision vocabularies**, and it is not caution for its own sake:
/// - the token request carries `client_secret` in its own body, so an echo of
///   it is an echo of the credential, and 401/403 is the likeliest failure on
///   this path (BYOK, decision 0011 -- every user registers their own
///   application). [visionApiMessage] already refuses to quote those two
///   statuses for the weaker version of this reason, a key echoed back;
/// - IGDB's documented error shape is a JSON **array**
///   (`[{"title":"Unauthorized","status":401,"cause":"..."}]`), which
///   [providerDetail] cannot read: it finds no explanation field, falls back to
///   the body, and pastes it capped at 200 characters. A body nobody parsed is
///   a body nobody can promise carries no credential;
/// - nothing here has ever seen a real error body from either host. No IGDB or
///   Twitch credential was available, so every shape above
///   is documentation rather than measurement -- unlike T-0072's and T-0097's,
///   which were taken from live calls.
/// The body is on [IgdbApiException.body] for a bug report, exactly as the
/// vision ones are.
String igdbFailureMessage({
  required IgdbHost host,
  required int statusCode,
}) {
  final where = '${host.service} at ${host.endpoint}';
  final explanation = switch ((host, statusCode)) {
    // Twitch answers a client id it does not know with a 400 rather than a 401,
    // so this is the one status that can point at one half of the pair.
    (IgdbHost.twitch, 400) =>
      '$where refused the credentials (HTTP 400) before it issued a token. '
          'That is the client id it does not recognise rather than the secret: '
          'check IGDB_CLIENT_ID against the application at $_twitchConsole.',
    (IgdbHost.twitch, 401 || 403) =>
      '$where rejected the credentials (HTTP $statusCode): the client id and '
          'the secret are not a working pair for an application it knows. Both '
          'come from one application at $_twitchConsole, and a secret is shown '
          'once there and cannot be read back afterwards -- regenerate it if '
          'you are not certain of it. $_checkBothHalves',
    // The token was just issued and IGDB refused it: the commonest way to reach
    // this is a `Client-ID` from one application and a secret from another,
    // since the search sends the id and the token separately.
    (IgdbHost.igdb, 401 || 403) =>
      '$where rejected the access token (HTTP $statusCode) that Twitch had '
          'just issued for it. The likeliest cause is a client id and a secret '
          'from two different Twitch applications: the search sends the id and '
          'the token separately, and only IGDB sees that they disagree. Check '
          'both are from the same application at $_twitchConsole. '
          '$_checkBothHalves',
    // The query is this build's, not the user's: [_games] assembles it and the
    // only user-supplied part is the title read off a spine.
    (IgdbHost.igdb, 400) =>
      '$where rejected the query (HTTP 400). That query is built by this build '
          'rather than typed by you, so there is nothing to correct in your '
          'credentials -- an unusual spine read is the likeliest trigger, and '
          'the title that produced it is worth reporting.',
    (_, 404) => '$where answered HTTP 404, so nothing at that address is '
        'serving the API this build asks for. That URL is fixed in this build '
        'rather than typed by you, so there is nothing to correct in your '
        'settings: a proxy or a captive portal in between is the likeliest '
        'thing, and the endpoint having moved is the other.',
    (IgdbHost.igdb, 429) =>
      '$where is rate-limiting the search (HTTP 429) and the retries did not '
          'clear it. This client already holds itself to $igdbRequestsPerSecond '
          'requests a second, so a 429 usually means something else is using '
          'the same Twitch application at the same time. Wait, and resolve '
          'again later.',
    (IgdbHost.twitch, 429) =>
      '$where is rate-limiting the token request (HTTP 429) and the retries did '
          'not clear it. Every row of this resolve needs that one token, so '
          'none of them was searched for. Wait, and resolve again later.',
    // Split by host because only one of the two is retried (T-0143): the token
    // is asked once per run, the search once per detection.
    (IgdbHost.twitch, >= 500) =>
      '$where failed on its own side (HTTP $statusCode) and the retries did not '
          'clear it. Every row of this resolve needs that one token, so none of '
          'them was searched for. Nothing about this run is wrong and there is '
          'nothing to fix here; try again later, and check that host\'s own '
          'status page if it persists.',
    (IgdbHost.igdb, >= 500) => '$where failed on its own side (HTTP '
        '$statusCode). Nothing about this run is wrong and there is nothing to '
        'fix here; try again later, and check that host\'s own status page if '
        'it persists.',
    _ => '$where refused the request (HTTP $statusCode).',
  };
  return '$explanation $_rowsSurvive';
}

/// The statuses the token request is asked again for, and the only ones
/// [IgdbClient] retries anywhere but through `Worker.run` (T-0143).
///
/// The axis is how many times a retry is paid, not what the status means. The
/// token is fetched once per run -- one [IgdbClient._tokenRefresh] for all
/// lanes, and T-0144 replays its failure to every later row -- so 4 attempts
/// and 2+4+8 s cost a whole document **14 s once**, against losing every
/// canonical id for the run. The same classification on the search is paid per
/// detection: rows x 14 / `resolverConcurrency` seconds of backoff, which on a
/// real hi-res document at 4 lanes is minutes of backoff on a stage that
/// finishes in seconds ([igdbRequestsPerSecond]), and a 5xx that is the host's
/// own side is answered the same way by every row anyway. So a
/// search 5xx still fails fast and the rows come back with
/// `shelfscan resolve <review.json>`, which re-runs only this stage.
///
/// 400/401/403 are the credential pair, which cannot become a working one
/// inside one run ([IgdbClient._tokenFailure]); 404 is an address fixed in this
/// build; an unrecognised status is not evidence of transience.
bool _tokenRetryable(int statusCode) => statusCode == 429 || statusCode >= 500;

class IgdbHit {
  IgdbHit({
    required this.igdbId,
    required this.title,
    required this.platformId,
    required this.platformName,
    this.alternativeNames = const [],
    this.releaseYear,
  });

  final int igdbId;

  /// Canonical IGDB name.
  final String title;
  final int platformId;
  final String platformName;

  /// Regional and re-release names IGDB knows the same game under
  /// ("Biohazard RE:4" for "Resident Evil 4"). Empty when IGDB lists none.
  final List<String> alternativeNames;

  /// Year of `first_release_date`, or null where IGDB stores none -- a small
  /// fraction of the games one control run touches (T-0165). It is the whole
  /// game's first
  /// release, not this platform's port date, which is what separates a remake
  /// from its original and does not separate a Switch release from its PS5
  /// one; [ResolverWorker] uses it for the first question only.
  final int? releaseYear;
}

class IgdbClient {
  IgdbClient({
    required this.clientId,
    required this.clientSecret,
    this.timeout = igdbCallTimeout,
    this.tokenRetryBackoff = const Duration(seconds: 2),
    http.Client? client,
  }) : _client = client;

  final String clientId;
  final String clientSecret;

  /// See [igdbCallTimeout] for what the default rests on.
  final Duration timeout;

  /// The wait before Twitch is asked again, doubled per attempt: `Worker.run`'s
  /// own 2+4+8 s, so the project has one answer to "how long is transient".
  /// Settable for the same reason `ResolverWorker.backoffBase` is overridden in
  /// `igdb_rate_limit_test.dart` -- a test that counts attempts must not sleep
  /// through them.
  final Duration tokenRetryBackoff;

  /// `Worker.maxRetries` + 1, the same number for the same reason.
  static const _tokenAttempts = 4;

  final http.Client? _client;

  /// One bucket per client, and both shells build exactly one client per run,
  /// so this is the whole application's request rate.
  final _requests = _RequestWindow(igdbRequestsPerSecond);

  String? _token;
  DateTime _tokenExpiry = DateTime.fromMillisecondsSinceEpoch(0);
  Future<String>? _tokenRefresh;

  /// The first refresh failure, replayed to every later caller (T-0144).
  ///
  /// Measured with a `MockClient` answering the token request 403 on a real
  /// hi-res document at `resolverConcurrency` 4: **one token request per wave
  /// of lanes**, so `rows / resolverConcurrency` of them rather than one. The
  /// request count is stated as a multiple of the document's rows for the
  /// reason [igdbRequestsPerSecond] gives (T-0246, T-0266, T-0267).
  /// [_tokenRefresh] dedupes the lanes that ask at the same moment and is
  /// cleared in `whenComplete`, so each following wave asked again -- against a
  /// personal Twitch application quota, since the project ships no credentials
  /// (BYOK, decision 0011). Nothing the client could do between two rows makes a
  /// rejected pair a working one: [clientId] and [clientSecret] are final, so
  /// "fixed credentials" is necessarily a different client.
  ///
  /// "For the run" is therefore the life of this object, and both shells build
  /// one per run -- the CLI per invocation, the app per press of Scan
  /// (`ProviderPolicy.buildResolver`), which is the same lifetime
  /// [_RequestWindow] already assumes for the rate limit. There is no reset,
  /// because there is no caller that could use one.
  ///
  /// What reaches here has already survived [_refreshToken]'s 4 attempts over
  /// 14 s where the status allows them (T-0143), so a remembered failure is one
  /// the host repeated for that long rather than a first answer. A timeout and
  /// an unreachable host are remembered on the first, for the arithmetic on
  /// [IgdbTimeoutException] and [IgdbUnreachableException].
  Object? _tokenFailure;
  StackTrace? _tokenFailureTrace;

  // ------------------------------------------------------------------ //

  /// **The probe T-0094 was opened to run, 2026-08-15, live IGDB, 3 requests.**
  /// `search` and a `where` on the field are two different mechanisms and the
  /// second sees what the first cannot:
  ///
  ///   `where alternative_names.name ~ *"約束の丘"*` -> game **1100000020**,
  ///   Path of Ember 0: Director's Cut, holding the alternative name
  ///   `そらのは０ 約束の丘 Director's Cut` (id 1100000021, full-width ０).
  ///   `search "そらのは０ 約束の丘 Director's Cut"` -- that exact stored
  ///   string, the one IGDB itself returned -- gives **0 rows**.
  ///
  /// So the title is reachable through the API and only `search` refuses it.
  ///
  /// The same filter on the bare series name returns **12 games**, and the one
  /// that is not among them settles the other half of the filing: Path of Ember
  /// True 2 holds no Japanese alternative name at all, only Chinese ones. Of
  /// the そらのは spines the brief calls "in this state", exactly one is
  /// -- a name IGDB has and will not return. The other is a name IGDB does not
  /// have, which no query shape reaches.
  Future<List<IgdbHit>> search(String query, {String? platformHint}) =>
      // Stripped here rather than in the caller so no future caller can send a
      // query IGDB is known not to match.
      _games(
        search: stripLegalMarks(query.replaceAll('"', '')),
        platformHint: platformHint,
      );

  /// Games one of whose [IgdbHit.alternativeNames] *contains* [query], for the
  /// title [search] will not return at all (T-0094; the probe is on [search]).
  ///
  /// `~ *"..."*` is a case-insensitive substring test, so this is looser than
  /// [search] in a direction [search] is not loose in: the needle
  /// `solar pilgrim` would match every edition and DLC name carrying it, and
  /// IGDB answers a `where` in id order, with no relevance ranking to sink
  /// them. Two things bound it, and neither is a length floor:
  ///
  /// - **the needle is always the whole query**, never one of
  ///   `shortenedQueries`' fragments. A stored name containing an entire spine
  ///   read is close to identity already; a stored name containing a two-token
  ///   prefix of one is not, and that is where a sweep would come from. It
  ///   costs nothing here either: measured on the title this task exists for,
  ///   no shortened needle reaches it that the whole one does not;
  /// - **the caller throws the answer away unless one row is exactly the
  ///   spine** (`ResolverWorker.process`). A wrong find is therefore not a
  ///   wrong candidate -- it is no candidate, and the row walks the ladder
  ///   exactly as it does today.
  ///
  /// `*` is stripped along with `"`: both are pattern syntax here, and a spine
  /// read carrying one would otherwise widen its own needle.
  ///
  /// **`~` folds case and not width**, measured 2026-08-15 on this one title:
  /// against the stored `そらのは０ 約束の丘 Director's Cut`, a needle spelling
  /// `Director's Cut` in any case matches, the half-width `そらのは0` does not,
  /// and neither does the digitless read. So this reaches the title only for a
  /// read that carries the printed 0 the way the case prints it.
  ///
  /// **What it is worth, live, 2026-08-15.** Given that read, the resolver
  /// auto-matches Path of Ember 0: Director's Cut on Nintendo Switch 2 at 1.000 where
  /// it had no candidate at all. Given the read `CONTROL-HIRES` actually
  /// produces today -- the same spine without its 0 (T-0113) -- it finds
  /// nothing, and no bucket on either control set moves -- before and after,
  /// no row differing in any field. The cost of asking is one request per row
  /// `search` answered with nothing, which is a handful on the hi-res set and
  /// none at all on the low-res one (doc/control-set.md).
  Future<List<IgdbHit>> searchAlternativeNames(
    String query, {
    String? platformHint,
  }) {
    final needle = stripLegalMarks(query.replaceAll(_patternMeta, ''));
    if (needle.isEmpty) return Future.value(const []);
    return _games(
      where: 'alternative_names.name ~ *"$needle"*',
      platformHint: platformHint,
    );
  }

  /// The game a store's own product id **is**, joined on
  /// [externalGameSources] rather than matched as a string (T-0159).
  ///
  /// Every hit this returns is the game the publisher's installer named, so the
  /// caller owes it none of the fuzzy machinery: no score, no
  /// [platformAgreement] gate, no tie rule, no [volumeNumbersAgree]. Those
  /// exist to make a *guess* safe and there is no guess here.
  ///
  /// **Measured live 2026-08-16 on 480 real GoG product ids** (GOG's own public
  /// store catalogue, `catalog.gog.com/v1/catalog`, `productType=game`, ten
  /// pages spread evenly across all 133): **394 join, 82.1%.** The join is
  /// one-to-one -- 394 rows for 394 uids, **0 uids carrying a second row and 0
  /// resolving to a second IGDB game** -- which is what entitles the caller to
  /// skip the gates. `limit 10` is therefore headroom, not an expectation.
  ///
  /// The 86 that do not join fall back to the ordinary title path, which is
  /// also where they would have started; the join costs them one request. That
  /// price is measured against a search that costs one request too, plus up to
  /// four more on `shortenedQueries`' ladder.
  ///
  /// **Empty means "no usable join" and covers two cases on purpose**: IGDB
  /// does not hold the uid, and IGDB holds it but lists the game on no platform
  /// at all (4 of the 394; the library is a real one, not published, and the
  /// rows are not named). A hit is a (game, platform) pair and neither case can
  /// make one, so both reach the caller as the same "carry on".
  ///
  /// No platform filter, deliberately, and it is worth a row that T-0156's
  /// search loses: `PC` -> {6} asks IGDB for Windows and a GoG DOS-era release
  /// is listed on 13 DOS (Mire II answered 0 rows there; two rows of the
  /// measured library are the same shape and are not named). The join
  /// finds the game whatever it is listed on and lets the caller decide what to
  /// do about the platform.
  Future<List<IgdbHit>> gamesByExternalId({
    required String source,
    required String uid,
  }) async {
    final sourceId = externalGameSources[source.trim().toLowerCase()];
    // `"` would end the pattern; a GoG id is digits, but the guard costs
    // nothing and this value arrives from a file on disk.
    final needle = uid.trim().replaceAll('"', '');
    if (sourceId == null || needle.isEmpty) return const [];
    final body = 'fields uid, game.id, game.name, '
        'game.alternative_names.name, game.platforms.id, game.platforms.name, '
        'game.first_release_date; '
        'where external_game_source = $sourceId & uid = "$needle"; limit 10;';
    final rows = jsonDecode(await _post('external_games', body)) as List<dynamic>;
    return [
      for (final row in rows)
        if ((row as Map<String, dynamic>)['game'] is Map<String, dynamic>)
          ..._hits(row['game'] as Map<String, dynamic>),
    ];
  }

  Future<List<IgdbHit>> _games({
    String? search,
    String? where,
    String? platformHint,
  }) async {
    final platforms =
        platformIds[(platformHint ?? '').toUpperCase().replaceAll(' ', '')];
    // `platforms = (a,b)` is a union, measured 2026-08-15: it returns a game
    // listed on 508 only, which "contains all" would not. `[a,b]` and `{a,b}`
    // are exact-set matches and drop those same games -- 0 rows for both
    // Solar Pilgrim VII titles.
    final clauses = [
      if (where != null) where,
      if (platforms != null) 'platforms = (${platforms.join(',')})',
    ];
    final body = [
      if (search != null) 'search "$search";',
      'fields id, name, alternative_names.name, platforms.id, platforms.name, '
          'first_release_date;',
      if (clauses.isNotEmpty) 'where ${clauses.join(' & ')};',
      'limit 10;',
    ].join(' ');

    final games = jsonDecode(await _post('games', body)) as List<dynamic>;
    return [
      for (final game in games)
        ..._hits(game as Map<String, dynamic>, platforms: platforms),
    ];
  }

  /// One hit per (game, platform) pair: the same title on SNES and PS1 are
  /// different physical items for a collector.
  ///
  /// [platforms] null keeps every platform the game is listed on, which is what
  /// [gamesByExternalId] wants and what an unhinted search already got.
  static List<IgdbHit> _hits(Map<String, dynamic> game, {Set<int>? platforms}) {
    // An expanded field is absent, not empty, when the game has no alternative
    // names at all.
    final alternativeNames = [
      for (final alt in (game['alternative_names'] as List<dynamic>? ?? []))
        if ((alt as Map<String, dynamic>)['name'] is String)
          alt['name'] as String,
    ];
    final released = game['first_release_date'];
    // Seconds, UTC: IGDB stores a unix timestamp and a local-time reading of
    // it moves a 1 January release into the previous year.
    final releaseYear = released is int
        ? DateTime.fromMillisecondsSinceEpoch(released * 1000, isUtc: true).year
        : null;
    return [
      for (final platform in (game['platforms'] as List<dynamic>? ?? []))
        if (platforms == null || platforms.contains(platform['id']))
          IgdbHit(
            igdbId: game['id'] as int,
            title: game['name'] as String,
            platformId: platform['id'] as int,
            platformName: platform['name'] as String,
            alternativeNames: alternativeNames,
            releaseYear: releaseYear,
          ),
    ];
  }

  /// The one place a request to IGDB is issued, retries included, so the
  /// documented rate holds whatever the caller sets `resolverConcurrency` to --
  /// the knob stops being a way to exceed it, and a second endpoint (T-0159)
  /// does not become a second lane through the limit.
  Future<String> _post(String endpoint, String body) async {
    // The token goes to a different host under a different limit and is
    // fetched before the slot is taken, so a refresh never sits on one.
    // Outside the try below on purpose: a token fetch that fails is Twitch's
    // failure and has already been named as one, and catching it here would
    // relabel it IGDB (T-0107).
    final token = await _getToken();
    await _requests.waitForSlot();
    final http.Response response;
    try {
      // The bound is around the request and nothing else: [_RequestWindow]
      // sleeps up to a second by design and [_getToken] may be waiting on
      // another lane's refresh, and neither is the endpoint failing to answer
      // (T-0104).
      response = await boundedPost(
        (client) => client.post(
          Uri.parse('$_igdbUrl/$endpoint'),
          headers: {
            'Client-ID': clientId,
            'Authorization': 'Bearer $token',
          },
          body: body,
        ),
        reusing: _client,
        within: timeout,
        onTimeout: (waited) => IgdbTimeoutException('IGDB', _igdbUrl, waited),
      );
    } on http.ClientException catch (e) {
      throw IgdbUnreachableException(IgdbHost.igdb, e);
    }
    if (response.statusCode != 200) {
      throw igdbFailure(
        host: IgdbHost.igdb,
        statusCode: response.statusCode,
        body: response.body,
      );
    }
    return response.body;
  }

  // ------------------------------------------------------------------ //

  Future<String> _getToken() {
    // The same failure the first lane got, so every row still degrades with
    // the sentence that explains it -- it simply is not asked again.
    final failure = _tokenFailure;
    if (failure != null) return Future.error(failure, _tokenFailureTrace);
    if (_token != null &&
        DateTime.now()
            .isBefore(_tokenExpiry.subtract(const Duration(minutes: 1)))) {
      return Future.value(_token);
    }
    // Concurrent workers share one refresh instead of stampeding Twitch.
    return _tokenRefresh ??= _rememberingFailure().whenComplete(() {
      _tokenRefresh = null;
    });
  }

  Future<String> _rememberingFailure() async {
    try {
      return await _refreshToken();
    } catch (error, stack) {
      _tokenFailure = error;
      _tokenFailureTrace = stack;
      rethrow;
    }
  }

  /// Asks Twitch, retrying the statuses in [_tokenRetryable] (T-0143).
  ///
  /// The retry lives here rather than in `Worker.run` for two reasons, and the
  /// first is the load-bearing one: here it is inside [_tokenRefresh], so all
  /// lanes share it and [_rememberingFailure] only ever sees a failure that
  /// already survived it -- a token error that reached `Worker` instead would be
  /// re-thrown from [_tokenFailure] without a request going out, and every row
  /// would sleep 14 s for a cached answer. And a response is where the
  /// status is: re-classifying a thrown exception would have to decide again
  /// what a timeout is, which [IgdbTimeoutException] has already decided.
  Future<String> _refreshToken() async {
    for (var attempt = 1;; attempt++) {
      final http.Response response;
      try {
        // Bounded like the search, and separately named: the token comes from
        // Twitch, so a failure here is a different host from the one the
        // searches go to and telling the user "IGDB" would send them to the
        // wrong status page.
        response = await boundedPost(
          (client) => client.post(Uri.parse(_tokenUrl), body: {
            'client_id': clientId,
            'client_secret': clientSecret,
            'grant_type': 'client_credentials',
          }),
          reusing: _client,
          within: timeout,
          onTimeout: (waited) =>
              IgdbTimeoutException('Twitch', _tokenUrl, waited),
        );
      } on http.ClientException catch (e) {
        throw IgdbUnreachableException(IgdbHost.twitch, e);
      }
      if (response.statusCode != 200) {
        if (attempt >= _tokenAttempts || !_tokenRetryable(response.statusCode)) {
          throw igdbFailure(
            host: IgdbHost.twitch,
            statusCode: response.statusCode,
            body: response.body,
          );
        }
        await Future<void>.delayed(tokenRetryBackoff * (1 << (attempt - 1)));
        continue;
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      _token = data['access_token'] as String;
      _tokenExpiry =
          DateTime.now().add(Duration(seconds: data['expires_in'] as int));
      return _token!;
    }
  }
}

/// Holds callers to [limit] issues per rolling second.
///
/// A rolling window rather than a per-second counter, because the limit being
/// enforced is itself a rolling one: 4 requests at 0.99 s and 4 more at 1.01 s
/// is 8 inside one second, and a counter that resets on the wall clock admits
/// exactly that burst -- which is the pattern a resolver pool produces.
///
/// Every blocked lane wakes and re-checks rather than queueing in order. The
/// claim is synchronous once the check passes, so two lanes cannot take one
/// slot; ordering between lanes is not a property anything here needs, since
/// `Orchestrator.runResolve` sorts its rows by input index afterwards.
class _RequestWindow {
  _RequestWindow(this.limit);

  final int limit;
  static const _span = Duration(seconds: 1);

  /// A monotonic clock, not `DateTime.now()`: a wall-clock step during a run
  /// would either release the whole window at once or stall it for the size of
  /// the step, and on Windows the wall clock also ticks in ~15.6 ms jumps.
  final _clock = Stopwatch()..start();

  /// When the grants still inside the window were made, never more than
  /// [limit] of them, oldest first.
  final _granted = <int>[];

  Future<void> waitForSlot() async {
    while (true) {
      final now = _clock.elapsedMilliseconds;
      _granted.removeWhere((at) => now - at >= _span.inMilliseconds);
      if (_granted.length < limit) {
        _granted.add(now);
        return;
      }
      await Future<void>.delayed(
          Duration(milliseconds: _granted.first + _span.inMilliseconds - now));
    }
  }
}
