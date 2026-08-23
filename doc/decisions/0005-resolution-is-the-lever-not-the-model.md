# 0005 — Buy quality with pixels, not with a bigger model; and the model that does win stays opt-in

**Status:** accepted, 2026-08-14, re-confirmed 2026-08-16
**Tasks:** T-0074 (*The vision prompt does not ask for the Switch 2 band*),
T-0090 (*A cloud primary DOES report the spines it could not read*), T-0112
(*T-0074's Switch 2 band is read unprompted by a GPT-5 cloud model*)
**Reports:** `T-0090`, `T-0112`
**Measurements:** `doc/measurements.md` — "A bigger local model, measured and
rejected", "The Switch 2 band, measured and rejected as a prompt problem", "The
second lever works"

## Context

The first stage reads game titles off spines in a photograph. When it misses
items, there are three obvious things to buy: a bigger model, a better prompt, or
better input. Every team's instinct is to reach for the first.

## Decision

**Treat input resolution as the primary lever, hold the default at a small local
model, and require any model upgrade to be measured on both control sets before
it becomes anything more than an option.**

Specifically: the shipped Windows default is a 7-billion-parameter local model
running through Ollama; a cloud model measurably better at the job is available
but stays an explicit opt-in; and the user-facing guidance is about photographing
the shelf at a higher resolution.

## The measurement that settled it

- **Pixels work.** The same shelf at the lower control resolution yields a
  fraction of the detections it yields at the higher one, with a far weaker
  platform-hint rate. Nothing else changes — same model, same prompt. The
  figures are a count of a private collection and are in the working record
  rather than here (T-0246); what they show is in
  [`doc/measurements.md`](../measurements.md), "What the figures are measured on".
- **A bigger *local* model does not.** A 32-billion-parameter model of the same
  family was pulled and run on the same photographs with the same prompt. It does
  not fit the available video memory, so a quarter of it runs on the CPU: nine
  times slower, one photograph lost outright to a server error, and on the two it
  finished it matched the smaller model at best and transcribed Japanese worse.
- **A bigger *cloud* model did not either — at first.** "A cloud model will read
  the Japanese spines" was an assumption that had been repeated in briefs for
  days. T-0090 measured it: the model tested reports those spines as unreadable
  rather than reading them, returns fewer detections than the local model, and
  invents a title at the lower resolution that the local model gets right. The
  assumption was retired as false *for that model*.
- **Then one did.** T-0112 measured a newer cloud model on all five control
  photographs and it reads what thirteen prompt wordings could not, per spine and
  correctly, and passes the low-resolution set where every previous attempt
  invented titles. It also makes one invention of its own at the higher
  resolution, and introduces a new class of partial row. It costs roughly half a
  dollar per scan of a real shelf against zero locally.

The full tables, costs and per-photo counts are in `doc/measurements.md` and are
not repeated here.

## Consequences

- The default path is keyless and free, and the project's quality claims are
  quoted against it.
- The better model is selectable, not default — a decision reinforced by
  [0011](0011-byok-no-proxy-and-no-endpoint-by-default.md), since choosing it
  sends photographs of a home to a third party.
- Because the prompt has no per-provider copy
  ([0002](0002-the-prompt-is-a-measured-artifact.md)), a wording tuned for the
  cloud model would re-price the default provider's control document. Two tasks
  priced exactly that and both declined; the arithmetic, including how many runs
  a statistically meaningful comparison would need, is in `doc/measurements.md`.
- Three separate "just use a bigger model" arguments have now been priced and
  written down, so the fourth one starts from evidence instead of from instinct.
  That is the point of keeping the rejected measurements at all.
