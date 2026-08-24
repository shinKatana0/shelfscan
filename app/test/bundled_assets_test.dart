/// Guards what `pubspec.yaml` declares as an asset (T-0386).
///
/// A key is written relative to `build/flutter_assets/`, so a key beginning
/// `../` lands outside the bundle and is left behind when packaging copies
/// that directory -- the app then ships a manifest promising a file it does
/// not carry. Nothing caught that for the whole life of the alias table:
/// `flutter test` builds its bundle at `app/build/unit_test_assets/`, one
/// level below where the escaped copies land, so `../` resolves there and
/// every widget test loading such an asset passes.
///
/// This is the half that needs no build, and it is deliberately paired with
/// `tool/check-bundle-assets.dart`, which reads a built bundle and can
/// therefore answer the question this file only approximates.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Asset paths declared under `flutter: assets:` in `app/pubspec.yaml`.
///
/// Scanned rather than parsed: pulling in a YAML parser for six lines would
/// add a dependency to the app's test graph, and the block is a flat list of
/// `- path` entries.
List<String> declaredAssets(String pubspec) {
  final assets = <String>[];
  var inside = false;
  for (final raw in pubspec.split('\n')) {
    final line = raw.replaceAll('\r', '');
    if (line.trimRight() == '  assets:') {
      inside = true;
      continue;
    }
    if (!inside) continue;
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    if (!trimmed.startsWith('- ')) break; // the block ended
    assets.add(trimmed.substring(2).trim());
  }
  return assets;
}

void main() {
  // The suite runs in `app/`, which is what these relative paths are against.
  final pubspec = File('pubspec.yaml').readAsStringSync();
  final assets = declaredAssets(pubspec);

  test('the scan finds the asset block at all', () {
    // Without this, every assertion below passes vacuously on an empty list.
    expect(assets, isNotEmpty);
    expect(assets, contains('assets/data/title_aliases.json'));
  });

  test('no declared asset escapes the app package', () {
    for (final asset in assets) {
      expect(asset.startsWith('../'), isFalse,
          reason: '$asset is written outside build/flutter_assets/ and '
              'reaches no built app; move it under app/');
      expect(asset.startsWith('/'), isFalse, reason: '$asset is absolute');
    }
  });

  test('every declared asset is a file that exists', () {
    for (final asset in assets) {
      expect(File(asset).existsSync(), isTrue,
          reason: 'pubspec.yaml declares $asset and there is no such file');
    }
  });
}
