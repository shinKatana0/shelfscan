/// The one question three providers answer identically: did the endpoint
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
  /// without claiming which of the three it was.
  String get message;

  @override
  String toString() => message;
}
