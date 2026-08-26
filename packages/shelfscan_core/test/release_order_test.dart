/// `tool/check-release-order.dart` answers the questions the suite cannot,
/// because both are about what was published rather than about this tree:
/// has this build number already been published (T-0402), and did a tag go
/// out whose own `CHANGELOG.md` named no release for it (T-0408)?
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
/// The changelog half has a control the version half does not need: the state
/// it must stay QUIET on. A tree ahead of the last tag with an open
/// `[Unreleased]` section is this repository on an ordinary day, and a check
/// refusing it would be a check nobody runs -- so that case asserts exit 0 as
/// deliberately as the refusal cases assert exit 1.
///
/// Every fixture is invented -- tag names, versions and package names alike.
/// One deliberate exception, and it is this project's own numbers rather than
/// anyone's data: the two quiet cases are planted at `0.2.0+2` against a
/// `v0.1.0` publishing `0.1.0`, because the state the check must not refuse
/// is the state this repository is actually in.
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
        changelog: _changelog(const []),
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
        changelog: _changelog(const []),
      );

      expect(verdict.outcome, Outcome.refused);
      expect(_text(verdict), contains('declares no top-level version'));
    });

    // Exit 2 is not exit 0: a run that compared nothing has proved nothing
    // and must not read as green (doc/conventions.md 4a).
    test('a missing pubspec compares nothing, and does not read as green', () {
      final verdict =
          judge(app: null, core: null, tags: const [], changelog: null);

      expect(verdict.outcome, Outcome.nothingCompared);
      expect(verdict.outcome.exitCode, 2);
      expect(_text(verdict), contains('NOT CHECKED'));
    });

    test('a tag whose tree holds no pubspec compares nothing either', () {
      final verdict = judge(
        app: _pubspec('3.1.0+9'),
        core: _pubspec('3.1.0+9'),
        tags: const [PublishedTag('v-ancient', null)],
        changelog: _changelog(const []),
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
          PublishedTag('v3.0.0', _pubspec('3.0.0+8'),
              changelog: _changelog(const ['3.0.0'])),
        ],
        changelog: _changelog(const ['3.0.0']),
      );

      expect(verdict.outcome, Outcome.inStep);
      expect(_text(verdict), contains('not compared: v-ancient'));
    });
  });

  group('the heading a release is named by', () {
    test('an open section names no release, which is the whole point', () {
      expect(releasedHeadings('# Changelog\n\n## [Unreleased]\n\n- planted\n'),
          isEmpty);
    });

    test('a heading with a date names its release, and a bare one does', () {
      expect(releasedHeadings('## [1.2.3] - 2001-01-01\n'), {'1.2.3'});
      expect(releasedHeadings('## [1.2.3]\n'), {'1.2.3'});
      // The em dash this project's own file uses, not the hyphen above.
      expect(releasedHeadings('## [1.2.3] — 2001-01-01\n'), {'1.2.3'});
    });

    test('several headings are all named', () {
      expect(releasedHeadings(_changelog(const ['2.0.0', '1.0.0'])),
          {'2.0.0', '1.0.0'});
    });

    // Controls on the pattern itself: it must not answer for text that only
    // looks like a heading, or the quiet cases below would be quiet for the
    // wrong reason (doc/conventions.md 4a).
    test('what is not a release heading', () {
      expect(releasedHeadings('### [1.2.3]\n'), isEmpty,
          reason: 'a deeper heading is not a release heading');
      expect(releasedHeadings('##[1.2.3]\n'), isEmpty);
      expect(releasedHeadings('see [1.2.3] for the details\n'), isEmpty,
          reason: 'a bracketed version inside a paragraph names nothing');
      expect(releasedHeadings('## [Unreleased] - 2001-01-01\n'), isEmpty);
      expect(releasedHeadings('## [1.2]\n'), isEmpty);
    });

    test('the heading names the release, and BUILD is not part of it', () {
      expect(_release('0.2.0+2'), '0.2.0');
      expect(_release('0.2.0'), '0.2.0');
    });
  });

  group('the changelog half', () {
    // The state this check most had to get right. It is the state of this
    // repository between releases, and refusing it would be refusing Tuesday.
    test('a tree ahead of the last tag with no heading for itself is a NOTE '
        'and exits 0', () {
      final verdict = _judge(tree: '0.2.0+2', published: {'v0.1.0': '0.1.0'});

      expect(verdict.outcome, Outcome.inStep);
      expect(verdict.outcome.exitCode, 0);
      expect(_text(verdict), contains('CHANGELOG: NOTE'));
      expect(_text(verdict), contains('no "## [0.2.0]" heading'));
      expect(_text(verdict), contains('If you are cutting 0.2.0 now'));
      expect(_text(verdict), isNot(contains('CHANGELOG: REFUSED')));
    });

    test('...and the same tree once the heading is written says so', () {
      final verdict = _judge(
        tree: '0.2.0+2',
        published: {'v0.1.0': '0.1.0'},
        changelog: _changelog(const ['0.2.0', '0.1.0']),
      );

      expect(verdict.outcome, Outcome.inStep);
      expect(_text(verdict), contains('CHANGELOG: OK'));
      expect(_text(verdict), contains('the middle step of the release order '
          'is taken'));
    });

    // The case this task exists for: a release that went out describing
    // itself as unreleased.
    test('a tag whose own tree named no release for it is refused', () {
      final verdict = _judge(
        tree: '0.3.0+3',
        published: {'v0.1.0': '0.1.0', 'v0.2.0': '0.2.0+2'},
        withoutTheirHeading: const {'v0.2.0'},
      );

      expect(verdict.outcome, Outcome.refused);
      expect(verdict.outcome.exitCode, 1);
      expect(_text(verdict), contains('CHANGELOG: REFUSED'));
      expect(_text(verdict),
          contains('v0.2.0 published 0.2.0, and the CHANGELOG.md in that '
              'tag\'s tree carries no "## [0.2.0]" heading'));
    });

    // ...and it refuses even though the build number half is in step, which
    // is the only way the two questions can be told apart in one run.
    test('the changelog refusal stands on its own, against an OK version', () {
      final verdict = _judge(
        tree: '0.3.0+3',
        published: {'v0.2.0': '0.2.0+2'},
        withoutTheirHeading: const {'v0.2.0'},
      );

      expect(verdict.outcome, Outcome.refused);
      expect(_text(verdict), contains('RELEASE ORDER: OK'));
      expect(_text(verdict), contains('CHANGELOG: REFUSED'));
    });

    test('the tag that skipped it is named and the one that did not is not',
        () {
      final verdict = _judge(
        tree: '0.3.0+3',
        published: {'v0.1.0': '0.1.0', 'v0.2.0': '0.2.0+2'},
        withoutTheirHeading: const {'v0.1.0'},
      );

      expect(_text(verdict), contains('v0.1.0 published 0.1.0'));
      expect(_text(verdict), isNot(contains('v0.2.0 published 0.2.0, and')));
    });

    test('a tag whose tree carries no changelog is named, not refused', () {
      final verdict = judge(
        app: _pubspec('0.9.0+9'),
        core: _pubspec('0.9.0+9'),
        changelog: _changelog(const ['0.8.0']),
        tags: [PublishedTag('v0.8.0', _pubspec('0.8.0+8'))],
      );

      expect(verdict.outcome, Outcome.inStep);
      expect(verdict.outcome.exitCode, 0);
      expect(_text(verdict),
          contains('not compared: v0.8.0 -- its tree carries no CHANGELOG.md'));
      expect(_text(verdict), isNot(contains('CHANGELOG: REFUSED')));
    });

    // Exit 2 for the same reason a missing pubspec is exit 2: a question
    // nobody could ask must not read as green.
    test('no changelog here at all compares nothing, and is not green', () {
      final verdict = _judge(
        tree: '0.2.0+2',
        published: {'v0.1.0': '0.1.0'},
        noChangelogHere: true,
      );

      expect(verdict.outcome, Outcome.nothingCompared);
      expect(verdict.outcome.exitCode, 2);
      expect(_text(verdict), contains('CHANGELOG: NOT CHECKED'));
      expect(_text(verdict), contains('That is not green.'));
    });

    test('a broken rule outranks an unasked question', () {
      final verdict = _judge(
        tree: '0.3.0+3',
        published: {'v0.2.0': '0.2.0+2'},
        withoutTheirHeading: const {'v0.2.0'},
        noChangelogHere: true,
      );

      expect(verdict.outcome, Outcome.refused);
      expect(_text(verdict), contains('CHANGELOG: REFUSED'));
    });

    test('a repository with no tags is asked the changelog question too', () {
      final verdict = _judge(tree: '0.2.0+2', published: const {});

      expect(verdict.outcome, Outcome.nothingPublished);
      expect(verdict.outcome.exitCode, 0);
      expect(_text(verdict), contains('no previous tag'));
      expect(_text(verdict), contains('CHANGELOG: NOTE'));
    });

    // The five refusals above the changelog say the tree is in no state to
    // cut a release at all, so the changelog answer does not join them.
    test('a tree with no build number is refused without a changelog word',
        () {
      final verdict = _judge(
        tree: '0.3.0',
        published: {'v0.2.0': '0.2.0+2'},
        withoutTheirHeading: const {'v0.2.0'},
      );

      expect(verdict.outcome, Outcome.refused);
      expect(_text(verdict), contains('the tree declares no build number'));
      expect(_text(verdict), isNot(contains('CHANGELOG:')));
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

    // The changelog half over real git: proves `git show <tag>:CHANGELOG.md`
    // reads what it is believed to read, which no pure case can.
    test('it refuses a tag whose own tree named no release for it', () {
      _plant(root,
          tree: '0.9.0+2',
          tags: {'v0.8.0': '0.8.0'},
          withoutTheirHeading: const {'v0.8.0'});

      final run = _run(root);

      expect(run.exitCode, 1, reason: run.out);
      expect(run.out, contains('CHANGELOG: REFUSED'));
      expect(run.out, contains('v0.8.0 published 0.8.0'));
      expect(run.out, contains('no "## [0.8.0]" heading'));
    });

    // The other direction, and it is the control on the case above: with the
    // heading present the same repository exits clean, so the refusal is the
    // missing heading rather than the read failing.
    test('a tree ahead of the tag with an open section exits clean', () {
      _plant(root, tree: '0.9.0+2', tags: {'v0.8.0': '0.8.0'});

      final run = _run(root);

      expect(run.exitCode, 0, reason: run.out);
      expect(run.out, contains('CHANGELOG: NOTE'));
      expect(run.out, contains('no "## [0.9.0]" heading'));
      expect(run.out, isNot(contains('not compared')),
          reason: 'the tag TREE\'s changelog was read, so it is compared '
              'rather than skipped');
      expect(run.out, isNot(contains('REFUSED')));
    });

    test('...and once the heading is written it says the step is taken', () {
      _plant(root,
          tree: '0.9.0+2',
          tags: {'v0.8.0': '0.8.0'},
          changelogNamesTree: true);

      final run = _run(root);

      expect(run.exitCode, 0, reason: run.out);
      expect(run.out, contains('CHANGELOG: OK'));
      expect(run.out, contains('carries "## [0.9.0]"'));
    });
  });
}

/// [published] is tag name to the version that tag's tree declares. By
/// default each of those trees also carries a changelog naming its own
/// release, which is the release order taken correctly; [withoutTheirHeading]
/// names the tags whose trees do not. [changelog] overrides what this tree
/// carries, whose default names every published release and nothing for
/// [tree] -- the ordinary state of a repository between releases.
Verdict _judge({
  required String tree,
  required Map<String, String> published,
  String? changelog,
  Set<String> withoutTheirHeading = const {},
  bool noChangelogHere = false,
}) =>
    judge(
      app: _pubspec(tree),
      core: _pubspec(tree),
      changelog: noChangelogHere
          ? null
          : changelog ??
              _changelog([for (final v in published.values) _release(v)]),
      tags: [
        for (final entry in published.entries)
          PublishedTag(
            entry.key,
            _pubspec(entry.value),
            changelog: _changelog(withoutTheirHeading.contains(entry.key)
                ? const []
                : [_release(entry.value)]),
          ),
      ],
    );

String _pubspec(String version) => 'name: planted\n'
    'version: $version\n'
    'environment:\n'
    '  sdk: ^3.4.0\n';

/// The release a version names, through the function under test rather than
/// by splitting the string again here.
String _release(String version) => releaseOf(parseVersion(version)!);

/// A Keep a Changelog file naming [released], under an open `[Unreleased]`
/// section -- the shape this project's own file has.
String _changelog(Iterable<String> released) => [
      '# Changelog',
      '',
      '## [Unreleased]',
      '',
      '- planted',
      '',
      for (final version in released) ...[
        '## [$version] - 2001-01-01',
        '',
        '- planted',
        '',
      ],
    ].join('\n');

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
///
/// Each tagged commit also carries a changelog naming every release up to and
/// including its own, which is the release order taken correctly;
/// [withoutTheirHeading] names the tags whose commits leave their own release
/// out. The working tree's changelog names what was released and, unless
/// [changelogNamesTree], nothing for [tree].
void _plant(
  Directory root, {
  required String tree,
  required Map<String, String> tags,
  String? core,
  Set<String> withoutTheirHeading = const {},
  bool changelogNamesTree = false,
}) {
  final tool = File('${root.path}/tool/check-release-order.dart');
  tool.parent.createSync(recursive: true);
  File('${_repoRoot.path}/tool/check-release-order.dart').copySync(tool.path);

  _git(root, const ['init', '-b', 'main']);
  final released = <String>[];
  tags.forEach((tag, version) {
    _write(
      root,
      appVersion: version,
      coreVersion: version,
      changelog: _changelog([
        if (!withoutTheirHeading.contains(tag)) _release(version),
        ...released,
      ]),
    );
    _git(root, const ['add', '-A']);
    _git(root, ['commit', '-m', 'planted $tag']);
    _git(root, ['tag', tag]);
    released.insert(0, _release(version));
  });
  _write(
    root,
    appVersion: tree,
    coreVersion: core ?? tree,
    changelog: _changelog([
      if (changelogNamesTree) _release(tree),
      ...released,
    ]),
  );
}

void _write(
  Directory root, {
  required String appVersion,
  required String coreVersion,
  required String changelog,
}) {
  for (final pair in [
    (appPubspec, appVersion),
    (corePubspec, coreVersion),
  ]) {
    final file = File('${root.path}/${pair.$1}');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(_pubspec(pair.$2));
  }
  File('${root.path}/$changelogFile').writeAsStringSync(changelog);
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
