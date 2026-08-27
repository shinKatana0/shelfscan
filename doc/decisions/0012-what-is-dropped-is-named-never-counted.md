# 0012 — What the pipeline drops is named, never counted — and a count that cannot be exact is stated as a bound

**Status:** accepted, 2026-08-14, sharpened through 2026-08-16
**Tasks:** T-0025 (*Accept HEIC photos on input*), T-0028 (*unreadable channel
reports a constant 3 japanese spines per photo*), T-0030 (*Flutter app discards
every pipeline warning, so failed photos vanish from the run*), T-0035 (*A
detection with an empty raw_title becomes a review row*), T-0036 (*PNG and WebP
photos are declared image/jpeg to both cloud providers*), T-0109 (*One unreadable
entry can describe several spines*), T-0123 (*The review list never says which
rows cannot reach .xcoll*), T-0151 (*The app still labels unreadable entries as a
count of spines*), T-0161 (*The app can only add photos*), T-0184 (*A declined
entry is named nowhere*)
**Reports:** `T-0108` (carries T-0109's fix),
`T-0123`, `T-0151`,
`T-0161`, `T-0184`

## Context

This project's most-filed class of defect, by a distance, is not a wrong answer.
It is a *quiet* one: a photograph skipped because its format was unsupported, a
warning the interface threw away, an item that never became a row. The user sees
a plausible collection and no indication that anything is missing from it, which
is the one failure they cannot detect and cannot correct.

The standing rule came out of five such defects in the project's first days and
is written on its front page: **a silent failure is worse than a loud one, and
anything the pipeline drops must be named to the user.**

## Decision

**Name it, do not count it.** Three parts, each measured separately:

1. **A dropped or declined item is reported by its own name**, not as a number.
   A count cannot be traced back to a row, which is precisely what the person
   holding the collection needs to do.
2. **Silence and a wall of text are both failures**, so the shape between them is
   fixed: at most two lines per *distinct reason*, the second capped at a small
   number of names, followed by "and N more" pointing at the field in the
   document that holds all of them. Forty declines of one reason are two lines
   whatever the folder held.
3. **Where an exact count is not available, state the bound, not a number.** No
   figure is ever derived from the model's prose.

Two lists that look alike are deliberately kept apart: what a model *perceived
on a photograph but could not read* is not the same as what a source *was handed
and made no row of*. Merging them would inflate a photograph's figures with an
entry nobody saw.

## The measurement that settled it

**On the unit (T-0109, T-0151).** The channel that reports unreadable spines
returns *entries*, and one entry can describe several spines. Measured on the
control set: one cloud model answers a **single entry naming two or three middle
spines on ten of ten runs, against a hand count off the photograph that the
entry never matches**, and answers one entry on eight runs and two on the other
two for one and the same group of spines on a second photograph. So a count of
entries is a **lower bound on spines and never a count of them**. The user-facing consequence is under-reporting exactly the thing this
channel exists to make the owner check by hand — and under-reporting is the
expensive direction, because a number read as exact stops the search at the first
missing game while a floor read as a floor does not. Both interfaces now say
"at least N", name the unit as a report, and print the model's own sentence
underneath. Deriving a spine count from that sentence was rejected explicitly: it
would be the fabricated count T-0028 already removed once.

**On the count itself (T-0184).** This is the sharpest instance and it is worth
stating exactly, because the task's own premise was wrong and its worker proved
it. The task was filed as "a declined entry is named nowhere: the summary counts
it and the document omits the list". The worker measured the chain link by link
and found it intact — the field existed, was populated and was written whenever
non-empty. There had been no decline. What had happened is that the summary line
reported one number of entries read and another of games found, **a count
invited a subtraction, the subtraction was performed, and it produced a decline
that had never happened** — in the task as filed, and in the acceptance
criterion asking for a test of it. The two folders concerned had the
same locale-generated default name, parsed to the same title, and were merged.

The fix is the decision generalised: **state every count instead of implying
one.** The summary now says how many entries named no game, how many named one,
and how many of those merged into another row — and it claims the merge clause
only in the runs where every row came from an entry.

**On the shape (T-0161).** A games folder declines more than it accepts — the
measured rates are in T-0158's report — so one line per entry is unusable and
silence is worse. The folded form is one line per distinct reason, out of a
closed set, with the names behind a tap.

## Consequences

- Every stage that can drop something carries a named list to the document, and
  the document is the canonical place those names live; the interfaces read
  values out of it rather than parsing sentences out of a warning.
- A decline is treated as the source **working**, not failing: a games folder
  holds saves, patches, screenshots and DLC archives, and a title guessed off one
  of those costs a database call and a row the human has to reject.
- The rule reaches beyond the user interface. It decided a database connection
  string — see [0010](0010-copy-the-database-before-reading-it.md) — and it
  decided a prompt question: a partial read of a spine the camera frame cut is
  *reported* rather than suppressed, because on one control set those fragments
  are the only signal the pipeline gives that a whole column of games was cut off.
  That analysis is in `doc/measurements.md`, "A cropped column's fragments".
- **One inconsistency is open and named rather than quietly tolerated.** The type
  carrying an unread-spine report is still named for the wrong unit, which is what
  taught three separate sites to count spines in the first place. The rename is
  filed, its cost is measured — dozens of references across the codebase — and it
  is known not to change any stored document, because the type name is not
  serialised. It is a live task, not a hidden defect.
