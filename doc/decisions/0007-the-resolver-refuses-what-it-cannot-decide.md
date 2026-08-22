# 0007 — The resolver refuses what it cannot decide, and the refusal is visible

**Status:** accepted, 2026-08-15, extended 2026-08-16
**Tasks:** T-0002 (*Gate the auto-match on platform: the scorer is not what is
failing*), T-0008 (*Measure resolver match rate on validated detections*), T-0055
(*A CJK sequel is one character away from being merged into its successor*),
T-0059 (*A roman-numeral sequel is merged into its predecessor and the row is
deleted*), T-0100 (*Normalized Levenshtein orders the two Japanese siblings
wrong*), T-0165 (*The tie rule cannot fire when a hint maps to one platform id*),
T-0170 (*Two tied candidates reach review as identical rows*)
**Reports:** `T-0002`, `T-0008`,
`T-0100`, `T-0170`
**Measurements:** `doc/measurements.md` — "The resolver, measured at last", "The
tie nobody could see, and what a release year buys"

## Context

The resolver turns a noisy title read off a spine into a canonical game id. It
scores candidates and, above a threshold, auto-matches: the row is exported
without anyone looking at it. Below the threshold it goes to a human.

The natural way to improve such a stage is to improve the score. That is what the
project set out to do, and the data said something else.

## Decision

**Where the resolver cannot tell two candidates apart, it refuses to choose, and
the row goes to review carrying both.** It never breaks a tie by the order the
database returned rows in. Concretely:

- an equal-scoring second candidate on the same platform refuses the auto-match;
- an equal *release year* exempts a second candidate from that refusal;
- a candidate whose platform contradicts the hint is refused outright, and a
  contradicting candidate is ranked down but never hidden from the human;
- a title whose printed volume number disagrees with the candidate's refuses the
  auto-match on any path;
- an unanswerable question refuses like any other: a candidate carrying no
  release year cannot claim the year exemption.

The threshold itself has never been moved.

## The measurement that settled it

**The scorer was never the problem.** T-0008 ran the resolver against live IGDB
for the first time and checked every row against the photographs. Almost all the
misses never reached the scorer at all — the database returned zero rows for
them. Word order, subtitle noise, regional titles and corrupt reads accounted for
zero occurrences each. What the data indicted instead was that the client emits
one hit per (game, platform) pair while the score compared titles only, so a
dozen rows tied at a perfect score and the winner was whichever arrived first.
Almost every confident false positive was the *right game on the wrong console*.
T-0002 was re-scoped from "replace the string metric" to "gate on the platform"
on the strength of that.

**The threshold is not the knob.** Scores cluster at the top and there was
nothing at all in the band immediately below the cut. Every false positive scored
comfortably above it. Later, once an unrelated fix trimmed the scorer, two
Japanese siblings straddled the threshold *in the wrong order* — the wrong match
scoring above the right one. No threshold was moved then either; what separates
those two rows is not a number but a printed volume number, which is why
volume agreement is a gate rather than a weight.

**The tie rule had a blind spot, and closing it was measured rather than
argued.** A hint mapping to a single platform id leaves every surviving candidate
on that id, so a guard that only fired between *different* platforms could never
fire at all — two different games at an identical score were decided by the
database's ordering. T-0165 measured four rule variants across four console
conditions and two control sets, using a method worth naming: one live answer per
(query, platform filter) was recorded to a file outside the repository and
replayed through the **real** resolver under each variant, so every variant sees
identical rows and the only difference is the rule. Sixteen variant runs cost
nothing after the first.

The result is the reason the rule is conditional rather than simply widened:
refusing every same-platform tie costs a handful of correct console rows, and
exempting an equal release year costs **none** of them back. Every row the
exemption keeps is one release under two database entries; every collision it
still refuses is two genuinely different releases, decades apart. The tables are
in `doc/measurements.md` and are not repeated here.

## Consequences

- The rule refuses far more wrong auto-matches than it costs right ones, and the
  exact ratio moved between two readings **without this repository changing** —
  a third party's result ordering changed underneath it. That is an argument for
  the rule, and it is why a bucket figure here is re-measured rather than carried
  forward.
- Refusal is affordable only because there is a human on the other side. Review
  is a mandatory step in this product, not an optional one, and the first
  validation run is why: the local model returns a uniform confidence on every
  row including partial reads, so confidence is unusable even as a *ranking*
  signal, let alone as a gate.
- A refusal has a cost the measurement did not price: two tied rows reach review
  looking identical. That was filed as its own task and fixed by putting the
  release year in front of the human — the same fact the rule uses.
- This is what makes widening a platform hint affordable; see
  [0006](0006-a-platform-hint-has-a-measured-width.md).
