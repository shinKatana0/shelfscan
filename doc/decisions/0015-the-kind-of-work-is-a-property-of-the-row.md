# 0015 — The kind of work is a property of the row, not of the run

**Status:** accepted, 2026-08-22
**Tasks:** T-0279 (*settle the shape before any second catalogue is written*),
T-0163 (*whether the export target accepts non-game media at all*)
**Reports:** `T-0279`

## Context

Tonkatsu Box is not a game manager. It is a mixed-media collection manager by
design — games, films, series, anime, manga, visual novels, books — and it
already searches AniList, TMDB, VNDB, MangaDex and Kitsu beside IGDB. That was
verified against its own repository while checking its licence for an unrelated
question (T-0163), and it changes the standing of one literal: the `media_type`
field `TonkatsuExporter` wrote as `game` has real siblings rather than being a
lone constant.

So "how would this project ever write one of the others" stopped being a
speculative question. The obvious answer is a mode, or a tab: choose *games* or
*anime* before the scan, and every stage afterwards knows what it is looking
at. This record is why that answer is wrong.

It is written before any of the work it governs — the second catalogue client,
the second prompt, the episode-aware resolver — because each of those is cheap
to build against a decided shape and expensive to unpick from a wrong one.

## Decision

The kind of work a row is a copy of is **a property of the row**:
`Detection.workKind`, defaulting to `WorkKind.game`, carried through review and
written into the `.xcoll` item. A run may carry a **hint**, and the hint selects
the prompt and nothing else.

The argument is a stage analysis, and it is narrow. Of the five stages that
could care:

| stage | decided where |
|---|---|
| the prompt | **per run** |
| catalogue routing | per row |
| resolver choice | per row |
| what review displays | per row |
| what the exporter writes | per row |

Only the prompt is per-run, and only for a mechanical reason: there is one
model call per photograph, so the model is asked once about a whole shelf,
before anything standing on it has been separated into rows. Every stage after
that one holds rows, and a row is where the kind is known.

**Why not a tab.** A tab makes the kind a property of the run, which is wrong
twice over. It splits inside this app what the export target joins into one
collection — Tonkatsu imports one mixed file, not one file per kind. And it
forces a shelf holding both to be photographed twice, because on a real shelf
they stand side by side, which is the arrangement this whole project exists to
read.

**The consequence that makes this more than naming.** A row that comes back as
anime from a games-hinted scan must **route** to the anime catalogue. A mode
would have to throw it away — and a row the model read correctly, discarded
because the run was labelled something else, is the silence decision 0012 is
about.

## The measurement that settled it

Run against disc cases of anime using the **unmodified game prompt**
(2026-08-22), a cloud model and the local model both answered them with the
carrier `unknown` rather than labelling them games. Neither had been told
anything about anime.

The models are therefore already producing mixed rows from a single-kind
prompt. A mode would not be preventing mixed input; it would only be discarding
it. The same observation is the evidence for the hint being advisory rather
than binding: aiming the prompt moves what the model looks for, not what it is
willing to answer.

## A source with no prompt: the kind is inferred per entry

Added 2026-08-23, on the owner's question. The stage analysis above says the
prompt is the only per-run thing. **A disk source has no prompt at all**, so
the question is what replaces it — and the answer is that nothing does.

What actually differs between a folder of games, a folder of films and a folder
of anime is the **grammar of the names**, and the three are genuinely different
rather than one shape with a flag:

```
setup_harbour_lantern_1.6.15_(45683).exe      version, build, architecture
The.Matrix.1999.1080p.BluRay.x264-GROUP.mkv   year, resolution, source, codec
[SubGroup] Series - 04 [1080p].mkv            group in brackets, EPISODE number
```

The third also splits the title: the series is the name and the episode is a
separate field, which neither of the others has.

**But the entry carries its own markers, so the kind is inferred rather than
chosen.** The extension separates most of it — `.exe`, `.msi`, `.iso` beside a
`goggame-*.info` is a game; `.mkv`, `.mp4`, `.avi` is video. The grammar
separates the rest — `[Group] Name - 04 [1080p]` is the fansub shape,
`Name.Year.1080p.Source-GROUP` is the scene shape, and an episode number in
`- NN` or `S01E04` tells a series from a film. Where neither settles it, the
source **declines**, which is machinery `FilenameSource` already has and
already uses.

**This is the case that argues hardest for the row property.** A real download
directory is mixed — the owner's own run over one returned application
installers beside everything else. A per-run mode would have to scan such a
folder once per kind and discard most of each pass; a per-entry property reads
it once. So the source with no prompt, which looked like the awkward case for
this decision, is the one it fits best.

A per-run hint may still exist for a disk source, but it means something
weaker than it does for a photograph: **a prior, not a selector.** "This folder
is mostly films" breaks ties; it does not override a clear marker.

### And the cost, which belongs here rather than being found later

`scan-installs` ships a contract — *point this at a games folder only* — and it
exists because a name cannot tell an application installer from a game
installer. That is measured, not feared: a run over a real download directory
returned application installers as titles, and `NoteWellSetup.exe` is the
example in the guide.

**Three kinds do not remove that contract, they weaken it.** It becomes *point
this at a media folder and review every row*, and there are now three ways for
a name to be read as the wrong thing instead of one. The failure stays silent,
because a filename never announces that it is not what it looks like. Any task
that adds a second kind to a disk source owns that sentence in the guide.

**And the mitigation, decided by the owner 2026-08-23 in the same breath: the
kind is correctable at review.** A person looking at the list can change a
row's kind, which is the only thing that turns a silent wrong inference into a
visible one. Two consequences follow and neither is optional. **The row has to
SHOW its kind** — a value you cannot see is one you cannot correct, and the
review screen is where every other uncertain thing in this pipeline is already
shown. And **changing it has to re-route**, not just relabel: a row corrected
from film to anime must resolve against the other catalogue, or the correction
buys a right word and a wrong match.

## What this gives up

There is a cost, and the first two items are the ones that were weighed.

1. **Dedupe and identity get harder, and this is the real price.** `titleKey`
   folds two rows with the same title into one; an adaptation shares its title
   with its source almost by definition, so a game and an anime of one name are
   now two rows this pipeline has to be taught not to merge. A mode makes that
   problem not exist. The kind has to become part of a row's identity, and
   nothing here has done that yet.
2. **The row-identity problem is admitted into the same document rather than
   quarantined beside it.** A film is one row; an anime is a series, a season
   and episodes (T-0163), and that does not fit `ResolvedGame`, whose identity
   is a title and a platform id. A mode could have given that its own document
   type. This decision guarantees the answer has to land inside
   `ReviewDocument`.

   **Settled, 2026-08-23 —
   [0016](0016-a-row-is-identified-by-the-catalogue-that-answered.md), T-0292.**
   It did land inside `ReviewDocument`, in two additive pieces and at no cost
   this paragraph did not predict. A row that maps to several catalogue
   entries carries them in `ResolvedGame.parts` (T-0163); a row's external
   identity stops being a games-catalogue key and becomes the catalogue that
   answered plus that catalogue's id, and the platform becomes optional
   instead of a placeholder. What this paragraph got wrong is the price: the
   rename it feared touches twelve lines of production code and reaches no
   file format, because `Candidate`'s wire key was never its identifier —
   which is the separation T-0290 had to build for `WorkKind` and that this
   type already had.
3. **Every stage after the prompt carries a branch, permanently.** A mode is
   one test at the top of a run. A property is a test in the resolver, in the
   review screen and in the exporter, and each further kind multiplies them.
4. **The review screen cannot be specialised.** One screen per kind is simpler
   than one screen rendering a heterogeneous list, and no arrangement of a
   mixed list recovers that simplicity.
5. **Nothing is bought today.** The default means no behaviour moves, so the
   costs above are paid now against a benefit that arrives with the second
   catalogue. If that catalogue is never built, this field is dead weight.

The first two were accepted anyway, because both problems are real whether or
not the app has a mode — a person with a mixed shelf has a mixed shelf — and
because the alternative's failure mode is discarding a row that was read
correctly.

## Consequences

- **`MediaType` keeps its meaning and its name: the physical carrier**,
  `cartridge | disc | unknown`. It could not have been reused for the kind even
  if the two concepts were closer, because that name is already on the wire in
  three places this project does not freely control — `review.json`, the CSV
  header, and the vision schema whose fingerprint `control_set_test.dart` pins
  to the control figures (decision 0004). `WorkKind` is a separate type for
  that reason, and because one name covering two concepts is how a
  half-applied rename survives review: each half looks correct on its own.
- **The `.xcoll` key stays `media_type`.** It is Tonkatsu's field and not ours
  to rename. So one wire name means the carrier in this project's CSV export
  and the kind in its `.xcoll` export. That is a fact about two external
  formats rather than a choice, and it is pinned by a test that puts one row
  through both targets and asserts the two answers differ.
- **The wire name is spoken for three times, not twice**, and the third is
  somebody else's too: the Anthropic Messages API calls the MIME type of an
  uploaded image `media_type`, which is what `providers/vision.dart` sends with
  every photograph. Nothing in this codebase may take that string as evidence
  of which concept it is looking at — only the Dart type says that, which is
  the whole reason there are two of them.
- **`game` is the only value of the kind that has ever been imported.** T-0009
  round-tripped it into Tonkatsu Box. `anime` is Tonkatsu's own vocabulary for
  a kind it manages, but this *spelling* of it in this field is an assumption
  until an import measures it; whichever task writes the second kind verifies
  it against the importer before anything else.

  **Verified, and the assumption was wrong — T-0162, corrected T-0290.**
  Tonkatsu's published collections write `game`, `movie`, `tv_show` and
  `animation`. It files an anime film and an anime series alike under
  `animation`, telling them apart by `platform_id` (`0` film, `1` series)
  rather than by the kind, so `anime` was a value no importer knows. The
  paragraph above is left standing because the instruction in it worked: the
  verification is what caught both this and `film`, one of them before it
  shipped. What the correction added is the reason the wrong word travelled so
  far — the exporter wrote the enum's *identifier* into the file, so nothing
  distinguished a name chosen for Dart from a value owed to somebody else's
  format. `WorkKind.wire` is that distinction, and a rename cannot reach an
  exported file any more.

  **And `animation` is the first kind this project declines to export.** Its
  `platform_id` is a film-or-series discriminator; no stage here produces the
  answer, and a row only becomes `animation` because a person corrected its
  kind at review, which says nothing about which of the two it is. So
  `TonkatsuExporter.canExport` refuses the row and the shells name it as
  dropped, rather than writing a `0` nobody claimed — the same rule this
  record already applies to a `work_kind` it cannot parse, one level further
  out.
- **An unrecognised `work_kind` is refused, not degraded.** `review.json` is
  hand-editable by design (T-0050), and `unknown` is an honest landing place
  for a carrier the model could not tell. There is no equivalent for a kind:
  answering `game` to a typo would write a claim about the row that nobody
  made.
- **A document of games writes no `work_kind` key at all**, so a scan of a game
  shelf still produces the bytes it produced before the field existed — the
  reproducibility `source_entry`, `source_id` and `source_year` are each
  absent-when-empty for.

## Out of this record

Each is its own task, and none of them is decided here: the second catalogue
client, the second prompt, the row-identity question (T-0163), the UI control
for the per-run hint, and whether the CSV export grows a column for the kind.

The row-identity question has since been decided, in
[0016](0016-a-row-is-identified-by-the-catalogue-that-answered.md).
