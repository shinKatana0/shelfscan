# 0004 — The control set is a definition and a manifest of figures, not a committed document

**Status:** accepted, 2026-08-15; **half of it reversed 2026-08-18**, and the
reversal itself **narrowed the same day** — see "The reversal" and "The
correction to the reversal" below
**Tasks:** T-0081 (*The control document every resolver measurement quotes is
not on disk*), T-0119 (*control_set_test's unreadable assertion names
no cause*), T-0131 (*Every measurement re-scans the control set for
detections an earlier one already had*), T-0136 (*the control-set definition
defines a control by what a directory does NOT hold*), T-0246 (*The published
control-set figures reconstruct the owner's physical game collection*), T-0260
(*The manifest still publishes which platforms the control photographs
answered*)
**Reports:** `T-0081`, `T-0131`, `T-0246`, `T-0260`
**Figures:** `doc/control-set.md` (the working record; not published)

## Context

Every quality claim in this project is a count taken from a specific set of
photographs. Those photographs are of a private home. They are gitignored and
they are staying that way.

That left an awkward gap. Four separate documents, and the project's own front
page, quoted figures against "the control document" as though such a file
existed.
The closest file on disk held a different number of rows and had been produced by
a prompt three versions old. Two measurements each paid for a live database
run before discovering that. A measurement everyone cites and nobody can
identify is not a control.

The obvious fix is to commit the review document — it is only text. That was
considered and rejected.

## Decision

**Define the control as named sets of photographs plus a manifest of the figures
a scan of them must produce, and commit the definition rather than the output.**

- Two sets, `CONTROL-HIRES` (three photographs at 4000×3000) and
  `CONTROL-LOWRES` (the same subject at 1200×900, two photographs), each pinned
  by its input files — name, byte size, content hash — the command that
  regenerates them, and the figures a regeneration must produce. Work names the
  set, never the number. The definition sits with the photographs it names, in
  the working record this repository keeps and does not publish; what is
  published is the figures, in [`doc/measurements.md`](../measurements.md).
  *(That last clause is what was reversed on 2026-08-18.)*
- **No review document is committed, and none should be.**
- The detections themselves are captured once per machine and kept **outside** the
  repository, with a status command that says whether the capture is fresh.
  Ask it before scanning.
- The manifest is enforced by a test at three levels of strength, the strongest
  of which needs neither the photographs nor a network.

## The measurement that settled it

Two findings, of different kinds.

**On why a document must not be committed.** A `review.json` of those
photographs is not a photograph, and it is not obviously the lesser disclosure:
it is the same house rendered as a sorted, machine-readable inventory of dozens
of possessions, filed under photo names that carry the minute someone walked
around photographing them. The convenient format is the argument against
committing it, not for. Against that, what committing it buys was checked
against the project's own history: every citation of that document ever written
cited its *counts*, and counts are what the manifest carries. And it is
unnecessary — T-0053 made the scan reproducible and T-0081 made it documented, so
the control can be had again in under a minute by anyone holding the
photographs, which is everyone entitled to check it. An inventory of someone's
home in public version history cannot be had back.

**On why the manifest needs a machine to enforce it.** The failure this guards
against is documented, not hypothetical: the prompt changed under T-0026 and the
figures quoted against it stayed on the page for three more tasks, so a
regression at the lower resolution survived four prompt edits unnoticed.
`test/control_set_test.dart` therefore computes a fingerprint of the assembled
prompt and compares it. Editing the prompt fails `dart test` **on every machine
— no photographs, no model, no network** — with a message naming the document to
re-measure. Levels two and three (checking the photographs by name and size, and
checking a freshly generated document against the manifest) skip with a named
reason wherever the photographs are absent, which is every machine but one.

T-0131 added the third piece after four separate tasks each bought the same
vision pass: the detections are captured once, and a capture that cannot be
verified counts as absent rather than as good.

## Consequences

- A stranger cloning this repository cannot reproduce the figures, and the
  project says so plainly rather than implying otherwise. What they can check is
  that the figures and the prompt they belong to have not silently drifted apart
  — which is the failure that actually happened here.
- The prompt is expensive to edit on purpose; see
  [0002](0002-the-prompt-is-a-measured-artifact.md).
- The fingerprint is a receipt for the figures. Updating it without re-running
  the measurement is explicitly worse than leaving it stale, because it looks
  checked.
- One bounded exception was recorded here: a test fixture that committed real
  titles to exercise a specific code path, named by the control-set definition
  as the ceiling rather than as a precedent. It no longer holds real titles —
  `legal_marks_test.dart`'s rows are invented substitutes — so the exception
  is spent rather than standing. T-0246 did not make that substitution and did
  not re-audit the fixture beyond reading it; what it changed is the sentence
  here, which described a state the tree had already left.

## The reversal, 2026-08-18 (T-0246)

**What is reversed:** that the figures are the published half. They are not.
Every count — `detections`, `per_photo`, `hints_answered`, the `hint_*` split,
`empty_titles`, `unreadable` — moved out of `doc/control-set-manifest.md` and
`doc/measurements.md` and into `doc/control-set.md`, which is the working
record and is not published. They sit beside the `sizes` key, which T-0234 had
already moved there for the same reason one step earlier.

**What is not reversed, and is the durable half of this record:** that no
review document is committed; that the detections are captured once and kept
outside the repository; that work names the set and never the number; and that
a machine enforces the pinning. All four stand unchanged.

**Why.** The reasoning above holds that a `review.json` is an inventory of a
private home while its *counts* are safe to publish. The first half was right
and the second was wrong, and the argument is the same argument one step
further: the counts are themselves an inventory at lower resolution. From the
published figures alone a reader had the size of the collection, its split
across three photographs, its platform mix — which is to say which consoles are
owned — the size of each stack, whether any title is owned on more than one
of them, and the size of the truncation corpus. The 2026-08-17 ruling names
"the size of their game library" among the things that may not leave this
machine, and the owner ruled again over the whole 2026-08-18 audit: all of it
comes out. Nothing about the disclosure changed; what changed is that somebody
asked what the figures say about the person who took them, which is the
question the pre-publication audit now opens with.

**What survives the removal, and it is the part that mattered.** The check
this decision built is the prompt fingerprint, and the fingerprint was never a
figure about a shelf. It stays in the published manifest with the set labels,
the photo lists and the hint *names* — a hint name is a token this project's
own prompt offers the model, where the number of rows answering it is a
household. So editing `detectionPromptRules` or `detectionJsonSchema` still
fails `dart test` on every machine, with no photographs, no model and no
network, exactly as the consequence below promises. What a stranger can no
longer do is read the figures the receipt is a receipt *for*; the failure
message names the unpublished document instead. That is a real loss and it is
smaller than it looks, because a stranger could never re-measure them anyway —
the photographs were never published, which this record already said.

**Where the internal-consistency checks went.** `control_set_test.dart`'s
`the manifest` group used to check that `per_photo` summed to `detections` and
the `hint_*` counts to `hints_answered`. Those moved to a group that reads the
private document and skips wherever it is absent, joining the two groups that
already skipped everywhere but one machine. In their place the published
manifest gained the opposite check: that no count-shaped key is in it at all,
so a figure put back is a red test rather than a silent republication.

## The correction to the reversal, 2026-08-18 (T-0260)

**What is corrected:** the paragraph headed "What survives the removal" above,
which kept the hint *names* in the published manifest on the reasoning that "a
hint name is a token this project's own prompt offers the model, where the
number of rows answering it is a household". That reasoning is right about a
name and wrong about a **set** of them. The `hints` key was documented as
exhaustive — *"the whole set of platform strings this set answered, not a
sample: every row of the set carries one of these"* — and an exhaustive list of
the platforms answered across a shelf is that shelf's platform mix. It is the
same disclosure the `hint_*` counts were removed for, one step further on, with
the counting already done: it needs no number attached to be a list of which
consoles a household owns. T-0259 found it and refused to fix it alone, because
it crossed a manifest, two tests and this record. The earlier paragraph is left
standing rather than edited, so that both readings are legible.

**What changed.** `hints` is out of `doc/control-set-manifest.md`. Nothing was
moved anywhere to receive it: the `hint_*` keys in `doc/control-set.md` already
spell the same names beside their counts, so this is a removal with no
corresponding addition.

**What it cost, and why the trade is right.**
`platform_hint_is_a_platform_test.dart` enumerated that key to check that every
hint string the sets produced is still one the `platform_hint` gate accepts. It
now enumerates `platformIds.keys` instead — every platform string this project
can emit, which is a **superset** of whatever a shelf answers, so no string
covered before is uncovered now and the check grew rather than shrank. What is
genuinely given up is the join between the two: that the strings a *real* run
of a *real* model produced are among the ones the gate accepts. That
guarantee's input is the photographs, so it could only ever run on the one
machine holding them — and it still runs there, against the `hint_*` keys, in
the group that skips wherever the private document is absent. A check whose
input is a private home is not a check a published repository can carry, and
publishing the input to make it portable is the move this record exists to
refuse.

**And the vacuity guard moved with it.** `control_set_test.dart` asserted that
the `hints` key was not empty, naming the exact failure it prevented: an empty
key makes the enumeration one file away pass by testing nothing. Its
replacement is in that file rather than in this one — a floor on the size of
`platformIds` and two of its keys from opposite ends of the table, chosen by
position in it and not because any shelf answered them. The drift check between
the published names and the private counts is simply gone: it existed because
the two halves were in two files, and they are not any more.
