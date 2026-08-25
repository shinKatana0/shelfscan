/// `tool/check-bundle-assets.dart` has two failures to tell apart, and this
/// pins which one it reports (T-0389).
///
/// A manifest key with no file behind it means either that the declaration is
/// wrong -- the `../` escape T-0386 exists for -- or that the artefact was
/// built before the declaration it is being judged against and simply carries
/// the older layout. The check reported the first wording for both, which
/// sends a reader to fix a `pubspec.yaml` that is already correct.
///
/// Neither case is allowed to pass, so every test here asserts exit 1 as well
/// as the wording: a bundle that cannot run correctly must not read as green.
///
/// **No build is involved.** Each case is a synthetic repository in a
/// temporary directory -- a copy of the real script, a stand-in
/// `app/pubspec.yaml` read only for its mtime, and a hand-encoded
/// `AssetManifest.bin` -- so both timestamps are set rather than measured and
/// the comparison is deterministic on any machine. The script under test is
/// the committed file, copied byte for byte.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';

/// Invented, and fixed so the expected output can be written down.
final _declaredAt = DateTime(2020, 6, 15, 12, 0, 0);
final _olderThanDeclaration = DateTime(2020, 6, 15, 10, 0, 0);
final _newerThanDeclaration = DateTime(2020, 6, 15, 14, 0, 0);

const _escapingKey = '../data/aliases.json';
const _containedKey = 'assets/data/aliases.json';

const _staleRemedy = 'Rebuild it and re-run.';
const _declarationRemedy = 'Declare the asset from inside app/ instead.';

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('bundle-age-'));
  tearDown(() => root.deleteSync(recursive: true));

  test('an artefact older than the declaration is told to rebuild', () {
    _plant(root,
        key: _escapingKey, carried: false, built: _olderThanDeclaration);

    final run = _check(root);

    expect(run.exitCode, 1, reason: 'a stale bundle must not pass');
    expect(run.out, contains('MISSING: 1 key(s) name no file here.'));
    expect(run.out, contains('STALE'));
    expect(run.out, contains('built     2020-06-15 10:00:00'));
    expect(run.out, contains('declared  2020-06-15 12:00:00'));
    expect(run.out, contains(_staleRemedy));
    expect(run.out, contains('BUNDLE ASSETS: STALE'));
    // The point of the task: the reader is not sent to a correct pubspec.
    expect(run.out, isNot(contains(_declarationRemedy)));
  });

  test('an artefact newer than the declaration keeps the `../` remedy', () {
    _plant(root,
        key: _escapingKey, carried: false, built: _newerThanDeclaration);

    final run = _check(root);

    expect(run.exitCode, 1);
    expect(run.out, contains('MISSING: 1 key(s) name no file here.'));
    expect(run.out, contains(_declarationRemedy));
    expect(run.out, contains('BUNDLE ASSETS: MISSING'));
    expect(run.out, isNot(contains('STALE')));
  });

  test('age alone is not a failure: an older complete bundle passes', () {
    _plant(root,
        key: _containedKey, carried: true, built: _olderThanDeclaration);

    final run = _check(root);

    expect(run.exitCode, 0);
    expect(run.out, contains('OK: every key resolves to a file.'));
    expect(run.out, isNot(contains('STALE')));
  });
}

/// One run of the copied script over the planted repository, with no argument
/// so the default bundle list is exercised too.
_Run _check(Directory root) {
  final result = Process.runSync(
    Platform.resolvedExecutable,
    ['run', '${root.path}/tool/check-bundle-assets.dart'],
    workingDirectory: root.path,
  );
  return _Run(result.exitCode, '${result.stdout}${result.stderr}');
}

class _Run {
  _Run(this.exitCode, this.out);

  final int exitCode;
  final String out;
}

/// Builds a repository holding the script, a declaration and one bundle at
/// `app/build/flutter_assets`, which is the first entry of the script's own
/// default list.
void _plant(
  Directory root, {
  required String key,
  required bool carried,
  required DateTime built,
}) {
  final tool = File('${root.path}/tool/check-bundle-assets.dart');
  tool.parent.createSync(recursive: true);
  File('${_repoRoot.path}/tool/check-bundle-assets.dart').copySync(tool.path);

  // Content is never read -- only this file's mtime is, as the moment the
  // asset layout was last declared.
  final declaration = File('${root.path}/app/pubspec.yaml');
  declaration.parent.createSync(recursive: true);
  declaration.writeAsStringSync('name: planted\n');
  declaration.setLastModifiedSync(_declaredAt);

  final bundle = Directory('${root.path}/app/build/flutter_assets');
  bundle.createSync(recursive: true);
  if (carried) {
    final asset = File('${bundle.path}/$key');
    asset.parent.createSync(recursive: true);
    asset.writeAsStringSync('{}\n');
  }
  final manifest = File('${bundle.path}/AssetManifest.bin');
  manifest.writeAsBytesSync(_manifestBytes({key: key}));
  manifest.setLastModifiedSync(built);
}

late final Directory _repoRoot = () {
  for (var dir = Directory.current.absolute;; dir = dir.parent) {
    if (File('${dir.path}/.env.example').existsSync()) return dir;
    if (dir.path == dir.parent.path) {
      fail('no .env.example at or above ${Directory.current.path}');
    }
  }
}();

/// `AssetManifest.bin` as Flutter writes it: a `StandardMessageCodec` map of
/// asset key -> list of variants, each a map carrying an `asset` path. Only
/// the short form of the size field is written, which every value here is
/// well inside.
Uint8List _manifestBytes(Map<String, String> keyToVariant) {
  final out = BytesBuilder();
  void size(int n) {
    if (n >= 254) fail('the test writer handles the short size field only');
    out.addByte(n);
  }

  void string(String value) {
    final bytes = utf8.encode(value);
    out.addByte(7);
    size(bytes.length);
    out.add(bytes);
  }

  out.addByte(13);
  size(keyToVariant.length);
  keyToVariant.forEach((key, variant) {
    string(key);
    out.addByte(12);
    size(1);
    out.addByte(13);
    size(1);
    string('asset');
    string(variant);
  });
  return out.toBytes();
}
