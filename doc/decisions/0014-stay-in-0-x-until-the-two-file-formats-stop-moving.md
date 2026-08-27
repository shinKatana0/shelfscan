# 0014 — Stay in 0.x until the two file formats stop moving, and keep both pubspecs in lockstep

**Status:** accepted, 2026-08-17; **the build-metadata clause amended
2026-08-25**, see *What changed, and the measurement that changed it*
**Tasks:** T-0194 (*the Windows runner's version metadata was never chosen*),
T-0211 (*0.1.0 is a decision rather than a default*)
**Reports:** `T-0194`, `T-0211`

## The decision

The first public release is **0.1.0**. The project stays in `0.x` for as long
as either of the two files it writes can still change shape, and the two
`pubspec.yaml` files — `app/` and `packages/shelfscan_core/` — always carry the
same number, and a **build number** rides behind a `+` (see the amendment
below). No suffixes.

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

## What changed, and the measurement that changed it

**Amended 2026-08-25.** This record originally said *no build metadata, no
suffixes*, and on 2026-08-17 that was right: nothing in the tree read a build
number, so one would have been decoration that drifts.

`app/android/` did not exist yet. It was scaffolded afterwards, and Android
reads exactly that field.

The measurement, taken on the signed release artefact:

    package: name='io.github.shinkatana0.shelfscan' versionCode='1' versionName='0.1.0'

`versionCode` comes from the `+N` behind the version in `app/pubspec.yaml`.
With no `+N`, Flutter substitutes **1** — so every Android package this project
has ever produced declares the same version, whatever its contents. Android
decides what is an update by that integer alone, so two different builds are
indistinguishable to the system that installs them, and a newer one is not an
upgrade of an older one.

That is not a versioning preference. It is a defect in the artefact, and the
clause forbidding build metadata is what produced it.

**So:** the version is `MAJOR.MINOR.PATCH+BUILD`. `BUILD` is a monotonic
integer, incremented for **every artefact handed to anyone**, never reset, and
never reused. It is not a date: three release packages were built on
2026-08-25 alone, and a date-shaped build number would have given all three the
same value — which is the defect this amendment exists to remove.

**A build that never leaves the machine consumes nothing.** The rule says
*every artefact handed to anyone*, and the word doing the work is *handed*. A
build made to measure something, to watch a check refuse, or to answer a
question about the artefact itself is not a hand-over, however many of them a
task makes: T-0404 built four apks and one Windows exe on its branch and
nobody received any of them. Requiring a number for each would make `BUILD` a
record of how much was built rather than of what was released, and would put
the counting somewhere git cannot see -- which is the class of rule this
record has spent two amendments narrowing.

**The number is consumed when the tag is cut.** That is the operational form
of the same sentence, and it is deliberately narrower than "handed to anyone":
cutting the tag is what makes an artefact findable by anyone but its builder,
and it is the only step of the release order git records. Handing a file to
someone without a tag is therefore not merely irregular but unrecorded, and no
check can see it. If it is ever done deliberately, cut the tag anyway.

*Ruled by the owner 2026-08-27, choosing this reading over the stricter one in
which any build consumes a number.*

Everything else in this record stands unchanged: the `0.x` gate, the two
formats that gate it, the lockstep between the two `pubspec.yaml` files, and
the release order.

## What the three numbers mean here, since neither package is a library

Both packages are `publish_to: none`. Nothing depends on their API, so the
usual reading of MAJOR — *the API broke* — has no subject. The contracts this
project actually has are the two file formats this record already names, and
the CLI surface the guides quote verbatim. The numbers are defined against
those:

- **MAJOR** — a released contract breaks: a field in `*.review.json` or a
  column in an export renamed, removed or re-meant; a CLI flag removed or
  changed in meaning. **While in `0.x` this bumps MINOR instead**, which is
  what Semantic Versioning reserves `0.x` for and what the gate above is about.
- **MINOR** — a capability a user can see: a new source, a new catalogue, a new
  export target, a new screen.
- **PATCH** — fixes and internal work that add no visible capability.
- **BUILD** — as above, and it moves for every handed-over artefact including
  ones where nothing else moved.

## Why a test rather than a checklist item

The release order in this record — both pubspecs, `CHANGELOG.md`, the tag — is
a rule enforced by remembering it, and this project has a written record of
what those cost. Two of the three parts are now assertable, so they are
asserted: that both `pubspec.yaml` files carry the same version, and that the
version has a build number at all. The second is the one that matters, because
its absence is silent — Flutter does not warn, it substitutes 1.

**What a suite can say, and where it stops.** `app_version_test.dart` asserts
everything the working tree knows about itself: that both `pubspec.yaml` files
agree, that `app/lib/app_version.dart` agrees with them, and that a build
number is present at all. It cannot say whether that number has been handed
over before, because that is a property of history and a suite deliberately
cannot see one -- it is exactly as green on a second artefact built at `+2` as
on the first. So *whether there is a number* stopped being enforced by
remembering and *which number it is* did not.

`tool/check-release-order.dart` closes that, and it is a script rather than a
test for that reason. Run before cutting a tag, it reads `app/pubspec.yaml`
out of every tag's tree and refuses when this tree's build number is not ahead
of all of them. Exit 0 in step, 1 refused, 2 when it compared nothing -- and
the third is not the first, because a checkout with no tags has answered the
question and a checkout where git cannot be reached has not.

Two limits, recorded here so nobody rediscovers them. It reads each tag's
**tree** and never its name, and **a tagged tree declaring no `+N` published
1**, because that is what Flutter substitutes.

**The changelog step is checked by the same script, in the one direction that
can refuse.** A tree ahead of the last tag whose changelog names no heading
for it is this repository on an ordinary day; the minute before a release is
cut is the *same git state*, because cutting the tag is the step after.
Nothing in the repository distinguishes them, so a check that refused one
would refuse both -- and a check that refuses ordinary work is a check that
stops being run. So the script answers in two voices: against this tree, a
`NOTE` that changes no exit code; against **every tag**, a refusal, because a
tag whose own tree carries no `## [VERSION]` heading for the version that tree
declared is a release that went out describing itself as unreleased.

Both halves share one limit and it is the mirror of the other: neither can see
an artefact handed over without a tag, and the changelog half sees a skipped
heading only once the tag exists. That is recoverable while the tag is local
and a report rather than a remedy once it is pushed -- one more reason the tag
is the last step and a person's act.

**And a check nothing names is reached by remembering, one level up.** The
release procedure is written where a person cutting a release will meet it --
`CONTRIBUTING.md`, *Cutting a release* -- with the order above, the command
for each check and what each answer means. It is a document because there is
nothing better available: git offers no hook that fires when a tag is cut
without also firing on ordinary commits, and any trigger at or after the tag
meets a check that refuses by design, since after the tag this tree is itself
something already published. Which is also why the tag is last: it is the step
that makes every earlier check unrepeatable.
