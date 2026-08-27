# 0010 — Copy the GOG Galaxy database before reading it, because the inert-looking option is the one that loses data

**Status:** accepted, 2026-08-16
**Tasks:** T-0177 (*GOG Galaxy keeps the whole owned library in a local
database, and we read only what is installed*)
**Report:** `T-0177`

## Context

A user's PC games are not all on the shelf and not all installed. GOG Galaxy —
the storefront client — keeps the entire *owned* library, installed or not, in a
SQLite database on the local disk. Reading it turns a handful of installed
folders into the user's whole PC collection.

The database belongs to a program this project does not control, and that
program is normally running while the scan happens. SQLite offers what looks
like exactly the right pair of options for that situation: open the file
read-only (`mode=ro`), and additionally declare it immutable (`immutable=1`) so
that SQLite takes no locks at all and cannot disturb the other process. The
second flag reads like the more careful of the two.

## Decision

**Copy the database file *and its write-ahead log* to a temporary directory,
then open the copy read-only.** Never open the live file, and specifically never
open it with `immutable=1`.

Around that:

- the copy is checked with `PRAGMA quick_check` and remade once if the check
  fails; a second failure is a named exception, not a fallback;
- the library's "as of" timestamp is taken from the later of the two files'
  modification times, because under a write-ahead log they can be far apart;
- zero rows read out of a database that exists is treated as a failure, not as
  an empty library.

## The measurement that settled it

All three options were run against a real Galaxy installation while
Galaxy was running and had written to its log since the last checkpoint. The
table is in the working record; the result is:

- `mode=ro` sees the log, and touches the original (the shared-memory file's
  timestamp moves).
- `mode=ro&immutable=1` **does not see the log at all** — it reports the
  database as using a different journal mode entirely — and so answered **fewer
  rows of the metadata table than the database held**, short by exactly what the
  log carried. No error, no warning, and nothing the caller could inspect to
  discover it.
- Copying both files and opening the copy sees the log and leaves the original
  untouched.

Two honest limits, which T-0177 states about itself and which are repeated here
because a registry that only carries the flattering half of a measurement is not
worth reading. First, the rows the immutable open dropped were rows of a
metadata cache table, not library rows and not games: the library tables
answered the same count under both opens, so the mechanism is measured and the
loss to *this feature* was not observed. Second, `mode=ro` did not actually
block against the running client, so the locking hazard that rules it out is
argued rather than observed. What is measured is the direction of the failure: the option that
looks safest is the one that answers a stale number confidently.

## Consequences

- Every scan of the library pays one copy of a few megabytes. In the Flutter app
  that is long enough to matter, so the read runs on a separate isolate.
- A torn copy is bounded rather than eliminated. SQLite discards log frames whose
  checksums fail, which degrades a torn log to an older *consistent* view rather
  than a wrong one; `PRAGMA quick_check` covers the main file, which that
  property does not.
- The reasoning is written at the call site as well as here, because the next
  person to touch this code will have the same instinct that `immutable=1` is
  the careful choice. Reasoning "read-only plus immutable is obviously safest"
  would have shipped a silently stale library, and nothing else in the code
  would have contradicted it.
- This is the project's clearest instance of a general rule it holds elsewhere:
  **a silent wrong answer is worse than a loud failure** (see
  [0012](0012-what-is-dropped-is-named-never-counted.md)). Here the rule decided
  a database connection string.
