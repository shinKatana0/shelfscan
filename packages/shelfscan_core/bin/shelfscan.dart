/// CLI over shelfscan_core, for desktop (Windows) validation runs.
///
/// Every measurement doc/measurements.md quotes was taken here: it is the
/// harness a pipeline change is measured on before the Flutter shell sees it.
///
/// Usage:
///   dart run shelfscan_core:shelfscan scan ./photos -o collection.review.json
///   dart run shelfscan_core:shelfscan scan ./photos --provider ollama
///   dart run shelfscan_core:shelfscan scan-installs C:/Games -o collection.review.json
///   dart run shelfscan_core:shelfscan resolve collection.review.json -o resolved.json
///   # ... edit review.json: set "status" to approved/rejected per game ...
///   dart run shelfscan_core:shelfscan export collection.review.json --target tonkatsu -o shelf.xcoll
///
/// `scan` reads JPEG, PNG and WebP from the photo directory, and decides which
/// is which from each file's signature rather than from its name -- so a HEIC
/// that a phone or a messaging app renamed `.jpg` is converted here, exactly
/// as it is in the app (T-0056). Every other file is named on stderr with its
/// extension and skipped, and a directory that yields no photo at all is an
/// error exit rather than a "0 photos" success: HEIC is the phone camera
/// default, and a run that quietly measured the older JPEGs sitting beside
/// three new HEIC files would be indistinguishable from a real measurement
/// (T-0025).
///
/// HEIC is converted to JPEG in a temp directory on Windows before the vision
/// stage (T-0031) and skipped, named, everywhere else. Nothing is written next
/// to the originals.
///
/// `scan-installs` is the other way into the same review document: a directory
/// of installed games rather than photographs (T-0160). It is a command and not
/// a flag on `scan` because the two share nothing but their output -- the
/// positional argument is a different kind of directory, no photo is read, no
/// vision provider is built, and every option `scan` has is about a model.
///
/// It goes one level down and no further: the folder's own files and each
/// subdirectory by name, plus `goggame-*.info` inside a subdirectory and the
/// one installer in it that names a game the subdirectory does not. That last
/// one fires on two triggers, not the one it shipped with: a folder name that
/// titles nothing (T-0178), and a folder name that titles something the one
/// unmistakable installer inside contradicts outright (T-0183). Nothing else
/// in it. A game's `data/`, `Saves/` and `Redist/` subtrees never reach the
/// pipeline, which is what keeps the review list a list of games.
///
/// The input contract is "a games folder", and it is enforced only here and in
/// the app: nothing inside `shelfscan_core` can tell `NoteWellSetup.exe` from
/// `setup_moor_1.9.exe`, and T-0158 measured the price of pointing this at the
/// wrong directory: over a `Downloads` folder it titles every installer it
/// finds and not one of them is a game. So a small list of well-known personal
/// and system directories is refused outright, and every run says what it
/// reads.
///
/// `resolve` re-runs ONLY the IGDB stage over the detections already in a
/// review document: no photos are read and no vision provider is called.
/// It is how the resolver's match rate is measured and re-measured after a
/// scorer change, without paying for vision or fighting model
/// non-determinism. Detections are copied through untouched;
/// `best`/`candidates` are recomputed and `status` resets to pending,
/// because a new match invalidates an earlier human approval.
///
/// ## Adding an item the scan missed (manual add)
///
/// Some spines carry no readable text at all -- a logo-only case such as
/// Nocturne 5 Gold -- and the scan reports them as unreadable spines, or not
/// at all. `review.json` is hand-editable by design, so the supported way to
/// add one is to append a game block to `games` and re-run `resolve`:
///
///     {
///       "detection": {
///         "raw_title": "Nocturne 5 Gold",
///         "platform_hint": "PS4",
///         "media_type": "disc",
///         "origin": "manual"
///       }
///     }
///
/// `raw_title` is the only required field. `platform_hint` narrows the IGDB
/// search and is worth typing; `media_type` is cartridge|disc|unknown;
/// `origin: "manual"` marks the entry as human-entered rather than read off
/// a photo (omitting it means "vision", which is what every file written
/// before this feature says by omission). `source_photo`, `confidence`,
/// `notes`, `best`, `candidates` and `status` may all be left out -- a
/// manual entry was read off no photo and has no candidates until `resolve`
/// gives it some. `added_from_photo` is the one photo field a manual entry
/// may carry: the name of the photo the item was typed while looking at,
/// which is what files it under that photo on the review screen (T-0052).
/// It is not a claim that anything was read off that photo, and `resolve`,
/// the dedupe stage and both exporters ignore it.
///
///     dart run shelfscan_core:shelfscan resolve collection.review.json
///
/// resolves the hand-written entry exactly like a vision one. Without IGDB
/// credentials `resolve` refuses to run; the entry then stays unmatched,
/// which the csv export still carries (see below) and `.xcoll` does not.
///
/// Providers, in the order the app offers them too (T-0343):
///   --provider ollama      local, needs a running Ollama server (DEFAULT)
///                          (SHELFSCAN_OLLAMA_MODEL, SHELFSCAN_OLLAMA_URL to override)
///   --provider openai      any endpoint speaking the OpenAI
///                          /chat/completions API -- Groq, OpenRouter,
///                          Mistral, GitHub Models, Cerebras, Gemini's
///                          compatibility endpoint. Needs all three of
///                          SHELFSCAN_OPENAI_BASE_URL (up to and including
///                          the version segment, e.g.
///                          https://api.groq.com/openai/v1),
///                          SHELFSCAN_OPENAI_MODEL and
///                          SHELFSCAN_OPENAI_API_KEY.
///   --provider anthropic   cloud, needs ANTHROPIC_API_KEY
///                          (SHELFSCAN_ANTHROPIC_MODEL to override the model;
///                          a model named there is sent with no temperature)
///   Policy: on desktop local is the default; every cloud endpoint is an
///   explicit opt-in. Your photos are uploaded in full to whichever
///   endpoint you name, and free tiers are commonly funded by training on
///   what is submitted to them -- check the service's data policy first.
///
/// SHELFSCAN_VISION_TIMEOUT=<seconds> bounds ONE vision call, per photo, for
/// whichever provider is in use, fallback included. Unset is 120 s, which is
/// ~3.5x the slowest read measured here and deliberately below the one model
/// this project measured above it (`qwen2.5vl:32b`, ~360 s per hi-res photo
/// for want of VRAM -- doc/measurements.md). Point the tool at something that
/// large and this is the variable that lets it finish. 1 to 1800; anything
/// else is refused rather than quietly replaced by the default.
///
/// Fallback: a SECOND model that re-reads every photo, results merged
/// (T-0011, T-0032). Off unless asked for; when on it doubles the vision cost
/// of the run, one extra call per photo:
///   SHELFSCAN_OLLAMA_FALLBACK_MODEL=gemma3:12b   bigger LOCAL model
///   --fallback openai                             cloud, needs the three
///                                                 SHELFSCAN_OPENAI_* variables
///   --fallback anthropic                          cloud, needs ANTHROPIC_API_KEY
///   --fallback none                               off, whatever the env says
/// The env var can only ever select a local model: sending photos to the
/// cloud takes the explicit flag, because a run started as local must not
/// become a cloud run by way of an environment variable someone forgot about.
///
/// It used to fire by itself, on photos where the primary reported spines it
/// could not read. It no longer does, because that report does not exist: the
/// local model answers `unreadable: []` on every photo including ones with
/// unread spines on them, and across seven T-0028 prompt variants never named
/// a spine it had actually skipped. A trigger that fires on no photo is not a
/// safety net, so the choice is the user's, per run, and it is all photos or
/// none.
///
/// Worth knowing before switching it on: the only second reader measured here
/// (gemma3:12b behind qwen2.5vl:7b, three 4000x3000 photos) added 15 rows and
/// took 70 s to 146 s, and every added row was wrong -- most re-readings of
/// spines already read, the rest invented or misread outright.
/// Both models' reads
/// are merged, so a second model's mistakes land in the review list too. That
/// is what the review step is for, and a wrong row can be rejected there while
/// a missing one cannot -- but the trade is real and it is not free.
///
/// Resolution (IGDB) is optional: without IGDB_CLIENT_ID/IGDB_CLIENT_SECRET
/// the resolve stage is skipped and games stay unresolved in the review
/// file. Note: the tonkatsu export needs resolved IGDB ids and silently
/// omits every approved item without one; csv exports an unmatched item
/// using the detection's own title and platform hint.
///
/// Regional titles (Biohazard vs Resident Evil) are rewritten before the
/// IGDB search using `data/title_aliases.json`, found by walking up from the
/// working directory; `--aliases <file>` points at a different one. The file
/// is a flat JSON object, `"regional fragment": "igdb fragment"`, and editing
/// it needs no rebuild. Missing or malformed, it degrades to three built-in
/// aliases with a warning.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shelfscan_core/shelfscan_core.dart';

import 'galaxy_db.dart';

/// A file in the photo directory that the scan will not read.
class SkippedFile {
  SkippedFile({
    required this.name,
    required this.extension,
    required this.reason,
  });

  final String name;
  final String extension;
  final String reason;
}

/// One file turned into JPEG bytes before the vision stage, and what it cost.
class ConvertedPhoto {
  ConvertedPhoto({required this.name, required this.elapsed});

  final String name;
  final Duration elapsed;
}

/// What a photo directory holds: the files the scan takes, and every file it
/// does not.
class PhotoDirectory {
  PhotoDirectory({
    required this.photos,
    required this.skipped,
    this.converted = const [],
    this.conversionWallClock = Duration.zero,
  });

  final List<PhotoInput> photos;
  final List<SkippedFile> skipped;

  /// The subset of [photos] that reached memory through a conversion.
  final List<ConvertedPhoto> converted;

  /// Everything the conversion cost, process start included, so the figure
  /// reported is the one the run actually paid.
  final Duration conversionWallClock;

  int get fileCount => photos.length + skipped.length;
}

/// One file's outcome: JPEG bytes, or the reason there are none.
class HeicConversion {
  HeicConversion.ok(Uint8List this.bytes, this.elapsed) : error = null;
  HeicConversion.failed(String this.error, this.elapsed) : bytes = null;

  final Uint8List? bytes;
  final String? error;
  final Duration elapsed;
}

/// Converts every path in one call and answers for each of them.
///
/// A batch rather than one call per file because the ~2.1 s of PowerShell
/// start-up dominates the ~0.8 s a photo actually takes, and because a host
/// that cannot convert at all should say so once.
typedef HeicConverter = Map<String, HeicConversion> Function(List<String> paths);

/// Reads a tab-separated `source<TAB>target` list and writes one JPEG per
/// line, reporting `OK<TAB>source<TAB>ms` or `ERR<TAB>source<TAB>reason`.
///
/// Windows Imaging Component is the whole reason this is PowerShell and not
/// Dart: no pub package decodes HEIC (`image` cannot, and every HEIC package
/// on pub.dev is a Flutter plugin), while WIC ships with the OS and needs
/// nothing installed beyond the HEIF extension the camera app already pulls
/// in. Quality 95 is not a guess: it is what produced `photos/hires/`, whose
/// scan is what this feature is measured against.
///
/// One process for the whole batch, and a stopwatch inside the loop so the
/// reported per-file cost excludes the start-up the batch pays once.
const _wicConvertScript = r'''
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
Add-Type -AssemblyName PresentationCore
foreach ($line in [IO.File]::ReadAllLines($env:SHELFSCAN_HEIC_LIST, [Text.Encoding]::UTF8)) {
  if ([string]::IsNullOrWhiteSpace($line)) { continue }
  $pair = $line -split "`t"
  $watch = [Diagnostics.Stopwatch]::StartNew()
  try {
    $source = [IO.File]::OpenRead($pair[0])
    try {
      $decoder = [Windows.Media.Imaging.BitmapDecoder]::Create(
        $source,
        [Windows.Media.Imaging.BitmapCreateOptions]::None,
        [Windows.Media.Imaging.BitmapCacheOption]::OnLoad)
      $encoder = New-Object Windows.Media.Imaging.JpegBitmapEncoder
      $encoder.QualityLevel = 95
      $encoder.Frames.Add($decoder.Frames[0])
      $target = [IO.File]::Create($pair[1])
      try { $encoder.Save($target) } finally { $target.Dispose() }
    } finally { $source.Dispose() }
    "OK`t$($pair[0])`t$($watch.ElapsedMilliseconds)"
  } catch {
    "ERR`t$($pair[0])`t$($_.Exception.Message -replace '\s+', ' ')"
  }
}
''';

/// PowerShell's `-EncodedCommand` payload: UTF-16LE, then base64.
///
/// Preferred over a `.ps1` on disk because it is immune to both the machine's
/// execution policy and to quoting the script path.
String _encodePowerShellCommand(String script) {
  final units = script.codeUnits;
  final bytes = Uint8List(units.length * 2);
  for (var i = 0; i < units.length; i++) {
    bytes[i * 2] = units[i] & 0xff;
    bytes[i * 2 + 1] = units[i] >> 8;
  }
  return base64.encode(bytes);
}

/// Why [operatingSystem] cannot convert HEIC, or null when it can.
///
/// A pure function rather than a `Platform.isWindows` branch for the same
/// reason [fallbackProviderFor] is one: "the other host degrades to a named
/// skip" is the claim worth pinning down, and it cannot be pinned down on a
/// machine that is the supported one.
String? heicConversionUnsupported(String operatingSystem) =>
    operatingSystem == 'windows'
        ? null
        : 'HEIC decoding here is Windows-only (it uses the Windows Imaging '
            'Component) and this host is $operatingSystem';

/// Converts HEIC to JPEG through Windows WIC, in a temp directory.
///
/// Never throws and never fails the run: every path it was given comes back
/// either with bytes or with a reason, because a HEIC that goes unmentioned
/// is the exact failure T-0025 exists to prevent.
///
/// Measured on the three 4000x3000 control photographs: 1251 / 536 / 516 ms each
/// (the first pays for the codec warming up), 3.4 s wall clock for the batch
/// against ~25 s of vision per photo. The JPEGs it produced are byte-identical
/// to `photos/hires/`.
Map<String, HeicConversion> windowsHeicToJpeg(List<String> paths) {
  if (paths.isEmpty) return const {};
  Map<String, HeicConversion> allFailed(String reason) => {
        for (final path in paths) path: HeicConversion.failed(reason, Duration.zero)
      };
  final unsupported = heicConversionUnsupported(Platform.operatingSystem);
  if (unsupported != null) return allFailed(unsupported);

  final work = Directory.systemTemp.createTempSync('shelfscan_heic_');
  try {
    final targets = <String, String>{};
    final lines = <String>[];
    for (var i = 0; i < paths.length; i++) {
      final target = '${work.path}${Platform.pathSeparator}$i.jpg';
      targets[paths[i]] = target;
      lines.add('${paths[i]}\t$target');
    }
    final listFile = File('${work.path}${Platform.pathSeparator}files.tsv')
      ..writeAsStringSync(lines.join('\n'));

    final ProcessResult result;
    try {
      result = Process.runSync(
        'powershell.exe',
        [
          '-NoProfile',
          '-NonInteractive',
          '-EncodedCommand',
          _encodePowerShellCommand(_wicConvertScript),
        ],
        environment: {'SHELFSCAN_HEIC_LIST': listFile.path},
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
    } on ProcessException catch (e) {
      return allFailed('powershell.exe could not be run (${e.message})');
    }

    final results = <String, HeicConversion>{};
    for (final line in const LineSplitter().convert(result.stdout as String)) {
      final parts = line.split('\t');
      if (parts.length < 3 || !targets.containsKey(parts[1])) continue;
      final path = parts[1];
      if (parts[0] == 'OK') {
        final jpeg = File(targets[path]!);
        final bytes = jpeg.existsSync() ? jpeg.readAsBytesSync() : Uint8List(0);
        results[path] = bytes.isEmpty
            ? HeicConversion.failed('the converter produced an empty file',
                Duration.zero)
            : HeicConversion.ok(
                bytes, Duration(milliseconds: int.tryParse(parts[2]) ?? 0));
      } else {
        results[path] = HeicConversion.failed(parts[2], Duration.zero);
      }
    }

    // A file the script never reported on -- it died early, or PowerShell
    // itself did. Its stderr is the only clue the user would otherwise lose;
    // the missing HEIF extension surfaces exactly here.
    final silence = _firstLine(result.stderr as String) ??
        'the converter exited ${result.exitCode} without reporting on it';
    for (final path in paths) {
      results.putIfAbsent(
          path, () => HeicConversion.failed(silence, Duration.zero));
    }
    return results;
  } finally {
    work.deleteSync(recursive: true);
  }
}

String? _firstLine(String text) {
  for (final line in const LineSplitter().convert(text)) {
    if (line.trim().isNotEmpty) return line.trim();
  }
  return null;
}

/// What [file] holds, read from its first bytes rather than from its name.
///
/// A header read and not `readAsBytesSync`: every file in the directory is
/// classified, and a photo directory can hold a video beside the photos.
/// Unreadable is indistinguishable from "not a photo" here on purpose -- the
/// file is skipped either way, and the skip is named.
String? _sniffFile(File file) {
  final RandomAccessFile handle;
  try {
    handle = file.openSync();
  } on FileSystemException {
    return null;
  }
  try {
    return sniffImage(handle.readSync(imageSignatureLength));
  } on FileSystemException {
    return null;
  } finally {
    handle.closeSync();
  }
}

/// Why the scan is leaving a file out, worded as what to do about it.
String _skipReason(String? kind, String extension, String? conversionError) {
  if (conversionError != null) {
    return 'HEIC conversion failed -- $conversionError; convert it to .jpg or '
        '.png first';
  }
  if (kind == heicMimeType) {
    return 'a HEIC this host cannot convert; convert it to .jpg or .png first';
  }
  if (undecodableImageExtensions.contains(extension)) {
    return 'a photo this tool cannot decode; convert it to .jpg or .png first';
  }
  if (photoMimeTypes.containsKey(extension) ||
      convertibleMimeTypes.containsKey(extension)) {
    // The name promises a photo and the bytes are not one. Worth its own line
    // since the bytes started deciding (T-0056): without it the reply to
    // "but it is a .jpg" would be the vaguest message here.
    return 'named $extension but the bytes are not a photo this tool reads; '
        'the contents decide here, not the name';
  }
  return 'not a readable photo';
}

/// Reads [dir], sorting by path so a re-run scans photos in the same order.
///
/// Each file's type comes from its signature, never from its extension, so a
/// HEIC renamed `.jpg` is converted here exactly as it is in the app -- the
/// two shells drifted apart on precisely this case (T-0056).
///
/// Sub-directories are not reported: the skipped list is about files that
/// look like they were meant to be scanned.
///
/// [convertHeic] converts what it can and names what it cannot; omitting it
/// is the no-conversion host, where every HEIC lands in [PhotoDirectory
/// .skipped].
PhotoDirectory readPhotoDirectory(Directory dir, {HeicConverter? convertHeic}) {
  final files = <File>[
    for (final entity in dir.listSync()..sort((a, b) => a.path.compareTo(b.path)))
      if (entity is File) entity
  ];
  final kinds = {for (final file in files) file.path: _sniffFile(file)};

  final convertible = [
    for (final file in files)
      if (kinds[file.path] == heicMimeType) file.path
  ];
  final started = Stopwatch()..start();
  final conversions = convertHeic == null || convertible.isEmpty
      ? const <String, HeicConversion>{}
      : convertHeic(convertible);
  started.stop();

  final photos = <PhotoInput>[];
  final skipped = <SkippedFile>[];
  final converted = <ConvertedPhoto>[];
  for (final file in files) {
    final name = _nameOf(file);
    final kind = kinds[file.path];
    if (kind != null && !needsConversion(kind)) {
      photos.add(PhotoInput(
          name: name, bytes: file.readAsBytesSync(), mimeType: kind));
      continue;
    }
    final conversion = conversions[file.path];
    final bytes = conversion?.bytes;
    if (bytes != null) {
      // Keeps the original file name -- that is the file the user has, and
      // what `source_photo` should point at -- so the name still says .heic
      // while the bytes are JPEG.
      photos.add(
          PhotoInput(name: name, bytes: bytes, mimeType: 'image/jpeg'));
      converted.add(ConvertedPhoto(name: name, elapsed: conversion!.elapsed));
      continue;
    }
    final extension = extensionOf(name);
    skipped.add(SkippedFile(
      name: name,
      extension: extension,
      reason: _skipReason(kind, extension, conversion?.error),
    ));
  }
  return PhotoDirectory(
    photos: photos,
    skipped: skipped,
    converted: converted,
    conversionWallClock: converted.isEmpty ? Duration.zero : started.elapsed,
  );
}

String _nameOf(File file) => file.uri.pathSegments.last;

/// The extensions this run will read, in the words the user is shown.
///
/// Read off the core tables rather than typed here, and split by
/// [convertsHeic] rather than fixed, because both halves of that were wrong at
/// once: the message named [photoMimeTypes] alone, so a Windows run printed
/// `Accepted: .jpg, .jpeg, .png, .webp` in the same output as
/// `CONVERTED: ...HEIC -> jpeg` and told a phone owner their photos were not
/// accepted immediately after accepting them (T-0077). Naming the convertible
/// extensions unconditionally would only move the contradiction to the host
/// that skips them.
String acceptedList({required bool convertsHeic}) {
  final direct = photoMimeTypes.keys.join(', ');
  return convertsHeic
      ? '$direct, and ${convertibleMimeTypes.keys.join(', ')} '
          '(converted to JPEG first)'
      : direct;
}

/// The host, not the listing: a directory that happens to hold no HEIC must
/// still tell the user HEIC would have been read.
bool get _convertsHeic =>
    heicConversionUnsupported(Platform.operatingSystem) == null;

/// Stderr lines naming every file the scan is about to leave out.
///
/// The failure this exists to prevent: three new HEIC photos dropped into
/// `photos/` for a re-measurement, the scan reading only the two old JPEGs
/// beside them, and the run printing a summary indistinguishable from a real
/// measurement (T-0025). Hence one line per file plus a banner, rather than
/// a count folded into the summary.
List<String> skipReport(PhotoDirectory listing, {required bool convertsHeic}) {
  if (listing.skipped.isEmpty) return const [];
  return [
    for (final file in listing.skipped)
      'SKIPPED: ${file.name} '
          '(${file.extension.isEmpty ? 'no extension' : file.extension}) '
          '-- ${file.reason}',
    if (listing.photos.isNotEmpty)
      '!! ${listing.skipped.length} of ${listing.fileCount} file(s) in this '
          'directory will NOT be scanned. '
          'Accepted: ${acceptedList(convertsHeic: convertsHeic)}',
  ];
}

/// Stdout lines naming every file that was converted before it was read.
///
/// Per photo rather than a total, so the cost sits next to the ~25 s vision
/// call it is compared against and a slow file cannot hide in an average.
List<String> conversionReport(PhotoDirectory listing) {
  if (listing.converted.isEmpty) return const [];
  return [
    for (final photo in listing.converted)
      'CONVERTED: ${photo.name} -> jpeg in ${photo.elapsed.inMilliseconds} ms',
    'HEIC: ${listing.converted.length} file(s) converted to a temp directory '
        'in ${listing.conversionWallClock.inMilliseconds} ms total '
        '(process start included). Nothing was written next to the originals.',
  ];
}

/// How much of the directory the run actually covered, for the summary line.
///
/// A summary that reads "Scanned 2 photo(s)" is true and still misleading
/// when the directory held five files, and the summary is the line that ends
/// up quoted in a report.
String scanScope(PhotoDirectory listing) => listing.skipped.isEmpty
    ? '${listing.photos.length} photo(s)'
    : '${listing.photos.length} of ${listing.fileCount} file(s) '
        '(${listing.skipped.length} skipped, named above)';

/// Stdout lines for what the model said it saw and could not read.
///
/// The lines exist at all because a spine that was seen and not read is kept
/// out of `games` by design (T-0007), so without them a photo of unread
/// Japanese spines looks like an empty shelf.
///
/// They no longer say "Unreadable spines: N". The type was built as one entry
/// per spine and named `UnreadableSpine` for it; on `gpt-4.1-mini` it is not.
/// Measured over 10 runs of CONTROL-HIRES's shelf-3.jpg, every run
/// answers exactly ONE entry whose text names two or three middle spines,
/// against a hand count off the photograph that the entry never matches; a
/// second photo answers one entry on 8 runs and two on 2, for one and the
/// same group of spines both times (T-0109). So the number moved while the
/// photograph did not, and
/// it was never the number the label promised. `qwen2.5vl:7b` hid this because
/// since T-0028 it answers an empty array.
///
/// The fix is not a better count. The entry carries prose, and deriving a
/// number from prose would be the fabricated count T-0028 removed. So the line
/// states the unit it really counts, says out loud that spines are not it, and
/// prints the model's own wording underneath -- the only place the
/// several-spines case is visible at all.
List<String> unreadableReport(ReviewDocument doc) {
  if (doc.unreadable.isEmpty) return const [];
  final byScript = <SpineScript, int>{};
  for (final spine in doc.unreadable) {
    byScript[spine.script] = (byScript[spine.script] ?? 0) + 1;
  }
  String photoOf(String name) => name.isEmpty ? 'not from a photo' : name;
  return [
    'Unread-spine reports: ${doc.unreadable.length} -- one report can '
        'describe several spines, so this is not a count of spines.',
    '  by photo: ${doc.unreadableByPhoto.entries.map((e) => '${photoOf(e.key)}: ${e.value} report(s)').join(', ')}',
    '  by script: '
        '${byScript.entries.map((e) => '${e.key.name}: ${e.value}').join(', ')}',
    for (final spine in doc.unreadable)
      '  ${photoOf(spine.sourcePhoto)}: '
          '${spine.reason ?? 'reported with no reason given'}',
  ];
}

/// Why [path] cannot be listed as a photo directory, or null when it can.
///
/// The path is echoed back absolute and normalised, never as typed: the
/// failure this exists for is a relative path resolved against a directory
/// the user was not thinking about (`scan ../../photos` is right from one of
/// the two directories the CLI is run from and wrong from the other), and
/// there the unexpected absolute path is the entire answer.
String? scanPathError(String path) {
  final absolute =
      Uri.file(Directory(path).absolute.path).normalizePath().toFilePath();
  return switch (FileSystemEntity.typeSync(path)) {
    FileSystemEntityType.directory => null,
    FileSystemEntityType.notFound => 'No photo directory at $absolute',
    _ => 'Not a photo directory: $absolute is a file -- scan takes the '
        'directory that holds your photos, not one photo',
  };
}

/// Why [path] cannot be read as a review document, or null when it can.
///
/// The mirror of [scanPathError] for the two commands that take a file rather
/// than a directory, absolute and normalised for the same reason: `resolve`
/// and `export` are run both from the repository root and from
/// `packages/shelfscan_core`, so a relative path is right from one of the two
/// and wrong from the other, and echoing back what was typed hides that.
/// [command] names the caller so the second half of the message can say what
/// that command wanted instead.
String? reviewPathError(String path, String command) {
  final absolute = absoluteFilePath(path);
  return switch (FileSystemEntity.typeSync(path)) {
    FileSystemEntityType.file => null,
    FileSystemEntityType.notFound => 'No review file at $absolute',
    _ => 'Not a review file: $absolute is a directory -- $command takes the '
        'review.json written by scan, not the directory it sits in',
  };
}

/// The path echoed back by every file message: absolute and normalised, never
/// as typed. [reviewPathError] carries the reason.
String absoluteFilePath(String path) =>
    Uri.file(File(path).absolute.path).normalizePath().toFilePath();

/// Why `-o [path]` cannot be written, or null when it can.
///
/// The output side of [scanPathError] and [reviewPathError], and `scan` is why
/// it exists: the write is the last statement of a run that has already paid
/// for the vision stage -- 35 s warm on three photos, minutes on a larger
/// shelf -- so a mistyped `-o` used to throw the whole scan away with a
/// `PathNotFoundException` and exit 255 (T-0051). Absolute and normalised for
/// the same reason as the other two, and the missing-directory case names both
/// paths because the missing part is the one the user did not type.
///
/// A missing parent is refused rather than created: `-o repots/x.csv` would
/// otherwise succeed silently and leave the typo permanent on disk.
///
/// The last case is a probe rather than a rule. It opens the output path for
/// append -- which creates nothing that was not there and truncates nothing
/// that was -- and removes the file again only if it had to create it. That is
/// the one way to answer "not writable" for a permission the process lacks, a
/// name the OS rejects or a path too long, without restating the filesystem's
/// own rules here.
String? outputPathError(String path) {
  final absolute = absoluteFilePath(path);
  if (FileSystemEntity.typeSync(absolute) == FileSystemEntityType.directory) {
    return 'Not an output file: $absolute is a directory -- -o names the file '
        'to write, not the directory to write it into';
  }

  final parent = File(absolute).parent.path;
  final parentError = switch (FileSystemEntity.typeSync(parent)) {
    FileSystemEntityType.directory => null,
    FileSystemEntityType.notFound => 'No output directory at $parent -- -o '
        'writes $absolute, and nothing here creates a directory for you',
    _ => 'Not an output directory: $parent is a file -- -o writes $absolute, '
        'which would have to sit inside it',
  };
  if (parentError != null) return parentError;

  final existed = File(absolute).existsSync();
  try {
    File(absolute).openSync(mode: FileMode.append).closeSync();
    if (!existed) File(absolute).deleteSync();
  } on FileSystemException catch (e) {
    return 'Cannot write to $absolute -- ${e.osError?.message ?? e.message}';
  }
  return null;
}

/// Where a `jsonDecode` failure sits, in the terms an editor shows.
///
/// `FormatException` reports a character offset, which is unusable on the
/// thousands of lines a real scan writes; line and column are what the
/// editor's status bar says. The offset is kept alongside because Dart's own
/// wording ("at character N") is 1-based and someone may have seen it already.
/// Empty when the exception carries no position at all.
String jsonErrorLocation(FormatException error) {
  final offset = error.offset;
  final source = error.source;
  if (offset == null || source is! String) return '';
  var line = 1;
  var column = 1;
  for (var i = 0; i < offset && i < source.length; i++) {
    if (source.codeUnitAt(i) == 0x0a) {
      line++;
      column = 1;
    } else {
      column++;
    }
  }
  return ' at line $line, column $column (character ${offset + 1})';
}

/// The two halves of "this file is not usable", kept apart because their
/// fixes are (T-0050).
///
/// Both follow [reviewPathError]'s shape -- what the file is instead of a
/// review file, then what to do about it -- so the four messages T-0037 and
/// T-0049 established read as one family. Unparseable text is a typing
/// mistake somewhere the offset can find; valid JSON of the wrong shape is a
/// field, and the field is named.
String reviewParseError(String path, FormatException error) =>
    'Not a review file: ${absoluteFilePath(path)} is not JSON -- '
    '${error.message}${jsonErrorLocation(error)}. review.json is hand-edited '
    'by design, so look at the last edit: an unclosed brace, a trailing comma '
    'or an unquoted string.';

String reviewShapeError(String path, ReviewFormatException error) =>
    'Not a review file: ${absoluteFilePath(path)} is JSON but not a review '
    'document -- $error. Run shelfscan with no arguments for the smallest '
    'legal game entry.';

/// The review document at [path], or one stderr line and exit 2.
///
/// Both failures are expected input rather than programmer error: manual add
/// is a documented workflow, so `review.json` is hand-edited, and a stray
/// brace in it is the same class of mistake as the mistyped path T-0049
/// handled two lines above this call.
ReviewDocument readReviewDocument(String path) {
  try {
    return ReviewDocument.parse(File(path).readAsStringSync());
  } on ReviewFormatException catch (e) {
    stderr.writeln(reviewShapeError(path, e));
    exit(2);
  } on FormatException catch (e) {
    stderr.writeln(reviewParseError(path, e));
    exit(2);
  }
}

/// Why a directory that holds files yielded no photo, naming what was there.
String noPhotosMessage(PhotoDirectory listing, String dirPath,
    {required bool convertsHeic}) {
  if (listing.skipped.isEmpty) return 'No files to scan in $dirPath';
  final counts = <String, int>{};
  for (final file in listing.skipped) {
    final key = file.extension.isEmpty ? '(no extension)' : file.extension;
    counts[key] = (counts[key] ?? 0) + 1;
  }
  final found =
      counts.entries.map((e) => '${e.key} x${e.value}').join(', ');
  return 'No readable photo in $dirPath: all ${listing.fileCount} file(s) '
      'were skipped. Found: $found. '
      'Accepted: ${acceptedList(convertsHeic: convertsHeic)}';
}

/// A games folder, enumerated for the source stage (T-0160).
///
/// The counts are separate because they are the three different things a
/// directory can hold and each one behaves differently downstream; the summary
/// line quotes them for the same reason [scanScope] quotes the skipped files.
class InstallDirectory {
  InstallDirectory({
    required this.entries,
    required this.unreadable,
    required this.gameDirectories,
    required this.metadataFiles,
    required this.looseFiles,
    this.installerNamed = 0,
  });

  /// What the source stage is handed, in listing order.
  final List<SourceEntry> entries;

  /// Metadata files this shell could not read, so core will never see them.
  /// A source can name what it declined; it cannot name what never reached it.
  final List<SkippedFile> unreadable;

  final int gameDirectories;
  final int metadataFiles;
  final int looseFiles;

  /// How many of [gameDirectories] went over under an installer's name rather
  /// than their own (T-0178). A subset, not a fourth kind of entry, so the
  /// three counts above still sum to [entries].
  final int installerNamed;
}

/// Reads a games folder two levels deep, and the second level only for
/// `goggame-*.info`.
///
/// What each level is for:
///
/// - the folder itself -- loose installers (`setup_moor_1.9.exe`) as one entry
///   each, and every subdirectory as one entry named by the directory. A game
///   installed as `Games/Marlow's Gate 3/` has its title in the folder name and
///   nowhere else, and that name keeps the apostrophe and the capitals that
///   `setup_marlows_gate_3_2.0.0.7_(64bit).exe` has thrown away (T-0158).
/// - inside each subdirectory, `goggame-*.info` and nothing else. That single
///   filter is what keeps a games folder reviewable: the rest of an installed
///   game is hundreds of `.dll`, `.pak` and `.exe` files, and every one that
///   reached the source stage would be a decline to group or a row the owner
///   must reject.
/// - inside a subdirectory the folder's own name cannot title, the one
///   installer that can ([installerNamingFolder]). Two triggers: a name that
///   titles nothing (T-0178) -- `New Folder` holding
///   `setup_harbour_lantern_1.6.15.exe` is the reported case, and it was a lost
///   game rather than a wrong title once T-0174 stopped `New Folder` being a
///   title -- and a name that DOES title something the one unmistakable
///   downloaded installer inside contradicts outright (T-0183), which is what
///   reaches a locale-generated name no list here holds. It replaces the
///   folder's entry rather than joining it, so the budget the filter above
///   protects is untouched: one entry per subdirectory, before and after.
///
/// Nothing below that is enumerated at all, so a game's `data/`, `Saves/` and
/// `Redist/` subtrees never reach core.
///
/// **The scanned directory's own name is not a container and is never handed
/// over (T-0193).** [SourceEntry.container] is a parent a title may be read
/// off when the entry's own name carries none, and that fallback is written
/// for a game's own folder -- one level down, where `Marlows Gate
/// 3/setup_mg3_2.0.0.7.exe` keeps the apostrophe the file threw away. The
/// directory the user pointed at is the other thing entirely: it names the
/// collection. Passing it filled that field with a name no entry can honestly
/// take, and `New Folder`, `Screenshots` and `Saves` each took it -- three
/// rows titled `Downloaded games` that stage 2 then merged into one plausible
/// game (measured 2026-08-16). Entries at this level therefore go over with no
/// container at all, and a name that titles nothing declines by name.
///
/// The subdirectory entry is emitted even when the directory holds an `.info`,
/// which is the case both sources can claim. Suppressing it would mean the
/// shell deciding that the metadata is usable, and whether it is usable is
/// decided by parsing it -- which is core's half of the boundary
/// (ARCHITECTURE.md), not the shell's. Emitting both costs a duplicate row when
/// the two titles disagree and saves the game when the `.info` is broken; stage
/// 2 merges them when they agree, by authority ([DetectionOrigin]).
InstallDirectory readInstallDirectory(Directory dir) {
  final entries = <SourceEntry>[];
  final unreadable = <SkippedFile>[];
  var gameDirectories = 0;
  var metadataFiles = 0;
  var looseFiles = 0;
  var installerNamed = 0;

  for (final entity in dir.listSync()
    ..sort((a, b) => a.path.compareTo(b.path))) {
    if (entity is File) {
      looseFiles++;
      entries.add(SourceEntry(name: _nameOf(entity)));
      continue;
    }
    if (entity is! Directory) continue;
    final name = leafName(entity.path);
    gameDirectories++;

    final List<FileSystemEntity> contents;
    try {
      contents = entity.listSync()..sort((a, b) => a.path.compareTo(b.path));
    } on FileSystemException catch (e) {
      unreadable.add(SkippedFile(
        name: name,
        extension: '',
        reason: 'directory cannot be listed -- '
            '${e.osError?.message ?? e.message}; any goggame-*.info in it was '
            'not read',
      ));
      entries.add(SourceEntry(name: name));
      continue;
    }

    final fileNames = [
      for (final child in contents)
        if (child is File) _nameOf(child)
    ];
    // The listing above is taken for the metadata either way, so consulting it
    // for a name costs no read (T-0178). A directory holding metadata keeps
    // its own entry whatever its name: the GoG path short-circuits here.
    final inside = fileNames.any(GogMetadataSource.fileName.hasMatch)
        ? null
        : installerNamingFolder(name, fileNames);
    if (inside == null) {
      entries.add(SourceEntry(name: name));
    } else {
      installerNamed++;
      entries.add(SourceEntry(name: inside, container: name));
    }

    for (final child in contents) {
      if (child is! File) continue;
      final childName = _nameOf(child);
      if (!GogMetadataSource.fileName.hasMatch(childName)) continue;
      final String content;
      try {
        content = child.readAsStringSync();
      } on FileSystemException catch (e) {
        unreadable.add(SkippedFile(
          name: childName,
          extension: extensionOf(childName),
          reason: 'cannot be read -- ${e.osError?.message ?? e.message}',
        ));
        continue;
      } on FormatException {
        unreadable.add(SkippedFile(
          name: childName,
          extension: extensionOf(childName),
          reason: 'is not UTF-8 text, so it is not the JSON this reads',
        ));
        continue;
      }
      metadataFiles++;
      entries
          .add(SourceEntry(name: childName, container: name, content: content));
    }
  }
  return InstallDirectory(
    entries: entries,
    unreadable: unreadable,
    gameDirectories: gameDirectories,
    metadataFiles: metadataFiles,
    looseFiles: looseFiles,
    installerNamed: installerNamed,
  );
}

/// The last segment of [path], made absolute and normalised first.
///
/// Both separators, because the answer must not depend on the host: a name is
/// what a title is parsed out of ([SourceEntry.name]) and a `Marlow's Gate
/// 3\setup.exe` that kept its backslash would be parsed as one word.
String leafName(String path) {
  final normalized =
      Uri.file(Directory(path).absolute.path).normalizePath().toFilePath();
  final parts = [
    for (final part in normalized.split(RegExp(r'[\\/]')))
      if (part.isNotEmpty) part
  ];
  return parts.isEmpty ? normalized : parts.last;
}

/// Both file sources over one entry list, in the order their confidence runs.
///
/// The hand-over is one reason string rather than a guess: [GogMetadataSource]
/// claims an entry only by returning an item for it, and exactly one of its
/// declines -- [GogMetadataSource.noMetadata] -- means "there was no metadata
/// here". Its other five say the metadata WAS there and was broken, which is a
/// different thing to tell the owner, and handing such an entry on would
/// replace it with `not a game file`, which is [FilenameSource]'s rule for
/// every `.info`.
///
/// So no entry is ever a row from one source and a named decline from the
/// other, which is what T-0158 expected this task to have to answer.
class InstalledGameSource implements DetectionSource {
  const InstalledGameSource();

  static const metadata = GogMetadataSource();
  static const names = FilenameSource();

  @override
  SourceReading read(SourceEntry entry) {
    final fromMetadata = metadata.read(entry);
    if (fromMetadata.items.isNotEmpty) return fromMetadata;
    final handOver = fromMetadata.declined.length == 1 &&
        fromMetadata.declined.single.reason == GogMetadataSource.noMetadata;
    return handOver ? names.read(entry) : fromMetadata;
  }
}

/// Directory names refused as a games folder, whatever is in them.
///
/// The input contract is the only place this distinction exists, and T-0158
/// measured why: over a `Downloads` folder the parser emitted a title for
/// every name it did not decline, and **every one of those titles was an
/// application** rather than a game. `test/corpus/installer_names.tsv`
/// exercises the shapes it emitted on -- `mediaplay`, `cardstack`, `NoteWell`,
/// a freenix image. Nothing in a name separates `NoteWellSetup.exe` from
/// `setup_moor_1.9.exe`, and a list of known applications is unbounded, so no
/// rule reading only the name can decline one and keep the other. A list of
/// known NON-games folders is the opposite
/// shape: short, closed, and wrong only in the direction that costs a retype.
const notAGamesFolder = {
  'downloads', 'download', 'desktop', 'documents', 'my documents',
  'pictures', 'my pictures', 'music', 'my music', 'videos', 'my videos',
  'onedrive', 'dropbox', 'temp', 'tmp', 'appdata', 'windows', 'system32',
  'program files', 'program files (x86)', 'programdata', 'users', 'home',
};

/// Why [path] is not a games folder, or null when it may be one.
///
/// The drive or filesystem root is refused for the same reason as the names
/// above and one worse: it is the one directory whose subdirectories are all of
/// the others.
String? gamesFolderError(String path) {
  final absolute = absoluteFilePath(path);
  final atRoot = Directory(absolute).parent.path == absolute;
  if (!atRoot && !notAGamesFolder.contains(leafName(path).toLowerCase())) {
    return null;
  }
  return 'Not a games folder: $absolute. This reads NAMES, and no rule reading '
      'a name tells NoteWellSetup.exe from setup_moor_1.9.exe -- run over a '
      'Downloads folder it titles every installer it finds, and not one of '
      'them is a game (T-0158). Point it at the directory your games '
      'are installed in.';
}

/// Why [path] cannot be listed as a games folder, or null when it can.
///
/// [scanPathError]'s shape, absolute and normalised for its reason.
String? installsPathError(String path) {
  final absolute =
      Uri.file(Directory(path).absolute.path).normalizePath().toFilePath();
  return switch (FileSystemEntity.typeSync(path)) {
    FileSystemEntityType.directory => null,
    FileSystemEntityType.notFound => 'No games folder at $absolute',
    _ => 'Not a games folder: $absolute is a file -- scan-installs takes the '
        'directory your games are installed in, not one file',
  };
}

/// Said on every run, because the contract cannot be enforced from inside.
String installsNotice(String dirPath) =>
    'Reading $dirPath: file and folder NAMES, plus any goggame-*.info beside '
    'them. No photo is read and no vision model is called. Nothing here can '
    'tell an application from a game, or a game from a film, by its name '
    '-- point this at a media folder, and review every row before you '
    'export it.';

/// How much of the directory the run covered, for the summary line.
String installScope(InstallDirectory listing) =>
    '${listing.entries.length} entry(ies) '
    '(${listing.gameDirectories} folder(s), ${listing.looseFiles} loose '
    'file(s), ${listing.metadataFiles} goggame-*.info)'
    '${listing.installerNamed == 0 ? '' : ', ${listing.installerNamed} '
        'folder(s) read under an installer name inside them'}';

/// The flag that adds a games folder to a run whose own input is photographs.
const installsFlag = '--installs';

/// The flag that adds the GOG library to a run whose own input is something
/// else. No value: there is one Galaxy database, and [galaxyDbFlag] names it
/// when it is not where it is expected.
const libraryFlag = '--library';

/// Where the Galaxy database is, when it is not where the reader looks.
///
/// A constant since T-0188, because [commandOptions] and the two readers below
/// have to agree on the spelling: a table that named a flag the code never
/// reads would refuse a working run, and one that missed a flag the code does
/// read would go on ignoring it in silence.
const galaxyDbFlag = '--galaxy-db';

/// Every source one run reads, in the order their rows enter stage 2.
///
/// The whole of what a mixed run assembles, and a pure function so a test can
/// drive the same list the commands pass. Installs before the library because
/// an installed game is the more specific claim about the same product id, and
/// stage 2 keeps a merged row where the earlier one sat.
List<SourceRun> sourceRunsFor({
  InstallDirectory? installs,
  GalaxyLibrary? library,
}) =>
    [
      if (installs != null)
        SourceRun(const InstalledGameSource(), installs.entries),
      if (library != null) SourceRun(const GogLibrarySource(), library.entries),
    ];

/// How many declined entries one reason names before the rest become a count.
///
/// Six because that is a reason line that still fits a terminal beside the
/// longest reason string in the closed set ([DeclineReason]); the number is a
/// display bound and nothing downstream reads it.
const declinedNamesShown = 6;

/// Stdout lines naming what the sources made no row out of, grouped.
///
/// Grouped and counted for [_warnDeclined]'s measured reason -- a games folder
/// declines more entries than it accepts, so 40 skipped files are one line --
/// and sorted by reason so a re-run over the same directory prints the same
/// summary.
///
/// **The names are printed here and in no warning.** `_warnDeclined` puts them
/// on the document instead of into a sentence (T-0145), and this is the shell,
/// which holds the document: it reads them as values. A bare count is the
/// failure T-0184 was filed for and a line per entry is the one T-0161 named,
/// so the shape between them is **at most two lines per distinct reason**, the
/// second capped at [declinedNamesShown] names -- 40 declines of one reason are
/// two lines whatever the folder holds.
List<String> declinedReport(ReviewDocument doc) {
  if (doc.declinedEntries.isEmpty) return const [];
  final byReason = <String, List<String>>{};
  for (final entry in doc.declinedEntries) {
    byReason.putIfAbsent(entry.reason, () => []).add(entry.name);
  }
  final reasons = byReason.keys.toList()..sort();
  return [
    'Not a game: ${doc.declinedEntries.length} entry(ies), named below and in '
        '"declined_entries"',
    for (final reason in reasons) ...[
      '  ${byReason[reason]!.length} x $reason',
      '      ${_declinedNames(byReason[reason]!)}',
    ],
  ];
}

String _declinedNames(List<String> names) => names.length <= declinedNamesShown
    ? names.join(', ')
    : '${names.take(declinedNamesShown).join(', ')} ... and '
        '${names.length - declinedNamesShown} more, all in "declined_entries"';

/// What became of every entry a run read, as counts nobody has to subtract.
///
/// The line this follows states an input count and an output count, and the
/// difference between them was read as one silent decline on the run that
/// produced T-0184 -- where there was none. Two of that folder's four entries
/// named the same game and stage 2 merged them, which is the pipeline working
/// as designed. Entries, declines and rows are three counts with two different
/// arithmetics between them, so the subtraction the old shape invited was not
/// merely inconvenient: it gave the wrong answer, and a decline was reported
/// that had never happened.
///
/// [rowsAreAllFromEntries] is false on `scan`, whose document also holds rows
/// read off photographs: there no merge is attributable to an entry and only
/// the declines are stated. Where it is true the difference is exact, because
/// every source in this shell answers one entry with one row or one decline.
List<String> entryAccounting(ReviewDocument doc,
    {required int entries, required bool rowsAreAllFromEntries}) {
  if (entries == 0) return const [];
  final declined = doc.declinedEntries.length;
  final named = entries - declined;
  final merged = named - doc.games.length;
  final mergeNote = rowsAreAllFromEntries && merged > 0
      ? ', and $merged of those merged into another row -- one game named in '
          'two places is one row'
      : '';
  return [
    'Of $entries entry(ies) read: $declined named no game, $named named '
        'one$mergeNote.',
  ];
}

/// Every option each command takes, and whether it takes a value after it.
///
/// The list is here rather than inside each command because the refusal has to
/// name what a command DOES take and what has the flag instead, and neither
/// answer is available to a command reading only its own arguments. Every entry
/// is a flag some function below asks [_option] or `args.contains` for; the
/// shared readers count as the command's own -- `--galaxy-db` is
/// `_libraryOrExit`'s and so belongs to every command that can call it.
///
/// `scan-installs` has no `--installs` and `scan-library` neither, and that is
/// T-0179's rule rather than an omission: a command may add sources that cost
/// less than its own, never more. Refusing them by name is what this table is
/// for -- until T-0188 they were accepted and ignored, so a second folder went
/// unscanned while the summary reported only the first.
const commandOptions = <String, Map<String, bool>>{
  'scan': {
    '-o': true,
    '--provider': true,
    '--fallback': true,
    '--aliases': true,
    installsFlag: true,
    libraryFlag: false,
    galaxyDbFlag: true,
  },
  'scan-installs': {
    '-o': true,
    '--aliases': true,
    libraryFlag: false,
    galaxyDbFlag: true,
  },
  'scan-library': {'-o': true, '--aliases': true, galaxyDbFlag: true},
  'resolve': {'-o': true, '--aliases': true},
  'export': {'-o': true, '--target': true},
};

/// Why [args] cannot be run as [command], or null when every option is one the
/// command has.
///
/// Only tokens that look like options are examined, and a known option's VALUE
/// is stepped over rather than examined -- `-o --library` names a file, however
/// odd. Extra positional arguments are left alone: this is the flag silence
/// T-0188 measured, and a positional one is a different question with different
/// commands to answer it for.
///
/// Unknown returns null for an unknown COMMAND, so [_usage] keeps answering
/// that one; there is no option table to check against.
String? unknownOptionError(String command, List<String> args) {
  final known = commandOptions[command];
  if (known == null) return null;
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    final takesValue = known[arg];
    if (takesValue != null) {
      if (takesValue) i++;
      continue;
    }
    if (arg == '-' || !arg.startsWith('-')) continue;
    final elsewhere = [
      for (final entry in commandOptions.entries)
        if (entry.key != command && entry.value.containsKey(arg)) entry.key,
    ];
    final takes = 'Options of "$command": ${known.keys.join(', ')}.';
    return elsewhere.isEmpty
        ? 'Unknown option "$arg" for "$command". Nothing was read. $takes'
        : '"$arg" is not an option of "$command" -- it belongs to '
            '"${elsewhere.join('", "')}". Nothing was read. $takes '
            'Run "shelfscan" with no arguments for what each command reads.';
  }
  return null;
}

Future<void> main(List<String> args) async {
  if (args.isEmpty) _usage();
  // Before the dispatch, so the refusal is answered before a notice is
  // printed, a directory listed or a photo read -- the footing every other
  // pre-flight failure already exits 2 on (T-0037, T-0049, T-0051, T-0179).
  final optionError = unknownOptionError(args.first, args.sublist(1));
  if (optionError != null) {
    stderr.writeln(optionError);
    exit(2);
  }
  try {
    switch (args.first) {
      case 'scan':
        await _scan(args.sublist(1));
      case 'scan-installs':
        await _installs(args.sublist(1));
      case 'scan-library':
        await _library(args.sublist(1));
      case 'resolve':
        await _resolve(args.sublist(1));
      case 'export':
        await _export(args.sublist(1));
      default:
        _usage();
    }
  } on ScanFailedException catch (e) {
    // Exit 2 and not the 1 the empty-directory path uses: that one reports
    // that there was nothing to scan, this one that a scan was run and every
    // call was refused -- a wrong model id or a wrong key, which the user
    // fixes and re-runs, exactly like the path, provider and credential
    // failures that already exit 2 (T-0037, T-0049, T-0050, T-0051).
    stderr.writeln(e.message);
    exit(2);
  } on FallbackConfigError catch (e) {
    stderr.writeln(e.message);
    exit(2);
  }
}

Never _usage() {
  stderr.writeln('Usage:\n'
      '  shelfscan scan <photos_dir> [-o review.json]\n'
      '                              [--provider anthropic|ollama|openai]\n'
      '                              [--fallback anthropic|ollama|openai|none]\n'
      '                              [--aliases data/title_aliases.json]\n'
      '                              [--installs <games_dir>] [--library]\n'
      '                              [--galaxy-db <path>]\n'
      '  shelfscan scan-installs <games_dir> [-o review.json]\n'
      '                                      [--aliases <file>] [--library]\n'
      '                                      [--galaxy-db <path>]\n'
      '                              # installed games, no photos, no vision\n'
      '  shelfscan scan-library [-o review.json] [--aliases <file>]\n'
      '                         [--galaxy-db <path>]\n'
      '                              # the whole GOG library, installed or not\n'
      '  shelfscan resolve <review.json> [-o out.json] [--aliases <file>]\n'
      '                                                 # IGDB stage only, no vision\n'
      '  shelfscan export <review.json> --target <tonkatsu|csv> -o <file>\n'
      '\n'
      'Photos: JPEG, PNG and WebP are read. Each file is identified by its\n'
      'contents, not by its name, so a HEIC your phone renamed .jpg is still\n'
      'converted rather than uploaded as a JPEG; every file that is not a\n'
      'photo is named on stderr and skipped.\n'
      'HEIC/HEIF/HIF (the phone camera default) is accepted ON WINDOWS: each\n'
      'file is converted to JPEG in a temp directory before the scan, and\n'
      'nothing is written next to your originals. Anywhere else -- and when\n'
      'the Windows HEIF extension is missing or the conversion fails -- the\n'
      'file is named on stderr with the reason and skipped, never dropped\n'
      'silently; convert it to .jpg yourself and re-run.\n'
      '\n'
      'scan-installs reads a folder of INSTALLED games instead: the names of\n'
      'the files and folders in it, plus any goggame-*.info a GoG installer\n'
      'left beside a game. No photo, no vision call, no cost. It goes one\n'
      'level down and no further, and inside a game\'s own folder it reads\n'
      'only goggame-*.info -- plus, when the folder itself is called\n'
      'something like "New Folder", the one installer in it that names a\n'
      'game. Point it at a games folder and nothing else --\n'
      'nothing in a file NAME tells NoteWellSetup.exe from setup_moor_1.9.exe,\n'
      'so over a Downloads folder this titles every installer it finds and\n'
      'not one of them is a game (T-0158). It writes the same review.json\n'
      'scan does, for the same resolve and export.\n'
      '\n'
      'scan-library reads GOG Galaxy\'s own local database instead, so a game\n'
      'you own but have not installed is in the list too. WINDOWS ONLY (that\n'
      'is where Galaxy runs). It reads one file on this machine and NOTHING\n'
      'from gog.com: no login, no OAuth, no credential stored or needed. The\n'
      'file is a CACHE OF THE LAST SYNC, not your account -- a game bought\n'
      'since Galaxy last ran is missing -- so the run prints how old it is.\n'
      'Three kinds of row are left out, and each is named in the run rather\n'
      'than dropped silently: DLC (its title is its own, so it would reach\n'
      'review as a game you do not own), releases Galaxy itself hides from\n'
      'your library, and releases from other stores connected to Galaxy\n'
      '(they carry no GOG id to match on).\n'
      '\n'
      'ONE RUN, SEVERAL SOURCES. A game you own on a disc and have installed\n'
      'on the PC is one game, and only a single run puts the two through one\n'
      'dedupe: --installs and --library add those sources to a scan of your\n'
      'photographs, and the run writes ONE review.json in which that game is\n'
      'one row. Run the commands separately instead and you get two files\n'
      'nobody can reconcile -- and the second -o overwrites the first.\n'
      '  shelfscan scan D:\\photos --installs "C:\\GOG Games" --library\n'
      'A command may add sources that cost less than its own, never more:\n'
      'scan-installs takes --library (neither reads a photo), scan-library\n'
      'takes neither, and nothing adds photographs to a run that has none --\n'
      'that run is "scan", and it is where every vision option already is.\n'
      'Each added source keeps its own notice above: --installs prints what a\n'
      'file name cannot tell you, --library how old the cache is.\n'
      '\n'
      '--fallback names a SECOND vision model that re-reads every photo; the\n'
      'two reads are merged. It is off unless you ask for it and it doubles\n'
      'the vision cost of the run -- with a cloud fallback, every photo is\n'
      'uploaded. It does not decide for itself which photos need it: the\n'
      'local model cannot report the spines it failed to read (T-0028), so\n'
      'there is nothing to decide on.\n'
      '\n'
      'Vision providers: ollama (local, the default), openai, anthropic.\n'
      '"openai" is any endpoint speaking the OpenAI /chat/completions API\n'
      '(Groq, OpenRouter, Mistral, GitHub Models, Cerebras, Gemini compat)\n'
      'and reads SHELFSCAN_OPENAI_BASE_URL, SHELFSCAN_OPENAI_MODEL and\n'
      'SHELFSCAN_OPENAI_API_KEY.\n'
      '"anthropic" reads ANTHROPIC_API_KEY and, optionally,\n'
      'SHELFSCAN_ANTHROPIC_MODEL -- unset uses a built-in default model, so\n'
      'you need not know an id to start. Model ids are Anthropic\'s to\n'
      'publish: see the Models overview at platform.claude.com/docs, or GET\n'
      'api.anthropic.com/v1/models. A model you name there is sent with NO\n'
      'temperature, because newer Claude models reject the parameter; its\n'
      'sampling is then Anthropic\'s rather than this tool\'s, and the run\n'
      'prints which of the two it used.\n'
      'Both cloud providers upload your photos in full to the endpoint you\n'
      'name, and free tiers are commonly funded by training on what is\n'
      'submitted to them.\n'
      '\n'
      'SHELFSCAN_VISION_TIMEOUT=<seconds> bounds ONE vision call, per photo,\n'
      'whichever provider reads it. Unset is ${visionCallTimeout.inSeconds} s,'
      ' which no model\n'
      'measured here needs raising -- but a local model too big for your VRAM\n'
      'is minutes per photo, and this is what lets it finish. 1 to\n'
      '$maxVisionTimeoutSeconds; anything else is refused, never silently\n'
      'replaced by the default.\n'
      '\n'
      'Missed an item? Append it to "games" in review.json and re-run resolve:\n'
      '  {"detection": {"raw_title": "Nocturne 5 Gold", "platform_hint": "PS4",\n'
      '                 "media_type": "disc", "origin": "manual"}}\n'
      'Only raw_title is required; everything else may be omitted.');
  exit(2);
}

/// The value [env] gives [name], with a set-but-empty value counting as unset.
///
/// The single door every environment read in this file goes through, and
/// `documented_lists_test.dart` fails on one that does not. Eight of the ten
/// variables checked `isEmpty` in four different spellings and two checked
/// nothing, so `SHELFSCAN_OLLAMA_URL=` built a provider on an empty base URL
/// and the run blamed Ollama minutes later (T-0080). One door is what makes
/// "all ten agree" a property of the code rather than of whoever last added a
/// variable.
String? envValue(Map<String, String> env, String name) {
  final value = env[name];
  return value == null || value.isEmpty ? null : value;
}

/// Names the bound one vision call is given, in whole seconds.
const visionTimeoutVar = 'SHELFSCAN_VISION_TIMEOUT';

/// The widest bound this accepts, in seconds.
///
/// 5x the slowest read this project has measured -- `qwen2.5vl:32b` at ~360 s
/// per 4000x3000 photo, 29 GB of weights and context against 24 GB of VRAM
/// (doc/measurements.md) -- which is the configuration the variable exists
/// for. A ceiling is what keeps [visionCallTimeout]'s second argument true:
/// the local path sends photos one at a time, so a wedged server is reported
/// after photos x bound, and a bound nobody outlasts is the unbounded wait
/// T-0104 removed, typed in by hand rather than left in by omission.
const maxVisionTimeoutSeconds = 1800;

/// The clause core's stall sentences deliberately stop short of (T-0152).
///
/// The diagnosis is measured and lives with each provider; the remedy names a
/// control, and only a shell knows whether its user has one. This shell does,
/// so it says so -- and it is defined once here, beside the variable it names,
/// rather than three times in three providers that cannot check the spelling.
///
/// Conditional on purpose: every diagnosis it follows argues the stall is the
/// likelier reading, and two of the three say so with a number. It offers the
/// bound to a user who has judged otherwise, which is the whole of what a
/// control is for -- it does not recommend raising it.
const raiseVisionTimeoutAdvice =
    'If the read is slow rather than stalled, the bound is yours to raise for '
    'the next run: $visionTimeoutVar=<seconds>, 1 to $maxVisionTimeoutSeconds.';

/// What one vision call is given on this run: [visionCallTimeout], or what
/// [visionTimeoutVar] names.
///
/// Every construction path goes through the three factories below, so the
/// value reaches the fallback reader as well as the primary one -- a second
/// read is a vision call and stalls the same way.
///
/// Nonsense is refused, not rounded into the default: the failure this
/// variable exists to end is silent, and a user who typed `600` and was given
/// 120 would learn it from a photo timing out at 120 s, which is exactly the
/// state before the variable existed. Zero and negative are nonsense here
/// rather than "no bound" -- `Future.timeout` would fire on them instantly and
/// call every endpoint stalled.
Duration visionTimeoutFrom(Map<String, String> env) {
  final raw = envValue(env, visionTimeoutVar);
  if (raw == null) return visionCallTimeout;
  final seconds = int.tryParse(raw.trim());
  if (seconds == null || seconds < 1 || seconds > maxVisionTimeoutSeconds) {
    throw FallbackConfigError(
        '$visionTimeoutVar must be a whole number of seconds from 1 to '
        '$maxVisionTimeoutSeconds, and it is "$raw". It bounds ONE vision '
        'call, per photo; unset it for the default of '
        '${visionCallTimeout.inSeconds} s.');
  }
  return Duration(seconds: seconds);
}

/// The local provider [env] describes, defaults where it describes nothing.
/// Shared by `--provider ollama` and the local fallback, which held their own
/// copies of both defaults and of the URL lookup.
///
/// [defaultOllamaUrl] and [defaultOllamaModel] are [OllamaVisionProvider]'s
/// own, retyped in this file until T-0087. They are named rather than left to
/// the optional parameters because [envValue] answers null and a named
/// parameter cannot be passed null to mean "use your default".
OllamaVisionProvider ollamaProviderFor(Map<String, String> env,
        {String? model}) =>
    OllamaVisionProvider(
      baseUrl: envValue(env, 'SHELFSCAN_OLLAMA_URL') ?? defaultOllamaUrl,
      model: model ??
          envValue(env, 'SHELFSCAN_OLLAMA_MODEL') ??
          defaultOllamaModel,
      timeout: visionTimeoutFrom(env),
      stallRemedy: raiseVisionTimeoutAdvice,
    );

VisionProvider _makeProvider(List<String> args) {
  final env = Platform.environment;
  // Desktop policy: local by default, cloud only when explicitly requested.
  final name = _option(args, '--provider') ?? 'ollama';
  switch (name) {
    case 'anthropic':
      final key = envValue(env, 'ANTHROPIC_API_KEY');
      if (key == null) {
        stderr.writeln('Provider "anthropic" needs ANTHROPIC_API_KEY. '
            'For a fully local run use: --provider ollama');
        exit(2);
      }
      final provider = anthropicProviderFor(key, env);
      // The model AND the sampling, because neither is recoverable from the
      // review file afterwards and a figure without both cannot be repeated
      // even in principle (AnthropicVisionProvider's measurement recipe).
      // Printed for the same reason the openai line is: this is the moment
      // photographs of a private home start being uploaded.
      stdout.writeln('Vision: Anthropic ${provider.model} '
          '(${_samplingNote(provider)}) -- every photo is uploaded there.');
      return provider;
    case 'ollama':
      final provider = ollamaProviderFor(env);
      stdout.writeln('Vision: local Ollama (${provider.model})');
      return provider;
    case 'openai':
      final provider = openAiProviderFor(env, onRequestAdjusted: _endpointNote);
      // Printed, not buried in --help: this is the moment the user is
      // choosing to upload photographs of their home (decision 0011).
      stdout.writeln('Vision: ${provider.model} at ${provider.baseUrl} -- '
          'every photo is uploaded there. Free tiers are commonly funded by '
          'training on what is submitted to them.');
      return provider;
    default:
      stderr.writeln(
          'Unknown provider "$name". Known: anthropic, ollama, openai');
      exit(2);
  }
}

/// Names the Claude model for `--provider anthropic` and `--fallback
/// anthropic`, matching SHELFSCAN_OLLAMA_MODEL and SHELFSCAN_OPENAI_MODEL.
const anthropicModelVar = 'SHELFSCAN_ANTHROPIC_MODEL';

/// The Anthropic provider at whatever model [env] names, or the built-in
/// default when it names none.
///
/// Unset gets the provider's own default model and with it the temperature 0
/// that default was argued for (T-0057). A model named here is sent WITHOUT a
/// temperature, because the parameter is model-gated: Claude Opus 4.7 and
/// later, Sonnet 5 and Fable 5 return 400 for a request carrying one, and a
/// 400 landing minutes into a paid scan reads as a broken key.
///
/// No table of which families accept sampling is kept here. It would age
/// exactly the way the pinned default id does, and a stale table fails the
/// same way it was written to prevent -- so the rule keys on WHO chose the id
/// rather than on which id it is. What that costs is that a named model's
/// sampling is the endpoint's, which is the unrecorded state T-0053 exists to
/// end; hence the line the run prints naming both.
///
/// Model ids are Anthropic's to publish and nothing in this repository is a
/// list of them: read the Models overview under platform.claude.com/docs, or
/// `GET https://api.anthropic.com/v1/models` with ANTHROPIC_API_KEY.
AnthropicVisionProvider anthropicProviderFor(
    String apiKey, Map<String, String> env) {
  final model = envValue(env, anthropicModelVar);
  final timeout = visionTimeoutFrom(env);
  return model == null
      ? AnthropicVisionProvider(
          apiKey: apiKey,
          timeout: timeout,
          stallRemedy: raiseVisionTimeoutAdvice)
      : AnthropicVisionProvider(
          apiKey: apiKey,
          model: model,
          temperature: null,
          timeout: timeout,
          stallRemedy: raiseVisionTimeoutAdvice);
}

/// What the endpoint refused and what went instead (T-0089).
///
/// On the same channel as every other warning because it carries the same
/// weight as one: a dropped `temperature` means the rest of the run is not the
/// near-greedy decoding every number in this project was measured under.
void _endpointNote(String note) => stderr.writeln('WARN: $note');

/// `NOTE:` rather than `WARN:` for a documented exclusion (T-0222): the owner
/// read these in the app as errors, and stderr had them under the same word.
/// Nothing is dropped -- the line and its count are unchanged, and
/// `declined_entries` in the review document still names every entry.
///
/// Four letters, not an abbreviation of one: `documented_lists_test` reads
/// every ALL-CAPS literal of six or more characters in this file as an
/// environment variable the CLI might be reading, and it is right to.
void _scanWarning(ScanWarning warning) => stderr.writeln(
    '${warning.severity == Severity.exclusion ? 'NOTE' : 'WARN'}: '
    '${warning.message}');

String _samplingNote(AnthropicVisionProvider provider) =>
    provider.temperature == null
        ? 'sampling not stated -- Anthropic chooses it; record that with any '
            'numbers from this run'
        : 'temperature ${provider.temperature}';

/// The OpenAI-compatible provider configured from the environment (T-0006).
///
/// Shared by `--provider openai` and `--fallback openai`, and throwing
/// rather than exiting for the same reason [fallbackProviderFor] does: it
/// stays a pure function of the environment that a test can call.
OpenAiCompatibleVisionProvider openAiProviderFor(Map<String, String> env,
    {void Function(String note)? onRequestAdjusted}) {
  const baseUrlVar = 'SHELFSCAN_OPENAI_BASE_URL';
  const modelVar = 'SHELFSCAN_OPENAI_MODEL';
  const keyVar = 'SHELFSCAN_OPENAI_API_KEY';

  final missing = [baseUrlVar, modelVar, keyVar]
      .where((v) => envValue(env, v) == null)
      .join(', ');
  if (missing.isNotEmpty) {
    throw FallbackConfigError('The "openai" provider needs $missing. The '
        'endpoint, model and key all come from you: nothing is shipped with '
        'this program (BYOK). Base URL example: '
        'https://api.groq.com/openai/v1');
  }
  return OpenAiCompatibleVisionProvider(
    baseUrl: envValue(env, baseUrlVar)!,
    model: envValue(env, modelVar)!,
    apiKey: envValue(env, keyVar)!,
    timeout: visionTimeoutFrom(env),
    stallRemedy: raiseVisionTimeoutAdvice,
    onRequestAdjusted: onRequestAdjusted,
  );
}

/// A run the environment describes but that cannot be built: an unknown
/// fallback name, a missing key, no model to escalate to, a timeout that is
/// not a number of seconds.
///
/// Named for the fallback because that is where it started; it has covered the
/// primary `openai` path since T-0006 and one type is still the right count --
/// every case is the same fact to `main`, which prints the message and exits 2.
///
/// An exception rather than a direct `exit(2)` so that the selection policy
/// below is a pure function a test can call: "a local-only configuration
/// never reaches the cloud" is a claim worth pinning down, and it cannot be
/// pinned down on a function that terminates the process.
class FallbackConfigError implements Exception {
  FallbackConfigError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Which provider, if any, re-reads every photo after the primary.
///
/// [name] is the `--fallback` value (null when the flag is absent). The two
/// entry points are deliberately not equivalent:
///   * `SHELFSCAN_OLLAMA_FALLBACK_MODEL` alone selects a bigger LOCAL model.
///     A second local read costs nothing but time, so no ceremony.
///   * a cloud endpoint requires `--fallback anthropic` or
///     `--fallback openai` typed on the command line. No environment
///     variable and no default can reach either, which is the "cloud is an
///     explicit opt-in" decision 0011 applied to the second-reader
///     path -- the SHELFSCAN_OPENAI_* variables configure that endpoint but
///     never select it. That decision only got weightier when the second read
///     stopped being conditional (T-0032): every photo now goes.
VisionProvider? fallbackProviderFor(String? name, Map<String, String> env,
    {void Function(String note)? onRequestAdjusted}) {
  final localModel = envValue(env, 'SHELFSCAN_OLLAMA_FALLBACK_MODEL');

  OllamaVisionProvider localFallback() =>
      ollamaProviderFor(env, model: localModel!);

  switch (name) {
    case null:
      return localModel == null ? null : localFallback();
    case 'none':
      // An explicit off, even with the env var set.
      return null;
    case 'ollama':
      if (localModel == null) {
        throw FallbackConfigError('--fallback ollama needs '
            'SHELFSCAN_OLLAMA_FALLBACK_MODEL: at temperature 0 the same '
            'model returns the same answer, so a second read by it buys '
            'nothing and costs a call per photo.');
      }
      return localFallback();
    case 'anthropic':
      final key = envValue(env, 'ANTHROPIC_API_KEY');
      if (key == null) {
        throw FallbackConfigError('--fallback anthropic needs '
            'ANTHROPIC_API_KEY. For a local escalation instead, set '
            'SHELFSCAN_OLLAMA_FALLBACK_MODEL to a bigger vision model.');
      }
      return anthropicProviderFor(key, env);
    case 'openai':
      return openAiProviderFor(env, onRequestAdjusted: onRequestAdjusted);
    default:
      throw FallbackConfigError('Unknown fallback "$name". '
          'Known: anthropic, ollama, openai, none');
  }
}

/// Path of the committed alias table, relative to the repository root.
const aliasFileName = 'data/title_aliases.json';

/// Nearest [aliasFileName] at or above [from], or null if there is none.
///
/// The CLI is run both from the repository root and from
/// `packages/shelfscan_core` (that is where `dart run shelfscan_core:shelfscan`
/// is issued), while the file lives at the root -- one fixed relative path
/// would therefore work from only one of the two.
File? findAliasFile(Directory from) {
  for (var dir = from.absolute;; dir = dir.parent) {
    final file = File('${dir.path}/$aliasFileName');
    if (file.existsSync()) return file;
    if (dir.path == dir.parent.path) return null;
  }
}

/// The alias table for this run: the data file, or the built-in fallback.
///
/// Neither a missing nor a malformed file stops the run. Aliases only widen
/// what IGDB is asked for; losing them costs match rate on regional titles,
/// which is a worse scan, not a failed one -- and a hand-edited data file is
/// exactly the kind of thing that is malformed at the least convenient
/// moment.
Map<String, String> loadTitleAliases(
  String? path, {
  required void Function(String) onWarning,
}) {
  final file = path != null ? File(path) : findAliasFile(Directory.current);
  if (file == null || !file.existsSync()) {
    onWarning('No alias file at ${path ?? aliasFileName} -- falling back to '
        '${builtinTitleAliases.length} built-in aliases.');
    return builtinTitleAliases;
  }
  try {
    return parseTitleAliases(file.readAsStringSync());
  } on FormatException catch (e) {
    onWarning('Alias file ${file.path} is unusable (${e.message}) -- falling '
        'back to ${builtinTitleAliases.length} built-in aliases.');
    return builtinTitleAliases;
  }
}

/// The Twitch application credentials IGDB needs, or null when [env] is
/// missing either of them.
///
/// A pure function of the environment for the same reason
/// [fallbackProviderFor] is one: the caller below terminates the process, and
/// "either half missing means no resolver" is a claim a test should be able
/// to make.
({String id, String secret})? igdbCredentialsFrom(Map<String, String> env) {
  final id = envValue(env, 'IGDB_CLIENT_ID');
  final secret = envValue(env, 'IGDB_CLIENT_SECRET');
  return id == null || secret == null ? null : (id: id, secret: secret);
}

/// The TMDB API Read Access Token, or null when [env] carries none.
///
/// Pure for the reason [igdbCredentialsFrom] is, and it spells no name: the
/// string lives on [tmdbTokenVariable] beside the client that needs it, so
/// there is one definition of it rather than one per shell.
String? tmdbTokenFrom(Map<String, String> env) =>
    envValue(env, tmdbTokenVariable);

/// Stage 3 as a map from the kind of a row to the catalogue that answers it.
///
/// **What a kind with no catalogue gets, and it is the owner's decision rather
/// than a fallback chosen here (T-0308): a keyless run.** A film row in a run
/// holding IGDB credentials and no TMDB token comes back exactly as a game row
/// does with no IGDB credentials -- the title read off the filename, CSV yes,
/// `.xcoll` no. That is the answer that teaches nobody a new rule, since
/// keyless already means this here.
///
/// So [WorkKind.game] is registered rather than left to the fallback, and the
/// fallback is [SkipResolver]. The other arrangement -- IGDB as the fallback --
/// is what this replaces, and it is the failure `CatalogueRouter`'s required
/// fallback exists to make visible: one resolver for every row searches a film
/// in the games catalogue.
///
/// **The TMDB branch has never been run.** No token exists on the machine this
/// was written on, and none existed when T-0162 wrote the client, so it is
/// tested against a fake `http.Client` and nothing else. Registering it routes
/// a film to a catalogue nobody here has called; it does not make films
/// resolve.
ResolverWorker resolverFor(
  Map<String, String> env, {
  Map<String, String>? aliases,
}) {
  final credentials = igdbCredentialsFrom(env);
  final token = tmdbTokenFrom(env);
  final catalogues = <WorkKind, Worker<Detection, ResolvedGame>>{
    if (credentials != null)
      WorkKind.game: ResolverWorker(
        IgdbClient(clientId: credentials.id, clientSecret: credentials.secret),
        aliases: aliases,
      ),
    if (token != null)
      WorkKind.movie: TmdbResolverWorker(TmdbClient(token: token)),
  };
  // Shared with the Flutter app, which takes the same branch when the user has
  // entered no IGDB credentials in Settings.
  if (catalogues.isEmpty) return SkipResolver();
  return CatalogueRouter(catalogues: catalogues, fallback: SkipResolver());
}

/// [required] marks a command that is pointless without IGDB (`resolve`):
/// there the missing credentials are a hard error, while `scan` degrades to
/// unresolved entries the human fixes at review.
ResolverWorker _makeResolver(List<String> args, {bool required = false}) {
  final env = Platform.environment;
  final credentials = igdbCredentialsFrom(env);
  if (credentials == null) {
    if (required) {
      stderr.writeln('The "resolve" command needs IGDB credentials: set '
          'IGDB_CLIENT_ID and IGDB_CLIENT_SECRET (see .env.example). '
          'Resolving is the entire point of this command, so there is '
          'nothing useful to do without them.');
      exit(2);
    }
    stdout.writeln('IGDB credentials not set -- resolve stage will be '
        'skipped, games stay unresolved (fine for vision validation).');
    return resolverFor(env);
  }
  // Said only on the run that can be surprised by it. With no IGDB
  // credentials the line above already says every row stays unresolved, and
  // repeating it per catalogue would be noise; with them, games are looked up
  // and films are not, which is the difference a person has to be told about.
  if (tmdbTokenFrom(env) == null) {
    stdout.writeln('No $tmdbTokenVariable -- film rows are keyless: the title '
        'read off the filename, CSV yes, .xcoll no. Games are unaffected.');
  }
  return resolverFor(
    env,
    aliases: loadTitleAliases(
      _option(args, '--aliases'),
      onWarning: (message) => stderr.writeln('WARN: $message'),
    ),
  );
}

Future<void> _scan(List<String> args) async {
  final dirPath = args.isNotEmpty ? args.first : _usage();
  final outPath = _option(args, '-o') ?? 'collection.review.json';

  // Every path is answered before a photo is read, converted or uploaded: on
  // this command the output check is the one that has to be here rather than
  // at the write, since by then the vision run has been paid for (T-0051).
  // A games folder named by --installs is answered here for the same reason --
  // a typo in it must not cost a scan of the shelf first.
  final installsPath = _option(args, installsFlag);
  final pathError = scanPathError(dirPath) ??
      outputPathError(outPath) ??
      (installsPath == null
          ? null
          : installsPathError(installsPath) ?? gamesFolderError(installsPath));
  if (pathError != null) {
    stderr.writeln(pathError);
    exit(2);
  }
  final dir = Directory(dirPath);

  final listing = readPhotoDirectory(dir, convertHeic: windowsHeicToJpeg);
  for (final line in conversionReport(listing)) {
    stdout.writeln(line);
  }
  for (final line in skipReport(listing, convertsHeic: _convertsHeic)) {
    stderr.writeln(line);
  }
  final photos = listing.photos;
  if (photos.isEmpty) {
    stderr.writeln(noPhotosMessage(listing, dir.path,
        convertsHeic: _convertsHeic));
    exit(1);
  }

  // Read before the vision run rather than after it, so a games folder that
  // refuses or a Galaxy database that is not there costs no photograph: both
  // exit 2 on the same pre-flight footing as the paths above.
  final installs =
      installsPath == null ? null : _installsOrExit(Directory(installsPath));
  if (installs != null && installs.entries.isEmpty) {
    stderr.writeln('Nothing to read in $installsPath: the directory holds no '
        'file and no subdirectory. Scanning the photos only.');
  }
  final library = args.contains(libraryFlag) ? _libraryOrExit(args) : null;

  final fallback = fallbackProviderFor(
      _option(args, '--fallback'), Platform.environment,
      onRequestAdjusted: _endpointNote);
  if (fallback != null) {
    final where = switch (fallback) {
      AnthropicVisionProvider p => 'cloud (${p.model}, ${_samplingNote(p)})',
      OpenAiCompatibleVisionProvider(:final model, :final baseUrl) =>
        'cloud ($model at $baseUrl)',
      OllamaVisionProvider(:final model) => 'local ($model)',
      _ => 'configured',
    };
    // The number, not the word: "fallback" reads as "only when needed", and
    // there is no "when needed" left to key on (T-0032).
    stdout.writeln('Fallback: $where -- re-reads ALL ${photos.length} photo(s), '
        '${photos.length} extra call(s).');
  }

  final orchestrator = Orchestrator(
    visionWorker: VisionWorker(_makeProvider(args), secondReader: fallback),
    resolverWorker: _makeResolver(args),
    // Local models process one image at a time anyway; avoid queue pileup.
    visionConcurrency:
        (_option(args, '--provider') ?? 'ollama') == 'ollama' ? 1 : 3,
  );

  final doc = await orchestrator.runScan(
    photos,
    sources: sourceRunsFor(installs: installs, library: library),
    progress: ScanProgress(
      onStage: (stage) => stdout.writeln('== $stage =='),
      onItem: (stage, done, total) => stdout.writeln('  $stage $done/$total'),
      onWarning: _scanWarning,
    ),
  );

  File(outPath).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(doc.toJson()));
  final unresolved = doc.games.where((g) => g.best == null).length;
  // One count for the whole run: the point of a mixed one is that a disc and
  // an install of the same game are one row here, so counting per input would
  // be two numbers that do not add up to the document.
  stdout.writeln('Scanned ${scanScope(listing)}'
      '${installs == null ? '' : ' and ${installScope(installs)}'}'
      '${library == null ? '' : ' and ${library.entries.length} release(s)'}: '
      '${doc.games.length} game(s) detected, $unresolved unresolved.');
  for (final line in [
    ...unreadableReport(doc),
    ...entryAccounting(doc,
        entries: (installs?.entries.length ?? 0) +
            (library?.entries.length ?? 0),
        rowsAreAllFromEntries: false),
    ...declinedReport(doc),
  ]) {
    stdout.writeln(line);
  }
  // The same reason the lines above exist: what the pipeline refuses has to be
  // named. A hint that is a line of our own prompt (T-0084) is dropped from the
  // platform column, which on its own looks like a spine whose branding was
  // illegible.
  // Counted per value, because the measured shape of this failure is a whole
  // photo answering one string on every row, or nearly (T-0074).
  final refused = <String, int>{};
  for (final game in doc.games) {
    final hint = game.detection.discardedPlatformHint;
    if (hint != null) refused[hint] = (refused[hint] ?? 0) + 1;
  }
  if (refused.isNotEmpty) {
    stdout.writeln('Platform hints refused: '
        '${refused.values.reduce((a, b) => a + b)} '
        '(kept per row in "discarded_platform_hint")');
    refused.forEach((hint, count) {
      stdout.writeln('  $count x "$hint" -- '
          '${platformHintRejection(hint) ?? 'not a platform'}');
    });
  }
  stdout.writeln('Review file: $outPath -- set "status" per game, then export.');
}

/// Read a directory of installed games into the same review document `scan`
/// writes (T-0160).
///
/// Built on [Orchestrator.resolveOnly], which holds no vision worker at all, so
/// this command *provably* cannot make a vision call -- the same guarantee
/// `resolve` has, and the reason a folder run costs nothing and repeats byte
/// for byte for free.
Future<void> _installs(List<String> args) async {
  final dirPath = args.isNotEmpty ? args.first : _usage();
  final outPath = _option(args, '-o') ?? 'collection.review.json';

  final pathError = installsPathError(dirPath) ??
      gamesFolderError(dirPath) ??
      outputPathError(outPath);
  if (pathError != null) {
    stderr.writeln(pathError);
    exit(2);
  }
  final dir = Directory(dirPath);

  final listing = _installsOrExit(dir);
  // The library may ride along here and not the other way round: this command
  // reads what is installed, `scan-library` what is owned, and the owned set
  // contains the installed one. Both refuse the same way and neither costs a
  // vision call, so one run reconciles them (T-0179).
  final library = args.contains(libraryFlag) ? _libraryOrExit(args) : null;
  if (listing.entries.isEmpty && library == null) {
    stderr.writeln('Nothing to read in ${dir.path}: the directory holds no '
        'file and no subdirectory.');
    exit(1);
  }

  final orchestrator =
      Orchestrator.resolveOnly(resolverWorker: _makeResolver(args));
  final doc = await orchestrator.runScan(
    const [],
    sources: sourceRunsFor(installs: listing, library: library),
    progress: ScanProgress(
      onStage: (stage) => stdout.writeln('== $stage =='),
      onItem: (stage, done, total) => stdout.writeln('  $stage $done/$total'),
      onWarning: _scanWarning,
    ),
  );

  File(outPath).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(doc.toJson()));
  final unresolved = doc.games.where((g) => g.best == null).length;
  stdout.writeln('Read ${installScope(listing)}'
      '${library == null ? '' : ' and ${library.entries.length} release(s)'}: '
      '${doc.games.length} game(s) found, $unresolved unresolved.');
  for (final line in [
    ...entryAccounting(doc,
        entries: listing.entries.length + (library?.entries.length ?? 0),
        rowsAreAllFromEntries: true),
    ...declinedReport(doc),
  ]) {
    stdout.writeln(line);
  }
  stdout.writeln('Review file: $outPath -- set "status" per game, then export.');
}

/// A games folder read for whichever command asked for one.
///
/// Shared by `scan-installs`, whose whole input this is, and by `scan
/// --installs`, which adds it to a shelf. The input contract T-0158 measured
/// is a property of what is being read and not of which command was typed, so
/// the refusal list and the unconditional notice travel with the read rather
/// than sitting in one command.
InstallDirectory _installsOrExit(Directory dir) {
  stdout.writeln(installsNotice(dir.path));
  final listing = readInstallDirectory(dir);
  for (final file in listing.unreadable) {
    stderr.writeln('SKIPPED: ${file.name} -- ${file.reason}');
  }
  return listing;
}

/// The GOG library read for whichever command asked for one, with the two
/// things the user must see before they trust its rows: how old the cache is,
/// and whether Galaxy's schema has moved under the reader (T-0177).
GalaxyLibrary _libraryOrExit(List<String> args) {
  final dbPath = _option(args, galaxyDbFlag) ?? galaxyDatabasePath;
  final GalaxyLibrary library;
  try {
    library = readGalaxyLibrary(path: dbPath);
  } on GalaxyLibraryException catch (e) {
    // Exit 2, with the other pre-flight failures: the user changes something
    // and re-runs. An absent or moved database is not a scan that found
    // nothing.
    stderr.writeln(e.message);
    exit(2);
  }
  stdout.writeln(galaxyStalenessNote(library));
  if (library.schemaVersion != galaxySchemaVersion) {
    // Not fatal -- the query already succeeded, so the tables this reads are
    // still there. Named because GOG does not know this reader exists and
    // their next update can move what it did not break today.
    stderr.writeln('WARN: this GOG Galaxy database is schema version '
        '${library.schemaVersion}; this reader was verified against '
        '$galaxySchemaVersion. Check the titles below against Galaxy.');
  }
  return library;
}

/// The whole owned GOG library, from Galaxy's local database (T-0177).
///
/// A sibling of [_installs] rather than a flag on it: they share their output
/// document and nothing else. That one walks a directory the user points at;
/// this one opens one known file and asks it what the account owns, which is a
/// different question with a different failure mode -- absence and staleness
/// rather than "is this a game or an installer".
Future<void> _library(List<String> args) async {
  final outPath = _option(args, '-o') ?? 'collection.review.json';
  final dbPath = _option(args, galaxyDbFlag) ?? galaxyDatabasePath;

  final pathError = outputPathError(outPath);
  if (pathError != null) {
    stderr.writeln(pathError);
    exit(2);
  }

  final library = _libraryOrExit(args);

  final orchestrator =
      Orchestrator.resolveOnly(resolverWorker: _makeResolver(args));
  final doc = await orchestrator.runScan(
    const [],
    sources: sourceRunsFor(library: library),
    progress: ScanProgress(
      onStage: (stage) => stdout.writeln('== $stage =='),
      onItem: (stage, done, total) => stdout.writeln('  $stage $done/$total'),
      onWarning: _scanWarning,
    ),
  );

  File(outPath).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(doc.toJson()));
  final unresolved = doc.games.where((g) => g.best == null).length;
  stdout.writeln('Read ${library.entries.length} release(s) from $dbPath: '
      '${doc.games.length} game(s) found, $unresolved unresolved.');
  for (final line in [
    ...entryAccounting(doc,
        entries: library.entries.length, rowsAreAllFromEntries: true),
    ...declinedReport(doc),
  ]) {
    stdout.writeln(line);
  }
  stdout.writeln('Review file: $outPath -- set "status" per game, then export.');
}

/// Re-run stage 3 (IGDB) over an existing review document.
///
/// Deliberately never constructs a vision provider: measuring the resolver
/// must not depend on, or pay for, another vision run.
Future<void> _resolve(List<String> args) async {
  if (args.isEmpty) _usage();
  final inPath = args.first;
  final outPath = _option(args, '-o') ?? _resolvedPathFor(inPath);

  final pathError =
      reviewPathError(inPath, 'resolve') ?? outputPathError(outPath);
  if (pathError != null) {
    stderr.writeln(pathError);
    exit(2);
  }

  final doc = readReviewDocument(inPath);

  // Credentials after the read, since T-0050: both are pre-flight checks and
  // neither reads a photo or touches the network, so the one that can be
  // answered from the file the user just pointed at goes first. The other
  // order sends someone off to register a Twitch application only to be told,
  // on their return, that their review.json has an unclosed brace.
  final orchestrator = Orchestrator.resolveOnly(
      resolverWorker: _makeResolver(args, required: true));

  final resolved = await orchestrator.runResolve(
    [for (final game in doc.games) game.detection],
    progress: ScanProgress(
      onStage: (stage) => stdout.writeln('== $stage =='),
      onItem: (stage, done, total) => stdout.writeln('  $stage $done/$total'),
      onWarning: _scanWarning,
    ),
  );

  final out = ReviewDocument(
    version: doc.version,
    created: DateTime.now().toUtc().toIso8601String(),
    photos: doc.photos,
    games: resolved,
    // Re-resolving reads no photos, so it learns nothing new about what was
    // unreadable or about which photos never got read -- carry the scan's
    // findings through instead of dropping them.
    unreadable: doc.unreadable,
    failedPhotos: doc.failedPhotos,
    notLookedAtPhotos: doc.notLookedAtPhotos,
  );
  File(outPath).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(out.toJson()));

  // The buckets that need no ground truth. Splitting "auto-matched" into
  // right and wrong is a human job on top of this file.
  final auto = resolved.where((g) => g.best != null).length;
  final noCandidates = resolved.where((g) => g.candidates.isEmpty).length;
  final belowThreshold = resolved.length - auto - noCandidates;
  stdout.writeln('Resolved ${resolved.length} detection(s) from $inPath:');
  for (final row in [
    ('auto-matched (score >= $minAutoScore)', auto),
    ('candidates below threshold', belowThreshold),
    ('no candidates at all', noCandidates),
  ]) {
    stdout.writeln('  ${'${row.$1}:'.padRight(38)}${row.$2}');
  }
  stdout.writeln('Output: $outPath (review status reset to pending)');
}

/// `collection.review.json` -> `collection.review.resolved.json`; the input
/// is never overwritten, so before/after runs stay comparable.
String _resolvedPathFor(String inPath) => inPath.endsWith('.json')
    ? '${inPath.substring(0, inPath.length - '.json'.length)}.resolved.json'
    : '$inPath.resolved.json';

Future<void> _export(List<String> args) async {
  if (args.isEmpty) _usage();
  final pathError = reviewPathError(args.first, 'export');
  if (pathError != null) {
    stderr.writeln(pathError);
    exit(2);
  }

  final target = _option(args, '--target') ?? _usage();
  final outPath = _option(args, '-o') ?? _usage();
  // Ahead of the read for the same reason it is ahead of the scan: both are
  // typos knowable before the command does anything at all.
  final outError = outputPathError(outPath);
  if (outError != null) {
    stderr.writeln(outError);
    exit(2);
  }

  final doc = readReviewDocument(args.first);
  final factory = exporters[target];
  if (factory == null) {
    stderr.writeln('Unknown target "$target". Known: ${exporters.keys.join(', ')}');
    exit(2);
  }

  final exporter = factory();
  final approved = doc.games
      .where((g) =>
          g.status == ReviewStatus.approved || g.status == ReviewStatus.edited)
      .length;
  // What the target actually carries, asked of the exporter rather than
  // re-derived here: `.xcoll` needs ids, csv does not, and a summary line
  // that says "exported N" while the file holds fewer is worse than no
  // summary at all.
  final written = exporter.select(doc).length;
  File(outPath).writeAsStringSync(exporter.export(doc));
  stdout.writeln('Exported $written of $approved approved game(s) -> $outPath');
  if (written < approved) {
    stdout.writeln('  ${approved - written} left out: the $target target '
        'carries only items with a resolved IGDB match.');
  }
  for (final line in spreadsheetNote(exporter.formulaCells(doc), outPath)) {
    stdout.writeln(line);
  }
}

/// How many formula cells the note names before the rest become a count.
///
/// A line each, so this is a bound on the height of the note rather than the
/// width of a line; six matches [declinedNamesShown] so the two things a
/// single run can say about the same file stop listing at the same point.
const formulaCellsShown = 6;

/// Stdout lines naming the exported cells a spreadsheet evaluates (T-0187).
///
/// Empty when there are none. A warning that fires on every export is one
/// people learn to ignore -- the failure T-0161 named for the folder dialog --
/// and the ordinary export has no such cell in it at all.
///
/// Named rather than counted, for T-0123's reason: a count cannot be traced
/// back to the row it came from. The remedy is not spelled out in full here
/// because it is two dialogs in two applications and this is a terminal line;
/// README's "Opening the CSV in a spreadsheet" is the page it points at, and
/// `csv_formula_cell_test.dart` pins that the page still says it.
List<String> spreadsheetNote(List<FormulaCell> cells, String outPath) {
  if (cells.isEmpty) return const [];
  final rest = cells.length - formulaCellsShown;
  return [
    '${cells.length} cell(s) begin with =, +, - or @, which Excel, LibreOffice '
        'and Google Sheets read as a formula rather than as text:',
    for (final cell in cells.take(formulaCellsShown))
      '    ${cell.column}: ${cell.value}',
    if (rest > 0) '    ... and $rest more',
    '  They are written through unchanged and an import dialog is unaffected. '
        'To read $outPath in a spreadsheet, import it with the columns set to '
        'Text (Excel: Data -> From Text/CSV) rather than double-clicking it -- '
        'README, "Opening the CSV in a spreadsheet".',
  ];
}

String? _option(List<String> args, String flag) {
  final index = args.indexOf(flag);
  return index >= 0 && index + 1 < args.length ? args[index + 1] : null;
}
