# 0016 — A row is identified by the catalogue that answered and that catalogue's id

**Status:** accepted, 2026-08-23
**Tasks:** T-0292 (*`Candidate` is IGDB-shaped, so a film's identity rides in
fields named after another catalogue*)
**Reports:** `T-0292`

## Context

`Candidate` was written when IGDB was the only catalogue this project could
ask. It carries `igdbId`, `platformId` and `platformName`, all required, and
writes `igdb_id`, `platform_id` and `platform_name` into `review.json`.

Three tasks have since arrived at the same wall from three directions, and none
of them was about identity when it started.

- **T-0162** added TMDB. A film's id now travels in a field called `igdbId`.
  Nothing is wrong in the bytes — the exporter writes the right number in the
  right place — and everything is wrong in the name, which is the failure this
  project has already paid for once: T-0290's whole cost was a Dart identifier
  that had quietly become somebody else's file format.
- **T-0162** also verified that a published movie item carries **no
  `platform_id` key at all**, so the film path invents `filmPlatformId = 0` and
  `filmPlatformName = ''` to satisfy two required fields, and documents loudly
  that neither reaches a file.
- **T-0290** found that `platform_id` is not one concept. For a game it is a
  catalogue platform id; for an animation it is the export target's
  film-or-series discriminator. `main` was writing the first into the second.
- **T-0163** found the same class from the other end: a part of a box set has
  no id at all, and `.xcoll` refuses it — pinned as a test rather than worked
  around.

A fourth kind, `tv_show`, exists in the target's vocabulary and has no kind
here yet, so whatever is decided has to survive it arriving.

Decision [0015](0015-the-kind-of-work-is-a-property-of-the-row.md) admitted
this as cost #2 when it was taken. This is that cost arriving.

## Decision

### 1. Identity is the pair (catalogue, id), stated and never implied

A row's external identity is **which catalogue answered and what that catalogue
calls the entry**, carried together as one namespaced value in the form
`catalogue:id`.

**This is not a new convention; it is the third use of one this tree already
argued twice.** `Detection.sourceId` is a namespaced string, and its doc
comment states the reason in the general form — *"the number alone is only
unique inside one store, and two stores' ids colliding would resolve one game
to another with nothing visible to a reader"*. `CatalogueEntry.ref` (T-0163)
copied it a day ago and restated it: *"a string, not an int, precisely because
`Candidate.igdbId` is an int for being only ever IGDB's"*. So of the three
types in this tree that hold an external id, two namespace it and argue why,
and the third is the one the other two point at.

**Why the catalogue is stated rather than derived from the kind.** The export
target derives it — an item's `media_type` implies whether its `external_id` is
an IGDB or a TMDB id — and copying that inward is the tempting shortcut. It is
wrong here for a reason that is in the tree rather than in principle:
`CatalogueRouter` holds `Map<WorkKind, Worker<Detection, ResolvedGame>>` and
the map is built by the shell, deliberately, so that a third catalogue is one
entry and no production line moves (T-0162). A kind therefore does not name a
catalogue in this codebase; it names whatever the shell registered for it. An
id whose catalogue is inferred from a map somebody else configures is exactly
the silent mismatch `Detection.sourceId` refuses.

**Where the two contracts meet, the exporter checks rather than casts.** The
target wants a bare integer with the catalogue implied by `media_type`. So
`TonkatsuExporter` splits the namespace off, and **refuses the row if the
namespace disagrees with what the kind implies**. That check is not decoration:
it is the shape of the defect T-0290 fixed by hand, made mechanical. A row
carrying a games-catalogue id under a film kind is precisely what `main` was
writing, one field over.

### 2. `platformId` becomes optional, with the reason on the field — not split

`Candidate.platformId` and `Candidate.platformName` become nullable, null
meaning **this kind of work has no platform**, and `filmPlatformId` /
`filmPlatformName` are deleted. The first of those two constants is the one
placeholder in this codebase sitting in a field other code can read, and
`exporters.dart` already argues against exactly it by name — *0 is a
valid-looking id and would be a lie in a column other tools may key on*.

**Not a split into per-kind candidate types**, and the third case is what rules
it out. A split by *has a platform / has not* puts `game` on one side and
`movie` on the other, and then has nowhere to put `animation`, which needs a
value in that wire position that is not a platform at all. A two-way carve of a
three-way distinction is how one name comes to mean two things, which is the
thing decision 0015 spends a paragraph on and T-0290 spent a task on. The
film-or-series bit belongs to the **kind**, where `WorkKind.wire` already makes
room for it: two enum values may share the wire string `animation` and differ
only in the number they put in `platform_id`. That is written in
`_PlatformId.undecidable`, and it is the right home.

**Nullable does not change the tie rule, and it makes it honest.** Two film
candidates compare equal on platform today because both are `0`; under this
change both are null and compare equal for the reason that is actually true.
Same answer, stated correctly. The one real edit is the candidate sort, which
calls `compareTo` on the value and needs a null-safe comparator.

### 3. An exporter declines a row it cannot carry, and the rule is already written once

`Exporter.canExport` is that rule, it is a documented part of the contract
rather than an implementation detail, and both shells ask it instead of
re-deriving it — the review screen says so in four separate comments and the
CLI's export summary does the same. **So the answer to "say it once instead of
three times" is that it already is said once. What looked like three arguments
is one contract with two clauses over three cases.**

- A row with no match at all is refused by the base clause, `best != null`.
- **A part of a box set is that same clause**, not a separate argument. T-0163's
  `expandParts` drops `best` because it was an answer about the box, so a part
  arrives unmatched and the default rule refuses it. Nothing was added for it;
  the test pins behaviour that was already there.
- An animation row is refused by the one added clause, and it is a **different
  kind of refusal**: that row can be identified perfectly well. What it lacks is
  not an id but the film-or-series bit the target requires beside it.

Stated once, in the form that covers all three: **a target refuses a row it
cannot fill honestly, and the shells name what was refused.** Failing to
identify the row is one case of that, not the whole of it. Collapsing the two
would make the animation refusal look like a missing id — which it is not, and
which would send the next person looking for a catalogue client that already
exists.

**Declining is per target, never pipeline-wide.** CSV carries every row `.xcoll`
refuses, because CSV is title text and an `.xcoll` item *is* a pair of ids. A
row that cannot be identified is not a row that failed; it is a row that the
one target keyed on ids cannot take. What is dropped is named
([0012](0012-what-is-dropped-is-named-never-counted.md)), which is what makes
the refusal a report rather than a silence.

### 4. Migration: at once, in one commit, with no seam

**There is nothing to migrate for the rename**, which is the finding that makes
the rest of this cheap — see the counts below. **There is something to migrate
for the retype**, and it is one widening read.

- `review.json` reads `igdb_id` as an int today. It becomes a read that accepts
  an integer and means `igdb:<that integer>`, beside a new key carrying the
  namespaced value. Every document written before this change loads unchanged,
  which is the treatment `source_entry`, `source_id`, `work_kind` and `parts`
  already get, and the document version stays 1.
- `platform_id` and `platform_name` become **absent when null** — the same
  absent-when-empty shape and the same reason: a scan of a game shelf writes the
  bytes it wrote before.

**Why no seam.** A seam — dual writing, a flag, a parallel field — is worth
paying for when a wrong answer is expensive to unwind *and* there are documents
in the wild written by a version nobody will update. Decision
[0014](0014-stay-in-0-x-until-the-two-file-formats-stop-moving.md) answers the
second half unusually directly: this project is in `0.x` *because* both files it
writes can still change shape, and **no document written by one version has yet
been loaded by another**. There is no installed base. A seam here would be
scaffolding built over nobody.

**What must land together, and this is the half worth stating as a rule.** The
namespace goes in everywhere in one commit. A `Candidate` whose id is sometimes
bare and sometimes namespaced is worse than either shape on its own, because
every consumer then has to guess which it holds — and a half-applied rename is
a substitution that stopped halfway, which is the failure shape this project
has paid for most often, and the one T-0162 found twice in one afternoon. One
commit for the type, the exporter's namespace check, and the reader's legacy
path.

## The measurement that settled it, and how it was counted

Every figure below is a count of this repository's own tracked Dart source,
taken with `git ls-files -z '*.dart' | xargs -0 grep -o` and the same form per
directory. `grep -o` rather than `grep -c`, because `-c` counts matching *lines*
and several lines here carry two occurrences. The pattern is bounded at both
ends, because the app's settings screen holds an unrelated `_igdbId` — the IGDB
*client id* — which a bare substring search folds into the total. That pattern
was positive-controlled against a known site in the exporter and
negative-controlled against the settings screen before any figure below was
taken.

**The rename is far cheaper than the task that raised it assumed, and that is
the answer rather than a caveat.**

| | occurrences | files |
|---|---|---|
| `igdbId`, everything | 90 | 34 |
| — of which `IgdbHit.igdbId`, where the name is **correct** | 6 | 2 |
| — of which `Candidate.igdbId`, which this record renames | 84 | 32 |
| `Candidate.igdbId` in `lib/` — production | **14** | **4** |
| `Candidate.igdbId` in `test/` | 70 | 28 |

Two of those fourteen are prose inside doc comments. So **the production cost of
the rename is twelve lines of code across four files**: `models.dart`,
`resolver.dart`, `exporters/exporters.dart`, and the app's `review_screen.dart`.
The seventy in tests are almost entirely `igdbId:` in fixture construction —
27 construction sites in all, five of them in `lib/`.

**And the rename reaches no file format, because the separation T-0290 had to
build already exists here.** `WorkKind` needed a `wire` field invented for it
because the exporter was writing `workKind.name` — the identifier itself.
`Candidate` never did that: the wire key is a string literal at the
(de)serialiser, `'igdb_id': igdbId`, and the CSV column is a literal in a header
constant. The field name and the wire name have been decoupled since the first
line, and nobody noticed. That wire key appears in `lib/` **5 times, in 4
places, across exactly two surfaces** — `review.json`'s `best` and
`candidates[]`, and the CSV header — with 22 more in tests and 9 in the three
READMEs.

So the two halves price completely differently, and conflating them is what made
this look expensive:

- **renaming the field** — 12 lines of production code, no format touched, no
  document invalidated;
- **retyping it to a namespaced string** — the same 12 lines, plus one widening
  read, plus one decision about a published CSV column header.

The platform half is the same shape and slightly larger: `platformId` is 27
occurrences in `lib/` and `platformName` 20, across 33 and 31 files in total. Of
the `lib/` platform reads, four are decisions rather than plumbing: the `.xcoll`
write, which is already guarded to the one kind that has a platform; the review
screen's identity comparison; and the resolver's tie rule, in two places.

### The one behaviour change hiding in the nullable platform, found by reading the fallbacks

`CsvExporter` writes `best?.platformName ?? d.platformHint ?? ''`. A film's
`platformName` is `''` today, which is **not null**, so it short-circuits the
fallback and the column comes out empty. Under a nullable field it becomes null,
the `??` chain continues, and the column takes `platformHint`.

For a film read off a filename that is still empty, because `FilenameSource`
sets a film's hint to null deliberately rather than to a default. But a row a
person **corrected** from game to film at review keeps the detection's original
hint — `correctWorkKind` clears the match, not the detection — so after
re-resolution that row would print a console name in the platform column of a
film. Nothing writes it today only because `''` happens to block the chain.
Whichever task implements this owns that line, and the fix is that a kind with
no platform writes no platform rather than falling through to a hint that was
about something else.

## Consequences

- **`Candidate.igdbId` becomes `Candidate.externalId`, a namespaced string**,
  matching `Detection.sourceId` and `CatalogueEntry.ref`. Three fields for one
  concept in one file becomes three fields in one shape, and a consumer splits
  at the first `:` rather than guessing which service answered.
- **`IgdbHit.igdbId` and `TmdbHit.tmdbId` keep their names and their `int`
  type.** Each is a single catalogue's answer by construction, and naming it for
  that catalogue is correct — the same argument that makes `Candidate.igdbId`
  wrong makes those two right. The namespace is applied at the resolver, on the
  one line per catalogue that builds a `Candidate`.
- **`TonkatsuExporter` gains a check it did not have**: the namespace must agree
  with the catalogue the kind implies, or the row is declined. The item it
  writes is unchanged — a bare integer, because that is the target's contract —
  so no exported file moves.
- **The CSV column `igdb_id` becomes `external_id` and carries the namespaced
  value.** This is the one place in this record a reader may reasonably
  disagree, so the argument is stated rather than assumed: a column named for
  one catalogue that carries another's ids is the same defect as the field, one
  level out, and this project has now twice watched a name outlive the thing it
  named. The cost is real — the header is published in the README in three
  languages, and T-0166 already accepted that a consumer must map by header
  rather than by position. What makes it affordable today is that **no catalogue
  app has ever imported this CSV**, which the README and the changelog both
  state. The day one does, the column is frozen and this becomes a different
  decision.
- **`tv_show` arrives with no new machinery, which is the test this shape had to
  pass.** It is a TMDB id like a film's, its target item carries no
  `platform_id`, so its platform is null and it exports. The
  switch-with-no-default in `_platformId` still forces someone to answer for it
  before it can reach the writer.
- **A box-set part still does not export to `.xcoll`**, and nothing here changes
  that. It has no id from any catalogue, so it fails identity in the plain
  sense; T-0163's pinned test goes on recording that, and what lifts it is a
  catalogue client that answers per part, not a change to this shape.
- **This does not settle dedupe.** Decision 0015's cost #1 — that `titleKey`
  folds an adaptation into the work it was adapted from, and that the kind has
  to become part of a row's identity — is about identity *before* a catalogue
  answers. Everything here is about identity *after* one has. The two meet
  eventually and they are not the same question.

## What this record does not answer

- **Whether `tv_show`'s `external_id` is a TMDB series id.** It is the obvious
  reading of the published collections and it was not verified against one.
  What would settle it: the same check T-0162 ran against the format's own
  reference files, before any task writes the fourth kind.
- **The internal separator.** `catalogue:id` is taken from the two existing
  fields for consistency, not because a colon was measured against a record
  type. If a later task meets a catalogue whose ids contain a colon, the
  convention breaks in the same place in all three fields, which is the cheapest
  place for it to break.
- **What a row identified by two catalogues looks like** — an anime holding both
  a TMDB and a games-catalogue entry. Nothing produces one and nothing needs
  one, and `parts` is the field that would grow if something did.
