/// GOG Galaxy's local library cache: the whole owned account, not the disk
/// (T-0177).
///
/// [GogMetadataSource] sees a GoG game only once it is installed, because the
/// only thing it reads is the `goggame-<productid>.info` the installer writes
/// beside the game. GOG Galaxy separately keeps every release the account owns
/// in one local SQLite file, installed or not. Same store, same product id, so
/// the rows land on T-0159's exact join unchanged -- the difference is the size
/// of the set.
///
/// **The schema is vendor-undocumented and was read off a real Galaxy install**
/// (`C:\ProgramData\GOG.com\Galaxy\storage\galaxy-2.0.db`, `PRAGMA
/// user_version` 40, 2026-08-16). Nothing on docs.gog.com describes it; GOG
/// does not know this reader exists. The library it was read on is private:
/// neither it nor its size is published, so what is recorded here is the shape
/// the reader relies on rather than the census taken of it.
///
/// `LibraryReleases` holds one row per owned release, and three kinds of row
/// there are not a game this source may emit. Each is excluded by a column
/// rather than by a guess about the title: `ReleaseProperties.isDlc = 1`, then
/// `isVisibleInLibrary = 0`, then a release key that is not `gog_`.
///
/// So the fear that the feature would drown review in bundle leftovers did not
/// survive contact with the file: what reaches review is one row per distinct
/// product id. **The filters that get it there are the vendor's own flags, not
/// a heuristic over titles** -- which is what makes them trustworthy on a
/// library nobody has looked at.
///
/// **The shell does the SQL; this file sees only text.** Core has no `dart:io`
/// and no SQLite, so the reader in each shell turns one library row into one
/// [SourceEntry] whose [SourceEntry.content] is the JSON object below, exactly
/// as T-0157 receives a `.info` file's text. Three keys are relied on and every
/// other column in that database is treated as absent:
///
/// ```json
/// {"releaseKey": "gog_1100000014", "isDlc": 0, "isVisibleInLibrary": 1}
/// ```
///
/// plus `title`, a string. `releaseKey` is `<platform>_<id>` and is the row's
/// primary key throughout the file; `ProductsToReleaseKeys` agrees its numeric
/// half with `gogId` on every row measured, which is what licenses reading the
/// product id straight out of it.
///
/// **Installed-ness is deliberately not read here.** The database has
/// `InstalledProducts`/`InstalledBaseProducts` for it, and no populated sample
/// of either was available to read the schema off, so a reader against them
/// would be code written to a guess -- the thing T-0157 refused to do. The
/// installed answer already exists and is already verified: it is
/// [GogMetadataSource], reading a file that cannot be there unless the game is.
/// Both sources emit the same `gog:<productid>`, so stage 2 merges a game that
/// is both owned and installed into one row.
library;

import 'dart:convert';

import '../models.dart';
import '../orchestrator.dart';
import 'gog_metadata.dart';

/// Reads one row of GOG Galaxy's local library into a detection.
class GogLibrarySource implements DetectionSource {
  const GogLibrarySource();

  /// The file the shell reads, named here so a decline can say where it looked
  /// and so the two shells cannot drift on it.
  static const databaseName = 'galaxy-2.0.db';

  /// A `<platform>_<id>` release key that is a GOG product.
  ///
  /// Anchored on `gog` because Galaxy 2.0 also stores releases from connected
  /// stores in the same table, and those carry no GOG product id at all.
  static final releaseKey = RegExp(r'^gog_(\d+)$');

  // The four below are [Severity.failure]: the shell promised a row of the
  // shape this file documents and did not deliver one, so a game may be
  // missing and the reader or the schema is what has to change. The three
  // after them are [Severity.exclusion] -- the row was read, understood, and
  // left out on purpose (T-0222).
  static const notJson = 'library row is not JSON';
  static const notAnObject = 'library row is not a JSON object';
  static const noReleaseKey = 'library row carries no "releaseKey" string';
  static const noTitle = 'library row carries no title';

  /// A connected store's release is in the same table and is not a GOG
  /// product: it has no id T-0159 can join on, so it would silently drop to
  /// fuzzy title matching while looking exactly like a row that cannot be
  /// wrong. "the GOG library" and "everything Galaxy knows about the account"
  /// are different documents; this source is the first.
  static const notGogProduct = 'library row is another store\'s release, not a GOG product';

  /// Same rule and same reason as
  /// [GogMetadataSource.dlcNotAGame]: a DLC's title is its own, so a row for it
  /// survives dedupe and reaches review as a game the user does not own.
  static const dlcNotAGame = 'library row is DLC, not a game';

  /// Galaxy does not show these in the user's own library, so neither does
  /// this -- a row the user cannot find in the app it came from is the
  /// surprise, not the omission.
  static const hiddenInLibrary = 'library row is not visible in the Galaxy library';

  @override
  SourceReading read(SourceEntry entry) {
    final content = entry.content;
    if (content == null) return _failed(entry, notJson);

    final Object? decoded;
    try {
      decoded = jsonDecode(content);
    } on FormatException {
      return _failed(entry, notJson);
    }
    if (decoded is! Map<String, dynamic>) return _failed(entry, notAnObject);

    final key = decoded['releaseKey'];
    if (key is! String || key.trim().isEmpty) {
      return _failed(entry, noReleaseKey);
    }
    // Read out of the row rather than out of [SourceEntry.name], for T-0157's
    // reason: the two agree only because the shell puts them there, and a join
    // must not be retargetable by a shell that names an entry differently.
    final match = releaseKey.firstMatch(key.trim());
    if (match == null) return _excluded(entry, notGogProduct);

    final title = decoded['title'];
    if (title is! String || title.trim().isEmpty) {
      return _failed(entry, noTitle);
    }

    // Absent is absent (T-0157): both columns are nullable in the vendor's own
    // schema, and a null there is not an assertion that the row is a hidden DLC.
    if (_isTrue(decoded['isDlc'])) return _excluded(entry, dlcNotAGame);
    if (_isFalse(decoded['isVisibleInLibrary'])) {
      return _excluded(entry, hiddenInLibrary);
    }

    return SourceReading(items: [
      Detection.fromSource(
        rawTitle: title.trim(),
        origin: DetectionOrigin.metadata,
        sourceEntry: entry.name,
        // T-0157's namespace, reused rather than repeated: T-0159 joins IGDB
        // `external_games` source 5 on exactly this prefix, and a second
        // spelling of it would be a join that compiles and never matches.
        sourceId: '${GogMetadataSource.idPrefix}${match.group(1)}',
        platformHint: GogMetadataSource.platformHint,
      ),
    ]);
  }

  /// SQLite has no boolean, and the column is `INTEGER NULL`; a shell that
  /// hands over a real `bool` is right too.
  static bool _isTrue(Object? v) => v == true || (v is num && v != 0);

  static bool _isFalse(Object? v) => v == false || (v is num && v == 0);

  SourceReading _excluded(SourceEntry entry, String reason) =>
      _decline(entry, reason, Severity.exclusion);

  SourceReading _failed(SourceEntry entry, String reason) =>
      _decline(entry, reason, Severity.failure);

  /// Two named helpers rather than one call carrying the class as an argument,
  /// so the class of a decline is legible at the `return` (T-0222).
  SourceReading _decline(SourceEntry entry, String reason, Severity severity) =>
      SourceReading(declined: [
        DeclinedEntry(name: entry.name, reason: reason, severity: severity)
      ]);
}
