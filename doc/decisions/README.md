# Decision records

Fourteen decisions that a competent reader, looking at this code, would ask
*why is it like this* about — and whose answer is not the obvious one.

Each record has four sections: the context, the decision, **the measurement that
settled it**, and the consequences. The fourth section is the reason this
registry is worth reading and the reason it is short. This project measured
almost everything it argued about, so a decision that cannot point at a
measurement is usually not a decision at all — it is a preference, or a bug fix
wearing a decision's clothes.

## What is not here

Around two hundred tasks have closed in this repository. Most were fixes, and a
registry of everything would be the backlog again. Specifically excluded:

- **Bug fixes**, however involved. The line drawn: a fix restores behaviour the
  code already claimed; a decision changes what the code claims. Several fixes
  *produced* the decisions below, and they are cited inside them.
- **Decisions already stated where a reader will find them.** The canonical
  intermediate document, the pinned external export format, the
  orchestrator/worker shape and the retry policy are in
  [`ARCHITECTURE.md`](../../ARCHITECTURE.md); what the product is and what it
  deliberately does not do is on the [front page](../../README.md); what a
  change must not break is in [`CONTRIBUTING.md`](../../CONTRIBUTING.md). This
  directory is for what was *not* findable.
- **Numbers.** They live in [`doc/measurements.md`](../measurements.md), which
  also records everything this project measured and then decided **not** to do.
  A record here cites a section of it rather than copying figures out of it —
  two copies of a number drift, and a number whose sentence changed in transit is
  one nobody can check again. Where a single figure is the crux of an argument it
  appears once, next to its pointer.

Every record opens with the task ids it came from, under **Tasks** and
**Reports**. Those are bare ids and not links on purpose: a task id such as
`T-0086` names an entry in the working record this repository keeps but does
not publish — the briefs, the worker reports and the board are development
artefacts, not product, and they quote conversations verbatim. What survives here
is what they produced: this registry for the reasoning,
[`doc/measurements.md`](../measurements.md) for the figures, and
[`ARCHITECTURE.md`](../../ARCHITECTURE.md) for the shape. **Nothing on this
page depends on looking one up.** The ids are kept because they are stable
names for a decision, and because a claim that names its origin is checkable by
anyone who ever does hold that record.

## The records

| # | Decision | In one line |
|---|---|---|
| [0001](0001-the-platform-boundary.md) | The pipeline is pure Dart; platform capabilities cross as values | The core has one dependency and touches no file, no device and no operating system — the shells convert, read and save, and hand it plain values. |
| [0002](0002-the-prompt-is-a-measured-artifact.md) | The vision prompt is a measured artifact, not writing | Moving one bullet and changing zero characters of text broke — and later restored — a correctness guarantee, so the prompt is edited only against a measurement. |
| [0003](0003-reproducibility-is-the-prompt-cache.md) | Reproducibility is the prompt cache, not a freshly loaded model | The first explanation of why two identical scans disagreed was wrong and stood for two days; what actually decides it is what the inference server had cached. |
| [0004](0004-the-control-set-is-figures-not-a-file.md) | The control set is a definition and a manifest, not a committed document | The photographs are someone's home, so what is committed is the figures a scan must produce — and a test that fails everywhere the moment the prompt drifts from them. |
| [0005](0005-resolution-is-the-lever-not-the-model.md) | Buy quality with pixels, not with a bigger model | Three "just use a bigger model" arguments were priced and two failed outright; the one that worked is still not the default. |
| [0006](0006-a-platform-hint-has-a-measured-width.md) | A platform hint is a lookup with a measured width | Whether a console hint means one database id or several is decided by counting how much the platforms' catalogues actually overlap — and it came out differently for the desktop, the Switch and the handhelds. |
| [0007](0007-the-resolver-refuses-what-it-cannot-decide.md) | The resolver refuses what it cannot decide | Ties are never broken by whichever row the database returned first; they go to a human, and the one exemption to that was measured to cost nothing. |
| [0008](0008-an-exact-id-skips-every-gate.md) | An exact product id skips every gate | The gates exist to make a guess safe; a store's own product id joined to the database one-to-one is not a guess, and it wins rows no string match could. |
| [0009](0009-a-photograph-is-one-origin-of-four.md) | A photograph is one of four origins a row can have | Installed games and a storefront's library enter the same pipeline as text, through the same boundary as the photographs, and merge into one document. |
| [0010](0010-copy-the-database-before-reading-it.md) | Copy the database before reading it | Opening another program's SQLite file read-only *and immutable* looks like the careful choice; it is the one that silently answers a stale number. |
| [0011](0011-byok-no-proxy-and-no-endpoint-by-default.md) | No shipped credentials, no proxy, no endpoint by default | An embedded key is not a secret and a shared proxy would make this project the processor of other people's photographs of their homes. |
| [0012](0012-what-is-dropped-is-named-never-counted.md) | What is dropped is named, never counted | This project's most-filed defect class is silence; and where an exact count is not available the interface states a bound rather than inventing a number. |
| [0014](0014-stay-in-0-x-until-the-two-file-formats-stop-moving.md) | Stay in 0.x until the two file formats stop moving | `*.review.json` and which rows reach `.xcoll` have both changed shape this month, and no document written by one version has yet been loaded by another. |
| [0015](0015-the-kind-of-work-is-a-property-of-the-row.md) | The kind of work is a property of the row, not of the run | The export target is a mixed-media manager and the models already answer a mixed shelf, so a games-or-anime mode would only be discarding rows that were read correctly. |

**0013 is not missing.** It records how this project's own working record is
organised, which is development rather than product, so it stays with the board
and the briefs on a private disk. Numbers are never reused.

## Adding one

A new record is written when a decision is *taken*, in the same pass that takes
it, and it needs three things: a task it came from, a measurement that settled
it, and a reader who would otherwise be surprised. If the record cannot be
written without re-deriving something, that is a sign it belongs in the archive
and not here. Number it in sequence; never renumber an existing one.
