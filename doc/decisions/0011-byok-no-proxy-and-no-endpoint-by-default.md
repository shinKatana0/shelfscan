# 0011 — The project ships no credentials, runs no proxy, and never makes a remote endpoint the default

**Status:** accepted, 2026-08-13, corrected 2026-08-15
**Tasks:** T-0010 (*App settings screen + API keys in flutter_secure_storage*),
T-0016 (*README and onboarding for the two BYOK setup paths*), T-0058 (*Settings
screen does not warn that Anthropic cloud sends photos off the machine*), T-0069
(*README still says --fallback re-reads only the photos with unreadable spines,
understating the upload*), T-0070 (*The privacy warning no longer tells the user
what to do about it*), T-0076 (*Scan screen renders no privacy notice until the
backend switch is touched*)
**Reports:** `T-0010`, `T-0058`,
`T-0069`, `T-0076`

## Context

The pipeline needs two kinds of remote service: a vision model to read the
photographs, and a games database (IGDB, authenticated through Twitch) to resolve
the titles. Both cost money or registration. The obvious product decision — the
one nearly every comparable tool makes — is to embed a key, or to stand up a
small proxy so that users can simply install the thing and run it.

The input to this pipeline is photographs of the inside of someone's home.

## Decision

**Bring your own key. The project ships no credentials and operates no server.**
Two supported paths:

- **keyless** — the local vision model plus CSV export, which requires no
  registration with anyone and is the default on Windows;
- **full functionality** — the user registers their own application for the games
  database and supplies their own vision key.

Around that:

- **No remote endpoint is ever a default, and choosing one must warn** — at the
  point of selection (the settings screen, the command-line usage text), never in
  a document nobody opens. Android is cloud-only by platform necessity and is
  warned on the first frame, before anything is tapped.
- Keys live in environment variables (CLI) or the operating system's keychain
  (app), never in a file inside the repository. The example environment file is a
  list of variable *names*; nothing loads it.
- The warning text has exactly **one** definition, and the question "should this
  be warned about?" is answered by the same policy object that decides which
  backend the run will actually use.

The reasoning, recorded so it is not relitigated for convenience: a secret
embedded in a distributed client is not a secret — it is extractable from the
binary, including when supplied as a compile-time define or an asset. The games
database's terms of service forbid sharing a client secret. And a shared proxy
would make this project the processor of other people's photographs of their
homes, which contradicts the one-line description of what it is: a companion
utility with no database and no catalog interface.

## What settled it

This is the one record in this registry whose fourth section is mostly an
argument rather than a number, and it is here because it is the decision that
shapes the product most. What is measured is the *failure mode*, twice, and both
times it was the documentation rather than the code:

- **T-0069 — "local" does not mean "offline".** The README stated that on the
  keyless path images never leave the machine. That is false. A local run POSTs
  every photograph to a URL the user can set; aimed at a box on the local
  network, it ships the photographs there over plain HTTP. The same task found
  the fallback option's description understating the upload by a large factor.
  **Keyless is not the same claim as offline, and the documentation must not
  conflate them.**
- **T-0076 — a warning that is not on screen is not a warning.** The scan screen
  rendered no privacy notice until the backend switch was *touched*, so a phone
  launch and a restored cloud preference both reached the scan button unwarned.

Both are the same defect class as
[0012](0012-what-is-dropped-is-named-never-counted.md): the user cannot correct
what they are not told.

The guard against the fix eroding is mechanical. A test walks every Dart file in
the application for the clause the warning constants share and requires exactly
one hit, in the file that owns the policy; it was verified to fail as intended by
pasting a second copy elsewhere. The widget tests assert the rendered string
*equals* the constant, so a paraphrase fails rather than a substring check
passing on both. This exists because the previous version of the screen carried
its own hand-written paraphrase of the warning, and the two had already drifted.

## Consequences

- First-run cost is higher than a competitor's, and the project accepts that. The
  keyless path is what makes it tolerable: a user who wants nothing to leave
  their machine registers with nobody.
- The two warnings differ in wording because the risks differ. A paid vendor
  account is told the photographs are uploaded; an arbitrary endpoint is told that
  as well as that free tiers are commonly funded by training on what is submitted
  to them, and that these are pictures of a home.
- The question is asked against a *copy* of the pending settings, so asking does
  not persist a choice the user has not saved — and it routes through the same
  policy that decides the effective backend, so a phone holding a restored
  desktop preference is warned about the backend it would really run rather than
  the one stored.
- The same reasoning is why no scan output of the control photographs is
  committed to this repository; see
  [0004](0004-the-control-set-is-figures-not-a-file.md).
- A cloud model has been measured to be materially better at part of this job
  ([0005](0005-resolution-is-the-lever-not-the-model.md)). It is still not the
  default, and this decision is why.
