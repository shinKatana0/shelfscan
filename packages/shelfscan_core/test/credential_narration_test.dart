/// What the CLI tells a run about the resolve stage, in each of the four
/// credential states it can be in (T-0387).
///
/// `_makeResolver` narrated one credential when there was one catalogue.
/// Since TMDB there are two, and the run holding a TMDB token and no IGDB
/// pair was told `resolve stage will be skipped` and then looked film and
/// anime rows up on TMDB. The second half of that sentence -- games stay
/// unresolved -- stayed true, which is what made the first half easy to read
/// past.
///
/// ## The shape of the assertion, and why it is not a string comparison
///
/// A test that pinned each state's sentence would pin the defect just as
/// happily as the fix. So the claim is checked against the program rather
/// than against a literal: a run may say the stage will be skipped **exactly
/// when** [resolverFor] hands back a [SkipResolver] for that same
/// environment. One side is what the user is told, the other is what the run
/// then does, and they are read from two different places -- a subprocess's
/// stdout and the factory itself.
///
/// ## Four states, and why four is all of them
///
/// Two credentials, each present or absent, and neither has a third
/// condition: `igdbCredentialsFrom` wants both halves or answers null, and
/// `tmdbTokenFrom` answers a token or null. A present-but-empty variable
/// reads as absent (T-0080), which is also what keeps these runs off the real
/// credentials of the machine running them.
///
/// **Nothing here reaches IGDB or TMDB.** The fixture holds one folder whose
/// name titles no game, so it declines and the run carries no detection for
/// any catalogue to answer -- in every one of the four states, including the
/// two that build a live client.
///
/// Every credential below is invented (`doc/conventions.md` §3b).
@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';

import 'package:shelfscan_core/shelfscan_core.dart';
import 'package:test/test.dart';

import '../bin/shelfscan.dart' show resolverFor;
import 'cli_snapshot.dart';

const _states = <String, Map<String, String>>{
  'both credentials': {
    'IGDB_CLIENT_ID': 'twitch-id',
    'IGDB_CLIENT_SECRET': 'twitch-secret',
    'SHELFSCAN_TMDB_TOKEN': 'tmdb-not-a-token',
  },
  'IGDB only': {
    'IGDB_CLIENT_ID': 'twitch-id',
    'IGDB_CLIENT_SECRET': 'twitch-secret',
    'SHELFSCAN_TMDB_TOKEN': '',
  },
  'TMDB only': {
    'IGDB_CLIENT_ID': '',
    'IGDB_CLIENT_SECRET': '',
    'SHELFSCAN_TMDB_TOKEN': 'tmdb-not-a-token',
  },
  'neither': {
    'IGDB_CLIENT_ID': '',
    'IGDB_CLIENT_SECRET': '',
    'SHELFSCAN_TMDB_TOKEN': '',
  },
};

/// The promise under test. A fragment rather than a sentence on purpose: what
/// must not be said in a run that resolves anything is the claim, however it
/// is later worded around.
const _skipClaim = 'resolve stage will be skipped';

/// The wording three guides and three READMEs quote, and that
/// `guide_transcript_test.dart` pins as `igdb-skipped`. Typed here as an
/// independent copy: a test comparing the program to the guides stays green
/// when somebody edits both, and this one does not.
const _keyless = 'IGDB credentials not set -- resolve stage will be skipped, '
    'games stay unresolved (fine for vision validation).';

Directory _tempDir(String prefix) {
  final dir = Directory.systemTemp.createTempSync(prefix);
  addTearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // The Windows errno 145 race the other path suites document.
    }
  });
  return dir;
}

String _join(String dir, String name) => '$dir${Platform.pathSeparator}$name';

/// The stdout lines between the command's own opening notice and the first
/// stage banner: everything `_makeResolver` said, and nothing else.
List<String> _narrationOf(String out) {
  final lines = const LineSplitter().convert(out.trimRight());
  final end = lines.indexOf('== source ==');
  expect(end, greaterThan(0), reason: 'no stage banner in: $out');
  return lines.sublist(1, end);
}

void main() {
  setUpAll(cliSnapshot);

  late Directory games;
  late String out;

  setUp(() {
    games = _tempDir('shelfscan_narration_games_');
    out = _join(_tempDir('shelfscan_narration_out_').path, 'n.review.json');
    // Declines by name, so the run holds no row and no catalogue is called.
    // An OS default folder name is the software's own vocabulary, which is
    // the standing exception `doc/conventions.md` §3b names.
    Directory(_join(games.path, 'Downloads')).createSync();
  });

  Future<List<String>> narration(Map<String, String> env) async {
    final result = await Process.run(
      Platform.resolvedExecutable,
      [cliSnapshot(), 'scan-installs', games.path, '-o', out],
      environment: env,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
    return _narrationOf(result.stdout as String);
  }

  test('four states, and the enumeration is complete', () {
    // Guards the table against a state being dropped rather than fixed: the
    // per-state tests below are generated from it, so a missing entry would
    // otherwise remove its own check in silence.
    expect(_states, hasLength(4));
  });

  group('a run is promised a skipped stage only when the stage is skipped', () {
    for (final state in _states.entries) {
      test(state.key, () async {
        final said = (await narration(state.value)).join('\n');
        final skips = resolverFor(state.value) is SkipResolver;

        expect(said.contains(_skipClaim), skips,
            reason: skips
                ? 'the stage is skipped and the run was not told so: $said'
                : 'the stage runs and the run was told it would not: $said');
      });
    }
  });

  test('TMDB only: told what it gets, not that it gets nothing', () async {
    final said = await narration(_states['TMDB only']!);

    expect(said.first, contains('IGDB credentials not set'));
    expect(said.first, contains('games stay unresolved'));
    expect(said.first, contains('looked up on TMDB'));
    expect(said.first, isNot(contains(_skipClaim)));
  });

  test('neither: the pinned wording, unmoved, on the pinned line', () async {
    final said = await narration(_states['neither']!);

    // `guide_transcript_test.dart` reads stdout line 1 for `igdb-skipped`,
    // which is this line: the first thing said after the opening notice, and
    // the only thing said at all in this state.
    expect(said, [_keyless]);
  });
}
