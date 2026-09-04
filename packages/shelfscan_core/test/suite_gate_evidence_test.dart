/// `tool/check-suites.sh` is this project's gate, and this pins that a run can
/// only ever read evidence it produced itself (T-0463).
///
/// The defect: `--log-dir` used to be the destination, one scratchpad is handed
/// to every worker in a session, and the script writes `core.log` before
/// `app.log`. A run stopped between the two left the PREVIOUS run's `app.log`
/// and `app.did-not-complete` standing -- green, complete, and about another
/// worktree -- so a reader doing exactly what `doc/conventions.md` section 4a
/// asks reported somebody else's green.
///
/// **No real suite runs here.** Running `dart test` and `flutter test` for
/// every case would cost minutes each and would prove nothing about which
/// directory the evidence landed in. Instead each case plants a synthetic
/// repository in a temporary directory -- the committed script copied byte for
/// byte, the two suite directories it `cd`s into, and a `dart`/`flutter` stand
/// -in on PATH that prints what a runner prints. What is under test is the
/// script's own reading and writing, which is all of it that this task
/// changed.
///
/// **The stand-in is its own positive control.** A real `dart test` in an empty
/// planted directory answers `No pubspec.yaml file found` and exit 65, which
/// the script reads as TRUNCATED and reports NOT GREEN. So a PATH injection
/// that silently failed to take could not produce a green here: every green
/// assertion below is evidence the stand-in was the thing that ran.
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// Invented, and carrying both hazards this shell has been measured to lose:
/// a space, and characters outside ASCII.
const _awkwardName = 'проба журналов';

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('suite-gate-'));
  tearDown(() {
    // Releases any stand-in still waiting, so no case leaves a process behind.
    File('${tmp.path}/release').writeAsStringSync('go\n');
    try {
      tmp.deleteSync(recursive: true);
    } on FileSystemException {
      // A stand-in one poll away from exiting can still hold a handle here.
    }
  });

  test('a run writes only into a directory it created', () {
    final root = _plant(tmp);
    final parent = _dir('${tmp.path}/parent');

    final run = _run(root, logParent: parent);

    expect(run.exitCode, 0, reason: run.out);
    expect(run.out, contains('PREFLIGHT: GREEN'));

    final dirs = _runDirs(parent);
    expect(dirs, hasLength(1), reason: 'one run, one directory');
    expect(run.out, contains('LOGS: ${parent.path}/${_name(dirs.single)}'),
        reason: 'the resolved directory has to be discoverable from stdout');

    for (final name in ['core.log', 'app.log', 'run.info', 'verdict']) {
      expect(File('${dirs.single.path}/$name').existsSync(), isTrue,
          reason: '$name is missing from the run directory');
    }
    for (final name in ['core.did-not-complete', 'app.did-not-complete']) {
      final file = File('${dirs.single.path}/$name');
      expect(file.existsSync(), isTrue, reason: '$name is missing');
      expect(file.readAsStringSync(), isEmpty,
          reason: '$name must stay empty when nothing died');
    }

    // The parent itself holds the run directory and nothing else: the four
    // artefact names must not appear beside it.
    expect(parent.listSync().map(_name).toList(), [_name(dirs.single)]);
  }, skip: _needsShell);

  test('a stale green in the parent cannot be read as this run\'s', () {
    final root = _plant(tmp);
    final parent = _dir('${tmp.path}/parent');

    // The incident, planted: an earlier run's app evidence, green and
    // complete, sitting where `--log-dir` points.
    const stale = '00:09 +7: All tests passed!\n';
    File('${parent.path}/app.log').writeAsStringSync(stale);
    File('${parent.path}/app.did-not-complete').writeAsStringSync('');
    File('${parent.path}/core.log').writeAsStringSync(stale);

    // `core` alone is the incident's own shape: a run that never reaches
    // the second suite, which is what used to leave the stale app evidence
    // standing where the reader would find it.
    final run =
        _run(root, logParent: parent, mode: 'fail', args: const ['core']);

    expect(run.exitCode, 1, reason: run.out);
    expect(run.out, contains('PREFLIGHT: NOT GREEN -- a real failure'));
    expect(run.out, isNot(contains('GREEN: ')));

    final dirs = _runDirs(parent);
    expect(dirs, hasLength(1));
    expect(File('${dirs.single.path}/core.log').readAsStringSync(),
        contains('Some tests failed.'),
        reason: 'the run must read the log it wrote');

    // And it deleted nothing it did not create: the parent may be shared with
    // a live run, which is the whole premise of the defect.
    expect(File('${parent.path}/app.log').readAsStringSync(), stale);
    expect(File('${parent.path}/core.log').readAsStringSync(), stale);
    expect(File('${parent.path}/app.did-not-complete').existsSync(), isTrue);
  }, skip: _needsShell);

  test('two runs given one --log-dir do not share evidence', () {
    final root = _plant(tmp);
    final parent = _dir('${tmp.path}/parent');

    final first = _run(root, logParent: parent, args: const ['core']);
    final second =
        _run(root, logParent: parent, mode: 'fail', args: const ['core']);

    expect(first.exitCode, 0, reason: first.out);
    expect(second.exitCode, 1, reason: second.out);

    final dirs = _runDirs(parent);
    expect(dirs, hasLength(2), reason: 'each run creates its own directory');
    expect(dirs[0].path, isNot(dirs[1].path));

    final verdicts = dirs
        .map((d) => File('${d.path}/verdict').readAsStringSync())
        .toList();
    expect(verdicts.where((v) => v.contains('PREFLIGHT: GREEN')), hasLength(1));
    expect(verdicts.where((v) => v.contains('NOT GREEN')), hasLength(1));
  }, skip: _needsShell);

  test('an interrupted run cannot be read as a finished one', () async {
    final root = _plant(tmp);
    final parent = _dir('${tmp.path}/parent');

    // core answers green and app does not answer at all, which is exactly
    // where the incident's run was cut off.
    final started = await _start(root, logParent: parent, mode: 'slow-app');
    final runDir = await _await(() {
      final dirs = _runDirs(parent);
      if (dirs.length != 1) return null;
      return File('${dirs.single.path}/app.log').existsSync()
          ? dirs.single
          : null;
    }, 'the run reached its second suite');
    started.kill();
    await started.exitCode;

    expect(File('${runDir.path}/core.log').readAsStringSync(),
        contains('All tests passed!'),
        reason: 'the first suite did finish, and green');
    expect(File('${runDir.path}/app.log').readAsStringSync(), isEmpty,
        reason: 'the second suite never answered');

    // The two signals, either of which a reader may check.
    expect(File('${runDir.path}/run-incomplete').existsSync(), isTrue,
        reason: 'an interrupted run keeps its marker');
    expect(File('${runDir.path}/verdict').existsSync(), isFalse,
        reason: 'the verdict is the last act, so it cannot exist yet');

    // And the interrupted evidence cannot satisfy the run that follows it.
    final next = _run(root, logParent: parent, mode: 'fail');
    expect(next.exitCode, 1, reason: next.out);
    expect(_runDirs(parent), hasLength(2));
  }, skip: _needsShell);

  test('stdout keeps its shape and every exit code keeps its meaning', () {
    final root = _plant(tmp);
    final parent = _dir('${tmp.path}/parent');

    final green = _run(root, logParent: parent);
    expect(green.exitCode, 0, reason: green.out);
    expect(green.out, contains('== core: dart test --reporter expanded'));
    expect(green.out, contains('== app: flutter test --reporter expanded'));
    expect(green.out, contains(RegExp(r'exit 0, log .*core\.log')));
    expect(green.out, contains('PREFLIGHT: GREEN'));

    final failed =
        _run(root, logParent: parent, mode: 'fail', args: const ['core']);
    expect(failed.exitCode, 1, reason: failed.out);
    expect(failed.out, contains('PREFLIGHT: NOT GREEN -- a real failure'));

    final died =
        _run(root, logParent: parent, mode: 'host-death', args: const ['core']);
    expect(died.exitCode, 3, reason: died.out);
    expect(died.out, contains('exit 79 is the host-death code'));
    expect(died.out, contains('green alone -> its host died.'));
    expect(
        died.out,
        contains('PREFLIGHT: HOLD -- a test host died; every named file is '
            'green alone'));

    final wedged = _run(root,
        logParent: parent, mode: 'wedge', args: const ['--bound', '1', 'core']);
    expect(wedged.exitCode, 4, reason: wedged.out);
    expect(wedged.out, contains('WEDGED: no verdict after 1s'));
    expect(
        wedged.out,
        contains('PREFLIGHT: HOLD -- the wall-clock bound tripped; nothing '
            'was judged'));

    final misused = _run(root, logParent: parent, args: ['--nope']);
    expect(misused.exitCode, 2, reason: misused.out);
    expect(misused.out, contains('check-suites: unknown argument: --nope'));
  }, skip: _needsShell);

  test('the default with no --log-dir is still a fresh directory of its own',
      () {
    final root = _plant(tmp);
    final fallback = _dir('${tmp.path}/tmpdir');

    final run = _run(root, tmpdir: fallback, args: const ['core']);

    expect(run.exitCode, 0, reason: run.out);
    expect(_runDirs(fallback), hasLength(1));
  }, skip: _needsShell);

  test('a directory whose name holds a space and Cyrillic is handled', () {
    final root = _plant(_dir('${tmp.path}/$_awkwardName'));
    final parent = _dir('${tmp.path}/$_awkwardName/parent $_awkwardName');

    final run = _run(root, logParent: parent, args: const ['core']);

    expect(run.exitCode, 0, reason: run.out);
    expect(run.out, contains('PREFLIGHT: GREEN'));
    final dirs = _runDirs(parent);
    expect(dirs, hasLength(1));
    expect(File('${dirs.single.path}/core.log').readAsStringSync(),
        contains('All tests passed!'));
  }, skip: _needsShell);

  test('the run records whose it is', () {
    final root = _plant(tmp);
    final parent = _dir('${tmp.path}/parent');
    // With no commit `rev-parse HEAD` still answers nothing, so this proves
    // the working tree is read rather than the commit -- and the tree is the
    // field that matters: the core log names no worktree anywhere in it.
    final repo = _gitInit(root);

    final run = _run(root, logParent: parent, args: const ['core']);
    expect(run.exitCode, 0, reason: run.out);

    final info =
        File('${_runDirs(parent).single.path}/run.info').readAsStringSync();
    for (final field in [
      'logdir',
      'root',
      'started',
      'pid',
      'head',
      'branch',
      'worktree'
    ]) {
      expect(info, contains(RegExp('^$field ', multiLine: true)),
          reason: 'run.info must name $field');
    }
    expect(info, contains(RegExp(r'^root +.*/tree$', multiLine: true)));
    expect(info,
        contains(RegExp(r'^started +[0-9]{8}T[0-9]{6}Z$', multiLine: true)));
    expect(info, contains(RegExp(r'^pid +[0-9]+$', multiLine: true)));
    // One field per line and no more: `git rev-parse` answering `HEAD` on its
    // way to exit 128 put two lines under one name until this caught it.
    expect(const LineSplitter().convert(info), hasLength(7));
    if (repo) {
      expect(info, contains(RegExp(r'^worktree .*/tree$', multiLine: true)),
          reason: 'the tree the run was launched from is the missing half');
    }
  }, skip: _needsShell);
}

// ---------------------------------------------------------------------------

/// Built rather than typed, so nothing between here and the file on disk can
/// eat it -- and doubled inside the character class, because what the source
/// must not carry literally the regex engine still needs escaped
/// (`doc/conventions.md` section 4a).
final _bs = String.fromCharCode(92);
final _anySep = RegExp('[/$_bs$_bs]');

/// `sh` and nothing else. On Windows `bash` may resolve to WSL's, which sees a
/// different filesystem and would fail in a way that says nothing about this
/// script, so there is deliberately no fallback -- and no fallback to a green
/// either: every case below runs the script, so a host without a POSIX shell
/// says so by name rather than passing quietly.
final String? _needsShell = () {
  try {
    if (Process.runSync('sh', ['-c', 'exit 7']).exitCode == 7) return null;
  } on ProcessException {
    // Falls through to the reason below.
  }
  return 'sh is not runnable here, and the gate under test is a shell script';
}();

class _Run {
  _Run(this.exitCode, this.out);

  final int exitCode;
  final String out;
}

Directory _dir(String path) => Directory(path)..createSync(recursive: true);

String _name(FileSystemEntity entity) => entity.path.split(_anySep).last;

/// Makes [root] a repository so the identity record has a tree to read. False
/// where git is not runnable, which leaves the git half of that record unasserted.
bool _gitInit(Directory root) {
  try {
    return Process.runSync('git', ['init', '--quiet', root.path]).exitCode == 0;
  } on ProcessException {
    return false;
  }
}

/// The run directories the script created under [parent], oldest name first.
List<Directory> _runDirs(Directory parent) => parent
    .listSync()
    .whereType<Directory>()
    .where((d) => d.path.split(_anySep).last.startsWith('shelfscan-suites-'))
    .toList()
  ..sort((a, b) => a.path.compareTo(b.path));

/// A synthetic repository under [where]: the committed script, the two
/// directories it `cd`s into, the stand-in runners, and a launcher that puts
/// them on PATH.
Directory _plant(Directory where) {
  final root = _dir('${where.path}/tree');
  _dir('${root.path}/packages/shelfscan_core');
  _dir('${root.path}/app');
  _dir('${root.path}/tool');
  File('${_repoRoot.path}/tool/check-suites.sh')
      .copySync('${root.path}/tool/check-suites.sh');

  final stub = _dir('${root.path}/stub');
  File('${stub.path}/dart').writeAsStringSync(_stubScript);
  File('${stub.path}/flutter').writeAsStringSync(_stubScript);
  File('${root.path}/with-stubs.sh').writeAsStringSync(_launcherScript);
  return root;
}

List<String> _argv(
  Directory root, {
  Directory? logParent,
  List<String> args = const [],
}) =>
    [
      '${root.path}/with-stubs.sh',
      '${root.path}/stub',
      '${root.path}/tool/check-suites.sh',
      if (logParent != null) ...['--log-dir', logParent.path],
      ...args,
    ];

Map<String, String> _env(String mode, Directory root, Directory? tmpdir) => {
      'SHELFSCAN_STUB_MODE': mode,
      'SHELFSCAN_STUB_RELEASE': '${root.parent.path}/release',
      if (tmpdir != null) 'TMPDIR': tmpdir.path,
    };

_Run _run(
  Directory root, {
  String mode = 'green',
  Directory? logParent,
  Directory? tmpdir,
  List<String> args = const [],
}) {
  final result = Process.runSync(
    'sh',
    _argv(root, logParent: logParent, args: args),
    environment: _env(mode, root, tmpdir),
    stdoutEncoding: null,
    stderrEncoding: null,
  );
  return _Run(
    result.exitCode,
    '${_text(result.stdout)}${_text(result.stderr)}',
  );
}

Future<Process> _start(
  Directory root, {
  String mode = 'green',
  Directory? logParent,
}) =>
    Process.start(
      'sh',
      _argv(root, logParent: logParent),
      environment: _env(mode, root, null),
    );

/// The script writes UTF-8; this console does not read it, so the bytes are
/// decoded here rather than by whatever the platform encoding happens to be.
String _text(Object? raw) =>
    raw is List<int> ? utf8.decode(raw, allowMalformed: true) : '$raw';

/// Polls [probe] until it answers, or fails naming what never happened.
Future<T> _await<T>(T? Function() probe, String what) async {
  for (var i = 0; i < 300; i++) {
    final answer = probe();
    if (answer != null) return answer;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  fail('timed out waiting until $what');
}

late final Directory _repoRoot = () {
  for (var dir = Directory.current.absolute;; dir = dir.parent) {
    if (File('${dir.path}/.env.example').existsSync()) return dir;
    if (dir.path == dir.parent.path) {
      fail('no .env.example at or above ${Directory.current.path}');
    }
  }
}();

/// Prepends a directory to PATH in the shell's own path vocabulary. Doing this
/// from Dart would mean guessing whether the inherited PATH is the Windows
/// form or the POSIX one; `cd` accepts either and `pwd` answers in the form
/// the shell will search.
const _launcherScript = '''
#!/bin/sh
set -u
_stub=\$(CDPATH= cd -- "\$1" && pwd)
shift
PATH="\$_stub:\$PATH"
export PATH
exec sh "\$@"
''';

/// Stands in for `dart test` and `flutter test`, answering what a runner
/// answers. A re-run naming one file comes back green whatever the mode, which
/// is the host-death discriminator the script exists for.
const _stubScript = '''
#!/bin/sh
_last=
for _a in "\$@"; do _last=\$_a; done
case "\$_last" in
  *.dart) echo "00:01 +1: All tests passed!"; exit 0 ;;
esac
_who=\${0##*/}
_mode=\${SHELFSCAN_STUB_MODE:-green}
case "\$_mode" in
  slow-app) [ "\$_who" = flutter ] && _mode=wait || _mode=green ;;
esac
case "\$_mode" in
  green)
    echo "00:00 +0: loading"
    echo "00:01 +2: All tests passed!"
    exit 0 ;;
  fail)
    echo "00:00 +0: loading"
    echo "00:01 +1 -1: Some tests failed."
    exit 1 ;;
  host-death)
    echo "00:00 +0: loading"
    echo "00:05 +0 -1: test/planted_test.dart: a case - did not complete [E]"
    echo "00:05 +0 -1: Some tests failed."
    exit 79 ;;
  wait)
    _i=0
    while [ ! -f "\${SHELFSCAN_STUB_RELEASE:-/nonexistent}" ] && [ \$_i -lt 60 ]
    do
      sleep 1
      _i=\$((_i + 1))
    done
    exit 0 ;;
  wedge)
    sleep 30
    exit 0 ;;
esac
''';
