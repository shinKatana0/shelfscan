// Assert that every asset key `AssetManifest.bin` names is actually a file
// inside the bundle that carries the manifest.
//
// Why this is a script and not a test (T-0386). `flutter test` builds its own
// bundle at `app/build/unit_test_assets/`, one directory below `app/build/`.
// A key beginning `../` resolved from there lands on `app/build/`, which is
// exactly where such a key drops its file during a build -- so a widget test
// loads an asset a packaged app does not carry, and passes. The escape is
// harmless in a test and fatal in a package, so only a built bundle can
// answer this. Run it after `flutter build`.
//
// usage: dart run tool/check-bundle-assets.dart [BUNDLE...]
//
//   BUNDLE  a directory holding AssetManifest.bin, or an .apk/.zip whose
//           assets/flutter_assets/ holds one. With no argument, every known
//           build output under app/build/ that exists is checked.
//
// exit: 0 every key present | 1 a key has no file | 2 nothing was checked
//
// Exit 2 matters as much as exit 1: a run that found no bundle has proved
// nothing, and must not read as green (doc/conventions.md 4a).
//
// What it prints is a scratch reading, not an artefact: the bundle labels are
// absolute paths of the machine that ran it, so do not paste the output into
// anything committed. `tool/check-suites.sh` says the same of its logs.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Build outputs looked at when no argument is given, relative to the
/// repository root. `flutter_assets` under a runner is what ships; the one
/// directly under `app/build/` is the intermediate the packaging step copies,
/// and it is listed because a key escapes there first.
const defaultBundles = <String>[
  'app/build/flutter_assets',
  'app/build/windows/x64/runner/Debug/data/flutter_assets',
  'app/build/windows/x64/runner/Profile/data/flutter_assets',
  'app/build/windows/x64/runner/Release/data/flutter_assets',
  'app/build/unit_test_assets',
  'app/build/app/outputs/flutter-apk/app-debug.apk',
  'app/build/app/outputs/flutter-apk/app-release.apk',
];

/// Where a Flutter bundle sits inside an Android package.
const apkBundlePrefix = 'assets/flutter_assets/';

void main(List<String> args) {
  if (args.contains('-h') || args.contains('--help')) {
    stdout.write(_usage);
    exit(0);
  }

  final root = _repositoryRoot();
  final targets = args.isNotEmpty
      ? args
      : [
          for (final b in defaultBundles)
            if (_exists('$root/$b')) '$root/$b',
        ];

  if (targets.isEmpty) {
    stderr.writeln('check-bundle-assets: no built bundle found.');
    stderr.writeln('Build first, then re-run:');
    stderr.writeln('  cd app && flutter build windows --debug');
    exit(2);
  }

  var checked = 0;
  var failed = false;
  for (final target in targets) {
    final bundle = _open(target);
    if (bundle == null) {
      stderr.writeln('$target: no AssetManifest.bin here -- not a bundle.');
      failed = true;
      continue;
    }
    checked++;
    failed = !_report(bundle) || failed;
  }

  if (checked == 0) {
    stderr.writeln('check-bundle-assets: nothing was checked.');
    exit(2);
  }
  stdout.writeln(failed
      ? 'BUNDLE ASSETS: MISSING -- the manifest names files the bundle '
          'does not carry.'
      : 'BUNDLE ASSETS: OK -- $checked bundle(s), every manifest key present.');
  exit(failed ? 1 : 0);
}

const _usage = '''
usage: dart run tool/check-bundle-assets.dart [BUNDLE...]

  BUNDLE  a directory holding AssetManifest.bin, or an .apk/.zip whose
          assets/flutter_assets/ holds one. Default: every known build
          output under app/build/ that exists.

exit: 0 every key present | 1 a key has no file | 2 nothing was checked
''';

/// One bundle, reduced to what the check needs: its manifest and the set of
/// paths it holds.
class Bundle {
  Bundle({required this.label, required this.manifest, required this.paths});

  final String label;
  final Uint8List manifest;

  /// Every file in the bundle, as a bundle-relative slash-separated path.
  final Set<String> paths;
}

bool _report(Bundle bundle) {
  final Map<String, Set<String>> wanted;
  try {
    wanted = _manifestPaths(bundle.manifest);
  } on Object catch (e) {
    stderr.writeln('${bundle.label}: AssetManifest.bin unreadable ($e).');
    return false;
  }

  final missing = <String, List<String>>{};
  for (final entry in wanted.entries) {
    final absent = entry.value.where((p) => !bundle.paths.contains(p)).toList()
      ..sort();
    if (absent.isNotEmpty) missing[entry.key] = absent;
  }

  stdout.writeln('== ${bundle.label}');
  stdout.writeln('   ${wanted.length} manifest key(s), '
      '${bundle.paths.length} file(s) in the bundle.');
  if (missing.isEmpty) {
    stdout.writeln('   OK: every key resolves to a file.');
    return true;
  }
  stdout.writeln('   MISSING: ${missing.length} key(s) name no file here.');
  for (final entry in missing.entries) {
    stdout.writeln('     key  ${entry.key}');
    for (final path in entry.value) {
      stdout.writeln('       no file at  $path');
    }
  }
  // A `../` key is the one cause measured here, so name it rather than
  // leaving the next reader to rediscover T-0386.
  if (missing.keys.any((k) => k.startsWith('../'))) {
    stdout.writeln('   A key beginning `../` is written relative to '
        'build/flutter_assets/ and');
    stdout.writeln('   therefore lands outside it. Declare the asset from '
        'inside app/ instead.');
  }
  return false;
}

/// Asset key -> every bundle-relative path that key promises: the key itself
/// and each variant's `asset` entry.
Map<String, Set<String>> _manifestPaths(Uint8List bytes) {
  final decoded = _StandardMessageReader(bytes).read();
  if (decoded is! Map) {
    throw FormatException('manifest is ${decoded.runtimeType}, not a map');
  }
  final out = <String, Set<String>>{};
  decoded.forEach((key, value) {
    if (key is! String) return;
    final paths = <String>{key};
    if (value is List) {
      for (final variant in value) {
        if (variant is Map && variant['asset'] is String) {
          paths.add(variant['asset'] as String);
        }
      }
    }
    out[key] = paths;
  });
  return out;
}

Bundle? _open(String target) {
  if (Directory(target).existsSync()) return _openDirectory(target);
  if (File(target).existsSync()) return _openArchive(target);
  return null;
}

Bundle? _openDirectory(String dir) {
  final manifest = File('$dir/AssetManifest.bin');
  if (!manifest.existsSync()) return null;
  final paths = <String>{};
  for (final e in Directory(dir).listSync(recursive: true)) {
    if (e is! File) continue;
    paths.add(e.path
        .substring(dir.length + 1)
        .replaceAll(r'\', '/'));
  }
  return Bundle(
      label: dir, manifest: manifest.readAsBytesSync(), paths: paths);
}

Bundle? _openArchive(String path) {
  final zip = _Zip(File(path).readAsBytesSync());
  final names = zip.names
      .where((n) => n.startsWith(apkBundlePrefix) && !n.endsWith('/'))
      .toList();
  if (names.isEmpty) return null;
  final manifestName = '${apkBundlePrefix}AssetManifest.bin';
  if (!names.contains(manifestName)) return null;
  return Bundle(
    label: '$path ($apkBundlePrefix)',
    manifest: zip.read(manifestName),
    paths: {for (final n in names) n.substring(apkBundlePrefix.length)},
  );
}

String _repositoryRoot() {
  var dir = File(Platform.script.toFilePath()).parent.parent;
  return dir.path.replaceAll(r'\', '/');
}

bool _exists(String path) =>
    Directory(path).existsSync() || File(path).existsSync();

/// Reader for the subset of Flutter's `StandardMessageCodec` wire format that
/// `AssetManifest.bin` uses. Written out here because the codec itself lives
/// in `package:flutter`, which a `dart run` script cannot import.
class _StandardMessageReader {
  _StandardMessageReader(this._bytes)
      : _data = ByteData.sublistView(_bytes);

  final Uint8List _bytes;
  final ByteData _data;
  int _pos = 0;

  Object? read() {
    final type = _bytes[_pos++];
    switch (type) {
      case 0:
        return null;
      case 1:
        return true;
      case 2:
        return false;
      case 3:
        return _take(4, () => _data.getInt32(_pos, Endian.host));
      case 4:
        return _take(8, () => _data.getInt64(_pos, Endian.host));
      case 5: // large int, written as a hex string
        return BigInt.parse(_string(), radix: 16);
      case 6:
        _align(8);
        return _take(8, () => _data.getFloat64(_pos, Endian.host));
      case 7:
        return _string();
      case 8:
        return _blob(1, 1);
      case 9:
        return _blob(4, 4);
      case 10:
        return _blob(8, 8);
      case 11:
        return _blob(8, 8);
      case 12:
        final n = _size();
        return [for (var i = 0; i < n; i++) read()];
      case 13:
        final n = _size();
        final map = <Object?, Object?>{};
        for (var i = 0; i < n; i++) {
          final key = read();
          map[key] = read();
        }
        return map;
      case 14:
        return _blob(4, 4);
      default:
        throw FormatException('unknown value type $type at ${_pos - 1}');
    }
  }

  T _take<T>(int width, T Function() get) {
    final value = get();
    _pos += width;
    return value;
  }

  void _align(int to) {
    final over = _pos % to;
    if (over != 0) _pos += to - over;
  }

  int _size() {
    final first = _bytes[_pos++];
    if (first < 254) return first;
    if (first == 254) return _take(2, () => _data.getUint16(_pos, Endian.host));
    return _take(4, () => _data.getUint32(_pos, Endian.host));
  }

  String _string() {
    final n = _size();
    final s = utf8.decode(Uint8List.sublistView(_bytes, _pos, _pos + n));
    _pos += n;
    return s;
  }

  /// Typed lists are not read -- the manifest holds none -- but they must be
  /// stepped over correctly if one ever appears, or every value after it
  /// decodes as rubbish.
  Object? _blob(int elementSize, int alignment) {
    final n = _size();
    _align(alignment);
    _pos += n * elementSize;
    return null;
  }
}

/// The little of the ZIP format an .apk listing needs: the central directory
/// for the names, and one entry inflated for the manifest. `dart:io` supplies
/// the only hard part (raw deflate), so this adds no dependency.
class _Zip {
  _Zip(this._bytes) : _data = ByteData.sublistView(_bytes) {
    final eocd = _findEndOfCentralDirectory();
    final count = _data.getUint16(eocd + 10, Endian.little);
    final offset = _data.getUint32(eocd + 16, Endian.little);
    if (count == 0xFFFF || offset == 0xFFFFFFFF) {
      // Refuse rather than report a partial listing as a complete one.
      throw const FormatException('ZIP64 archive; this reader does not '
          'handle one, so its listing would be incomplete');
    }
    var p = offset;
    for (var i = 0; i < count; i++) {
      if (_data.getUint32(p, Endian.little) != 0x02014b50) {
        throw FormatException('central directory entry $i is malformed');
      }
      final method = _data.getUint16(p + 10, Endian.little);
      final compressed = _data.getUint32(p + 20, Endian.little);
      final nameLength = _data.getUint16(p + 28, Endian.little);
      final extraLength = _data.getUint16(p + 30, Endian.little);
      final commentLength = _data.getUint16(p + 32, Endian.little);
      final local = _data.getUint32(p + 42, Endian.little);
      final name = utf8.decode(
          Uint8List.sublistView(_bytes, p + 46, p + 46 + nameLength));
      _entries[name] = _ZipEntry(method, compressed, local);
      p += 46 + nameLength + extraLength + commentLength;
    }
  }

  final Uint8List _bytes;
  final ByteData _data;
  final _entries = <String, _ZipEntry>{};

  Iterable<String> get names => _entries.keys;

  Uint8List read(String name) {
    final entry = _entries[name]!;
    final nameLength = _data.getUint16(entry.local + 26, Endian.little);
    final extraLength = _data.getUint16(entry.local + 28, Endian.little);
    final start = entry.local + 30 + nameLength + extraLength;
    final raw = Uint8List.sublistView(_bytes, start, start + entry.compressed);
    if (entry.method == 0) return raw;
    if (entry.method != 8) {
      throw FormatException('$name uses compression method ${entry.method}');
    }
    return Uint8List.fromList(ZLibCodec(raw: true).decode(raw));
  }

  int _findEndOfCentralDirectory() {
    // The comment field is at most 64 KB, so the record is within that of
    // the end.
    final floor = _bytes.length - 22 - 0xFFFF;
    for (var p = _bytes.length - 22; p >= (floor < 0 ? 0 : floor); p--) {
      if (_data.getUint32(p, Endian.little) == 0x06054b50) return p;
    }
    throw const FormatException('no end-of-central-directory record');
  }
}

class _ZipEntry {
  _ZipEntry(this.method, this.compressed, this.local);

  final int method;
  final int compressed;
  final int local;
}
