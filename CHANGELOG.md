# Changelog

Notable changes to shelfscan. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

This file starts at the first public release. Everything before it was built
task by task against a board that stays on a private disk and is not
published, so there is no earlier history to list here. What that work decided,
and why, is in [`doc/decisions/`](doc/decisions/); the figures behind it are in
[`doc/measurements.md`](doc/measurements.md).

**"Verified" is used sparingly here and always means the same thing:** run
from one end to the other, into another program, and checked. One path has
that — photographs → `.xcoll` → an import into Tonkatsu Box. Everything else
is written and tested, and where it has been run at all the entry says how
far. [`doc/measurements.md`](doc/measurements.md) bounds every such claim and
is the authority behind it.

## [Unreleased]

### Fixed
- **The READMEs said the app converts HEIC on Windows only.** It has carried a
  decoder on each platform since the Android one landed — the Windows Imaging
  Component on Windows, the system codec on Android — and two claims in each
  of the three files were wrong: the one naming HEIC as Windows-only, and the
  one telling an Android user to convert a HEIC by hand before picking it. The
  second is the one that cost something, because it is advice a reader acts
  on. What replaces them describes the code and claims nothing about a phone,
  which no build has run on.
- **A refused cloud vision call no longer reports a 403 as a rejected API
  key.** 401 and 403 are separate sentences now: 401 says the credentials were
  rejected, 403 says access was refused and deliberately claims nothing about
  the key in either direction — on this endpoint family a 403 can be a
  project, a region, a permission or a model the key may not use, and a proxy
  in front of the API can answer one having asked the API nothing. A 403 also
  says that access can depend on the connection the machine is on rather than
  on anything you configured, and sends you to try another network before
  checking your key: the same key and model can be refused over one connection
  and work over another.
- **A photo the vision model loops on is no longer reported as a shelf with
  too many games on it.** A frame can carry no more readable titles than one
  that scans cleanly and still fill the model's output budget, because it also
  holds narrow strips that look like a spine and carry no title — cases
  stacked edge-on, a rib and a logo and nothing to read. The model cannot tell
  one from the next and enumerates them until the budget runs out. Both
  endings of that now read the answer before naming a cause: whether the loop
  runs into the output cap or closes its document first and arrives as JSON of
  the wrong shape, an answer that repeats itself is told to re-frame the shot
  so that only spines whose titles face the camera are in it, and told that
  cutting the same shot into sections will not help. An answer of distinct
  entries that simply ran out of room keeps the advice it already had; a
  wrong-shaped answer that is not a loop no longer claims a cause nobody
  measured. A looping frame is also no longer offered the settings screen,
  because the model id is not what to change.

### Changed
- **A 403 talks about the device you are on, not "this machine".** The
  sentence reaches a phone as readily as a desktop, and the case it describes
  is one that happens on a phone.
- **A refused vision call carries a sanitised summary of what answered it**, on
  `VisionApiException.diagnostics`: the endpoint's own `error.type` and
  `error.code`, the response `content-type`, a classification of the body as
  `json`, `unrecognized-json`, `non-json` or `empty`, the `x-request-id` its
  support can look up, and `server` and `cf-ray` where they are sent. Together
  those tell an endpoint's own refusal apart from a proxy or an edge answering
  in front of it, and an API error document apart from an HTML block page. It
  is deliberately kept out of the sentence you read and out of the raw response
  body, which is unchanged and still never shown — on a 401 that body holds the
  API key echoed back. `error.message` is never read, no character of the body
  is ever quoted, and a value that cannot be made safe is dropped whole rather
  than shortened.
- **The empty scan screen's heading lines up with the text below it.**
  Alignment only; no wording, spacing or behaviour changed.
- **The READMEs say where Android stands.** It builds from this tree and it
  is not finished; it is not the priority at present, nothing about it is
  promised, and it has not been abandoned. Every Android sentence in those
  files describes what the code does rather than what has been observed on a
  phone — one paragraph says so, once, rather than a hedge beside each of
  them. Nothing the app does changed.
- **The app says that media folders accumulate, before you have to guess it.**
  *Add media folder* has appended since the control existed, and the only
  thing that said so was the list of folders — which does not exist until you
  have pressed it twice. The empty screen and the picker's own prompt now say
  it, and both name anime beside games and films, which the walk has read
  since the fansub grammar landed. Games in one folder, films in another and
  anime in a third are one scan and one dedupe; nothing about what the app
  does has changed.

## [0.2.0] - 2026-08-27

Both `pubspec.yaml` files read `0.2.0+2`. The number is `0.2.0` rather than
`0.1.1` because the entries below add capability a user can see, which is what
[`doc/decisions/0014`](doc/decisions/0014-stay-in-0-x-until-the-two-file-formats-stop-moving.md)
defines MINOR against; `+2` is the build number that record's 2026-08-25
amendment introduced, and it starts at 2 because 1 is what every Android
package built before it already declares.

### Added
- **Films are read as films.** A video file whose name is release-shaped —
  `Some.Title.1999.1080p.BluRay.x264-GROUP.mkv` — comes back as a film row
  rather than a game row, and a film kept in its own folder comes back as one
  film row rather than as a game named after the folder. The kind is decided
  per file, so a folder holding a film and a game installer is read once and
  gives both. Both shells walk a folder by the same shared rule, so a folder
  that is a film in the CLI is a film in the app.
- **A second catalogue, for the rows the games one cannot answer.** A film row
  goes to TMDB and never to IGDB, in any configuration, and TMDB wants a
  credential of its own — an environment variable in the CLI, a Settings field
  in the app. Without one the film rows are keyless and keep the title that
  was read. **How far this has been run:** against the live service from the
  CLI only, on a few public example titles on one evening. No run through the
  app has ever had an answer from TMDB, and how well TMDB answers real release
  names is unmeasured anywhere. `doc/measurements.md`, *TMDB's `year` filters
  and the first live film searches*, is the authority and states the rest of
  the limits.
- **Anime is a kind, and no anime row has ever matched anything.** A video
  named the fansub way — `[Group] Title - 04 [1080p].mkv` — comes back as one
  row for the series. `S01E04` and `1x04` are declined on purpose: they say
  *series* without saying which kind of series, and answering would file every
  television release as anime. An anime film goes to TMDB's film search and an
  anime series to its tv search — **and the tv search has never been called
  against the live service by anything.** That half is written and tested and
  nothing more.
- **The kind of work is a field on the row, and you correct it.** Review shows
  what each row was read as and lets you change it, so a film read as a game,
  or the reverse, is settled by the person rather than by a better guess
  (decision 0015).
- **A row that maps to several catalogue entries expands into them** at
  review, so a box or a compilation no longer has to leave as one item.
- **Android is in the tree and it builds.** `app/android/` is committed, and
  debug and release apks both build from it; the toolchain, and the failures
  on the way that name something other than the missing step, are in
  [`doc/android-build.md`](doc/android-build.md). **Nothing has been installed
  or run:** there is no device and no emulator here, so every Android line
  below is *built* and never *working*. With that said —
  - HEIC photos are accepted on Android, decoded by the platform's own codec
    over a method channel rather than by a plugin.
  - *Local* is selectable there, and it means a model on **another** machine:
    an Ollama you name on your own network. It is offered but never the
    default, is blocked until an address is typed, and carries a warning of
    its own, because the photographs cross that network unencrypted.
  - The TMDB credential can be held in Settings, in the OS keychain, beside
    the others.
- **Keyless is a mode you choose before the scan**, with what it will cost
  said where you choose it, rather than a state you fall into by leaving two
  fields blank.

- **TMDB is credited the way its terms require.** The mandated sentence
  appears verbatim, with only the bracketed word substituted, in all three
  READMEs, on the settings screen and in the CLI, and TMDB's own mark ships
  beside it in the READMEs. The file is byte-identical to the one TMDB
  publishes -- its SHA-256 is the digest in the published URL -- and it ships
  unaltered rather than rasterised, because TMDB publishes SVG and no raster
  format at all. What the published page does **not** give: no minimum size,
  no clear space, no alteration rule. Nothing here invents one.
- **An open-source licences page**, reachable from Settings. The notices file
  has been generated into every build all along; what was missing was a route
  to it. 90 packages ship, measured on the transitive closure of the direct
  dependencies rather than by subtracting the declared development ones --
  two packages declared for development ship anyway, pulled in by others.
  **How far this has been run:** the page's *contents* cannot be observed by
  any test this project can write -- Flutter's test binding registers no
  licences at all, deliberately -- so this is proved in code and tests and
  still wants one look on a real run.
- **The app says which build it is.** The licence page carries the version,
  so two hand-installed packages can be told apart from inside the one you
  are holding, which until now they could not be — from inside or out.
- **A `NOTICE` file, and a licence section in all three READMEs.** The MIT
  terms in `LICENSE` grant the right to modify, sublicense and sell "the
  Software", and the Software includes TMDB's mark — which this project
  cannot license. `NOTICE` names `app/assets/tmdb/blue_long_1.svg`, records
  that it ships unaltered for attribution, and states that the MIT grant does
  not extend to it. `LICENSE` itself is unchanged, so it still matches MIT and
  the sidebar still shows it. None of the three READMEs had a licence heading
  before; each now links both files.
- **A test holds the four translation markers to their own claim.** A marker
  saying `CURRENT` must name what its English source says now, and marking it
  `STALE` — one word, in a language the person marking need not read — is the
  other way to satisfy it.
- **`CONTRIBUTING.md` carries the release procedure**, which nothing in the
  repository had. It gives decision 0014's order — both `pubspec.yaml` files,
  then `CHANGELOG.md`, then the tag — with the command that checks each step
  and what each answer means, including why a missing changelog heading is a
  note at exit 0 rather than a refusal: the git state of a tree about to be
  released and the git state of an ordinary day are the same one. Deciding the
  version and cutting the tag stay a person's acts.

### Changed
- **A translation marker names the content of the English file — its git
  blob — rather than a commit**, so the check it documents survives a merge
  and a history rewrite. A commit hash survived neither: after this project's
  identity rewrite the documented command answered `fatal: bad revision` from
  a clone. The two guides stay marked stale; only the mechanism moved.
- **The CSV's id column is `external_id`, and it names which catalogue
  answered** — `igdb:1234`, `tmdb:1234` — where it was `igdb_id` carrying a
  bare number. A row is identified by the catalogue that answered it
  (decision 0016), because there is now more than one — and until there was,
  a column named for one catalogue could carry every id it would ever hold.
  Anything reading these exports by header needs the new name; the column
  order did not change.
- **`.xcoll` takes a film** as a `movie` item carrying the film catalogue's id
  and no `platform_id` key at all — a film has no platform, and the writer
  leaves the key out rather than inventing a zero. No `.xcoll` holding a film
  has been imported into a catalog app here, so that step is written and
  tested rather than verified, like every other export that did not come from
  a photograph.
- **The provider list leads with local, then your own OpenAI-compatible
  endpoint, then Anthropic** — in the app, in the CLI banner and in the
  guides. What did not move: local is still the desktop default, and no
  external endpoint is a default anywhere.
- **Three Flutter plugins moved together** to get off the Kotlin Gradle
  Plugin, so an Android build no longer prints the warning that future Flutter
  versions will fail on it.

### Fixed
- **The documents said a cloud backend is never a default; on Android one
  is.** `SECURITY.md` said it outright and the README left it to be inferred,
  stating only that Android's Local backend is never the default and never
  what it starts on instead — on the section `SECURITY.md` sends a reader to
  for the full per-provider breakdown, so the summary said more about the
  platform split than the detail it pointed at. `SECURITY.md` and all three
  READMEs now say which backend each platform starts on: an OpenAI-compatible endpoint you
  name is never a default anywhere, Anthropic is not the default where a
  local model can run, and Anthropic is the Android default because the phone
  runs none of its own and its Local backend cannot start until you have
  typed a server address. They also carry the qualifier that fact needs:
  nothing is uploaded before you have supplied your own key, because a
  keyless cloud backend is refused at the tap and the run makes no call at
  all. And `SECURITY.md` stops giving one backend's reason for both — the
  free-tier training warning belongs to an endpoint you name, not to a paid
  Anthropic account, which is how the app has always worded the two.
- **`SECURITY.md`'s supported-versions paragraph no longer says there is no
  released version.** `v0.1.0` has been tagged since 2026-08-17. The policy is
  unchanged — only the latest commit on `main` is supported — and the page now
  says what that means for a tag: it is not separately supported, and a fix
  goes out on `main` rather than backwards into a release already made.
- **`SECURITY.md`'s account of what leaves your machine named one
  catalogue.** Its "Your photographs" list is what a security-minded reader
  opens on purpose, and since films got their own catalogue the resolve stage
  also sends title strings to TMDB — so the list was a destination short, on
  the page whose premise is that it is complete. It now names both catalogues
  and which rows go to each, keeps the distinction that is the reassuring half
  — neither catalogue is ever sent an image — and says which credential goes
  where. Its "without those credentials the stage is skipped" is now which
  rows go unmatched. The wording is the one the READMEs already use.
- **README's "Nothing is telemetered" enumerated what leaves the machine and
  named one catalogue.** It is a completeness claim — *the only things ever
  sent anywhere* — and since films got their own catalogue the resolve stage
  also sends title strings to TMDB, so the list was a destination short. It
  now names both catalogues, keeps the distinction that is the reassuring
  half — neither catalogue is ever sent an image — and says which credential
  goes where. The section it delegates the full answer to, "Where your photos
  go", had an IGDB bullet and no TMDB one, so that was fixed too rather than
  left as an incomplete page a complete claim points at; its "the stage is
  skipped without those credentials" is now which rows go unmatched, the
  stage being keyed on catalogues rather than on one credential. "What it
  costs" gains a film and anime row, and the Path A/B comparison says what
  Path B actually asks for now. In all three READMEs.
- **README's "Path B — bring your own keys" named two credentials and the
  tool reads three.** Its "Where the keys go" table gave 11 of the 12
  environment variables the CLI reads, and the missing one was the film and
  anime credential that the section one heading away already describes as a
  CLI environment variable. The section now names three and the table has a
  row for `SHELFSCAN_TMDB_TOKEN`. The IGDB row said the resolve stage is
  skipped without those two, which stopped being true when the stage became
  keyed on catalogues rather than on one credential; both rows now say which
  rows go unmatched instead. In all three READMEs.
- **Every Android package this project had ever built declared the same
  version**, so none of them was an upgrade of any other as far as Android is
  concerned: the system decides what is an update by that integer alone, and
  packages carrying the same one are the same version to it however different
  their contents. The cause was an absence: with no build number
  behind the version in `pubspec.yaml`, Flutter substitutes `1` and warns
  nobody, so the apks came out carrying `versionCode='1'` whatever was in
  them. The version now carries one, and a test fails if it ever stops —
  the absence is silent and nothing else in the tree would have said so. A
  test can only see the working tree, though, so it says nothing about whether
  that number has been used before — it is as green on a second package built
  at `+2` as on the first. `tool/check-release-order.dart` is what answers
  that: run before cutting a tag, it reads the version out of every tag's tree
  and refuses when this tree's build number is not ahead of all of them. It
  answers for the changelog step as well: a tag whose own tree names no
  heading for the version that tree declared is a release that went out
  describing itself as unreleased.
- **An asset declared by a `../` path never reached a built app**, on Windows
  or Android, and no test could have caught it: `flutter test` builds its
  bundle beside the files such a key escapes to, so the broken path resolves
  in a test and nowhere else. Both bundled files now sit under `app/`. **What
  it cost, stated plainly because the first account of it overstated the
  case:** the alias table's fallback holds the same three pairs the file does,
  byte for byte, so no title resolved worse for it -- but the TMDB mark could
  not load at all, and the file and its fallback would have diverged silently
  the first time anyone added a fourth entry. A check under `tool/` now fails
  a build whose manifest names a file the bundle does not carry, and says so
  as *rebuild this* when the artefact merely predates the declaration.
- **A run holding a TMDB credential and no IGDB pair was told the resolve
  stage would be skipped**, and then resolved film and anime rows on TMDB. It
  now says what that run will actually do; a run with neither credential says
  what it always did, word for word.
- A photograph holding more spines than the local model will report is still
  declined, but the request now carries a generation cap and the advice
  arrives in a fraction of the wait, instead of after minutes of the model
  repeating what it already read. The cap buys the time and not the outcome;
  `doc/measurements.md` has both halves.
- A control is absent where it cannot work rather than offered and refused:
  the GOG Galaxy library is not offered off Windows, since Galaxy is a Windows
  program.
- A row with no candidates stops asking you to pick one.
- A folder scan says what it will and will not read *before* it runs, instead
  of implying that every entry in the folder is read as a game.

## [0.1.0] — 2026-08-17

The first public release, described as it stood at the tag; where the tree has
moved since, [Unreleased](#unreleased) says so. Highlights, not a task list:

### Added
- Scan a folder of shelf photos with a local vision model (Ollama, the
  desktop default, no account and no key) or a cloud one you select —
  Anthropic, or any OpenAI-compatible endpoint.
- Additional detection sources that need no photograph: a games folder and
  a GOG Galaxy library (Windows — Galaxy is a Windows program), reconciled with
  the shelf through one dedupe. These are newer than the photo path and have
  had far less exercise: they have been run against real folders, and they
  stop at the export — no disk-sourced `.xcoll` has been imported into a
  catalog app here.
- Optional IGDB resolution with your own Twitch credentials.
- Human review of every item before export — in the CLI over
  `*.review.json`, or on the app's review screen.
- Export to Tonkatsu Box `.xcoll` (pinned `version: 2`) and to CSV. The
  `.xcoll` path is the one verified end to end, by an import into Tonkatsu Box;
  the CSV has never been imported into a catalog app here.
- A Flutter app for Windows, and a CLI as the desktop harness. **Windows only
  at this release:** the Android half of the pipeline was written and tested
  but had never been built or run — there was no `app/android/` yet, and
  nothing had run on a device. There is no installer and no published binary;
  you build from source.
- HEIC photos converted on Windows via WIC; named and skipped elsewhere.
