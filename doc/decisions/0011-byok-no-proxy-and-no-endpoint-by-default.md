# 0011 — The project ships no credentials, runs no proxy, and never makes a remote endpoint the default

**Status:** accepted, 2026-08-13, corrected 2026-08-15; **the Android half of
one clause narrowed 2026-08-24** — see "The Android clause, narrowed" below
**Tasks:** T-0010 (*App settings screen + API keys in flutter_secure_storage*),
T-0016 (*README and onboarding for the two BYOK setup paths*), T-0058 (*Settings
screen does not warn that Anthropic cloud sends photos off the machine*), T-0069
(*README still says --fallback re-reads only the photos with unreadable spines,
understating the upload*), T-0070 (*The privacy warning no longer tells the user
what to do about it*), T-0076 (*Scan screen renders no privacy notice until the
backend switch is touched*), T-0361 (*The phone cannot point at the desktop's
Ollama, which is what would make Android useful without a key*), T-0362 (*Three
documents still say Android is cloud-only*)
**Reports:** `T-0010`, `T-0058`,
`T-0069`, `T-0076`, `T-0361`, `T-0362`

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
  *(The first half of that sentence is what was narrowed on 2026-08-24; the
  second half was checked separately and still holds. Both are below.)*
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
  *(There are three of them since 2026-08-24; see the amendment below.)*
- The question is asked against a *copy* of the pending settings, so asking does
  not persist a choice the user has not saved — and it routes through the same
  policy that decides the effective backend, so a phone holding a restored
  desktop preference is warned about the backend it would really run rather than
  the one stored.
  *(The second clause described a substitution that no longer happens; the
  amendment below says what replaced it and why.)*
- The same reasoning is why no scan output of the control photographs is
  committed to this repository; see
  [0004](0004-the-control-set-is-figures-not-a-file.md).
- A cloud model has been measured to be materially better at part of this job
  ([0005](0005-resolution-is-the-lever-not-the-model.md)). It is still not the
  default, and this decision is why.

## The Android clause, narrowed 2026-08-24 (T-0361, recorded by T-0362)

**What is narrowed:** *Android is cloud-only by platform necessity*, in the
first clause of the Decision above. It is not cloud-only, and the necessity
was never about the network.

What is necessary, and unchanged, is that **the phone runs no vision model of
its own**: on-device models are too weak for shelf spines, which is measured
and stands exactly as it stood.
What the clause was read as implying is a different sentence — that the only
model an Android app could reach was somebody's cloud. That never followed. A
model on the local network was always reachable, and since T-0361 the app
reaches one: `VisionBackend.local` is offered on both platforms, and on a
phone it means an Ollama the user names on their own network, characteristically
the same desktop, the same model and the same hardware the desktop app already
talks to.

**Two claims about two machines, and neither settles the other.** A reader who
leaves this record believing the on-device measurement was overturned has been
misinformed by its correction — and would then find no stated reason for the
thing that measurement is the reason for, which is that this project promises
no recognition on the phone itself.

**What is not narrowed, and it is the other half of the same sentence:**
*warned on the first frame, before anything is tapped*. It was checked on its
own, because two claims in one sentence can fail apart. It holds — and by a
different route from the one it was written for.

- It was true because every backend the phone offered was remote, so there was
  no local case for the first frame to be silent about.
- It is true now because every backend the phone offers still leaves the
  device. Local acquired a warning of its own there; the phone's default is
  still the cloud, which T-0361 deliberately did not move; and the scan screen
  still composes its notice from the policy when it builds rather than when the
  switch is touched, which is the T-0076 fix this record already turns on.
- What would have broken it is precisely what was not done: making local the
  Android default, or offering it as a backend with nothing to say. Local on a
  phone is not "nothing leaves this machine" — it is T-0069's correction made
  visible on a platform instead of merely true — so a silent local backend
  would have been a first frame warning about nothing while the photographs
  crossed a network in the clear.

**The exception this clause carves is now a preference rather than a
necessity, which is a heavier thing to hold.** *No remote endpoint is ever a
default* has always had Android on the other side of it: the phone's default
is the vendor cloud. That used to be a consequence of there being nothing
else. There is something else now and it is still not the default — because a
default that cannot run until the user has typed an address is a broken first
launch, and because the order the backends are offered in is the owner's call
and not a task's. That reasoning lives on `ProviderPolicy.defaultBackend`, and
it is a reason of a different kind from the one this record originally gave.
Whoever revisits the Android default from here is arguing with a judgement,
not with a hardware limit.

**What the new path costs, stated here because this is the privacy record.**
Ollama speaks plain HTTP and this app wraps it in nothing, so on that path
every photograph crosses the user's own network **unencrypted and
unauthenticated**: anything else on that network can read it in transit. What
is bounded is the destination, not the exposure — nothing reaches the
internet. Both halves are in the warning shown where the backend is chosen and
in all three READMEs, because a guarantee stated only in a decision record is
stated to the wrong reader.

**And the third warning is why the count in the Consequences above moved.**
That section says "the two warnings"; there are three, and the new one is
local's. It exists because the first sentence of the other two is true on this
path as well, and a backend that said nothing would have been read as saying
that nothing happens.

**What replaced the substitution.** A Consequence above records that a phone
holding a restored desktop preference is warned about the backend it would
*really* run rather than the one stored. That downgrade is gone: a stored
`local` preference is now honourable on a phone, so answering a different
question than the one asked would be the defect rather than the fix. What such
a restore actually carries onto the phone is the desktop's loopback address,
and that is refused by name, at the tap, as a blocker the user can read — in
place of a silent substitution they could not.

**Not exercised.** No phone has been pointed at a desktop Ollama through this
code. Everything above is what the code and its tests do, not a run anybody
has watched.

**Why this is an amendment and not an edit**, since a record silently updated
to match today loses the thing it is for: the practice here is
[0004](0004-the-control-set-is-figures-not-a-file.md)'s — the earlier sentence
is left standing rather than rewritten, so that both readings are legible, and
what changed is dated, attributed to the task that changed it, and separated
into what moved and what did not.
