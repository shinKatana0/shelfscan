# 0009 — A photograph is one of four origins a row can have, and authority is a property of the origin

**Status:** accepted, 2026-08-16
**Tasks:** T-0155 (*A scan can only begin from photographs: the pipeline has no
seam for a source that produces detections directly*), T-0157 (*GoG installs
carry authoritative metadata next to them, and nothing reads it*), T-0158 (*An
installer filename is a noisy title with a strong year hint, and nothing parses
it*), T-0160 (*Neither shell can point at a folder*), T-0173 (*One run cannot
cover photos and installs together*), T-0179 (*A run may have many sources*)
**Reports:** `T-0155`, `T-0157`,
`T-0158`, `T-0160`,
`T-0179`

## Context

The product began as "photographs in, collection file out". The recognition
stage was the vision model, and the only row that did not come from it was one a
human typed at review.

But a collection is not all on a shelf. PC games are installed in folders, and a
storefront client keeps the owned library — installed or not — in a local
database. Those name their games *exactly*: an installer writes the title into a
metadata file, and there is nothing to recognise. Running them through a vision
model would be absurd, and running them as a separate tool produces two documents
nobody can reconcile.

## Decision

**A detection has an *origin*, and there are four:** it was read off a
photograph, typed by a human, taken from metadata that names the game, or
inferred from a filename. A non-photographic source is a small pure-Dart class
that turns text into rows; there are three of them today, for store metadata, for
filenames, and for the storefront's library database.

Three parts to the seam:

1. **The shell enumerates and reads; the source parses.** A source is handed a
   `SourceEntry` — a name, the container it sat in, and its text content. No
   bytes, no path, no timestamp, no file handle. This is the same boundary the
   photographs cross ([0001](0001-the-platform-boundary.md)), and reading a
   source is deliberately *synchronous*: no pool, no retries, no network.
2. **A run takes a list of sources beside the photographs, and produces one
   document.** A shelf, a games folder and a storefront library go through one
   deduplication pass, so a game that is two of those is one row.
3. **Authority is a property of the origin, named once.** Metadata and manual
   entry are authoritative; a photograph read and a filename guess are not.

The routing between sources is done by the shell, which knows which source owns
which entry because it built the two lists from two different places. A composite
source that guessed from the *shape* of a name was considered and rejected: it
would be a guess about a namespace this project does not own, and it would have
misrouted a real entry that was measured.

## The measurement that settled it

- **The two non-photographic paths are not equally trustworthy, and one enum
  value would have hidden it.** A store's metadata file names the game because the
  installer wrote it there (T-0157, which verified that premise against real
  files before anything was built). A title cut out of
  `Game.Name.2019.RePack-GROUP` is a guess with nobody behind it (T-0158). Those
  are different claims, so they are different origins, and `isAuthoritative` is
  the axis every consumer branches on.
- **What authority actually decides was measured end to end.** A merge ranks
  candidates by completeness first, then authority, then photo yield, then
  confidence — authority sits above photo yield because a yield is a proxy for
  how legible a photograph was, and neither of the rows in question was
  photographed; it sits below completeness because a truncated title is no use to
  anyone whoever vouches for it. The proof is a test that runs the real CLI as a
  subprocess over a photograph of a game and a store install of the same game:
  **one row survives, and it is the authoritative one** — which is also the one
  carrying the product id that [0008](0008-an-exact-id-skips-every-gate.md)
  needs.
- **One document, not one command per combination.** Three inputs make seven
  non-empty combinations. Rather than grow commands, the rule adopted is that **a
  command may add sources that cost less than its own, never more**: the
  photograph command can add installs and the library, the install command can
  add the library, and the library command adds nothing. The commands that take
  no photographs are built on a pipeline that holds no vision worker at all, so
  they *provably* cannot make a vision call.
- **A folder can out-yield a photograph.** The per-photo yield statistic had to
  stop counting rows that came off no photograph, because a folder of installers
  produces more rows than the highest yield ever measured from a single
  photograph.

## Consequences

- The product's name is now slightly wrong, and that is accepted: it scans
  shelves *and* disks into one document.
- Authority changes two things and no more — which read wins a merge, and the
  confidence value a source row carries. It deliberately does **not** change what
  the resolver matches on; the resolver's special path keys on the presence of a
  store product id instead. A doc comment anticipates a third consumer that does
  not exist yet, and says so.
- Which source owns an entry is *stated by the shell*, never inferred from the
  entry.
- A source that is handed something it cannot use declines it, and a decline is
  named rather than counted; see
  [0012](0012-what-is-dropped-is-named-never-counted.md). That list is why a
  source returns a reading with two lists rather than a bare list of rows.
