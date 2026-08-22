# Changelog

Notable changes to shelfscan. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

This file starts at the first public release. Everything before it was built
task by task against a board that stays on a private disk and is not
published, so there is no earlier history to list here. What that work decided,
and why, is in [`doc/decisions/`](doc/decisions/); the figures behind it are in
[`doc/measurements.md`](doc/measurements.md).

## [0.1.0] — 2026-08-17

The first public release. Highlights, not a task list:

### Added
- Scan a folder of shelf photos with a local vision model (Ollama, the
  desktop default, no account and no key) or a cloud one you select —
  Anthropic, or any OpenAI-compatible endpoint.
- Additional detection sources that need no photograph: a games folder and
  a GOG Galaxy library (Windows — Galaxy is a Windows program), reconciled with
  the shelf through one dedupe. These are newer than the photo path and have
  had far less exercise; a couple of hand-picked library rows have reached a
  Tonkatsu Box import, a whole library has not.
- Optional IGDB resolution with your own Twitch credentials.
- Human review of every item before export — in the CLI over
  `*.review.json`, or on the app's review screen.
- Export to Tonkatsu Box `.xcoll` (pinned `version: 2`) and to CSV. The
  `.xcoll` path is the one verified end to end, by an import into Tonkatsu Box;
  the CSV has never been imported into a catalog app here.
- A Flutter app for Windows, and a CLI as the desktop harness. **Windows only:**
  the Android half of the pipeline is written and tested but has never been
  built or run — there is no `app/android/`, and it has never run on a device. Nor is there an
  installer or a published binary; you build from source.
- HEIC photos converted on Windows via WIC; named and skipped elsewhere.
