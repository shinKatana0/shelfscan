# 0006 — A platform hint is a lookup with a measured width, and a hint the gate cannot honour is worse than no hint

**Status:** accepted, 2026-08-14, extended 2026-08-16
**Tasks:** T-0002 (*Gate the auto-match on platform: the scorer is not what is
failing*), T-0023 (*Switch 2 cases resolve as Nintendo Switch*), T-0026
(*Platform is recalled from game knowledge for classic re-releases, not read from
the case*), T-0084 (*A platform_hint the model copied out of the prompt travels
to the CSV as a platform name*), T-0156 (*The platform gate has no PC entry, so
every GoG or installer row is either unfiltered or a mismatch*), T-0168 (*A
console game file is declined by the filename source, because the only hint it
could carry is PC*), T-0190 (*platformIds has no 3DS, DS, Wii U or Vita entry, so
four unambiguous console containers keep declining*)
**Reports:** `T-0002`, `T-0023`,
`T-0084`, `T-0113`,
`T-0190`

## Context

A detection carries a *platform hint*: a short string read off the case, or
written by whatever non-photographic source produced the row. IGDB — the games
database this project resolves against — identifies platforms by numeric id, and
returns one hit per (game, platform) pair, so the same title comes back several
times if it exists on several consoles.

The hint's job is to constrain that. Without it, a search for a well-known title
returns a dozen rows tying at the top score and the winner is whichever the
database happened to return first — which is how a Nintendo game auto-matched to
Xbox and a Rockstar game to Android.

The obvious design is a dictionary from hint to platform id. Two things make it
harder than that: hints are not a closed vocabulary (a case may print a family
name like `NINTENDO`, or a whole console band), and a family of consoles is
sometimes one id in the database and sometimes several.

## Decision

**`platformIds` is a lookup, not a vocabulary, and the width of each entry is a
measured property of that console family.** Three rules:

1. **A hint the map does not key is not rejected.** It falls back to matching the
   hint's words against the platform *name* the database returned. `NINTENDO` is
   left unmapped deliberately — it is equally an NES, an N64 and a Wii — and as
   a word-subset it matches `Nintendo Switch` and `Nintendo Switch 2` but not
   `Xbox Series X|S`. A family hint therefore narrows without pretending to pick
   a console.
2. **A mapped hint agrees with any console it can mean.** Where a family shares a
   case, a physical format or a band the model cannot read, the entry is a union
   of ids rather than one. Where the sibling platforms are routinely the same
   game, the entry is one id.
3. **A source that cannot produce an honest hint produces no row.** The gate
   refuses a candidate whose platform contradicts the hint, so a wrong hint is
   not a cosmetic error: it removes the game from the run twice over, once by
   filtering the query and once by refusing what survives.

## The measurement that settled it

The width question was measured three times, on three families, and it came out
differently each time — which is the whole point.

- **Desktop: one id.** Unioning Windows with Linux, Mac or DOS was measured
  against live IGDB. Each union bought exactly one row and lost several to
  ties, because a desktop game is listed on all of them as a matter of course.
  The one row it buys is a title the database does not list on Windows at all.
  Rejected (T-0156).
- **Switch: a union.** A Switch 2 case and a Switch case are the same plastic;
  the printed band that distinguishes them defeated thirteen prompt wordings on
  the local model (`doc/measurements.md`, "The Switch 2 band"), and a file
  container carries no band at all. Mapping `SWITCH` to the Switch id alone sank
  every Switch 2 release into a mismatch. The union rescued rows the
  database had answered with nothing and removed the last wrong auto-match, at
  the cost of ties (T-0023).
- **The handhelds: a union, for the opposite reason.** T-0190 read the whole
  platform listing live — one request rather than four searches, so that "is
  there a second one of these?" could be answered without recalling anything —
  and found that Wii U and Vita have no sibling at all, while the 3DS and DS each
  do. It then counted the overlap: **1.6% and 1.0%** of those catalogues are
  listed on both the parent and the sibling, where a desktop game is on three
  platforms routinely. Both mappings were then replayed through the *real*
  resolver against live IGDB, one search per title per mapping. The narrow
  mapping answers a real DSiWare title with nothing or with junk; the union
  costs one cross-id tie, which is one tap and cannot reach a wrong game.

The third rule was measured as a failure already shipping. A container that
spans systems — a PlayStation package that is equally PS3, PS4 and Vita; an
archive extension that is a Vita package *and* a Valve archive — can only claim a
hint that is wrong for some of its files. T-0113 measured what such a hint costs
on a real row: the misread spines carry a hint for the wrong console, and the
row is lost to the platform filter *before* it is lost to anything else, so the
two defects are conjunctive and fixing either alone moves nothing. The offline
four-cell measurement is in `doc/measurements.md`, "One spine, two gates".
Those containers therefore decline.

## Consequences

- Every entry in `platformIds` is defensible by a number, and the table's doc
  comment carries them. Adding a console means reading its ids off the live
  listing and counting the overlap, not recalling an id.
- The gate only re-states a constraint the query already applied — except for the
  unmapped hints, which is where it does its real work.
- A union produces ties, and ties are refused rather than guessed; see
  [0007](0007-the-resolver-refuses-what-it-cannot-decide.md). The two decisions
  are designed against each other: widening a hint is affordable *because* the
  tie rule turns the ambiguity into a review tap instead of a wrong export.
- A hint is also validated on the way in for a different reason. Because the
  vision model sometimes copies the prompt's own menu text into the answer (see
  [0002](0002-the-prompt-is-a-measured-artifact.md)), a hint is checked against
  the *notation* of this project's schema line — a pipe with whitespace, a gloss
  marker, implausible length — and not against a list of known platforms, which
  would throw away the family hints the resolver relies on.
