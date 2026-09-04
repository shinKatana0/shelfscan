**English** · [Русский](README.ru.md) · [日本語](README.ja.md)

<!-- TRANSLATIONS — read this before you edit the text below.
     README.ru.md and README.ja.md make the same claims as this file. Change
     anything here beyond a typo and both are stale. In the same commit either
     update them and bump the blob name on their TRANSLATED-FROM line, or set
     that line's last word to STALE — marking is cheap and honest, a silent lag
     is neither.
     The rule in full, what the marker names and why it is not a commit:
     CONTRIBUTING.md, "Translations". -->

<!-- FIGURES - every figure on this page belongs to the model it was
     measured on, and that is not always the model this project ships.
     A region carrying such figures is bounded by a pair of HTML
     comments, "measured-on: <model id>" and "/measured-on", invisible
     on the rendered page. The test is
     packages/shelfscan_core/test/figure_attribution_test.dart:
     it counts the regions, requires each to name its model in the
     visible text too, and fails when the shipped default id appears
     inside a region marked as the historical one. Pointing a measured
     sentence at whatever ships next is what it exists to catch. -->

# shelfscan

[![CI](https://github.com/shinKatana0/shelfscan/actions/workflows/ci.yml/badge.svg)](https://github.com/shinKatana0/shelfscan/actions/workflows/ci.yml)

**shelfscan turns a game collection you already own into a file another app
can import.** Photograph a shelf and a vision model reads the spines. Point it
at a folder of installed PC games, or at the GOG Galaxy library on your
machine, and it reads those with no model and no cost at all. A film in that
folder is read as a film rather than as a game, and looked up in a film
catalogue rather than the games one
([how far that goes](#films-are-read-as-films-and-how-far-that-goes)).
**In the app it is folders rather than a folder:** press *Add media folder*
once per folder and one scan reads all of them, so games in one, films in
another and anime in a third go through a single dedupe instead of three
review files nobody can reconcile.
Everything from one run lands in a single review file you confirm by
hand, and out of that comes `.xcoll` for Tonkatsu Box — which fetches covers
and metadata itself from the ids in it — a Custom Cards file for the same app
carrying the rows that matched nothing, or generic CSV for CLZ Games and most
other collection managers.

It owns **no catalog UI and no database**: recognition and export, nothing
else. Four sources go through one dedupe, so a game you own on a disc *and*
have installed is one row, not two. There is a command-line tool and a Flutter
app; both run the same pipeline.

It is not affiliated with any of the apps it feeds ([disclaimer](#disclaimer)).

## What it cannot do

The honest half, up front. Every line here is measured, and the section it
links to has the numbers.

**The Android build is unfinished, and nothing in this document is promised for
it.** That is a decision rather than a measurement, and it comes before the list
because everything in the list is read through it. Both platforms are built from
this tree; Windows is the one this project stands behind today, and Android is
not the priority at present. **It has not been abandoned** — it is still
intended, and the work on it is not closed. Until it is finished, read every
Android sentence in this file as a description of what the code does rather
than as a report of a working app.

- **Android is the thinner of the two platforms.** Both Windows and Android
  are built from this tree; only the Windows one has been **run** here. Debug
  and release apks build ([`doc/android-build.md`](doc/android-build.md)), and
  neither has ever been installed on anything, so nothing on the Android side
  is reported here as working rather than as built. One further thing is
  Windows-only by construction: the GOG Galaxy library is read from Galaxy's
  own database, and Galaxy is a Windows program. HEIC conversion is not — the
  code carries a decoder on each platform, the Windows Imaging Component on
  Windows and the system codec on Android. There is no installer and no
  published binary — you build it from source ([Setup](#setup)).
- **It is exactly as good as the vision model you supply, and the free one has <!-- measured-on: qwen2.5vl:7b -->
  a known ceiling.** The local `qwen2.5vl:7b` reads a Latin-script
  spine well and does not read the printed *Switch 2* band at all — those
  cases come back hinted `PS2`. It *does* transcribe Japanese script at full
  resolution; at low resolution it omits the Japanese spines, which is the
  right answer there because they are illegible rather than merely foreign.
  A cloud model is not automatically better: `gpt-4.1-mini` reads none of
  those Japanese spines, which the local model does. Only
  `gpt-5.5` reads both the script and the band, and charges for it
  ([the measured difference](#which-model-and-what-it-changes)). <!-- /measured-on -->
  Every one of those readings was taken on `qwen2.5vl:7b`, the built-in
  default until 2026-09-04. The default is now `qwen3-vl:8b-instruct`, and
  none of this was measured on it
  ([what is known about it](#which-model-and-what-it-changes)).
- **Human review is not optional, and confidence will not do it for you.** The
  local model returns `1.0` for everything, including partial reads. Every item
  passes your eye before export; that is where the remaining fifth gets fixed
  ([what to expect](#what-to-expect)).
- **Some spines are not read at all** — a spine that carries a logo and no
  text, and any spine too dim or too small in the frame to resolve. They are
  counted and named rather than guessed at, and you
  [add them by hand](#adding-one-by-hand).
- **Platform is often blank.** Disc cases carry a band the model reads; a stack
  of Switch cartridges does not, so those rows arrive with no platform and you
  set it at review.
- **The Tonkatsu `.xcoll` export needs catalogue ids**, so it needs a
  credential for the catalogue a row belongs to. Without one the run still
  works, and the rows it cannot carry leave through the Custom Cards export and
  through CSV instead ([Path A](#path-a--keyless)). A Custom Card is a title and
  a kind and no more: the receiving app stores it as a custom item and fetches
  no cover and no metadata for it.
- **Only one path is verified end to end.** Photographs → `.xcoll` → an import
  into Tonkatsu Box: every approved item arrived, covers and metadata fetched
  by the importer, every platform id correct, including Nintendo Switch 2
  (T-0009). The disk
  sources are newer and have had far less exercise. They have now been run
  against real folders: one installed GOG game resolved by its store id alone
  (`externalId`, no search string), and a folder of staged downloads gave three
  more rows and one named refusal. But that run stops at the export — **no
  disk-source `.xcoll` has been imported into a catalog app**, so "verified end
  to end" still belongs to the photographs alone. Nor has a CSV ever been
  imported into CLZ Games here: the format is generic and tested, the import is
  not.
- **Films are looked up, and both shells can reach the catalogue that does
  it.** A video file whose name is release-shaped becomes a film row rather
  than a game row, and the kind is shown and correctable at review. A film row
  goes to TMDB and never to the games catalogue, in any configuration. The
  lookup wants a token of its own — an environment variable in the CLI, a
  Settings field in the app — and a film row without one is keyless in either
  shell. **No run through the app has ever had an answer from TMDB**, and how
  well TMDB answers real release names is unmeasured anywhere: the path has
  been run in the CLI, not surveyed
  ([how far that goes](#films-are-read-as-films-and-how-far-that-goes)).
- **A folder of installers is not a games folder.** Names alone cannot tell
  `NoteWellSetup.exe` from `setup_moor_1.9.exe` — measured on a real `Downloads`
  folder, every title the name parser produced was an application rather than a
  game — so the command refuses the well-known personal and system directories
  outright. That folder was a private one and its contents are not published.
  Reading names for three kinds of thing rather than one makes that weaker and
  not stronger: a name can now also be read as the wrong *kind*, so the rule is
  point it at a media folder and review every row.
- **"Local" does not mean "offline".** A local run POSTs every photo to your
  Ollama server, and that address is yours to set: pointed at a box on the LAN
  it ships the photographs there over plain HTTP
  ([where your photos go](#where-your-photos-go)).

## Films are read as films, and how far that goes

The disk sources read **films** as well as games. A video file whose name is
release-shaped — `Some.Title.1999.1080p.BluRay.x264-GROUP.mkv` — becomes a
film row; an installer beside it stays a game row. The kind is decided per
file, so one folder holding both is read once and there is no mode to choose
before the run, and a file that settles neither is declined and named to you
rather than guessed at. The kind is shown on the review screen and you can
change it there, which is the only thing that turns a wrong guess into a
visible one.

**The lookup goes to a film catalogue, and never to the games one.** Both
shells route by the kind of the row: game rows to IGDB, film rows to TMDB, and
a kind with no catalogue configured is left unresolved rather than handed to
whichever catalogue happens to be there. So a film is never searched among
games in any configuration — the arrangement that used to hand back an
adaptation's *game*, with that game's platform and a confidence score, reading
like a row that went right, is gone.

**That path has been run against the live service, and that is a smaller claim
than it sounds.** Two public release names, on one machine, on one evening,
with one token. They resolved; the release year in the filename narrowed the
search to the right film rather than to its remakes; and a year the catalogue
disagrees with empties the query, which is then retried without it — and where
that retry cannot tell two films of the same title apart, the row is left for
you rather than picked. What that establishes is that the path works end to
end. It is not a measurement of how well TMDB answers real release names across
a collection, and nothing here has run it over an animation row or at any
scale.

**The token goes wherever you are running from.** In the CLI it is the
environment variable `SHELFSCAN_TMDB_TOKEN`, listed in `.env.example`; in the
app it is a Settings field, kept in the OS keychain with every other
credential. In the app it keys a run on its own — with a TMDB token and no
IGDB pair the film rows are looked up and the game rows are the keyless ones.
Choosing **Keyless** there is obeyed whatever is stored: the mode is what you
asked for, and a credential only decides what the run could have reached.

**No run through the app has ever had an answer from TMDB**, though. The live
searches above are the CLI's. What the app has is the wiring to the same
client, which is not the same claim.

**Keyless is the case most readers are in, and nothing about it changed.**
Without a token a film row reaches review carrying the title read off its
filename, matches nothing, and exports to CSV but not to `.xcoll`, which is a
file of catalogue ids and has nothing to put in one — exactly as a game row
behaves without IGDB credentials. Games are unaffected either way, and a CLI
run says which of the two cases you are in.

**What a film that did resolve exports as.** `.xcoll` takes it as a `movie`
item carrying the film catalogue's id and no platform key at all — a film has
no platform, and the writer omits the key rather than inventing a `0`. CSV
carries the id as `tmdb:1234`, the prefix naming which catalogue answered, and
still has no column for the kind: its `media_type` is the physical carrier,
`cartridge`/`disc`/`unknown`. **No `.xcoll` holding a film has been imported
into a catalog app here**, so that half is written and tested rather than
verified, like every other disk-source export. The full account is in
[the guide](doc/guide.md#it-reads-films-too-now-and-that-widens-the-contract-rather-than-fixing-it).

**Animation and anime are two different kinds, and only one of them is looked
up.** That is the receiving app's distinction, not an invention here. Its own
source says it in two sentences: `animation` is *"animated movies and series
(Pixar, Disney) … not anime, which is AniList"*, and `anime` is *"Japanese
anime on its own Anime model backed by AniList — not animation, which is TMDB
cartoons"* (`packages/core/lib/models/media_type.dart`, `release/0.44`).

- **Animation** is a TMDB cartoon or animated series. An animated film goes to
  TMDB's film search, an animated series to its tv search, and `.xcoll` takes
  either — as an `animation` item whose `platform_id` is `0` for a film and
  `1` for a series. A row left at plain `Animation`, with film-or-series
  unanswered, is refused by `.xcoll` outright rather than given an invented `0`.
- **Anime** is a separate type upstream, keyed by AniList or Kitsu and carrying
  no `platform_id` at all. **Nothing here queries AniList or Kitsu**, so an
  anime row is never matched and never reaches `.xcoll`. It leaves through the
  Custom Cards export and through CSV, carrying the title and the kind and
  nothing else. Nothing infers the kind either: no name says *Japanese*, so
  `Anime` is a value a person sets at review.

A video named the fansub way — `[Group] Title - 04 [1080p].mkv` — therefore
comes back as an **animated series** row rather than an anime one, because the
grammar detects an episode and never a nationality, and a Western cartoon ships
under the same convention. `S01E04` and `1x04` are still declined deliberately:
they say *series* without saying which kind. **What has never happened is the
match.** The tv search has not been called against the live service by
anything, ever; the live searches described above were films. So that path is
written and tested and nothing more.

**What this project resolves, and against what:**

| kind | catalogue | what `.xcoll` gets |
|---|---|---|
| Game | IGDB | `game` + an IGDB id + a platform id |
| Film | TMDB, film search | `movie` + a TMDB id, no platform key |
| Animated film | TMDB, film search | `animation` + a TMDB id + `platform_id` `0` |
| Animated series | TMDB, tv search | `animation` + a TMDB id + `platform_id` `1` |
| Animation, film-or-series unanswered | none — the question is open | nothing; the row is left out and named |
| Anime | none here | nothing; it leaves through Custom Cards and CSV |

Upstream accepts more catalogues than these for those types, and several of
them need no registration. This project queries none of them and is not adding
any; the longer account of why is in
[doc/integrations/tonkatsu-handoff.md](doc/integrations/tonkatsu-handoff.md).

The operational half — what a run prints, and why reading names for three kinds
of thing makes this command's safety contract weaker rather than stronger — is
in [doc/guide.md](doc/guide.md), under *Installed games*.

## Try it without an account

No key, no registration, nothing to sign up for. You need the Dart SDK (the
CLI alone needs no Flutter), [Ollama](https://ollama.com), and a ~6 GB model
download.

```
ollama pull qwen3-vl:8b-instruct

cd packages/shelfscan_core
dart pub get
dart run shelfscan_core:shelfscan scan ../../photos -o collection.review.json
```

Open `collection.review.json`, set `"status"` to `approved` or `rejected` on
each game, then:

```
dart run shelfscan_core:shelfscan export collection.review.json --target csv -o shelf.csv
```

That is the whole keyless path, and it is the default on Windows. The longer
form — what the run prints, what it skips, and the two commands that read a
disk instead of a photo — is [Setup](#setup) and [Commands](#commands).

## What it costs, and what leaves your machine

| | |
|---|---|
| Photos, local model | **$0.** Your own Ollama server, no account. |
| Photos, cloud model | **your own key, your own bill.** Measured with `gpt-5.5` at the vendor's listed rates on 2026-08-16: a three-photo 4000×3000 shelf scan costs about **$0.45** ($0.38–$0.46; a two-photo 1200×900 scan is $0.20–$0.27). |
| Installed games, GOG Galaxy library | **$0.** No model and no key; Galaxy's library is read from a file on your own machine, and nothing is fetched from any store. |
| IGDB ids (and with them `.xcoll`) | **$0**, but it needs a free Twitch application you register yourself ([Path B](#path-b--bring-your-own-keys)). |
| Film and animation ids (and with them their `.xcoll` rows) | **$0**, but it needs a free TMDB account you register yourself ([Path B](#path-b--bring-your-own-keys)). |

**Bring your own keys.** This project ships no credentials and runs no proxy;
there is no shared key hidden in the binary and nothing to sign up for to use
it. Keys live in environment variables (CLI) or the OS keychain (app), never in
a file inside the repository.

**Nothing is telemetered.** No analytics, no crash reporting, no server of this
project's own, no cache. The only things ever sent anywhere are the photographs
you scan — to the vision model *you* configured, and to nothing else — and the
title strings the resolve stage sends to a catalogue: to IGDB for game rows, to
TMDB for film and animation rows. Neither catalogue is ever sent an image.
What else leaves is the credential each one takes — your Twitch client id and
secret to `id.twitch.tv` for an access token, your TMDB token to TMDB with
every search —
and a catalogue you hold no credential for is not contacted at all. Exactly
what goes where is [Where your photos go](#where-your-photos-go), and it is
worth reading before you pick a cloud endpoint.

## Where to read next

| | |
|---|---|
| [doc/guide.md](doc/guide.md) | one complete run, from nothing to an imported collection — starting with how to photograph the shelf |
| [doc/android-build.md](doc/android-build.md) | building the Android apk on Windows: the toolchain, and four failures, three of which name something other than the missing step |
| [ARCHITECTURE.md](ARCHITECTURE.md) | the pipeline, the platform boundary, where a new source plugs in |
| [doc/decisions/](doc/decisions/) | the non-obvious decisions, each with the measurement that settled it |
| [doc/measurements.md](doc/measurements.md) | the measurements behind the decisions — including what was measured and then *not* built. Not every number: a prompt figure usually lives in the doc comment beside the rule it settled |
| [CONTRIBUTING.md](CONTRIBUTING.md) | running the suites, and what a change must not silently break |
| [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) | how people are expected to behave here |
| [SECURITY.md](SECURITY.md) | keys, photographs, and how to report a problem |
| [CHANGELOG.md](CHANGELOG.md) | what changed between versions |

The rest of this document is the reference: what a run produces, setup in full,
every command, the export formats, and where your photos go.

## What to expect

<!-- measured-on: qwen2.5vl:7b -->

Measured on two real shelf photos with the local model `qwen2.5vl:7b`, which
was the built-in default when they were taken:

- **~80–83% of items come out correct end to end**, ~93% on
  Latin-script titles. Every item passes human review before export, and
  that is not a formality — it is where the remaining fifth gets fixed.
- **The Japanese-script spines on these photos are not read.** The model
  does not guess at them any more (it used to invent plausible titles); they
  are counted and reported as unreadable, and you add them by hand. That is
  these photos, not a rule about the script — on the full-resolution
  control set the same model transcribes them
  ([the table below](#which-model-and-what-it-changes)).
- **Spines with a logo and no text** (a case whose art carries no printed
  title is the example that started this note) are not detected. Same answer:
  add by hand.
- **Platform is often blank.** Disc cases carry a platform band the model
  reads; a stack of Switch cartridges does not, so those items arrive
  with no platform and you set it at review.
- **Model confidence is useless here** — the local model returns `1.0`
  for everything, including partial reads. Do not filter on it.

<!-- /measured-on -->

A run over the two photos above prints exactly what it could not read.
*Illustrative output: the filenames and the figures in this block are made
up, not measured off any shelf.*

```
Scanned 2 photo(s): 18 game(s) detected, 18 unresolved.
Unread-spine reports: 6 -- one report can describe several spines, so this is not a count of spines.
  by photo: photo_a.jpg: 3 report(s), photo_b.jpg: 3 report(s)
  by script: japanese: 3, unknown: 3
  photo_a.jpg: characters too small to resolve
  ...
```

Reports, not spines: a cloud model answers one entry for a group of them
("two/three spines in the middle are too blurred to read"), so the number
is of things the model said, and its own wording is printed under it.

### Which model, and what it changes

The model is yours to choose and it is the largest single lever on the result.
Three have been measured here on the same control photographs; the full numbers
and the runs behind them are in
[`doc/measurements.md`](doc/measurements.md), "The second lever works" and "A
bigger local model, measured and rejected".

<!-- measured-on: qwen2.5vl:7b -->

| | `qwen2.5vl:7b` (local) | `gpt-4.1-mini` | `gpt-5.5` |
|---|---|---|---|
| Cost | **$0** | your key | your key — about **$0.45** for a three-photo shelf scan |
| Latin-script spines | ~93% correct | comparable detection counts, photo by photo | comparable or slightly higher; reads a glare-struck title `gpt-4.1-mini` misreads |
| Japanese-script spines | **read** at full resolution, with the platform wrong; omitted at low resolution, where they are illegible | **not read** — none of them | **read**, every one, on five runs of five, with the platform right |
| The printed *Switch 2* band | **not read** — those cases come back hinted `PS2` | not read | **read per spine** — every `SWITCH 2` hint correct across the three full-resolution photographs, five runs each, and no false positive on a case whose band prints none. The third photograph contributes none: the frame cuts a column at its edge, and the cases in the cut print the band but are not read — so that tally counts hints given rather than bands present. At 1200×900 the band was checked on one photograph and every case in it is read correctly over five runs; that is a separate measurement |
| Invention | none on either control set | misreads that glare-struck title on 3 of 5 low-resolution runs | one invented title, on 2 of 5 runs — the same spine twice, out of everything read across the three full-resolution photographs; none at all at 1200×900 |

<!-- /measured-on -->

**The local column is `qwen2.5vl:7b`, and it is not the built-in default any
more.** The default became `qwen3-vl:8b-instruct` on 2026-09-04, and no figure
in this table — or anywhere else in this repository — was measured on it.
What is known about it is one comparison, on one machine, on one reported run:
it read all three photographs of that run, where a reasoning-heavy multimodal
model read none of them. It is an image-capable instruct model that answered
where the other spent its whole output budget without writing anything, and
that is the whole of the case for it. Nothing here says it is faster, better,
or as measured. If you want the figures above, name `qwen2.5vl:7b` yourself —
in Settings, or in `SHELFSCAN_OLLAMA_MODEL`.

Two things this table is not. It is **not** "cloud is better": the free local
model reads those Japanese spines and one of the two paid ones does not, so
it is a model claim rather than a cloud claim, and a paid endpoint buys you
nothing by being paid.
And it is **not** a reason to reach for a bigger *local* model — a 32B was
measured and rejected, for numbers that are in the archive.

The lever that beat all of them is free: **photograph the shelf at a higher
resolution.** The same shelf gives well over twice as many detections at
4000×3000 as at 1200×900 — same model, same prompt. Before paying for a model,
re-shoot
the shelf: [the guide](doc/guide.md#step-1--photograph-the-shelf) says what
that means in practice.

### Adding one by hand

"Add by hand" above is a supported workflow, not a shrug: the review file
is hand-editable by design. Append a block to `games` in it, and re-run
`resolve` (below) to match it against IGDB:

```json
{
  "detection": {
    "raw_title": "<the title as you read it off the spine>",
    "platform_hint": "PS4",
    "media_type": "disc",
    "origin": "manual"
  }
}
```

```
dart run shelfscan_core:shelfscan resolve collection.review.json
```

Only `raw_title` is required. `platform_hint` narrows the IGDB search and
is worth typing; `media_type` is `cartridge`, `disc` or `unknown`;
`origin: "manual"` marks the row as typed rather than read off a photo.
`added_from_photo` is the one photo field a typed row may carry — the name
of the photo you were looking at while typing it, which is what files it
under that photo on the app's review screen. Everything else
(`source_photo`, `confidence`, `notes`, `best`, `candidates`, `status`) may
be left out: a typed row was read off no photo and has no candidates until
`resolve` gives it some.

A hand-written entry resolves exactly like a read one. Without IGDB
credentials `resolve` refuses to run, and the entry then stays unmatched —
which the CSV export still carries and `.xcoll` does not.

## Windows: download and run

**The quickest way to have the app is not to build it.** Every `v*` tag
publishes one asset, built on a Windows runner from the tree that tag names:

1. Open [Releases](https://github.com/shinKatana0/shelfscan/releases) and take
   **`ShelfScan-win-x64.zip`** from the newest one.
2. **Extract it fully**, wherever you like. It is portable — no installer, no
   registry keys, nothing written outside the folder and the app's own
   settings.
3. Open the extracted folder and run **`shelfscan_app.exe`** inside it.

> **Extract the zip before running `shelfscan_app.exe`. Do not start the
> executable from inside the archive.** Windows will happily open an `.exe`
> straight out of a zip preview, and it launches without the files that sit
> beside it — so it stops with a missing-DLL box naming
> `file_selector_windows_plugin.dll` or one of its neighbours. Extract the
> folder and it starts. This is how the zip is meant to be used rather than
> anything wrong with the download.

**No Flutter and no Dart SDK** — neither is needed to run it, and there is no
build step. That is not the same as "runs on any Windows installation": on a
machine that has never had Microsoft's Visual C++ Redistributable installed, one
of the bundled plugins will not load, which is the second bullet below and a
one-time fix. Keep the folder together:
the executable is small and does not run alone — the DLLs and the `data\`
folder beside it are the program.

Windows may warn that the publisher is unrecognised before it will start the
file. The build is not code-signed and this project holds no certificate to
sign it with, so that warning is expected rather than a sign anything is
wrong.

Two things can stop it starting, and neither is a fault in the download:

- **"Windows protected your PC".** SmartScreen, because the build is not
  code-signed and this project holds no certificate to sign it with. *More
  info* → *Run anyway*.
- **A missing `VCRUNTIME140.dll` or `MSVCP140.dll`.** Two of the bundled
  plugins are compiled against Microsoft's C++ runtime, which is not part of
  Windows and is not redistributed here. Most machines already have it, put
  there by some other program. If yours has not, install the
  [Microsoft Visual C++ Redistributable for x64](https://aka.ms/vs/17/release/vc_redist.x64.exe)
  once and the folder starts working.

### The model is a separate download, and nothing here bundles one

Reading spines off a photograph needs a vision model, and **there is no model
and no Ollama inside that zip.** The app installs and starts correctly without
one; what it cannot do until you choose a backend in Settings is scan. The
three choices are the same ones the CLI has:

- **Local** — an [Ollama](https://ollama.com) server that you install and run,
  with the vision model pulled once (`ollama pull qwen3-vl:8b-instruct`,
  about 6 GB).
  This is what Windows starts on. It needs no account and no key, and your
  photographs go no further than that server. [Path A](#path-a--keyless) below
  is the whole of the setup.
- **Anthropic**, or **any OpenAI-compatible endpoint you name** — your own key,
  and every photograph is uploaded in full. [Path B](#path-b--bring-your-own-keys)
  below.

So a first scan that stops saying it cannot reach Ollama is a prerequisite that
is not there yet, not a broken install. Settings says the same thing beside the
field, before you scan rather than after.

### What this release is, and is not

**It is a `0.x` build**, which is deliberate and not modesty: the two file
formats this program writes can still change shape, so a review document
written by one version is not promised to load in the next. The reasoning is
[decision 0014](doc/decisions/0014-stay-in-0-x-until-the-two-file-formats-stop-moving.md).

**Windows x64 is the only build published.** There is no installer, no Android
apk, no macOS or Linux binary, and no auto-updater — a newer version is another
download, and you replace the folder. Building any of the other targets from
source is documented and unchanged: [`doc/build.md`](doc/build.md).

Everything from [Setup](#setup) onwards is the reference and the source build.
None of it is needed to run the download.

## Setup

The CLI needs the Dart SDK (>= 3.4) and nothing else; the app needs the
Flutter SDK, which includes it. Windows is the only host this has been built
and run on.

**None of this is needed to run the Windows app** —
[Windows: download and run](#windows-download-and-run) above is a zip and
no toolchain. What follows is for the CLI, for the other platforms, and
for changing the code.

For a walkthrough of one whole run rather than a reference, see
[doc/guide.md](doc/guide.md).

**shelfscan ships no credentials and runs no proxy.** There is nothing to
sign up for to use this project, and no shared key hidden in the binary.
Everything below is either keyless or uses an account you register
yourself. Which one you want:

| | Path A — keyless | Path B — your own keys |
|---|---|---|
| Vision | local Ollama, on your machine | local Ollama, or a cloud model with your key |
| IGDB ids (game rows) | no | yes |
| TMDB ids (film and animation rows) | no | yes |
| CSV export | yes | yes |
| Custom Cards export (Tonkatsu) | yes — it carries **every** row, since every row is unmatched; each is a title and a kind and nothing else | yes, and it carries only what `.xcoll` left behind, which on a fully matched shelf is nothing |
| `.xcoll` export | no (needs catalogue ids) | yes |
| Registration | none | a Twitch application for IGDB, a TMDB account for films and animation — both free, and each one on its own is enough for its own rows |
| Photos leave the machine | no further than your own Ollama server | only if you pick a cloud model — or a cloud `--fallback`, which uploads all of them |

### Path A — keyless

No account, no key, nothing to configure. This is the default on Windows.

1. Install [Ollama](https://ollama.com) and pull the default vision
   model (~6 GB):

   ```
   ollama pull qwen3-vl:8b-instruct
   ```

2. Put your shelf photos in a folder and scan it:

   ```
   cd packages/shelfscan_core
   dart pub get
   dart run shelfscan_core:shelfscan scan ../../photos -o collection.review.json
   ```

   The run announces both of its choices: `Vision: local Ollama
   (qwen3-vl:8b-instruct)` and `IGDB credentials not set -- resolve stage will be
   skipped, games stay unresolved`. That second line is not an error.

   **A folder straight off your phone works.** JPEG, PNG and WebP are read
   as they are; **HEIC/HEIF/HIF — the phone camera default — is read on
   Windows**, converted to JPEG in a temp directory before the scan, with
   nothing written next to your originals. It is not the extension that
   decides but the file's contents, so a HEIC your phone or a messaging app
   renamed `.jpg` is converted too, and a spreadsheet named `.jpg` is
   skipped rather than uploaded. The run says what it converted (three
   4000×3000 photos, against ~25 s of vision each) and names every file it
   is leaving out, before it starts. *Illustrative output: the filenames
   and the figures in this block are made up, not measured off any
   shelf.*

   ```
   CONVERTED: shelf-1.HEIC -> jpeg in 700 ms
   CONVERTED: shelf-2.HEIC -> jpeg in 400 ms
   CONVERTED: shelf-3.HEIC -> jpeg in 400 ms
   HEIC: 3 file(s) converted to a temp directory in 2000 ms total (process start included). Nothing was written next to the originals.
   SKIPPED: notes.jpg (.jpg) -- named .jpg but the bytes are not a photo this tool reads; the contents decide here, not the name
   ```

   Nothing is dropped quietly, HEIC included. Where it cannot be converted
   — a host that is not Windows, a Windows missing the *HEIF Image
   Extensions* codec (install it from the Microsoft Store), or a file the
   codec fails on — the photo is skipped with the converter's own reason and
   the run continues with the rest:

   ```
   SKIPPED: shelf-1.HEIC (.heic) -- HEIC conversion failed -- HEIC decoding here is Windows-only (it uses the Windows Imaging Component) and this host is linux; convert it to .jpg or .png first
   ```

   A folder that yields no photo at all is an error exit, not a "0 photos"
   success.

3. Open `collection.review.json` and set `"status"` to `approved` or
   `rejected` on each game.

4. Export CSV. *Illustrative output: the figures below are made up, not
   measured off any shelf.*

   ```
   dart run shelfscan_core:shelfscan export collection.review.json --target csv -o shelf.csv
   Exported 18 of 18 approved game(s) -> shelf.csv
   ```

**The limitation of this path:** no IGDB ids, and therefore no `.xcoll`.
The Tonkatsu Box import format *is* a list of IGDB ids (see
[Supported targets](#supported-targets)), so it has nothing to carry
without the resolve stage, and says so rather than writing a file that
silently drops everything.
*Illustrative output: the filenames and the figures in this block are made
up, not measured off any shelf.*

```
dart run shelfscan_core:shelfscan export collection.review.json --target tonkatsu -o shelf.xcoll
Exported 0 of 18 approved game(s) -> shelf.xcoll
  18 left out: the tonkatsu target carries only items with a resolved IGDB match.
```

CSV has no such requirement: it keeps the titles and platforms the
vision model read, with an empty `external_id` column. Neither has
`tonkatsu-cards`, which carries exactly the rows `.xcoll` cannot and imports
into the same app as custom cards — a title and a kind, with no cover and no
catalogue metadata behind them ([Supported targets](#supported-targets)).

### Path B — bring your own keys

Every credential here is optional and independent — take any of them, all
of them, or none. Nothing here is required to run a scan.

**IGDB (game ids, and with them `.xcoll`).** IGDB is authenticated
through Twitch, so the credentials come from a Twitch application:

1. Register at https://dev.twitch.tv/console/apps. A Twitch account with
   2FA enabled is required — the console refuses to create an
   application without it.
2. The redirect URL is unused by this project (it uses the
   client-credentials flow), so any valid value such as
   `http://localhost` is fine.
3. Take the client id and generate a client secret.

**TMDB (film and animation ids).** Film and animation rows are looked up in a
film catalogue rather than in IGDB, and that takes a credential of its own: the
API Read Access Token from https://www.themoviedb.org/settings/api — not
the v3 *API Key*, which TMDB accepts only as a query parameter and would
therefore sit in every URL an error or a log quotes. Without it those rows
are keyless exactly as a game row is without the IGDB pair, and games are
unaffected either way. How far that path has actually been run is in
[Films are read as films](#films-are-read-as-films-and-how-far-that-goes).

**Cloud vision (optional, for harder photos).** Either your own Anthropic
API key from https://console.anthropic.com, or your own key for any
endpoint speaking the OpenAI `/chat/completions` API — Groq, OpenRouter,
Mistral, GitHub Models, Cerebras, Gemini's compatibility endpoint. The
local model is the default; every cloud endpoint is an explicit opt-in,
never a silent fallback.

**Where the keys go.** In the CLI, environment variables — nothing else
is read:

| Variable | Used for |
|---|---|
| `IGDB_CLIENT_ID`, `IGDB_CLIENT_SECRET` | the resolve stage for game rows (unmatched without them) |
| `SHELFSCAN_TMDB_TOKEN` | the resolve stage for film and animation rows (unmatched without it) |
| `ANTHROPIC_API_KEY` | `--provider anthropic` or `--fallback anthropic` |
| `SHELFSCAN_ANTHROPIC_MODEL` | optional; blank uses the built-in default. Naming a model also stops shelfscan stating a temperature, since the newer Claude families reject one — so record which model any numbers came from |
| `SHELFSCAN_OPENAI_BASE_URL`, `SHELFSCAN_OPENAI_MODEL`, `SHELFSCAN_OPENAI_API_KEY` | `--provider openai` or `--fallback openai`; all three are required, nothing is defaulted |
| `SHELFSCAN_OLLAMA_MODEL`, `SHELFSCAN_OLLAMA_URL` | override the local defaults |
| `SHELFSCAN_OLLAMA_FALLBACK_MODEL` | a second LOCAL model that re-reads every photo (`--fallback`); it can never select a cloud one |
| `SHELFSCAN_VISION_TIMEOUT` | whole seconds one vision call is given, 1–1800; blank is 120 s. Raise it only for a model too large for your machine, which is minutes per photo. Anything outside the range is refused, not defaulted |

```
# PowerShell
$env:IGDB_CLIENT_ID = '...'
$env:IGDB_CLIENT_SECRET = '...'

# bash
export IGDB_CLIENT_ID=...
export IGDB_CLIENT_SECRET=...
```

[`.env.example`](.env.example) is a **reference list of variable names
only**. Nothing in this codebase parses a `.env` file — copying it to
`.env` and filling it in has no effect and produces no error. Set the
variables in your shell instead.

In the app, keys go in the settings screen and are stored in the OS
keychain, never in a file inside the repository.

### The app

This is how to build it. A Windows reader who only wants to *run* it does not
come this way — [Windows: download and run](#windows-download-and-run) is that
route, and it needs none of what follows.

Both targets have been built from this tree. Neither builds on a
`flutter doctor` that prints green, and the prerequisites each one is missing
are written down rather than left to be rediscovered: **Windows** in
[`doc/build.md`](doc/build.md), **Android** in
[`doc/android-build.md`](doc/android-build.md) — the toolchain, and four
failures, three of which name something other than the missing step and one of
which does not fail the build at all. Android Studio is not required for
either.

The platform folders are committed, so a clone already has them — what that
means if you edit them is in [`doc/build.md`](doc/build.md). Setup is:

```
cd app
flutter pub get
flutter run -d windows   # or: flutter run -d <android-device>
```

Provider policy lives in one file (`app/lib/provider_config.dart`), and
both platforms offer the same three backends: local (Ollama), Anthropic,
or any OpenAI-compatible endpoint you name. What differs is what *local*
means. On Windows it is a model on the machine in front of you, and it is
the default. **On Android it is a model on another machine:** the phone
reads nothing itself — on-device models are too weak for shelf spines, and
that measurement has not changed — so Local there is an Ollama server you
name on your own network, typically the same desktop that already serves
the Windows app. Nothing can guess that address for you (`localhost` on a
phone *is* the phone), so on Android Local is offered but never the
default, and it will not start until you have put the server's address in
Settings as `http://ADDRESS:PORT`. **What Android defaults to instead is
Anthropic:** a default that cannot work until an address is typed would be
a broken first launch, and an endpoint you name is never a default
anywhere, so the cloud backend is what is left.

**That path keeps your photos off the internet; it does not encrypt
them.** Each one crosses your own network to that server over plain HTTP,
unencrypted and unauthenticated, so anything else on that network can read
it on the way. The app says so where you pick the backend, beside the
cloud warnings. And it is **untried**: no phone has yet been pointed at a
desktop Ollama through this app, so what is written here is what the code
does, not a run anyone has watched.

Both cloud choices warn, where you make them, that every photo is uploaded
in full; the named-endpoint one adds the free-tier training sentence, which
a paid Anthropic account does not need. The app reads each photo with one
model only — the CLI's `--fallback` second reader has no counterpart there.

**Photos: the app takes what the CLI takes**, from the same table in
`shelfscan_core`, and decides by the file's contents rather than by its
name in the same way. Its file dialog offers HEIC — Windows' own "image"
filter does not, which is why phone photos used to be not merely
unreadable but invisible — and on Windows it converts each one in-process,
340–610 ms per 4000×3000 photo, off the UI thread. Whatever it will not
scan it names in a rejected-photos panel the moment you pick it, rather
than minutes later at a provider call. **On Android it converts them
through Android's own codec** rather than through WIC, so a HEIC picked
there is not something you have to convert first; a phone whose Android is
too old to decode HEIF says so in that same panel, one file at a time.

## Commands

```
shelfscan scan <photos_dir> [-o review.json]
                            [--provider anthropic|ollama|openai]
                            [--fallback anthropic|ollama|openai|none]
                            [--aliases <file>]
                            [--installs <games_dir>] [--library]
                            [--galaxy-db <path>]
shelfscan scan-installs <games_dir> [-o review.json] [--aliases <file>]
                                    [--library] [--galaxy-db <path>]
                                                # no vision call, no cost
shelfscan scan-library [-o review.json] [--aliases <file>]
                       [--galaxy-db <path>]
                                                # the whole GOG library,
                                                # installed or not
shelfscan resolve <review.json> [-o out.json] [--aliases <file>]
                                                # IGDB stage only, no vision
shelfscan export <review.json> --target <tonkatsu|csv> -o <file>
```

- **`scan`** — photos in, review file out. `--provider ollama` is the
  default, so the flag matters only to opt in to the cloud:
  `--provider openai` (any OpenAI-compatible endpoint; needs the three
  `SHELFSCAN_OPENAI_*` variables) or `--provider anthropic` (needs
  `ANTHROPIC_API_KEY`). `--fallback` adds a second model that
  re-reads **every** photo and merges the two reads: double the vision
  calls, and with a cloud second reader every photo uploaded — see
  [Where your photos go](#where-your-photos-go) for what that measured.
  `--fallback none` turns it off even when
  `SHELFSCAN_OLLAMA_FALLBACK_MODEL` is set.
  `--aliases` names a different regional-title table than the one below.
- **`scan-installs`** — a directory of PC games in, the same review file
  out, with **no vision call at all**: it reads GoG's own
  `goggame-*.info` where an install has one and falls back to parsing the
  file or folder name where it does not. A video file whose name is
  release-shaped is read as a **film** rather than a game, decided per file
  ([Films](#films-are-read-as-films-and-how-far-that-goes)). Free, instant
  and byte-identical on repeats, because nothing is guessed by a model. Point
  it at a games folder and not at `Downloads`: measured over one, every title
  the name parser produced was an application rather than a game (T-0158), and
  nothing in a filename can tell `NoteWellSetup.exe` from
  `setup_moor_1.9.exe`. The folder measured was a private one: neither its
  listing nor any count of it is published. The command refuses the well-known
  personal and system directories outright and says so on every run.
- **`scan-library`** — GOG Galaxy's own local database in, the same review
  file out, so a game you own but have **not** installed is in the list too.
  No photo, no vision call, no cost, and nothing from `gog.com`: it reads one
  file on this machine, with no login, no OAuth and no credential stored or
  needed. **Windows only** — that is where Galaxy runs. **And Galaxy must be
  installed here and signed in at least once**, because that file is what its
  sync writes: a machine nobody has ever signed in on has nothing to read.
  That is a precondition on Galaxy, not a credential for shelfscan — the
  no-login sentence above still holds, and Galaxy need be neither running nor
  online while you do this. The two ways it can be unmet are reported apart,
  each exiting 2 rather than as a scan that found nothing: **no database at
  all** — Galaxy is not installed, or the file was moved or lost, and Galaxy
  rebuilds it on next launch; and **a database with no rows** — it is there,
  but no GOG account has ever signed in on this machine, or GOG has moved the
  schema out from under the reader. What it reads is a cache of the last sync
  rather than your account, so a game bought since Galaxy last ran is missing,
  and the run prints how old the cache is. DLC, releases Galaxy itself hides,
  and releases from other stores connected to Galaxy are counted out **by name
  rather than dropped silently** — the run names each kind of row it left out.
- **One run, several sources.** A game you own on a disc *and* have installed
  is one game, and only a single run puts the two through one dedupe:
  `--installs` and `--library` add those sources to a scan of your
  photographs, and the run writes one review file in which that game is one
  row. Run the commands separately and you get two files nobody can reconcile
  — and the second `-o` overwrites the first.

  ```
  shelfscan scan D:\photos --installs "C:\GOG Games" --library
  ```

  A command may add sources that cost less than its own, never more:
  `scan-installs` takes `--library`, `scan-library` takes neither, and nothing
  adds photographs to a run that has none — that run is `scan`, which is where
  every vision option already lives.
- **`resolve`** — re-runs the IGDB stage over an existing review file
  without touching a photo or a vision model. Useful after adding
  credentials to a keyless scan, after editing the alias table, and for
  measuring the matcher. It requires IGDB credentials and refuses to run
  without them, since resolving is its entire purpose. Review statuses
  reset to pending: a new match invalidates an earlier approval. Output
  defaults to the input name with `.resolved.json`, so the input is never
  overwritten and before/after runs stay comparable.
- **`export`** — writes the chosen format from the approved items.

### Regional titles: the alias table

A Japanese-market spine reads *Biohazard*; IGDB knows the game as *Resident
Evil* and answers a search for the title as read with nothing at all. The
same for *Rockman* and *Mega Man*. `app/assets/data/title_aliases.json` rewrites the
title before the search, and it is hand-editable on purpose — of the things
that turn a miss into a match, it is the only one that needs no code change.

The file as shipped, in full:

```json
{
  "biohazard": "resident evil",
  "rockman": "mega man",
  "seiken densetsu": "mana"
}
```

- A flat JSON object, `"what the spine says": "what IGDB calls it"`. Both
  sides are lower-cased when loaded, so write them however reads best.
- A key is replaced **wherever it occurs inside the title**, not only when
  the whole title is equal to it: `biohazard re:4` is searched for as
  `resident evil re:4`. So keep keys distinctive — a short one will rewrite
  titles you did not mean it to.
- The search uses the rewritten title; the scoring that follows compares
  every IGDB row against the raw spine text as well. An alias therefore only
  has to get IGDB to return the game, not to name it exactly.
- `--aliases <file>` uses a different file. Without the flag the CLI walks
  up from the working directory looking for `app/assets/data/title_aliases.json`, which
  is why the same command works from the repository root and from
  `packages/shelfscan_core`.
- The file is read at the start of every run: edit, save, re-run. Nothing to
  rebuild or restart. Editing it and re-running `resolve` on an existing
  review file costs no vision calls, which is the cheap way to test a new
  alias.
- Missing or malformed, the run continues on three built-in aliases and says
  so — a bad alias table is a worse scan, not a failed one:

  ```
  WARN: No alias file at app/assets/data/title_aliases.json -- falling back to 3 built-in aliases.
  ```

- It is read by the games resolver only, so a run with no IGDB credentials
  never reads it and editing it changes nothing — including a run that has a
  resolve stage because a TMDB token keyed it.

**Editing the file does not change the running app until you rebuild it.**
The app uses the same file rather than a copy of its own, but it takes it as
a bundled Flutter asset (`app/pubspec.yaml` → `assets/data/title_aliases.json`),
and assets are baked in at build time. So an edit reaches the CLI on the very
next run, and the app on the next `flutter run` / `flutter build`. An
installed app never reads your edited file — on Android there is no such file
to read.

## Supported targets

| Target            | Format          | How to import                              | Needs a catalogue id |
|-------------------|-----------------|--------------------------------------------|----------------------|
| `tonkatsu`        | `.xcoll` light  | Tonkatsu Box → Import → Import Collection  | yes                  |
| `tonkatsu-cards`  | Custom Cards JSON | Tonkatsu Box → Settings → *Custom cards*   | no                   |
| `csv`             | generic CSV     | Import dialog of most collection managers  | no                   |

The `.xcoll` light format carries catalogue ids and platform ids only —
Tonkatsu Box fetches titles and covers itself on import. An item with no
resolved match has nothing to put in it, so `export --target tonkatsu`
leaves such items out and reports how many. CSV carries the text, so it
takes them either way.

### The two Tonkatsu paths, and what the second one is not

The two Tonkatsu targets **partition** one review file. A row with a match the
light format can carry goes to `.xcoll`; every other approved row goes to
Custom Cards, and no row goes to both. So a shelf that resolved unevenly is two
files and two imports rather than one file and a list of losses:

```
dart run shelfscan_core:shelfscan export collection.review.json --target tonkatsu -o shelf.xcoll
dart run shelfscan_core:shelfscan export collection.review.json --target tonkatsu-cards -o shelf-cards.json
```

**A Custom Card is a name, not an identity, and that is the whole difference.**
It carries the title and the kind, plus the raw title as read and the platform
where this project holds one honestly. The receiving app stores it as a custom
item: **no catalogue entry, no cover, no metadata, no description, no genres**.
Nothing later refetches or updates it. Do not expect the `.xcoll` experience
from it — expect the row to exist, spelled the way you approved it, instead of
being dropped.

**It needs no credential at all**, which is the part that matters for
[Path A](#path-a--keyless): the rows it carries are exactly the ones nothing
matched, so a wholly keyless run has a Tonkatsu import of its own for the first
time. `.xcoll` still needs the ids and still gets none on such a run.

**`cover` is the one field this project refuses on principle.** The Custom
Cards format accepts a cover, and only as an `http(s)` URL; the only image here
is a photograph on your own disk, so no export ever writes that key.

**Nothing was removed to make room for any of this.** Every provider, every
lookup and both existing exports behave exactly as they did — the registry was
appended to, and `.xcoll` and CSV write the same bytes for the same document.

**`version: 2` is pinned on purpose, and the reason is compatibility rather
than age.** Tonkatsu Box writes v3 and accepts v2 on import; v3's difference is
that `user_rating` became a one-decimal number instead of an integer, a field
this project never writes — and older builds reject a v3 file cleanly. So a
`version: 2` file is read by more installations than a v3 one and loses nothing
this project could have put in it. The reference is `docs/RCOLL_FORMAT.md` in
`hacan359/tonkatsu_box`, branch `release/0.44`.

A smaller handover — a name and a type, with the receiving app doing its own
catalogue resolution — **is being evaluated and is not supported**: nothing
upstream has agreed to it, and `.xcoll` remains the contract. The audit and the
open questions are in
[doc/integrations/tonkatsu-handoff.md](doc/integrations/tonkatsu-handoff.md).

### CSV columns

```
title,platform,media_type,external_id,source_photo
```

`external_id` is what the catalogue that resolved the row calls it, in the
form `catalogue:id` — `igdb:1234`. The prefix names which catalogue
answered, so a consumer splits at the first `:` rather than assuming one.
It is empty when nothing resolved the row, which is every row on a keyless
run. `igdb:` and `tmdb:` are the two anything writes today: a game row carries
the first, and a film row carries the second when the run had a TMDB token
([Films](#films-are-read-as-films-and-how-far-that-goes)).

There is no column for the kind of work a row is. `media_type` is the physical
carrier it came on — `disc`, `cartridge` or `unknown` — and a film row and a
game row are told apart by nothing in this file.

`source_photo` is the photo the title was read *off*, and is empty when it
was read off none — a row you typed at review, or one taken from an
installed game.

A scan that read anything other than a photograph (`scan-installs`,
`scan-library`, the app's games folder) appends three more columns, so
that such a run says where its rows came from:

```
title,platform,media_type,external_id,source_photo,source_entry,origin,source_id
```

| column | what it is |
|--------|------------|
| `source_entry` | the file or folder the row was read from — `goggame-1100000008.info`, `setup_harbour_lantern_1.0.exe` |
| `origin` | `vision` (read off a photo), `manual` (typed at review), `metadata` (the installer wrote this title), `filename` (guessed from a name) |
| `source_id` | what the store calls the game, `catalogue:id` — `gog:1100000008`. Empty when there is none |

The three are absent from an export that has nothing to put in them, so a
photo-only CSV is exactly the five columns it has always been. Map by
column name rather than by position if you feed both kinds into the same
script; the first five columns never move.

#### Opening the CSV in a spreadsheet

This file is written for an import dialog, and that is where it behaves.
A spreadsheet is a different reader: **Excel, LibreOffice and Google
Sheets evaluate any cell whose text begins with `=`, `+`, `-` or `@` as a
formula.** A folder of yours named `-Tactics` arrives in `source_entry`
spelled exactly that way and shows up in Excel as an error such as
`#NAME?`. This is about the cell's content, not the file's syntax, so
quoting the field does not change it and nothing in the CSV format can.

**shelfscan writes your names through unchanged.** The usual defence is a
leading `'`, and it is not used here: the apostrophe is Excel's own
syntax, so every importer that is not a spreadsheet — which is every
consumer this file is written for — would take it as part of the title.
Defusing the spreadsheet would corrupt the import dialog.

So if you want to look at the file in a spreadsheet, import it rather
than double-click it, and set the columns to Text: Excel's *Data → From
Text/CSV*, LibreOffice's Text Import dialog (leave *Evaluate formulas*
unticked). A text editor needs no such care.

**You do not have to remember any of this.** An export that writes such a
cell names it — the CLI after `Exported N of M`, the app on the message
that reports the saved file — and an export that writes none says nothing
extra.

## Where your photos go

These are pictures of your home, so it is worth being exact. Every photo
is sent, in full, to every vision model the run is configured with — one
call per photo per model. Nothing downscales, crops or samples them, and
this project has no telemetry, no cache and no server of its own. A HEIC
is converted to JPEG at its original dimensions before the call — that is
the only change ever made to a photo here, and the JPEG lives in a temp
directory, never next to your original.

- **Local provider (`--provider ollama`, the app's Local backend; the
  default on desktop):** each photo is POSTed to your own Ollama server
  and nowhere else. That server is `http://localhost:11434` unless you
  point `SHELFSCAN_OLLAMA_URL` (CLI) or the Ollama URL in Settings (app)
  at something else — so "never leaves the machine" holds exactly as long
  as that address is your machine. Aimed at a box on your LAN, it ships
  the photos there over plain HTTP. **On Android that is the only shape
  Local has:** the phone runs no model, so the address is always another
  machine and the photos always cross your network unencrypted and
  unauthenticated. They still reach nothing on the internet.
- **An OpenAI-compatible endpoint (`--provider openai`, the app's
  Endpoint backend):** every photo is uploaded in full to whatever
  endpoint you named in `SHELFSCAN_OPENAI_BASE_URL` or in Settings. This
  is the case to read the terms of first: free tiers are commonly funded
  by training on what is submitted to them. It is why no endpoint is ever
  a default here — a base URL this project picked for you would be a
  service you never chose.
- **Anthropic (`--provider anthropic`, the app's Cloud backend):** every
  photo is uploaded in full to Anthropic. **It is the app's default on
  Android**, where the phone runs no model of its own and Local means a
  server on your own network that cannot work until you have typed its
  address — so a phone scans through Anthropic unless you choose
  otherwise. Nothing is uploaded before you have supplied your own key:
  a cloud backend without one is refused at the tap, naming the credential
  it wants, and the run makes no call at all.
- **`--fallback` — a second model, on top of any of the above:** it
  re-reads **every** photo, not the ones the first model struggled with,
  and the two reads are merged. So the run makes twice the vision calls,
  and with a cloud second reader **every photo is uploaded** — including
  on a run whose primary was local and which therefore looks local. That
  is why a cloud second reader takes `--fallback openai` or
  `--fallback anthropic` typed on the command line: no environment variable
  can turn a local run into a cloud one, and
  `SHELFSCAN_OLLAMA_FALLBACK_MODEL` selects a second *local* model and
  nothing else. The run says which one
  it got, and how many extra calls it is worth, before it starts.
- **IGDB (the resolve stage, game rows):** receives the title strings the
  vision model read, never an image, and your own Twitch client id and
  secret go to `id.twitch.tv` for an access token. Without those
  credentials game rows go unmatched and neither service is contacted at
  all.
- **TMDB (the resolve stage, film and animation rows):** receives the title
  strings those rows were read as — and the release year, when the file
  name carried one — never an image, and your own API Read Access Token
  goes to TMDB with every search. Without it those rows go unmatched and
  TMDB is not contacted at all.

### What `--fallback` actually bought

<!-- measured-on: qwen2.5vl:7b -->

Measure before you turn it on. The one second reader measured here —
`gemma3:12b` behind `qwen2.5vl:7b`, on the three 4000×3000 control photos
— added 15 rows and took the run from 70 s to 146 s. Every one of those
added rows was checked against the photographs, and **every one was wrong**:

- **9** were second readings of spines the first model had *already read
  correctly*, kept apart as separate rows by as little as one character
  (a base title alongside the same title carrying its sequel's subtitle).
- **6** were invented or misread, including two titles welded out of
  characters from two different spines, and one invented Japanese title
  on a photo whose Japanese spines that same model had just reported as
  unreadable.
- **0** were an item the first model had missed — which is the entire
  reason to run a second one.

<!-- /measured-on -->

A wrong row can be rejected at review and a missing one cannot, so this
is a trade rather than a disaster. But it is a **local** second reader
that was measured. A cloud one has never been measured here — no cloud key
was available (T-0057) — so nothing above is evidence about
what `--fallback openai` or `--fallback anthropic` would buy, and turning
one on to find out uploads every photo.

Since T-0061 this is a **CLI flag only**. The app has one reader per
photo and never asks for a second, so there is no switch for it in
Settings and nothing to look for.

## Repository layout

```
packages/shelfscan_core/   # pure Dart pipeline (no Flutter deps) + CLI
app/                       # Flutter shell: Windows (built and run), Android (never run here)
```

## How it works

sources → dedupe → catalogue resolver workers (parallel, fuzzy matching +
[regional aliases](#regional-titles-the-alias-table)), routed by the kind of
each row → review file → exporter. Photographs are one source among four and
take one extra stage of their own: vision workers, in parallel, one call per
photo per model.

See [ARCHITECTURE.md](ARCHITECTURE.md) for the diagrams and the platform
boundary, and [doc/decisions/](doc/decisions/) for why the non-obvious pieces
are the way they are — each record carrying the measurement that settled it.

## Development workflow

Contributing? Start with [CONTRIBUTING.md](CONTRIBUTING.md) — how to run the
two test suites, and what a change must not silently break. What this
repository publishes and what it leaves out is there too, under
[What is published, and what is not](CONTRIBUTING.md#what-is-published-and-what-is-not),
and so is the rule every edit to this file is held to:
[Translations](CONTRIBUTING.md#translations).

## Disclaimer

This project is not affiliated with, endorsed by, or connected to
Tonkatsu Box, CLZ, or GAMEYE. All product names and trademarks are the
property of their respective owners. Game metadata is provided by IGDB.

This application uses TMDB and the TMDB APIs but is not endorsed, certified,
or otherwise approved by TMDB. It reaches those APIs only with a TMDB token
you supply yourself.

<img src="app/assets/tmdb/blue_long_1.svg" alt="TMDB" width="180">

## Licence

shelfscan is MIT-licensed: [`LICENSE`](LICENSE).

One file is excluded from that grant. `app/assets/tmdb/blue_long_1.svg` is
TMDB's mark, shipped unaltered for attribution, and this project grants no
rights over it — no right to modify, sublicense or sell it.
[`NOTICE`](NOTICE) records the exclusion.
