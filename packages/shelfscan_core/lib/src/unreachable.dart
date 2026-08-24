/// The one question every provider answers identically: did the endpoint
/// answer at all?
library;

/// A request that never reached an HTTP status -- no code, no body, nothing to
/// explain (T-0105).
///
/// Four classes had grown this shape in three days (T-0097 local, T-0103 cloud,
/// T-0107 both IGDB hosts) with no type between them, so the one caller that
/// must classify -- the app's `_settingsCanFix` (T-0102) -- named each of them
/// by hand and a fifth provider's version would have fallen through to `false`
/// silently. What each subclass still owns is its own remedy: `ollama serve`
/// for a server the user can start, the base URL for one they typed, neither
/// for an address fixed in the build. Only the question is shared.
///
/// Its own file rather than `providers/vision.dart`, where the first two live:
/// the resolve stage throws one of these too and `providers/igdb.dart`
/// deliberately depends on none of the vision vocabulary (its own comments say
/// so twice). A supertype spanning both stages belongs to neither.
///
/// [endpointIsUserSet] sits here rather than in the app's `provider_config.dart`
/// even though ARCHITECTURE.md puts provider policy there: it is a fact each
/// provider holds about its own address, and the app's copy would be a second
/// one to keep in step.
abstract class UnreachableEndpoint implements Exception {
  /// The address that did not answer.
  String get endpoint;

  /// Whether [endpoint] is a field the user can correct. It is the whole of
  /// what a caller wants the type for: nothing answered, so neither a key nor a
  /// model id can be what failed, and the URL is the only setting left to
  /// offer.
  bool get endpointIsUserSet;

  /// The sentence the user reads. Each subclass composes its own; this only
  /// promises there is one.
  ///
  /// What every one of them owes beyond its own remedy, and it is the half
  /// that was missing when a true message cost a day (T-0354): a remedy inside
  /// this app is not the whole remedy. Nothing answered, so nothing here can
  /// tell a blocked route from a dead host from an address typed wrong -- and
  /// a reader offered only somewhere to look in here will look in here. Name
  /// [endpoint], so it can be tried without this app at all, and point outward
  /// without claiming which of the three it was. [checkOutsideThisApp] is that
  /// outward half; each subclass composes it rather than writing it (T-0357).
  String get message;

  @override
  String toString() => message;
}

/// The outward half of [UnreachableEndpoint.message], composed once (T-0357).
///
/// It was written three times before this, once per provider file, because
/// `providers/igdb.dart` deliberately depends on none of the vision vocabulary
/// (its own comments say so twice) and `providers/tmdb.dart` on neither, so
/// the copies could not import each other. This file depends on no provider at
/// all, which is the reason the supertype is here and the same reason the
/// clause is.
///
/// **It is a composition rather than a constant, because two parts are
/// genuinely different sentences** (both measured T-0355):
///
/// - [stage] is the work that failed. `the scan` for the photographs, `the
///   lookup` for the resolve stage -- `resolve` is a CLI command of its own
///   that reads an existing review document and scans nothing, so `the scan`
///   would name work that never ran.
/// - [usually] is what a browser refused the same way points at, and that
///   depends on where the host is. [outOnTheInternet] is the list for a host
///   this machine has to reach across a network it does not own; a server on
///   this machine or the next desk is a different and rarer story, and
///   `providers/ollama_vision.dart` supplies its own.
///
/// Neither has a default, deliberately. A fifth family inheriting one in
/// silence is the shape of the defect [UnreachableEndpoint] itself was filed
/// for (T-0105).
///
/// **Why a browser, and which word carries the hedge** (T-0354, whose case
/// bought this clause): settings copied from a working desktop onto a phone
/// reported a reset. The reset was true -- the phone's own browser was refused
/// by the same host -- and a day went into looking for a fault in here,
/// because the sentence named somewhere to look inside this app and nowhere
/// outside it. A browser is the check a person can run without the thing they
/// are trying to test. A blocked route, a dead host and a mistyped address all
/// arrive as one `ClientException`, so nothing here knows which happened: the
/// conditional is the only firm claim, `usually` carries the rest, and
/// `points outside` is a direction rather than a diagnosis.
String checkOutsideThisApp({
  required String stage,
  required String usually,
}) =>
    'Open that address in a browser on this device: any answer at all, even '
    'an error page, means the host is reachable from here. A browser refused '
    'the same way points outside this app rather than at $stage -- usually '
    '$usually.';

/// [checkOutsideThisApp]'s [usually] for a host out on the internet, which is
/// every family but the local one.
const outOnTheInternet =
    'this machine being offline, or a proxy or a firewall in the way';
