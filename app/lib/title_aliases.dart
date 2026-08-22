/// Loading of the regional-title alias table for the app.
///
/// The table is a repository-level data file (`data/title_aliases.json`)
/// bundled as a Flutter asset. `shelfscan_core` cannot read it itself: it
/// must not touch `dart:io` (ARCHITECTURE.md platform boundary), and on
/// Android there is no file to read anyway -- so the shell loads the bytes
/// and injects the parsed map into the resolver, exactly as the CLI does.
library;

import 'package:flutter/services.dart';
import 'package:shelfscan_core/shelfscan_core.dart';

/// Asset key of the bundled table. Declared in `app/pubspec.yaml`; the file
/// itself stays at the repository root so the CLI and the app read one table
/// rather than two copies that drift apart.
const titleAliasesAsset = '../data/title_aliases.json';

/// The alias table, or the built-in fallback if the asset is missing or
/// malformed.
///
/// Never throws: aliases only widen what IGDB is asked for, so losing them
/// costs match rate on regional titles rather than the scan.
Future<Map<String, String>> loadTitleAliases({
  AssetBundle? bundle,
  void Function(String message)? onWarning,
}) async {
  try {
    return parseTitleAliases(
        await (bundle ?? rootBundle).loadString(titleAliasesAsset));
  } on Object catch (e) {
    onWarning?.call('Alias table unusable ($e) -- falling back to '
        '${builtinTitleAliases.length} built-in aliases.');
    return builtinTitleAliases;
  }
}
