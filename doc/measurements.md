# shelfscan — Measurement Archive

The measurements this project's decisions rest on, and everything it measured
and then rejected. Collected here by T-0125, out of the front page that had
accumulated them. Nothing here was rewritten; the numbers are quoted from code
comments and from briefs, and several of those comments cite them back.

**Not every figure, though, and the shortfall is a real one rather than a
backlog.** Some measurements live in the doc comment beside the rule they
settle instead of here, and `PROJECT.md` says so outright of
`detectionPromptRules` and `detectionJsonSchema`: "their doc comments carry the
numbers". Where a figure governs one constant, moving it here parts it from
what it governs and copying it here states one measurement in two places —
which is how two published versions of it come to disagree. The providers under
`packages/shelfscan_core/lib/src/providers/` are where that shows: of thirteen
distinct numeric claims sampled there by T-0271, eight have no home below, and
the sample was thirteen out of seventy-eight doc-comment lines carrying a
number — so eight is a floor rather than a total. **Look beside the rule before
concluding a figure was never taken.**

None of that loosens the standing rule in `PROJECT.md` that a new measurement
is written here in the first place: that rule decides between this file and
`PROJECT.md`, which is the page it exists to stop growing back, and it is not a
licence to leave a figure in a doc comment because writing it here is work.

Read this when you are about to spend effort on something — a bigger model,
splitting the photos, a prompt wording, a scoring threshold — or when you are
about to quote a number. The reason these records are kept is that the
alternative is paying twice for the same finding.

## The two control sets

Every figure below is quoted against one of two named sets of private
shelf photographs:

- **`CONTROL-HIRES`** — three 4000×3000 photographs, HEIC
  originals converted to JPEG once by WIC (T-0031).
- **`CONTROL-LOWRES`** — the same subject at 1200×900, two photographs.

**The photographs are of a private home, and neither they nor what they show
are published.** The images, their original filenames and any list of the
titles on the shelves stay in the working record beside them; this archive
identifies each set by what it is, and each photograph by a stable label —
`shelf-1.jpg` … `shelf-3.jpg` at 4000×3000, `lowres-1.jpg` and `lowres-2.jpg`
at 1200×900 — so that a figure stays attached to the file it was measured on
without the file naming itself. Every figure below was measured on those
photographs and is quoted with the method that produced it; where a passage
used to show its working by listing the titles it read, the list is gone and a
sentence saying what was measured stands in its place. **No figure here has
been restated over invented data.**

**No sentence here counts the spines, cases, games, rows or detections on a
control photograph.** The audit of 2026-08-18
found that a detection total, a per-photo split, a stack size and a
per-platform tally together reconstruct the size of a private collection, its
platform mix and which consoles are owned — the thing the ruling of 2026-08-17
put first among what may not leave the machine. T-0246 moved every such count
to `doc/control-set.md`, beside the photographs, next to the byte sizes that
had been kept there since T-0234, and **T-0253 removed the ones it had left
standing in prose** — a census does not stop being one for being spelled out
as a word rather than a digit, written as a ratio, or taken over a subset
rather than the whole. No example of the form is quoted here, because an
example of a census is a census. What each measurement *showed* is still
here, in full, with its direction and its conclusion; what a reader can no longer do is
add the numbers up into an inventory.

**What is still counted here, stated so the claim above is checkable rather
than reassuring.** Counts of runs, of prompt wordings and of tokens, which
measure the model rather than the shelf; counts of calls **where a call is
not one per row**, and of seconds **where the stage is not rate-bound** — both
qualified below, and both were unqualified here until T-0266; counts of what
a run got *wrong* — invented titles, phantom `unreadable` entries, rows
retyped between two answers — which have no object on the shelf behind them;
proportions whose total is nowhere in the tree; and IGDB's and GOG's own
public-catalogue figures. Two shapes are deliberately kept and are the
nearest thing to an exception: a passage that names the rows a rule changed,
one after another, still says how many there were by listing them (the names
are invented substitutes, the count of them is not), and the second-reader
breakdown on [`README.md`](../README.md) counts rows a second model added, of
which none was an item the first had missed.

**Two of those licences read wider than they are (T-0266).** A count of
*calls* measures the model only where a call is not one per row — an IGDB
search is one per row, so a search count is a row count in other units — and a
count of *seconds* is that same figure again wherever the stage is rate-bound,
because a duration over a published rate is a request count. Both were listed
above without those conditions, and both now carry them: the licences are
narrowed rather than struck, because this document still states durations and
call counts that meet them, and a list that omitted the class would be as
untrue of the tree as the clause this task came for.

**The third had never been measured at all.** "Proportions with no total left
in the tree to multiply them by" was an assertion rather than a measurement:
nobody had looked. T-0266 looked. Four files held a figure that divides back
into the row count of the hi-res control document, one of them stating it in
digits; four more scaled to it through the review file's own line count, and
one carried the size of a private folder. Twelve sites over nine files. No
value is quoted here, because the value is the thing being removed.

The sharpest instance is worth its own sentence, because the removal mechanism
produced it: T-0246 restated one file's request count as a **multiple of the
document's rows**, and said in the comment that it did so because the count is
the size of a private collection — while leaving the absolute counterpart of
that same multiple two lines below it. A ratio is only a removal while its
absolute is gone. Every one of the twelve now carries a ratio, a difference or
a formula and no total. **The clause is true of this tree and was false of the
tree it was written into**, which is the whole of why
[`doc/conventions.md`](conventions.md) §6a says a claim of cleanliness written
into the tree must be re-checked against it.

**The call licence is still too wide, one qualification further (T-0267).** "A
call that is not one per row" is a row count divided by whatever the call *is*
one per — and that divisor is usually not in the sentence at all. It is a
constant in `lib/`, which a reader looks up. The resolve stage's token request
is one per wave of `resolverConcurrency` lanes, so a count of those requests
times that constant is the row count again; two sites carried such a count and
both now state `rows / resolverConcurrency` instead. The same shape reaches
past calls: a display cap is one per *listed* item, so a sentence saying the
cap covers a whole real run bounds that run's rows through the constant. So the
class is **a figure a reader recovers using a constant in `lib/`** — one half
published prose, the other half source code — and no sweep over prose can see
it, because the rate is never in the prose. What sees it is the inverse:
enumerate the converting constants first, then look for a figure standing in
either unit of each chain.

Both resolutions are the standard control: a prompt measured on `CONTROL-HIRES` alone is
half-measured, which is how T-0026's low-resolution invention regression
survived four prompt edits. Why the control is a definition and a manifest of
figures rather than a committed scan is
[decision 0004](decisions/0004-the-control-set-is-figures-not-a-file.md).

Where a section below says "this file" it means this archive — with one
exception: T-0106's "this file's adjacency findings" are the adjacency findings
of [decision 0002](decisions/0002-the-prompt-is-a-measured-artifact.md), which
is where that argument now lives because it is a standing instruction as much
as a measurement. The sections are in the order they were written in, so the
"next section", "above" and "below" inside them still point where they pointed.

## Validation status (T-0001, done 2026-08-13)

Local qwen2.5vl:7b via Ollama on 2 real photos: ~80–83% end-to-end correct,
~93% on Latin-script titles. Findings:
- JP-script spines: none read; model **hallucinated** a plausible title
  with confidence 0.85 → anti-hallucination prompt task filed (Critical).
- Text-less logo spines (cases whose art carries no printed title) not
  detected — known limitation, handled by manual add at review.
- Platform hints track the printed platform band: correct where a spine
  carries one legibly, absent where the model reads none.
Verdict: GO. Pre-segmentation (T-0003) downgraded to optimization.

## Pre-segmentation, measured and rejected (T-0003, 2026-08-13)

Splitting each photo into overlapping strips was implemented, measured on
the same two photos with qwen2.5vl:7b, and reverted. 3 strips: the same
distinct real items as the whole-photo baseline, but 2 invented titles per
run (a correctly read three-word title came back with its middle word swapped
for one from a sibling in the same series; a two-word title came back with its
first word replaced), several truncated duplicates, and **every** platform hint
the whole-photo baseline had read off a printed band was lost. 5 strips was
worse: 4 inventions and a pile of fragments, including barcode numbers as
titles. Neither setting read a Japanese spine at all, or produced a platform
hint where the whole-photo read had none. Cost 3x and 5x the provider calls.

So `shelfscan_core` keeps its "http only" runtime dependency: the `image`
package needed for cropping pulls in 6 transitive packages (archive, xml,
petitparser, posix, ffi, path) and bought nothing.

After the anti-hallucination prompt fix (T-0007, done 2026-08-13): the
low-resolution count as it is recorded today, every detection corresponding to
a real item, zero invented titles; the JP-script spines are now omitted
instead of guessed. One finding to keep
in mind — the local model returns `confidence: 1.0` uniformly, including
on partial reads, so confidence is unusable even as a *ranking* signal
here, not merely untrustworthy as a gate.

## Every number was a sample until the request said otherwise (T-0053, 2026-08-14)

Two things were true at once and only one of them was known. The local
request sent no `options`, so nothing in this repository asked for the
sampling every figure depended on — and `qwen2.5vl:7b`'s own Modelfile
carries `temperature 0.0001`, so the answers came back near-greedy anyway.
Ollama's documented default of 0.8 was never in play. Every count taken
before this date is therefore a draw that happened to be stable, resting on
a model file nobody here controls, and not on anything this project did.

`OllamaVisionProvider` now states `temperature: 0` and a fixed seed. The two
control sets were re-run under it and verified against the photographs by
eye:

- low-res, 2 photos, 8 runs: the recorded count, 0 invented, every detection
  hinted and every hint correct
- hi-res, 3 photos, 8 runs: the recorded count, 0 invented, every detection
  hinted and all but the そらのは re-releases correct

byte-identical across all 8 (4 repeats plus seeds 1 / 12345 / 99) and
identical to the 4 pre-change runs — every one of them a repeat ask on one
loaded server, which is the condition that byte-identity needs and this line
did not carry until T-0086 (next section). Repeatability cost no quality here,
and the seed is inert while the temperature is 0.

## What temperature 0 actually bought (T-0086, 2026-08-15)

"Byte-identical across all 8" was measured honestly and stated without its
condition: all eight were **repeat asks on one loaded server**. Re-measured on
`CONTROL-HIRES` against an Ollama server started for the measurement
(`OLLAMA_NUM_PARALLEL=1`, its own request log accounting for every request it
served, no other client):

- **5 consecutive repeat runs — byte-identical documents**, `created` aside;
- **3 runs with the prompt cache dropped** (`ollama stop` first) —
  byte-identical to each other, and differing from the five on **about a third
  of one photo's rows**: letter case, ™/®, one diacritic. No count, no split,
  no hint, no item moved;
- **3 runs overlapped with a second process scanning the same server** — 30 of
  the 50 requests overlapping another in time — **byte-identical to the
  isolated five.** Concurrency was the first suspect and it cannot bite here:
  at `OLLAMA_NUM_PARALLEL=1` the server serialises the overlap, and the queue
  shows up in wall clock (55 s isolated, 65–84 s loaded) and nowhere else.

Concurrency is a real cause on a server that is *allowed* to batch, and that
is the sharper version of the finding (4 runs at `OLLAMA_NUM_PARALLEL=4`, same
model, same 32768 context per slot): isolated, that server answered the same
document twice and it differed from the `np=1` document on 3 rows, one of them
a bilingual title read without its first half — a difference `titleKey` does
not fold. Overlapped with competing traffic, 1 of 2 runs moved one more row's
letter case, and it moved to exactly the string T-0086 was filed over.
`OLLAMA_NUM_PARALLEL` is not something this repository sets: it is the same
class of hidden dependency as `qwen2.5vl:7b`'s own Modelfile temperature.

**The true claim, in the words that survive: at temperature 0 every figure the
control record counts reproduces across 18 hi-res runs — the total, the
per-photo split and the hint distribution, in all 18 — under every condition
below. The review
document reproduces BYTE for byte when the server has already answered those
photos and is serving one request at a time. A first ask, or a server allowed
to batch, can retype a row.** ("Unconditionally" stood here until T-0106 found
the condition those 18 runs never met: see the next section.) The model has two answers per
photo and each is reproducible on its own: 6 first asks — 6 model loads, two
server processes, a three-photo and a one-photo scan, three and a half hours
apart, before and after T-0085 merged — wrote one of them to the byte, and
every repeat wrote the other.

**What this does and does not invalidate.** Every earlier figure that compared
*counts* stands: T-0074's thirteen wordings, T-0026/T-0033/T-0034's invention
and hint counts, T-0053's own detection numbers, the control manifest. Only
claims of *byte* identity carry the condition — T-0053's "all 8" above is the
one this project made. Resolve buckets are unaffected by case (`IgdbClient`
lowercases) and by legal marks (T-0063); the diacritic in those retyped rows is
not folded anywhere and is filed as T-0091.

**The switch is the prompt cache, not the cold/warm boundary this file
recorded.** A server already loaded and busy on two other photos, asked for
this photo for the first time, answered with the first-ask typography exactly.
llama-server reports `cached n_tokens = 4890` of 4891 on a repeat and 15 on a
first ask: a repeat skips the prefill, so it is not the same arithmetic that
produces the logits. `ollama stop` correlates only because it discards the
cache along with the model.

The control is defined as figures rather than as a file, and the definition now
says what a regeneration is allowed to differ in ([decision
0004](decisions/0004-the-control-set-is-figures-not-a-file.md)).

What the pinning protects is visible at 0.8: five seeds give five different
hi-res totals and four different low-res ones, none of them the pinned figure
more than once, invented titles on 3 of 5 seeds at
each resolution, and `platform_hint` answered with the schema example text
verbatim on whole photos. **T-0007's zero-invention guarantee is a property
of near-greedy decoding as much as of the prompt wording** — a prompt
measured at another temperature is a measurement of a different system.

One residue, measured and not fixed: the two answers differ on one photo only
— about a third of its rows, ™/® and letter case, no item and no hint moved,
and `titleKey` folds the difference away for dedupe (not for the resolver:
T-0063, and the diacritic in those rows is T-0091). Two five-photo scans of
already-answered photos wrote byte-identical review files; one after
`ollama stop` wrote the same rows in the same order with a handful typeset
differently. Ollama
unloads an idle model after 5 minutes and the cache goes with it, so two scans
an hour apart are two first asks — the mechanism behind the two disagreeing
scans that opened this task.

The cloud providers state their sampling too since T-0057, but only one of
them can be asked to repeat: the Anthropic Messages API takes a temperature and
has no seed, so a figure from it is a stated draw rather than a reproducible
one. Neither has been measured — no cloud key was available — so no
number in this file is evidence about a cloud model. The recipe for taking
those numbers is the doc comment on `AnthropicVisionProvider`.

## A third cache state, and the counted figure that moves in it (T-0106, 2026-08-15)

The cache matches a token *prefix* and the photo's tokens come first, so there
are three states and `cached n_tokens` names which one a request is in: 15 when
nothing of this photo is cached, 4890 of 4891 when this exact request has been
served before, and something between when this photo has been — under a
**different prompt text**. It holds several photos at once, which is what makes
the third state ordinary: three consecutive scans of `CONTROL-HIRES` logged
4890 on all six asks of runs 2 and 3, so a re-scan is repeats, and **scanning
the set under a changed prompt puts every photo of the second pass into the
third state** (4817 on 3 of 3, twice). That is a prompt A/B — the reason anyone
runs these photos twice, and what T-0026, T-0028, T-0033, T-0034, T-0074 and
T-0093 each did.

There `unreadable` moves, and it is the only counted figure that does. The
middle hi-res photo, whose spines a hand check finds all legible, answers
**3 phantom entries** — one `unknown` and two byte-identical `japanese`, the
copies `detectionPromptRules` forbids in as many words. Across 34 asks in that state
it is 3 on 18 and 0 on 16, never another number and never on another photo:
2 of 2 whole-set A/B runs; with one photo and `ollama stop` first, 5 of 5 for
T-0093's schema edit, 3 of 3 for a change to the prompt's first line, 2 of 2
for an unrelated prompt, 0 of 3 for a change in the `confidence` bullet and
0 of 3 in the schema's last line; 4 of 14 on a server left running for an hour.
**Where the change sits does not predict it** — the one thing this file's
adjacency findings would have led anyone to expect.

Everything else holds on both control sets: the total, the per-photo split,
every detection hinted and the same distribution, 0 empty titles, the middle
photo's titles byte-identical, and the low-resolution figures likewise. The
folded row set holds in that A/B too,
but not in every third-state ask: on a server left running, 13 of 14 read one
bilingual spine without its non-English half — the same row and the same loss
T-0086 measured at `OLLAMA_NUM_PARALLEL=4`.

So unlike the other two states this one has no document: 21 asks of one request,
differing in nothing but what the server had cached, wrote three. The rule is
to stay out of it rather than to reproduce it, and it costs one line —
`ollama stop qwen2.5vl:7b` immediately before the run whose figures you take,
which is now part of the regeneration recipe. Putting a
different photo between the two asks does not work; the cache restores the old
prefix anyway.

## The Switch 2 band, measured and rejected as a prompt problem (T-0074, 2026-08-15)

A Nintendo Switch 2 case prints a `2` in the band at the top of the spine and
a Switch 1 case prints the same band without one; the model answers `SWITCH`
for both. Reading the printed `2` was measured to turn a whole band of those
rows from review into correct auto-matches, so it was worth a serious
attempt.

**Thirteen wordings, one hi-res run each at temperature 0.** None works, and
the failure has a shape: with `SWITCH2` absent from the schema menu, prose
about the band is **inert** (not one banded case named, every time); with it
present the model answers it **wholesale** — per photo, not per spine (every
banded case named, and a false `SWITCH2` on most of the other spines in the
same photograph). A bare uppercase token in the rules re-opened the
T-0014/T-0028 copying defect **at temperature 0**, answering the literal
`SWITCH2 | N64 -- omit this field entirely...` on most rows of a photo. Twelve
of the thirteen also cost one detection off the hi-res total.

**The stop was the low-res control**, for the third time in this bullet's
neighbourhood: the best-performing variant invented titles on 3 of 4 runs at
1200×900, displacing a real title from the shelf.

**It is a capacity limit, not a wording one.** Asked *only* about the band —
"what is printed in the red band at the top of this stack, character by
character" — the model answers `2` correctly on every one of them. Asked to
compare two marks it says they are identical. The `2` is perceived and transcribable; the 7B
cannot hold that discrimination across a whole photo of spines while also
reading titles.

Remaining levers, in the worker's order: a **second targeted pass over the
band region** — note T-0003 rejected pre-segmentation for the *title* read,
not for a hint read, so it is not the same experiment — or a cloud model in
T-0011's fallback slot.

## The second lever works: `gpt-5.5` reads the band (T-0112, 2026-08-16)

The cloud half of T-0074's remaining two levers, measured on all five control
photos through the shipped `OpenAiCompatibleVisionProvider` against live
`api.openai.com`. **Five repeats of `CONTROL-HIRES` and five of
`CONTROL-LOWRES`, 25 billed calls, 285,174 tokens, $3.18.** Model id `gpt-5.5`,
which the endpoint's own `/v1/models` listing resolves to `gpt-5.5-2026-04-23`;
prompt fingerprint `56cb401b`, unchanged. Harness: `tool/cloud_probe.dart`.

**These figures are prose and must never become a `control-set` manifest
block**, for the reason T-0090 gives: a manifest block is what a regeneration
must reproduce, and a vendor model id is not a thing a count can be pinned to.

Per photo, `gpt-5.5` reads slightly more than the local model on two of the
three hi-res photographs and materially more at 1200×900, and it is stable
where the local model is: `shelf-2.jpg` and `lowres-1.jpg` return the identical
count on all five runs, while `shelf-3.jpg` and `lowres-2.jpg` wander by
several rows. The counts themselves are in the control record
(`doc/control-set.md`), which is where every per-photo figure now lives
(T-0246); the comparison, not the census, is what this section is for.

**The band is read, per spine, and it is right.** Every `CONTROL-HIRES` call
was tallied by hint, each row's answer or its absence, and the tally sums to
exactly the hi-res detection total across the 15 calls and not to the total of
all 25, **so this tally is hi-res only**, and the low-resolution
read below sits outside it. Checked spine by spine against the photographs:

- `shelf-2.jpg` — **every case whose band prints a `2` answered `SWITCH 2`, all
  five runs**, and every case whose band does not, `SWITCH` every time. A case
  printing no `2` directly under one that does is answered `SWITCH`, so this is
  not a per-photo answer of the kind every T-0074 variant gave. Every title and
  every hint on that photograph correct, on all five runs.
- `lowres-1.jpg` at 1200×900 — **every case whose band prints a `2` answered
  `SWITCH 2`, all five runs**, zero false positives on the cases printing none.
  This one is `CONTROL-LOWRES`: further correct reads that are **not** part of
  the hi-res tally.
- `shelf-1.jpg` — the Latin-titled cases carrying the `2` are all `SWITCH 2` on
  all five runs; the CJK ones are declined (below).
- `shelf-3.jpg` — no `SWITCH 2` at all, and **that is a miss, not the
  correct abstention this bullet claimed until T-0220.** The frame cuts a
  column at its edge, but several of the spines in the cut print the band
  legibly and none of them is read. "A cropped column's fragments" below is where that was
  measured and where the two readings are reconciled. The hint count is zero
  either way; only the verdict on it moves.

**What the hi-res band tally is a tally *of*, itemised, so it is never quoted
at another scope again.** The banded spines of `shelf-2.jpg` over five runs,
plus the Latin-titled banded spines of `shelf-1.jpg` over five runs, plus
nothing from `shelf-3.jpg` (a cut column left unread, not a photograph without
a band), plus the invented rows below, which carry a correct `SWITCH 2` hint on
a title that is not on the shelf. The published form is **every band hint
correct across `CONTROL-HIRES`, five runs each** — not "across all five control
photos", which the itemisation contradicts.

**What was not measured at 1200×900.** The band was checked spine by spine on
`lowres-1.jpg` and nowhere else in `CONTROL-LOWRES`: no
`SWITCH 2` read is recorded either way for `lowres-2.jpg`, and
no hint tally was taken over the low-resolution set as a whole. Its evidence
for the band is that one photograph's every-case-correct, and quoting a low-res
figure beside the hi-res tally as though they were one measurement is what this
section was corrected for (T-0206).

Nothing wandered: **no title was hinted two ways across repeats** on any of
the five photos.

**T-0029 is answered as a by-product, and T-0023 was right.** The
Japanese-script spines the local 7B hints `PS2` — consecutive volumes of one
series, some carrying a volume number, one a Latin subtitle — carry the
Switch 2 band, and `gpt-5.5` both transcribes every one of them in Japanese,
volume numbers and subtitle included, and hints `SWITCH 2` on each, on all
five
runs. `gpt-4.1-mini` read none of them (T-0090). So **"a cloud model will read
the Japanese spines" is retired as false for `gpt-4.1-mini` and true for
`gpt-5.5`**; it was a model claim, not a cloud claim.

**`CONTROL-LOWRES` is passed, which is where every previous attempt died.**
Five runs, 10 calls, **zero invented titles** — every row on both photographs
checked by eye. The one glare-struck spine that `gpt-4.1-mini` returns as a
different title from the same series on 3 of 5 runs (T-0090) is read
correctly on 5 of 5 here. The folded title set of
`lowres-1.jpg` is **identical on all five runs**.

**One invention, and it is at 4000×3000.** One spine on `shelf-1.jpg` carries
a Traditional-Chinese title; on **2 of 5 runs** it comes back as an unrelated
Japanese-script title, hinted `SWITCH 2`, and on the other 3 it is declared
`unreadable` with an accurate description. **Two rows across all five
`CONTROL-HIRES` runs** — the same spine twice, on one photograph;
`CONTROL-LOWRES` invents nothing at all. It replaces an `unreadable` entry
rather than displacing a correctly-read title, which is the milder of the two
failure shapes, but it is an invention against T-0007's guarantee and it
arrives wearing a confident platform hint. A Japanese-script spine on the same
photograph is declined on all five runs.

**A denominator of unknown provenance was retired here (T-0215).** This
paragraph and the working record for T-0112 both quoted one number as the row
total across all 25 calls. `cloud_probe tally`'s own per-photo output does not
sum to it under any grouping — neither the hi-res subtotal nor the whole — and
`tally` prints no grand total for one to have been misread from. So it was a
figure of unknown provenance rather than a fourth scope, and the denominator is
the recorded hi-res total instead. Nothing was re-scanned to settle it, and the
two invented rows are not in question. T-0147 borrowed the same number for the
fragments; its own user-facing figure, the duplicate rows in an affected hi-res
scan, does not rest on it. (The totals themselves are in the control record,
T-0246.)

**What is not stable is whether the cropped fragments come back at all.** On
2 of 5 runs `shelf-3.jpg` also reads the edge-on column at the frame's
right and returns truncated rows, each the leading one or two words of a
longer spine and each cut on a word boundary, all hinted `SWITCH`. The rows
themselves are not published; what the measurement turns on is where they
cut. They are honest partial reads, not
inventions. They are also the one new defect this lever introduces: see
T-0146 — which measured that they are **not** what it was filed for.
Every cut lands on a word boundary, and they were already rows before the band
was read as well as after, so the hint gate was never their cause. T-0146
fixed the mid-word case it did find and filed **T-0147** for these; T-0147,
not T-0146, is the item standing between this lever and a clean run.

**Sampling could not be stated.** `gpt-5.5` refuses `max_tokens` (use
`max_completion_tokens`) and refuses `temperature` at any value but its default
1, both as HTTP 400s that T-0089's rule obeys and reports. So every figure here
was taken at the endpoint's own sampling, and the stability above is measured
rather than asked for. Two refusals per provider instance, free in tokens.

**Cost.** 11,045 prompt tokens per 4000×3000 photo and 2,353 per 1200×900 one,
plus ~3,850 completion tokens either way, of which about two thirds is
reasoning. At the vendor's listed $5 / $0.50 cached / $30 per million
(2026-08-16): **a three-photo hi-res scan is $0.38–$0.46**, a two-photo low-res
scan $0.20–$0.27. So a full scan of the shelf these were measured on costs
about **$0.45** against $0 local. Prompt caching is worth having and
is automatic: 129,792 of 165,675 hi-res prompt tokens were cached, because all
photos in a scan share the prompt prefix.

## A cropped column's fragments, measured and left alone (T-0147, 2026-08-16)

The defect T-0112 introduced and T-0146 could not reach: on 2 of 5 `gpt-5.5`
runs `shelf-3.jpg` returns one- and two-word rows, honest reads of
spines the frame cut, which
`isTruncatedRead` refuses at both scopes because all four cut on a word
boundary. **No code changed. This section is the deliverable.** Nothing live
was spent: every figure below is offline, off the shared capture and off the
photographs.

**The geometry, by eye.** `shelf-3.jpg` clips a column at its right edge, of
which the frame leaves between fourteen characters and none. Every fragment
off that edge is a duplicate of a row the same run already carries, so on
`CONTROL-HIRES` a fragment costs a tap and carries nothing.

**On `CONTROL-LOWRES` it is the opposite, and that decides the prompt lever.**
`lowres-2.jpg` clips a column at its right edge and `gpt-5.5` returns such
fragments on **5 of 5** runs; no other photograph of that set covers what the
cut leaves out. In that scan
the fragments are the **only** report the pipeline makes that a whole column
of games was cut. A prompt that declines a cut spine deletes them, and
"a silent failure is worse than a loud one" ([decision
0012](decisions/0012-what-is-dropped-is-named-never-counted.md)) settles which way
that trades before anything is measured. The prompt also already says
*"Do not guess full titles from partial text — put the partial text in
`raw_title` as read and lower the confidence instead"*: the fragments are that
rule working, and the instruction that would suppress them contradicts one
written to hold T-0007's guarantee.

**The defect is not in the photographs, it is in the model.** The shared
capture (`FRESH` for both sets, prompt fingerprint `56cb401b`,
`qwen2.5vl:7b`) reproduces the recorded per-photo split, and **no row of either
cut-column photo is a strict word prefix of any other row of the run**. The
shipped default reads nothing off either cut column. The fix would be to a
prompt that has no per-provider copy (`detectionPromptRules` is shared by
design), for an opt-in cloud path that costs $0.45 a scan.

**A "this row looks like a fragment" marker is measured, not argued, and every
row it marks is wrong.** Over that whole five-photo run the relation *A's
whitespace-separated words are all of B's first words, and B has more* holds 10
times, over a handful of distinct short rows — one of them appearing in two
photographs. **Not one of those rows is a cropped fragment.** Some are separate
cases sitting on the shelf beside the longer namesake that swallows them —
each visible in the photographs — and another is a glare-struck spine whose
trailing volume digit is read short,
T-0024/T-0054's own counterexample, still live in the shipped capture. (The
rows themselves are shelf contents and are not published; the relation, and
the fact that it holds on each of them and never on a real fragment, are the
measurement.)
Any text rule strong enough to mark the
shortest cropped fragment marks these; the cropped column, which is the thing that makes a
fragment a fragment, leaves no trace in `detectionJsonSchema` at all.

**What measuring the prompt lever would cost.** At T-0112's rates one run of
both control sets is 55,268–59,372 tokens (33,135 + 11,009–12,868 hi-res;
4,706 + 6,418–8,663 low-res). T-0147's 120k budget therefore buys **two** runs
of the variant — against a defect with a 2-of-5 base rate, so two clean runs
have a **0.36** chance of meaning nothing. Against T-0112's fixed 2/5, Fisher's
exact reaches p < 0.05 only at **16** variant runs (10/C(21,2) = 0.048): about
**913k tokens and $9–12**, 7.6× the budget, and that is before re-running the
baseline under the changed prompt's own cache prefix. A prompt edit also fails
`dart test` everywhere until both `control-set` blocks are re-measured on the
local model (`test/control_set_test.dart` pins them to the fingerprint), so a
change made for one opt-in cloud model re-prices the default provider's control
document.

**What would change this.** Any one of: a positional field reaching the review
screen for another reason — a row whose box touches the frame edge is decidable
where its text is not, and the marker becomes a rule with no heuristic in it; a
fragment measured to auto-match and export a wrong IGDB id rather than to sit
in review (the fragments that are word-prefixes of a real IGDB name are
the candidates); the rate
rising off one photograph and one provider; or `gpt-5.5` ceasing to be an
opt-in.

**A correction to T-0112, from the same by-eye pass: its "no `SWITCH 2`,
correctly" for `shelf-3.jpg` is a miss, not an abstention.** Several spines in
the cut column print the red band legibly, and some of the fragments come off
spines whose band prints a `2` and are answered `SWITCH`. On the 3 of 5 runs
that return no fragment at all those spines are simply unread, which is not an
abstention either. No count moves: the fragments carry a `SWITCH` hint, so the
photograph contributes no `SWITCH 2` on every run either way, and the band
tally stands, as do the
detection totals it is quoted against.

**Which of the two passages stands, settled from the record (T-0220).** Both
sat in this file at once, and a reader of the T-0112 section alone got the
retracted verdict. The order is mechanical — that bullet was written 2026-08-16
08:13 and this correction 09:24, 71 minutes later, and the later text names the
earlier as the thing it corrects — but recency is not the argument, because a
later pass can be the careless one. The evidence is asymmetric in the same
direction. T-0112's by-eye pass checked this photograph's uncut rows
and magnified spines of a *different* photograph to settle what they print, so
its "correctly" is an inference from the frame's geometry rather than a read of
the cut column — and on the three runs in five where that column returns
nothing, there is no row there to check. T-0147 read the frame's right edge as
an upscaled crop, which is the disputed region itself, and counted the legible
bands in it. The later passage rests on a magnified read of exactly
what the earlier one judged from a distance, so it stands and the bullet above
now carries it. Nothing was re-scanned and no live call was made to settle
this; both passes are already in the working record.

## One spine, two gates: the missing `0` is never the binding one (T-0113, 2026-08-16)

T-0113 was filed as "the read drops the printed volume digit `0` off one
Japanese-script spine, and that costs an auto-match". The read is real — the
shared capture (`FRESH`, nothing scanned) holds that title digitless
for `shelf-2.jpg`, exactly as filed. The **cost** is not:
it was measured under a condition the filing dropped.

The spine is on a real shelf and is not named here; below it is *the read
with the digit* and *the read as it comes back, digitless*, which is the whole
of what the measurement turns on.

The control record states it with the condition attached — that spelling
auto-matches at 1.000 *"under a `SWITCH2` hint"*, which is the hand-corrected
third control condition, not the set as it reads. As it reads, every
Japanese-script row is hinted `PS2` (T-0029). That hint is not a passive
wrong label; it removes the game from the run twice:

- `platformIds['PS2'] = {8}`, so `IgdbClient._games` puts `platforms = (8)` in
  **every** request the row makes — `search`, T-0094's
  `alternative_names.name ~` filter and each `shortenedQueries` retry — and
  additionally drops any hit whose platform is not 8. The game itself
  is Nintendo Switch 2 (508) and cannot come back through any of them;
- and if one did, `platformAgreement('PS2', 508)` is `mismatch`, which
  `ResolverWorker._best` refuses outright.

**Measured offline, no network and no scan**, by running the shipped
`ResolverWorker` against a stand-in server that honours `platforms = (…)`
exactly, treats `alternative_names.name ~ *"needle"*` as a case-folded
substring test, and answers plain `search` with nothing — which is what T-0094
measured live for this title:

| read | hint | requests | candidates | best |
|---|---|---|---|---|
| with the printed volume digit | `SWITCH 2` | 2 | 1 | the right game, Nintendo Switch 2, @ **1.000** |
| with the printed volume digit | `PS2` *(as read)* | 4 | **0** | none |
| digitless *(as read)* | `SWITCH 2` | 4 | **0** | none |
| digitless *(as read)* | `PS2` *(as read)* | 4 | **0** | none |

The first row reproduces T-0094's live 1.000 exactly, which is what says the
stand-in is faithful; the third reproduces the control's own "the fallback
finds nothing on this document". **The two defects are conjunctive.** Fixing
the digit while the hint stays `PS2` moves nothing — 0 candidates before and
after — so T-0113 pays only after T-0029, and T-0029 pays only after T-0113.

That re-prices all three levers:

- **The prompt.** Unaffordable and aimed at the wrong half. `detectionPromptRules`
  has no per-provider copy (T-0147), so any edit re-prices the *default*
  provider's control document and fails `test/control_set_test.dart` until both
  blocks are re-measured — which needs a local scan of the GPU. T-0074
  spent thirteen wordings in this exact neighbourhood and concluded the 7B is
  at a capacity limit, not a wording one. And the two providers fail
  differently: `gpt-4.1-mini` drops the whole title and answers `DIRECTOR'S CUT`
  alone, the 7B keeps the series name and drops the digit, so there is no one
  wording to write.
- **The review row.** Over every row of the shared capture, **none** would
  fire a marker for "this read names no game" (whole read inside a closed
  edition/qualifier vocabulary). The rule has no false positives on that data
  and no true positives either: the only instance is one row of a real
  `gpt-4.1-mini` export, which is not reproducible without buying that scan
  again. The row already carries T-0123's `not in .xcoll -- tap to pick a
  match`. Note the brief's premise that the candidate picker recovers the fix
  is false: `_CandidateSheet` lists only what the resolver found and offers no
  search, so for a read that names no game every choice in it is wrong or
  "No match"; the repair is the group header's add-by-hand.
- **The alias table**, the third lever, priced here because nobody had. It
  works mechanically — `_applyAliases` is a substring rewrite, so
  an entry restoring the dropped volume digit makes the query equal to IGDB's
  stored alternative name at 1.000, and `sameVolume` accepts it because it is
  satisfied by any spelling the score was allowed to use. It is still worthless:
  under `PS2` it dies at the same platform clause (row 2 above), and under a
  corrected hint the only provider that produces one, `gpt-5.5`, already prints
  the digit — so the entry would never fire. Against that, it is one alias per
  misread spine in a table whose contract is regional titles.

**What is already decided covers this row.** T-0112 measured `gpt-5.5` on this
photograph at every title and every hint correct, on 5 of 5 runs, with
no code change: it prints the digit *and* it reads the Switch 2 band, which is
both gates at once and is the only thing measured that clears them.

**What would reverse this.** T-0029 landing on the default provider, which
makes the digit the last gate and T-0113 worth exactly one auto-match at 1.000;
a per-provider prompt, which would let a wording be measured without re-pricing
the default control document; IGDB gaining a digitless or half-width spelling
as an alternative name, which would let the field filter reach the title from
the read as it is; or staying on `gpt-4.1-mini`, which is the one
condition under which the review-row marker is worth its width.

## A bigger local model, measured and rejected (2026-08-14)

`qwen2.5vl:32b` was pulled and run against the same three 4000×3000 photos
as the 7B, same prompt, same context length:

| | `qwen2.5vl:7b` | `qwen2.5vl:32b` |
|---|---|---|
| detections | the recorded hi-res count, on 3 photos | **little over half of it, on 2** |
| photos processed | 3 of 3 | **2 of 3** — one died with `Ollama 500` after retries |
| wall clock | **77 s** | 727 s |
| resident | 100% GPU | 29 GB, 26% CPU / 74% GPU |

The 32B does not fit: 21 GB of weights plus a 32768 context comes to 29 GB
against 24 GB of VRAM, so a quarter of it runs on the CPU. On the two photos
it did finish it matched the 7B at best and transcribed Japanese worse
(on one Japanese title it dropped a middle clause and the volume digit both;
on another it duplicated a clause), kept the same `PS2` platform errors, and emitted one detection with
an empty title. Nine times slower, one photo lost outright, nothing gained.

Consequence for T-0029 (the Japanese-script spines answering `PS2`): a bigger
*local* model is not the lever on this hardware. The remaining candidates
are a cloud model in T-0011's fallback slot, or reading the console icon as
an image region.

**The cloud half of that is now measured and false (T-0090, 2026-08-15).**
`gpt-4.1-mini` on all five control photos, 38 live calls: it does **not** read
the JP-script spines — it reports them as unreadable on every run, which is a
better self-report than the local model gives and a worse read. It returns
fewer detections than the local model, and invents a title at 1200×900
(one glare-struck spine returned as a different title from the same series,
3 of 5 runs) that the 7B does not. So
"a cloud model will read the Japanese spines" was an assumption, not a
finding, and it is retired for this model. T-0028's hand count of unread
spines on `shelf-3` is also corrected upward by one.

**Reframed 2026-08-15 by T-0023.** Those `PS2` hints are very likely a
misread of the **Switch 2 band**, not PlayStation-2-era confusion — those
spines carry the band and it is what the model is reading. With the
hint corrected by hand, the first of those spines resolves to the right game on
Switch 2 with no code change at all. So T-0029 is probably not a
model-capability problem, does not need a cloud key, and is the same missing
prompt clause as T-0074. Measure before spending anything on it.

## The resolver, measured at last (T-0008 and T-0002, 2026-08-15)

The resolve stage had never once run against live IGDB — no credentials
were available until 2026-08-14. Measured on `CONTROL-HIRES`, every
row checked against the photographs. These buckets are the one class of figure
here that is **not** pinned by a test: unlike a detection count they can move
without this repository changing, because IGDB gains games. The bucket sizes
are in the control record (T-0246); what they showed is here. Treat both as of
their date:

- **The great majority auto-matched correctly, exactly one wrongly, and the
  rest had no candidates at all.**
- **All but one of the misses never reached the scorer** — IGDB returned zero
  rows. Word order, subtitle noise, regional titles, corrupt reads: **zero
  occurrences each.** So the string metric was never the problem, and T-0002
  was re-scoped from "replace Levenshtein" to what the data indicted.
- What it indicted: `_score` compared titles only while `IgdbClient` emits one
  hit per (game, platform) pair, so a dozen rows scored 1.000 at once and
  `best` was whichever returned first. On the older prompt **all but one of the
  false positives were exactly that** — a console title matched to Xbox,
  another to Android — and in several of them the right row was not even in
  the `take(5)` a reviewer sees.
- `minAutoScore` was never the knob: scores cluster at 1.000, thin out through
  0.95–0.99 and 0.90–0.95, and there is **nothing between 0.85 and 0.90.**
  Every false positive scored ≥ 0.905. It stays at 0.85.
  **That empty band is gone (T-0100, 2026-08-15).** Once T-0095 trimmed the
  scorer, Japanese-script siblings from one series straddle the threshold *in the
  wrong order*: a wrong match scores **0.857** and a right one **0.852**, and a
  one-word-short read of a right Latin match scores 0.829 below it. Short
  titles are where normalised Levenshtein has no resolution left, and every
  Japanese title here is short — so the threshold argument does not transfer
  from the Latin measurements it was taken from. **No threshold was moved.**
  What separates the siblings is not a score: the spine prints a volume number
  and the name it matched does not, which is T-0055's and T-0059's conclusion
  about dedupe transferred to resolution. `volumeNumbersAgree` refuses that as
  an auto-match on any path — of the candidate observations across both control
  sets that carry a digit on either side, a minority disagree, exactly one of
  those is at or above the threshold, and **no auto-match is lost** on any of
  the three conditions.

T-0002 gates `best` on the platform and only *ranks* `candidates`, so a
contradicting row sinks but is never hidden from the human. Result on the old
run: more correct auto-matches, and the wrong ones down to a single row.

**A third of the misses were one character** (T-0063): those detections
returned zero IGDB rows because the read carried a legal mark.
Measured per symbol on one title: **® 0 hits, © 0, ℗ 0** — but **™ 1 and
℠ 1**, so the fatal class is not "trademark symbols" and the two the
filing named are the two that are harmless. All five symbols are stripped from
the query now, and the raw title stays exactly as read. Auto-matches went up by
as many rows as the marks had been costing, and the no-candidate bucket down
by the same.

The deeper consequence: whether a read carries those marks *is* the cold/warm
difference T-0053 measured and called harmless because "`titleKey` folds it
away" — true for dedupe, false for the resolver, which never calls
`titleKey`. Before the fix, nearly a fifth of the rows resolved differently
depending on whether Ollama had the model loaded. After it, none. **No resolve
measurement
taken before 2026-08-15 is reproducible.**

**The platform hint is load-bearing, and that is now measured.** With hints
stripped — the state T-0001 measured — the old code
auto-matched most of the run and named the **wrong console on well over half
of those** (Echo of the Hollow → Wii U, Edge of the Soren → PC). The tie rule
takes that to a third as many auto-matches, **none wrong**, and the rest to
review. The current prompt hints every detection, so this is
insurance rather than a live wound — but it is why T-0026 and T-0033 were
worth their measurement passes.


## The tie nobody could see, and what a release year buys (T-0165, 2026-08-16)

`ResolverWorker._best` refused a tie only between candidates whose
`platformId` differed, so a hint mapping to a **single** id — `PC` → {6},
`PS4` → {48}, `PS5` → {167}, `SWITCH2` → {508} — left every surviving row on
that id and the guard could never fire. Two *different games* at an identical
score were then decided by whichever IGDB returned first.

**How this was measured, since the method is reusable and cost almost
nothing.** One live answer per (query, platform filter) was recorded to a file
outside the repository and replayed through the **real** `ResolverWorker` under
four rule variants, so every variant sees identical rows and the only
difference is the rule. Detections came from the control capture (T-0131,
`FRESH`, nothing scanned). **278 live IGDB requests in total**, all of them
recording; every one of the sixteen variant runs after the first cost **0**.
Release years were added to 479 already-recorded game ids in **2 bulk
requests** rather than by re-recording 274 answers.

Auto-matches, by rule variant. `no tie rule` is the ambiguity test removed
entirely; `shipped` is T-0023's; `same platform` refuses any equal-scored
second candidate; `+ same year` exempts one whose IGDB release year equals the
top row's:

Auto-match counts per condition are in the control record (T-0246); the
column-to-column *differences*, which are what the variants are being judged
on, are here:

| condition | shipped vs no tie rule | same platform vs shipped | + same year vs shipped |
|---|---|---|---|
| `CONTROL-HIRES`, hints as read | fewer | fewer | **none** |
| `CONTROL-HIRES`, hints stripped | far fewer | none | **none** |
| `CONTROL-HIRES`, the そらのは `PS2` corrected | fewer | fewer | **none** |
| `CONTROL-HIRES`, every Switch-family hint forced to 508 | none | fewer | **none** |
| `CONTROL-LOWRES`, hints as read | fewer | fewer | **none** |
| T-0156's desktop titles under `PC` | none | fewer | **fewer** |

- **The collisions T-0156 filed are real and every one of them is now
  refused**:
  a 1993 strategy title against its 2016 remake, a 1993 title against its 2012
  remake, and a 1993 shooter — whose install writes a read that auto-matched
  the 2016 entry of the same name, while the 1995 re-release tied at 1.000 on
  an alternative name. The titles are real installs and are not named;
  the collision shape — one name, two releases, distinguishable only by year —
  is the finding.
- **Refusing every same-platform tie costs console rows in each of the four
  console conditions; exempting an equal release year costs none.** The rows it
  costs are the same pairs each time: one console title against its own
  Collector's Edition, both released the same day on PS5, and IGDB's two
  separate entries for a second title, both carrying one release date. Every
  row the exemption keeps is one release under two entries; every collision it
  still refuses is two releases. **That is the whole argument for the year, and
  it is why the answer is conditional rather than "widen the rule".**
- **A small fraction of the games one control run touches carry no
  `first_release_date`.** An absent year refuses, like any other unanswered
  question here.

**`_best`'s own two figures, re-measured under the new rule.** With the hints
stripped from every hi-res detection: without any tie rule more than half the
auto-matches are **on the wrong console**; with the rule, **none** are. So it
still refuses every one of them, and it now costs more correct auto-matches
than T-0002 measured. Under the model's own hints it refuses the same rows
T-0023 named — a Switch 2 title against the Switch 1 entries of the same
game — but IGDB
now returns 508 before 130 for all of them, so today it refuses as **wrong**
nearly every row T-0023 measured it refusing as **right**, and as right the
one it measured wrong: the verdict inverted. Nothing in this repository
changed between those two readings; a third party's result ordering did. That
is an argument for the rule and not against it, and it is why a bucket figure is
re-measured rather than carried forward. Both the shipped rule and the year
rule produce identical rows in every one of these conditions.

**The year the *source* carries — the other direction the filing named — is
not implementable today, and it is not merely unimplemented.** Off a
photograph there is no year to carry: **no read of either control set**
contains a four-digit year, because no spine prints one. Off a
filename there is one — T-0158's `parseGameFileName` answers
`FileNameParse.year` — and it stops at the seam: nothing builds a `Detection`
from a parse, and `Detection` has no field to carry a year in (filed as
T-0171). Folding it into the title instead is refused two gates earlier:
a three-word title with the year appended scores **0.750** and the same title
with the year in brackets **0.682**
against IGDB's name, both under `minAutoScore`, and `volumeNumbersAgree`
disagrees as well — the conjunctive shape T-0113 and T-0156 both found. And
exempting four-digit numbers from that volume key would break the case where
the number *is* the volume: an annual sports series whose consecutive editions
differ only in a four-digit year, a
distinction T-0158's own corpus turns on.

One cost this measurement does not price: a refused tie reaches review as two
rows a human cannot tell apart, because `Candidate` carries no year either
(T-0170).


## The exact join: IGDB does carry GoG ids, and 82% of them (T-0159, 2026-08-16)

**The premise, which the brief asked to verify before anything was built:
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

**394 of 480 real GoG product ids join: 82.1%.** A real library is
**unmeasured and cannot be measured here** — T-0157 and T-0158 both found no
real `goggame-*.info` available to read. The
sample is GOG's own public store catalogue instead (`catalog.gog.com/v1/catalog`,
`productType=in:game`, 6360 products over 133 pages), ten pages taken evenly
across the whole of it in trending order so the long tail is in it as heavily
as the front page:

| catalogue page | 1 | 15 | 29 | 43 | 57 | 71 | 85 | 99 | 113 | 127 |
|---|---|---|---|---|---|---|---|---|---|---|
| joined, of 48 | 41 | 40 | **17** | 44 | 45 | 40 | 47 | 41 | 45 | 34 |

Page 29 is the one outlier and page 85 the best; popularity is not what
predicts a hit, so 82% is the honest figure for a shelf of unknown taste
rather than a best case. A store catalogue is not an install list, and the two
differ in a direction that is not measurable from here: what people install
skews toward what they bought, which skews toward the front pages.

**The join is one-to-one.** 394 rows for 394 uids, **0 uids carrying a second
row and 0 resolving to a second IGDB game**. That is what entitles the resolver
to skip every gate — `minAutoScore`, `platformAgreement`, `volumeNumbersAgree`
and T-0165's tie rule all exist to make a *guess* safe, and there is no guess.

### What it is worth against the string path

The four rows below were driven through the shipped resolver twice, live, on
the identical raw title — once with the `sourceId` and once without it:

Two names, two GoG products each, four rows. The titles and the product ids are
real installs and are not published; what the rows show is the shape:

| raw title | GoG product id | join | title path |
|---|---|---|---|
| name A | product 1 | the 1995 re-release | none, 5 candidates |
| name A | product 2 | the 2016 release | none, 5 candidates |
| name B | product 1 | the 1993 release | none, 5 candidates |
| name B | product 2 | the 2016 release | none, 5 candidates |

Each `join` cell was a distinct IGDB game id, resolved from the product id
alone.

Two of the three collisions T-0165 measured, and the join does not have them:
the string path cannot tell 1993 from 2016 and correctly refuses all four,
while the product id already says which release is installed. So this is not a
cheaper route to a row the product already got — it is four rows it cannot
auto-match at all. **The third collision has no GOG row on IGDB
for either release**, so it is one of the 18% and stays exactly where T-0165
left it.

### The platform, which is the only thing the join does not answer

**A GOG `external_games` row carries no `platform`** — absent on all 394. So
the platform id for the `.xcoll` row comes from the joined game's own
`platforms`, picked by the detection's hint through `platformIds`
(`GogMetadataSource.platformHint` is `PC` → {6}, T-0156). **270 of the 394
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

One thing the join is worth that the search cannot be: **it applies no platform
filter**, so a GoG DOS-era release is *found*. T-0156 measured Mire II
answering 0 rows under `PC` → {6} and accepted that; the same game joined by id
comes back with its DOS listing and a human to pick it.

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

## The disk sources, run against real folders at last (orchestrator, 2026-08-16)

Every figure above for the GoG paths was taken without a single real
`goggame-*.info` to read: T-0157 cross-checked three files found
elsewhere, T-0158's whole GoG corpus group was synthetic, and T-0159's 82%
hit rate came from GOG's public catalogue rather than from anyone's library.
Those limits are stated honestly in each of those sections and were true when
written.

One real game and a staged folder of downloads were then made available, both
paths given explicitly. The shipped CLI was run against them. **Both
folders are on a private disk and are private: neither the paths, the
folder names, the installer names nor the titles they resolved to are
published.** What is published is every figure the run produced and the shape
of each name the parser was given, which is what the parser is measured
against.

**The installed-games folder — one installed game, `scan-installs`.** 2 entries
read (1 folder, 1 `goggame-*.info`), 1 row, 0 declined:

| field | value |
|---|---|
| read | the publisher's title, from the install's `goggame-*.info` |
| origin | `metadata` — the publisher's title, not a parse |
| source id | `gog:<gameId>`, taken from the file's `gameId` field and not its name |
| hint | `PC` |
| resolved | one IGDB game, by id |
| method | **`externalId`** — the exact join, no search string, no Levenshtein |

So T-0157's reader, T-0159's join and T-0170's `match_method` are confirmed
together on one real file. A first run with the IGDB variables absent
reported the credentials missing and left the row unresolved, which is the
designed behaviour and not a failure.

**The staged-downloads folder — three staged folders, `scan-installs`.** By the
shape of the name the parser was handed, not by the name:

| folder on disk | read | resolved |
|---|---|---|
| `Title_Words_2.1_(1100000018)_win_gog` — version, bracketed build, two suffixes | the title, cleaned | IGDB, 1.000, fuzzy |
| three words, no separators, a colon missing against IGDB's name | the three words as-is | IGDB, 0.947, fuzzy |
| a non-English default "new folder" name, one `setup_<title>_2_ultimate_2.1.0.4.exe` inside | the installer's title, lower-cased | no candidate |
| the same default name, numbered copy, one `setup.exe` inside | — | **declined**, named |

The first row is the version strip, the build number in brackets, the `win`
and `gog` suffixes all coming off one name. The second is the fuzzy path
earning its keep on a missing colon. Neither folder's contents leaked, and
neither are they described here: what is measured is that a folder holding many
files produced exactly one row.

The last two are T-0183's and T-0189's cases, and both were found this way
rather than by reasoning — the first because the generic-name list is English
while a Russian-locale Windows creates a new folder under a non-English name, the
second because
a folder that names nothing still became a row until a numbered copy was made
to prove it.

**What is still unverified, and it is the important half.** No disk-sourced
`.xcoll` has been imported into Tonkatsu Box. The photograph path has that
(T-0009); this one has resolution and export and stops there. Until
somebody runs the import, "verified end to end" belongs to the photographs
alone.

## The 7B's density ceiling, and the loop past it (T-0278, 2026-08-23)

The task was filed on a dense shelf photograph the owner supplied: the local
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
fifth of the frame is missing from an answer that parses cleanly and reports
no omission. Not one invented title at any density — the anti-invention
guarantee holds the whole way up — which makes this the decision 0012 class
rather than the T-0007 class: a quiet loss, not a wrong answer.

**It is not legibility.** At 120 spines three quarters of the titles were
rendered in small type and 108 of 120 came back correct. What the ceiling
bounds is how much of one frame the model can hold, which is the same sentence
T-0074 reached from the Switch 2 band.

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
fixed point with. T-0053 pinned it for reproducibility and that is still
right; this is the bill.

**The same loop has a second site.** On the frame the ceiling was first found
on it runs away in **`unreadable`** instead — the array is 99% of the answer
and every `reason` string in it is byte-identical to every other, as is every
`script` value. That is T-0028's phantom entry, which `detectionPromptRules`
forbids in as many words ("The entries are not copies of each other"),
running away rather than appearing two or three times.

### Two sentences, one cause — the defect that was worth fixing

Which failure the user meets is decided by whether the model closes its
document before the context fills, and nothing else:

| the loop ends by | the code | what the user was told, before T-0278 |
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
another agent's app-test-suite window; four later passes inside that same
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
   read off spines. That is T-0007's rule and decision 0012's class in one
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

## The generation cap, and the ceiling that is not the context window (T-0281, 2026-08-23)

T-0278 left the Ollama request with no `num_predict`, so the only bound behind
a `done_reason: length` was the server's context window. This section is what
choosing a number cost to establish. **Every frame is synthetic**, generated
for this task at 3060×2040 with invented titles and printed platform bands, and
`prompt_eval_count` is 4932 on all of them — the same rig as the section above,
independently rebuilt: `qwen2.5vl:7b`, `num_ctx` 32768, the shipped
`detectionPrompt` dumped out of `providers/vision.dart` rather than retyped,
`format: 'json'`, `temperature: 0`, `seed: 20260814`.

**The loop reproduced on a frame T-0278 never saw**, which is the strongest
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

Neither bound survives contention. T-0278 measured 24–105 tokens/s on this
machine depending only on what else was running, and at the low end no cap is
reachable inside 120 s. The value buys the uncontended case.

### The floor, checked rather than assumed

A synthetic 120-spine frame answered in **4690 tokens, `done_reason: stop`,
parsing, 100 items, `unreadable` empty, 97 of them real spines** — under
T-0278's 5504 at the same density, on a different frame. 8192 clears both by
half again. **4096 is rejected on this**: it stops the loop in 46 s and it also
sits under every honest answer anyone here has measured.

### The state changes the answer, and it is the cached-prefix state again

The same 176-spine frame asked a second time, with its image prefix already in
the KV cache (`prompt_eval_duration` 0.05 s against 3.5 s cold), **does not
loop**: it stops on its own at 9006 tokens with `done_reason: stop` and a
document that parses — 191 rows, 122 distinct, 114 of them real spines. This is
the third cache state of T-0106 reaching a different fixed point, not a
different frame, and the two runs diverge at character 2737 of the answer.

Two things follow, and the first is why the cap is where it is:

1. **A real scan is always the cold ask** — each photograph is sent once — so
   the runaway is the case the shipped path meets and the 9006-token answer is
   an artifact of asking four times. A cap chosen to preserve it would be
   chosen for a state the product does not run in.
2. **8192 does cut that warm answer off**, and it is worth stating plainly
   rather than discovering later: on the warm prefix the cap costs 114 real
   titles and returns nothing. Against that, T-0278 measured the same 176-spine
   density cut into two halves at identical pixel scale yielding **130 / 176** —
   more than the 114 — so the advice the decline prints beats the answer the
   decline suppresses.

The `num_predict` 8192 and `num_predict` 12288 answers on the warm prefix are
**byte-identical up to 8192 tokens**: the shorter is an exact prefix of the
longer. So the cap changes where the same greedy sequence is cut and nothing
else, which is what makes the comparison above a comparison.

### One thing past the ladder's end: the anti-invention guarantee has a density

T-0278 records not one invented title at any density, and its ladder's densest
*answering* rung was 120 spines. At 176, on the warm prefix that answers, **8 of
the 122 distinct rows are titles that are not on the frame** — and they are not
misreads. Every one of them pairs a first word taken from elsewhere in the
frame with the last row's second word, continuing the series past where it
stops.

**Read this narrowly.** These synthetic titles are a regular two-word
combinatorial series, which is an invitation to continue a pattern that real
spine titles do not extend. It is evidence that a frame past the ceiling can
fabricate rows that parse and look like reads, not a measurement of the rate on
anything real. Filed as its own task rather than folded in here.
