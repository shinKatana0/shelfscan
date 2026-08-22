# 0008 — When a source carries the store's own product id, join on it and skip every gate

**Status:** accepted, 2026-08-16
**Tasks:** T-0159 (*A GoG product id could join IGDB exactly, instead of being
matched as a string*), T-0157 (*GoG installs carry authoritative metadata next to
them, and nothing reads it*)
**Reports:** `T-0159`, `T-0157`
**Measurements:** `doc/measurements.md` — "The exact join: IGDB does carry GoG
ids, and 82% of them"

## Context

A game installed from the GOG store leaves a small metadata file beside itself
carrying the store's own product id. The games database this project resolves
against, IGDB, records external store ids for many games.

If those two ids can be joined, a PC game does not need to be matched by its
title at all. The question was whether the join exists in practice, and whether
it is worth a second code path next to a fuzzy matcher that already works.

## Decision

**Where a row carries a store product id, resolve it by joining on that id, and
skip every safety gate the title path uses** — the score threshold, the platform
agreement check, the volume-number check and the tie rule. Where the join
returns nothing, fall through to the ordinary title path.

The gates exist to make a *guess* safe. There is no guess here.

## The measurement that settled it

The premise was verified before anything was built, which is the part of this
worth copying. The database's own source listing was read live: it answers 22
external sources and the store in question is a specific numbered one. Only then
was the hit rate measured.

- **The join exists and is common**, at a rate given in `doc/measurements.md`.
  The sample deliberately was not a real library — no real library was
  available to measure. It was the
  store's public catalogue, sampled evenly across the whole of it in trending
  order so that the long tail is represented as heavily as the front page. The
  outlier page is named in the archive; popularity is not what predicts a hit, so
  the figure is honest for a shelf of unknown taste rather than a best case.
- **The join is one-to-one.** Every id that joined produced exactly one row and
  one game — no id carried a second row and none resolved to a second game. That
  property, not the hit rate, is what entitles the resolver to skip the gates.
- **It buys rows the title path cannot have at any threshold.** Four rows were
  driven through the shipped resolver twice, live, on the identical raw title —
  once with the product id and once without. Two of the three title collisions
  that [0007](0007-the-resolver-refuses-what-it-cannot-decide.md) measured are in
  that set: a 1993 game and its modern remake share a title, the string path
  cannot tell them apart and correctly refuses both, while the product id already
  says which release is installed.
- **Cost per row is one request** where it answers, against one search plus up to
  four more on the fallback ladder; a row that does not join pays one request
  more than today and then resolves exactly as it does today.

## Consequences

- The join applies **no platform filter**, deliberately, and that is worth a row
  the filtered search loses: a DOS-era release is *found* by id and reaches a
  human with the platforms the database really gives it, where the title search
  under a Windows filter answers nothing.
- The platform is the one thing the join does not answer — the external row
  carries none — so the platform id for the export comes from the joined game's
  own platform list, chosen through the hint. Most joined games are listed on
  more than one platform, so this is a real choice and not a formality.
- Where the joined game is listed on **no** platform at all, the row falls back
  to the title path rather than asserting a platform the database does not
  record. A hit is a (game, platform) pair and there is no pair to make.
  Claiming one would be a guess on the one path in this product whose whole claim
  is that it does not guess.
- Adding another storefront is a single entry in a map plus one measurement of
  its source number. A store this project has not measured is not an error — the
  row simply resolves the ordinary way.
