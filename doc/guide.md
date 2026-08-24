**English** · [Русский](guide.ru.md) · [日本語](guide.ja.md)

<!-- TRANSLATIONS — read this before you edit the text below.
     guide.ru.md and guide.ja.md make the same claims as this file. Change
     anything here beyond a typo and both are stale. In the same commit either
     update them, or set the "Translated from" line at the top of each to
     STALE. The rule in full, and why there is no CI check for it, is one
     place only: ../README.md, "Translations". -->

<!-- TRANSCRIPTS. Some blocks below are program output and are pinned, byte
     for byte, against a real run of the command: they carry a marker of the
     form "transcript: NAME" in an HTML comment directly above them. The test
     is packages/shelfscan_core/test/guide_transcript_test.dart. Change one of
     those blocks, or the string the program builds, and it fails until the
     two agree again. That file also lists the output blocks it does NOT pin,
     and why. -->

# shelfscan — one complete run

This page walks one run from nothing to a collection imported into Tonkatsu
Box, in the order you actually do it. Each decision is explained where it
comes up rather than listed at the top, and every step says what can go wrong
and what the program says when it does — those sentences are the product, and
recognising one is usually the whole fix.

What you end up with: a `.xcoll` file Tonkatsu Box imports, or a `.csv` any
spreadsheet reads. shelfscan owns no catalog and no database. It recognises
your shelf and hands the result to an app that does.

There are two ways through, and the first step of the guide is really choosing
between them:

- **Keyless.** A local vision model and a CSV export. No registration
  anywhere, nothing paid, no key. This is the default on Windows.
- **Full.** The same scan plus an IGDB key, which is what makes `.xcoll`
  possible — that format carries IGDB ids and nothing else, so an item with
  no id cannot be in the file at all.

You can start keyless and add the key later: the key affects one stage, and
that stage can be re-run on its own over a scan you have already paid for.

---

## Before you start

The tested host is **Windows**. The pipeline itself is plain Dart and platform
independent; two things in this guide are not, and both are called out where
they arise (HEIC conversion, and the GOG Galaxy library).

You need the Dart SDK. Then, once:

    cd packages/shelfscan_core
    dart pub get

**Every command below is run from `packages/shelfscan_core`.** The CLI is also
commonly run from the repository root, which is exactly why it echoes every
path back to you *absolute and normalised* rather than as you typed it: a
relative path such as `../../photos` is right from one of those two
directories and wrong from the other, and the unexpected absolute path in the
error message is the whole answer.

To see the command surface at any point, run the tool with no arguments:

    dart run shelfscan_core:shelfscan

That usage text is the authority. If this page and that text ever disagree,
the text is right.

---

## Step 1 — Photograph the shelf

**Resolution is the lever.** This is the single biggest thing you control, and
it is measured on a real shelf: the same shelf photographed at 4000×3000
gives **well over twice** the detections the same two photographs give at
1200×900.
Same model, same prompt, nothing else changed. Every attempt this project made
to buy quality with a bigger model failed; every attempt to buy it with pixels
worked.

Those two figures are the project's standard control sets, `CONTROL-LOWRES` and
`CONTROL-HIRES` — the same shelf, twice, at those two resolutions. They are
private photographs and are not published, so what you can read is what they
produce: [`measurements.md`](measurements.md) quotes the figures they settled,
each against the set it was measured on.

So, practically: shoot at your phone camera's full resolution and do not let a
messaging app downscale the file on its way to the PC. Fill the frame with
spines. A column the frame cuts off is still read, and the fragments it
produces are honest partial reads rather than inventions — but they are
fragments, so it is cheaper to include the whole column.

**But do not put the whole shelf in one frame — that is the other lever, and
it runs the opposite way.** Resolution is free; spines per frame are not. The
local `qwen2.5vl:7b` was measured against synthetic shelves of increasing
density, and there are two thresholds on the way up:

- **Somewhere past forty spines in one frame it starts leaving spines out and
  telling you nothing about it.** The answer parses, no title is invented, and
  the missing ones are simply absent. The `unreadable` list stays empty, so
  there is no banner and no count — this is the one loss in the whole tool
  that does not announce itself, and the only defence against it is knowing
  the number of spines you photographed.
- **Further up it stops answering at all.** Instead of reporting what it
  cannot read, the model repeats what it already read, over and over, until it
  runs out of room. That run takes minutes and yields nothing — either an
  answer that breaks off part-way, or a wall of near-identical entries the
  scan declines whole rather than putting invented-looking rows in your review
  list. Both failures name the shelf and tell you to photograph it in
  sections; this is why.

**So: two or three sections rather than one wide shot.** It costs one extra
vision call per section and nothing else — the sections go through one dedupe,
so a spine that appears in both overlapping frames is still one row. A cloud
model holds far more in one frame than the local 7B does; if you are scanning
locally, the sections are what buy you the whole shelf.

Numbers, the ladder they came off and the two failure texts:
[`measurements.md`](measurements.md), "The 7B's density ceiling".

**What is read.** JPEG, PNG and WebP. Each file is identified **by its
contents, not by its name**, so a HEIC that your phone or a messaging app
renamed `.jpg` is still recognised as HEIC and converted, rather than being
uploaded as a broken JPEG.

**HEIC** — the phone camera default — is accepted **on Windows**: each file is
converted to JPEG in a temp directory before the scan, and nothing is written
next to your originals. Anywhere else, and when the Windows HEIF extension is
missing or the conversion fails, the file is named on stderr with the reason
and skipped. Never dropped in silence; convert it to `.jpg` yourself and
re-run.

Put the photographs in a directory of their own. `scan` takes the directory,
not a file.

### What can go wrong

**A file in the directory is not a photo.** One line per file, then a banner —
not a count folded into the summary, because three new HEIC files dropped
beside two old JPEGs used to produce a run indistinguishable from a real one:

    SKIPPED: notes.txt (.txt) -- <reason>
    !! 1 of 4 file(s) in this directory will NOT be scanned. Accepted: .jpg, .jpeg, .png, .webp, and .heic, .heif, .hif (converted to JPEG first)

The accepted list is built for the host you are on, so a machine that does not
convert HEIC does not claim it does.

**Nothing in the directory is readable.** This is an error exit, not a
"0 photos" success:

    No readable photo in D:\photos: all 3 file(s) were skipped. Found: .heic x3. Accepted: .jpg, .jpeg, .png, .webp

or, when the directory is simply empty, `No files to scan in D:\photos`.

**The path is wrong.**

    No photo directory at D:\photso
    Not a photo directory: D:\photos\shelf1.jpg is a file -- scan takes the directory that holds your photos, not one photo

**HEIC was converted.** Not a failure, but you will see it, per file so a slow
one cannot hide in an average. *Illustrative output: the figures below are made
up, not measured off any shelf.*

    CONVERTED: shelf-1.heic -> jpeg in 800 ms
    HEIC: 3 file(s) converted to a temp directory in 3400 ms total (process start included). Nothing was written next to the originals.

---

## Step 2 — Choose a vision backend

Three are available, and the choice is between money and what gets read
correctly.

    --provider ollama      local, needs a running Ollama server (DEFAULT)
    --provider openai      any endpoint speaking the OpenAI /chat/completions
                           API (Groq, OpenRouter, Mistral, GitHub Models,
                           Cerebras, Gemini's compatibility endpoint)
    --provider anthropic   cloud, needs ANTHROPIC_API_KEY

**Local is the default on desktop and every cloud endpoint is an explicit
opt-in**, because your photographs are uploaded in full to whichever endpoint
you name, and free tiers are commonly funded by training on what is submitted
to them. These are pictures of your home. Read the service's data policy
before you point this at it.

**"Local" does not mean "offline".** A local run POSTs every photo to
`SHELFSCAN_OLLAMA_URL`, which is yours to set. Aimed at the default
`http://localhost:11434` nothing leaves the machine; aimed at a box on your
LAN it ships the photographs there over plain HTTP. Keyless and offline are
not the same claim.

### What each one actually reads

Measured on the same five control photographs, checked against the
photographs by eye rather than against another JSON file. Numbers and full
caveats: [`measurements.md`](measurements.md), "The second lever works" and "A
bigger local model, measured and rejected".

| | local `qwen2.5vl:7b` | `gpt-4.1-mini` | `gpt-5.5` |
|---|---|---|---|
| hi-res detections | the baseline | fewer | slightly more, and it wanders by photo |
| Japanese-script spines | transcribes them all | **reads none** | transcribes them all |
| printed Switch 2 band | **not read** — hints those cases `PS2` | not read | read per spine, every hint correct across the three full-resolution photographs, five runs each; measured separately at 1200×900, every case correct on the one photograph there where the band was checked |
| invented titles at 1200×900 | none | one, on 3 of 5 runs | none over 5 runs |
| cost | **$0** | paid | ~**$0.45** for a three-photo shelf |

Two things worth taking from that table, because both are easy to assume the
other way round:

- **The local model is not the one that fails on Japanese.** It transcribes
  every Japanese-script spine; `gpt-4.1-mini` reads none of them. "A cloud model
  will read the Japanese spines" was measured and is false for that model.
- **What the local model does miss is the printed Switch 2 band.** Those
  spines come back hinted `PS2`, which is wrong. Thirteen prompt wordings were
  tried against this and none worked, so it is a model limit rather than
  something to tune. `gpt-5.5` reads the band per spine and gets it right —
  and still invents one row at 4000×3000 on 2 runs of 5, so review is not
  optional on it either.

If you have a handful of Switch 2 cases and a shelf you scan once, the cloud
pass is worth about the price of a coffee. If you scan repeatedly, or your
shelf has no Switch 2 band on it, local costs nothing and gives up little.

### Setting up the local model

Install Ollama, pull a vision model, and leave the server running. The
built-in defaults are `qwen2.5vl:7b` at `http://localhost:11434`, and both are
overridable with `SHELFSCAN_OLLAMA_MODEL` and `SHELFSCAN_OLLAMA_URL`. Expect
about **25 s per 4000×3000 photo** on a machine that fits the model.

### Setting up a cloud backend

PowerShell:

    $env:ANTHROPIC_API_KEY = '...'

or, for any OpenAI-compatible endpoint, all three of:

    $env:SHELFSCAN_OPENAI_BASE_URL = 'https://api.groq.com/openai/v1'
    $env:SHELFSCAN_OPENAI_MODEL = '...'
    $env:SHELFSCAN_OPENAI_API_KEY = '...'

The base URL goes up to and including the version segment. Setting these
configures the endpoint but never selects it — only the `--provider` flag
does.

`SHELFSCAN_ANTHROPIC_MODEL` is optional: unset uses a built-in default, so you
need not know a model id to start. Model ids are the vendor's to publish.

The variables are read from the environment of the shell that runs the
command. **Nothing in this codebase parses a `.env` file.**
[`.env.example`](../.env.example) is a reference list of names only; copying
it to `.env` has no effect and produces no error. A set-but-empty variable
counts as unset everywhere, deliberately.

### What can go wrong

**Ollama is not running:**

    Cannot reach Ollama at http://localhost:11434 -- nothing answered there. Start the server with: ollama serve. If that address is another machine, check it is right and reachable from here. (<socket reason>)

**The model is not pulled:**

    Ollama at http://localhost:11434 has no model "qwen2.5vl:7b" (HTTP 404) -- it is not <...>

**Ollama is running but not answering.** A different failure with a different
fix, so it is a different message. It ends on the diagnosis: a wedged model
runner stalls exactly like this, `qwen2.5vl:7b` answers a 4000×3000 photo in
about 25 s here, so check the server is alive with `ollama ps` before assuming
the model is merely slow — a model too large for the machine is the one case
measured here that legitimately takes minutes.

If that is your case, raise the per-call bound:
`SHELFSCAN_VISION_TIMEOUT=<seconds>`, which bounds **one** vision call, per
photo, for whichever provider is in use. Unset is 120 s. Accepted range is 1
to 1800; anything else is refused rather than quietly replaced by the default,
because a raise that did not take looks exactly like the timeout it was meant
to fix.

**A photo with too many spines on it is NOT that case, and raising the bound
for one is measured to be a waste of your time.** Past the density ceiling in
Step 1 the local model repeats itself rather than answering, so the extra
minutes contain nothing the first few seconds had not already produced, and
the answer is declined at the end whatever the bound was. If a scan is slow on
one photo and that photo is a wide shot of a full shelf, photograph it in two
or three sections instead — the fix is the frame, not the seconds.

**A cloud key is missing.** Nothing is read; the run exits before any photo
moves:

    Provider "anthropic" needs ANTHROPIC_API_KEY. <...>
    The "openai" provider needs SHELFSCAN_OPENAI_MODEL. <...>

**Every call was refused** — a wrong model id or a wrong key. The run exits 2
with the aggregated message, distinct from the "nothing to scan" exit, because
this one means a scan was run and every call bounced.

### About `--fallback`

`--fallback` names a **second** vision model that re-reads **every** photo,
with the two reads merged. It is off unless you ask for it, and it does not
decide for itself which photos need it — the local model cannot report the
spines it failed to read, so there is nothing to decide on. It doubles the
vision cost of the run, and with a cloud fallback every photo is uploaded a
second time. The run says so in the number rather than the word:

    Fallback: cloud (<model>, <sampling>) -- re-reads ALL 3 photo(s), 3 extra call(s).

---

## Step 3 — Get an IGDB key

This is the step most likely to strand you, so it is here in full. You need it
only for `.xcoll`; CSV works without it.

**What it is for.** Stage 3 of the pipeline resolves each title read off a
spine to a canonical IGDB game id and platform id. The Tonkatsu `.xcoll` light
format carries *exactly those two ids per item* and nothing else — Tonkatsu
Box fetches the cover and the metadata itself on import. So an item with no
IGDB match has nothing to write into a `.xcoll` at all. CSV has a title column
and carries it fine.

**shelfscan ships no credentials and runs no proxy.** A secret embedded in a
distributed client is not a secret, the Twitch terms forbid sharing a client
secret, and a shared proxy would make this project the processor of other
people's photographs of their homes. So the key is yours, it stays yours, and
it costs nothing.

### Registering the application

IGDB credentials are Twitch application credentials. There is no separate IGDB
signup.

1. Sign in to Twitch, or create an account.
2. **Enable two-factor authentication** on that account. Twitch will not let
   you register an application without it, and this is where most people
   stop — it is a Twitch requirement, not a shelfscan one.
3. Go to `https://dev.twitch.tv/console/apps` and choose **Register Your
   Application**.
4. Fill in:
   - **Name** — anything unique on Twitch; `shelfscan-<yourname>` works.
   - **OAuth Redirect URLs** — `http://localhost`. The field is required.
     shelfscan never uses it: it authenticates machine-to-machine with the
     client id and secret, so no browser redirect ever happens.
   - **Category** — *Application Integration*.
5. **Create**, then **Manage** on the application you just made.
6. Copy the **Client ID**.
7. Press **New Secret** and copy the secret. **It is shown once and cannot be
   read back afterwards.** If you lose it, generate another — the old one
   stops working.

Both halves come from **one** application. Mixing an id from one with a secret
from another is a real and common mistake, and it fails late, at the search
rather than at the token.

### Giving them to the tool

PowerShell:

    $env:IGDB_CLIENT_ID = '...'
    $env:IGDB_CLIENT_SECRET = '...'

bash:

    export IGDB_CLIENT_ID=...
    export IGDB_CLIENT_SECRET=...

In the same shell you run the scan from. Both must be set and non-empty:
either half missing means no resolver at all.

In the Flutter app they go in the two IGDB fields in **Settings** instead, and
are stored in the OS keychain rather than in any file.

### What can go wrong

**Neither is set.** `scan` does not fail — it degrades, and says so:

<!-- transcript: igdb-skipped -->

    IGDB credentials not set -- resolve stage will be skipped, games stay unresolved (fine for vision validation).

`resolve` does fail, because resolving is its entire purpose:

<!-- transcript: resolve-needs-igdb -->

    The "resolve" command needs IGDB credentials: set IGDB_CLIENT_ID and IGDB_CLIENT_SECRET (see .env.example). Resolving is the entire point of this command, so there is nothing useful to do without them.

**The client id is wrong.** Twitch answers an unknown client id with a 400
rather than a 401, which is the one status that can point at one half of the
pair, so the message does:

> refused the credentials (HTTP 400) before it issued a token. That is the
> client id it does not recognise rather than the secret: check
> IGDB_CLIENT_ID against the application at
> `https://dev.twitch.tv/console/apps`.

**The pair does not work.** HTTP 401 or 403 from Twitch: the id and the secret
are not a working pair for an application it knows. Both come from one
application, and a secret is shown once and cannot be read back — regenerate
it if you are not certain of it.

**Two different applications.** HTTP 401 or 403 from IGDB, on a token Twitch
had just issued: the search sends the id and the token separately, and only
IGDB sees that they disagree.

**No network.** The message says plainly that neither the client id nor the
secret is what failed, that the address is fixed in the build rather than
typed by you, and that there is nothing to correct in your settings — check
whether the machine is online and whether a proxy or firewall is refusing the
connection.

**In every one of those cases nothing is lost.** This stage only adds
canonical ids: the row is in the review unmatched and can be matched by hand
there. You do not re-scan to recover from an IGDB failure — you fix the
credentials and run `resolve` over the file you already have.

---

## Step 4 — Run the scan

    dart run shelfscan_core:shelfscan scan D:\photos -o collection.review.json

`-o` defaults to `collection.review.json` in the current directory. The
options `scan` takes, and no others:

    -o <file>            where to write the review document
    --provider <name>    anthropic | ollama | openai
    --fallback <name>    anthropic | ollama | openai | none
    --aliases <file>     regional title table (data/title_aliases.json)
    --installs <dir>     add a folder of installed games to this run
    --library            add the GOG Galaxy library to this run
    --galaxy-db <path>   where that database is, if not where it is expected

The last three belong to Part 2 below; they are listed here because a run that
mixes sources has to be **one** run, and this is the command that does it.

### What you will see

The provider it chose, so a run can never be misattributed afterwards:

    Vision: local Ollama (qwen2.5vl:7b)

Then the stages, one line per stage and one per item, and any warning on
stderr:

    == VISION ==
      VISION 1/3
    ...
    WARN: <...>

Then the summary. The scope line quotes what it did **not** cover as well as
what it did, because "Scanned 2 photo(s)" is true and still misleading when
the directory held five files.
*Illustrative output: the filenames and the figures in this block are made
up, not measured off any shelf.*

    Scanned 3 photo(s): 45 game(s) detected, 4 unresolved.

Then, when they apply:

    Unread-spine reports: 2 -- one report can describe several spines, so this is not a count of spines.
      by photo: shelf-3.jpg: 1 report(s), ...
      by script: japanese: 1, ...
      shelf-3.jpg: <the model's own wording>

That wording is deliberate. A spine the model saw and could not read is kept
out of `games` on purpose — nothing is invented for it — so without these
lines a photo of unread Japanese spines would look like an empty shelf. And
the unit really is *reports*, not spines: one report has been measured naming
two or three spines at once.

    Platform hints refused: 4 (kept per row in "discarded_platform_hint")
      4 x "PS2" -- <why it was refused>

A refused hint is named rather than dropped, because a row that silently lost
its platform looks exactly like a spine whose branding was illegible.

Finally:

    Review file: collection.review.json -- set "status" per game, then export.

### What can go wrong

**A flag that belongs to another command.** Checked before anything is read,
so nothing is paid for:

<!-- transcript: unknown-option -->

    Unknown option "--targt" for "export". Nothing was read. Options of "export": -o, --target.
    "--target" is not an option of "scan" -- it belongs to "export". Nothing was read. Options of "scan": -o, --provider, --fallback, --aliases, --installs, --library, --galaxy-db. Run "shelfscan" with no arguments for what each command reads.

**A mistyped `-o`.** Also answered before the vision run, because the write is
the last statement of a run you have already paid minutes for:

    Not an output file: D:\out is a directory -- -o names the file to write, not the directory to write it into
    No output directory at D:\repots -- -o writes D:\repots\shelf.csv, and nothing here creates a directory for you
    Cannot write to D:\shelf.csv -- <the OS message>

A missing parent directory is refused rather than created: `-o repots/x.csv`
would otherwise succeed silently and leave the typo permanent on disk.

**The run took a long time and produced fewer rows than the shelf has.** That
is not a failure — it is the review step's whole reason for existing. Go to
step 5.

---

## Step 5 — Read the review

Model confidence is not trustworthy, so **every item passes human review
before export**. This is not a formality bolted on; it is the boundary the
whole tool is built around. Everything before it is recognition, everything
after it is formatting.

There is one document and two ways to read it. `collection.review.json` is
hand-editable by design, and the Flutter app renders that same document as an
approve/reject screen. Both feed the same exporters, so it does not matter
which you use.

### The four states a row can be in

In the file, every entry in `games` carries a `status`:

| status | meaning | exported? |
|---|---|---|
| `pending` | you have not decided yet | no |
| `approved` | keep it as matched | yes |
| `rejected` | a false positive, or a row you do not own | no |
| `edited` | you replaced the match by hand | yes |

`edited` exports exactly like `approved` — the app's counter tracks both,
which is why it says "Export 41 items" rather than counting the word
`approved`.

### What the app's marks mean

Each row shows the matched title, or — when nothing matched — the raw text
read off the spine. Underneath it, a subtitle whose clauses always appear in
the same order, so rows stay scannable:

- **the platform** — the canonical platform name if matched, otherwise the
  hint read off the case, otherwise `?`;
- **`raw: "..."`** — what was actually read off the spine, or **`added by
  hand`** for an item you typed;
- **the release year**, when IGDB gives one;
- **`matched as "..."`** — the alternative name that matched, which is how an
  English canonical title comes to sit above a Japanese raw one;
- **`matched by store id`** or **`score 87%`** — how the match was made. A
  store-id join writes no percentage, because a percentage on that row would
  be a string measurement nobody took;
- **`not in .xcoll -- tap to pick a match`** — see below. Absent on a keyless
  run, where it would be true of every row and where there is no candidate
  list to tap into;
- **the status word**, once you have decided;
- **`hint refused: "..."`** — the platform hint the pipeline threw out, named
  so the row is not mistaken for one whose branding was illegible;
- **`note: "..."`**, if there is one.

A **pencil icon** on the left marks an item you typed rather than one read off
a photo — so you do not waste time re-checking your own input against a
photograph.

The **check** and **cross** buttons on the right approve and reject. Colour is
never the only signal: the subtitle spells the status out in words too.

**Tap any row** to open the candidate list. The resolver's own pick is marked
but not privileged — the entire point of that sheet is that it can be wrong.
The last entry is **No match**, which clears the match and rejects the item.

### The banners above the list

- **`N of M photos could not be scanned`** — coloured as an error, naming the
  files. Nothing from them is in the list.
- **`N of M photos were not looked at`** — you stopped the scan before it got
  to them. A separate banner, and deliberately not coloured as an error:
  being told your own Stop was a failure is worse than being told nothing.
- **`At least N spines could not be read`** — with the caveat that one report
  can describe several spines, so there may be more, and the promise that
  nothing was invented for them. Each photo gets an **Add** button that files
  the item you type into that photo's group.
- **`Keyless run -- nothing was looked up`** — this run had no IGDB stage, so
  every row is the title as it was read. Not coloured as an error: it is the
  mode you chose, and it names the export that carries the rows.

### What cannot reach `.xcoll`, and why

An `.xcoll` item **is** a pair of ids — an IGDB game id and a platform id.
There is no title field to fall back on. So a row with no resolved IGDB match
has nothing to write, and it says so on its own face, independently of whether
you have approved it:

    not in .xcoll -- tap to pick a match

Three kinds of row land there: a title IGDB has no candidate for, a title
whose candidates all scored below the auto-match threshold and that you never
picked from, and an item you typed by hand while the resolver was unavailable.

**CSV carries all of them**, as long as the row has a non-blank title. That is
the fallback, and it is why keyless use is a real path rather than a crippled
one.

**On a keyless run every row is one of these**, so the app says it once above
the list instead of on each row: a mark that is on everything locates nothing,
and there the invitation to tap for a match is not even true — nothing was
looked up, so no row has candidates to offer. The export sheet also says which
target would carry none of the rows you marked, before you pick it. In the app
that mode is chosen by name, above the **Scan** button.

What to expect: on a real shelf measured during development, a minority of
rows had no IGDB id — enough that you meet them on any run, not so many that
the rest could not be exported.

If you export `.xcoll` with such rows approved, the app stops you first — and
names the rows rather than counting them, because a count cannot be traced
back to a row:

> **Unresolved items will be dropped.** 4 approved items have no matched game,
> and the tonkatsu export can only carry matched ones. They will be left
> out: …

with **Back to review** and **Export anyway**.

---

## Step 6 — Fix a row by hand

Three different problems, three different fixes.

### The match is wrong

Tap the row and pick the right candidate. The status becomes `edited` and the
row exports. If none of the candidates is right, choose **No match** — that
clears the match and rejects the item, which is the honest outcome and keeps
a wrong id out of your catalog.

In the file, do the same by setting `"status": "rejected"`, or by editing the
entry's chosen match directly.

### The scan missed an item entirely

Some spines carry no readable text at all — a case whose art is a logo and
nothing else — and no amount of scanning harder recovers them. Typing the title is
the only path those items have.

In the app: the **Add missing item** button, or the **Add** button on the
unread-spine banner for the photograph you are looking at, which files the new
row into that photo's group.

In the file: append a block to `games` and re-run `resolve`.

    {
      "detection": {
        "raw_title": "<the title as you read it off the spine>",
        "platform_hint": "PS4",
        "media_type": "disc",
        "origin": "manual"
      }
    }

Only `raw_title` is required. `platform_hint` narrows the IGDB search and is
worth typing. `media_type` is `cartridge`, `disc` or `unknown`. `origin:
"manual"` marks the row as human-entered. `best`, `candidates`, `status`,
`confidence` and the photo fields may all be left out — a typed item was read
off no photograph and has no candidates until `resolve` gives it some.

### Nothing is matched, because you had no key yet

Set the two IGDB variables from step 3 and run the resolver over the scan you
already have. **No photograph is read and no vision provider is built**, so
this costs nothing and repeats for free:

    dart run shelfscan_core:shelfscan resolve collection.review.json

Output defaults to `collection.review.resolved.json` — the input is never
overwritten, so a before/after comparison stays possible. `-o` overrides it.
*Illustrative output: the filenames and the figures in this block are made
up, not measured off any shelf.*

    Resolved 45 detection(s) from collection.review.json:
      auto-matched (score >= 0.85):        41
      candidates below threshold:          14
      no candidates at all:                10
    Output: collection.review.resolved.json (review status reset to pending)

**`resolve` resets every status to `pending`.** That is deliberate: a new
match invalidates an approval you gave to the old one. So resolve first,
review second — doing it the other way round throws your review away.

### What can go wrong

`review.json` is hand-edited by design, so a stray character is expected input
rather than a crash. The two halves are kept apart because their fixes are:

    Not a review file: D:\collection.review.json is not JSON -- <message> at line 812, column 5 (character 21044). review.json is hand-edited by design, so look at the last edit: an unclosed brace, a trailing comma or an unquoted string.

    Not a review file: D:\collection.review.json is JSON but not a review document -- <the field that is wrong>. Run shelfscan with no arguments for the smallest legal game entry.

The line and column are given because a character offset is unusable on the
thousands of lines a real scan writes. And the path errors mirror the scan's:

    No review file at D:\collection.review.jsn
    Not a review file: D:\photos is a directory -- resolve takes the review.json written by scan, not the directory it sits in

---

## Step 7 — Export

    dart run shelfscan_core:shelfscan export collection.review.json --target tonkatsu -o shelf.xcoll
    dart run shelfscan_core:shelfscan export collection.review.json --target csv -o shelf.csv

All three of the review file, `--target` and `-o` are required; leaving one
out prints the usage text and exits.
*Illustrative output: the filenames and the figures in this block are made
up, not measured off any shelf.*

    Exported 41 of 45 approved game(s) -> shelf.xcoll
      4 left out: the tonkatsu target carries only items with a resolved IGDB match.

The count is asked of the exporter rather than re-derived, so a summary saying
"exported 45" while the file holds 41 cannot happen.

**An unknown target names the ones that exist:**

<!-- transcript: unknown-export-target -->

    Unknown target "tonkatsu-box". Known: tonkatsu, csv

**If you exported CSV**, you may also see this, and only when it applies —
an ordinary export has no such cell in it:

    2 cell(s) begin with =, +, - or @, which Excel, LibreOffice and Google Sheets read as a formula rather than as text:
        title: =SUM(...)
        ...
      They are written through unchanged and an import dialog is unaffected. To read shelf.csv in a spreadsheet, import it with the columns set to Text (Excel: Data -> From Text/CSV) rather than double-clicking it -- README, "Opening the CSV in a spreadsheet".

Those names are yours and were exported exactly as they are; nothing rewrites
a cell. In the app the same information arrives as a snackbar with a **What to
do** button.

---

## Step 8 — Import into Tonkatsu Box

In Tonkatsu Box: **Import → Import Collection**, and pick the `.xcoll` file.

Covers and metadata are **not** in that file and are not meant to be.
shelfscan writes a pinned `version: 2` light collection whose items are an
IGDB id and a platform id apiece; Tonkatsu Box fetches everything else itself
on import. That is the entire premise of the tool — send ids, let the catalog
app do the rest — and it has been run end to end on a real shelf:
**every approved item imported, covers and metadata fetched by the importer,
every platform id correct** — including the console band that was the open
risk, and a split within one platform family read off the cases.

The `.xcoll` format belongs to the Tonkatsu Box project, not to this one. It
is treated as an external contract and pinned; its reference lives with that
project, cited in the doc comment on `TonkatsuExporter` in
`packages/shelfscan_core/lib/src/exporters/exporters.dart`.

**One thing that looks like a bug and is not.** A game you own on two consoles
arrives as two entries — one title on Switch 2 and on PS5, or another as itself
and as its Switch 2 Edition. Two *different*
platform hints, both present, stay two rows. That rule was adopted after the
first version of the dedupe was measured dropping exactly this pair.

---

# Part 2 — the disk sources

Games installed on the PC, and games you own on GOG but have not installed,
can go into the same review document. This half is shorter for a good reason:
**no key, no model, no photograph, no cost.** It reads names and local files
only, and a run repeats byte for byte for free.

## Installed games

    dart run shelfscan_core:shelfscan scan-installs "C:\GOG Games" -o collection.review.json

Options: `-o`, `--aliases`, `--library`, `--galaxy-db`. No provider options —
there is no vision call to configure.

It reads the names of the files and folders in the directory, plus any
`goggame-*.info` a GOG installer left beside a game. It goes **one level down
and no further**, and inside a game's own folder it reads only
`goggame-*.info` — plus, when the folder itself is named something like "New
Folder", the one installer in it that names a game. A game's `data/`, `Saves/`
and `Redist/` subtrees never reach the pipeline, which is what keeps the
review list a list of games.

**Every run says what it is doing, because this contract cannot be enforced
from the inside:**

<!-- transcript: scan-installs-notice -->

    Reading C:\GOG Games: file and folder NAMES, plus any goggame-*.info beside them. No photo is read and no vision model is called. Nothing here can tell an application from a game, or a game from a film, by its name -- point this at a media folder, and review every row before you export it.

Take that seriously. Pointed at a real `Downloads` folder, **every title it
produced was an application** rather than a game. The folder was a private one:
neither its listing nor any count of what was in it is published, and the
verdict on the titles is the measurement. Nothing in a file *name* separates
`NoteWellSetup.exe` from `setup_moor_1.9.exe`, and no rule reading only a name
ever will.

### It reads films too now, and that widens the contract rather than fixing it

Since T-0162 this command also reads **films**. A video file whose name is
release-shaped — `Some.Title.1999.1080p.BluRay.x264-GROUP.mkv` — becomes a film
row rather than a game row; a game installer beside it stays a game row. The
kind is decided per file, so one folder holding both is read once and produces
both, and you do not choose a mode before the run.

**Films are read, and a film is looked up in a film catalogue.** Deciding that
a name is a film is one half; sending it to TMDB rather than to the games
catalogue is the other, and since T-0308 both shells route a row by its kind.
What that needs from you, and what happens when you have not got it, is below
— because it is not what you would guess.

**The contract above gets weaker, not stronger.** It used to be *point this at
a games folder only*. It is now:

> **Point this at a media folder, and review every row.**

The failure it guards against has not gone anywhere — it has multiplied. There
were two ways a name could be read as the wrong thing (an application taken for
a game, or nothing taken for anything); there are now three, because a name can
also be read as the wrong *kind*. And **every one of them fails silently**, for
the reason that has not changed since the first version of this command: a
filename never announces that it is not what it looks like. A holiday video
named like a release is a film row; a film named like an installer is a game
row; neither says so.

Two things keep that honest, and neither is automatic:

- **A file that settles nothing is declined rather than guessed at.** A video
  carrying neither a year nor a resolution produces no row at all, and is
  reported to you as skipped — the same treatment a name with no title in it
  gets. Declining is the success case here.
- **The kind is shown on the review screen and you can change it.** That is the
  only thing that turns a silent wrong guess into a visible one, so the
  instruction to *review every row* now means the kind as well as the title.
  Correcting it throws away whatever match the row was holding — a match found
  under the wrong kind is not evidence for the right one — and marks the row as
  owed a fresh one. **Nothing in the app performs that fresh lookup**, and since
  T-0311 the review screen says so rather than promising one: its only resolver
  call fires on an item you have just typed, and it writes no review document,
  so there is no file to point `resolve` at. A corrected film row therefore
  reaches an export from the app carrying the title read off its filename and
  nothing else. **In the CLI there is a way, and it is one command:** `resolve`
  over a document the CLI itself produced re-runs every row against the
  catalogue that row's *current* kind implies, so a row you corrected to film
  goes to TMDB — if the run has the token below. Without it the row comes back
  keyless, which is the same place it started.

**The film lookup wants a credential of its own — a third, after IGDB and the
vision model.** It is `SHELFSCAN_TMDB_TOKEN`, the API Read Access Token from
your own TMDB account, and `.env.example` says which of TMDB's two credentials
that is and why it is not the other one. Set it the way you set the IGDB pair
in Step 3.

**What a run does when it is not set is the owner's decision, and it is the
plain one: a film row is keyless.** It behaves exactly as a game row does
without IGDB credentials — it reaches review carrying the title read off its
filename, matches nothing, and exports to CSV but not to `.xcoll`, which is a
file of catalogue ids and has nothing to put in one. Games are unaffected, and
a run holding IGDB credentials but no TMDB token says exactly that on stdout
before it starts — you are told which case you are in rather than left to
infer it from a row that came back empty. **The app is always in this case:**
it keeps credentials in the OS keychain and its Settings screen has two fields
rather than three, so there is nowhere to put a TMDB token and a film row there
is keyless on every path.

**No film reaches the games catalogue, in any configuration.** Both shells now
build one resolver per kind rather than one resolver: game rows to IGDB, film
rows to TMDB, and a kind nobody registered a catalogue for is left unresolved
rather than sent to whichever catalogue happens to be configured. Until T-0308
a film row in a run with IGDB credentials was searched among games, and a film
whose title is also a game's — an adaptation shares its title almost by
definition — could come back holding that game's canonical title, platform and
confidence score, reading on the review screen exactly like a row that went
right. That cannot happen now.

**What has actually been run against TMDB, so you can price the rest
yourself.** Two public release names, on one machine, on one evening, with one
token: they resolved, and the release year read out of the filename narrowed
the search to the right film rather than to its remakes. A year the catalogue
disagrees with is worse than no year — it empties the answer — so a query that
comes back with nothing is retried without it; and where that retry cannot tell
two films of the same title apart, the row is left for you rather than picked.
That is the whole of what anyone here has seen. **It is not a measurement of
how well TMDB answers real release names**, nothing has been run over anime or
over a collection, and *review every row* still means what it says.

**And what a film that resolved exports as.** `.xcoll` takes it as a `movie`
item carrying the film catalogue's id and no `platform_id` key at all — a film
has no platform, and the writer leaves the key out rather than inventing a `0`.
CSV carries the id as `tmdb:1234`; the prefix is which catalogue answered, and
CSV still has no column for the kind, because its `media_type` is the physical
carrier (`cartridge`/`disc`/`unknown`). No `.xcoll` carrying a film has been
imported into a catalog app here, so that last step is written and tested
rather than verified — the same as every other disk-source export.

So a short, closed list of well-known personal and system directories is
refused outright:

<!-- transcript: scan-installs-refused -->

    Not a games folder: C:\Users\me\Downloads. This reads NAMES, and no rule reading a name tells NoteWellSetup.exe from setup_moor_1.9.exe -- run over a Downloads folder it titles every installer it finds, and not one of them is a game (T-0158). Point it at the directory your games are installed in.

A drive root is refused for the same reason and one worse: it is the one
directory whose subdirectories are all the others.

**Other things it will tell you:**

    No games folder at C:\GOG Gamez
    Not a games folder: D:\setup.exe is a file -- scan-installs takes the directory your games are installed in, not one file
    Nothing to read in C:\GOG Games: the directory holds no file and no subdirectory.
    SKIPPED: <a goggame-*.info this shell could not read> -- <reason>

And on success, an accounting nobody has to do arithmetic on, plus a named
list of what was refused — grouped by reason, at most two lines per reason, so
forty declines of one kind are two lines and never forty:

    Read 38 entry(ies) (31 folder(s), 5 loose file(s), 2 goggame-*.info): 29 game(s) found, 3 unresolved.
    Not a game: 9 entry(ies), named below and in "declined_entries"
      6 x not a game file
          <six names>
      3 x <another reason>
          <names>

## The GOG library, installed or not

    dart run shelfscan_core:shelfscan scan-library -o collection.review.json

Options: `-o`, `--aliases`, `--galaxy-db`. No positional argument — there is
one Galaxy database, and `--galaxy-db` names it when it is not where the
reader looks.

**Windows only**, because that is where Galaxy runs. It reads **one file on
this machine and nothing from gog.com**: no login, no OAuth, no credential
stored and none needed.

**Galaxy must be installed here and signed in at least once.** That file is
what Galaxy's sync writes, so on a machine nobody has ever signed in on there
is nothing to read. It is a precondition on Galaxy and not a credential for
this tool — the sentence above still holds — and Galaxy itself need be
neither running nor online while you do this.

**It is a cache of the last sync, not your account.** A game bought since
Galaxy last ran is missing, and one removed since may still be listed. So
every run prints how old it is:

    GOG Galaxy library as of <last sync timestamp> -- this is a local cache of the last sync, not a live read of the account: a game bought since then is missing and one removed since may still be listed. Nothing was read from gog.com and no credential was used.

DLC, releases Galaxy hides, and releases from other stores connected to Galaxy
are **counted out by name rather than dropped silently** — the run names each
kind of row it left out.

**What can go wrong:** two states are reported apart, because the answer to
each differs, and both exit 2 with their own message rather than being
reported as a scan that found nothing.

*No database at all* — Galaxy is not installed here, or the file was moved or
lost:

    No GOG Galaxy library database at <path>. Galaxy rebuilds it on next launch if it was lost; install or run Galaxy once, or pass the path if it lives elsewhere.

*A database with no rows* — it is there, but no GOG account has ever signed
in to Galaxy on this machine, or GOG has moved the schema out from under the
reader. Zero rows out of a database that exists is a failure and not an empty
library, because those two look identical from here:

    The GOG Galaxy database at <path> returned no library rows. Either no GOG account is signed in to Galaxy on this machine, or the schema has changed (this reader was written against PRAGMA user_version 40, found <n>).

And if GOG has moved the schema in a way the query survives you get a warning,
not a failure — the query already succeeded, so the tables this reads are
still there:

    WARN: this GOG Galaxy database is schema version 41; this reader was verified against 40. Check the titles below against Galaxy.

## One run, several sources

A game you own on a disc **and** have installed on the PC is one game, and
only a single run puts the two through one dedupe:

    dart run shelfscan_core:shelfscan scan D:\photos --installs "C:\GOG Games" --library

That writes **one** review document in which that game is one row. Run the
commands separately and you get two files nobody can reconcile — and the
second `-o` overwrites the first.

A command may add sources that cost less than its own, never more:
`scan-installs` takes `--library` (neither reads a photo), `scan-library`
takes neither, and nothing adds photographs to a run that has none — that run
is `scan`, which is where every vision option already lives. Each added source
keeps its own notice: `--installs` prints what a file name cannot tell you,
`--library` prints how old the cache is.

Each of the disk-source paths above ends where step 4 ended — a
`collection.review.json` and the line

    Review file: collection.review.json -- set "status" per game, then export.

From there, **steps 5 to 8 are identical.** Review, fix, export, import. The
rows read off a folder or a library are reviewed exactly like the rows read
off a photograph, and for the same reason: a name is not proof, and the export
is the last point at which a wrong row is still cheap to remove.

---

## Where to go next

- [`measurements.md`](measurements.md) — the measurements this project's
  decisions rest on, including what it measured and then decided not to do.
  Not every figure: one that settles a single constant usually lives in the
  doc comment beside that constant, and the archive's own opening says so.
  Read the one section that covers what you are about to try.
- [`decisions/`](decisions/) — the decisions a reader would otherwise be
  surprised by, each with the measurement that settled it.
- [`../ARCHITECTURE.md`](../ARCHITECTURE.md) — the pipeline, the module map,
  and the platform boundaries.
- [`../.env.example`](../.env.example) — the complete list of environment
  variables the CLI reads, with what blank means for each.
