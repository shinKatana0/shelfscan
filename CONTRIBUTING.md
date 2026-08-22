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

Before publishing anything, run both suites through `tool/check-suites.sh`
instead. Neither runner can be trusted to say what happened to itself: when a
suite file's test host process dies, every test in that file — including tests
that never started — is reported `did not complete` with no cause attached, and
a test that hangs rather than dies produces no timeout and no further output at
all. The script bounds each run in wall clock, kills the process tree if the
bound trips, and then reads its own log: any file named `did not complete` is
re-run on its own, because a file whose host died comes back green and a real
defect does not.

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
