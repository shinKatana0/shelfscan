# What this integration depends on, and a smaller boundary proposed for it

**Status: a design note. Nothing in production changes on the strength of it.**
`.xcoll` stays the contract, no provider is removed, no exporter is replaced.
What follows is an audit of what this project looks up and why, and an argument
about a smaller handover the Tonkatsu Box maintainer has proposed. It ends in
questions rather than in a decision, because the questions are not this
project's to answer alone.

Every upstream claim below was read at `hacan359/tonkatsu_box`, branch
`release/0.44`, and the file it came from is named beside it. Where this note
argues from this repository it names the class or the file too, for the same
reason: a claim nobody can check is not worth writing down.

## 1. The current boundary

Two files cross it today, and both are written by an exporter reading the same
document.

- **`*.review.json`** is the contract on this side. Everything before it is
  recognition — photographs, disk sources, dedupe, catalogue resolution, and a
  person approving each row. Everything after it is formatting. Both Tonkatsu
  targets read that file and nothing else.
- **`TonkatsuExporter`** (registry key `tonkatsu`, extension `xcoll`) writes a
  `version: 2` light collection. An item in it is a `media_type`, an
  `external_id`, and — for a game or an animation — a `platform_id`. There is
  no title field in a light item and no cover: the importer fetches everything
  else from the id.
- **`TonkatsuCardsExporter`** (registry key `tonkatsu-cards`, extension `json`)
  writes the rows the first one declines, as a bare array of Custom Cards. A
  card carries `title` and `type`, plus `alt_title` and `platform` where this
  pipeline holds them honestly. Four keys, and there is no fifth.

Both live in `packages/shelfscan_core/lib/src/exporters/exporters.dart`. The two
partition the approved rows: a row the first can carry belongs in `.xcoll`, and
the second asks the first rather than restating its rule.

So the boundary today is **ids where there are ids, names where there are
not**, and the second half of that is new.

## 2. The dependency matrix

One row per external lookup or resolver this project performs, with what each
one is for.

| lookup / resolver | shelfscan's own features | another export | only the Tonkatsu export | credential | safe to decouple from Tonkatsu |
|---|---|---|---|---|---|
| Ollama vision (`ollama_vision.dart`) | yes — stage 1, every row starts here | feeds every export | no | none; a URL you supply | n/a — it produces the rows, not the ids |
| Anthropic vision (`providers/vision.dart`) | yes — stage 1 | feeds every export | no | `ANTHROPIC_API_KEY` | n/a, as above |
| OpenAI-compatible vision (`openai_compatible_vision.dart`) | yes — stage 1 | feeds every export | no | `SHELFSCAN_OPENAI_API_KEY`, and a base URL and a model with it — all three required, nothing defaulted | n/a, as above |
| IGDB, via a Twitch OAuth token exchange (`providers/igdb.dart`) | yes — the review screen is built out of the answer | yes — CSV's `external_id`, `title` and `platform` cells | no | `IGDB_CLIENT_ID` + `IGDB_CLIENT_SECRET` | no |
| TMDB, film search and television search (`providers/tmdb.dart`) | yes — same as above | yes — the same three CSV cells | no | `SHELFSCAN_TMDB_TOKEN` | no |
| `FilenameSource`, `GogMetadataSource`, `GogLibrarySource` (`lib/src/sources/`) | yes — stage 1b | feeds every export | no | none, and no network call at all | n/a — they are local readers |
| `InstalledGameSource` (shell code, once in `bin/` and once in `app/lib/`) | yes — it routes an entry to the two readers above by name | feeds every export | no | none | n/a, as above |
| `SkipResolver` (`workers/resolver.dart`) | yes — it is the keyless path, and the fallback behind `CatalogueRouter` | feeds every export | no | none | n/a — it is the absence of a lookup |

**The headline, and it is the finding rather than a summary: the third column
is empty.** No lookup in this repository exists only to satisfy the Tonkatsu
exporter.

The two that could conceivably have been there are IGDB and TMDB, and neither
is. Both feed the review screen directly — a `Candidate` carries the canonical
`title` the row is shown under, the `platformName`, the
`matchedAlternativeName` that actually matched where a regional title diverged,
the `releaseYear` that separates a remake from its original, and the candidate
list a person picks from when nothing scored high enough to match on its own.
Review is mandatory here (`PROJECT.md`, "Review is mandatory UX"), so removing
either catalogue would take a required step apart and not merely an export.
Both also fill three cells of the CSV export, which no Tonkatsu import reads.

**What this matrix does not license.** It is an audit. Nothing is removed on
the strength of it, and nothing here recommends removing anything. Its use is
that the question *which of these is Tonkatsu's tax?* now has a written answer,
and the answer is *none of them*.

## 3. Credentials, and the keyless question

Upstream's own table (`docs/RCOLL_FORMAT.md`, "Source Values") marks a
*Keyless* column for exactly the reason this note exists — "a writer outside
the app needs the keyless column: those APIs answer an id lookup with no
registration". By it, `visual_novel` (VNDB), `manga` (AniList, MangaBaka,
MangaDex, Kitsu) and `anime` (AniList, Kitsu) are keyless outright; `book` is
keyless on OpenLibrary and Fantlab, `audio` on MusicBrainz, and `tv_show` and
`animation` on TVmaze only. `game` is `no (Twitch OAuth)` and `movie` is `no`.

Two things follow, and the second is the constraint rather than the
observation.

**This project already asks for no credential where none is needed.** The only
credentialed lookups it performs are IGDB and TMDB, and both genuinely require
one. Ollama takes an address and no key; every detection source reads a local
file and makes no request at all; the keyless path resolves nothing on purpose
and exports through CSV and through Custom Cards. There is nothing to fix here,
and this paragraph exists so that a reader who has just read the keyless column
does not go looking for the gap.

**And none of those keyless catalogues is being added.** The standing
constraint is that a provider is not added here to satisfy an export target
that resolves the thing itself. Adding AniList to fill an `anime` row's
`external_id` would put a second matcher, a second alias problem and a second
tie rule in this repository to produce a number the receiving app can produce
from the name.

## 4. Duplicated responsibilities — and the half that is not duplicated

Where the two projects do the same work:

- **Name parsing.** `FilenameSource`'s grammar reads a release-shaped or
  fansub-shaped name into a title, a year and a kind; Tonkatsu has its own
  parsers for the same job on its own import routes.
- **Catalogue search and fuzzy matching.** `ResolverWorker` and
  `TmdbResolverWorker`, the normalization in `title_key.dart`, the alias table
  in `app/assets/data/title_aliases.json` and the tie rules around them — all
  of it is a smaller version of matching machinery the receiving app already
  has for more catalogues than this one queries.
- **Credential custody.** Each side holds its own Twitch pair and its own TMDB
  token, and each asks its own user for them.

**And where they do not, which is the more interesting half.** This project
holds four things the receiving app cannot recover from a name, because none of
them is in the name:

- the **platform read off the spine** — a photograph is the only place that
  fact exists for a physical copy, and it is what tells one title on two
  consoles apart;
- the **film-or-series answer a person gave at review**, which is a
  `platform_id` of `0` or `1` on an animation item and is not derivable from
  anything else this pipeline holds;
- the **raw title as printed on the object**, before any alias was applied — a
  regional cover is evidence, and the canonical name is a substitution made
  over it;
- and the **fact that a human confirmed the row at all**, which is the whole
  premise of the tool and the one thing an automatic import cannot manufacture.

Everything a minimal handoff would give up is in the first list. Everything it
must keep carrying is in the second.

## 5. The proposed minimal boundary

The maintainer's proposal, so it is not paraphrased away: Tonkatsu already has
its own name parsers, matching and resolution mechanisms, catalogue
integrations and provider-side credentials, so a future ShelfScan → Tonkatsu
boundary might be

```json
{ "name": "...", "type": "..." }
```

with optional hints — `year`, `platform`, `alt_title` — only where useful.

### Where it is strictly better than anything here

**`anime`, and it is the case that motivates the whole idea.** Upstream files
Japanese anime on its own model backed by AniList or Kitsu —
`packages/core/lib/models/media_type.dart`: *"Japanese anime on its own [Anime]
model backed by AniList — not [animation], which is TMDB cartoons"* — and both
of those catalogues are keyless. This project queries neither, has been told
not to add either, and since the `anime` kind was separated out an `anime` row
is one `.xcoll` declines by construction: `TonkatsuExporter` maps the kind to
no catalogue at all, so there is no `external_id` to write and the row is
refused by name rather than mis-filed under `animation`. A name and a type
would be enough for a resolver that is already built and already keyless.
`manga`, `visual_novel` and `book` are the same shape one step further out —
kinds this project does not read at all today, whose catalogues upstream
resolves without a credential.

### Where it is not better

**`game` and `movie` rows.** This project already resolves those, and the ids
are not a byproduct of the export: the review screen is built out of them.
Handing over a name instead would not remove a lookup — the lookup still has to
happen for a person to confirm anything — it would only stop the export using
its result, and hand the receiving app a second matching problem this side has
already solved with better evidence.

### Where the hints are load-bearing

- **One title on two platforms.** The spine says which, and only this side has
  seen the spine. Without `platform` the receiving end is choosing between two
  correct answers with nothing to choose on.
- **A remake against its original.** A year separates them — see the trap
  below, which is about *which* year.
- **A film against a series of the same name.** `platform_id` `0`/`1` is this
  project's answer and it comes from a person, not from an inference.
- **A regional title.** `alt_title` should carry the raw text as read, with the
  alias table's canonical name in `name`, so the receiving matcher can try
  both and a reader can see which one was on the object.

### The year hint has a trap, and it is worth stating precisely

The only year an unmatched row can carry here is `Detection.sourceYear`, and it
is *a claim about the name, never a fact about the work*: the rule that
produces it reads position rather than meaning, so on a scene-style name the
four-digit token is conventionally the release of the rip. Its own doc comment
forbids exporting it, and `TonkatsuCardsExporter` refuses the `year` key for
exactly that reason.

`Candidate.releaseYear` is the trustworthy one, and it exists only where a
match already exists. So the trap is this: **for precisely the rows a minimal
handoff is meant to help — the ones nothing matched — there is no honest year
to send.** A `year` hint is fillable on the rows that least need it, and empty
on the rows that most do. That is not an argument against the hint; it is an
argument against reading its absence as an absence of information.

### Does an import path for this already exist? Not quite, and this is the finding

**Custom Cards takes a name and a type and imports without a credential**,
which is most of the shape the proposal asks for. It does not resolve.

`lib/core/import/sources/custom_file/custom_card_entry.dart` says so at the
list of types it accepts: *"Card types a file may declare. `custom` itself is
not accepted: the card is always stored as a custom item, `type` only picks how
it masquerades."* The import service agrees at the write —
`lib/core/import/sources/custom_file/custom_cards_import_service.dart` builds a
`CustomMedia` and inserts a row whose `media_type` is `custom` and whose
`external_id` is the id of that local custom record.

So an imported card has:

- **no catalogue identity.** Nothing links it to an IGDB, TMDB or AniList
  entry, so nothing later refetches or updates it.
- **no fetched metadata.** Description, genres, rating and the rest are read
  out of the file or absent.
- **a cover only if the file supplied a URL.** `cover` takes an `http(s)` URL
  and the importer downloads it after the insert; it looks nothing up. This
  project writes no `cover` under any condition, because the only image it
  holds is a photograph on the owner's own machine.
- **duplicate detection, but by title.** `duplicateRowIndexes` compares
  trimmed, case-folded titles against the items already in the target
  collection and against earlier rows of the same file, and marks the matches
  in the preview. That is a real check and it is not a catalogue-identity
  dedupe: it cannot tell one title on two platforms apart, and it cannot see
  that a card is the same work as a catalogued item under a different name.

That is the gap in one sentence: **the file format the proposal describes
already exists upstream and is parsed; what does not exist is a mode that puts
its rows through the matcher.**

### The smallest upstream extension that would close it

Stated as a proposal, not as a design, and it is a question for the maintainer
rather than a plan:

> a **resolve-on-import** mode over the file Custom Cards already parses — each
> row's `name` and `type` through Tonkatsu's own matcher, a confident match
> becoming a real catalogued item, everything else falling back to a custom
> card exactly as today.

Same file, same parser, one flag. That shape is preferred to a new format for a
reason that is about maintenance rather than elegance: it needs **no second
serializer on this side and no second parser on that one**. The exporter that
writes the file already exists here and is tested against the parser's rules;
a new format would mean two writers here, two readers there, and two chances
for them to drift.

### Ambiguity must not be resolved silently

Upstream already has the surface for it:
`lib/features/settings/screens/custom_cards_preview_screen.dart` is a preview
step between parsing and writing, and `parseFile` is documented as validating
without touching the database. So the natural answer is that a row with several
candidates surfaces there, and **defaults to keeping it as a custom card rather
than to a guess** — the fallback is the safe one, and it is already the
behaviour when nothing matches.

That is also this project's own standing rule, which is why this note can argue
it from both sides: model confidence is not trustworthy here and every row
passes a person before it is exported. A resolve-on-import that guessed
silently would undo, one program later, the step that makes this one worth
running.

### What shelfscan must not send

- **Covers of any kind.** The receiving app fetches them from an id, and the
  only image this project holds is a photograph of somebody's home. A path to
  one must never leave the machine either.
- **Descriptions, genres and ratings.** This pipeline holds none of them and a
  default written into a card is a claim the owner did not make.
- **Ids for catalogues this project never queried.** An `external_id` under a
  `source` nothing here contacted would be a fabricated identity, and upstream
  silently falls back to a type's default catalogue on an unknown `source` —
  so a wrong one resolves against the wrong catalogue rather than failing.
- **Every personal and progress field** — status, the two dates,
  `time_spent_minutes`, rating, comment, favourite, rewatch count, the episode
  and season counters, tags. This tool collects none of them.

## 6. Backward compatibility and migration

**`.xcoll` v2 stays the production contract and nothing here deprecates it.**
Upstream writes v3 and accepts v2 on import (`docs/RCOLL_FORMAT.md`: *"Always
`3` (v2 also accepted on import)"*); v3's difference is that `user_rating`
became a one-decimal number rather than an integer, a field this project does
not write, and *"older builds reject v3 files cleanly"*. So 2 is the wider
compatibility and the pin is deliberate.

If the upstream extension ever landed, the migration shape is **the same file,
consumed differently** — not a third registry entry beside `tonkatsu` and
`tonkatsu-cards`.

The argument for that is the one this whole section turns on: the file
`TonkatsuCardsExporter` writes *is already* `{name, type}` plus hints, under
upstream's own key names. `title` is the name, `type` is the type, `alt_title`
and `platform` are two of the three proposed hints, and `year` is the third and
is the one this project cannot fill honestly. A resolve-on-import flag would
change what the receiving app *does* with that file, not what this project
writes into it. Adding a third exporter to emit the same four keys under
different spellings would be a second serializer for no gain, and it would put
this project in the position of maintaining a format that only one mode of one
importer reads.

Two consequences worth stating so they are not rediscovered later. The rows
that would flow through such a mode are exactly the rows `.xcoll` declines
today, so nothing that currently imports well would change route. And a
receiving app that never gains the flag still imports the same file as custom
cards, which is what it does now — the migration has no flag day.

## 7. The compatibility abstraction, and why it is not being built

The question is whether a neutral representation should be introduced ahead of
Tonkatsu-specific serialization, so that a second target app does not require
recognition-side change.

**The recommendation is to build nothing, and the argument is that it already
exists.** `ReviewDocument` / `ResolvedGame` *is* the neutral representation;
`Exporter` is the serializer seam; and `ARCHITECTURE.md` key decision 1 already
states the property — exporters are thin adapters over `ResolvedGame`, and
adding a new target app never touches recognition code.

That claim was checked against the diff that added the third target rather than
taken on trust, and it holds:

- `exporters.dart` gained **178 lines and lost none** — one new class and one
  appended registry entry.
- **`app/lib` was not touched at all.** The export sheet builds itself from the
  registry, so the app picked the target up with no change.
- `bin/shelfscan.dart` changed nine lines, all narration: the usage banner's
  list of targets and one sentence that now asks the exporter why it left rows
  out instead of stating one target's reason for all of them.
- Nothing under `workers/`, `providers/`, `sources/`, `orchestrator.dart` or
  `models.dart` was touched. No recognition code was in the diff.

An extra abstraction between `ResolvedGame` and `Exporter` would therefore be a
layer with one implementation, added on the strength of a second consumer that
does not exist. If the minimal handoff is ever built, the evidence above says
it arrives the same way: one class, one registry line, no recognition change —
or, per section 6, no new class at all.

## 8. Open questions for the maintainer

Written to be asked as they stand. None of them assumes its answer.

1. Would a `{name, type}` import payload be accepted at all, or is a resolved
   `external_id` the boundary you want to keep?
2. Which hints are worth carrying — `year`, `platform`, `alt_title`? Are there
   others that would help your matcher more than these?
3. Would such rows go through your existing parser and matcher stack, or would
   they need a route of their own?
4. How should an ambiguous match surface? Is the Custom Cards preview screen
   the right place, and should an import that resolves anything require
   confirmation before it writes?
5. Could this become an official contract, or would you rather ShelfScan kept
   producing `.xcoll` and left resolution on this side?
6. Is there an existing internal schema or import route we should target
   instead of anything new?
7. Is a **resolve-on-import flag over the Custom Cards file you already parse**
   the right shape for this — same file, same parser, one option — or is a
   separate route cleaner from where you sit?
8. Does `custom_cards_preview_screen`'s preview step give you the place to show
   "this row matched three things, keep it as a card?" without a new screen?
9. `.xcoll` here pins `version: 2` because v3's `user_rating` change is a field
   we never write and older builds reject v3 cleanly. Is 2 still the right pin
   for a writer outside the app, now that v3 is current?
10. Is there anything a scanner on the shelf side could send that would help
    your matcher and that we are not currently keeping — beyond the platform
    read off the spine and the raw title as printed?
