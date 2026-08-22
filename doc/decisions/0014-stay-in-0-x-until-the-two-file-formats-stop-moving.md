# 0014 — Stay in 0.x until the two file formats stop moving, and keep both pubspecs in lockstep

**Status:** accepted, 2026-08-17
**Tasks:** T-0194 (*the Windows runner's version metadata was never chosen*),
T-0211 (*0.1.0 is a decision rather than a default*)
**Reports:** `T-0194`, `T-0211`

## The decision

The first public release is **0.1.0**. The project stays in `0.x` for as long
as either of the two files it writes can still change shape, and the two
`pubspec.yaml` files — `app/` and `packages/shelfscan_core/` — always carry the
same number. No build metadata, no suffixes.

## Why a major zero, when the pipeline works

Two file formats leave this program and are read by something else, and both
are still young.

`*.review.json` is the document a person confirms by hand, and it is also the
resume point between a scan and an export — a run interrupted at review is
resumed from it. It grew a field as recently as the fourth detection origin
(decision 0009) and gained a per-entry severity the day before this release.

`.xcoll` is pinned to `version: 2` because Tonkatsu Box reads it, so its shape
is not ours to move. But *which* rows reach it is ours, and that rule has
already changed once: an item with no resolved match is left out and counted
(decision 0012), which was not true of the first exports.

A `1.0` would promise that a document written today still loads a year from
now. Nothing here has been asked to survive a format change yet, because
nothing outside this repository has written one. `0.x` says that plainly, and
Semantic Versioning reserves exactly this meaning for it.

## Why both pubspecs move together, even though only one is a program

`app/pubspec.yaml`'s version is not decoration: it flows through
`app/windows/runner/CMakeLists.txt` into `Runner.rc`, so the built `.exe` is
stamped from it and Windows shows that number in the file's properties
(T-0194). `packages/shelfscan_core` is a path dependency and is never published
to a package registry, so its own number is free — and a free number is one
that drifts. Two numbers that disagree would make a bug report ambiguous about
which half it came from, and the report form asks for a version.

So they move together, and the release checklist is: both pubspecs, then
`CHANGELOG.md`, then the tag.

## What would end 0.x

A `1.0` becomes honest when a `*.review.json` written by an older version has
been loaded by a newer one and the result was checked, and when a second
program besides Tonkatsu Box has imported an export. Neither has happened. The
CSV target in particular has never been imported into a catalog app here, which
`README.md` and `CHANGELOG.md` both say.
