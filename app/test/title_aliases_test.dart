/// Guards the app's half of the alias table (T-0004).
///
/// The table is a repository-level data file the app can only see because it
/// is registered as an asset, and the registration is a line in
/// `pubspec.yaml` that nothing else would notice the loss of: without this
/// test a dropped asset entry degrades silently to the built-in three
/// aliases, on a device, months later.
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelfscan_app/provider_config.dart';
import 'package:shelfscan_app/title_aliases.dart';
import 'package:shelfscan_core/shelfscan_core.dart';

/// An asset bundle with a scripted answer for the alias key.
class _FakeBundle extends CachingAssetBundle {
  _FakeBundle(this.contents);

  /// Null = the asset is not in the bundle at all.
  final String? contents;

  @override
  Future<ByteData> load(String key) async {
    final contents = this.contents;
    if (contents == null) throw StateError('asset not found: $key');
    return ByteData.sublistView(Uint8List.fromList(contents.codeUnits));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the registered asset is really in the bundle and parses', () async {
    // Loaded through rootBundle, so this fails if the pubspec entry is gone
    // or points at a path the flutter tool cannot resolve.
    final aliases = await loadTitleAliases(
        onWarning: (message) => fail('warned instead of loading: $message'));

    expect(aliases, isNotEmpty);
    expect(aliases, containsPair('biohazard', 'resident evil'));
  });

  test('a missing asset falls back to the built-in table', () async {
    final warnings = <String>[];

    final aliases = await loadTitleAliases(
        bundle: _FakeBundle(null), onWarning: warnings.add);

    expect(aliases, builtinTitleAliases);
    expect(warnings, hasLength(1));
  });

  test('a malformed asset falls back too, without throwing', () async {
    final warnings = <String>[];

    final aliases = await loadTitleAliases(
        bundle: _FakeBundle('{"biohazard": 4}'), onWarning: warnings.add);

    expect(aliases, builtinTitleAliases);
    expect(warnings, hasLength(1));
  });

  test('the loaded table reaches the resolver', () async {
    final resolver = ProviderPolicy.buildResolver(
      ProviderSettings(igdbClientId: 'id', igdbClientSecret: 'secret'),
      aliases: await loadTitleAliases(),
    );

    expect(resolver.aliases, containsPair('biohazard', 'resident evil'));
  });
}
