# 0004 - Keep control photographs and their measurements private

**Status:** accepted

## Context

Vision quality claims need a stable control: the same inputs, prompt and
sampling settings must be used when comparing results. A review document made
from photographs of a home is also an inventory of that home. Publishing the
photographs, their original names, file metadata, detections, platform mix or
result counts would expose information about its owner.

A public test still needs to detect when the prompt changes underneath the
measurements used to justify it.

## Decision

**Keep the control definition and results beside the private photographs.**
The local definition identifies the inputs and expected results, and the
capture is reused when it is fresh. A capture that cannot be verified is
considered absent. Neither a control review document nor figures derived from
those photographs belong in the public repository.

The public [`control-set manifest`](../control-set-manifest.md) contains only
stable set identifiers and the assembled prompt's fingerprint. It contains no
photo list, device metadata, result counts or platform mix. The prompt check
runs on every machine without photographs, a model or a network connection.
Checks that need the private inputs run only where those inputs are present and
otherwise skip with a reason.

## Evidence

The prompt once changed while its published measurements stayed in place, and
a lower-resolution regression went unnoticed. Comparing a fingerprint of the
assembled prompt with the public manifest makes that drift a failing test.
Changing the fingerprint requires remeasuring the private control; merely
updating the stored value would make stale measurements look current.

A review document would provide a convenient test fixture, but it would also
publish the titles read from the photographs. Counts and exhaustive platform
hints are not safe substitutes: together they can reveal a collection's size
and the kinds of items in it. The prompt fingerprint has no such dependence on
the contents of the photographs.

## Consequences

- A fresh clone can verify prompt stability, but cannot reproduce the private
  control results. The distinction is explicit in the tests.
- Local checks compare the named inputs, capture and expected results only on
  a machine that has the private control data.
- Public tests of accepted platform-hint strings use the static
  `platformIds.keys` vocabulary. The check against what a real model returned
  remains local to the private control.
- A prompt change fails `dart test` until the control is remeasured and the
  fingerprint is deliberately updated.
