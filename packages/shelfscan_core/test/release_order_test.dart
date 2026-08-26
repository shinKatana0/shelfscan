/// `tool/check-release-order.dart` answers the one question the suite cannot:
/// has this build number already been published? (T-0402)
///
/// `app/test/app_version_test.dart` judges the working tree, which is all a
/// suite can see -- so it is exactly as green on a second artefact built at
/// `+2` as on the first. The check reads each tag's tree instead, and this
/// file is what makes that comparison assertable without cutting a tag.
///
/// Two halves, because two different things can be wrong. `judge` is pure and
/// is exercised over invented text: every branch, including the equal-numbers
/// case the task exists for. Then the committed script is copied into
/// synthetic git repositories and run for real, which is the only way to prove
/// that `git show <tag>:app/pubspec.yaml` reads what it is believed to read
/// and that a repository with no tags exits clean.
///
/// Every fixture is invented -- tag names, versions and package names alike.
library;

import 'dart:io';

import 'package:test/test.dart';

import '../../../tool/check-release-order.dart';

void main() {
  group('the pattern this check judges versions by', () {
    // Controls on the matcher itself, because a pattern that cannot fail
    // proves nothing about what it passed (doc/conventions.md 4a). `+BUILD`
    // is OPTIONAL here and required in app_version_test.dart, so these are
    // not that file's controls over again -- the first case is the one that
    // differs, and it is the tagged tree this repository actually has.
    test('a version with no build number parses, and publishes 1', () {
      final parsed = parseVersion('0.1.0');
      expect(parsed, isNotNull);
      expect(parsed!.build, isNull);
      expect(parsed.versionCode, 1,
          reason: 'Flutter substitutes 1 for an absent +N, so a tagged tree '
              'without one published 1 rather than 0 or nothing');
    });

    test('a version with a build number parses', () {
      expect(parseVersion('4.5.6+78')!.build, 78);
    });

    test('what is not a version at all', () {
      expect(parseVersion('0.2.0+'), isNull);
      expect(parseVersion('0.2.0+beta'), isNull);
      expect(parseVersion('0.2.0+2026-08-25'), isNull);
      expect(parseVersion('nonsense'), isNull);
      expect(parseVersion(null), isNull);
    });

    test('the key pattern reads the top-level version, not a constraint', () {
      const pubspec = 'name: planted\n'
          'version: 1.2.3+4\n'
          'dependencies:\n'
          '  version: ^9.9.9\n';
      expect(readVersionKey(pubspec), '1.2.3+4');
    });

    test('a pubspec with no top-level version reads as none', () {
      expect(readVersionKey('name: planted\n'), isNull);
    });
  });

  group('the comparison', () {
    test('a build number ahead of everything published is in step', () {
      final verdict = _judge(tree: '3.1.0+9', published: {'v3.0.0': '3.0.0+8'});

      expect(verdict.outcome, Outcome.inStep);
      expect(verdict.outcome.exitCode, 0);
      expect(_text(verdict), contains('RELEASE ORDER: OK'));
    });

    // The case the whole task exists for: two artefacts Android cannot tell
    // apart, which the suite reports green.
    test('a build number already published is refused, and named', () {
      final verdict = _judge(tree: '3.1.0+8', published: {'v3.0.0': '3.0.0+8'});

      expect(verdict.outcome, Outcome.refused);
      expect(verdict.outcome.exitCode, 1);
      expect(_text(verdict),
          contains('build number 8 was already published by v3.0.0'));
      expect(_text(verdict), contains('this tree declares 3.1.0+8'));
      expect(_text(verdict), contains('v3.0.0 published 3.0.0+8'));
    });

    test('a build number behind what was published is refused', () {
      final verdict = _judge(tree: '3.1.0+4', published: {'v3.0.0': '3.0.0+8'});

      expect(verdict.outcome, Outcome.refused);
      expect(_text(verdict), contains('build number 4 is behind 8'));
    });

    test('a tagged tree with no +N published 1, so +1 is refused', () {
      final verdict = _judge(tree: '0.9.0+1', published: {'v0.8.0': '0.8.0'});

      expect(verdict.outcome, Outcome.refused);
      expect(_text(verdict),
          contains('build number 1 was already published by v0.8.0'));
      expect(_text(verdict), contains('no +N, so Flutter substituted it'));
    });

    test('...and +2 against that same tag is in step', () {
      final verdict = _judge(tree: '0.9.0+2', published: {'v0.8.0': '0.8.0'});

      expect(verdict.outcome, Outcome.inStep);
    });

    // Not "the most recent tag": the rule is never reused, which is a claim
    // about everything ever published.
    test('the highest published number binds, not the newest tag', () {
      final verdict = _judge(tree: '2.0.0+12', published: {
        'v1.0.0': '1.0.0+20',
        'v1.5.0': '1.5.0+11',
      });

      expect(verdict.outcome, Outcome.refused);
      expect(_text(verdict), contains('behind 20, published by v1.0.0'));
    });

    test('no tags at all is a clean exit and says which it is', () {
      final verdict = _judge(tree: '3.1.0+9', published: const {});

      expect(verdict.outcome, Outcome.nothingPublished);
      expect(verdict.outcome.exitCode, 0);
      expect(_text(verdict), contains('no previous tag'));
      expect(_text(verdict), contains('--no-tags'));
    });

    test('two pubspecs that disagree are refused before any tag is read', () {
      final verdict = judge(
        app: _pubspec('3.1.0+9'),
        core: _pubspec('3.1.0+8'),
        tags: const [],
      );

      expect(verdict.outcome, Outcome.refused);
      expect(_text(verdict), contains('the two pubspecs disagree'));
      expect(_text(verdict), contains('declares 3.1.0+9'));
      expect(_text(verdict), contains('declares 3.1.0+8'));
    });

    test('a tree with no build number is refused', () {
      final verdict = _judge(tree: '3.1.0', published: {'v3.0.0': '3.0.0+8'});

      expect(verdict.outcome, Outcome.refused);
      expect(_text(verdict), contains('the tree declares no build number'));
    });

    test('a pubspec with no version key is refused', () {
      final verdict = judge(
        app: 'name: planted\n',
        core: _pubspec('3.1.0+9'),
        tags: const [],
      );

      expect(verdict.outcome, Outcome.refused);
      expect(_text(verdict), contains('declares no top-level version'));
    });

    // Exit 2 is not exit 0: a run that compared nothing has proved nothing
    // and must not read as green (doc/conventions.md 4a).
    test('a missing pubspec compares nothing, and does not read as green', () {
      final verdict = judge(app: null, core: null, tags: const []);

      expect(verdict.outcome, Outcome.nothingCompared);
      expect(verdict.outcome.exitCode, 2);
      expect(_text(verdict), contains('NOT CHECKED'));
    });

    test('a tag whose tree holds no pubspec compares nothing either', () {
      final verdict = judge(
        app: _pubspec('3.1.0+9'),
        core: _pubspec('3.1.0+9'),
        tags: const [PublishedTag('v-ancient', null)],
      );

      expect(verdict.outcome, Outcome.nothingCompared);
      expect(verdict.outcome.exitCode, 2);
      expect(_text(verdict), contains('no tag declares a readable version'));
      expect(_text(verdict), contains('v-ancient'));
    });

    test('...but one unreadable tag beside a readable one is named, not '
        'fatal', () {
      final verdict = judge(
        app: _pubspec('3.1.0+9'),
        core: _pubspec('3.1.0+9'),
        tags: [
          const PublishedTag('v-ancient', null),
          PublishedTag('v3.0.0', _pubspec('3.0.0+8')),
        ],
      );

      expect(verdict.outcome, Outcome.inStep);
      expect(_text(verdict), contains('not compared: v-ancient'));
    });
  });

  group('the script itself, over a real repository', () {
    late Directory root;

    setUp(() => root = Directory.systemTemp.createTempSync('release-order-'));
    tearDown(() => root.deleteSync(recursive: true));

    test('git is on PATH, which every case below needs', () {
      final run = Process.runSync('git', const ['--version']);
      expect(run.exitCode, 0,
          reason: 'without git these cases fail for a reason that has '
              'nothing to do with the check');
    });

    test('it reads the version out of the tag TREE, not the tag name', () {
      // The tag name carries no build number, exactly as this repository's
      // own does not -- so a check reading the name could not answer at all.
      _plant(root, tree: '0.9.0+2', tags: {'v0.8.0': '0.8.0'});

      final run = _run(root);

      expect(run.exitCode, 0, reason: run.out);
      expect(run.out, contains('RELEASE ORDER: OK'));
      expect(run.out, contains('v0.8.0 published 0.8.0 -> versionCode 1'));
      expect(run.out, contains('this tree declares 0.9.0+2'));
    });

    test('it refuses a build number the tag already published', () {
      _plant(root, tree: '0.9.0+7', tags: {'v0.8.0': '0.8.0+7'});

      final run = _run(root);

      expect(run.exitCode, 1, reason: run.out);
      expect(run.out,
          contains('build number 7 was already published by v0.8.0'));
    });

    test('a repository with no tags exits clean', () {
      _plant(root, tree: '0.9.0+2', tags: const {});

      final run = _run(root);

      expect(run.exitCode, 0, reason: run.out);
      expect(run.out, contains('no previous tag'));
    });

    test('it refuses when the two pubspecs disagree', () {
      _plant(root, tree: '0.9.0+2', core: '0.9.0+3', tags: const {});

      final run = _run(root);

      expect(run.exitCode, 1, reason: run.out);
      expect(run.out, contains('the two pubspecs disagree'));
    });
  });
}

Verdict _judge({
  required String tree,
  required Map<String, String> published,
}) =>
    judge(
      app: _pubspec(tree),
      core: _pubspec(tree),
      tags: [
        for (final entry in published.entries)
          PublishedTag(entry.key, _pubspec(entry.value)),
      ],
    );

String _pubspec(String version) => 'name: planted\n'
    'version: $version\n'
    'environment:\n'
    '  sdk: ^3.4.0\n';

String _text(Verdict verdict) => verdict.lines.join('\n');

/// One run of the copied script over the planted repository.
_Run _run(Directory root) {
  final result = Process.runSync(
    Platform.resolvedExecutable,
    ['run', '${root.path}/tool/check-release-order.dart'],
    workingDirectory: root.path,
  );
  return _Run(result.exitCode, '${result.stdout}${result.stderr}');
}

class _Run {
  _Run(this.exitCode, this.out);

  final int exitCode;
  final String out;
}

/// Builds a git repository holding the committed script, one commit and tag
/// per entry of [tags] in order, and finally the working-tree version.
void _plant(
  Directory root, {
  required String tree,
  required Map<String, String> tags,
  String? core,
}) {
  final tool = File('${root.path}/tool/check-release-order.dart');
  tool.parent.createSync(recursive: true);
  File('${_repoRoot.path}/tool/check-release-order.dart').copySync(tool.path);

  _git(root, const ['init', '-b', 'main']);
  tags.forEach((tag, version) {
    _write(root, appVersion: version, coreVersion: version);
    _git(root, const ['add', '-A']);
    _git(root, ['commit', '-m', 'planted $tag']);
    _git(root, ['tag', tag]);
  });
  _write(root, appVersion: tree, coreVersion: core ?? tree);
}

void _write(
  Directory root, {
  required String appVersion,
  required String coreVersion,
}) {
  for (final pair in [
    (appPubspec, appVersion),
    (corePubspec, coreVersion),
  ]) {
    final file = File('${root.path}/${pair.$1}');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(_pubspec(pair.$2));
  }
}

/// Identity and signing are passed per command rather than read from the
/// machine, so the fixture repository is the same everywhere and the run
/// cannot be stopped by a global setting. `core.hooksPath` is cleared for the
/// same reason: this project points it at `.githooks`.
void _git(Directory root, List<String> args) {
  final run = Process.runSync(
    'git',
    [
      '-c', 'user.name=fixture',
      '-c', 'user.email=fixture@example.invalid',
      '-c', 'commit.gpgsign=false',
      '-c', 'tag.gpgsign=false',
      '-c', 'core.hooksPath=',
      ...args,
    ],
    workingDirectory: root.path,
  );
  if (run.exitCode != 0) {
    fail('git ${args.join(' ')} failed: ${run.stdout}${run.stderr}');
  }
}

late final Directory _repoRoot = () {
  for (var dir = Directory.current.absolute;; dir = dir.parent) {
    if (File('${dir.path}/.env.example').existsSync()) return dir;
    if (dir.path == dir.parent.path) {
      fail('no .env.example at or above ${Directory.current.path}');
    }
  }
}();
