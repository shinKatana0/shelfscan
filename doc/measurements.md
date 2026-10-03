# ShelfScan measurement methods and public evidence

The control photographs and local folder inputs are private. Their labels,
properties, and quantitative results are kept outside the public repository.
This page records the methods and conclusions that can be shared without
identifying those inputs. The detailed tables below use synthetic frames or
public catalogue queries, as stated in each section.

## Control-photo methods and conclusions

Control validation compares an original-resolution set with a downscaled set
under the same model, prompt, and sampling settings. A prompt change needs
both sets checked again: a result on only one resolution does not establish
that recognition remains stable. The local prompt fingerprint is pinned in
[the public control manifest](control-set-manifest.md). The source images and
per-image outcomes remain local.

Higher resolution improves recognition when printed spine text is small.
Increasing the amount of shelf content in one frame has the opposite effect:
at high density the local model can silently omit items or enter a repetition
loop. The synthetic density experiment below isolates that behavior without
using a private photograph.

Prompt examples, field order, and cache state can change what the model
reports. A response that parses is not necessarily faithful to the image;
review remains necessary. The local control procedure checks results against
the images themselves rather than comparing one model response with another.

Pre-segmentation of ordinary shelf photos did not justify the additional
processing. For an unusually dense frame, sectioning at the same pixel scale
is useful because it reduces content per request; the synthetic experiment
below documents the distinction.

## Resolver and source methods

Resolver evaluation must distinguish a retrieved catalogue candidate from an
automatic match. A close title score alone does not settle platform or release
year ambiguity. IGDB's public external-game-source data can connect a GOG
identifier to a catalogue entry; the join still needs platform selection.
Local folder and collection observations are deliberately omitted because
their row counts and outcomes would describe a private installation.

## The exact join: IGDB does carry GoG ids, and 82% of them

**The premise, verified before anything was built rather than assumed:
IGDB's `external_game_sources` endpoint answers 22 sources and GOG is `5`.**
The list runs `1 Steam`, `3 GiantBomb`, **`5 GOG`**, `10 Youtube`,
`11 Microsoft`, `13 Apple`, `14 Twitch`, `15 Android`, `20 Amazon`,
`22 Amazon Luna`, `23 Amazon ADG`, `26 Epic Games Store`, `28 Oculus`,
`29 Utomik`, `30 Itchio`, `31 Xbox Marketplace`, `32 Kartridge`,
`36 Playstation Store US`, `37 Focus Entertainment`,
`54 Xbox Game Pass Ultimate Cloud`, `55 GameJolt`, `121 IGDB`. A GOG row
carries the store's own product id as `uid`, and the deprecated `category`
field still answers `where category = 5` with the same rows.

### The hit rate, and where the sample came from

**394 of 480 public GOG product ids join: 82.1%.** The
sample is GOG's public store catalogue (`catalog.gog.com/v1/catalog`,
`productType=in:game`, 6360 products over 133 pages), ten pages taken evenly
across the whole of it in trending order so the long tail is in it as heavily
as the front page:

| catalogue page | 1 | 15 | 29 | 43 | 57 | 71 | 85 | 99 | 113 | 127 |
|---|---|---|---|---|---|---|---|---|---|---|
| joined, of 48 | 41 | 40 | **17** | 44 | 45 | 40 | 47 | 41 | 45 | 34 |

Page 29 is the one outlier and page 85 the best; popularity is not what
predicts a hit, so 82% is the honest figure for an unspecified selection of products
rather than a best case. A store catalogue is not an install list, and the two
differ in a direction that is not measurable from here: what people install
skews toward what they bought, which skews toward the front pages.

**The join is one-to-one.** 394 rows for 394 uids, **0 uids carrying a second
row and 0 resolving to a second IGDB game**. That is what entitles the resolver
to skip every gate — `minAutoScore`, `platformAgreement`, `volumeNumbersAgree`
and the resolver's tie rule all exist to make a *guess* safe, and there is no guess.

### The platform, which is the only thing the join does not answer

**A GOG `external_games` row carries no `platform`** — absent on all 394. So
the platform id for the `.xcoll` row comes from the joined game's own
`platforms`, picked by the detection's hint through `platformIds`
(`GogMetadataSource.platformHint` is `PC` → {6} ). **270 of the 394
joined games are listed on more than one platform**, so this is a real choice
and not a formality.

**385 of the 394 are listed on 6 and auto-match. Nine are not**, and they split
two ways: five are listed only somewhere else — two on 13 DOS, two on VR
platforms, one on 150 TurboGrafx — and reach review with the right game and the
platforms IGDB really gives it; four are listed on **no platform at all** and
fall back to the title path, because a hit is a (game, platform) pair and there
is no pair to make. Claiming 6 for any of the nine would assert a Windows
release IGDB does not record, on the one path in this product whose whole claim
is that it does not guess.

These nine came out of the same public-catalogue sample as everything else in
this section — nobody's library, for the reason stated where the sample is
described. Their titles are not named here.

### What a title match would have had to survive

Of the 394 joins, **376 carry a GOG title identical to IGDB's canonical name**
once punctuation is folded, and 18 do not. The shapes of those 18, which is
what the number is worth — the titles themselves are public-catalogue rows and
are not listed out here: an arabic numeral against a roman numeral, an
abbreviated edition against the full subtitle it stands for, a bare name
against the same name carrying a subtitle, a dropped diacritic, and a year-like
number standing where a subtitle is on the other side. That 4.6% is the part
of the string path the join removes outright; the collisions above are the part
it removes that the string path could not have got right at any threshold.

### Cost

**37 live IGDB requests** for the whole of this, plus 7 Twitch token requests
(one per script run) and ~15 unauthenticated requests to GOG's own public
catalogue. The two bulk sweeps over 480 ids were 8 requests each because
`where uid = (...)` takes 60 at a time under `limit 500`. Per row at runtime
the join costs **one** request where it answers, against one search plus up to
four more on `shortenedQueries`' ladder; a row that does not join pays one
request more than today and then resolves exactly as it does today.


## The 7B's density ceiling, and the loop past it

The task was filed on a dense shelf photograph that motivated the experiment: the local
model did not answer inside the shipped 120 s bound, and with
`SHELFSCAN_VISION_TIMEOUT=900` it answered HTTP 200 with a decodable JSON
document that was **not this one** — `unreadable[372]` a string where the
parse shapes an object — so the scan declined it whole and the photograph
yielded nothing.

**Everything counted below was measured on synthetic shelf frames generated
for the task** — invented titles, invented platform bands, a density and a
resolution chosen deliberately — for the reason the disk-sources section above
gives: the photograph that started it is private, and no figure taken on it is
recorded anywhere. The synthetic frames reproduce the failure, which is what
lets the numbers be stated at all.

Rig: `qwen2.5vl:7b`, Ollama 0.32.14, `num_ctx` 32768, 100% GPU,
`OLLAMA_NUM_PARALLEL` 1, the shipped `detectionPrompt` unaltered,
`format: 'json'`, `temperature: 0`, `seed: 20260814` — the request
`OllamaVisionProvider.analyze` builds. Frames are 3060×2040, spines in a grid,
titles unique within a frame; `prompt_eval_count` is **4932 on every one of
them**, so nothing here is a resolution effect.

### The ladder

| spines | output tokens | items returned | titles correct | invented |
|---|---|---|---|---|
| 6 | 298 | 6 | 6 / 6 | 0 |
| 12 | 579 | 12 | 12 / 12 | 0 |
| 24 | 1149 | 24 | 24 / 24 | 0 |
| 40 | 1929 | 40 | 40 / 40 | 0 |
| 60 | 2401 | 50 | 50 / 60 | 0 |
| 84 | 3023 | 63 | 63 / 84 | 0 |
| 120, ¾ of them in small type | 5504 | 114 | 108 / 120 | 0 |
| 176, ⅚ of them in small type | 27836 | — | the loop | — |

**Output is linear in spines** at ~48 tokens a row, right up to the loop.

**The model starts dropping spines between 40 and 60 and says nothing.**
`unreadable` is `[]` on every honest run in that table, so at 84 spines a
quarter of the frame is missing from an answer that parses cleanly and reports
no omission. Not one invented title on any rung of this ladder that answered,
and the densest of those is 120 spines — which makes what is measured here the
decision 0012 class rather than an invention regression: a quiet loss, not a wrong
answer.

**Above 120 the guarantee is not established, and the 176 rung is why.** It
looped on the first ask (below) and was never scored for invention at all, so
the top of this ladder is blank rather than clean. a later synthetic run scored it
on the one state in which that density answers — a warm image prefix, which a
real scan never has — and **8 of the 122 distinct rows are titles that are not
on the frame**, each continuing the two-word series past where it stops. What
that establishes is a limit on the range of the sentence above: past the
ceiling a frame can return rows that parse and read like spines. What it does
not establish is a rate, or anything about real spine titles — these frames'
titles are a regular series, which is itself the invitation to continue one —
or that the cold ask a real scan makes does the same, because that ask does
not answer at all. Numbers and method in "The generation cap" below.

**It is not legibility.** At 120 spines three quarters of the titles were
rendered in small type and 108 of 120 came back correct. What the ceiling
bounds is how much of one frame the model can hold, which is the same sentence
the earlier band experiment suggested from the Switch 2 band.

### The loop

At 176 spines the run does not answer. It generates **27,836 tokens** —
`4932 + 27836 = 32768`, the context window exactly — returns
`done_reason: length`, and breaks off mid-string, so it is not JSON.
Counted without reading it:

    "raw_title" keys                              580
    distinct values                                20
    last index at which a new value appeared       19

It read the first row and wrote that row out twenty-nine times. `temperature:
0` is why nothing escapes: greedy decoding has no draw to break a repetition
fixed point with. sampling pinned it for reproducibility and that is still
right; this is the bill.

**The same loop has a second site.** On the frame the ceiling was first found
on it runs away in **`unreadable`** instead — the array is 99% of the answer
and every `reason` string in it is byte-identical to every other, as is every
`script` value. That is a known phantom entry, which `detectionPromptRules`
forbids in as many words ("The entries are not copies of each other"),
running away rather than appearing two or three times.

### Two sentences, one cause — the defect that was worth fixing

Which failure the user meets is decided by whether the model closes its
document before the context fills, and nothing else:

| the loop ends by | the code | what the user was told, before the diagnostic change |
|---|---|---|
| filling the context | `done_reason: length` → `visionTruncatedFailure` | "there was more on that shelf than one answer can hold. Photograph it in two or three sections" — correct |
| closing the document | HTTP 200 → `visionWrongShapeFailure` | "the model is the thing to change **rather than the shelf or the photograph**" — wrong for this cause |

`visionWrongShapeMessage` now names the shelf first and the model id second.

### The timeout, measured and left alone

**Past the ceiling a raised bound buys nothing**: the answer is complete after
the first twenty titles and the remaining minutes are copies, and it is
declined at the end regardless. `SHELFSCAN_VISION_TIMEOUT=900` buys four and a
half minutes of progress bar over 120 s and the same zero rows.

**Below the ceiling the bound is not about the shelf.** Seventeen passes on
one machine, one model, one server process, inside thirty-one minutes:
generation ran **24.0 to 104.6 tokens/s**, median **102** over the thirteen
uncontended ones. The four slow passes (24.0, 27.9, 46.9, 54.0) fall inside
a competing app-test-suite window; four later passes inside that same
window ran at full rate, so the contention was bursty and the window is where
the slow block sits rather than a per-run tax that can be predicted. The
spread is the finding either way: a 120 s bound admits ~3,000 output tokens or
~12,000 depending on nothing but what else the machine is doing — roughly 60
spines against 250. No single number tunes that, so the default stays at 120 s
and the guide tells the user about the frame instead.

The pairs that show it directly, same frame, same tokens, different clock:
40 spines took 92.5 s in the slow block and 22.5 s outside it; 120 spines took
61.6 s and 56.7 s; 176 spines 304.9 s and 300.4 s.

### The bound on `unreadable`, rejected

Cutting the `unreadable` array off in the request schema was the cheapest
option on paper and does not survive the measurement:

1. **It does not cover the case.** The synthetic reproduction loops in
   `items`; a cap on `unreadable` leaves that run untouched.
2. **A legitimate `unreadable` list is bounded only by the frame.** The prompt
   asks for one entry per item left out, and decision 0012 records that one
   entry may cover several spines — so the count is a lower bound on spines
   and never a count of them. A cap low enough to stop a loop early is low
   enough to truncate an honest report.
3. **The prompt schema is not enforcement.** `detectionJsonSchema` is example
   text; the request sends `format: 'json'`. Editing that constant is a prompt
   edit (decision 0002), and `control_set_test.dart` pins a fingerprint of
   `detectionPrompt`, so it fails `dart test` everywhere until both control
   sets are re-measured — paid to add a rule the model already ignores once it
   is looping.
4. **The enforced version is not incomplete, it is worse — and that was
   measured, not reasoned.** Ollama's `format` will take a JSON Schema and it
   does honour `maxItems`. The 176-spine frame under a schema capping both
   arrays at 120 came back in 58 s, `done_reason: stop`, **valid JSON that
   parses cleanly** — and holding 120 rows of which **35 are distinct**, three
   of them repeated 30, 29 and 29 times, 55 of the 176 titles correct. So the
   bound converts a loud failure into a quiet one: today the loop is declined
   whole and the user is told; with the cap the same loop is accepted, and
   dozens of copied rows land in the review list looking exactly like titles
   read off spines. That is the existing visibility rule and decision 0012's class in one
   answer, which is the strongest argument against this option rather than the
   weakest. Anyone returning to it has to bound the loop *and* detect it, and
   a cap alone does only the first.

### What sectioning buys, on the frame that fails

The remedy both failure texts name, measured on the same 176-spine frame cut
into two halves of 88 at **identical pixel scale** (3060×1020 each, so nothing
about legibility changed):

| | titles correct |
|---|---|
| one frame, 176 spines | **0** — the loop, nothing returned at all |
| top half, 88 spines | 71 / 88 |
| bottom half, 88 spines | 59 / 88 |
| the two together | **130 / 176** |

Two vision calls instead of one, and the sections meet at one dedupe, so a
spine caught in both overlapping frames is still one row.

### Reproducibility

Every figure above is a temperature-0 greedy draw and repeats to the token.
Second passes: 40 spines 1929 tokens both times, 40/40 both times; 120 spines
5504 tokens both times, 114 items and 108/120 both times; 176 spines **27,836
tokens both times**, `done_reason: length` both times. What does *not* repeat
is the clock — see the tokens/s spread above, measured on the same two frames.

## The generation cap, and the ceiling that is not the context window

The Ollama request previously had with no `num_predict`, so the only bound behind
a `done_reason: length` was the server's context window. This section is what
choosing a number cost to establish. **Every frame is synthetic**, generated
for this task at 3060×2040 with invented titles and printed platform bands, and
`prompt_eval_count` is 4932 on all of them — the same rig as the section above,
independently rebuilt: `qwen2.5vl:7b`, `num_ctx` 32768, the shipped
`detectionPrompt` dumped out of `providers/vision.dart` rather than retyped,
`format: 'json'`, `temperature: 0`, `seed: 20260814`.

**The loop reproduced on a frame absent from the earlier experiment**, which is the strongest
thing to say for it: a fresh 176-spine frame, first ask, generated 27836 tokens
— `4932 + 27836 = 32768` — returned `done_reason: length`, and was not JSON.
296 s.

### What the cap does to that frame

Same frame, same first-ask state, `num_predict: 8192`:

| | tokens | done_reason | wall | the user gets |
|---|---|---|---|---|
| no cap | 27836 | `length` | 296 s | the truncated advice, after five minutes |
| `num_predict` 8192 | 8192 | `length` | 93 s | the same advice, three times sooner |

Both decline the photo. The cap buys the three minutes, not the outcome — and
it is the whole of what it buys, which is why the value could be argued about
rather than derived.

### The ceiling is `visionCallTimeout`, and it binds well below the window

A cap only helps if the generation reaches it before the call is abandoned:
past that the user is told the server went quiet, which carries no advice about
the shelf. The cold-ask budget measured here is **8.6 s to load the model, 3.5 s
to prefill, 103.8 generated tokens/s** — so 120 s admits about **11200**
generated tokens. 8192 lands at 93 s; 12288 would need ~130 s and never fire.
The context window, 27836 tokens away, never enters the arithmetic.

Neither bound survives contention. Earlier synthetic runs measured 24–105 tokens/s on this
machine depending only on what else was running, and at the low end no cap is
reachable inside 120 s. The value buys the uncontended case.

### The floor, checked rather than assumed

A synthetic 120-spine frame answered in **4690 tokens, `done_reason: stop`,
parsing, 100 items, `unreadable` empty, 97 of them real spines** — under
the earlier synthetic run's 5504 at the same density, on a different frame. 8192 clears both by
half again. **4096 is rejected on this**: it stops the loop in 46 s and it also
sits under every honest answer anyone here has measured.

### The state changes the answer, and it is the cached-prefix state again

The same 176-spine frame asked a second time, with its image prefix already in
the KV cache (`prompt_eval_duration` 0.05 s against 3.5 s cold), **does not
loop**: it stops on its own at 9006 tokens with `done_reason: stop` and a
document that parses — 191 rows, 122 distinct, 114 of them real spines. This is
the third cache state of earlier cache-state experiments reaching a different fixed point, not a
different frame, and the two runs diverge at character 2737 of the answer.

Two things follow, and the first is why the cap is where it is:

1. **A real scan is always the cold ask** — each photograph is sent once — so
   the runaway is the case the shipped path meets and the 9006-token answer is
   an artifact of asking four times. A cap chosen to preserve it would be
   chosen for a state the product does not run in.
2. **8192 does cut that warm answer off**, and it is worth stating plainly
   rather than discovering later: on the warm prefix the cap costs 114 real
   titles and returns nothing. Against that, the earlier synthetic experiment measured the same 176-spine
   density cut into two halves at identical pixel scale yielding **130 / 176** —
   more than the 114 — so the advice the decline prints beats the answer the
   decline suppresses.

The `num_predict` 8192 and `num_predict` 12288 answers on the warm prefix are
**byte-identical up to 8192 tokens**: the shorter is an exact prefix of the
longer. So the cap changes where the same greedy sequence is cut and nothing
else, which is what makes the comparison above a comparison.

### One thing past the ladder's end: the anti-invention guarantee has a density

the synthetic ladder shows no invented title on any rung that answered, and its
densest *answering* rung is 120 spines. At 176, on the warm prefix that
answers, **8 of the 122 distinct rows are titles that are not on the frame** —
and they are not misreads. Every one of them pairs a first word taken from
elsewhere in the frame with the last row's second word, continuing the series
past where it stops.

**Read this narrowly.** These synthetic titles are a regular two-word
combinatorial series, which is an invitation to continue a pattern that real
spine titles do not extend. It is evidence that a frame past the ceiling can
fabricate rows that parse and look like reads, not a measurement of the rate on
anything real. Filed as its own task rather than folded in here.

## TMDB's `year` filters, and the first live film searches (2026-08-23)

The first requests this project has ever made to TMDB. Eight searches settled
two questions — what the `year` parameter does, and what a year left inside
the query *text* does instead — and a scan of three constructed filenames the
same evening verified that the film path runs at all. All three parts are
below; the limits under them are as much of the measurement as the figures,
because three titles on one machine on one evening are what this rests on.

**On what.** No imagery, and nothing off anybody's disk: three films chosen as
public examples for the test — *Metropolis* (1927), *Alien* (1979) and
*Nosferatu* (1922) — asked of the live service through the shipped
`TmdbClient` with an API Read Access Token supplied for the run. They are
**neither a private collection nor part of this tree's invented fixture
family** — nothing quotes them as a fixture and nothing should start; they
are public-catalogue rows used as evidence, the way the GOG catalogue sample above are.

### The five searches

| query | `year` | results | first row |
|---|---|---|---|
| `Metropolis` | — | 81 | *Metropolis*, 1927 |
| `Metropolis` | 1927 | **1** | *Metropolis*, 1927 |
| `Metropolis` | 1926 | **0** | — |
| `Alien` | 1979 | 9 | *Alien*, 1979 |
| `Alien` | 1978 | 8 | *The Alien Factor*, 1978 — **the 1979 film is not in the list** |

**`year` filters rather than prefers.** A film whose catalogued release year is
not the one asked for is **absent from the answer, not demoted in it**. The two
off-by-one rows are the finding, and they show it failing in both of the ways
it can: a narrow title comes back empty, a common one comes back full of other
films. Nothing in the answer says a year was applied, so from inside the
process the two are indistinguishable from a title the catalogue does not have.

**The `results` column is what the service reported as the total, which is not
what reaches the resolver.** `TmdbClient.searchMovie` makes one unpaginated
request and reads that page: the query TMDB reported 81 results for handed the
resolver 20 rows. The two figures are the same measurement and neither is a
correction of the other — see the third row of the end-to-end table, where the
20 are what the tie rule then had to judge.

Three things were already resting on this before it was written down here:

- **The parameter stays**, and the measurement is the argument for keeping it:
  the same title goes from 81 candidates to 1, and the 1 is right. Dropping the
  year to avoid the off-by-one would hand a person eighty-one rows to read.
- **The zero-result retry is what the off-by-one costs.** A retry
  without the year, on a query that found nothing at all, is the whole of the
  remedy the filter needs; it fires only where the row was already lost.
- **A doc comment asserting the opposite was corrected by it.**
  `TmdbClient.searchMovie` had said that `year` prefers but does not require a
  match, so a filename year off by one still finds the film. Every clause was
  false. It had been written against a fake, which answered as it was told to —
  which is the reason this section exists rather than a second fake test.

### The year inside the query *text*, and the film a bare title returns

Three further searches, the same evening and the same token, asked the other
question: what happens to a year that is inside the query string rather than in
the `year` parameter. They are the searches that motivated a resolver change, and until now
they had not previously been documented in public.

| query | results | first row |
|---|---|---|
| `Metropolis 1927` | **0** | — |
| `Metropolis` | 81 | *Metropolis*, 1927 |
| `Nosferatu 1922` | **0** | — |
| `Nosferatu` | 55 | *Nosferatu*, **2024** |

The bare `Metropolis` row is the first row of the table above and not a second
search; it is repeated here because the pair is what carries the finding, and
the total of eight counts it once.

Two findings, and they are separate claims.

**1. A year inside the query text returns nothing.** Both titles, both
directions: with the year in the string, zero rows; with it removed, rows.
What the zero does not say is why — an unmatchable query looks the same
whatever made it unmatchable, which is the same blindness the off-by-one
`year` rows have above. On this side, the cause was the filename parser: the film grammar shared an installer's year floor of 1970,
so a film made before that kept its year in the title and the title was what
went to the service.

**2. A bare title returns the wrong film.** `Nosferatu` alone returns 55 rows
and the **2024** film is first, not the 1922 one that was asked for. Nothing
in the run says where in the 55 the 1922 film sits, only that it is not the
answer. So dropping the year is not a repair on its own: it buys back the rows
and spends the one thing that says which row was wanted.

**What follows from finding 2 is an argument, and this run is not it.** What
was measured is the four rows above and what came back. The inference — that
the year has to reach whatever *chooses* among the answers and not only
whatever fetches them — is the reasoning behind the separate `sourceYear`
field and behind the resolver's `_separatedBySourceYear`, which breaks a tie on a
candidate's release year. That machinery is where the design was argued and
settled; this evening neither established it nor exercised it. **No tie has
been broken by a year on a live TMDB answer.** The one row here that reached a
tie is the third of the end-to-end rows below, and its year had already been
spent on the search — it ended in the refusal, which is the other half of the
same rule.

### The path, end to end, the same evening

Three release-style filenames (`<Title>.<year>.1080p…mkv`, constructed for the
test — nothing was read off a disk), through the shipped CLI's film path:

| the row's year | outcome |
|---|---|
| *Alien*, 1979 | `tmdb:348`, release year 1979, **score 1.0**, auto-matched |
| *Metropolis*, 1927 | `tmdb:19`, release year 1927, one candidate, auto-matched |
| *Metropolis*, 1926 | the year emptied the query, the retry fired, **20 candidates** came back and **`best` stayed null** |

So the client, the credential in a header, the request shape, the parse, the
`tmdb:` namespacing and the retry are all verified on live answers. The third
row is the one worth reading twice: it is not a failure. Three films are called
*Metropolis*, the year that would have separated them is exactly the thing the
retry just spent, and the tie rule refused to pick — a refusal reaching a human
is the designed outcome, and it is the existing visibility rule holding on a catalogue it was
not measured on.

### What this does not establish, and it is most of it

- **Nothing about match quality.** Three titles is not a rate. No proportion of
  anything auto-matches, resolves or misses on the strength of this; a figure
  of that kind would need a corpus, and none was run.
- **Nothing about a release name that differs from the catalogue's.** Nothing
  in the run turned on one: every title was asked by a name the catalogue
  answers to directly, so `TmdbHit.originalTitle` — the field that exists for
  exactly the opposite case, and where anime and other non-English releases
  live — was never exercised against the live service.
- **Nothing about choosing among the answers.** The wrong-film row says a year
  is needed to pick; it does not show anything picking. No live answer here was
  separated by a release year, so `_separatedBySourceYear` remains exercised
  offline only, against a fake.
- **Nothing about the app.** The film path measured here is the CLI's, and
  that has not changed. The app can hold a TMDB token -- a
  Settings field routed to the OS keychain, where the CLI reads its own from
  the environment -- but no run through `app/` has ever had an answer from
  TMDB. So the figures below say nothing about the shell most people use, and
  a first app run against the live service would be a new measurement rather
  than a repeat of this one.
- **Nothing past resolution.** No film row has been exported and imported into
  a collection manager. "Verified end to end" still belongs to the photograph
  path alone, exactly as it does for the disk sources above.
- **Nothing about the failure paths.** No rate limit, no 401, no unreachable
  host was seen live; those messages remain offline claims against a fake, as
  does every other assertion in `tmdb.dart` that is not the `year` question.
- **The counts are third-party and dated.** Like the resolver's buckets, they
  can move without this repository changing — TMDB gains films, and a search
  total is a property of its catalogue on the day. Treat every number above as
  of 2026-08-23. What does not move with the catalogue is the finding: a
  filtering parameter stays a filtering parameter.
