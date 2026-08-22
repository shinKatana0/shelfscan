# 0002 — The vision prompt is a measured artifact, not a piece of writing

**Status:** accepted, 2026-08-13, reinforced through 2026-08-16
**Tasks:** T-0007 (*Vision prompt: forbid inventing unreadable titles*), T-0014
(*Vision parse stores the string "null" as platform_hint*), T-0026 (*Platform is
recalled from game knowledge for classic re-releases, not read from the case*),
T-0028 (*unreadable channel reports a constant 3 japanese spines per photo*),
T-0033 (*Low-resolution photo answers NINTENDO where the hi-res photo answers
SWITCH*), T-0034 (*T-0007's zero-invented-titles guarantee does not hold at
1200×900*), T-0093 (*Detection.notes is asked for, parsed and persisted, and
displayed nowhere*)
**Reports:** `T-0007`, `T-0014`,
`T-0026`, `T-0028`,
`T-0033`, `T-0034`,
`T-0093`

## Context

The first stage of the pipeline asks a vision model to read the spines of game
cases out of a photograph and answer in JSON. Two constants carry that request:
`detectionPromptRules` and `detectionJsonSchema`, both in
`packages/shelfscan_core/lib/src/providers/vision.dart`.

Prompt text looks like documentation. It reads like English, it diffs like
English, and every instinct a programmer has says that tidying it — shortening a
rule, deleting a field nothing displays, grouping related sentences together —
is free. In this project every one of those instincts has been measured, and
each one was wrong.

## Decision

**Treat those two constants as instrumented code with a published measurement,
not as prose.** Concretely:

- No edit to either constant is made on taste, readability or symmetry. An edit
  is a change to a measured system and is re-measured against both control sets
  before it is kept (see [0004](0004-the-control-set-is-figures-not-a-file.md)).
- Nothing is removed from either constant because it appears unused. The cost of
  a removal is not paid where the removal happens.
- Wordings that were tried and measured flat or worse are recorded in the doc
  comments on those constants, so the next person does not retry them blind.
- The prompt has no per-provider copy. One text is sent to the local model and
  to every cloud endpoint, so a change made for one provider re-prices the
  control document of all of them.

## The measurement that settled it

Three independent findings, each reproduced more than once:

1. **Example values in the schema are copied verbatim into the model's answer.**
   Measured three separate times: a literal `"null"` string arriving as a
   platform hint (T-0014), and entries in the "could not read this spine" channel
   echoing the example text back (T-0028). This is why the schema is not
   illustrated with realistic-looking values.

2. **Adjacency matters more than length.** T-0026 added prose about console
   branding next to an unrelated rule about Japanese script, and broke the
   guarantee that the model never invents a title it cannot read — but only at
   the lower of the two control resolutions. T-0034 repaired it by moving one
   bullet and changing **zero characters** of text. A separate shortened variant
   still invented titles, which disproved "the prompt got too long" as the
   explanation. T-0033 then found that the same bullet's position also governs an
   apparently unrelated field, the platform hint.

3. **A field nothing reads still does work.** T-0093 removed `notes` from the
   schema — a field answered as an empty string on every row anyone had ever
   measured, and displayed nowhere in either interface. Removing it left every
   count intact and made one control photograph report fabricated unread-spine
   entries where the shipped schema reports none, reproducibly, five runs each
   way. A line in one object of the schema governs the contents of a different
   array.

The counts behind all three are in [`doc/measurements.md`](../measurements.md);
they are not repeated here.

## Consequences

- Editing the prompt is expensive by design. `test/control_set_test.dart`
  computes a fingerprint of the assembled prompt and fails `dart test` — on every
  machine, with no photographs, no model and no network — the moment either
  constant changes, with a message naming the document that must be re-measured.
- Because there is no per-provider prompt, a wording that would help one opt-in
  cloud model cannot be tried cheaply. T-0113 and T-0147 both priced a prompt
  change and both declined it for this reason; the arithmetic is in
  `doc/measurements.md`.
- The anti-invention guarantee is a property of the prompt **and** of near-greedy
  decoding. A prompt measured at another sampling temperature is a measurement of
  a different system — see [0003](0003-reproducibility-is-the-prompt-cache.md).
- Two people reading this repository will disagree about whether the prompt is
  well written. That is accepted. It is well measured, and the doc comments say
  what the alternatives cost.
