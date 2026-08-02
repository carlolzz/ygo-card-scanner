# Next session: calibrate the frame-quality gate on device

**Written:** 2026-08-03 · **Against:** branch `scan-detection-and-collection-ux`
(CLAUDE.md build-order step 18).

**Baseline to start from:** `flutter analyze` clean, **384** tests green,
`pytest tools/` green.

`CLAUDE.md` step 18 has the full background. This file covers only what is *not*
written down there: what to look at on the phone, in what order, and why.

---

## The one thing that must happen before anything else

**Every threshold in `FrameQualityTuning` is a first guess.** They were chosen
from synthetic buffers, because that is all a host test can offer. The gate they
control decides whether a frame is hashed at all, so a wrong value here is the
one change in step 18 that can make recognition *worse* rather than better.

Turn on Settings → Scanning → diagnostics and read the new **`qual:`** line:

```
qual: sharp=182  glare=3%          a frame that passed
qual: sharp=12!  glare=2%          rejected as blurred  (! marks the failing gate)
qual: sharp=240  glare=31%  ev=-0.6   rejected as glared, exposure stepping down
```

Point at a card you *know* the app used to recognise and watch `sharp=`:

- **If good frames routinely read below `minSharpness` (40)** the gate is too
  strict and is throwing away usable frames. Raise it, or drop it to 0 to switch
  blur rejection off entirely while you tune glare.
- **If a visibly smeared frame reads well above 40**, it is too loose and is
  doing nothing. Lower it.
- `maxGlareFraction` (0.08) is the same exercise against an Ultra/Secret rare
  under a lamp.

The safety net is `maxConsecutiveSkips` (6): after six rejections in a row the
gate stops rejecting, so even a badly wrong threshold degrades to step 17's
behaviour rather than wedging. If scanning feels *intermittent* rather than
broken, that failsafe firing repeatedly is the likely reason — check `qual:`.

---

## Then: which of the two hypotheses is actually true

The 40–90 distances that prompted this step have two candidate explanations, and
until now nothing on screen could tell them apart:

1. the photograph is bad (blur / foil glare), or
2. the **crop is landing in the wrong place**, so a perfectly good photograph is
   hashed over the wrong pixels.

`qual:` and `art box:` together settle it. **A sharp, glare-free frame whose
nearest card still ranks at 60 is hypothesis 2** — and that points straight at
the item below, which has been open since step 16 and is still unverified.

---

## Still unverified since step 16: `art box: locked`

The diagnostics `art box:` line should read **`locked`**, not `fixed roi`, on a
standard (non-Pendulum, non-full-art) card.

That has never been confirmed on any device. Step 16 corrected an
`ArtMatchTuning.artBoxRoi` whose 1.147 aspect made `OpenCvCardDetector._findArtBox`
reject on every standard card unconditionally, so the art-box correction had
never once fired. If it still says `fixed roi`, that is a bigger thread than any
threshold here and should be chased first — recognition accuracy would still be
resting on the fixed fractions. See `docs/scan_pipeline_review.md` finding 1.

---

## Exposure compensation: watch for the CameraX risk

This is the highest-risk change in step 18. It issues real
`setExposureOffset` calls on a device whose camera stack is the least reliable
part of the app (see the `camerax-image-stream-instability` memory).

Watch for: the preview going black, the `cam:` line reading `STALLED`, or `r=`
climbing. If any of that correlates with `ev=` moving, the fastest bisect is to
set `FrameQualityTuning.exposureStep = 0`, which makes `nextExposureOffset`
return the current value forever and takes the platform call out of the loop
without removing any other part of the gate.

---

## Capture samples while you are there

The diagnostics box now has a **`[ save this frame ]`** button. It writes the
rectified card and its art crop as PGM plus a JSON sidecar and opens the share
sheet.

Grab 5–10 on genuinely hard cards — Secret Rares under a lamp, sleeved cards,
anything that reads `card detected, frame poor` or ranks far away while looking
fine. That corpus is the precondition
`.claude/skills/scan-pipeline.md` sets before *any* image preprocessing
(highlight normalisation, CLAHE, a wider art-box search) can honestly be
evaluated — and preprocessing is the next real lever on accuracy, since the
descriptor and the index are already as good as measurement has made them.

PGM opens directly in PIL/OpenCV, so `tools/` can analyse them with the same
`Image.open` the index builder uses.

---

## Collection UX to sanity-check

Nothing here is risky, but it is all new on device:

- the standard list is unchanged; both grid modes render and the choice survives
  leaving the screen (it is persisted in `meta`);
- the filter sheet composes with the search box, Reset keeps the query, and the
  filter button's count matches what is applied;
- the Set picker now sits **above** condition/edition/language in both the scan
  review gate and the collection edit sheet, so the keyboard no longer covers
  the controls below it — this was the reported annoyance;
- the surface hint no longer collides with "Point at a card".

---

## Verification

```
flutter analyze                    # must be clean
flutter test                       # 384 baseline
pytest tools/                      # 5 tests, untouched by step 18
```

**App name**: if the launcher still reads `ygo_scanner`, that is a stale install,
not a source bug — the manifest has been correct since `7bccff3`. `flutter clean`,
uninstall the package, reinstall.

---

## Still open, deliberately

`autoMatchMaxDistance`/`maxHammingDistance` at 48/72,
`CardDetectionTuning.innerQuadMinAreaRatio` at 0.78, the passcode ROI filter off
(its coordinate space is genuinely wrong — the *unrotated* sensor size is passed
for boxes ML Kit reports in rotated space), and `artAgreementFrames` at 2.
That last one is worth revisiting **only after** the quality gate is calibrated:
the gate now removes the motion-blur frames that were the main argument for
requiring two, so the trade may look different than it did in step 17.
