# 0003 — What makes a run reproducible is the prompt cache, not a freshly loaded model

**Status:** accepted, 2026-08-15
**Tasks:** T-0053 (*Two identical scans of the same photos do not agree: the
vision call is sampled, not measured*), T-0086 (*A scan at temperature 0 is not
byte-reproducible*), T-0092 (*dedupeDetections' doc comment still credits the
typography difference to a freshly loaded model*), T-0098 (*Four more comments
still call the first-ask/repeat typography the cold/warm difference*), T-0106
(*CONTROL-HIRES unreadable = 0 is not reproducible*), T-0119
(*control_set_test's unreadable assertion names no cause*)
**Reports:** `T-0053`, `T-0086`,
`T-0092`, `T-0098`,
`T-0106`

## Context

Every quality figure in this project is a count taken from a model's answer to a
photograph. If two runs of the same photograph disagree, no figure means
anything and no prompt change can be evaluated.

Two identical scans did disagree. The first explanation was the obvious one: the
model had just been loaded into memory for one of the runs, so a "cold" model
answers differently from a "warm" one. That explanation was written into a doc
comment, into the project's front page and into the resolver's own
justification, and it stood for two days. It is wrong.

## Decision

**Reproducibility is a property of what the inference server has cached, and it
is stated as a condition on every figure rather than assumed.** Three parts:

1. The request states its own sampling. `OllamaVisionProvider` sends
   `temperature: 0` and a fixed seed rather than relying on the server's or the
   model file's defaults, and the cloud providers state their sampling too.
2. Every claim of *byte* identity carries the condition under which it holds —
   a server that has already answered these photographs, serving one request at
   a time. Claims about *counts* do not need it.
3. A measurement run drops the cache first (`ollama stop`) so that it is taken in
   a known state, and that line is part of the control set's documented
   regeneration recipe.

## The measurement that settled it

Recorded in full in `doc/measurements.md`, "What temperature 0 actually bought
(T-0086)" and "A third cache state, and the counted figure that moves in it
(T-0106)". The shape of it:

- Before any of this, nothing in the repository asked for the sampling that every
  figure depended on. The answers came back nearly greedy anyway, because the
  model's own model file happened to carry a near-zero temperature — a file
  nobody here controls. T-0053 found that and pinned the request.
- T-0086 then re-measured against a server started for the measurement, with its
  own request log accounting for every request served. Repeat runs were
  byte-identical. Runs with the cache dropped were byte-identical *to each other*
  and differed from the repeats on a handful of rows of one photograph — letter
  case, trademark signs, one diacritic; no count, no item and no hint moved. Runs
  deliberately overlapped with a second process were byte-identical to the
  isolated ones, which is what eliminated concurrency as the cause on that
  configuration.
- The mechanism is visible in the server's own log: the number of cached prompt
  tokens is near-total on a repeat and near-zero on a first ask, so a repeat skips
  the prefill and is not the same arithmetic. Stopping the model correlates only
  because it discards the cache along with the model.
- T-0106 found a **third** state, which is the one that matters in practice: the
  cache matches a token prefix, so scanning the control photographs under a
  changed prompt puts every photo of the second pass into a state that is neither
  a first ask nor a repeat. That is exactly what a prompt A/B test is. In that
  state one counted figure moves — a photograph hand-counted at zero unread
  spines answers a small number of phantom entries — and where in the prompt the
  change sits does not predict whether it happens.

## Consequences

- The wrong explanation had to be retracted from six places once it was
  disproved (T-0092, T-0098, T-0119). The retraction is itself part of the
  record: `doc/measurements.md` keeps the superseded claim visible with the
  condition it was missing, rather than quietly correcting it.
- Anyone running a prompt comparison must drop the cache between passes, or the
  comparison lands in the third state and one of its figures is not the prompt's
  doing. This is one line, and it is why it is written into the recipe rather
  than into someone's memory.
- Figures taken before 2026-08-15 are readable but not all of them are
  reproducible; `doc/measurements.md` says which class each belongs to. The
  resolver's own numbers were re-taken (see
  [0007](0007-the-resolver-refuses-what-it-cannot-decide.md)).
- Two hidden dependencies of this kind are now known — the model file's own
  temperature, and the server's parallelism setting — and neither is something
  this repository sets. They are named in the archive so a figure taken on
  someone else's machine can be read correctly.
