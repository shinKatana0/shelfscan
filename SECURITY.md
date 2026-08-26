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

Only the latest commit on `main` is supported. `v0.1.0` is tagged and the
tree has moved on from it, but a tag is not separately supported: a fix goes
out on `main`, never backwards into a release already made.

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
- **A cloud backend: Anthropic, or any OpenAI-compatible endpoint you
  name.** An endpoint you name is never a default anywhere. Anthropic is not
  the default on the desktop, where a local model can run — but it **is** the
  Android default, because the phone runs no model of its own and Local there
  means a server on your own network that cannot work until you have typed
  its address. **No photo is uploaded before you have supplied your own
  key:** a cloud backend without one is refused at the tap, naming the
  credential it wants, and the run makes no call. The app warns where the
  backend is chosen, and the two warnings differ on purpose — Anthropic's
  says every photo is uploaded to Anthropic in full; a named endpoint's adds
  that free tiers are commonly funded by training on what is submitted to
  them, which is not a claim about a paid Anthropic account.
- **`--fallback` doubles it.** A second reader re-reads *every* photo, so a
  cloud second reader uploads every photo even on a run whose primary was
  local. It can only be turned on from the command line; no environment
  variable can make a local run cloud.
- **IGDB and TMDB** receive the title strings the model read — IGDB for
  game rows, TMDB for film and anime rows. **Neither catalogue is ever
  sent an image.** Each takes its own credential: your Twitch client id
  and secret go to `id.twitch.tv` for an access token, your TMDB API Read
  Access Token goes to TMDB with every search. Rows whose catalogue you
  hold no credential for go unmatched, and that catalogue is not
  contacted at all.

**There is no telemetry, no analytics and no crash reporting** of any kind.

The full per-provider breakdown is [Where your photos
go](README.md#where-your-photos-go) in the README.
