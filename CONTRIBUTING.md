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

- **Windows** — two things `flutter doctor` does not check at all, and the
  cache that breaks every later build if you clear `app\build\` by hand:
  below on this page.
- **Android** — the toolchain, and five failures: three that name something
  other than the missing step, one that does not fail the build at all and
  is invisible to every debug build, and one you cause by running the suites
  beside the build.
  [`doc/android-build.md`](doc/android-build.md). **Android Studio is not
  required**; the command-line SDK is enough, and that page is the shortest
  route from a bare Windows machine to an apk.

Neither is needed to run the suites, review a change, or work on
`shelfscan_core`.

**The platform folders are committed.** `flutter create` scaffolded
`app/windows/` and `app/android/` once; ever since they have been hand-edited
source carrying the release identity — `Runner.rc`, the `AndroidManifest.xml`,
the `applicationId`, the icons — and they are reviewed like any other file.
What is genuinely generated inside one is ignored by the `.gitignore` that
`flutter create` writes into that folder, and build output is a different path
again. The [`.gitignore`](.gitignore) comment at the entry says the same at
more length.

**Do not run `flutter create` over this checkout.** It regenerates those
folders and hands back `com.example` in place of the identity above, and on
Android it also drops the `INTERNET` permission that a release build has no
other way to get — a loss no build fails on and no debug build reproduces. If
you have already run it, `git status` names every file it touched and
`git checkout --` on those files puts them back.

`flutter create` also writes two files from the default counter template that
are not part of this project and are not tracked here: `app/README.md` and
`app/test/widget_test.dart`. Delete both. The test pumps a `MyApp` that does
not exist here (this app is `ShelfscanApp`), so leaving it in place makes
`flutter test` fail on a file nobody wrote:

```
test/widget_test.dart:16:35: Error: Couldn't find constructor 'MyApp'.
```

Neither is gitignored, deliberately: being untracked and unignored is what
makes `git status` name them, and that is the only warning you get that the
command ran at all.

### Windows: two prerequisites `flutter doctor` will not tell you about

**A green `flutter doctor` does not mean the Windows build will work.** Its
Visual Studio check looks for the `Desktop development with C++` workload
plus exactly two components (`VC.Tools.x86.x64` and `VC.CMake.Project`),
and it has no Windows Developer Mode check at all — so it prints
`[✓] Visual Studio - develop Windows apps` while both of the things below
are missing. The first build of this app hit them in this order.

**1. Turn on Windows Developer Mode.** Without it `flutter create` and
every build that has plugins abort with:

```
Building with plugins requires symlink support.

Please enable Developer Mode in your system settings. Run
  start ms-settings:developers
to open settings.
```

Flutter links plugin sources into the build with symlinks, and Windows
allows only administrators to create symlinks until Developer Mode is on.
Run that `start ms-settings:developers` command and flip the switch. It is
off on a fresh machine: the registry value it writes,
`HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock\AllowDevelopmentWithoutDevLicense`,
does not exist at all until Developer Mode is enabled the first time, and
reads `1` afterwards.

**2. Add the C++ ATL component to Visual Studio.** The
`Desktop development with C++` workload does not include ATL — it is a
separate entry under *Individual components*. Without it the build runs the
whole toolchain and then dies on a single plugin:

```
flutter_secure_storage_windows_plugin.cpp(6): fatal error C1083: Cannot open include file: 'atlstr.h': No such file or directory
```

Visual Studio Installer → Modify → **Individual components** → search
`ATL` → tick **C++ ATL for x64/x86 (Latest MSVC)**. That is the name in
Build Tools 2026; the wording tracks the toolset, so VS 2022 lists the same
thing as `C++ ATL for latest v143 build tools (x86 & x64)`. The name is
also translated in a localized installer, so the handle that always works
is the component id `Microsoft.VisualStudio.Component.VC.ATL`.

The compiler's error text is localized the same way: on a Russian install
that C1083 line reads `Не удается открыть файл включение: atlstr.h`. The
tokens that survive translation are `C1083` and `atlstr.h` — search your
console output for those, not for the English sentence.

The ATL dependency is ours rather than Flutter's: `flutter_secure_storage`,
which keeps the BYOK credentials in the OS keychain, is the only thing in
this project that includes `<atlstr.h>`.

### What the first successful build looks like

Measured on Flutter 3.47.0 stable, Visual Studio Build Tools 2026
18.9.12105.275 with MSVC 14.51.36231, Windows 11 25H2:

| Command | Cold build | Produces |
|---|---|---|
| `flutter build windows --debug` — what `flutter run -d windows` compiles | 124 s | `app\build\windows\x64\runner\Debug\shelfscan_app.exe` |
| `flutter build windows` | 164 s | `app\build\windows\x64\runner\Release\shelfscan_app.exe` |

Cold means nothing cached — no `build\`, no `.dart_tool\`. Expect a couple of
minutes and do not assume it has hung.

The release exe is only 90 KB and does not run alone: `flutter_windows.dll`,
`data\`, and one DLL per plugin sit beside it. Distribute the folder.

### Do not delete `app\build\` by hand — use `flutter clean`

Clearing the build output by hand while leaving `app\.dart_tool\` in place is
the obvious reflex and it breaks every later build, debug and release alike.
The build compiles everything successfully and then dies at the INSTALL
project:

```
error MSB3073: "...\cmake.exe" -DBUILD_TYPE=Debug -P cmake_install.cmake [...\app\build\windows\x64\INSTALL.vcxproj]
```

Nothing in that names the cause. It is visible only by running that same
cmake line by hand from `app\build\windows\x64`:

```
CMake Error at cmake_install.cmake:231 (file):
  file INSTALL cannot find
  ".../app/build/native_assets/windows": No error.
```

**The cause: the incremental cache in `.dart_tool\flutter_build` outlived the
directory it describes in `build\`.** The `install_code_assets` stamp there
still validates, so the step that creates `build\native_assets\windows` is
skipped, while CMake's install step still requires that directory to exist.
`flutter pub get` does not clear the stamp and does not help.

The fix:

```
cd app
flutter clean
flutter pub get
flutter build windows --debug
```

`flutter clean` removes `build\` and `.dart_tool\` together, which is why it
works where deleting `build\` alone does not.

This is **not** a fresh-clone problem — a genuinely cold tree builds fine (the
table above), so there is no reason to run `flutter clean` after cloning.

As with the ATL error above, the MSBuild wrapper text is localized; the tokens
that survive translation are `MSB3073`, `cmake_install.cmake`,
`INSTALL.vcxproj` and `native_assets`.

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

Almost every line here was written by an orchestrator/worker agent workflow
powered by [briefboard](https://github.com/shinKatana0/briefboard) — a task
board with a mandatory written brief before implementation and a review before
merge. Each task's brief, its worker's report and the board itself stay on a
private disk and **are not published** — they are development artefacts rather
than product, they quote conversations verbatim, and there are roughly 25,000 lines
of them against the ~2,100 lines of distilled record that replaced them here:
[ARCHITECTURE.md](ARCHITECTURE.md) for how it is put together,
[doc/decisions/](doc/decisions/) for why, and
[doc/measurements.md](doc/measurements.md) for what that rests on.

**So a task id is not a link.** Pages here cite ids like `T-0086` because an id
is a stable name for a decision, and a claim that names its origin can be
checked by whoever holds that record. Nothing published depends on looking one
up.

The board is not something a contributor installs, either. It is one person's
working tool; a pull request is reviewed as a pull request.

### Translations

Four files are translations: [`README.ru.md`](README.ru.md),
[`README.ja.md`](README.ja.md), [`doc/guide.ru.md`](doc/guide.ru.md) and
[`doc/guide.ja.md`](doc/guide.ja.md). **English is the source.** A translation
follows this file and `doc/guide.md`; it never leads them, and a claim that
exists in only one language is a bug in the translation.

A translation that has quietly fallen behind is worse than no translation at
all, because a reader trusts it and has no way to tell. So each translated file
carries one marker line at its top — inside an HTML comment in `README.ru.md`
and `README.ja.md`, visible in the two guides — in one fixed form:

```
TRANSLATED-FROM: README.md blob <40 hex characters> CURRENT
```

The 40 characters are **the name git gives that file's content**, not a commit.
The last word is the file's own claim about itself. One command prints what the
name is now:

```
git rev-parse HEAD:README.md
```

Equal to the marker means the English has not moved since this translation was
written. Different means it has, and `git diff <the name in the marker>
HEAD:README.md` shows what changed — a convenience rather than the verdict, and
the half that can stop working.

**Naming content instead of history is the whole of the scheme, and it was
paid for.** A commit hash is the obvious thing to record, was recorded here
until T-0406, and answers wrongly in two separate ways. Merge two branches that
each translated from the same base, and neither branch's hash has the other's
work in its ancestry: each marker then reports the other branch's commits as
English it has not caught up with. Rewrite the history — this repository has
done it twice — and every recorded hash names an object no clone holds, so the
check answers `fatal: bad revision` and cannot be run at all. A blob name
survives both, because neither a merge nor a rewrite changes what a file says.
Measured: `README.md` at one commit hashed to
`905149e2634f446c4821e92eb2893282c65e4f2c` before the identity rewrite of
2026-08-25 and to the same 40 characters after it, while the commit that named
it is no longer on `main` at all.

**Which direction it fails in.** Any edit to the English changes its blob name,
so a typo fix reports every translation behind. That is over-reporting, and it
is the safe direction: this marker can call a current translation stale, and it
cannot call a stale one current — nothing short of an exact revert of the
English brings a blob name back. What it gives up is the *list* of English
commits, which a rewrite had already taken away.

**Editing the English obliges one of two things in the same commit:** update
the translation, or set its marker's last word to `STALE`. Marking is the cheap
option and it is the right one when you do not read the language — nobody is
asked to fake a translation, only to stop the file claiming a currency it lost.
The blob name always says what the translation was made *from*: bump it when
you translate, leave it standing when you mark. Read the new one out of the
file you have just edited:

```
git hash-object README.md
```

**Marking is not enough when the edit *removed* something.** The marker is an
HTML comment, so on GitHub the deleted thing renders and the warning about it
does not. A translation behind by an **addition** costs its reader a paragraph
they cannot see; one behind by a **removal** leaves them holding the thing
English deleted, with no signal at all. That is not hypothetical: both
translated READMEs went on giving a `flutter create` command as the setup step
— the one that overwrites the committed platform folders and drops the
`INTERNET` permission a release build has no other way to get — correctly
marked `STALE` the whole time, and on the rendered page the mark was invisible
and the command was not.

So the cheap option carries a rider, and it is narrow enough to follow without
thinking about it:

**If your English edit deleted or replaced a command, a fenced code block, a
flag, a path or a file name, make the same deletion or replacement wherever
the four translated files carry it — then mark them `STALE` as usual.**

That needs no knowledge of the target language, because what it applies to is
exactly what is never translated (the paragraph below): the thing you removed
is byte-identical in every file that still carries it, so one command finds
every copy.

```
grep -n "igdb_id" README.ru.md README.ja.md doc/guide.ru.md doc/guide.ja.md
```

**Grep the name you replaced, not the line you deleted** — the two are the
same thing only when you removed a whole line. T-0300 replaced a column name
*inside* lines: six copies sat in fenced blocks and were byte-identical, and
three sat inside translated prose, where the surrounding sentence is Russian
or Japanese and the line matches nothing. Grepping the line would have shipped
two translations whose code blocks said the new name and whose prose still
said the old one, which is worse than either endpoint.

The command spans four files as a **check**; edit the ones that carry a copy
and say in the report that the others did not. Delete what it names, or paste
the English's replacement over it. The translation is then behind by an
**addition** again, which is the case the marker already handles.

**One commit, not two.** This rule said two until T-0406, because a marker
naming *the commit the English moved to* cannot be inside that commit. A blob
name has no such shape: `git hash-object` reads the working tree, so the name
of the English you have just written exists before any commit does, and the
content and the markers go in together.

**The hole gets no note.** A line saying "this step was removed, read the
English" has to be written in Russian and in Japanese, and a rule whose last
step needs a translator fails in exactly the situation this whole convention
exists for. A reader who meets prose describing a step that is no longer under
it goes to `README.md`, which the top of their file links. Confusion is the
price, and it is the cheaper of the two failures.

**And one case this does not reach**, named rather than papered over: a removal
that lived only in translated prose, with no untranslated string to grep for.
There `STALE` stays the whole obligation — you cannot find the paragraph
without the language, and cutting by guess cuts the wrong thing. Say in the
commit message what was removed, so whoever next reads that language knows what
to look for.

Two things are deliberately not translated: **code blocks and program output**,
which are quoted from the running tool and would stop matching what a reader
sees, and the **engineering records** — `ARCHITECTURE.md`, `doc/decisions/`,
`doc/measurements.md` and the build diagnoses in `doc/android-build.md`. Those
are English only, along with code comments and commit messages.

**What a history rewrite does to a marker: nothing, and that is the change.** A
rewrite replaces commit objects; it does not change what a file says, so every
blob name still names the same content and every marker still answers. Two
things do move and both are bounded. If the rewrite edits an English file
itself — scrubbing a string out of every version of it, say — that file's blob
name at `HEAD` changes, every `CURRENT` marker on it stops matching, and
whoever ran the rewrite owes the same choice as any other English edit:
translate, or mark. And the *older* blob a marker names may stop being
reachable, so `git diff <that name> HEAD:README.md` can answer `fatal: bad
object` where it used to print a diff. The verdict never needs that object — it
is a comparison between two strings — which is exactly the property the
commit-hash marker did not have, and there the unreachable object *was* the
verdict.

**What is checked, and what is not.**
`packages/shelfscan_core/test/translation_marker_test.dart` reads the four
markers and fails when one claims `CURRENT` while its English source has a
different blob name at `HEAD`. It asks nobody to translate: the last word of
one line is the whole fix, in a language you need not read. That is the
difference from the CI check this section carried as considered-and-rejected
until T-0406 — that one fired on "the English changed and the translation did
not" and left a contributor two exits, translate a language they may not read
or bump the marker without translating, the second of which converts the marker
into a lie. Separating the claim (`CURRENT` or `STALE`) from the reference (the
blob name) removes the lie, because `STALE` is an honest answer and it is the
one the test asks for.

Three things are still unchecked and cannot be checked here: whether a file
marked `STALE` is stale, whether a `CURRENT` one is *complete* — the marker
answers whether the English moved, not whether all of it was carried over, and
a file with a known gap says so in prose beside its marker — and whether a
marker was bumped without the translation being touched. The last is forgery,
and no marker scheme detects it.

## Pull requests

Say what you measured, not only what you changed. A behaviour claim in this
project is expected to name the run it came from.
