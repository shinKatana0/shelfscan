/// Providers are the only classes that know how to talk to a specific vision
/// backend. Anthropic and Ollama have one each; every endpoint speaking the
/// OpenAI `/chat/completions` shape shares `openai_compatible_vision.dart`.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../http_timeout.dart';
import '../models.dart';
import '../unreachable.dart';
import '../workers/base.dart';

/// The reading rules every provider must put in front of its model.
///
/// Single source of truth on purpose: these rules used to be copy-pasted
/// into each provider, so a fix landed in one model's prompt and silently
/// missed the other (T-0007). Providers compose their prompt from this
/// const plus [detectionJsonSchema] and add nothing beyond provider-specific
/// framing.
///
/// The anti-invention rules are not cosmetic wording. A confidently wrong
/// item survives human review far more easily than an obviously missing
/// one, which makes invention the most expensive failure mode this pipeline
/// has (decision 0007: model confidence is not trustworthy).
///
/// **Every count of the control photographs left this comment under T-0246**
/// (the audit of 2026-08-18). A detection total, a per-photo split, a stack
/// size or a per-platform tally is a measurement of a private collection, so
/// the figures live in `doc/control-set.md` beside the photographs and only
/// the direction of each result is here. Counts of *runs*, of prompt variants
/// and of seeds are not disclosures and are kept, because they are what says
/// how much weight a result carries. What this record exists to do is unchanged
/// and is the reason it is long: nothing below should be retried blind.
///
/// The `platform_hint` rule (T-0021) is the same principle applied to the
/// second field, and it is not redundant with the title rules. Listing
/// `SWITCH` in [detectionJsonSchema]'s menu alone took one photograph from
/// no hint at all to a hint on every spine, but one of them was `N64` for
/// HARBOUR STARBURST -- a red Switch 2 case whose branding says nothing of the
/// sort. The model was answering from what it knows about the game, which the
/// title rules forbid for titles and said nothing about for platforms. With
/// "READ, not recalled" added, two consecutive runs answered every spine of
/// that photograph from the branding, with no N64. Console branding is printed
/// text naming the platform, so reading it is not the logo-inference T-0007
/// bans;
/// that distinction has to be stated or the two rules read as contradicting
/// each other.
///
/// Side effect from the same runs, worth knowing before reverting any of
/// this: `media_type` on that photograph went from `unknown` on every row to
/// `cartridge` on every row, which is correct for Switch cases.
///
/// T-0026 carried that rule to re-releases, measured on three 4000x3000
/// photos whose readable spines were counted by hand off the images. It
/// started from two defects: almost every item on one photograph answered
/// the bare wordmark `NINTENDO`, which `platformIds` does not key, and a
/// large minority of another answered `PS2` -- every one of them a
/// PlayStation-2-era classic in a red Switch case. What moved the results:
///   - "Name the console, not the manufacturer" took that stack from almost
///     none correct to every row correct. Constraining the model to the token
///     the map already holds was chosen over adding a `NINTENDO` key, because
///     that word is equally the branding of a NES, N64 or Wii case: unmapped
///     only drops the platform filter, while mapping it to Switch would filter
///     an NES search down to nothing.
///   - Naming WHERE the branding sits -- console icon at one end of the
///     spine, publisher wordmark at the other -- is what reached the
///     re-releases: the wrong hints roughly halved. It also recovered
///     spines no earlier run had read, with zero invented.
/// Four edits that read as obvious improvements and measured flat or worse,
/// all reverted; do not re-add one without a run:
///   - "name to yourself the printed mark you are reading it off": no change.
///   - "not the one the game first appeared on" in the schema line: the same
///     items answered `PS4` instead of `PS2`. Changing which console gets
///     recalled is not the same as getting one read, and `PS4` is the harder
///     of the two for a human reviewer to catch.
///   - splitting the re-release clause into its own bullet: slightly worse.
///   - "a Japanese-language title changes none of this": back to the
///     pre-T-0026 error rate, undoing the gain above. The bullet is at its
///     dilution limit.
/// Residual, and the reason this is a partial fix: the そらのは spines still
/// answer `PS2`. Every other hint is correct, and the PlayStation control held
/// at every row correct through every variant above, its PS4 titles included.
///
/// That same T-0026 edit cost T-0007's zero-invention guarantee at 1200x900,
/// where the Japanese Switch 2 spines are illegible rather than merely
/// untranslatable (T-0034). Bisected on the two low-res photos, four runs per
/// prompt state, runs containing an invented title:
///   a8e6eca^ T-0007  0/4      a8e6eca  T-0011  0/4
///   9284c6f  T-0021  0/4      80c7038  T-0026  4/4
///   e729f5f  T-0028  4/4
/// From 80c7038 on, the model names those spines (`MUSHROOMS AND THE
/// GREAT WOODEN SWORD`, `DOLCE & GABBANA SHIELD`, at T-0028 `MUSHROOMS &
/// COOKING ADVENTURE` and `DOLCESTORM SHIELD`) and drops the real `Mythéon
/// Shield` beneath them, so the stack gains a row it should not have.
///
/// The cause is adjacency, not length: T-0026 put 14 lines of branding prose
/// immediately after the Japanese-transcription rule, which is the only rule
/// governing those spines. Moving that bullet down to sit between
/// `confidence` and `unreadable` -- no word of any bullet changed -- restores
/// 0/4 while leaving every hi-res figure where T-0026 left it. The bullet
/// ORDER is load-bearing; re-sorting this list for tidiness is a measured
/// change, not a cosmetic one.
///
/// A prompt change is measured on BOTH photo sets from here on, because
/// neither exercises what the other does -- the hi-res photos read those
/// spines correctly or not at all, so they cannot fail this way, and four
/// consecutive prompt edits were signed off on them alone.
///   low-res, 2 photos, before: two invented rows, one real row displaced
///   low-res, 2 photos, after:  0 invented, back to the recorded baseline
///   hi-res, 3 photos, before and after: unmoved on every figure -- count,
///     per-photo split, 0 invented, hints
/// The low-res result is T-0007's recorded baseline reproduced exactly; the
/// drop against the run before it is the two invented rows leaving, and
/// `Mythéon Shadow` returning pays for one of them.
///
/// Three rewrites measured flat or worse and were reverted; do not retry one
/// without a run:
///   - platform bullet compressed to 9 lines AND the list split into headed
///     steps (which items to list / their fields / what went unread): still
///     4/4 invented. Position beats wording here.
///   - platform bullet moved to the very end: 0/4 invented, but the hi-res
///     re-releases fell back to `PS2` and the correct-hint figure fell --
///     reopening the defect T-0026 exists to close.
///   - platform bullet moved one place later, after `confidence`: 1/4
///     invented, a rarer failure rather than a fix.
///
/// T-0033 re-measured that same move against the OTHER field it turns out to
/// govern, and found it already fixed. On one 1200x900 photograph -- one
/// photo, one set of pixels, the same 2990 characters in the two orders --
/// `platform_hint` answers (6 runs each):
///   T-0028 order: almost every row `NINTENDO`, a couple `SWITCH`, and one
///                 extra detection
///   this order:   every row `SWITCH`, no `NINTENDO`
/// So a low-resolution `NINTENDO` is not the icon becoming illegible: the
/// same pixels answer either way depending on where this bullet sits. Asked
/// on that photo to describe the two ENDS of each spine and name no title,
/// the model reports a logo at the left end of every one -- "likely
/// Nintendo", perceived but not resolved into the Switch pictogram -- and
/// transcribes the right end as `NINTENDO` on all but a few, which say
/// `SQUARE ENIX`. Those few are exactly the ones that answer `SWITCH` under
/// the order that invents. The `Nintendo` pill is the transcribable mark and
/// wins whenever this bullet is placed where the model reaches for it.
/// Over all five photos through `dedupeDetections` the T-0028 order leaves
/// substantially more review rows than this one does. Two different present
/// hints stay two rows (T-0018-02), so every `NINTENDO` read was refused a
/// merge; here nearly all of the low-res reads merge into their hi-res row.
/// The ones that do not are truncations rather than hints: `MOONLIGHT`
/// (ambiguous among three Moonlight titles, the case [isTruncatedRead]
/// accepts by design) and
/// `PILGRIM VII REMAKE INTERBLOOM` (leading word behind an object in the
/// photo, T-0054).
/// Hi-res control re-measured at this order and unmoved, twice: every figure
/// as recorded, 0 invented.
///
/// EVERYTHING ABOVE THIS LINE was measured before the request said what
/// sampling it wanted (T-0053), so each of those results is a single draw or a
/// handful of them. They are near-greedy draws rather than wild ones --
/// qwen2.5vl:7b's own Modelfile carries `temperature 0.0001` and that, not
/// anything this project did, is why they held still -- and the two re-run
/// under the pinned options came back exactly: T-0034's low-res figures and
/// the hi-res ones above. Treat the rest as evidence, not as constants.
///
/// Re-established WITH the sampling pinned (T-0053, 2026-08-14, qwen2.5vl:7b
/// / Ollama 0.32.9 / RTX 5090 Laptop), every figure counted off the
/// photographs by eye rather than against another run's JSON:
///   low-res, 2 photos, 8 runs: the recorded counts exactly, 0 invented, every
///     detection hinted and every hint correct. Legible Latin spines at the
///     dim bottom edge of one photograph are dropped, and
///     MOONLIGHT 3 comes back truncated to `MOONLIGHT`; the Japanese spines
///     omitted as they should be, and every readable spine of the other
///     photograph read.
///   hi-res, 3 photos, 8 runs: the recorded counts exactly, 0 invented, every
///     detection hinted, and one photograph correct on every row. Every
///     Latin spine on the three photographs; the wrong hints are all T-0029's
///     そらのは re-releases.
/// The 8 runs per set are 4 repeats at the default seed plus seeds 1, 12345
/// and 99, all byte-identical to each other AND to the 4 pre-change runs that
/// sent no options at all. So temperature 0 bought repeatability here without
/// moving quality, and the seed is inert while it is 0. All 8 were repeat asks
/// on one loaded server, which T-0086 measured to be the condition the BYTES
/// hold under; the counts hold without it.
///
/// What the pinning is worth shows at temperature 0.8, Ollama's documented
/// default, one run per seed on the same pixels and the same prompt:
///   hi-res detections: five different totals across five seeds, all but one
///     below the pinned figure
///   low-res detections: four different totals across five seeds, on both
///     sides of the pinned figure
///   invented titles on 3 of the 5 seeds at each resolution -- そらのは
///     spines named as titles of a well-known JP series, Mythéon spines
///     named as games that are not on the shelf, a Japanese-script spine
///     given a title
///   `platform_hint` answered with this file's schema example verbatim on
///     every row of one low-res photo and every row of one hi-res photo
///     (T-0014, T-0028 -- see [detectionJsonSchema])
/// The anti-invention rules are therefore a property of near-greedy decoding
/// as much as of their wording: a prompt measured at another temperature is a
/// measurement of a different system.
///
/// Reproducible is not byte-exact, and the exception is measured rather than
/// assumed: the model has TWO answers for these photos, not a distribution of
/// them. Each is reproducible on its own; they differ on one photo only -- one
/// hi-res photograph, a third of its rows, in typography alone (`Frost
/// Wake™` for `Frost Wake`, `IRON HERALD™ SÜNFALL` for `IRON HERALD SUNFALL`).
/// Item counts, item identity and every platform hint were unmoved, and
/// [titleKey] folds ™ and the diacritic away, so the review rows are the same
/// rows. The other two hi-res photos never differed, and neither did the
/// low-res pair over 15 runs across three loads.
///
/// Which of the two comes back was recorded here as the cold/warm boundary --
/// "the first scan after Ollama loads the model" -- and T-0086 measured that
/// wrong on 2026-08-15. It is the first ask for a given PHOTO by a given
/// SERVER PROCESS: a server that had been loaded and busy on two other photos,
/// asked for this one for the first time, answered with the first-ask
/// typography exactly, and answered the repeat with the other one exactly. An
/// unload correlates only because it drops the prompt cache with the model.
/// See [OllamaVisionProvider] for the run counts and the cache figures.
///
/// The `unreadable` bullet stops the model padding that array (T-0028; the
/// copied example it padded with is documented on [detectionJsonSchema]).
/// What it does not do is make the array a count. Against a hand-counted
/// truth taken off the three photos, with the example removed qwen2.5vl:7b
/// answers zero on all three, and on a repeat run names a couple of spines it
/// had already read and listed. Across every T-0028 variant it never once
/// reported a spine it had actually skipped: on the first photo it lists
/// exactly the spines it read and never mentions the Japanese Switch 2
/// cases beside them. So the local 7B has no perception to report here, and
/// the honest zero it now gives is a fix to the cost (T-0011 escalated every
/// photo of every run on a fabricated trigger) and to the count shown to the
/// human (T-0012), not a working signal. What measured flat at zero and is not
/// worth re-trying blind: asking it to count the visible spines and subtract
/// the ones it listed; naming the concrete cases (too small, Japanese,
/// art-only, logo-only) that belong here.
///
/// **That zero is conditional on the prompt cache and not on any wording here
/// (T-0106, 2026-08-15).** Asked for `shelf-2.jpg` on a server that
/// has already answered that photo under a DIFFERENT prompt text -- which is
/// what the second pass of any prompt A/B is -- these rules answer three
/// entries where a first ask and a repeat both answer none: one `unknown` and
/// two byte-identical `japanese`, which the bullet above forbids in as many
/// words. Three on 18 of 34 such asks, none on the other 16, never another
/// number and never on another photo; item counts, titles and hints unmoved on
/// both control sets. No wording is at fault and none was found that helps, so
/// a nonzero `unreadable` measured that way is evidence about the cache and
/// not about this text. `ollama stop` before the run is what avoids it;
/// doc/measurements.md, "A third cache state", carries the run counts and the
/// recipe.
///
/// **T-0074 asked for the Nintendo Switch 2 band and did not get it. Nothing
/// below is shipped; the prompt this comment sits on is unchanged.** A Nintendo
/// Switch 2 case's band prints the console icon with a `2` beside it, and a
/// hint naming that 2 is worth a measurable number
/// of extra auto-matches -- re-confirmed live under this prompt, see
/// [platformIds]. Thirteen wordings, one hi-res run each at temperature 0 and
/// seed 20260814, every result taken off the photographs by eye. Baseline for
/// the whole table: the recorded hi-res figures, 0 invented, every detection
/// hinted with the そらのは cases wrong.
///
/// The columns are `band` -- was the Switch 2 band read on the cases that
/// carry one, none / some / all -- and `cost`, against that baseline.
///
///    #  what was tried                          band   cost
///    1  replaced "Read that mark."               none   one detection lost,
///                                                       hints worse
///    2  inside the icon list                     none   one detection lost
///    3  appended to "Read that mark"             none   one detection lost,
///                                                       hints worse
///    4  own line at the END of the bullet        none   one detection lost
///    5  `SWITCH2` in the schema menu, ONLY       some   false SWITCH2 on
///                                                       Switch 1 spines
///    6  menu + "check each spine separately"     all    false SWITCH2 on
///                                                       every Nintendo spine
///    7  menu + "SWITCH2 is the exception"        some   schema line copied
///                                                       into rows
///    8  that rule, menu as it ships              none   schema line copied
///                                                       into rows
///    9  rule only, one token, exception framing  none   one detection lost
///   10  menu + that rule shortened               all    false SWITCH2 on
///                                                       every Nintendo spine
///   11  "a digit goes on the end of the hint"    none   one detection lost,
///                                                       hints worse
///   12  "read the characters inside that band"   none   one detection lost,
///                                                       hints worse
///   13  "any digit printed in it included", at
///       the HEAD of the bullet                   none   one detection lost
///
/// Two mechanisms, and they are exclusive. With `SWITCH2` absent from
/// [detectionJsonSchema]'s menu no wording gets the band read at all (1-4, 9,
/// 11-13): prose naming the console ("a Nintendo Switch 2") is inert. With it
/// present the model answers it wholesale (5, 6, 10) -- every Nintendo spine
/// on 6 and 10, and on 5 the answer is chosen per PHOTO rather than per row,
/// photo 1 answering `SWITCH` on every row while photo 2 answers `SWITCH2` on
/// most -- each token carried across its whole frame, including the rows it
/// does not fit. So the menu token decides the value and no restraint wording
/// moved it; "the exception and never the default" (10) restrained nothing.
///
/// A bare uppercase token in the RULES re-opens T-0014/T-0028 at temperature
/// 0, which wording alone was thought to hold shut there. On 7 photo 1
/// answered the literal string `SWITCH2 | SWITCH` on every row; on 8 photo 2
/// answered `SWITCH2 | N64 -- omit this field entirely if the platform is
/// unclear` on most rows and the same tail after `PS2` on the そらのは. The
/// model builds a pipe menu out of whatever tokens the rules put near each
/// other, whether or not the schema also carries them.
///
/// 7 is the only variant that ever discriminated: photo 2 answered `SWITCH2`
/// for COLD ARCHIVE requiem and Ashes of the Kingdom Nintendo Switch 2
/// Edition and `SWITCH` for the rest, no false positive. The same prompt
/// destroyed photo 1. Nothing was found that gets one without the other.
///
/// Low-res, 1200x900, 4 runs each:
///   5 (menu only):     the recorded counts, 0 invented, all 4 runs -- and
///     every Switch spine answers `SWITCH`, not `SWITCH2`. The contagion above
///     is resolution-dependent, so hi-res alone would not have found this
///     either.
///   10 (menu + rule):  2 INVENTED on 3 of the 4 runs --
///     `MUSHROOM-CHOKUKEI NO TAKA` for a Japanese-script spine and
///     `Duskthorn Shield` displacing the real `Mythéon Shadow`, so the
///     photograph gains a row. That is T-0026's and T-0034's failure, in the
///     same
///     bullet's neighbourhood, for the third time, against T-0007's Critical
///     guarantee.
///
/// Cost that every rules-bullet edit paid regardless of wording: Starweave
/// Chronicles 3 on photo 1 was lost, one detection off the hi-res total. Only
/// 5, the schema-only variant, held the total.
///
/// Ask the model what it sees, again (decision 0002). Throwaway prompts on photo
/// 1, same model and sampling, no title asked for: "describe the left end of
/// every spine" degenerates into one line of "icon only" per spine; asked
/// which digit is printed inside the red band at the left end of the spines
/// at the top of the stack, character by character, it answers `2` on each of
/// them, correct; "compare the top spine's mark with Mythéon Shadow's"
/// answers "The console marks are identical". So the 2 is perceived and
/// transcribable, and what the 7B cannot do is carry that discrimination
/// across a whole photo of spines while also reading their titles. That is a
/// capacity limit rather than a wording one, which is why the table above
/// stops at 13.
const detectionPromptRules = '''
You identify video games on a photo of a collector's shelf.
The photo shows game cartridges and/or disc cases, possibly spines only.
List every game whose title you can actually READ.

Reading rules -- follow them exactly:
- If you cannot read a spine or cover, OMIT that item entirely. Leave it
  out of "items". Do NOT emit a guessed entry. A missing item is correct
  behaviour here; an invented one is a serious error.
- NEVER infer a title from box art, colour, shape, logo, artwork style or
  from what is on the shelf next to it. Only characters you can actually
  read on the item count as evidence.
- Do not guess full titles from partial text -- put the partial text in
  "raw_title" as read and lower the confidence instead.
- "platform_hint" is READ, not recalled: take it from the console branding
  printed on the item -- the logo or coloured band naming the console. Never
  derive it from the title or from which console you know the game to be on.
  That branding sits at one end of the spine, and every case for a given
  console carries it whoever published the game: a Nintendo Switch spine
  prints a small white console icon -- a screen with a controller down each
  side -- and a PlayStation spine prints a PS4/PS5 band. Read that mark. A
  publisher wordmark at the opposite end (SQUARE ENIX, SEGA, CAPCOM, ATLUS)
  is not console branding -- when that is all you recognise, do not fall back
  on the title.
  This holds for re-releases of older games: a classic reprinted for a newer
  console carries the NEWER console's branding, and the platform a game
  originally shipped on is never evidence about the box in this photo. Report
  the console this copy is FOR, not the console the game is famous on.
  Name the console, not the manufacturer: a maker or publisher wordmark such
  as "Nintendo" or "Sony" on its own is not a platform -- read the console
  name printed with it.
  If no console branding is legible, omit the field.
- "confidence" expresses how clearly you could READ the characters, not
  how plausible or well-known the game is. An unreadable spine is not a
  high-confidence guess.
- Japanese titles: transcribe the characters as printed. Never translate
  them, and never romanize a title from memory or from recognition of the
  game -- if you cannot read the characters themselves, omit the item.
- Every item you leave out because you could not read it: add one entry to
  "unreadable" saying which script the characters looked like and what
  stopped you. These belong here: a spine whose characters are too small or
  too blurred to transcribe, a Japanese title whose characters you cannot
  make out, and a case showing only artwork or a logo and no readable
  title. The entries are not copies of each other. If every spine you can
  see is already in "items", answer "unreadable": [] -- an empty list is
  the normal result, not a failure. Report it, do not title it -- there is
  no title field there, and it never counts as an item.''';

/// Shared for the same reason [detectionPromptRules] is: one copy per
/// provider drifts per provider.
///
/// `platform_hint` names an ACTION for the unclear case, not a value
/// (T-0014). It used to end with `... | null if unclear`, and qwen2.5vl:7b
/// did the literal thing: it answered with the four-character string
/// "null" on most of a low-res control run, which travelled all the way to
/// the review UI and the CSV export as a platform name.
///
/// Two things were measured on the real photos before settling on this
/// wording, and both are easy to undo by accident:
///
///   - Removing the unclear branch and demonstrating JSON null in a second
///     example item instead made the model INVENT: with no escape from the
///     `SNES | PS1 | N64 | ...` menu it answered "N64" for those same
///     items. A wrong platform survives human review far more easily than a
///     missing one, so the menu must always carry an explicit way out.
///   - With this wording the model stops writing the word and answers `""`
///     instead. That is honest absence, and [Detection.fromJson] maps it to
///     null -- the parse-side normalization is what makes the result
///     correct, this const only stops provoking the bad value.
///
/// The menu is a vocabulary, not an enum: a console it does not name is a
/// console the model will not answer with. It listed `SNES | PS1 | N64 | ...`
/// until T-0021, and every Switch detection came back with no hint at all
/// while every PlayStation one was correct -- the ellipsis did not stand in
/// for the missing value. Adding `SWITCH` is what recovered
/// them. The model still answers the branding it reads (`NINTENDO SWITCH`),
/// not the menu token, which is why `platformIds` keys both spellings.
///
/// That last sentence no longer describes qwen2.5vl:7b at temperature 0: it
/// answers the menu token verbatim, `SWITCH` wherever it reads that branding
/// in the hi-res control. A vocabulary this model copies exactly is also one it
/// cannot be given a second entry of. **Do not add `SWITCH2` here** -- T-0074
/// measured that edit alone and with four rules meant to restrain it, and the
/// model then answers `SWITCH2` for whole photos off Switch 1 bands, worse
/// with a restraining rule beside it than without one. The full table and the
/// low-res invention it costs are on [detectionPromptRules].
///
/// `unreadable` (T-0011) is the counterpart of the omit rule: T-0007 made an
/// unread spine disappear silently, which is correct for `items` and blind
/// for everything downstream. Its entries carry no title field, so they can
/// be counted for the human without giving the model a second place to guess
/// in. [SpineScript.parse] maps anything unrecognized to unknown.
///
/// Neither value here may read as a fillable answer, and that is the same
/// lesson as `platform_hint` above, measured a third time (T-0028). This
/// block used to show `"script": "japanese | latin | unknown"` with
/// `"reason": "why you could not read it, e.g. 'characters too small'"`, and
/// across eight T-0026 runs plus one re-measured baseline here the model
/// answered with exactly that entry, three times per photo, on all three
/// photos -- including the one that carries no Japanese spine at all. It was
/// the example being copied, not a count:
///   - deleting only the `e.g.` value changed every reason string on the
///     next run and dropped one of the phantom entries on one photo;
///   - naming the script as a description rather than a bare menu broke the
///     constant `japanese` block: scripts and reasons then differed within
///     one photo.
/// Two edits measured worse and were reverted; do not re-add one without a
/// run:
///   - "a spine you listed in items is never also in unreadable": the
///     phantom entries stayed and one real detection was lost.
///   - asking the reason to say WHERE the spine sits: that detection lost
///     again, and the repeated-reason block came back.
/// What this does NOT buy is a true count -- see [detectionPromptRules].
///
/// `notes` earns nothing and is kept anyway, and both halves of that were
/// measured (T-0093, 2026-08-15, temperature 0, both control sets).
///
/// **The model never uses it.** Asked for it on every row, qwen2.5vl:7b
/// answers the **empty string on every row of both control sets**.
/// Not a parse artifact: read off the wire, before [Detection.fromJson] folds
/// `""` to null. So the line costs prompt tokens on every call plus a
/// `"notes": ""` per row of output, and carries content on none.
///
/// **Deleting the line is worse.** With it gone every recorded count holds on
/// both control sets -- detections, per-photo split, hints and the platform
/// split, all folding to the same [titleKey] row set as the run before the
/// edit -- but `shelf-2.jpg` starts reporting **2 unreadable
/// spines where the shipped schema reports 0**, deterministically: five cold
/// loads each, alternating, 2/2/2/2/2 against 0/0/0/0/0. They are the T-0028
/// phantom: every readable spine of that photo is in `items` including every
/// Japanese one, one entry claims `script: japanese` regardless, and on
/// a cold load the two entries carry byte-identical reason strings, which
/// [detectionPromptRules] explicitly forbids. `unreadable` is on the control
/// record's must-not-differ list (decision 0004); it differed, so the edit was
/// reverted. One line's presence in the `items` object governs the
/// `unreadable` array -- the same adjacency T-0026/T-0034 measured and the
/// second time one bullet has moved an unrelated-looking field.
///
/// **The cold loads are what make that pair comparable (T-0106).** They put
/// every ask above in the same cache state -- a first ask. Asked instead
/// straight after the same photo under another prompt text, the SHIPPED schema
/// answers phantom entries of its own on that photo, so an `unreadable` count
/// taken without that discipline measures the cache and not the schema.
///
/// [Detection.notes] therefore stays a live channel rather than dead weight:
/// a human writes one on a manual add or a hand-edited document, and since
/// T-0093 the review row shows it.
///
/// Every result above predates T-0053's pinned sampling and is a single draw
/// from a near-greedy model. The copy-the-example hazard itself is not
/// historical: at temperature 0.8 the `platform_hint` line below comes back
/// verbatim AS the value, on every row of one low-res photo and every row of
/// one hi-res photo. Wording fixed it at 0.0001 (T-0014) and wording alone
/// does not hold it at 0.8 -- which is the argument for stating the sampling
/// on the request rather than inheriting whatever the model shipped with.
const detectionJsonSchema = '''
{
  "items": [
    {
      "raw_title": "text exactly as readable on the spine/cover",
      "platform_hint": "SNES | PS1 | N64 | SWITCH | ... -- omit this field entirely if the platform is unclear",
      "media_type": "cartridge | disc | unknown",
      "confidence": 0.0,
      "notes": "optional remarks, e.g. 'label worn, partially occluded'"
    }
  ],
  "unreadable": [
    {
      "script": "what the characters LOOKED like: japanese, latin, or unknown",
      "reason": "what stopped you reading this particular spine"
    }
  ]
}''';

/// Providers use this as-is, so that no provider carries instruction text of
/// its own.
const detectionPrompt = '''
$detectionPromptRules

Respond with STRICT JSON only, no prose, matching:
$detectionJsonSchema''';

/// Deliberately not a file path: on Android photos may come straight from
/// the camera/gallery picker without a stable filesystem path.
class PhotoInput {
  PhotoInput({required this.name, required this.bytes, this.mimeType});
  final String name;
  final Uint8List bytes;
  final String? mimeType;
}

/// The second list is the whole reason this is not a bare `List<Detection>`:
/// "0 items" and "0 items, plus unread Japanese spines" are very different
/// answers to show a human (T-0011).
class PhotoAnalysis {
  const PhotoAnalysis({this.items = const [], this.unreadable = const []});

  final List<Detection> items;

  /// What the model SAID it could not read -- not what it failed to read.
  ///
  /// Decorative for the default primary: since T-0028 `qwen2.5vl:7b` answers
  /// `[]` on every photo, including photos with hand-counted unread spines on
  /// them, and across seven prompt variants it never once named a spine it had
  /// actually skipped. The only entry it can still put here is
  /// [UnreadSpineReport.titleless], derived from a row it really did emit rather
  /// than from anything it reported. So treat a zero as "nobody counted", never
  /// as "nothing was missed"; it drove the escalation until T-0032 and drives
  /// nothing now.
  ///
  /// Not a property of local models as such, which is why the field stays:
  /// `gemma3:12b` on the same three photos answered entries of its own --
  /// japanese, latin "partially occluded", unknown "only artwork visible" --
  /// and every one of them holds up against the photographs, including a spine
  /// that carries no text at all. It is the model that cannot report here, not
  /// the channel.
  final List<UnreadSpineReport> unreadable;
}

abstract class VisionProvider {
  Future<PhotoAnalysis> analyze(PhotoInput photo);
}

/// The one entry point from a model's raw answer to a [PhotoAnalysis].
///
/// Providers hand their response text here and keep no parsing of their own,
/// for the same reason [detectionPromptRules] is shared: what lives per
/// provider drifts per provider. Ollama asks for `format: json` and Anthropic
/// cannot, so fences arrive from one and not the other -- that is a property
/// of the transport, not a licence for the two to disagree about a payload
/// (T-0013).
PhotoAnalysis parsePhotoAnalysisText(String text, String photoName) =>
    parsePhotoAnalysis(
        _shaped<Map<String, dynamic>>(
            jsonDecode(_stripCodeFence(_stripThinkingBlock(text))),
            _answerPath,
            'an object with an "items" list'),
        photoName);

/// [parsePhotoAnalysisText], with an answer this parse cannot use reported as
/// the model's failure instead of the decoder's (T-0164, T-0167).
///
/// The wrapper is here rather than inside [parsePhotoAnalysisText] because the
/// sentence names the service and the model, and this is the innermost place
/// that knows them -- the shared parse deliberately knows neither. It is the
/// same division T-0111 and T-0142 use one line above each call: the provider
/// supplies its own name, the vocabulary is written once.
///
/// Two failures, not one (T-0167). A text that never reached the decoder is
/// [visionNotJsonFailure]; a document that decoded and is not this one is
/// [visionWrongShapeFailure], which carries the path the parse stopped at. The
/// second catch is a [ReviewFormatException] raised by an explicit check, never
/// a cast error caught by type -- see [parsePhotoAnalysis].
PhotoAnalysis parsePhotoAnalysisAnswer(
  String text,
  String photoName, {
  required String service,
  required String model,
  bool hasKey = true,
}) {
  try {
    return parsePhotoAnalysisText(text, photoName);
  } on ReviewFormatException catch (e) {
    throw visionWrongShapeFailure(
        service: service,
        model: model,
        problem: '$e',
        answer: text,
        hasKey: hasKey);
  } on FormatException {
    throw visionNotJsonFailure(
        service: service, model: model, answer: text, hasKey: hasKey);
  }
}

/// A reasoning model's thinking, inline in the string the answer is in.
///
/// Measured 2026-08-15 against Groq on the one vision-capable model that
/// account is offered, `qwen/qwen3.6-27b`: asked for JSON only, its
/// `message.content` begins `\n<think>\nThe user wants me to identify game
/// titles...`, and there is no separate `reasoning` field to read instead.
///
/// **A rule about the payload rather than a list of markers.** An answer this
/// parser can use begins `{`, so a leading well-formed element is never part of
/// one and goes with its content, whatever it is called -- `<thinking>` and
/// `<reasoning>` cost nothing extra to cover. A marker that is not an element
/// at all (Kimi's `◁think▷`, the harmony `<|channel|>` headers) is NOT covered
/// and still fails at [jsonDecode], as it does today.
///
/// One block, and only when something is left after it: an answer wrapped
/// whole in an element (`<answer>{...}</answer>`) is thereby left to fail with
/// the message it fails with today rather than as an empty string. So this can
/// only ever turn a failure into a parse, never one failure into another.
///
/// The unclosed case -- thinking that ran into the output cap -- does not match
/// here and does not have to: every provider reads its own stop field before it
/// parses, so that answer is already the cap's sentence (T-0111).
final _thinkingBlock =
    RegExp(r'^<([A-Za-z][\w.:-]*)(?:\s[^>]*)?>[\s\S]*?</\1\s*>');

String _stripThinkingBlock(String text) {
  final trimmed = text.trim();
  final match = _thinkingBlock.firstMatch(trimmed);
  if (match == null) return trimmed;
  final rest = trimmed.substring(match.end).trim();
  return rest.isEmpty ? trimmed : rest;
}

/// Anchored to both ends on purpose: the global `replaceAll('```', '')` this
/// replaces edited every backtick out of the payload, so a title that
/// legitimately contains one came back corrupted instead of intact (T-0013).
final _codeFence = RegExp(r'^```[A-Za-z0-9_+-]*\r?\n?([\s\S]*?)\r?\n?```$');

String _stripCodeFence(String text) {
  final trimmed = text.trim();
  return (_codeFence.firstMatch(trimmed)?.group(1) ?? trimmed).trim();
}

/// What the document itself is called when the path has nowhere else to point.
///
/// A word rather than `ReviewFormatException`'s empty-path convention: that one
/// is read with a file open, where "is a list" needs no subject, and this one is
/// read inside a sentence about a model's reply, where it does.
const _answerPath = 'the answer';

/// The JSON kind of [value], in the words [ReviewFormatException] uses.
///
/// A second copy of `models.dart`'s private `_foundType`, deliberately: sharing
/// it means editing that file, which T-0166 is queued in.
String _foundJson(Object? value) => switch (value) {
      null => 'missing',
      String() => 'a string',
      num() => 'a number',
      bool() => 'true/false',
      List() => 'a list',
      _ => 'an object',
    };

/// [value] as [T], or a [ReviewFormatException] naming [path] and [expected].
///
/// The same contract as `models.dart`'s `_shape`, so a shape failure reads the
/// same whether this parse found it or [Detection.fromJson] did one level in.
T _shaped<T>(Object? value, String path, String expected) => value is T
    ? value
    : throw ReviewFormatException(
        path, 'is ${_foundJson(value)}; it must be $expected');

/// An absent list is an empty one; a list that is something else is not.
List<dynamic> _shapedList(Object? value, String path, String expected) =>
    value == null ? const [] : _shaped<List<dynamic>>(value, path, expected);

/// Both halves are optional -- a model that answers `{}` reported nothing,
/// which is a valid answer and never an error. So is `{"items":[]}`: a
/// photograph with nothing recognisable on it (T-0028 measured the local model
/// answering exactly that), which is why the check is on the shape of the list
/// and never on how full it is.
///
/// An item the model listed without a title is not one: it crosses to
/// `unreadable` here (`Detection.hasTitle`, `UnreadSpineReport.titleless`).
///
/// **Every step is checked, and nothing is coerced** (T-0167). `{"items":
/// ["Vex"]}` is the most plausible wrong shape a model produces and the most
/// tempting to repair -- the string is right there, and reading it as a
/// `raw_title` would turn a broken answer into rows the owner cannot tell from
/// read ones. That is T-0007's rule, so the answer is declined whole: a
/// document whose shape is not recognised carries no evidence about which of
/// its rows are good, and half of it accepted looks exactly like all of it.
///
/// The path travels into both factories, so a bad field one level in reads
/// `items[3].raw_title` rather than the bare `raw_title` it reached the user
/// as before this (T-0050's check, escaping through a parse that named
/// nothing).
PhotoAnalysis parsePhotoAnalysis(Map<String, dynamic> data, String photoName) {
  final items = <Detection>[];
  final unreadable = [
    // Deliberately not the review file's wording for the same two levels
    // (T-0154, "a list of unread-spine reports"): this one names a model
    // answer, which the reader has not seen and cannot edit, so it says what
    // the entry is rather than what the document calls it.
    for (final (index, spine) in _shapedList(data['unreadable'], 'unreadable',
            'a list of what the model could not read')
        .indexed)
      UnreadSpineReport.fromJson({
        ..._shaped<Map<String, dynamic>>(spine, 'unreadable[$index]',
            'an object reporting something the model could not read'),
        'source_photo': photoName,
      }, path: 'unreadable[$index]'),
  ];
  for (final (index, item) in _shapedList(
          data['items'], 'items', 'a list of the items the model read')
      .indexed) {
    final path = 'items[$index]';
    final json = <String, dynamic>{
      ..._shaped<Map<String, dynamic>>(
          item, path, 'an object with a "raw_title"'),
      'source_photo': photoName,
    };
    if (Detection.hasTitle(json)) {
      items.add(Detection.fromJson(json, path: path));
    } else {
      unreadable.add(UnreadSpineReport.titleless(sourcePhoto: photoName));
    }
  }
  return PhotoAnalysis(items: items, unreadable: unreadable);
}

// --------------------------------------------------------------------- //

/// A failure that answers, for itself, whether what its sentence blames is
/// something the user set (T-0169).
///
/// The one caller is the app's `_settingsCanFix`, which turns the answer into
/// the **Open settings** shortcut under the status line. It read the answer off
/// the HTTP status until now, and the four 200-shape sentences that landed on
/// 2026-08-16 broke that key: [visionEmptyAnswerFailure],
/// [visionNotJsonFailure] and [visionWrongShapeFailure] all end on the model
/// id, which is user-typed on both surfaces since T-0067, while
/// [visionTruncatedFailure] says in as many words that the key, the model id
/// and the photo file are all fine. One status, both answers -- so the status
/// cannot decide it. Neither can the message text: matching on a sentence is
/// the coupling T-0140 and T-0145 each deleted, and these four sentences are
/// measured artifacts their authors may reword.
///
/// Named for the fact and not for the remedy, exactly as [UnreachableEndpoint]
/// is: core says what is wrong, and each shell decides what to render for it.
abstract interface class UserSetCause implements Exception {
  /// Whether the thing this failure blames is one the user holds -- the key,
  /// the model id, the backend, a URL they typed. False is a real answer and
  /// not a default: it says the remedy is somewhere Settings does not reach.
  bool get causeIsUserSet;
}

/// A vision call that failed after reaching an HTTP status, explained.
///
/// Both cloud providers used to throw `Exception('<service> <status>:
/// <body>')`, so the provider's own JSON was the entire message and a wrong
/// model id, a wrong key and an unsupported parameter all read the same
/// (T-0072).
///
/// [statusCode] is usually non-2xx and is not always: a 200 whose answer
/// stopped at the output cap arrives here too, carrying its own 200
/// ([visionTruncatedFailure]). Anything keying on the status must therefore
/// name the statuses it means rather than assume this class implies failure at
/// the transport -- and [causeIsUserSet] exists because the one caller that
/// tried could not (T-0169).
class VisionApiException implements Exception, UserSetCause {
  VisionApiException(this.message,
      {required this.statusCode,
      required this.body,
      required this.causeIsUserSet});

  final String message;
  final int statusCode;

  /// Answered per sentence by whichever builder wrote it, never derived here:
  /// the three 200s disagree with each other, so no expression over
  /// [statusCode] could produce this.
  @override
  final bool causeIsUserSet;

  /// The raw answer, kept for a bug report and deliberately kept out of
  /// [message]: it is what the user used to be given instead of an
  /// explanation.
  final String body;

  @override
  String toString() => message;
}

/// The same explanation for a status the worker will retry.
///
/// A subclass so [Worker.run]'s retry policy is untouched, and [toString] so
/// the line that finally reaches the user after the retries are spent is a
/// sentence rather than `RetryableException: ...`.
class RetryableVisionApiException extends RetryableException {
  RetryableVisionApiException(super.message);

  @override
  String toString() => message;
}

/// A CLOUD vision call that never reached a status: nothing answered, the
/// connection died before the answer did (T-0103), or nothing came back inside
/// the budget (T-0104).
///
/// Not a [VisionApiException] for the reason [OllamaUnreachableException] is
/// not one either -- there is no status and no body to explain. Both, and
/// IGDB's, are [UnreachableEndpoint]s, which is the type a caller asking "was
/// the endpoint unreachable?" catches (T-0105).
///
/// Deliberately NOT retryable, and the argument is the one thing about this
/// class that is not obvious. Three failures reach it, measured
/// with package:http 1.6.0 against loopback and an undefined name, 2026-08-15:
///
///   refused connection       2.1 s, `ClientException` that also implements
///                                   `SocketException`
///   name does not resolve   22.3 s, same
///   connection dropped      <0.1 s, plain `ClientException`
///                                   (`Connection closed before full header
///                                   was received`)
///
/// The first two are settled facts about the network for as long as
/// a scan lasts, and [Worker] would spend 2+4+8 s of backoff per photo to
/// re-learn each of them -- 42 s of sleep on a three-photo offline run before
/// the one line that explains it, and on a name that does not resolve every
/// one of those attempts pays the 22 s lookup again on top.
/// The dropped connection is the one that would repay a retry, and
/// separating it is possible but not free: the only reliable discriminator is
/// `error is SocketException`, which would put `dart:io` in a `lib/` that has
/// none (the boundary ARCHITECTURE.md keeps so the same pipeline runs
/// anywhere), and the message text cannot stand in for it -- the OS half comes
/// back in the display language, measured in a non-English one as T-0097
/// measured for Ollama.
/// Against that: each retry re-uploads a whole photograph to an endpoint that
/// has just dropped one, and no cloud endpoint has ever been called from this
/// repository (decision 0011), so the policy would be a guess about a wire
/// nobody here has watched. Retrying would also cost the type --
/// [RetryableVisionApiException] carries a message and nothing else, so the app
/// could no longer tell that the base URL, a Settings field, is what to offer
/// (T-0102).
///
/// [timedOut] is the fourth failure and it is the same type on purpose (T-0104):
/// an endpoint that accepted the connection and then said nothing is, to
/// everything downstream, the same fact as one that was never there -- no
/// status, no body, and the same Settings field to offer. Reusing the type is
/// what gets the new failure the app's existing handling for free; since T-0105
/// a class of its own would at least inherit [UnreachableEndpoint], but it would
/// still be a second name for one fact.
///
/// It is not retryable either, and for a different arithmetic. [Worker] gives 4
/// attempts and 2+4+8 s of backoff, so a retried timeout costs
/// 4 x [visionCallTimeout] + 14 s = 494 s **per photo** -- 24 minutes on a
/// three-photo scan that sends photos one at a time, which re-creates the hang
/// this bound exists to end rather than surviving it. The one attempt costs
/// 120 s. What a retry would buy is unknown in a way the refused connection's
/// was not: nothing here can tell a proxy that will stall forever from a model
/// runner that would answer on the next ask, and each attempt re-uploads a
/// whole photograph (3.32 MB as base64, measured T-0090) to an endpoint that
/// has just failed to answer one.
class VisionUnreachableException extends UnreachableEndpoint {
  VisionUnreachableException(
    http.ClientException error, {
    required this.service,
    required this.endpoint,
    required this.endpointIsUserSet,
  })  : reason = error.message,
        waited = null,
        stallRemedy = null;

  /// Nothing arrived inside the budget. No socket [reason] exists for this one
  /// -- no error was reported, which is the whole complaint.
  VisionUnreachableException.timedOut({
    required this.service,
    required this.endpoint,
    required this.endpointIsUserSet,
    required Duration this.waited,
    this.stallRemedy,
  }) : reason = '';

  /// Leads the sentence, as in [visionApiMessage].
  final String service;

  /// The URL the user can act on: the base URL they typed for the
  /// OpenAI-compatible family, and for Anthropic the full endpoint this
  /// repository fixes -- which they cannot correct but can name to a proxy or
  /// a firewall.
  @override
  final String endpoint;

  /// Why the two cloud providers advise differently: one of these URLs is the
  /// user's and the other is this repository's.
  @override
  final bool endpointIsUserSet;

  /// `http.ClientException.message`, never `'$e'`: the toString carries the
  /// request URI and, on a refused connection, an ephemeral LOCAL port
  /// (`port = 51485` beside `uri=http://127.0.0.1:51484/v1/x`, measured). Kept
  /// in parentheses at the end for the same reason the cloud bodies are quoted
  /// that way: it is the socket's sentence, localized, and can never be the one
  /// the user is expected to read.
  final String reason;

  /// How long the call was given, or null when it failed rather than stalled.
  final Duration? waited;

  /// The shell's half of the stall sentence, or null where the shell has no
  /// control to name (T-0152).
  final String? stallRemedy;

  /// "no answer came back" rather than "nothing answered there": a connection
  /// dropped mid-exchange lands here too, and something did answer that one.
  @override
  String get message => waited == null
      ? 'Cannot reach $service at $endpoint -- no answer came back, so neither '
          'the key nor the model id is what failed. '
          '${endpointIsUserSet ? _checkYourUrl : _checkThisMachine} ($reason)'
      : timedOutMessage(
          service: service,
          endpoint: endpoint,
          waited: waited!,
          advice: endpointIsUserSet ? _stalledYourUrl : _stalledInBetween,
          remedy: stallRemedy,
        );
}

/// The two halves that differ, and the whole of why they do: one of these URLs
/// is the user's own and the other is this repository's, so `ollama serve`'s
/// counterpart -- one thing to do -- exists for the configurable endpoint only.
const _checkYourUrl =
    'Check that base URL first: it is yours to set, and a wrong host or port '
    'fails exactly like this. If it is right, check whether this machine is '
    'online and whether a proxy or firewall is refusing the connection.';
const _checkThisMachine =
    'That address is fixed in this app rather than typed by you, so there is '
    'nothing to correct in your settings: check whether this machine is online '
    'and whether a proxy or firewall is refusing the connection.';

/// The same two halves for the stall (T-0104), and one clause they share with
/// the refusal above: a call that never got an answer never got a verdict on
/// the key or the model id either, and saying so is what stops a stalled proxy
/// being read as a rejected key.
///
/// Neither says how long to wait instead, and neither names a control: the
/// budget is a constructor parameter, the CLI exposes it and the app does not
/// (T-0108), so the clause about raising it is the shell's to supply and
/// arrives as [VisionUnreachableException.stallRemedy] (T-0152).
const _stalledYourUrl =
    'Neither the key nor the model id is what failed -- nothing got far enough '
    'to judge them. A host that accepts connections but is not this API stalls '
    'exactly like this, and so does a proxy that holds one open, so check that '
    'base URL first: it is yours to set. The slowest cloud read measured for '
    'this project was 34.5 s for one 4000x3000 photo, so that budget is far '
    'likelier to have caught a stall than a slow model.';
const _stalledInBetween =
    'Neither the key nor the model id is what failed -- nothing got far enough '
    'to judge them. That address is fixed in this app rather than typed by you, '
    'so what is left is the network in between: a proxy or a captive portal '
    'that accepts a connection and then holds it open stalls exactly like this. '
    'The slowest cloud read measured for this project was 34.5 s for one '
    '4000x3000 photo, so that budget is far likelier to have caught a stall '
    'than a slow model.';

/// The exception for a non-2xx vision response, given the sentence to carry.
///
/// Split out of [visionApiFailure] for [ollamaFailure] (T-0097), whose
/// vocabulary is its own -- a server that is not running and a model that is
/// not pulled are not among the cloud statuses -- but whose exception shape
/// must be the same one, or the retry policy and the all-photos-failed summary
/// treat the local path differently from the cloud ones.
///
/// [retryable] stays with the caller: no two providers here classify the same
/// statuses (Anthropic adds 529, the OpenAI shape takes every 5xx, Ollama
/// takes 429 and the three 5xx a crashed model runner answers with). So does
/// [causeIsUserSet], for the stronger reason that the two vocabularies do not
/// share a status either: a 404 is a model id on both sides but for different
/// reasons, and Ollama's second 404 is about the URL instead.
Exception visionFailure({
  required String message,
  required int statusCode,
  required String body,
  required bool retryable,
  required bool causeIsUserSet,
}) =>
    retryable
        ? RetryableVisionApiException(message)
        : VisionApiException(message,
            statusCode: statusCode,
            body: body,
            causeIsUserSet: causeIsUserSet);

/// The exception for a non-2xx CLOUD vision response.
///
/// **Which statuses [visionApiMessage] blames the user's own fields for**, and
/// why the rest are excluded rather than defaulted in -- a shortcut that leads
/// nowhere teaches the user to ignore the one that does (T-0102, moved here
/// from the app by T-0169 so it sits beside the sentences it describes):
///  - 401/403 name the key and 404 the model id, and both are Settings fields;
///  - 400 names two candidates, "a parameter or the model id", and only one of
///    them is the user's -- it is how an endpoint refuses a photo, and how it
///    reports the T-0089 `max_tokens` case. Which endpoint families answer 400
///    rather than 404 for an unknown model id is unmeasured here, so the offer
///    would rest on a guess about six endpoints;
///  - 429 and 5xx say the run itself is fine and to try later. They arrive as
///    [RetryableVisionApiException], which carries no answer at all.
Exception visionApiFailure({
  required String service,
  required String model,
  required int statusCode,
  required String body,
  required bool retryable,
}) =>
    visionFailure(
      message: visionApiMessage(
          service: service, model: model, statusCode: statusCode, body: body),
      statusCode: statusCode,
      body: body,
      retryable: retryable,
      causeIsUserSet: const {401, 403, 404}.contains(statusCode),
    );

/// What [statusCode] means for the person who typed the model id.
///
/// [service] leads the sentence: `Anthropic` for the native API, the base URL
/// for the OpenAI-compatible family, where it is the only thing that tells six
/// endpoints apart. [model] is named in every branch that the model could
/// explain, because since T-0067 the id is user-typed on both surfaces and is
/// therefore the likeliest thing to be wrong.
///
/// Bodies measured against api.openai.com on 2026-08-15, one call each:
///   - 404: `The model `gpt-4.1-mini-typo` does not exist or you do not have
///     access to it.` (`code: model_not_found`) -- so the endpoint's own
///     wording is worth quoting, the "or no access" half especially.
///   - 400: `Unsupported parameter: 'max_tokens' is not supported with this
///     model. Use 'max_completion_tokens' instead.` -- the T-0089 case, and
///     the reason a 400 quotes the provider at all: that sentence is the fix.
///   - 401: `Incorrect API key provided: sk-not-a*********-000.` The key
///     is echoed back with its ends intact, which is why 401 and 403 quote
///     nothing at all -- the redaction is the endpoint's choice, not ours.
/// Anthropic answers the same `error.message` shape (`{"type":"error",
/// "error":{"type":"not_found_error","message":"model: ..."}}`), unmeasured
/// here: no Anthropic key was available.
String visionApiMessage({
  required String service,
  required String model,
  required int statusCode,
  required String body,
}) {
  final detail = providerDetail(body);
  final said = detail == null ? '' : ' Provider said: $detail';
  return switch (statusCode) {
    400 => '$service rejected the request for model "$model" as invalid '
        '(HTTP 400). The key is not the problem; a parameter or the model id '
        'is.$said',
    401 || 403 => '$service rejected the API key (HTTP $statusCode) -- the '
        'key itself, not the model id "$model". Check the key you configured '
        'for this endpoint, and that it may use this model.',
    404 => '$service has no model "$model" (HTTP 404): that model id was not '
        'found. Check it against the endpoint\'s own model list -- a typo and '
        'a retired id both fail exactly like this, and the key is fine.$said',
    429 => '$service is rate-limiting model "$model" (HTTP 429) and the '
        'retries did not clear it. Wait, or scan fewer photos at once.$said',
    >= 500 => '$service failed on its side for model "$model" (HTTP '
        '$statusCode) and the retries did not clear it. Nothing about this '
        'run is wrong; try again later.$said',
    _ => '$service refused the request for model "$model" (HTTP $statusCode).'
        '$said',
  };
}

/// The exception for a 200 whose answer stopped at the output cap.
///
/// [VisionApiException] rather than a class of its own, and the status it
/// carries is the true one: the call succeeded, so nothing downstream should
/// read it as a rejection. [body] keeps the raw answer out of the message,
/// exactly as it does for a non-2xx.
///
/// **The one of the four 200s that answers [UserSetCause] `false`** (T-0169),
/// and its own sentence is the argument: the key, the model id and the photo
/// file are all named as fine, the cap is a constant in this build that
/// neither surface exposes, and the fix offered is to photograph the shelf in
/// sections. Nothing in Settings changes any of that, so the shortcut its
/// three neighbours get would lead nowhere here.
///
/// Deliberately NOT retryable, and the arithmetic is the opposite of a 429's. A
/// retry is not hopeless -- T-0120 measured one `CONTROL-HIRES` photo through
/// `gpt-5.5` at completion 3046, 4093 and twice at the 4096 ceiling, so the
/// tail is what crosses it -- but [Worker] gives four attempts, and each one
/// re-uploads the whole photograph and bills a whole capped completion for an
/// answer that will be discarded if it lands long again. Splitting the photo
/// moves the ceiling; asking the same question four times does not.
Exception visionTruncatedFailure({
  required String service,
  required String model,
  required int? cap,
  required String answer,
  required String body,
  bool hasKey = true,
}) =>
    VisionApiException(
      visionTruncatedMessage(
        service: service,
        model: model,
        cap: cap,
        wroteNothing: answer.trim().isEmpty,
        hasKey: hasKey,
      ),
      statusCode: 200,
      body: body,
      causeIsUserSet: false,
    );

/// What a completion that stopped at the output cap means for the person who
/// took the photograph.
///
/// The failure it replaces is `FormatException: Unexpected end of input`, which
/// is the T-0072 class: true, useless, and blaming the JSON for what the token
/// budget did. Every provider here can see it -- `finish_reason: length` in the
/// OpenAI shape, `stop_reason: max_tokens` from Anthropic, `done_reason:
/// length` from Ollama -- and until T-0111 none of them looked.
///
/// **Two shapes, one cause** (T-0120, live, 2026-08-16). Two of three photos
/// came back `finish_reason: length` with `completion_tokens: 4096` and an
/// EMPTY `content`: the reasoning model spent the whole budget before it wrote
/// a character. The half-JSON form is the one the defect was filed for. Both
/// arrive here, and [wroteNothing] is the only thing that separates them,
/// because "your answer was cut short" is a lie about a photo that produced no
/// answer at all.
///
/// **The advice is what the user can reach, which is one action of the two.**
/// Fewer spines per photo is theirs. The cap is not: it is a constant in this
/// build (`_maxOutputTokens` in openai_compatible_vision.dart, `_numPredict`
/// in ollama_vision.dart, [_anthropicMaxOutputTokens] here), and neither the
/// app nor the CLI exposes a control for any of the three, so recommending it
/// would be T-0072 again in a new costume. A null [cap] is the case where this
/// request carried none -- an endpoint that refused both names for it
/// (T-0120/T-0139) -- and there the ceiling is the endpoint's own, so the
/// sentence must not claim a number this repository sent. Ollama was that case
/// until T-0281 measured what its absent cap cost and sent one.
String visionTruncatedMessage({
  required String service,
  required String model,
  required int? cap,
  required bool wroteNothing,
  bool hasKey = true,
}) {
  final ceiling =
      cap == null ? 'its own output limit' : 'the $cap-token output cap';
  final what = wroteNothing
      ? 'and wrote no answer at all -- a reasoning model can spend the whole '
          'budget thinking before it writes a character'
      : 'so the answer breaks off part-way and is no longer the complete JSON '
          'the rest of the scan reads';
  // A keyless server has no key to clear the user of suspecting, and naming
  // one there is the local path borrowing the cloud's vocabulary (T-0097).
  final notAtFault = hasKey
      ? 'The key, the model id and the photo file are all fine'
      : 'Neither the model id nor the photo file is at fault';
  final whose = cap == null
      ? 'That limit is the endpoint\'s own; this request carries no cap for it '
          'to raise.'
      : 'That cap is fixed in this build and neither the app nor the CLI has a '
          'control for it, so fewer spines is the fix that is yours.';
  return '$service stopped model "$model" at $ceiling $what. $notAtFault -- '
      'there was more on that shelf than one answer can hold. Photograph it in '
      'two or three sections and scan those instead. $whose';
}

/// The exception for a 200 that carries no answer text for a reason other than
/// the output cap.
///
/// A third pair beside [visionTruncatedFailure] rather than a flag on it
/// (T-0142). The two share only the status and the not-retryable decision;
/// every load-bearing clause of the truncated sentence -- the cap, the number,
/// "more on that shelf than one answer can hold", photograph it in sections --
/// is false here, and a photo the endpoint refused on policy grounds is not
/// made smaller by splitting it.
///
/// [reason] is the endpoint's own stop field (`finish_reason`, `stop_reason`,
/// `done_reason`), null when the answer carried none. [refusal] is the OpenAI
/// shape's `message.refusal`, the only one of these that comes with the model's
/// own words.
///
/// [UserSetCause] `true`, unlike its truncated neighbour and on the same
/// evidence -- its own sentence (T-0169). Both branches end on the model id
/// and the backend, and both are the user's on both surfaces.
Exception visionEmptyAnswerFailure({
  required String service,
  required String model,
  required String? reason,
  required String body,
  String? refusal,
  bool hasKey = true,
}) =>
    VisionApiException(
      visionEmptyAnswerMessage(
        service: service,
        model: model,
        reason: reason,
        refusal: refusal,
        hasKey: hasKey,
      ),
      statusCode: 200,
      body: body,
      causeIsUserSet: true,
    );

/// The stop reasons that mean the endpoint refused the image rather than failed
/// to describe it: `content_filter` in the OpenAI shape, `refusal` from
/// Anthropic. Both are documented values and neither has been seen here.
const _refusedImageReasons = {'content_filter', 'refusal'};

/// What a 200 carrying no text means for the person who took the photograph.
///
/// The failure it replaces is `type 'Null' is not a subtype of type 'String'`
/// in the OpenAI-compatible provider and `FormatException: Unexpected end of
/// input` in the other two -- the T-0072 class, and the first of them worse
/// than what it replaced because it names a Dart type instead of anything about
/// the run.
///
/// Built from the vendors' documented response shapes, not from a run: nothing
/// here has ever seen one of these (T-0142). `content` is documented null in
/// the OpenAI shape for a refusal, for a tool-only answer and for
/// `finish_reason: content_filter`; Anthropic's `content` can arrive with no
/// text block for the same reasons.
///
/// **A refusal gets its own sentence** because it is the only one of these the
/// user can act on, and what they can do is not obvious about a photograph of
/// their own shelf. The two actions named are the ones that exist on both
/// surfaces -- the model id is user-typed (T-0067) and the backend is chosen by
/// the app's switch or the CLI's `--provider` -- and the local one is qualified,
/// because Android has no local backend at all (`ProviderPolicy.available`).
///
/// **An unrecognised reason is quoted, never absorbed.** A default sentence
/// that hides the one string the endpoint volunteered would be this defect
/// again in a new costume.
String visionEmptyAnswerMessage({
  required String service,
  required String model,
  required String? reason,
  String? refusal,
  bool hasKey = true,
}) {
  final said = refusal == null ? null : _capped(refusal);
  final quote = said == null ? '' : ' It said: $said';
  final accepted = _accepted(hasKey);
  if (_refusedImageReasons.contains(reason)) {
    return '$service declined this photograph for model "$model" and returned '
        'no answer at all ("$reason").$quote $accepted, and then the image '
        'itself was refused under the endpoint\'s own content rules, which '
        'nothing in this app or the CLI can relax. What is left is a different '
        'reader: the model id is yours to type and the backend is yours to '
        'choose on both surfaces, and where this machine can run Ollama the '
        'local backend has no such filter in front of it.';
  }
  final why = reason == null
      ? 'and named no reason for it'
      : 'and named "$reason" as the reason it stopped';
  return '$service answered for model "$model" with no text at all $why.$quote '
      '$accepted, and the call itself succeeded (HTTP 200) -- what is missing '
      'is the answer the rest of the scan reads. That reason is quoted as the '
      'endpoint gave it rather than interpreted: the only empty answer this '
      'build can explain is the output cap, and this was not that. Scan that '
      'photo again, and if it comes back empty a second time try another model '
      'id or another backend -- both the app and the CLI let you choose one.';
}

/// Which of the two things a 200 clears the user of suspecting.
///
/// A keyless server has no key to clear the user of suspecting, and naming one
/// there is the local path borrowing the cloud's vocabulary (T-0097). Shared by
/// the two sentences that say it rather than copied into both.
String _accepted(bool hasKey) => hasKey
    ? 'Your key and the photo file are not what failed -- both were accepted'
    : 'The photo file is not what failed -- it was accepted';

/// The exception for a 200 whose text is not a JSON document at all.
///
/// **A [FormatException] on purpose, and it is the one decision in this pair.**
/// T-0013 pinned that type for this answer on all three providers
/// (`vision_parsing_test.dart`, "a payload that is not JSON fails") and T-0083
/// pinned it again at four boundaries of its stripping rule. Two facts settle
/// whether that pin is the contract or the defect, and they point the same way:
///
///   - **Nothing in the repository catches it, so nothing can be broken by
///     keeping it.** The four `on FormatException` clauses in `lib/` and `bin/`
///     are the review-file parse, the alias-file parse and two error-body
///     decodes; a vision answer reaches none of them. It travels instead
///     through `runPool`'s untyped `catch (e)` and is stringified into a
///     warning, so the message is the whole of what a user ever sees.
///   - **It is the one of the four 200-shapes where the type is true.** The cap
///     (T-0111) and the empty answer (T-0142) are reported by the endpoint in a
///     stop field and are read before the parse; nothing is malformed in
///     either. Here the call succeeded, the model answered, and the answer is
///     genuinely not the document it should be -- which is what this type
///     means.
///
/// So the type stays and only the message changes. The cost is the
/// `FormatException: ` prefix Dart's own [Object.toString] puts in front of the
/// sentence; a subclass overriding it would drop the prefix and break the four
/// T-0083 boundary tests that assert it, which is a worse trade than a wart.
FormatException visionNotJsonFailure({
  required String service,
  required String model,
  required String answer,
  bool hasKey = true,
}) =>
    VisionNotJsonException(visionNotJsonMessage(
      service: service,
      model: model,
      answer: answer,
      hasKey: hasKey,
    ));

/// [visionNotJsonFailure]'s type: still a [FormatException], and now able to
/// answer [UserSetCause] (T-0169).
///
/// This is the one of the four 200-shapes that reached the app as a type it
/// could not classify at all, because T-0164 pinned [FormatException] for it
/// (see above) and that class carries nothing but a message. A **subclass**
/// costs neither half of that pin: `dart:core`'s `toString` opens with the
/// literal `"FormatException"` rather than with `runtimeType`, so the prefix
/// T-0164 accepted as a wart is unchanged byte for byte, and every
/// `isA<FormatException>` in T-0013's and T-0083's tests still matches.
class VisionNotJsonException extends FormatException implements UserSetCause {
  VisionNotJsonException(super.message);

  /// The sentence ends on the model id in the app's settings, which is the
  /// remedy it names and the only one it names.
  @override
  bool get causeIsUserSet => true;
}

/// What a 200 carrying text that is not JSON means for the person who took the
/// photograph.
///
/// The failure it replaces is `FormatException: Unexpected character (at
/// character 1)` -- the T-0072 class, naming the JSON rather than the model
/// that was told "STRICT JSON only, no prose" ([detectionPrompt]) and wrote
/// prose anyway.
///
/// **Unmeasured**: no endpoint has produced one of these
/// (T-0164). The shapes it is built for are prose, an apology, and the
/// reasoning markers T-0083's rule deliberately does not reach -- Kimi's
/// `◁think▷` non-element markers and the harmony `<|channel|>` headers.
///
/// **[answer] is quoted rather than described**, through the same [_capped] the
/// other sentences use, because the first line of it is the only thing that
/// tells the user which of those they have -- and it separates prose from a
/// payload that stopped part-way, which reaches here too whenever no stop field
/// named the cap.
///
/// **The remedy named is the model id**, and it exists on all three surfaces:
/// the app's settings screen has a text field per backend and the CLI reads
/// `SHELFSCAN_OLLAMA_MODEL` / `SHELFSCAN_OPENAI_MODEL` /
/// `SHELFSCAN_ANTHROPIC_MODEL`. Nothing is said about the prompt: it is a
/// measured artifact no user can reach (decision 0002), so advising it would be
/// T-0072 in a new costume.
String visionNotJsonMessage({
  required String service,
  required String model,
  required String answer,
  bool hasKey = true,
}) {
  final said = _capped(answer);
  final quote = said == null ? '' : ' It said: $said';
  return '$service answered for model "$model" with text that is not the JSON '
      'document the rest of the scan reads.$quote ${_accepted(hasKey)}, and the '
      'call itself succeeded (HTTP 200) -- what this model did not do is follow '
      'the instruction to answer in strict JSON and no prose. Scan that photo '
      'again, and if the answer looks like that a second time the model is the '
      'thing to change rather than the shelf or the photograph: the model id is '
      'yours to type, in the app\'s settings and in the CLI\'s environment, and '
      'a model that will not answer in JSON here will not on the next photo '
      'either.';
}

/// The exception for a 200 whose text decoded and is not this document.
///
/// **A fifth pair rather than a flag on [visionNotJsonFailure]** (T-0167). The
/// two share a frame and disagree in the clause that matters: there the model
/// ignored "STRICT JSON only" and wrote prose, here it answered in JSON and
/// answered a different question, and only this one has somewhere to point.
/// Folding them would cost the path, which is the whole gain.
///
/// **A [VisionApiException], unlike its neighbour.** T-0164 kept a
/// [FormatException] because T-0013 and T-0083 pin that type for a text that is
/// not JSON; the cast error this replaces is pinned by nothing, so the type is
/// free -- and the family's own class is the better answer, as it is for the
/// other two 200s (T-0111, T-0142). It carries [answer] in `body` for a bug
/// report, and it drops the `FormatException: ` prefix T-0164 had to accept as
/// a wart. `statusCode` is 200 here; [UserSetCause] rather than that status is
/// what decides the Settings route (T-0169), and the answer is `true` -- the
/// sentence ends on the model id, in the app's settings.
Exception visionWrongShapeFailure({
  required String service,
  required String model,
  required String problem,
  required String answer,
  bool hasKey = true,
}) =>
    VisionApiException(
      visionWrongShapeMessage(
        service: service,
        model: model,
        problem: problem,
        answer: answer,
        hasKey: hasKey,
      ),
      statusCode: 200,
      body: answer,
      causeIsUserSet: true,
    );

/// What a 200 carrying the wrong document means for the person who took the
/// photograph.
///
/// The failure it replaces is `type 'List<dynamic>' is not a subtype of type
/// 'Map<String, dynamic>' in type cast` -- the T-0072 class at its purest, a
/// Dart generic naming neither the run, the model nor the endpoint.
///
/// **Measured since T-0278**, and by the default local model: past a density
/// ceiling `qwen2.5vl:7b` repeats itself under greedy decoding until it runs
/// out of context, and the answer that arrives is one array of near-identical
/// entries. Whether that reaches here or [visionTruncatedFailure] is decided
/// by nothing the user did -- the model either closes the document first
/// (here) or fills the context first (there) -- which is why the advice below
/// now names the shelf as well as the model id. The shapes the filing measured
/// offline still hold; `{"items":["Vex"]}` is the one a model plausibly
/// writes.
///
/// [problem] is the parse's own `path is X; it must be Y`, which is the reason
/// the check lives in the parse: the boundary could only have said "the wrong
/// shape", and where is most of what a reader needs.
///
/// **What is deliberately absent is any suggestion of what the model meant.**
/// The sentence says the answer was declined and not repaired, because the
/// alternative is invented rows in a review list (T-0007).
String visionWrongShapeMessage({
  required String service,
  required String model,
  required String problem,
  required String answer,
  bool hasKey = true,
}) {
  final said = _capped(answer);
  final quote = said == null ? '' : ' It said: $said';
  return '$service answered for model "$model" with JSON that is not the '
      'document the rest of the scan reads: $problem.$quote '
      '${_accepted(hasKey)}, and the call itself succeeded (HTTP 200) -- the '
      'answer decoded, and what it decoded to is a different document from the '
      'one this scan asks for. None of it was read anyway: an answer this shape '
      'is declined whole rather than repaired into a plausible one, because a '
      'repaired row would sit in your review list looking exactly like a title '
      'read off a spine. Scan that photo again. If the answer has the same '
      'shape a second time, try the shelf before the model: the one cause '
      'measured for this shape is a frame holding more spines than the model '
      'can hold at once, which makes it repeat itself until the answer is a '
      'wall of copies, and photographing the shelf in two or three sections '
      'ends it. If sections change nothing, the model id is yours to type, in '
      'the app\'s settings and in the CLI\'s environment.';
}

/// How much of a provider's explanation is quoted before it stops being one.
const _detailLimit = 200;

/// One line of it, whitespace collapsed and cut to [_detailLimit], or null when
/// there is nothing left.
String? _capped(String line) {
  final collapsed = line.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (collapsed.isEmpty) return null;
  return collapsed.length <= _detailLimit
      ? collapsed
      : '${collapsed.substring(0, _detailLimit)}...';
}

/// The server's own one-line explanation, or a capped excerpt when the body is
/// not the `error.message` shape the cloud families use -- a proxy's HTML error
/// page is then the only information there is, and a truncated line of it
/// still beats nothing.
///
/// Public since T-0097 so the local provider quotes bodies the same way the
/// cloud ones do rather than growing a second copy of this.
String? providerDetail(String body) =>
    _capped(_explanationIn(_decodeOrNull(body) ?? body) ?? body);

Object? _decodeOrNull(String text) {
  try {
    return jsonDecode(text);
  } on FormatException {
    return null;
  }
}

/// The explanation buried in a decoded body, or null if there is none to find.
///
/// Recursive for one measured reason (T-0097): Ollama answers a rejected image
/// with a whole JSON document ENCODED AS A STRING inside `error` --
/// `{"error":"{\"error\":{\"code\":400,\"message\":\"Failed to load image or
/// audio file\",...}}"}` on 8 bytes of fake JPEG, local server, 2026-08-15.
/// Taking that string as the explanation, which is what the flat version did,
/// hands the user escaped JSON and calls it a sentence.
///
/// Terminates because `jsonDecode` of a JSON string literal is strictly shorter
/// than its source.
String? _explanationIn(Object? data) {
  if (data is String) {
    final inner = _decodeOrNull(data);
    return inner == null ? data : _explanationIn(inner) ?? data;
  }
  if (data is Map<String, dynamic>) {
    for (final key in const ['error', 'message']) {
      if (data.containsKey(key)) {
        final found = _explanationIn(data[key]);
        if (found != null) return found;
      }
    }
  }
  return null;
}

const _apiUrl = 'https://api.anthropic.com/v1/messages';

/// The cap the Anthropic request carries, named rather than written twice so
/// the message reporting a `stop_reason: max_tokens` cannot quote a number the
/// request did not send.
///
/// **The lowest of the three this repository sends, and the only one nobody
/// has priced** (T-0281). The other two are 8192: `_maxOutputTokens` in
/// openai_compatible_vision.dart clears a reasoning model's measured tail,
/// `_numPredict` in ollama_vision.dart clears a dense shelf inside the call
/// timeout. They are not one constant and should not become one -- three
/// different models, three different things being bounded.
///
/// What 4096 is worth flagging for is arithmetic, not a measurement: this
/// answer is ~48 tokens a row whatever writes it, so 4096 is about 85 rows,
/// and T-0278's ladder puts an 84-spine frame at 3023 tokens and a 120-spine
/// one at 5504. A dense frame would therefore stop here. Carried across models
/// and never run -- no key for this provider has ever been available, which is
/// the same reason the class comment below gives for every other number on it.
const _anthropicMaxOutputTokens = 4096;

/// Vision provider backed by the Anthropic Messages API.
///
/// No key for it was ever available, so nothing in this
/// repository is a measurement of this provider. Every count quoted below --
/// and every count in [detectionPromptRules] -- was taken from `qwen2.5vl:7b`
/// through Ollama, and none of it is evidence about a cloud model.
class AnthropicVisionProvider implements VisionProvider {
  /// Sampling is stated rather than inherited (T-0057), following
  /// [OllamaVisionProvider] and T-0053. Sending nothing does not mean sampling
  /// is off: it means the endpoint picks, and unlike a local model there is no
  /// Modelfile to read the choice out of afterwards.
  ///
  /// **[temperature] 0 buys a stated setting, not repeatability, because this
  /// API has no seed.** The Messages API takes `temperature`, `top_p` and
  /// `top_k` and nothing else -- there is no seed parameter to send (checked
  /// against the Messages API reference, 2026-08-15), and Anthropic documents
  /// no bit-exactness guarantee at any temperature. So two cloud scans of the
  /// same photo may legitimately differ, and a difference between them is not
  /// by itself a defect. `top_p` and `top_k` are deliberately left unset: at
  /// temperature 0 the distribution they would truncate is already degenerate,
  /// and Claude 4+ rejects `temperature` and `top_p` sent together.
  ///
  /// The 0 is argued from local evidence and nothing else. T-0053 measured
  /// this prompt on `qwen2.5vl:7b` at temperature 0.8: invented titles on 3 of
  /// 5 seeds at each resolution, and `platform_hint` returned as the
  /// [detectionJsonSchema] example text verbatim on whole photos -- the
  /// T-0014/T-0028 defect that prompt wording alone does not hold shut once
  /// decoding stops being near-greedy. Whether a frontier cloud model degrades
  /// that way is **unmeasured**. Near-greedy is chosen here because it is the
  /// decoding every rule in [detectionPromptRules] was written against, not
  /// because the local numbers were shown to transfer.
  ///
  /// [temperature] is nullable because the parameter is model-gated: sampling
  /// parameters were removed from Claude Opus 4.7 and later, Sonnet 5 and
  /// Fable 5, where a request carrying one returns 400 (Messages API
  /// reference, 2026-08-15). The default [model] accepts it. Pass
  /// `temperature: null` to point this provider at one of those models -- and
  /// record in the run notes that the sampling was then the endpoint's, which
  /// is the unrecorded state this whole task exists to end.
  ///
  /// ## Measurement recipe -- for whoever gets a key
  ///
  /// None of this has been run. It is written down so the first person with a
  /// key executes the method this project already paid for locally (T-0034,
  /// T-0053) instead of re-deriving it, and so their numbers are comparable
  /// with the local ones rather than a separate island.
  ///
  /// Control sets: **both**, always. The low-res pair at 1200x900 and the
  /// hi-res three at 4000x3000. They do not exercise the same failures -- four
  /// prompt edits were signed off on hi-res alone and the low-res
  /// anti-invention guarantee broke silently underneath them (T-0034). The
  /// local scores on those sets are in the control record; that is the
  /// yardstick
  /// for "did the cloud model read more spines", not a target to reproduce.
  ///
  /// Repeats: 8 runs per set per setting, as T-0053 used -- enough that one
  /// stable draw cannot pass as a constant. Here all 8 are plain repeats since
  /// there is no seed. On [OpenAiCompatibleVisionProvider] spend 3 of the 8 on
  /// seed changes instead, which is the only way to find out whether that
  /// endpoint honours the field.
  ///
  /// Compare, per photo and per run:
  ///   - detection count and the titles themselves;
  ///   - invented titles -- a title with no matching spine **on the
  ///     photograph**, verified by eye. Never JSON against JSON: that is how
  ///     invented titles survived four prompt edits;
  ///   - `platform_hint` correct / wrong / absent per row, and separately
  ///     whether any row echoed the [detectionJsonSchema] example text as its
  ///     value (T-0014, T-0028);
  ///   - the Japanese spines the model must omit rather than guess, and
  ///     the そらのは re-releases answered `PS2` locally (T-0029) -- the
  ///     two defects a cloud model is being bought for;
  ///   - stability: how many of the 8 runs are byte-identical, and where they
  ///     differ, whether it is typography or an item ([titleKey] folds the
  ///     first away, so only the second changes review rows).
  ///
  /// Record the model id, the date, and the temperature actually sent
  /// alongside every number. A cloud model id is not a frozen artifact the way
  /// a pulled Ollama tag is, so a figure without those three cannot be
  /// repeated even in principle.
  AnthropicVisionProvider({
    required this.apiKey,
    this.model = 'claude-sonnet-4-6',
    this.temperature = 0,
    this.timeout = visionCallTimeout,
    this.stallRemedy,
    http.Client? client,
  }) : _client = client;

  final String apiKey;
  final String model;
  final double? temperature;

  /// See [visionCallTimeout] for what the default rests on.
  final Duration timeout;

  /// What a shell that can change [timeout] tells the user to do about a stall
  /// (T-0152). Null on a shell that cannot, which is the app.
  final String? stallRemedy;

  /// The caller's client, or null when each call makes and closes its own
  /// ([boundedPost]).
  final http.Client? _client;

  @override
  Future<PhotoAnalysis> analyze(PhotoInput photo) async {
    final http.Response response;
    try {
      response = await boundedPost(
        (client) => client.post(
          Uri.parse(_apiUrl),
          headers: {
            'x-api-key': apiKey,
            'anthropic-version': '2023-06-01',
            'content-type': 'application/json',
          },
          body: jsonEncode({
            'model': model,
            'max_tokens': _anthropicMaxOutputTokens,
            if (temperature != null) 'temperature': temperature,
            'system': detectionPrompt,
            'messages': [
              {
                'role': 'user',
                'content': [
                  {
                    'type': 'image',
                    'source': {
                      'type': 'base64',
                      'media_type': photo.mimeType ?? 'image/jpeg',
                      'data': base64Encode(photo.bytes),
                    },
                  },
                  {
                    'type': 'text',
                    'text': 'Catalog every game visible on this shelf photo.',
                  },
                ],
              }
            ],
          }),
        ),
        reusing: _client,
        within: timeout,
        onTimeout: (waited) => VisionUnreachableException.timedOut(
          service: 'Anthropic',
          endpoint: _apiUrl,
          endpointIsUserSet: false,
          waited: waited,
          stallRemedy: stallRemedy,
        ),
      );
    } on http.ClientException catch (e) {
      throw VisionUnreachableException(
        e,
        service: 'Anthropic',
        // The full endpoint rather than the host: it is not a setting, so what
        // is left to do with it is name it to a proxy or a firewall.
        endpoint: _apiUrl,
        endpointIsUserSet: false,
      );
    }

    final status = response.statusCode;
    if (status != 200) {
      throw visionApiFailure(
        service: 'Anthropic',
        model: model,
        statusCode: status,
        body: response.body,
        retryable: const {429, 500, 502, 503, 529}.contains(status),
      );
    }

    final answer = jsonDecode(response.body) as Map<String, dynamic>;
    final text = (answer['content'] as List<dynamic>? ?? [])
        .where((b) => b['type'] == 'text')
        .map((b) => b['text'] as String? ?? '')
        .join();
    // Unmeasured here -- no Anthropic key was available --
    // so this reads the documented `stop_reason` and nothing else: it is the
    // only thing that tells a 200 cut off at the cap from a model that answered
    // badly (T-0111).
    if (answer['stop_reason'] == 'max_tokens') {
      throw visionTruncatedFailure(
        service: 'Anthropic',
        model: model,
        cap: _anthropicMaxOutputTokens,
        answer: text,
        body: response.body,
      );
    }
    // A content list with no text block in it joins to '' and used to die one
    // step later as `FormatException: Unexpected end of input` (T-0142).
    if (text.trim().isEmpty) {
      throw visionEmptyAnswerFailure(
        service: 'Anthropic',
        model: model,
        reason: answer['stop_reason']?.toString(),
        body: response.body,
      );
    }
    return parsePhotoAnalysisAnswer(text, photo.name,
        service: 'Anthropic', model: model);
  }
}
