# 0005 — Buy quality with pixels, not with a bigger model; and the model that does win stays opt-in

**Status:** accepted, 2026-08-14, re-confirmed 2026-08-16

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

- **More image detail helps.** The higher-resolution control read yields more
  usable detections and stronger platform hints under the same model and
  prompt. The private control results are summarized without owner-derived
  counts in [`doc/measurements.md`](../measurements.md), under
  "Control-photo methods and conclusions".
- **A larger local model did not improve the result.** It exceeded available
  video memory, ran more slowly and transcribed Japanese less reliably on the
  completed comparison. It is not a better default.
- **Cloud models differed.** An earlier model left difficult spines unreadable
  and introduced an invention. A newer model read the difficult platform band
  more reliably, while retaining its own errors and a paid, off-device path.
  That result supports an opt-in choice, not a default change.

## Consequences

- The default path is keyless and free, and the project's quality claims are
  quoted against it.
- The better model is selectable, not default — a decision reinforced by
  [0011](0011-byok-no-proxy-and-no-endpoint-by-default.md), since choosing it
  sends photographs of a home to a third party.
- Because the prompt has no per-provider copy
  ([0002](0002-the-prompt-is-a-measured-artifact.md)), a wording tuned for the
  cloud model would re-price the default provider's control document. Prompt
  comparisons were priced and declined; see the measurement archive for their
  method and limits.
- Three separate "just use a bigger model" arguments have now been priced and
  written down, so the fourth one starts from evidence instead of from instinct.
  That is the point of keeping the rejected measurements at all.
