**English** · [Русский](README.ru.md) · [日本語](README.ja.md)

<!-- TRANSLATIONS: Update both translated READMEs and their TRANSLATED-FROM
     blob markers when this page changes. See CONTRIBUTING.md#translations. -->

# ShelfScan

[![CI](https://github.com/shinKatana0/shelfscan/actions/workflows/ci.yml/badge.svg)](https://github.com/shinKatana0/shelfscan/actions/workflows/ci.yml)

Turn the games you already own into a digital collection without entering
them one by one. Take photos of a shelf, scan games on your PC, or read your
GOG Galaxy library. ShelfScan gathers the results in one place for you to
check, then exports them to Tonkatsu Box or CSV.

It handles recognition and export; your collection lives in the app you
choose.

## Scan → Review → Export

**Scan** a shelf photo or a supported source on your computer.
**Review** the titles and platforms, and fix or add anything missed.
**Export** the approved items as Tonkatsu Box Custom Cards JSON, a legacy
`.xcoll` collection, or CSV.

## What it can read

- Photos of game shelves and cases (JPEG, PNG, WebP, and HEIC on Windows).
- Installed games found in folders on your PC, including GOG installation
  metadata where available.
- Your GOG Galaxy library on Windows, including games that are not installed.
- Media folders you select in the app. Supported file names can also yield
  film and animation rows. You can correct their kind, including to anime,
  during review.

You can combine sources in one scan. ShelfScan groups duplicates before
review, but it does not assume every title or platform it reads is right.
[The guide](doc/guide.md) explains supported inputs, formats, and limits.

## Download and run

The [latest GitHub release](https://github.com/shinKatana0/shelfscan/releases/latest)
has a portable **Windows x64** zip. Download `ShelfScan-win-x64.zip`,
extract the whole folder, and run `shelfscan_app.exe` inside it. There is
no installer or Dart/Flutter setup for this route.

To scan photos, choose a vision provider in Settings. Windows starts with
local Ollama, which you install separately. Pull the default model with
`ollama pull qwen3-vl:8b-instruct`. The Settings choice is
**Vision: local Ollama** (`qwen3-vl:8b-instruct`).
That server is `http://localhost:11434` by default.
Then choose your photos or sources, review the results, and export.

Android code is in the repository, but there is no published Android build.
See the [Android build notes](doc/android-build.md) if you want to build it
from source. For the command-line tool and detailed first run, use the
[guide](doc/guide.md).

## Your photos and your keys

You do not need a ShelfScan account. There is no ShelfScan server or
collection database, and the app ships without API keys. Local Ollama
can run on your Windows PC without a key; if you point
it at a server on your network, your photos go to that server. Choosing
Anthropic or an OpenAI-compatible endpoint sends photos to that provider.
Catalogue lookup can send titles to IGDB or TMDB using credentials you supply.
Cloud services are never chosen silently on Windows.

See the [provider setup guide](doc/guide.md#step-2--choose-a-vision-backend)
and [privacy details](SECURITY.md#your-photographs) before sending photos
to a service.

## Tonkatsu Box

ShelfScan identifies items and lets you review them. Tonkatsu Box handles
catalogue matching, covers, and metadata when you import the default
v0.45-compatible Custom Cards JSON with source lookup enabled. A unique match
becomes a catalogue-backed card; ambiguous or unmatched items stay custom
instead of being guessed at. The older `.xcoll` export is still available.

The [Tonkatsu integration note](doc/integrations/tonkatsu-handoff.md) covers
the export contract and import choices.

## Notes before you export

Review matters: photos and file names can be hard to read, and a missing
platform is better than an invented one. These observations concern the
evaluated local model, not a promise about every model:

<!-- measured-on: qwen2.5vl:7b -->

The evaluated `qwen2.5vl:7b` missed some printed platform markings.

<!-- /measured-on -->

<!-- measured-on: qwen2.5vl:7b -->

`qwen2.5vl:7b` read small spine text less reliably in downscaled photos.

<!-- /measured-on -->

<!-- measured-on: qwen2.5vl:7b -->

On crowded synthetic shelf images, `qwen2.5vl:7b` sometimes omitted
spines without reporting them.

<!-- /measured-on -->

<!-- measured-on: qwen2.5vl:7b -->

In a local comparison, adding a second reader to `qwen2.5vl:7b` also added
wrong or duplicate rows. Check every result, including a fallback read.

<!-- /measured-on -->

The [photo and review walkthrough](doc/guide.md#step-1--photograph-the-shelf)
has the practical advice.

### Opening the CSV in a spreadsheet

CSV is intended for import. Excel, LibreOffice and Google Sheets can
evaluate any cell whose text begins with `=`, `+`, `-` or `@` as a formula.
**shelfscan writes your names through unchanged** so an import into another
collection app receives the original text. To inspect the CSV in a
spreadsheet, **import it rather than double-click it** and set columns to
Text: Excel's *Data → From Text/CSV*, or LibreOffice's Text Import dialog
with *Evaluate formulas* unticked.

## Documentation

- [User guide](doc/guide.md) — first scan, review, export, and troubleshooting
  ([Russian](doc/guide.ru.md), [Japanese](doc/guide.ja.md)).
- [Providers](doc/guide.md#step-2--choose-a-vision-backend) and
  [privacy](SECURITY.md#your-photographs) — model setup, keys, and data flow.
- [Tonkatsu Box integration](doc/integrations/tonkatsu-handoff.md) —
  current handoff and legacy compatibility.
- [Architecture](ARCHITECTURE.md) and [build notes](doc/build.md) —
  for developers.

Want to contribute? Start with [CONTRIBUTING.md](CONTRIBUTING.md).

## Licence and attribution

ShelfScan is [MIT-licensed](LICENSE). It is not affiliated with, endorsed by,
or connected to Tonkatsu Box, CLZ, or GAMEYE. All product names and
trademarks are the property of their respective owners. Game metadata is
provided by IGDB.

This application uses TMDB and the TMDB APIs but is not endorsed, certified,
or otherwise approved by TMDB. It reaches those APIs only with a TMDB token
you supply yourself.

<img src="app/assets/tmdb/blue_long_1.svg" alt="TMDB" width="180">

The TMDB mark is shipped unaltered for attribution and is excluded from this
project's MIT grant; see [NOTICE](NOTICE).
