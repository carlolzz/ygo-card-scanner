# Next session: is 72 the right ceiling, and is the quality gate calibrated?

**Written:** 2026-08-03 · **Against:** branch `scan-detection-and-collection-ux`
(CLAUDE.md build-order step 19).

**Baseline to start from:** `flutter analyze` clean, **397** tests green,
`pytest tools/` green.

`CLAUDE.md` steps 18 and 19 have the full background. This file covers only what
is *not* written down there: what to look at on the phone, in what order, and why.

---

## What changed under you, and what it means for testing

Step 19 removed the second distance gate. Every hit the index ranks within
`ArtMatchTuning.maxHammingDistance` (72) now opens the review panel; past
`autoMatchMaxDistance` (48) it opens hedged — **"Best guess — check the
picture"** under the card name.

So the two things to watch are opposites of each other:

1. **Cards that used to fail should now just work.** The 48-72 band was being
   discarded into the empty-frame branch. If "Can't identify this card" still
   appears often, the nearest hit is beyond 72 and the ceiling — not the
   presentation — is the constraint.
2. **Watch for a hedged panel showing the *wrong* card.** That is the cost this
   change buys. It should be rare (only 1.37 % of indexed cards have any
   neighbour within 72) and it is recoverable in one tap, but if it happens more
   than occasionally, `maxHammingDistance` is too loose and the honest fix is to
   lower *it*, not to reinstate the second gate.

Note what did **not** change: two agreeing frames, the quality gate, and the
review gate. Nothing is ever written without a confirm.

---

## The measurement that settles the ceiling

Turn on Settings → Scanning → diagnostics and read the `d=` values on cards that
*used* to fail.

- **Clustered in 48-72** → the change did its job; leave 72 alone.
- **Clustered just past 72** (say 74-84) → raising the ceiling is defensible on
  the measured curve in `ArtMatchTuning.maxHammingDistance`'s own doc: the
  neighbour probability is flat to r=84 (1.81 %) and only cliffs at 88 (4.04 %)
  and 96 (76 %). Anything at or past 96 is noise, not a card.
- **Sharp, glare-free frames whose nearest card is still 60+** is the *other*
  hypothesis and points at the crop, not the threshold — see the `art box:` line
  below.

`ArtMatcher.bestGuesses()` (new) re-ranks the last frame **unthresholded**, so the
"Show best guesses" button now always has something to show. If its top entry is
routinely correct at distances past 72, that is the same evidence, from the other
side.

---

## Still unverified since step 16: `art box: locked`

Unchanged and still the biggest single thread. The diagnostics `art box:` line
should read **`located`**, not `fixed roi`, on a standard (non-Pendulum,
non-full-art) card. That has never been confirmed on any device. If it still says
`fixed roi`, chase that before any threshold here — recognition accuracy would
still be resting on the fixed fractions. See `docs/scan_pipeline_review.md`
finding 1.

---

## Still uncalibrated since step 18: `FrameQualityTuning`

Every threshold in it is a first guess chosen from synthetic buffers. The gate
decides whether a frame is hashed at all, so a wrong value here is the one thing
that can make recognition *worse*. Read the `qual:` line:

```
qual: sharp=182  glare=3%          a frame that passed
qual: sharp=12!  glare=2%          rejected as blurred  (! marks the failing gate)
qual: sharp=240  glare=31%  ev=-0.6   rejected as glared, exposure stepping down
```

If good frames routinely read below `minSharpness` (40), raise it or set it to 0
while tuning glare. If scanning feels *intermittent*, `maxConsecutiveSkips` (6)
firing repeatedly is the likely reason. The exposure-compensation loop is the
highest-risk part of step 18 — if `ev=` moving correlates with a black preview or
`cam: STALLED`, set `FrameQualityTuning.exposureStep = 0` to bisect it out.

---

## The overlays, which you will see immediately

- The diagnostics box now sits **directly under the app-bar icons** (the app bar
  was being counted twice in the inset) and is **capped so it can never reach the
  orange guide box**, scrolling internally instead. Type is 10pt and the capture
  affordance is now the ⤓ icon at the bottom right of the box.
- The surface hint sits **above** "Point at a card".
- Sanity-check both at a large system font size, which is where the band gets
  tight, and confirm the guide box is still exactly centred.

---

## Collection

Filters → **Set** is now a search box over the sets you actually own rather than
a chip per set. Type a partial name, pick from the list, Apply. Everything else in
the sheet is unchanged.

---

## CSV import (step 20) — what to try on device

Statistics → **Import collection from CSV**. The safest first test is the one
that should do nothing at all:

1. **Export, then immediately import the file you just exported, keeping
   entries.** Every count must be unchanged. That round trip is the property the
   default strategy is built around, and it is test-pinned both ways — the same
   file under *sum* doubles every quantity instead.
2. Then a real merge: a CSV from elsewhere. Read the confirmation dialog before
   tapping Import; it is the only point at which you can see what a file is
   about to do to the collection.

Worth watching, in rough order of likelihood:

- **`file_selector` is a new native plugin**, so it is the one part of this only
  a device can prove. If the picker will not open at all, that is the plugin, not
  the import. Its type filter is deliberately broad; if a CSV still shows greyed
  out in some provider, note which provider — the fix is another MIME type in
  `FileSelectorCsvSource._csv`.
- **"N rows skipped"** almost always means passcodes the card database does not
  have. `collection_entries.passcode` is a foreign key, so those rows genuinely
  cannot be stored. Re-sync the card database in Settings and import again.
- **"N imported without their set"** means the set code/name/rarity in the file
  matched no printing this database knows for that card. The entry is still
  imported, just without a set — worth checking what those rows actually say.

---

## Verification

```
flutter analyze                    # must be clean
flutter test                       # 464 baseline
py -3 -m pytest tools/             # 5 tests, untouched since step 18
```

---

## Still open, deliberately

`maxHammingDistance` at 72, `CardDetectionTuning.innerQuadMinAreaRatio` at 0.78,
the passcode ROI filter off (its coordinate space is genuinely wrong — the
*unrotated* sensor size is passed for boxes ML Kit reports in rotated space), and
`artAgreementFrames` at 2. That last one is now the clearest latency lever left:
it costs one frame interval (150 ms) plus a detection pass on every card, and the
quality gate already removes the motion-blur frames that were the main argument
for requiring two.
