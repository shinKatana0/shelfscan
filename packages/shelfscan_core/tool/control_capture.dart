/// Captures local control detections for repeatable offline checks.
///
/// Control photographs and their detections are private. Captures stay outside
/// the repository; this tool reports status and counts without printing titles.
/// A checkout without the local control definition reports UNVERIFIABLE.
///
/// Usage, from `packages/shelfscan_core`:
///
///     dart run tool/control_capture.dart where
///     dart run tool/control_capture.dart status [CONTROL-HIRES|CONTROL-LOWRES|all]
///     dart run tool/control_capture.dart capture CONTROL-HIRES|CONTROL-LOWRES|all
///     dart run tool/control_capture.dart replay CONTROL-HIRES|CONTROL-LOWRES|all
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shelfscan_core/shelfscan_core.dart';

/// Bumped when the file layout below changes. An older format is
/// [Verdict.unverifiable], not "probably fine": the whole class of defect here
/// is two things that are supposed to agree drifting apart.
const captureFormat = 1;

const hiRes = 'CONTROL-HIRES';
const lowRes = 'CONTROL-LOWRES';

/// The model fixed for local control captures. A different model gets a
/// different capture identity even if the app default changes.
const controlSetModel = 'qwen2.5vl:7b';

/// FNV-1a over the UTF-8 prompt bytes, as eight hex digits. This check
/// needs a stable fingerprint, without another package dependency.
String promptFingerprint(String text) {
  var hash = 0x811c9dc5;
  for (final byte in utf8.encode(text)) {
    hash = ((hash ^ byte) * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

/// The `control-set` fenced blocks of [markdown], by section name.
Map<String, Map<String, String>> parseManifest(String markdown) {
  final sections = <String, Map<String, String>>{};
  Map<String, String>? current;
  var inBlock = false;
  for (final line in const LineSplitter().convert(markdown)) {
    final trimmed = line.trim();
    if (trimmed == '```control-set') {
      inBlock = true;
      continue;
    }
    if (!inBlock) continue;
    if (trimmed == '```') {
      inBlock = false;
      current = null;
      continue;
    }
    final header = RegExp(r'^\[([A-Z0-9-]+)\]$').firstMatch(trimmed);
    if (header != null) {
      current = sections.putIfAbsent(header.group(1)!, () => {});
      continue;
    }
    final entry = RegExp(r'^([A-Za-z0-9_]+)\s*=\s*(.*)$').firstMatch(trimmed);
    if (entry != null && current != null) {
      current[entry.group(1)!] = entry.group(2)!.trim();
    }
  }
  return sections;
}

/// The public set labels and prompt fingerprint, relative to the repo root.
const manifestPath = 'doc/control-set-manifest.md';

/// Repository root, found by walking up from [from].
Directory? findRepoRoot(Directory from) {
  for (var dir = from.absolute;; dir = dir.parent) {
    if (File('${dir.path}/$manifestPath').existsSync()) return dir;
    if (dir.path == dir.parent.path) return null;
  }
}

/// The manifest blocks of the repository at [root].
Map<String, Map<String, String>> readManifest(Directory root) =>
    parseManifest(File('${root.path}/$manifestPath').readAsStringSync());

/// The untracked control definition beside the private photographs.
const controlSetPath = 'doc/control-set.md';

/// The `control-set` blocks of [controlSetPath], or null where that document is
/// absent -- which is every machine but the one holding the photographs.
Map<String, Map<String, String>>? readPrivateControlSet(Directory root) {
  final file = File('${root.path}/$controlSetPath');
  return file.existsSync() ? parseManifest(file.readAsStringSync()) : null;
}

/// Merge local photograph names, sizes and outcomes with the public prompt pin.
/// A clone without the local definition retains only the public set labels.
Map<String, Map<String, String>> readManifestWithSizes(Directory root) {
  final private = readPrivateControlSet(root);
  if (private == null) return readManifest(root);
  return {
    for (final entry in readManifest(root).entries)
      entry.key: {...entry.value, ...?private[entry.key]},
  };
}

List<String> manifestList(String value) =>
    value.split(',').map((part) => part.trim()).toList();

/// The local photograph names and byte sizes, in scan order.
Map<String, int> manifestPhotos(Map<String, String> section) {
  final listed = section['photos'];
  if (listed == null || listed.trim().isEmpty) {
    throw StateError('this control-set section states no photographs: they '
        'are in $controlSetPath beside the photographs, not in $manifestPath, '
        'so read the manifest with readManifestWithSizes');
  }
  final names = manifestList(listed);
  final stated = section['sizes'];
  if (stated == null) {
    throw StateError('this control-set section states no byte sizes: they are '
        'in $controlSetPath beside the photographs, not in $manifestPath, so '
        'read the manifest with readManifestWithSizes');
  }
  final sizes = manifestList(stated).map(int.parse).toList();
  if (sizes.length != names.length) {
    throw StateError('$controlSetPath names a different number of photographs '
        'and sizes for this control set');
  }
  return {for (var i = 0; i < names.length; i++) names[i]: sizes[i]};
}

/// The local platform-hint counts for a control set.
Map<String, int> manifestHints(Map<String, String> section) => {
      for (final entry in section.entries)
        if (entry.key.startsWith('hint_'))
          entry.key.substring('hint_'.length): int.parse(entry.value),
    };

// --------------------------------------------------------------------- //
// What cannot be checked here, and how that is said

/// `status` on a checkout that does not hold the local control definition.
///
/// Not 3, which means regenerate: without the control photographs there is
/// nothing to regenerate from, and a caller reading 3 here would be sent to
/// buy a vision pass it cannot buy. Not 0 either -- nothing was checked.
const notHereExit = 4;

/// A named failure when a public set identifier is absent.
String? blockMissing(Map<String, Map<String, String>> manifest, String name) =>
    manifest.containsKey(name)
        ? null
        : '$manifestPath holds no [$name] block. A control set is a '
            'control-set fenced block naming a set; the two this '
            'tool knows are [$hiRes] and [$lowRes].';

/// Why local control data cannot be checked here, or null when it can.
String? figuresNotHere(Directory root) {
  final local = readPrivateControlSet(root);
  if (local == null) {
    return 'the control definition this check needs is in $controlSetPath '
        'beside the photographs, and it is not on this machine';
  }
  for (final name in [hiRes, lowRes]) {
    if (local[name]?['photos']?.trim().isNotEmpty != true) {
      return '$controlSetPath needs a photos entry for [$name] beside the '
          'other local control data';
    }
  }
  return null;
}

/// What `status` answers where [figuresNotHere] does.
///
/// A named verdict rather than a throw, because the ladder already has the
/// word for it and because a stack trace tells a reader nothing to act on --
/// which is the same defect as a silent failure, from the other end.
List<String> notHereReport(List<String> sets, String reason) => [
      for (final name in sets)
        '$name: ${Verdict.unverifiable.name.toUpperCase()} -- $reason',
      '',
      'Nothing to do on this checkout: a capture is made, and checked, where '
          'the control photographs are. What can be checked without them -- '
          'that the prompt those figures belong to has not moved -- runs in '
          '`dart test` on every machine.',
    ];

// --------------------------------------------------------------------- //
// Where a capture lives

/// Store private captures outside the repository in a stable user cache.
String captureDir(Map<String, String> env) {
  final explicit = env['SHELFSCAN_CAPTURE_DIR']?.trim();
  if (explicit != null && explicit.isNotEmpty) return _slashes(explicit);
  for (final (variable, suffix) in [
    ('LOCALAPPDATA', 'shelfscan/control-capture'),
    ('XDG_CACHE_HOME', 'shelfscan/control-capture'),
    ('HOME', '.cache/shelfscan/control-capture'),
  ]) {
    final base = env[variable]?.trim();
    if (base != null && base.isNotEmpty) return _slashes('$base/$suffix');
  }
  throw StateError('No LOCALAPPDATA, XDG_CACHE_HOME or HOME in the '
      'environment -- set SHELFSCAN_CAPTURE_DIR to a directory outside the '
      'repository.');
}

/// One separator in every message, so two runs quoting the same path quote
/// the same string. Windows accepts either.
String _slashes(String path) => path.replaceAll(r'\', '/');

/// The key includes every input that can change a control result. A new
/// model or server setting gets a separate capture file.
class CaptureKey {
  const CaptureKey({
    required this.controlSet,
    required this.fingerprint,
    required this.promptChars,
    required this.provider,
    required this.model,
    required this.ollamaUrl,
    required this.numParallel,
    required this.temperature,
    required this.seed,
    required this.photos,
  });

  final String controlSet;
  final String fingerprint;
  final int promptChars;
  final String provider;
  final String model;
  final String ollamaUrl;

  /// What the *client* could see of a *server* setting: `OLLAMA_NUM_PARALLEL`
  /// from this process's environment, or `unset` (Ollama's default is 1). A
  /// server on another host can be at 4 with nothing here to say so, which is
  /// why [ollamaUrl] is part of the key as well.
  final String numParallel;

  final double temperature;
  final int seed;

  /// Photo name to byte size, in scan order. A re-crop or a re-export moves a
  /// size, which is level 2 of `doc/control-set.md`'s staleness ladder.
  final Map<String, int> photos;

  String get fileName =>
      '$controlSet.$fingerprint.${model.replaceAll(':', '-')}'
      '.np$numParallel.json';

  Map<String, dynamic> toJson() => {
        'control_set': controlSet,
        'prompt_fingerprint': fingerprint,
        'prompt_chars': promptChars,
        'provider': provider,
        'model': model,
        'ollama_url': ollamaUrl,
        'ollama_num_parallel': numParallel,
        'temperature': temperature,
        'seed': seed,
        'photos': photos,
      };

  /// Null when any field is missing or wrongly typed -- the caller turns that
  /// into [Verdict.unverifiable].
  static CaptureKey? tryParse(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final photos = json['photos'];
    if (photos is! Map<String, dynamic> || photos.isEmpty) return null;
    final sizes = <String, int>{};
    for (final entry in photos.entries) {
      final size = entry.value;
      if (size is! int) return null;
      sizes[entry.key] = size;
    }
    for (final field in [
      'control_set',
      'prompt_fingerprint',
      'provider',
      'model',
      'ollama_url',
      'ollama_num_parallel',
    ]) {
      if (json[field] is! String) return null;
    }
    if (json['prompt_chars'] is! int) return null;
    if (json['temperature'] is! num) return null;
    if (json['seed'] is! int) return null;
    return CaptureKey(
      controlSet: json['control_set'] as String,
      fingerprint: json['prompt_fingerprint'] as String,
      promptChars: json['prompt_chars'] as int,
      provider: json['provider'] as String,
      model: json['model'] as String,
      ollamaUrl: json['ollama_url'] as String,
      numParallel: json['ollama_num_parallel'] as String,
      temperature: (json['temperature'] as num).toDouble(),
      seed: json['seed'] as int,
      photos: sizes,
    );
  }

  /// The first field of [other] that disagrees with this one, or null.
  String? firstDifference(CaptureKey other) {
    final mine = toJson();
    final theirs = other.toJson();
    for (final field in mine.keys) {
      if (jsonEncode(mine[field]) != jsonEncode(theirs[field])) {
        return '$field: capture has ${jsonEncode(theirs[field])}, '
            'this machine wants ${jsonEncode(mine[field])}';
      }
    }
    return null;
  }
}

/// The key a capture made here and now would carry.
CaptureKey wantedKey(String controlSet, Map<String, String> section,
    Map<String, String> env) {
  return CaptureKey(
    controlSet: controlSet,
    fingerprint: promptFingerprint(detectionPrompt),
    promptChars: detectionPrompt.length,
    provider: 'ollama',
    model: env['SHELFSCAN_OLLAMA_MODEL']?.trim().isNotEmpty == true
        ? env['SHELFSCAN_OLLAMA_MODEL']!.trim()
        : controlSetModel,
    ollamaUrl: env['SHELFSCAN_OLLAMA_URL']?.trim().isNotEmpty == true
        ? env['SHELFSCAN_OLLAMA_URL']!.trim()
        : defaultOllamaUrl,
    numParallel: env['OLLAMA_NUM_PARALLEL']?.trim().isNotEmpty == true
        ? env['OLLAMA_NUM_PARALLEL']!.trim()
        : 'unset',
    temperature: 0,
    seed: 20260814,
    photos: manifestPhotos(section),
  );
}

// --------------------------------------------------------------------- //
// Verdicts

enum Verdict {
  /// The only one that means "use it".
  fresh,

  absent,
  stale,

  /// Present and not checkable: unparseable, an unknown format, a key missing
  /// a field. Answered the same as [absent] on purpose.
  unverifiable,
}

class CaptureCheck {
  const CaptureCheck(this.verdict, this.path, this.reason);
  final Verdict verdict;
  final String path;
  final String reason;

  bool get usable => verdict == Verdict.fresh;
}

/// What to do about the capture for [want] at [path].
///
/// The counted figures are re-checked against the manifest on every call and
/// not only at capture time: a file truncated by a killed process parses, and
/// nothing else here would notice.
CaptureCheck checkCapture(
    String path, CaptureKey want, Map<String, String> section) {
  final file = File(path);
  if (!file.existsSync()) {
    return CaptureCheck(Verdict.absent, path, 'no capture at this path');
  }

  Object? decoded;
  try {
    decoded = jsonDecode(file.readAsStringSync());
  } on Object catch (e) {
    return CaptureCheck(Verdict.unverifiable, path, 'does not parse ($e)');
  }
  if (decoded is! Map<String, dynamic>) {
    return CaptureCheck(Verdict.unverifiable, path, 'is not a JSON object');
  }
  if (decoded['format'] != captureFormat) {
    return CaptureCheck(Verdict.unverifiable, path,
        'format ${decoded['format']}, this tool writes $captureFormat');
  }
  final have = CaptureKey.tryParse(decoded['key']);
  if (have == null) {
    return CaptureCheck(Verdict.unverifiable, path,
        'the "key" block is missing or incomplete, so nothing about this '
        'capture can be checked');
  }
  final difference = want.firstDifference(have);
  if (difference != null) {
    return CaptureCheck(Verdict.stale, path, difference);
  }

  final List<Detection> detections;
  final int unreadable;
  try {
    detections = readDetections(decoded);
    unreadable = (decoded['unreadable'] as List).length;
  } on Object catch (e) {
    return CaptureCheck(
        Verdict.unverifiable, path, 'the body does not read back ($e)');
  }
  final mismatch = manifestMismatch(detections, unreadable, section);
  if (mismatch != null) {
    return CaptureCheck(Verdict.stale, path, mismatch);
  }
  return CaptureCheck(Verdict.fresh, path, 'key and counts both agree');
}

List<Detection> readDetections(Map<String, dynamic> capture) => [
      for (final row in capture['detections'] as List)
        Detection.fromJson(row as Map<String, dynamic>),
    ];

/// Compare a capture with the local control definition.
String? manifestMismatch(
    List<Detection> detections, int unreadable, Map<String, String> section) {
  final photos = manifestPhotos(section);
  final stated = section['detections'];
  if (stated == null) {
    throw StateError('this control-set section states no counts: they are in '
        '$controlSetPath beside the photographs, not in $manifestPath, so '
        'read the manifest with readManifestWithSizes');
  }
  final expected = int.parse(stated);
  if (detections.length != expected) {
    return 'holds ${detections.length} detections, $controlSetPath states '
        '$expected';
  }
  final perPhoto = countByPhoto(detections);
  final wantPerPhoto = manifestList(section['per_photo']!).map(int.parse);
  final havePerPhoto = [for (final name in photos.keys) perPhoto[name] ?? 0];
  if (!_sameInts(havePerPhoto, wantPerPhoto.toList())) {
    return 'per-photo split is $havePerPhoto, $controlSetPath states '
        '${wantPerPhoto.toList()}';
  }
  final hints = countHints(detections);
  final wantHints = manifestHints(section);
  if (jsonEncode(_sorted(hints)) != jsonEncode(_sorted(wantHints))) {
    return 'the hint distribution moved: ${_sorted(hints)} against the '
        'manifest\'s ${_sorted(wantHints)}';
  }
  final empty =
      detections.where((d) => d.rawTitle.trim().isEmpty).length;
  if (empty != int.parse(section['empty_titles']!)) {
    return 'holds $empty empty titles, $controlSetPath states '
        '${section['empty_titles']}';
  }
  if (unreadable != int.parse(section['unreadable']!)) {
    return 'holds $unreadable unreadable entries, $controlSetPath states '
        '${section['unreadable']} -- a stale prompt cache can produce phantom '
        'entries; restart the model before capture';
  }
  return null;
}

bool _sameInts(List<int> a, List<int> b) =>
    a.length == b.length && List.generate(a.length, (i) => a[i] == b[i]).every((x) => x);

Map<String, int> _sorted(Map<String, int> counts) =>
    Map.fromEntries(counts.entries.toList()..sort((a, b) => a.key.compareTo(b.key)));

Map<String, int> countByPhoto(List<Detection> detections) {
  final counts = <String, int>{};
  for (final detection in detections) {
    counts[detection.sourcePhoto] = (counts[detection.sourcePhoto] ?? 0) + 1;
  }
  return counts;
}

Map<String, int> countHints(List<Detection> detections) {
  final counts = <String, int>{};
  for (final detection in detections) {
    final hint = detection.platformHint;
    if (hint == null || hint.isEmpty) continue;
    counts[hint] = (counts[hint] ?? 0) + 1;
  }
  return counts;
}

// --------------------------------------------------------------------- //
// Making one

/// Writes [content] to [path] through a uniquely named temporary file.
///
/// Two runs capturing the same key at once write identical bytes, so the
/// rename is safe whichever lands last; what it prevents is a reader seeing a
/// half-written file, which is the failure mode a plain write has and which
/// looks exactly like a corrupt capture.
void writeAtomically(String path, String content) {
  final temp = File('$path.${pid}.tmp');
  temp.parent.createSync(recursive: true);
  temp.writeAsStringSync(content);
  temp.renameSync(path);
}

/// Reads the control photos of [section] from [photoRoot], failing before any
/// call is paid for if a name or a byte size has moved.
List<PhotoInput> readControlPhotos(String controlSet, String photoRoot,
    Map<String, String> section) {
  final dir = controlSet == hiRes ? '$photoRoot/hires' : photoRoot;
  final photos = <PhotoInput>[];
  manifestPhotos(section).forEach((name, size) {
    final file = File('$dir/$name');
    if (!file.existsSync()) {
      throw StateError('$controlSet is missing $dir/$name -- the control set '
          'is the photographs, so there is nothing to capture without it');
    }
    final bytes = file.readAsBytesSync();
    if (bytes.length != size) {
      throw StateError('$dir/$name is ${bytes.length} bytes, the manifest '
          'states $size -- a re-crop or a re-export, and not the control '
          'photo any figure was measured on');
    }
    photos.add(PhotoInput(name: name, bytes: Uint8List.fromList(bytes)));
  });
  return photos;
}

/// Restart the model before capture so a prior prompt cache cannot affect
/// the local control result.
void stopModel(String model) {
  final result = Process.runSync('ollama', ['stop', model]);
  if (result.exitCode != 0) {
    throw StateError('"ollama stop $model" failed (${result.exitCode}): '
        '${result.stderr}. Without it the run can land in the third cache '
        'state and fabricate rows, so this is not skippable.');
  }
}

Future<Map<String, dynamic>> captureSet(String controlSet, CaptureKey key,
    String photoRoot, Map<String, String> section) async {
  final photos = readControlPhotos(controlSet, photoRoot, section);
  stopModel(key.model);
  final provider =
      OllamaVisionProvider(baseUrl: key.ollamaUrl, model: key.model);

  final detections = <Detection>[];
  final unreadable = <UnreadSpineReport>[];
  // One at a time, as `visionConcurrency` is for ollama in both shells: a
  // single scan then never overlaps itself whatever the server allows.
  for (final photo in photos) {
    final started = DateTime.now();
    final analysis = await provider.analyze(photo);
    detections.addAll(analysis.items);
    unreadable.addAll(analysis.unreadable);
    stdout.writeln('  ${photo.name}: ${analysis.items.length} detection(s), '
        '${analysis.unreadable.length} unreadable, '
        '${DateTime.now().difference(started).inSeconds} s');
  }

  return {
    'format': captureFormat,
    'key': key.toJson(),
    'captured': DateTime.now().toUtc().toIso8601String(),
    'counts': {
      'detections': detections.length,
      'per_photo': [for (final photo in photos) countByPhoto(detections)[photo.name] ?? 0],
      'unreadable': unreadable.length,
    },
    'detections': [for (final d in detections) d.toJson()],
    'unreadable': [for (final u in unreadable) u.toJson()],
  };
}

// --------------------------------------------------------------------- //

const _usage = '''
control_capture -- the control sets' detections, captured once

  dart run tool/control_capture.dart where
  dart run tool/control_capture.dart status  [CONTROL-HIRES|CONTROL-LOWRES|all]
  dart run tool/control_capture.dart capture [CONTROL-HIRES|CONTROL-LOWRES|all]
  dart run tool/control_capture.dart replay [CONTROL-HIRES|CONTROL-LOWRES|all]

`capture` needs SHELFSCAN_PHOTOS and a running Ollama; it runs `ollama stop`
itself. Everything else is offline and free.

Exit codes: 0 usable, 3 regenerate (absent, stale or unverifiable), 4 the
local control definition this check reads is not on this machine, 2 misuse.
''';

Future<int> run(List<String> args,
    {Directory? from, Map<String, String>? environment}) async {
  if (args.isEmpty) {
    stderr.writeln(_usage);
    return 2;
  }
  final env = environment ?? Platform.environment;
  final start = from ?? Directory.current;
  final root = findRepoRoot(start);
  if (root == null) {
    stderr.writeln('No $manifestPath at or above ${start.path}');
    return 2;
  }
  final manifest = readManifestWithSizes(root);
  final dir = captureDir(env);

  final command = args.first;
  final target = args.length > 1 ? args[1] : 'all';
  final sets = switch (target) {
    'all' => [hiRes, lowRes],
    hiRes => [hiRes],
    lowRes => [lowRes],
    _ => <String>[],
  };
  if (sets.isEmpty) {
    stderr.writeln('Unknown control set "$target". '
        'The only two are $hiRes and $lowRes ($manifestPath).');
    return 2;
  }

  // Before any command, because every one of them reads a figure and both
  // conditions leave the same question unanswerable.
  for (final name in sets) {
    final missing = blockMissing(manifest, name);
    if (missing != null) {
      stderr.writeln(missing);
      return 2;
    }
  }
  final notHere = figuresNotHere(root);
  if (notHere != null) {
    notHereReport(sets, notHere).forEach(stdout.writeln);
    return notHereExit;
  }

  CaptureCheck checkOf(String name) {
    final key = wantedKey(name, manifest[name]!, env);
    return checkCapture('$dir/${key.fileName}', key, manifest[name]!);
  }

  switch (command) {
    case 'where':
      stdout.writeln(dir);
      for (final name in sets) {
        stdout.writeln('  $name -> '
            '${wantedKey(name, manifest[name]!, env).fileName}');
      }
      return 0;

    case 'status':
      var usable = true;
      for (final name in sets) {
        final check = checkOf(name);
        usable &= check.usable;
        stdout.writeln('$name: ${check.verdict.name.toUpperCase()} '
            '-- ${check.reason}');
        stdout.writeln('  ${check.path}');
      }
      if (!usable) {
        stdout.writeln('\nREGENERATE: dart run tool/control_capture.dart '
            'capture $target');
      }
      return usable ? 0 : 3;

    case 'capture':
      final photoRoot = env['SHELFSCAN_PHOTOS'];
      if (photoRoot == null || !Directory(photoRoot).existsSync()) {
        stderr.writeln('Set SHELFSCAN_PHOTOS to the control photo directory. '
            'The control set is the photographs; without them there is '
            'nothing to capture and the local control definition is all '
            'there is.');
        return 2;
      }
      for (final name in sets) {
        final key = wantedKey(name, manifest[name]!, env);
        final path = '$dir/${key.fileName}';
        stdout.writeln('$name -> $path');
        final capture = await captureSet(name, key, photoRoot, manifest[name]!);
        final mismatch = manifestMismatch(
            readDetections(capture),
            (capture['unreadable'] as List).length,
            manifest[name]!);
        if (mismatch != null) {
          // Written anyway: a run that disagrees with the recorded figures is
          // a measurement, and deleting it leaves the next run to
          // rediscover it. It just does not pass `status`.
          writeAtomically(path, const JsonEncoder.withIndent('  ').convert(capture));
          stderr.writeln('WARN: this run does not reproduce the recorded '
              'figures -- '
              '$mismatch. Written, but `status` will call it stale. Check the '
              'photographs by eye before you believe either side.');
          return 3;
        }
        writeAtomically(path, const JsonEncoder.withIndent('  ').convert(capture));
        stdout.writeln('  ${(capture['counts'] as Map)['detections']} '
            'detections, reproduces the recorded figures.');
      }
      return 0;

    case 'replay':
      final detections = <Detection>[];
      for (final name in sets) {
        final check = checkOf(name);
        if (!check.usable) {
          stderr.writeln('$name: ${check.verdict.name.toUpperCase()} -- '
              '${check.reason}\nREGENERATE first: dart run '
              'tool/control_capture.dart capture $name');
          return 3;
        }
        final rows = readDetections(
            jsonDecode(File(check.path).readAsStringSync())
                as Map<String, dynamic>);
        final merged = dedupeDetections(rows);
        stdout.writeln('$name: ${rows.length} detections -> '
            '${merged.length} rows');
        detections.addAll(rows);
      }
      if (sets.length > 1) {
        detections.sort((a, b) => a.sourcePhoto.compareTo(b.sourcePhoto));
        final merged = dedupeDetections(detections);
        stdout.writeln('combined sets: ${detections.length} detections -> '
            '${merged.length} rows (${detections.length - merged.length} '
            'merges)');
      }
      return 0;

    default:
      stderr.writeln(_usage);
      return 2;
  }
}

Future<void> main(List<String> args) async => exit(await run(args));
