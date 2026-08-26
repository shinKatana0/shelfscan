// Answer one question before a release is cut: is the build number in this
// tree greater than every build number already published under a tag?
//
// Why this is a script and not a test (T-0402). `app/test/app_version_test
// .dart` asserts that both pubspecs agree and that a build number is
// PRESENT, which is everything the working tree can say about itself. It
// cannot say whether that number has been handed over before, because a suite
// cannot see history -- so it is exactly as green on a second artefact built
// at `+2` as on the first, and decision 0014's "never reused" is left
// enforced by remembering. Reading the previous tag is what closes that, and
// only something outside the suite can do it.
//
// What it reads:
//
//   app/pubspec.yaml                      the version this tree would ship
//   packages/shelfscan_core/pubspec.yaml  which must agree with it
//   <tag>:app/pubspec.yaml                out of each tag's TREE
//
// Out of the tree and never out of the tag name. The only tag this project
// has is `v0.1.0`, which carries no build number at all, so the name cannot
// answer this question even in principle.
//
// **A tagged tree that declares no `+N` published build number 1** -- not 0
// and not none. Flutter substitutes 1 for an absent `+BUILD`, and decision
// 0014's measurement on the signed artefact is `versionCode='1'`. That
// substitution is the whole defect the amendment exists for, so a check that
// read the absent field as 0 would wave through a `+1` that Android cannot
// tell apart from what already shipped.
//
// **Every tag, not just the most recent one.** "Never reused" is a claim
// about everything ever published, not about the last thing published, and
// this repository has already carried two root commits with a tag pointing
// into the orphaned one (doc/conventions.md 6a). Where the two readings agree
// -- which is every case with one tag, including today's -- they are the same
// answer; where they differ, the stricter one is the rule decision 0014
// actually states.
//
// **What it cannot see, and this is a hole rather than a caveat:** an
// artefact handed to someone without a tag being cut. Nothing in git records
// that. This enforces the rule against what was published; cutting the tag is
// still an act a person has to remember.
//
// usage: dart run tool/check-release-order.dart
//
// exit: 0 in step, or nothing published yet | 1 refused | 2 nothing compared
//
// The two clean exits are different answers and each says which it is. A
// clone fetched with `--no-tags` has published nothing, so no build number
// can have been reused and the question is answered -- vacuously, but
// answered; a check that failed there is a check people delete. A checkout
// where git cannot be reached at all answers nothing, and exits 2 rather than
// green (doc/conventions.md 4a).

import 'dart:io';

/// What Flutter writes into `versionCode` when the version carries no `+N`,
/// measured on the signed artefact in decision 0014: `versionCode='1'`.
const flutterDefaultBuild = 1;

const appPubspec = 'app/pubspec.yaml';
const corePubspec = 'packages/shelfscan_core/pubspec.yaml';

/// The top-level `version:` key, anchored per line so it cannot match a
/// constraint indented under `dependencies:`. The same pattern judges the same
/// field in `app/test/app_version_test.dart`.
final _versionKey = RegExp(r'^version:[ \t]*(\S+)[ \t]*$', multiLine: true);

/// `+BUILD` is optional here and required there, deliberately: a tag cut
/// before the 2026-08-25 amendment legitimately carries none, and reading
/// what it published is the point of this script.
final _version = RegExp(r'^(\d+)\.(\d+)\.(\d+)(?:\+(\d+))?$');

/// A version as one `pubspec.yaml` declares it.
class Declared {
  const Declared(this.text, {required this.build});

  final String text;

  /// Null where the declaration carries no `+N`.
  final int? build;

  /// What an Android package built from this declaration carries.
  int get versionCode => build ?? flutterDefaultBuild;
}

/// A tag, and the `app/pubspec.yaml` its tree carries. Null where that tag has
/// no such file, which an old enough tag legitimately does not.
class PublishedTag {
  const PublishedTag(this.tag, this.pubspec);

  final String tag;
  final String? pubspec;
}

enum Outcome {
  inStep(0),
  nothingPublished(0),
  refused(1),
  nothingCompared(2);

  const Outcome(this.exitCode);

  final int exitCode;
}

class Verdict {
  const Verdict(this.outcome, this.lines);

  final Outcome outcome;
  final List<String> lines;
}

/// The top-level version of a pubspec's text, or null when there is none.
String? readVersionKey(String? pubspec) =>
    pubspec == null ? null : _versionKey.firstMatch(pubspec)?[1];

/// The declared version, or null when the text is not one.
Declared? parseVersion(String? text) {
  if (text == null) return null;
  final trimmed = text.trim();
  final match = _version.firstMatch(trimmed);
  if (match == null) return null;
  final build = match[4];
  return Declared(trimmed, build: build == null ? null : int.parse(build));
}

/// The whole comparison, over text rather than over a repository, so that
/// every case below can be exercised without making a tag.
Verdict judge({
  required String? app,
  required String? core,
  required List<PublishedTag> tags,
}) {
  if (app == null || core == null) {
    return const Verdict(Outcome.nothingCompared, [
      'RELEASE ORDER: NOT CHECKED -- a pubspec is missing.',
      'Expected $appPubspec and $corePubspec. Run this from a checkout of '
          'this repository.',
    ]);
  }

  final appText = readVersionKey(app);
  final coreText = readVersionKey(core);
  if (appText == null || coreText == null) {
    return Verdict(Outcome.refused, [
      'RELEASE ORDER: REFUSED -- '
          '${appText == null ? appPubspec : corePubspec} declares no '
          'top-level version.',
    ]);
  }
  if (appText != coreText) {
    return Verdict(Outcome.refused, [
      'RELEASE ORDER: REFUSED -- the two pubspecs disagree.',
      '  $appPubspec declares $appText',
      '  $corePubspec declares $coreText',
      'decision 0014: they move in lockstep, so that a bug report naming a '
          'version is unambiguous about which half it came from.',
    ]);
  }

  final tree = parseVersion(appText);
  if (tree == null) {
    return Verdict(Outcome.refused, [
      'RELEASE ORDER: REFUSED -- "$appText" is not MAJOR.MINOR.PATCH+BUILD.',
    ]);
  }
  if (tree.build == null) {
    return Verdict(Outcome.refused, [
      'RELEASE ORDER: REFUSED -- the tree declares no build number.',
      '  $appPubspec declares $appText',
      'Flutter substitutes $flutterDefaultBuild for an absent +BUILD and '
          'warns nobody, so the package would go out declaring '
          'versionCode=$flutterDefaultBuild like every one before it '
          '(decision 0014).',
    ]);
  }

  if (tags.isEmpty) {
    return Verdict(Outcome.nothingPublished, [
      'RELEASE ORDER: NOTHING TO COMPARE -- no previous tag.',
      '  this tree declares $appText -> versionCode ${tree.versionCode}',
      'Nothing has been published under a tag here, so no build number can '
          'have been reused. A clone fetched with --no-tags looks exactly '
          'like this, and that is not a failure.',
    ]);
  }

  final readable = <String, Declared>{};
  final unreadable = <String>[];
  for (final tag in tags) {
    final version = parseVersion(readVersionKey(tag.pubspec));
    if (version == null) {
      unreadable.add(tag.tag);
    } else {
      readable[tag.tag] = version;
    }
  }
  if (readable.isEmpty) {
    return Verdict(Outcome.nothingCompared, [
      'RELEASE ORDER: NOT CHECKED -- no tag declares a readable version.',
      '  tags seen: ${unreadable.join(', ')}',
      'None of them carries a readable $appPubspec, so nothing was compared. '
          'That is not green.',
    ]);
  }

  var highest = readable.entries.first;
  for (final entry in readable.entries) {
    if (entry.value.versionCode > highest.value.versionCode) highest = entry;
  }
  final published = highest.value.versionCode;

  final detail = <String>[
    '  this tree declares ${tree.text} -> versionCode ${tree.versionCode}',
    for (final entry in readable.entries)
      '  ${entry.key} published ${entry.value.text} -> versionCode '
          '${entry.value.versionCode}'
          '${entry.value.build == null ? '  (no +N, so Flutter substituted '
              'it)' : ''}',
    if (unreadable.isNotEmpty)
      '  not compared: ${unreadable.join(', ')} -- no readable $appPubspec',
  ];

  if (tree.build! > published) {
    return Verdict(Outcome.inStep, [
      'RELEASE ORDER: OK -- the tree is ahead of everything published.',
      ...detail,
    ]);
  }

  final collision = [
    for (final entry in readable.entries)
      if (entry.value.versionCode == tree.build) entry.key,
  ];
  return Verdict(Outcome.refused, [
    collision.isNotEmpty
        ? 'RELEASE ORDER: REFUSED -- build number ${tree.build} was already '
            'published by ${collision.join(', ')}.'
        : 'RELEASE ORDER: REFUSED -- build number ${tree.build} is behind '
            '$published, published by ${highest.key}.',
    ...detail,
    'decision 0014: BUILD is incremented for every artefact handed to '
        'anyone, never reset and never reused. Android decides what is an '
        'update by that integer alone, so two packages sharing one are '
        'indistinguishable to it. Raise it above $published in both pubspecs '
        'and in app/lib/app_version.dart, then re-run.',
  ]);
}

void main(List<String> args) {
  if (args.contains('-h') || args.contains('--help')) {
    stdout.write(_usage);
    exit(0);
  }

  final root = _repositoryRoot();
  final tags = _publishedTags(root);
  if (tags == null) {
    stderr.writeln('RELEASE ORDER: NOT CHECKED -- git could not be run here.');
    stderr.writeln('`git tag -l` did not answer, so nothing was compared. '
        'That is not green.');
    exit(Outcome.nothingCompared.exitCode);
  }

  final verdict = judge(
    app: _read('$root/$appPubspec'),
    core: _read('$root/$corePubspec'),
    tags: tags,
  );
  final out = verdict.outcome == Outcome.inStep ||
          verdict.outcome == Outcome.nothingPublished
      ? stdout
      : stderr;
  for (final line in verdict.lines) {
    out.writeln(line);
  }
  exit(verdict.outcome.exitCode);
}

const _usage = '''
usage: dart run tool/check-release-order.dart

Reads the build number this tree declares and the one every tag published,
out of each tag's tree rather than out of its name.

exit: 0 in step, or nothing published yet | 1 refused | 2 nothing compared

Read the exit code as well as the line: they are written by different halves
of this script and only agree when both are right.
''';

/// Every tag, with the `app/pubspec.yaml` its tree carries. Null when git
/// itself did not answer, which is not the same as there being no tags.
List<PublishedTag>? _publishedTags(String root) {
  final listed = _git(root, const ['tag', '-l']);
  if (listed == null) return null;
  final names = [
    for (final line in listed.split('\n'))
      if (line.trim().isNotEmpty) line.trim(),
  ]..sort();
  return [
    for (final tag in names)
      PublishedTag(tag, _git(root, ['show', '$tag:$appPubspec'])),
  ];
}

/// stdout of a git command, or null when it did not succeed. A tag whose tree
/// holds no `app/pubspec.yaml` fails here and is reported as not compared,
/// which is why a non-zero exit is data rather than an error.
String? _git(String root, List<String> args) {
  try {
    final run = Process.runSync('git', args, workingDirectory: root);
    return run.exitCode == 0 ? run.stdout as String : null;
  } on ProcessException {
    return null;
  }
}

String? _read(String path) {
  final file = File(path);
  return file.existsSync() ? file.readAsStringSync() : null;
}

String _repositoryRoot() {
  final dir = File(Platform.script.toFilePath()).parent.parent;
  return dir.path.replaceAll(r'\', '/');
}
