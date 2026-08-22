# 0001 — The pipeline is pure Dart; every platform capability crosses the boundary as a value

**Status:** accepted, 2026-08-13, tested continuously since
**Tasks:** T-0003 (*Photo pre-segmentation into strips*), T-0004 (*Alias table as
data file + IGDB alternative_names*), T-0025 (*Accept HEIC photos on input*),
T-0031 (*CLI: convert HEIC via Windows WIC before the vision stage*), T-0155 (*A
scan can only begin from photographs: the pipeline has no seam for a source that
produces detections directly*), T-0177 (*GOG Galaxy keeps the whole owned library
in a local database*)
**Reports:** `T-0003`, `T-0004`,
`T-0025`, `T-0031`,
`T-0177`

## Context

The product ships as two things over one pipeline: a command-line tool used as
the validation harness, and a Flutter application for Windows and Android. The
pipeline itself — read photographs, deduplicate, resolve against a games
database, assemble a document — is the same work in both.

Android is the constraint that makes this more than a preference. A file the
user picks there does not necessarily have a stable path; a native library
compiled for a desktop is not present; a format the desktop can decode may have
no decoder at all. Anything the pipeline does *for itself* has to be possible in
the least capable of its hosts.

## Decision

**`packages/shelfscan_core/lib` is pure Dart with one runtime dependency
(`http`), imports neither Flutter nor `dart:io` nor `dart:ffi`, and never reads a
file, writes a file or opens a device.** Everything platform-specific belongs to
a shell — `bin/` for the CLI, `app/lib/` for Flutter — and reaches the pipeline
as a plain value:

- photographs arrive as bytes (`PhotoInput`), never as paths;
- exporters return strings; saving them is the shell's job;
- the alias table is handed to the resolver as a parsed map, because the resolver
  may not read the file itself — the CLI reads it from disk, the app loads the
  same file as a bundled asset;
- HEIC images are converted to JPEG by the shell before the pipeline sees them;
- a non-photographic source of games — a folder of installers, a storefront's
  local library database — is enumerated and read by the shell, which hands the
  pipeline a `SourceEntry` of name, container and text (see
  [0009](0009-a-photograph-is-one-origin-of-four.md)).

**A second rule travels with the first: a dependency has to pay for itself.**
The default answer to "add a package" is no, and the alternative is priced before
the package is added.

## The measurement that settled it

Two additions were priced rather than assumed, five months of project time
apart, and both came out against the package:

- **Image manipulation (T-0003).** Splitting each photograph into overlapping
  strips before the vision call was implemented and measured. It found no
  additional item, invented titles the whole-photo read got right, and lost every
  platform hint — the numbers are in `doc/measurements.md`, "Pre-segmentation,
  measured and rejected". The relevant part for this decision is the second
  finding: the `image` package the cropping needed pulls in six transitive
  packages, and it bought nothing. The feature was reverted and core stayed
  `http`-only.
- **SQLite (T-0177).** Reading the storefront's library database looked like it
  required a SQLite package — the brief for that task asserted it outright.
  It does not. `dart:ffi` is in the SDK, and Windows has shipped the SQLite
  engine itself since Windows 10 1803, so the shell opens the system library
  directly and binds ten functions. Not even an FFI helper package is needed,
  because the allocator comes from the library already open. Measured cost: zero
  new packages, zero transitive packages, zero bytes added to the Android build,
  and no additional build step. The rejected alternative would have compiled
  SQLite into the Android build for a feature that cannot exist on Android — the
  storefront client does not run there.

The boundary itself is not a convention that people remember. It is asserted by
tests in `packages/shelfscan_core/test/`: nothing under `lib/` imports
`dart:io`, nothing under `lib/` imports `dart:ffi`, and the package's declared
dependencies parse to exactly `['http']`. The second of those was added by
T-0177 precisely because the first would not have caught it — `dart:ffi` is not
`dart:io`, and the guard that existed would have let the violation through.

## Consequences

- The same pipeline runs unchanged in a terminal and on a phone, and the go/no-go
  quality checks were all taken through the CLI before any interface existed.
- The price is **duplication in the shells**, and it is paid honestly rather than
  argued away. The HEIC converter exists in both shells; so does the database
  reader, at about 190 lines. Both duplications are guarded by tests that assert
  the two copies agree — the app's and the CLI's readers must declare identical
  SQL, the same schema version and the same default path — so a divergence fails
  the suite rather than surfacing as a bug on one platform.
- A capability the shell cannot provide degrades to a **named** skip rather than
  a silent one. HEIC on a host that cannot convert it is reported to the user by
  filename (see [0012](0012-what-is-dropped-is-named-never-counted.md)).
- Adding a new kind of input is a shell change plus a small pure-Dart class, and
  never a change to the orchestrator.
- The rule is stated so it can be broken deliberately if it ever stops paying.
  So far each attempt to break it has been priced and has come out against.
