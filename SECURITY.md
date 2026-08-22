# Security and privacy

This project handles two sensitive things: your API credentials, and
photographs of your home. Both are covered here.

## Reporting a problem

**Do not open a public issue for a vulnerability.** Use GitHub's private
vulnerability reporting — the **Security** tab of this repository →
*Report a vulnerability*. That opens a private thread visible only to the
maintainer.

Expect a first response within a week. This is a one-maintainer hobby
project: there is no on-call rotation and no bounty.

Only the latest commit on `main` is supported. There is no released version
yet, so there are no back-ports.

## Credentials

**Bring your own key.** The project ships no credentials, runs no proxy,
and has no server of its own. A secret embedded in a distributed client is
not a secret, and a shared proxy would make this project the processor of
other people's photographs.

Where a key lives depends on which shell you run:

- **The app** stores secrets in the **OS credential store** via
  `flutter_secure_storage` — Windows Credential Manager, Android Keystore.
  Non-secret preferences go to `shared_preferences`; secrets never do.
- **The CLI** reads credentials from **environment variables only**
  (`Platform.environment`). Nothing parses a `.env` file. `.env.example` is
  a reference list of variable *names* with no values, and no code loads
  it — copying it to `.env` and filling it in has no effect.

No credential is ever written to a file inside the repository. If you
believe you have committed one, rotate it first and rewrite history second.

## Your photographs

Every photo is sent in full to whatever vision backend the run is
configured with, one call per photo per model. Nothing is downscaled,
cropped, sampled, cached or retained by this project.

- **Local backend (the desktop default):** each photo is POSTed to the
  Ollama server you point it at. **Keyless is not the same as offline** —
  that address is user-settable, and aimed at a machine on your LAN it
  ships the photographs there over plain HTTP.
- **A cloud backend is never a default and always an explicit choice.**
  Anthropic, or any OpenAI-compatible endpoint you name. The app shows a
  warning at the point of selection, before the first such run, because
  free tiers are commonly funded by training on what is submitted to them.
- **`--fallback` doubles it.** A second reader re-reads *every* photo, so a
  cloud second reader uploads every photo even on a run whose primary was
  local. It can only be turned on from the command line; no environment
  variable can make a local run cloud.
- **IGDB** receives the title strings the model read, never an image. Your
  Twitch client id and secret go to `id.twitch.tv` for an access token.
  Without those credentials the stage is skipped and neither service is
  contacted at all.

**There is no telemetry, no analytics and no crash reporting** of any kind.

The full per-provider breakdown is [Where your photos
go](README.md#where-your-photos-go) in the README.
