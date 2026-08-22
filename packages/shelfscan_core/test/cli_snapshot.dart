/// The CLI compiled once per run, for the nine suites that spawn it (T-0217).
///
/// `dart run bin/shelfscan.dart` writes no snapshot for the file-path form, so
/// every child front-end compiled the entry point from source. Measured on an
/// idle machine, medians of 8 interleaved runs each, through the same
/// `Platform.resolvedExecutable` the suites spawn: 2.29 s for `dart run` on
/// the source, 0.32 s for the kernel snapshot this file builds, 0.19 s for a
/// `dart compile exe` binary.
///
/// The snapshot wins over the AOT binary on the build side and ties on the
/// total: 1.60 s to build against 5.97 s, which over the children in this
/// package cancels the 0.13 s each that AOT is faster. So the tie is broken on
/// the other axis -- a kernel snapshot runs on the same JIT VM `dart run`
/// does, and changes what is compiled rather than how it runs, while AOT is a
/// second execution mode for the CLI that nothing else in this project uses.
///
/// It is built here, not only in CI, so a local `dart test` is as fast as a CI
/// one; `.github/workflows/ci.yml` calls [main] before `dart test` only so the
/// build is not inside a suite's own timeout on a cold runner.
///
/// **A build failure throws and there is deliberately no fallback to
/// `dart run`.** A fallback would turn a broken entry point into a run that is
/// merely slow, and slow is not a thing anyone investigates. The throw carries
/// the compiler's own output, and every test in the calling suite fails in
/// `setUpAll` naming it.
library;

import 'dart:convert';
import 'dart:io';

/// Built once per test process; the lock below is for the concurrent ones.
String? _path;

/// The kernel snapshot to run instead of `bin/shelfscan.dart`, built if it is
/// absent or older than any source it was built from.
///
/// Spawn it as `Process.run(Platform.resolvedExecutable, [cliSnapshot(),
/// ...args])`: the executable is unchanged, only the entry point argument
/// moves from a `.dart` path to this one.
String cliSnapshot() {
  final cached = _path;
  if (cached != null) return cached;

  final snapshot = _absolute('.dart_tool/shelfscan_cli.dill');
  final lockFile = File(_absolute('.dart_tool/shelfscan_cli.lock'));
  lockFile.parent.createSync(recursive: true);
  final lock = lockFile.openSync(mode: FileMode.write);
  // Blocking, because `dart test` runs suites concurrently: without it all
  // nine would build their own copy over each other.
  lock.lockSync(FileLock.blockingExclusive);
  try {
    if (!_isFresh(snapshot)) _build(snapshot);
    return _path = snapshot;
  } finally {
    lock.unlockSync();
    lock.closeSync();
  }
}

/// Pre-builds the snapshot, for CI and for anyone who wants the cost visible
/// as its own step: `dart run test/cli_snapshot.dart`.
void main() => stdout.writeln(cliSnapshot());

String _absolute(String relative) =>
    '${Directory.current.absolute.path}${Platform.pathSeparator}'
    '${relative.replaceAll('/', Platform.pathSeparator)}';

/// Whether [snapshot] is newer than every Dart source linked into it and than
/// the resolved dependency set.
bool _isFresh(String snapshot) {
  final file = File(snapshot);
  if (!file.existsSync()) return false;
  final built = file.lastModifiedSync();
  for (final name in const ['bin', 'lib']) {
    final dir = Directory(name);
    if (!dir.existsSync()) return false;
    for (final entry in dir.listSync(recursive: true)) {
      if (entry is File &&
          entry.path.endsWith('.dart') &&
          entry.statSync().modified.isAfter(built)) {
        return false;
      }
    }
  }
  final lock = File('pubspec.lock');
  return !lock.existsSync() || !lock.lastModifiedSync().isAfter(built);
}

/// Compiles to a temporary path and renames, so a failed or interrupted build
/// can never leave a truncated snapshot that the mtime check then calls fresh.
void _build(String snapshot) {
  final temp = '$snapshot.${pid}_tmp';
  final result = Process.runSync(
    Platform.resolvedExecutable,
    ['compile', 'kernel', 'bin/shelfscan.dart', '-o', temp],
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
  if (result.exitCode != 0 || !File(temp).existsSync()) {
    try {
      File(temp).deleteSync();
    } on FileSystemException {
      // Nothing to clean up: the compiler wrote no output.
    }
    throw StateError(
      'Could not compile the CLI under test.\n'
      '  ${Platform.resolvedExecutable} compile kernel bin/shelfscan.dart\n'
      '  exit ${result.exitCode}, run in ${Directory.current.path}\n'
      '${result.stdout}${result.stderr}',
    );
  }
  File(temp).renameSync(snapshot);
}
