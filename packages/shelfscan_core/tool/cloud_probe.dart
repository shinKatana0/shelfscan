/// A control set through a cloud endpoint, repeated, with the token bill
/// (T-0112).
///
/// Not `control_capture.dart`: that tool is the LOCAL control, keyed on
/// `SHELFSCAN_OLLAMA_*`, and its output is a capture other tasks replay. A
/// cloud figure must never become a `control-set` manifest block
/// (doc/measurements.md, T-0090) -- the endpoint's model id points at whatever
/// the vendor serves that day, so nothing here is a thing a regeneration has
/// to reproduce. What this writes is one task's evidence file.
///
/// The manifest it parses is the tracked one `control_capture.dart` names; the
/// prose that identifies the photographs is not published, and that tool says
/// why.
///
/// Everything it prints is a count, a duration or a token figure. Titles go to
/// the output file only, for the reason `control_capture.dart` gives: they are
/// an inventory of a private house and a transcript is not where that goes.
/// `rows` prints them on demand, which is the eye check against the
/// photographs and is the only reason to look.
///
///   dart run tool/cloud_probe.dart run  CONTROL-HIRES|CONTROL-LOWRES|all N OUT
///   dart run tool/cloud_probe.dart rows OUT [run]
///   dart run tool/cloud_probe.dart tally OUT
///
/// `run` needs SHELFSCAN_PHOTOS and the three SHELFSCAN_OPENAI_* variables.
/// OUT is written after every photo, so a killed run keeps what it paid for.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shelfscan_core/shelfscan_core.dart';

import 'control_capture.dart'
    show
        findRepoRoot,
        hiRes,
        lowRes,
        promptFingerprint,
        readControlPhotos,
        readManifestWithSizes,
        writeAtomically;

/// The `usage` object of every 200, taken off the wire.
///
/// [OpenAiCompatibleVisionProvider] parses `choices` and drops the rest, and
/// the token bill is half of what this task was asked for. A client wrapper
/// reads it without touching the provider -- T-0111 is in flight in
/// `lib/src/providers/`.
class UsageRecordingClient extends http.BaseClient {
  UsageRecordingClient(this._inner);

  final http.Client _inner;
  final List<Map<String, Object?>> usages = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await _inner.send(request);
    final bytes = await response.stream.toBytes();
    if (response.statusCode == 200) {
      final usage = (jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>)
          ['usage'] as Map<String, dynamic>?;
      if (usage != null) usages.add(flattenUsage(usage));
    }
    return http.StreamedResponse(
      Stream.value(bytes),
      response.statusCode,
      contentLength: bytes.length,
      request: response.request,
      headers: response.headers,
      reasonPhrase: response.reasonPhrase,
    );
  }

  @override
  void close() => _inner.close();
}

/// `prompt_tokens`, `completion_tokens`, `total_tokens` and the two nested
/// details objects, flat. `reasoning_tokens` is inside
/// `completion_tokens_details` and is a third of a GPT-5 answer (T-0120).
Map<String, Object?> flattenUsage(Map<String, dynamic> usage) {
  final flat = <String, Object?>{};
  for (final entry in usage.entries) {
    final value = entry.value;
    if (value is Map) {
      for (final nested in value.entries) {
        if (nested.value is num) flat['${entry.key}.${nested.key}'] = nested.value;
      }
    } else if (value is num) {
      flat[entry.key] = value;
    }
  }
  return flat;
}

Future<Map<String, Object?>> probePhoto(
  VisionProvider provider,
  UsageRecordingClient client,
  PhotoInput photo,
) async {
  final before = client.usages.length;
  final started = DateTime.now();
  Object? failure;
  PhotoAnalysis? analysis;
  try {
    analysis = await provider.analyze(photo);
  } catch (e) {
    failure = e;
  }
  final elapsed = DateTime.now().difference(started);
  return {
    'photo': photo.name,
    'seconds': elapsed.inMilliseconds / 1000,
    if (failure != null) 'error': '$failure',
    'items': [
      for (final d in analysis?.items ?? const <Detection>[])
        {
          'title': d.rawTitle,
          'hint': d.platformHint,
          'media': d.mediaType.name,
          'confidence': d.confidence,
        }
    ],
    'unreadable': [
      for (final u in analysis?.unreadable ?? const <UnreadSpineReport>[])
        {'script': u.script.name, 'reason': u.reason}
    ],
    // Every call the photo cost, refusals included: the 400s of T-0089's
    // correction are free in tokens but are not free in calls.
    'usage': client.usages.sublist(before),
  };
}

Future<int> runProbe(List<String> args, Map<String, String> env) async {
  if (args.length != 3) {
    stderr.writeln(_usage);
    return 2;
  }
  final sets = args[0] == 'all' ? [hiRes, lowRes] : [args[0]];
  final runs = int.tryParse(args[1]);
  final out = args[2];
  if (runs == null || runs < 1 || sets.any((s) => s != hiRes && s != lowRes)) {
    stderr.writeln(_usage);
    return 2;
  }

  final root = findRepoRoot(Directory.current);
  if (root == null) {
    stderr.writeln('Not inside the repository.');
    return 2;
  }
  final manifest = readManifestWithSizes(root);

  final photoRoot = env['SHELFSCAN_PHOTOS'];
  if (photoRoot == null || !Directory(photoRoot).existsSync()) {
    stderr.writeln('Set SHELFSCAN_PHOTOS to the photo directory.');
    return 2;
  }
  final apiKey = env['SHELFSCAN_OPENAI_API_KEY'];
  final baseUrl = env['SHELFSCAN_OPENAI_BASE_URL'];
  final model = env['SHELFSCAN_OPENAI_MODEL'];
  if (apiKey == null || baseUrl == null || model == null) {
    stderr.writeln('Set SHELFSCAN_OPENAI_API_KEY, SHELFSCAN_OPENAI_BASE_URL '
        'and SHELFSCAN_OPENAI_MODEL.');
    return 2;
  }

  final client = UsageRecordingClient(http.Client());
  final adjustments = <String>[];
  final provider = OpenAiCompatibleVisionProvider(
    baseUrl: baseUrl,
    model: model,
    apiKey: apiKey,
    client: client,
    onRequestAdjusted: (note) {
      adjustments.add(note);
      stdout.writeln('  request adjusted: $note');
    },
  );

  // Appending rather than starting a file per invocation: a repeat measured in
  // a second file is a repeat nobody can tally against the first.
  final existing = File(out).existsSync()
      ? jsonDecode(File(out).readAsStringSync()) as Map<String, dynamic>
      : null;
  if (existing != null &&
      (existing['model'] != model ||
          existing['prompt_fingerprint'] != promptFingerprint(detectionPrompt))) {
    stderr.writeln('$out holds a different model or prompt. Use another file.');
    return 2;
  }
  final record = <String, Object?>{
    'model': model,
    'base_url': baseUrl,
    'prompt_fingerprint': promptFingerprint(detectionPrompt),
    'started': existing?['started'] ?? DateTime.now().toUtc().toIso8601String(),
    'runs': <Map<String, Object?>>[
      for (final r in (existing?['runs'] as List? ?? const []))
        (r as Map).cast<String, Object?>()
    ],
    'adjustments': adjustments,
  };
  final results = record['runs'] as List<Map<String, Object?>>;
  final runsDone = <String, int>{};
  for (final r in results) {
    final set = r['set'] as String;
    final n = r['run'] as int;
    if (n > (runsDone[set] ?? 0)) runsDone[set] = n;
  }

  try {
    for (final set in sets) {
      final photos = readControlPhotos(set, photoRoot, manifest[set]!);
      final first = (runsDone[set] ?? 0) + 1;
      for (var run = first; run < first + runs; run++) {
        for (final photo in photos) {
          // One at a time: `visionConcurrency` 3 would make the first three
          // photos pay T-0089's correction each, and the wall clock is not
          // what is being measured.
          final result = await probePhoto(provider, client, photo);
          results.add({'set': set, 'run': run, ...result});
          writeAtomically(
              out, const JsonEncoder.withIndent('  ').convert(record));
          stdout.writeln('$set run $run ${photo.name}: '
              '${(result['items'] as List).length} item(s), '
              '${(result['unreadable'] as List).length} unreadable, '
              '${result['seconds']} s, '
              '${_tokens(result)} tokens'
              '${result['error'] != null ? ' -- FAILED' : ''}');
        }
      }
    }
  } finally {
    client.close();
    record['finished'] = DateTime.now().toUtc().toIso8601String();
    writeAtomically(out, const JsonEncoder.withIndent('  ').convert(record));
  }
  tally(out);
  return 0;
}

String _tokens(Map<String, Object?> result) {
  var total = 0;
  for (final usage in result['usage'] as List) {
    total += ((usage as Map)['total_tokens'] as num?)?.toInt() ?? 0;
  }
  return '$total';
}

/// Titles and hints of one run, for the check against the photographs.
void rows(String out, int run) {
  final record = jsonDecode(File(out).readAsStringSync()) as Map<String, dynamic>;
  for (final entry in record['runs'] as List) {
    if (entry['run'] != run) continue;
    stdout.writeln('--- ${entry['photo']} (${entry['set']}, run $run)');
    for (final item in entry['items'] as List) {
      stdout.writeln('${item['hint'] ?? '-'}\t${item['title']}');
    }
    for (final u in entry['unreadable'] as List) {
      stdout.writeln('UNREADABLE\t${u['reason'] ?? ''}');
    }
  }
}

/// Counts only: per photo per run, the hint histogram, and the bill.
void tally(String out) {
  final record = jsonDecode(File(out).readAsStringSync()) as Map<String, dynamic>;
  final byPhoto = <String, List<int>>{};
  final hints = <String, int>{};
  final titleSets = <String, Set<String>>{};
  final foldedSets = <String, Set<String>>{};
  var prompt = 0, completion = 0, reasoning = 0, cached = 0, calls = 0;

  for (final entry in (record['runs'] as List).cast<Map<String, dynamic>>()) {
    final items = entry['items'] as List;
    byPhoto.putIfAbsent(entry['photo'] as String, () => []).add(items.length);
    for (final item in items) {
      final hint = (item['hint'] as String?) ?? '(none)';
      hints[hint] = (hints[hint] ?? 0) + 1;
      final row = '${entry['photo']}#${entry['run']}';
      // Two keys because they answer two questions: the raw one moves when the
      // model retypes a (tm) (T-0090 measured 13 rows of 18 doing that on one
      // run), and only the folded one moves when it reads a different spine.
      titleSets.putIfAbsent(row, () => {}).add((item['title'] as String).toUpperCase());
      foldedSets.putIfAbsent(row, () => {}).add(titleKey(item['title'] as String));
    }
    for (final usage in (entry['usage'] as List).cast<Map<String, dynamic>>()) {
      calls++;
      prompt += (usage['prompt_tokens'] as num?)?.toInt() ?? 0;
      completion += (usage['completion_tokens'] as num?)?.toInt() ?? 0;
      reasoning +=
          (usage['completion_tokens_details.reasoning_tokens'] as num?)?.toInt() ?? 0;
      cached += (usage['prompt_tokens_details.cached_tokens'] as num?)?.toInt() ?? 0;
    }
  }

  stdout.writeln('model            ${record['model']}');
  stdout.writeln('prompt f-print   ${record['prompt_fingerprint']}');
  byPhoto.forEach((photo, counts) => stdout.writeln('$photo  $counts'));
  stdout.writeln('hints            ${_sorted(hints)}');
  stdout.writeln('raw titles       ${_spread(titleSets)}');
  stdout.writeln('folded titles    ${_spread(foldedSets)}');
  stdout.writeln('hint spread      ${_hintSpread(record)}');
  stdout.writeln('calls $calls  prompt $prompt (cached $cached)  '
      'completion $completion (reasoning $reasoning)  '
      'total ${prompt + completion}');
  final notes = record['adjustments'] as List;
  if (notes.isNotEmpty) stdout.writeln('adjustments      ${notes.length}');
}

/// Per photo: the `SWITCH 2` count each run answered, and how many folded
/// titles were given more than one hint across the runs.
///
/// The second number is the one that decides whether a hint can be trusted per
/// row; a stable total with a wandering assignment would look identical in the
/// histogram.
String _hintSpread(Map<String, dynamic> record) {
  final switch2 = <String, List<int>>{};
  final hintsOf = <String, Map<String, Set<String>>>{};
  for (final entry in (record['runs'] as List).cast<Map<String, dynamic>>()) {
    final photo = entry['photo'] as String;
    var count = 0;
    for (final item in entry['items'] as List) {
      final hint = (item['hint'] as String?)?.toUpperCase() ?? '(none)';
      if (hint == 'SWITCH 2' || hint == 'SWITCH2') count++;
      hintsOf
          .putIfAbsent(photo, () => {})
          .putIfAbsent(titleKey(item['title'] as String), () => {})
          .add(hint);
    }
    switch2.putIfAbsent(photo, () => []).add(count);
  }
  final out = <String>[];
  switch2.forEach((photo, counts) {
    final wandering =
        hintsOf[photo]!.values.where((hints) => hints.length > 1).length;
    out.add('$photo SWITCH 2 $counts, $wandering title(s) hinted two ways');
  });
  return out.join('; ');
}

/// Per photo: how many distinct title sets its runs produced, and the size of
/// the symmetric difference against the first run.
String _spread(Map<String, Set<String>> titleSets) {
  final byPhoto = <String, List<Set<String>>>{};
  titleSets.forEach((key, titles) =>
      byPhoto.putIfAbsent(key.split('#').first, () => []).add(titles));
  final out = <String>[];
  byPhoto.forEach((photo, sets) {
    final distinct = <String>{for (final s in sets) (s.toList()..sort()).join('|')};
    var maxDiff = 0;
    for (final s in sets) {
      final diff = s.difference(sets.first).length +
          sets.first.difference(s).length;
      if (diff > maxDiff) maxDiff = diff;
    }
    out.add('$photo ${sets.length} run(s), ${distinct.length} distinct, '
        'max ${maxDiff} row(s) differing');
  });
  return out.join('; ');
}

Map<String, int> _sorted(Map<String, int> counts) =>
    Map.fromEntries(counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value)));

const _usage = '''
cloud_probe -- a control set through a cloud endpoint, repeated (T-0112)

  dart run tool/cloud_probe.dart run  CONTROL-HIRES|CONTROL-LOWRES|all N OUT
  dart run tool/cloud_probe.dart rows OUT [run]
  dart run tool/cloud_probe.dart tally OUT

`run` needs SHELFSCAN_PHOTOS and SHELFSCAN_OPENAI_API_KEY / _BASE_URL /
_MODEL, and costs money. `rows` and `tally` are offline and free.
''';

Future<int> run(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln(_usage);
    return 2;
  }
  switch (args.first) {
    case 'run':
      return runProbe(args.sublist(1), Platform.environment);
    case 'rows':
      if (args.length < 2) break;
      rows(args[1], args.length > 2 ? int.parse(args[2]) : 1);
      return 0;
    case 'tally':
      if (args.length < 2) break;
      tally(args[1]);
      return 0;
  }
  stderr.writeln(_usage);
  return 2;
}

Future<void> main(List<String> args) async => exit(await run(args));
