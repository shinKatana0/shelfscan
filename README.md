**English** · [Русский](README.ru.md) · [日本語](README.ja.md)

<!-- TRANSLATIONS — read this before you edit the text below.
     README.ru.md and README.ja.md make the same claims as this file. Change
     anything here beyond a typo and both are stale. In the same commit either
     update them, or set the "Translated from" line at the top of each to
     STALE — marking is cheap and honest, a silent lag is neither.
     The rule in full, and why there is no CI check for it: "Translations",
     under Development workflow, at the end of this file. -->

# shelfscan

[![CI](https://github.com/shinKatana0/shelfscan/actions/workflows/ci.yml/badge.svg)](https://github.com/shinKatana0/shelfscan/actions/workflows/ci.yml)

**shelfscan turns a game collection you already own into a file another app
can import.** Photograph a shelf and a vision model reads the spines. Point it
at a folder of installed PC games, or at the GOG Galaxy library on your
machine, and it reads those with no model and no cost at all. Everything from
one run lands in a single review file you confirm by hand, and out of that
comes `.xcoll` for Tonkatsu Box — which fetches covers and metadata itself
from the ids in it — or generic CSV for CLZ Games and most other collection
managers.

It owns **no catalog UI and no database**: recognition and export, nothing
else. Four sources go through one dedupe, so a game you own on a disc *and*
have installed is one row, not two. There is a command-line tool and a Flutter
app; both run the same pipeline.

It is not affiliated with any of the apps it feeds ([disclaimer](#disclaimer)).

## What it cannot do

The honest half, up front. Every line here is measured, and the section it
links to has the numbers.

- **Android is the thinner of the two platforms.** Both Windows and Android
  are built and run from this tree, but two things are Windows-only by
  construction: HEIC photos from a phone are converted through
  the Windows Imaging Component, and the GOG Galaxy library is read from
  Galaxy's own database, and Galaxy is a Windows program. There is no
  installer and no published binary — you build it from source
  ([Setup](#setup)).
- **It is exactly as good as the vision model you supply, and the free one has
  a known ceiling.** The default local `qwen2.5vl:7b` reads a Latin-script
  spine well and does not read the printed *Switch 2* band at all — those
  cases come back hinted `PS2`. It *does* transcribe Japanese script at full
  resolution; at low resolution it omits the Japanese spines, which is the
  right answer there because they are illegible rather than merely foreign.
  A cloud model is not automatically better: `gpt-4.1-mini` reads none of
  those Japanese spines, which the local model does. Only
  `gpt-5.5` reads both the script and the band, and charges for it
  ([the measured difference](#which-model-and-what-it-changes)).
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
- **The Tonkatsu `.xcoll` export needs IGDB ids**, so it needs an IGDB
  credential. Without one the run still works and exports CSV
  ([Path A](#path-a--keyless)).
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
- **A folder of installers is not a games folder.** Names alone cannot tell
  `NoteWellSetup.exe` from `setup_moor_1.9.exe` — measured on a real `Downloads`
  folder, every title the name parser produced was an application rather than a
  game — so the command refuses the well-known personal and system directories
  outright. That folder was a private one and its contents are not published.
- **"Local" does not mean "offline".** A local run POSTs every photo to your
  Ollama server, and that address is yours to set: pointed at a box on the LAN
  it ships the photographs there over plain HTTP
  ([where your photos go](#where-your-photos-go)).

## Try it without an account

No key, no registration, nothing to sign up for. You need the Dart SDK (the
CLI alone needs no Flutter), [Ollama](https://ollama.com), and a ~6 GB model
download.

```
ollama pull qwen2.5vl:7b

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

**Bring your own keys.** This project ships no credentials and runs no proxy;
there is no shared key hidden in the binary and nothing to sign up for to use
it. Keys live in environment variables (CLI) or the OS keychain (app), never in
a file inside the repository.

**Nothing is telemetered.** No analytics, no crash reporting, no server of this
project's own, no cache. The only things ever sent anywhere are the photographs
you scan — to the vision model *you* configured, and to nothing else — and the
title strings the resolve stage sends to IGDB, which is never an image. Exactly
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

Measured on two real shelf photos with the default local model
(`qwen2.5vl:7b`):

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

| | `qwen2.5vl:7b` (local, default) | `gpt-4.1-mini` | `gpt-5.5` |
|---|---|---|---|
| Cost | **$0** | your key | your key — about **$0.45** for a three-photo shelf scan |
| Latin-script spines | ~93% correct | comparable detection counts, photo by photo | comparable or slightly higher; reads a glare-struck title `gpt-4.1-mini` misreads |
| Japanese-script spines | **read** at full resolution, with the platform wrong; omitted at low resolution, where they are illegible | **not read** — none of them | **read**, every one, on five runs of five, with the platform right |
| The printed *Switch 2* band | **not read** — those cases come back hinted `PS2` | not read | **read per spine** — every `SWITCH 2` hint correct across the three full-resolution photographs, five runs each, and no false positive on a case whose band prints none. The third photograph contributes none: the frame cuts a column at its edge, and the cases in the cut print the band but are not read — so that tally counts hints given rather than bands present. At 1200×900 the band was checked on one photograph and every case in it is read correctly over five runs; that is a separate measurement |
| Invention | none on either control set | misreads that glare-struck title on 3 of 5 low-resolution runs | one invented title, on 2 of 5 runs — the same spine twice, out of everything read across the three full-resolution photographs; none at all at 1200×900 |

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

## Setup

The CLI needs the Dart SDK (>= 3.4) and nothing else; the app needs the
Flutter SDK, which includes it. Windows is the only host this has been built
and run on.

For a walkthrough of one whole run rather than a reference, see
[doc/guide.md](doc/guide.md).

**shelfscan ships no credentials and runs no proxy.** There is nothing to
sign up for to use this project, and no shared key hidden in the binary.
Everything below is either keyless or uses an account you register
yourself. Which one you want:

| | Path A — keyless | Path B — your own keys |
|---|---|---|
| Vision | local Ollama, on your machine | local Ollama, or a cloud model with your key |
| IGDB ids | no | yes |
| CSV export | yes | yes |
| `.xcoll` export | no (needs IGDB ids) | yes |
| Registration | none | Twitch application (free) |
| Photos leave the machine | no further than your own Ollama server | only if you pick a cloud model — or a cloud `--fallback`, which uploads all of them |

### Path A — keyless

No account, no key, nothing to configure. This is the default on Windows.

1. Install [Ollama](https://ollama.com) and pull the default vision
   model (~6 GB):

   ```
   ollama pull qwen2.5vl:7b
   ```

2. Put your shelf photos in a folder and scan it:

   ```
   cd packages/shelfscan_core
   dart pub get
   dart run shelfscan_core:shelfscan scan ../../photos -o collection.review.json
   ```

   The run announces both of its choices: `Vision: local Ollama
   (qwen2.5vl:7b)` and `IGDB credentials not set -- resolve stage will be
   skipped, games stay unresolved`. That second line is not an error.

   **A folder straight off your phone works.** JPEG, PNG and WebP are read
   as they are; **HEIC/HEIF/HIF — the phone camera default — is read on
   Windows**, converted to JPEG in a temp directory before the scan, with
   nothing written next to your originals. It is not the extension that
   decides but the file's contents, so a HEIC your phone or a messaging app
   renamed `.jpg` is converted too, and a spreadsheet named `.jpg` is
   skipped rather than uploaded. The run says what it converted (three
   4000×3000 photos, against ~25 s of vision each) and names every file it
   is leaving out, before it starts:

   ```
   CONVERTED: shelf-1.HEIC -> jpeg in 652 ms
   CONVERTED: shelf-2.HEIC -> jpeg in 361 ms
   CONVERTED: shelf-3.HEIC -> jpeg in 369 ms
   HEIC: 3 file(s) converted to a temp directory in 1907 ms total (process start included). Nothing was written next to the originals.
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
vision model read, with an empty `external_id` column.

### Path B — bring your own keys

Both credentials are optional and independent — take either, both, or
neither. Nothing here is required to run a scan.

**IGDB (game ids, and with them `.xcoll`).** IGDB is authenticated
through Twitch, so the credentials come from a Twitch application:

1. Register at https://dev.twitch.tv/console/apps. A Twitch account with
   2FA enabled is required — the console refuses to create an
   application without it.
2. The redirect URL is unused by this project (it uses the
   client-credentials flow), so any valid value such as
   `http://localhost` is fine.
3. Take the client id and generate a client secret.

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
| `IGDB_CLIENT_ID`, `IGDB_CLIENT_SECRET` | the resolve stage (skipped without them) |
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

Both targets have been built and run from this tree. Neither builds on a
`flutter doctor` that prints green, and the prerequisites each one is missing
are written down rather than left to be rediscovered: **Windows** immediately
below, **Android** in [`doc/android-build.md`](doc/android-build.md) — the
toolchain, and four failures, three of which name something other than the
missing step and one of which does not fail the build at all. Android Studio
is not required for either.

**The platform folders are committed.** `flutter create` scaffolded
`app/windows/` and `app/android/` once; ever since they have been hand-edited
source carrying the release identity — `Runner.rc`, the `AndroidManifest.xml`,
the `applicationId`, the icons — and they are reviewed like any other file.
What is genuinely generated inside one is ignored by the `.gitignore` that
`flutter create` writes into that folder, and build output is a different path
again. The [`.gitignore`](.gitignore) comment at the entry says the same at
more length.

So a clone already has them, and setup is:

```
cd app
flutter pub get
flutter run -d windows   # or: flutter run -d <android-device>
```

**Do not run `flutter create` over this checkout.** It regenerates those
folders and hands back `com.example` in place of the identity above, and on
Android it also drops the `INTERNET` permission that a release build has no
other way to get — a loss no build fails on and no debug build reproduces. If
you have already run it, `git status` names every file it touched and
`git checkout --` on those files puts them back.

`flutter create` also writes two files from the default counter template that
are not part of this project and are not tracked here: `app/README.md` and
`app/test/widget_test.dart`. Delete both. The test pumps a `MyApp` that does
not exist here (this app is `ShelfscanApp`), so leaving it in place makes
`flutter test` fail on a file nobody wrote:

```
test/widget_test.dart:16:35: Error: Couldn't find constructor 'MyApp'.
```

Neither is gitignored, deliberately: being untracked and unignored is what
makes `git status` name them, and that is the only warning you get that the
command ran at all.

#### Windows: two prerequisites `flutter doctor` will not tell you about

**A green `flutter doctor` does not mean the Windows build will work.** Its
Visual Studio check looks for the `Desktop development with C++` workload
plus exactly two components (`VC.Tools.x86.x64` and `VC.CMake.Project`),
and it has no Windows Developer Mode check at all — so it prints
`[✓] Visual Studio - develop Windows apps` while both of the things below
are missing. The first build of this app hit them in this order.

**1. Turn on Windows Developer Mode.** Without it `flutter create` and
every build that has plugins abort with:

```
Building with plugins requires symlink support.

Please enable Developer Mode in your system settings. Run
  start ms-settings:developers
to open settings.
```

Flutter links plugin sources into the build with symlinks, and Windows
allows only administrators to create symlinks until Developer Mode is on.
Run that `start ms-settings:developers` command and flip the switch. It is
off on a fresh machine: the registry value it writes,
`HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock\AllowDevelopmentWithoutDevLicense`,
does not exist at all until Developer Mode is enabled the first time, and
reads `1` afterwards.

**2. Add the C++ ATL component to Visual Studio.** The
`Desktop development with C++` workload does not include ATL — it is a
separate entry under *Individual components*. Without it the build runs the
whole toolchain and then dies on a single plugin:

```
flutter_secure_storage_windows_plugin.cpp(6): fatal error C1083: Cannot open include file: 'atlstr.h': No such file or directory
```

Visual Studio Installer → Modify → **Individual components** → search
`ATL` → tick **C++ ATL for x64/x86 (Latest MSVC)**. That is the name in
Build Tools 2026; the wording tracks the toolset, so VS 2022 lists the same
thing as `C++ ATL for latest v143 build tools (x86 & x64)`. The name is
also translated in a localized installer, so the handle that always works
is the component id `Microsoft.VisualStudio.Component.VC.ATL`.

The compiler's error text is localized the same way: on a Russian install
that C1083 line reads `Не удается открыть файл включение: atlstr.h`. The
tokens that survive translation are `C1083` and `atlstr.h` — search your
console output for those, not for the English sentence.

The ATL dependency is ours rather than Flutter's: `flutter_secure_storage`,
which keeps the BYOK credentials in the OS keychain, is the only thing in
this project that includes `<atlstr.h>`.

#### What the first successful build looks like

Measured on Flutter 3.47.0 stable, Visual Studio Build Tools 2026
18.9.12105.275 with MSVC 14.51.36231, Windows 11 25H2:

| Command | Cold build | Produces |
|---|---|---|
| `flutter build windows --debug` — what `flutter run -d windows` compiles | 124 s | `app\build\windows\x64\runner\Debug\shelfscan_app.exe` |
| `flutter build windows` | 164 s | `app\build\windows\x64\runner\Release\shelfscan_app.exe` |

Cold means nothing cached — no `build\`, no `.dart_tool\`. Expect a couple of
minutes and do not assume it has hung.

The release exe is only 90 KB and does not run alone: `flutter_windows.dll`,
`data\`, and one DLL per plugin sit beside it. Distribute the folder.

#### Do not delete `app\build\` by hand — use `flutter clean`

Clearing the build output by hand while leaving `app\.dart_tool\` in place is
the obvious reflex and it breaks every later build, debug and release alike.
The build compiles everything successfully and then dies at the INSTALL
project:

```
error MSB3073: "...\cmake.exe" -DBUILD_TYPE=Debug -P cmake_install.cmake [...\app\build\windows\x64\INSTALL.vcxproj]
```

Nothing in that names the cause. It is visible only by running that same
cmake line by hand from `app\build\windows\x64`:

```
CMake Error at cmake_install.cmake:231 (file):
  file INSTALL cannot find
  ".../app/build/native_assets/windows": No error.
```

**The cause: the incremental cache in `.dart_tool\flutter_build` outlived the
directory it describes in `build\`.** The `install_code_assets` stamp there
still validates, so the step that creates `build\native_assets\windows` is
skipped, while CMake's install step still requires that directory to exist.
`flutter pub get` does not clear the stamp and does not help.

The fix:

```
cd app
flutter clean
flutter pub get
flutter build windows --debug
```

`flutter clean` removes `build\` and `.dart_tool\` together, which is why it
works where deleting `build\` alone does not.

This is **not** a fresh-clone problem — a genuinely cold tree builds fine (the
table above), so there is no reason to run `flutter clean` after cloning.

As with the ATL error above, the MSBuild wrapper text is localized; the tokens
that survive translation are `MSB3073`, `cmake_install.cmake`,
`INSTALL.vcxproj` and `native_assets`.

Provider policy differs per platform and lives in one file
(`app/lib/provider_config.dart`): Windows offers local (default),
Anthropic, or any OpenAI-compatible endpoint you name; **Android is
cloud-only** — on-device models are too weak for shelf spines, so the
Android app needs your own vision key. Both cloud choices warn, where you
make them, that every photo is uploaded in full; the named-endpoint one
adds the free-tier training sentence, which a paid Anthropic account does
not need. The app reads each photo with one model only — the CLI's
`--fallback` second reader has no counterpart there.

**Photos: the app takes what the CLI takes**, from the same table in
`shelfscan_core`, and decides by the file's contents rather than by its
name in the same way. Its file dialog offers HEIC — Windows' own "image"
filter does not, which is why phone photos used to be not merely
unreadable but invisible — and on Windows it converts each one in-process,
340–610 ms per 4000×3000 photo, off the UI thread. Whatever it will not
scan it names in a rejected-photos panel the moment you pick it, rather
than minutes later at a provider call. **On Android it converts nothing:**
the HEIC codec it uses is part of Windows, so a HEIC picked there is
rejected with that reason and you convert it first.

## Commands

```
shelfscan scan <photos_dir> [-o review.json]
                            [--provider anthropic|ollama|openai]
                            [--fallback anthropic|ollama|openai|none]
                            [--aliases data/title_aliases.json]
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
  `--provider anthropic` (needs `ANTHROPIC_API_KEY`) or
  `--provider openai` (any OpenAI-compatible endpoint; needs the three
  `SHELFSCAN_OPENAI_*` variables). `--fallback` adds a second model that
  re-reads **every** photo and merges the two reads: double the vision
  calls, and with a cloud second reader every photo uploaded — see
  [Where your photos go](#where-your-photos-go) for what that measured.
  `--fallback none` turns it off even when
  `SHELFSCAN_OLLAMA_FALLBACK_MODEL` is set.
  `--aliases` names a different regional-title table than the one below.
- **`scan-installs`** — a directory of PC games in, the same review file
  out, with **no vision call at all**: it reads GoG's own
  `goggame-*.info` where an install has one and falls back to parsing the
  file or folder name where it does not. Free, instant and byte-identical
  on repeats, because nothing is guessed by a model. Point it at a games
  folder and not at `Downloads`: measured over one, every title the name
  parser produced was an application rather than a game (T-0158), and nothing
  in a filename can tell `NoteWellSetup.exe` from `setup_moor_1.9.exe`. The
  folder measured was a private one: neither its listing nor any count of it
  is published. The command refuses the well-known personal and
  system directories outright and says so on every run.
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
same for *Rockman* and *Mega Man*. `data/title_aliases.json` rewrites the
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
  up from the working directory looking for `data/title_aliases.json`, which
  is why the same command works from the repository root and from
  `packages/shelfscan_core`.
- The file is read at the start of every run: edit, save, re-run. Nothing to
  rebuild or restart. Editing it and re-running `resolve` on an existing
  review file costs no vision calls, which is the cheap way to test a new
  alias.
- Missing or malformed, the run continues on three built-in aliases and says
  so — a bad alias table is a worse scan, not a failed one:

  ```
  WARN: No alias file at data/title_aliases.json -- falling back to 3 built-in aliases.
  ```

- It is used by the resolve stage only, so on a keyless run (no IGDB
  credentials, no resolve stage) nothing reads it and editing it changes
  nothing.

**Editing the file does not change the running app until you rebuild it.**
The app uses the same file rather than a copy of its own, but it takes it as
a bundled Flutter asset (`app/pubspec.yaml` → `../data/title_aliases.json`),
and assets are baked in at build time. So an edit reaches the CLI on the very
next run, and the app on the next `flutter run` / `flutter build`. An
installed app never reads your edited file — on Android there is no such file
to read.

## Supported targets

| Target     | Format         | How to import                                  | Needs IGDB ids |
|------------|----------------|------------------------------------------------|----------------|
| `tonkatsu` | `.xcoll` light | Tonkatsu Box → Import → Import Collection      | yes            |
| `csv`      | generic CSV    | Import dialog of most collection managers      | no             |

The `.xcoll` light format carries IGDB ids and platform ids only —
Tonkatsu Box fetches titles and covers itself on import. An item with no
resolved match has nothing to put in it, so `export --target tonkatsu`
leaves such items out and reports how many. CSV carries the text, so it
takes them either way.

### CSV columns

```
title,platform,media_type,external_id,source_photo
```

`external_id` is what the catalogue that resolved the row calls it, in the
form `catalogue:id` — `igdb:1234`. The prefix names which catalogue
answered, so a consumer splits at the first `:` rather than assuming one.
It is empty when nothing resolved the row, which is every row on a keyless
run.

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
  the photos there over plain HTTP.
- **Anthropic (`--provider anthropic`, the app's Cloud backend):** every
  photo is uploaded in full to Anthropic.
- **An OpenAI-compatible endpoint (`--provider openai`, the app's
  Endpoint backend):** every photo is uploaded in full to whatever
  endpoint you named in `SHELFSCAN_OPENAI_BASE_URL` or in Settings. This
  is the case to read the terms of first: free tiers are commonly funded
  by training on what is submitted to them. It is why no endpoint is ever
  a default here — a base URL this project picked for you would be a
  service you never chose.
- **`--fallback` — a second model, on top of any of the above:** it
  re-reads **every** photo, not the ones the first model struggled with,
  and the two reads are merged. So the run makes twice the vision calls,
  and with a cloud second reader **every photo is uploaded** — including
  on a run whose primary was local and which therefore looks local. That
  is why a cloud second reader takes `--fallback anthropic` or
  `--fallback openai` typed on the command line: no environment variable
  can turn a local run into a cloud one, and
  `SHELFSCAN_OLLAMA_FALLBACK_MODEL` selects a second *local* model and
  nothing else. The run says which one
  it got, and how many extra calls it is worth, before it starts.
- **IGDB (the resolve stage):** receives the title strings the vision
  model read, never an image, and your own Twitch client id and secret go
  to `id.twitch.tv` for an access token. Without those credentials the
  stage is skipped and neither service is contacted at all.

### What `--fallback` actually bought

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

A wrong row can be rejected at review and a missing one cannot, so this
is a trade rather than a disaster. But it is a **local** second reader
that was measured. A cloud one has never been measured here — no cloud key
was available (T-0057) — so nothing above is evidence about
what `--fallback anthropic` or `--fallback openai` would buy, and turning
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

sources → dedupe → IGDB resolver workers (parallel, fuzzy matching +
[regional aliases](#regional-titles-the-alias-table)) → review file →
exporter. Photographs are one source among four and take one extra stage of
their own: vision workers, in parallel, one call per photo per model.

See [ARCHITECTURE.md](ARCHITECTURE.md) for the diagrams and the platform
boundary, and [doc/decisions/](doc/decisions/) for why the non-obvious pieces
are the way they are — each record carrying the measurement that settled it.

## Development workflow

Contributing? Start with [CONTRIBUTING.md](CONTRIBUTING.md) — how to run the
two test suites, and what a change must not silently break. The rest of this
section is how the work itself is organised.

Almost every line here was written by an orchestrator/worker agent workflow
powered by [briefboard](https://github.com/shinKatana0/briefboard) — a task
board with a mandatory written brief before implementation and a review before
merge. Each task's brief, its worker's report and the board itself stay on a
private disk and **are not published** — they are development artefacts rather
than product, they quote conversations verbatim, and there are roughly 25,000 lines
of them against the ~2,100 lines of distilled record that replaced them here:
[ARCHITECTURE.md](ARCHITECTURE.md) for how it is put together,
[doc/decisions/](doc/decisions/) for why, and
[doc/measurements.md](doc/measurements.md) for what that rests on.

**So a task id is not a link.** Pages here cite ids like `T-0086` because an id
is a stable name for a decision, and a claim that names its origin can be
checked by whoever holds that record. Nothing published depends on looking one
up.

The board is not something a contributor installs, either. It is one person's
working tool; a pull request is reviewed as a pull request.

### Translations

Four files are translations: [`README.ru.md`](README.ru.md),
[`README.ja.md`](README.ja.md), [`doc/guide.ru.md`](doc/guide.ru.md) and
[`doc/guide.ja.md`](doc/guide.ja.md). **English is the source.** A translation
follows this file and `doc/guide.md`; it never leads them, and a claim that
exists in only one language is a bug in the translation.

A translation that has quietly fallen behind is worse than no translation at
all, because a reader trusts it and has no way to tell. So each translated file
records, at the top of the file, the commit its English original stood at when
it was written — an HTML comment in `README.ru.md` and `README.ja.md`, a visible
line in the two guides — and one command answers whether that is still true:

```
git log --oneline <that commit>..HEAD -- README.md
```

No output means the translation is current. Any output is the list of English
changes it has not caught up with, and the reader can decide what that costs
them.

**Editing the English obliges one of two things in the same commit:** update
the translation, or replace its `Translated from` line with `STALE`, naming the
commit the English moved to. Marking is the cheap option and it is the right
one when you do not read the language — nobody is asked to fake a translation,
only to stop the file claiming a currency it lost.

**Marking is not enough when the edit *removed* something.** The marker is an
HTML comment, so on GitHub the deleted thing renders and the warning about it
does not. A translation behind by an **addition** costs its reader a paragraph
they cannot see; one behind by a **removal** leaves them holding the thing
English deleted, with no signal at all. That is not hypothetical: both
translated READMEs went on giving a `flutter create` command as the setup step
— the one that overwrites the committed platform folders and drops the
`INTERNET` permission a release build has no other way to get — correctly
marked `STALE` the whole time, and on the rendered page the mark was invisible
and the command was not.

So the cheap option carries a rider, and it is narrow enough to follow without
thinking about it:

**If your English edit deleted or replaced a command, a fenced code block, a
flag, a path or a file name, make the same deletion or replacement in all four
translated files, in the same commit — then mark them `STALE` as usual.**

That needs no knowledge of the target language, because what it applies to is
exactly what is never translated (the paragraph below): the text you removed is
byte-identical in every file that still carries it, so one command finds every
copy.

```
grep -n "the line you just deleted" README.ru.md README.ja.md doc/guide.ru.md doc/guide.ja.md
```

Delete what it names, or paste the English's replacement over it. The
translation is then behind by an **addition** again, which is the case the
marker already handles.

**The hole gets no note.** A line saying "this step was removed, read the
English" has to be written in Russian and in Japanese, and a rule whose last
step needs a translator fails in exactly the situation this whole convention
exists for. A reader who meets prose describing a step that is no longer under
it goes to `README.md`, which the top of their file links. Confusion is the
price, and it is the cheaper of the two failures.

**And one case this does not reach**, named rather than papered over: a removal
that lived only in translated prose, with no untranslated string to grep for.
There `STALE` stays the whole obligation — you cannot find the paragraph
without the language, and cutting by guess cuts the wrong thing. Say in the
commit message what was removed, so whoever next reads that language knows what
to look for.

Two things are deliberately not translated: **code blocks and program output**,
which are quoted from the running tool and would stop matching what a reader
sees, and the **engineering records** — `ARCHITECTURE.md`, `doc/decisions/`,
`doc/measurements.md` and the build diagnoses in `doc/android-build.md`. Those
are English only, along with code comments and commit messages.

**A CI check was considered and not built.** It is buildable — the workflow
already runs on every push — but the only check worth having is "the English
changed and the translation did not", and it fires on a typo fix at a
contributor with two exits: translate a language they may not read, or bump the
marker without translating, which converts the marker into a lie. Four files do
not earn that. The marker costs one line per file, anyone can check it in one
command, and when it is wrong it is wrong in the safe direction — it says
stale when the change was cosmetic, never current when the change was real.

## Disclaimer

This project is not affiliated with, endorsed by, or connected to
Tonkatsu Box, CLZ, or GAMEYE. All product names and trademarks are the
property of their respective owners. Game metadata is provided by IGDB.
</content>
