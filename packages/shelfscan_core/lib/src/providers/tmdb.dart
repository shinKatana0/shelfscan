/// TMDB search — the film catalogue, and the second one this project talks to
/// (T-0162, decision 0015).
///
/// Shaped after `igdb.dart` deliberately, because the resolver's seam is only
/// worth having if a second catalogue costs a client and nothing else: a hit
/// type, a search, one bounded request, and the same three failure classes
/// (`RetryableException` for a rate limit, `UnreachableEndpoint` for a host
/// that never answered, a plain exception for a refusal).
///
/// **What it does NOT copy is the platform gate.** IGDB's search is
/// constrained by a platform id and scored against it; a film has no platform,
/// which is why `TonkatsuExporter` writes no `platform_id` for one and why
/// `FileNameParse.platformHint` is null on a film row. The year takes the
/// gate's place instead, and it is the field a release filename almost always
/// carries — but it is a hard filter rather than a preference, which is
/// [TmdbClient.searchMovie]'s subject and cost this project T-0336.
///
/// **RUN AGAINST THE LIVE SERVICE ONCE, FOR ONE QUESTION.** Five searches on
/// 2026-08-23 settled what the `year` parameter does, and nothing else. Every
/// other claim here is still offline against a fake client: the request this
/// builds and the parsing of a recorded-shape response are verified, and that
/// TMDB answers that shape is read off its published API rather than
/// measured. No TMDB credential exists on the machine this is developed on.
/// See `doc/reports/T-0162.md` and `doc/reports/T-0336.md`.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../http_timeout.dart';
import '../unreachable.dart';
import '../workers/base.dart';

/// The credential is an **API Read Access Token**, not the v3 `api_key`, and
/// the difference is a privacy one rather than a preference.
///
/// TMDB accepts the v3 key only as a query parameter, which puts the
/// credential in every URL the client builds — and a URL is the one thing an
/// error, a log line or a stack trace quotes by reflex. The read token goes in
/// an `Authorization` header, so there is no shape of failure here that can
/// echo it. Both are issued on the same TMDB settings page, so this costs the
/// user nothing but the right copy button.
///
/// `tmdb_credential_test.dart` holds the guarantee rather than this comment:
/// no message this file throws contains the token.
const tmdbTokenVariable = 'SHELFSCAN_TMDB_TOKEN';

const _tmdbHost = 'api.themoviedb.org';

/// The same bound as `igdbCallTimeout` and for the same argument: a catalogue
/// search answers in milliseconds, nothing legitimate on this path takes
/// seconds, so a tight bound costs nothing and catches a stall while the run
/// is still worth saving. Not shared with that constant because the two are
/// separate services whose budgets may diverge, and one name would hide it.
const tmdbCallTimeout = Duration(seconds: 20);

/// One possible TMDB match for a detection.
class TmdbHit {
  TmdbHit({
    required this.tmdbId,
    required this.title,
    this.originalTitle,
    this.releaseYear,
  });

  final int tmdbId;

  /// TMDB's title in the language the search asked for.
  final String title;

  /// The title in the film's own language, when TMDB lists a different one.
  ///
  /// The analogue of `IgdbHit.alternativeNames` and it exists for the same
  /// measured reason: a filename is often the original-language release name
  /// while the catalogue's canonical title is the localised one, and scoring
  /// only the canonical form loses the match without saying so.
  final String? originalTitle;

  /// Year of `release_date`. Null where TMDB stores none, which it does for
  /// unreleased and poorly catalogued entries.
  final int? releaseYear;
}

/// A TMDB rate limit, as a [RetryableException] so `Worker.run`'s policy is
/// untouched — the treatment `RetryableIgdbException` gets.
class RetryableTmdbException extends RetryableException {
  RetryableTmdbException(super.message);
}

/// A non-2xx that is not a rate limit.
///
/// **No response body is ever quoted**, which is `igdb.dart`'s rule carried
/// over unchanged: this is a BYOK path (decision 0011), the likeliest failure
/// on it is a bad credential, and a service's own error text is not a place to
/// find out what it decided to include.
class TmdbApiException implements Exception {
  TmdbApiException(this.message, {required this.statusCode});
  final String message;
  final int statusCode;
  @override
  String toString() => message;
}

class TmdbUnreachableException extends UnreachableEndpoint {
  TmdbUnreachableException(this.reason);

  final String reason;

  @override
  String get endpoint => _tmdbHost;

  /// Fixed in this build, so there is no URL setting to correct — the same
  /// answer `IgdbUnreachableException` gives, and the reason it matters is
  /// that it tells the user not to go looking in their settings.
  @override
  bool get endpointIsUserSet => false;

  @override
  String get message =>
      'TMDB at $_tmdbHost did not answer, so no film title could be looked '
      'up. Nothing answered, so the TMDB token is not what failed. That '
      'address is fixed in this build rather than typed by you, so there is '
      'nothing to correct in your settings. $_checkOutsideThisApp '
      'Rows still reach review unmatched ($reason)';
}

/// The check that runs without this application, word for word what
/// `igdb.dart` says (T-0354, T-0355). The clause about a base URL `yours to
/// set` is dropped rather than reworded, for the reason it is dropped there:
/// [_tmdbHost] is a constant in this file.
///
/// **`any answer at all` is true here for a different reason, and the reason
/// is the thing that had to be checked.** The vision copy's comment says it is
/// needed because those are POST endpoints; [TmdbClient.searchMovie] is a GET.
/// What makes an error page the expected result anyway is that the address
/// named above is the bare host with no path, and that the search itself
/// carries a bearer token a browser does not have. Either way a browser is
/// answered with an error rather than anything friendly, which is what the
/// clause stops the reader reading as a second failure.
const _checkOutsideThisApp =
    'Open that address in a browser on this device: any answer at all, even an '
    'error page, means the host is reachable from here. A browser refused the '
    'same way points outside this app rather than at the lookup -- usually '
    'this machine being offline, or a proxy or a firewall in the way.';

class TmdbTimeoutException extends UnreachableEndpoint {
  TmdbTimeoutException(this.waited);

  final Duration waited;

  @override
  String get endpoint => _tmdbHost;
  @override
  bool get endpointIsUserSet => false;

  @override
  String get message => timedOutMessage(
        service: 'TMDB',
        endpoint: _tmdbHost,
        waited: waited,
        advice: 'A catalogue search answers in milliseconds, so this is a '
            'stalled connection rather than a slow lookup.',
      );
}

class TmdbClient {
  TmdbClient({required this.token, this.timeout = tmdbCallTimeout, http.Client? client})
      : _client = client;

  /// The API Read Access Token. See [tmdbTokenVariable] for why it is that and
  /// not the v3 key.
  final String token;

  final Duration timeout;
  final http.Client? _client;

  /// Films TMDB knows under [title], most confident first.
  ///
  /// **[year] FILTERS. Measured live, five searches, 2026-08-23.** This
  /// comment said the opposite until then — that TMDB's `year` prefers a
  /// match without requiring one, so a filename year off by one still finds
  /// the film — and every clause of it was false. It had been written against
  /// a fake, which answered as it was told to.
  ///
  /// What the service does: a film whose catalogued release year is not the
  /// one asked for is **absent from the answer, not demoted in it**. The
  /// correct year cuts a common title from dozens of candidates to the one
  /// right film; that same year off by one comes back either empty or holding
  /// a list the film is not in.
  ///
  /// So the parameter stays — the narrowing is the whole value of it, and the
  /// measurement shows it doing exactly the work it was added for. The
  /// off-by-one it creates is real and common (a festival year against a
  /// general release, a territory date) and is handled one layer up, by
  /// `TmdbResolverWorker`'s retry without it. This client asks once and
  /// reports what came back; the retry is a decision about evidence and
  /// belongs where the evidence is weighed.
  Future<List<TmdbHit>> searchMovie(String title, {int? year}) async {
    final query = title.trim();
    if (query.isEmpty) return const [];

    final uri = Uri.https(_tmdbHost, '/3/search/movie', {
      'query': query,
      'include_adult': 'false',
      if (year != null) 'year': '$year',
    });

    final http.Response response;
    try {
      response = await boundedPost(
        (client) => client.get(uri, headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        }),
        reusing: _client,
        within: timeout,
        onTimeout: TmdbTimeoutException.new,
      );
    } on http.ClientException catch (e) {
      throw TmdbUnreachableException(e.message);
    }

    if (response.statusCode != 200) throw _failure(response.statusCode);

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) return const [];
    final results = decoded['results'];
    if (results is! List) return const [];

    return [
      for (final result in results)
        if (_hit(result) case final hit?) hit,
    ];
  }

  /// A result TMDB returned that this can read, or null.
  ///
  /// Null rather than throwing: one malformed entry in a list of twenty is not
  /// a failed search, and the run's own rule is that a bad row degrades to no
  /// row rather than ending anything.
  static TmdbHit? _hit(Object? result) {
    if (result is! Map<String, dynamic>) return null;
    final id = result['id'];
    final title = result['title'] ?? result['original_title'];
    if (id is! int || title is! String || title.trim().isEmpty) return null;
    final original = result['original_title'];
    return TmdbHit(
      tmdbId: id,
      title: title,
      originalTitle:
          original is String && original.trim().isNotEmpty && original != title
              ? original
              : null,
      releaseYear: _year(result['release_date']),
    );
  }

  /// TMDB writes `release_date` as `YYYY-MM-DD`, and as `""` for a film it has
  /// no date for — the empty string is the common case, not the malformed one.
  static int? _year(Object? value) {
    if (value is! String || value.length < 4) return null;
    return int.tryParse(value.substring(0, 4));
  }

  Exception _failure(int statusCode) => switch (statusCode) {
        429 => RetryableTmdbException(
            'TMDB is rate limiting this run. Waiting and asking again.'),
        401 => TmdbApiException(
            'TMDB refused the token (401). Check that $tmdbTokenVariable holds '
            'the API Read Access Token from your TMDB account settings, not '
            'the v3 API key — the two are different strings on the same page.',
            statusCode: statusCode),
        404 => TmdbApiException(
            'TMDB answered 404 for a search request, which means the request '
            'this build sends no longer matches its API.',
            statusCode: statusCode),
        _ => TmdbApiException(
            'TMDB answered $statusCode. No film titles were looked up; rows '
            'still reach review unmatched.',
            statusCode: statusCode),
      };
}
