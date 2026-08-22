# The control-set manifest

What identifies each control set, in the form the tests parse. This is the
machine-readable half of the control definition, and the half that is
published. The other half — the counts each set must reproduce, the byte sizes
and content hashes that identify the photographs, the commands that regenerate
a run, the staleness ladder and the cache-state recipe — stays in the working
record beside the photographs it describes, because the sets are named sets of
a private home
([decision 0004](decisions/0004-the-control-set-is-figures-not-a-file.md)).
What the sets are and what was measured on them is
[`doc/measurements.md`](measurements.md), "The two control sets".

**The control set itself is private and is not published.** The photographs are
of a private home; neither the images, nor their original filenames, nor their
byte sizes, nor any figure stating how many spines, cases or games are on them,
is in this repository or ever will be. That last clause was false when it was
written: the counts were out of the manifest blocks (T-0246) and still in the
prose of about fifty files, spelled out, as ratios and over subsets, until
T-0253 swept them. `doc/measurements.md`, "The two control sets", says what is
still counted anywhere and why none of it is a count of the shelf.
`photos` below names each image by a stable label rather than by
the name it was given, so a figure stays attached to the file it was measured
on without the file naming itself.

**The counts are not here, and neither is the platform mix (T-0246, T-0260).**
A detection count is a count of one household's possessions, and the platform
split is a list of which consoles that household owns; together they
reconstruct the collection. So `detections`, `per_photo`, the `hint_*` counts,
`empty_titles` and `unreadable` live in `doc/control-set.md` beside the
photographs they describe, next to the `sizes` key that has been kept there for
the same reason since T-0234. The checks they serve can only fire where the
photographs are, so they run there and skip everywhere else.

**T-0246 left a `hints` key here, and that was half a removal.** Its reasoning
was that a hint name is a token this project's own prompt offers the model
while the number of rows answering it is a shelf. That is true of one name and
false of an exhaustive set of them: a list of every platform answered across a
shelf is that shelf's platform mix, and needs no number attached to be one.
T-0260 dropped the key. The names were not moved anywhere, because the `hint_*`
keys in `doc/control-set.md` already spell them beside their counts — the
removal takes something out of this file and adds nothing to that one.

What stays here is what is not a disclosure: which sets exist, which files each
one is, and the fingerprint of the prompt they were all measured against.

**It is published so that one check runs everywhere (T-0231).** `[PROMPT]`
below pins the assembled `detectionPrompt`, so editing `detectionPromptRules`
or `detectionJsonSchema` in
`packages/shelfscan_core/lib/src/providers/vision.dart` fails `dart test` on
every machine — no photographs, no model, no network. **That failure is the
feature: re-measure and move the figures, never move the hash.** Until T-0231
these blocks lived with the prose above, which is not in a clone, so the check
ran on one machine while [`CONTRIBUTING.md`](../CONTRIBUTING.md) said it ran on
all of them.

Nothing here quotes a title, and since T-0246 nothing here counts one. The
working record counts rather than compares for a measured reason: two
regenerations of the same set differ in letter case, ™/® and one diacritic
without moving any count.

Only the prompt check is runnable from this file alone. Everything that needs
the photographs — that the named files are present at the byte sizes the
working record states, and that a freshly regenerated review document still
produces the counts it states — skips with a named reason wherever
`SHELFSCAN_PHOTOS` and `SHELFSCAN_CONTROL_REVIEW` are unset, which is every
machine but one.

## CONTROL-HIRES

Three 4000×3000 photographs of the same subject, HEIC originals converted to
JPEG once
by WIC (T-0031). Measured 2026-08-15, local `qwen2.5vl:7b`, temperature 0, seed
20260814, three runs.

```control-set
[CONTROL-HIRES]
photos          = shelf-1.jpg, shelf-2.jpg, shelf-3.jpg
```

## CONTROL-LOWRES

The same subject at 1200×900, two photographs. Same model and sampling,
measured
2026-08-15. Zero invented titles is this set's whole reason for existing
(T-0034) and it is not a key below: it is counted against the photographs by
eye, never against a previous JSON.

```control-set
[CONTROL-LOWRES]
photos          = lowres-1.jpg, lowres-2.jpg
```

## The prompt these figures belong to

A detection count is a measurement of a prompt. `detectionPrompt` composes
`detectionPromptRules` and `detectionJsonSchema`, and its fingerprint is
recorded here:

```control-set
[PROMPT]
fingerprint = 56cb401b
chars       = 3581
```

**What this still proves after T-0246 took the counts off the page.** It proves
that the prompt every recorded measurement of this project belongs to has not
silently changed: edit either constant and `dart test` fails on any machine,
naming the working record to re-measure. That was always the check worth having
everywhere — the defect being prevented is a prompt moving three times under
figures that stayed put, and the fingerprint is the half that detects it. What
it no longer does is name the figures on the same page; they are in
`doc/control-set.md`, and the failure message points there.

FNV-1a over the UTF-8 bytes, computed by `promptFingerprint` in
`packages/shelfscan_core/tool/control_capture.dart`. A hash and not a copy of
the text, because the copy would be a second place to edit the most
measurement-sensitive text in the repository, and the whole class of defect
here is two things that are supposed to agree drifting apart (T-0056, T-0077).
