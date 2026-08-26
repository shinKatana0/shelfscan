# Contributing

Thanks for looking. This is a small, opinionated project: a companion
utility that turns shelf photos into an importable collection file. Read
[`README.md`](README.md) for what it is and what it deliberately will not do,
[`doc/decisions/`](doc/decisions/) for what is already decided and the
measurement behind each, and [`ARCHITECTURE.md`](ARCHITECTURE.md) for the
pipeline and the platform boundary.

## Running the suites

Two packages, two suites. Neither needs a network, an API key, or anything
outside the repository.

```
cd packages/shelfscan_core && dart pub get && dart analyze && dart test
cd app                     && flutter pub get && flutter analyze && flutter test
```

`shelfscan_core` is pure Dart — do not add a Flutter dependency to it, and
keep its runtime dependencies at `http` alone. CI runs these same four
commands as two jobs, each `test` with `--reporter expanded` so a failing
test is named in the log.

**Do not run the app suite while an Android release build is running in the
same checkout.** `flutter analyze`, `flutter test` and `flutter pub get` each
rewrite `GeneratedPluginRegistrant.java` within seconds of starting, and they
write the version the release build must not compile: the build fails on a dev
dependency, naming a generated file, and looks like a defect in the tree. The
measurement and the recovery are in
[`doc/android-build.md`](doc/android-build.md), trap 5. Nothing here builds for
Android, so the two are only ever concurrent by choice.

Before publishing anything, run both suites through `tool/check-suites.sh`
instead. Neither runner can be trusted to say what happened to itself: when a
suite file's test host process dies, every test in that file — including tests
that never started — is reported `did not complete` with no cause attached, and
a test that hangs rather than dies produces no timeout and no further output at
all. The script bounds each run in wall clock, kills the process tree if the
bound trips, and then reads its own log: any file named `did not complete` is
re-run on its own, because a file whose host died comes back green and a real
defect does not.

## Formatting — do not run `dart format`

This tree is **not formatter-managed**. Every line in it was wrapped by hand,
no formatter produced it, and no combination of formatter settings reproduces
it. On the toolchain this is developed against, a bare `dart format` over the
two packages rewrites **136 files**. On a fresh clone it is worse and it is the
same command: before `pub get` the formatter cannot read the package's language
version, falls back to a newer default style, and rewrites more still.

So, before your first edit, **turn format-on-save off for Dart** — in VS Code
that is `editor.formatOnSave` under `[dart]`, in IntelliJ and Android Studio
the "Reformat code" save action. It is the setting that runs the command for
you without asking, and it is the likeliest way this happens to somebody.

In VS Code this workspace already sets that key for you, in
`.vscode/settings.json`, for Dart and for this folder only. Take it as one
fewer thing to remember rather than as a guarantee: no other editor reads that
file, and the sentence above is still the rule.

That belongs beside the four commands above rather than in passing, because
none of them will tell you it happened. `dart analyze` and `flutter analyze` do
not judge formatting, `tool/check-suites.sh` runs the two suites and no format
check, and there is deliberately no format check anywhere. Nor does a
reformatted tree simply pass: one test asserts against the source text of
`app/lib` and fails when a line break moves there, with a message about the
code rather than about the formatting. Your own change is a rounding error
inside a diff that size, and the rest of it is invisible unless you read
`git status` file by file.

**When an edit pushes a line past 80 columns, wrap it by hand** the way the
lines around it are already wrapped, and change nothing else on the screen.
That is the whole of the rule. 80 is the preference here and not a gate —
several hundred lines in the tree are already over it — so a line you cannot
wrap without making it harder to read stays long. `dart format -o show` on the
one file you touched is not a way around this either: it reformats the whole
file, not your line.

## Building the app

Neither platform builds on a `flutter doctor` that prints green, and the
prerequisites each one is missing are written down rather than left to be
rediscovered:

- **Windows** — two things `flutter doctor` does not check at all:
  [`README.md`](README.md), *Setup → The app*.
- **Android** — the toolchain, and five failures: three that name something
  other than the missing step, one that does not fail the build at all and
  is invisible to every debug build, and one you cause by running the suites
  beside the build.
  [`doc/android-build.md`](doc/android-build.md). **Android Studio is not
  required**; the command-line SDK is enough, and that page is the shortest
  route from a bare Windows machine to an apk.

Neither is needed to run the suites, review a change, or work on
`shelfscan_core`.

## Cutting a release

Deciding the version and cutting the tag are a person's acts, and this
project means that. Nothing below fires on its own: CI runs the two suites on
a push to `main` and on a pull request, never on a tag, and git offers no hook
that fires when a tag is cut without also firing on ordinary work. What
follows is the order from
[`doc/decisions/0014`](doc/decisions/0014-stay-in-0-x-until-the-two-file-formats-stop-moving.md),
with the command that checks each step and what its answers mean.

The order is **both `pubspec.yaml` files, then `CHANGELOG.md`, then the tag.**

**1 — the version.** Pick it against decision 0014's definitions of MAJOR,
MINOR, PATCH and BUILD; the gate keeping this project in `0.x` is there too.
BUILD is a monotonic integer, incremented for every artefact handed to
anyone, never reset and never reused. There is no check for the choice
itself, and there should not be.

Write it into three places — `app/pubspec.yaml`,
`packages/shelfscan_core/pubspec.yaml` and `app/lib/app_version.dart` — as
`MAJOR.MINOR.PATCH+BUILD`. `app/test/app_version_test.dart` holds all three
to each other and requires the `+BUILD` half to be present, so this is the
one step you cannot forget: it runs in the app suite whether or not you think
about it. Its limit is that a suite sees only the working tree. It is exactly
as green on a second artefact built at `+2` as on the first.

**2 — the changelog.** Give the release its own `## [VERSION]` heading in
`CHANGELOG.md`, above the entries it covers.

**3 — the checks, before the tag exists.**

```
dart run tool/check-release-order.dart ; echo "EXIT=$?"
```

It answers in two voices, one per question. The changelog voice joins the run
only once the tree's version is known: an answer that comes before that says
the tree is in no state to cut a release at all, and each of those fixes is
upstream of the changelog. So one voice and a non-zero exit is a complete
answer rather than a truncated one.

The release order:

- `RELEASE ORDER: OK` — this tree's build number is ahead of every number any
  tag ever published.
- `RELEASE ORDER: REFUSED` (exit 1) — the two pubspecs disagree, or the tree
  declares no build number, or the number it declares has been published
  before. The message names which.
- `RELEASE ORDER: NOTHING TO COMPARE` (exit 0) — no tag here, so nothing can
  have been reused. A clone fetched with `--no-tags` looks exactly like this
  and it is not a failure.
- `RELEASE ORDER: NOT CHECKED` (exit 2) — a pubspec was missing, no tag
  carried a readable one, or `git` could not be run. Nothing was compared,
  which is not the same as nothing being wrong.

The changelog step, and this is the answer to read carefully:

- `CHANGELOG: OK` — the file carries `## [VERSION]` for the version this tree
  declares. Step 2 is done.
- `CHANGELOG: NOTE` — it does not, **and the exit code is still 0.** That is
  deliberate and it is the one place this check will not decide for you. A
  tree ahead of the last tag with an open `[Unreleased]` section is this
  repository on an ordinary day, and it is the *same git state* as the minute
  before a release is cut — the tag does not exist yet in either. Nothing in
  the repository can tell them apart, so nothing here refuses on it; a check
  that refused on a Tuesday is a check people stop running. **So when you are
  cutting a release, read the word and not the exit code.** `NOTE` at that
  moment means step 2 is owed.
- `CHANGELOG: REFUSED` (exit 1) — some tag published a tree whose own
  `CHANGELOG.md` named no release for it. If that tag is still local, write
  the heading and re-cut it. If it is pushed, this is a report and not a
  remedy: fixing the tree does not fix what went out.
- `CHANGELOG: NOT CHECKED` (exit 2) — there is no `CHANGELOG.md` here.

**Run it before you cut the tag, and understand why it cannot be run after.**
The comparison is against everything already published, and once the tag
exists this tree *is* something already published. Measured on a synthetic
repository declaring `1.0.0+7`: it passes at exit 0 one second before
`git tag`, and one second after — with nothing else changed — answers
`REFUSED — build number 7 was already published by v1.0.0`. That is the check
working correctly, and it is why the trigger is a person following this page
rather than a hook. It is also why the tag is last.

**4 — the artefacts.** Build what you are shipping (*Building the app*,
above), then:

```
dart run tool/check-bundle-assets.dart ; echo "EXIT=$?"
```

It asserts that every asset key `AssetManifest.bin` names is a file inside
the bundle carrying it — the failure it exists for is a key beginning `../`,
which is written outside the bundle and reaches no packaged app. Exit 0 every
key present, 1 a key has no file or the bundle predates the declaration it is
judged against, 2 nothing was checked.

**Read the bundles it names, not only the last line.** With no argument it
checks every known build output under `app/build/` that exists, and a
checkout where only the suites have been run has exactly one: the unit-test
bundle, which is the single bundle that *cannot* answer this question — a
`../` key resolved from there lands somewhere that exists, so it passes.
That run prints `1 bundle(s)`, `OK`, exit 0, and proves nothing about what
you are about to ship. Check the runner directory or the `.apk` you built is
in the list. The output carries absolute paths of the machine that ran it, so
it is a scratch reading rather than something to paste anywhere.

**5 — both suites, through the script.** `sh tool/check-suites.sh` rather
than the runners directly, for the reason in *Running the suites* above:
neither runner can be trusted to say what happened to itself.

**6 — cut the tag.** A person's act, and the only step of the release order
git records.

## What a change must not break

- **The platform boundary.** Photos travel as bytes (`PhotoInput`), never
  as file paths; exporters return strings and never touch the filesystem.
  This is what lets the same pipeline run in the CLI and on Android.
- **`.xcoll` is an external contract**, pinned at `version: 2`. An upstream
  format change gets a new writer, never a mutation of the existing one.
- **Nothing the pipeline drops may be dropped silently.** A skipped photo,
  an unreadable spine, an unresolved title — each is named to the user.
  This is the project's most-repeated defect class.
- **No external endpoint is ever a default**, and choosing one must warn at
  the point of selection. The uploads are photographs of someone's home.

## The measured artifacts — read this before editing them

Two things in this repository are **measurements, not text**, and a casual
edit invalidates them without failing anything you would notice:

- **`detectionPromptRules` and `detectionJsonSchema`** in
  `packages/shelfscan_core/lib/src/providers/vision.dart`. Their doc
  comments carry the numbers behind every word. Moving one bullet has
  changed unrelated fields; removing a field that is answered empty on
  every row has resurrected fabricated output. Do not edit either by taste,
  and do not delete part of them because it looks unused.
- **The control-set fingerprint.** `test/control_set_test.dart` pins a hash of
  the assembled prompt, recorded in
  [`doc/control-set-manifest.md`](doc/control-set-manifest.md), so any edit to
  the above fails `dart test` everywhere — no photographs, no model, no
  network. That failure is the feature: **re-measure and move the figures,
  never move the hash.** The figures themselves are not in this repository —
  a detection count and a platform split describe a private collection, so
  they live in the working record beside the photographs, and the hash is the
  half that can be published. Re-measuring means
  scanning both control resolutions, high and low; a prompt measured at the
  high one alone is half-measured, and that is how a regression at the low one
  once survived four prompt edits. The control photographs are of a private
  home and are not published, so **re-measuring is the one thing a fork cannot
  do** — say so in the pull request instead of adjusting the hash. The check
  itself runs in your clone, and is meant to.

New measurements go in `doc/measurements.md`, first time, not into a
summary somewhere else.

## Comments and docs

English only. **Comments are for measurements and non-obvious decisions
only** — a number from a real run, or a choice a reader could not infer
from the code. Never restate the code in prose. When you touch a file for
any reason, trim the comments already in it.

## How this repository is developed

Most of what is here was written by an orchestrator/worker agent workflow
against a task board. That board, its briefs and its worker reports stay on a
private disk and are not published: they are development artefacts rather than
product, and they quote conversations verbatim. **Nothing you need is in them.**
What they produced is published — [`doc/decisions/`](doc/decisions/) for the
reasoning, [`doc/measurements.md`](doc/measurements.md) for the figures,
[`ARCHITECTURE.md`](ARCHITECTURE.md) for the shape, and this page for the
rules a change is held to.

## Pull requests

Say what you measured, not only what you changed. A behaviour claim in this
project is expected to name the run it came from.
