# 0002 — The vision prompt is a measured artifact, not a piece of writing

**Status:** accepted, 2026-08-13, reinforced through 2026-08-16

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
   platform hint, and entries in the "could not read this spine" channel
   echoing the example text back. This is why the schema is not
   illustrated with realistic-looking values.

2. **Adjacency matters more than length.** Prose about console
   branding next to an unrelated rule about Japanese script broke the
   guarantee that the model never invents a title it cannot read — but only at
   the lower of the two control resolutions. Moving one bullet without
   changing its text repaired the regression. A separate shortened variant
   still invented titles, which disproved "the prompt got too long" as the
   explanation. The same bullet's position also governs an apparently
   unrelated field, the platform hint.

3. **A field nothing reads still does work.** `notes` was always empty and
   displayed nowhere, yet removing it from the schema changed a control
   answer: the model reported fabricated unread-spine entries where the
   shipped schema reports none, repeatedly under the same sampling settings. A line in one object of the schema governs the contents of a different
   array.

The qualitative conclusions are in
[`doc/measurements.md`](../measurements.md), "Control-photo methods and
conclusions".

## Consequences

- Editing the prompt is expensive by design. `test/control_set_test.dart`
  computes a fingerprint of the assembled prompt and fails `dart test` — on every
  machine, with no photographs, no model and no network — the moment either
  constant changes, with a message naming the document that must be re-measured.
- Because there is no per-provider prompt, a wording that would help one opt-in
  cloud model cannot be tried cheaply. Two prompt experiments were priced
  and declined for this reason; see
  `doc/measurements.md`.
- The anti-invention guarantee is a property of the prompt **and** of near-greedy
  decoding. A prompt measured at another sampling temperature is a measurement of
  a different system — see [0003](0003-reproducibility-is-the-prompt-cache.md).
- Two people reading this repository will disagree about whether the prompt is
  well written. That is accepted. It is well measured, and the doc comments say
  what the alternatives cost.
