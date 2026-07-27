# Adversarial review — scan recognition pipelines

**Date:** 2026-07-27 · **Against:** branch `scan-detection-and-collection-ux`, after
CLAUDE.md build-order step 15.

An adversarial code review of the two recognition pipelines — artwork pHash
matching (primary) and 8-digit passcode OCR (on-demand mode). Produced by a
subagent instructed to find defects rather than summarise, then **re-verified in
the main session**. Several findings rest on offline measurement against the
repo's own data (`assets/card_hashes.json`, `tools/.image_cache/`) rather than on
reasoning from the design docs.

> **Status: implemented.** Everything ranked below except finding 7 was fixed in
> the pass that followed this review (CLAUDE.md build-order step 16). This
> document is kept as the *evidence* — the measurements are what justify the
> constants now in the code — with a resolution note under each finding. The
> outcomes column records what actually happened, including the two places where
> implementing it produced a better number than the review predicted.

## Verification legend

| tag | meaning |
|---|---|
| **✅ VERIFIED** | Re-checked directly in the main session — code read, constant confirmed, or measurement reproduced. Trust these. |
| **◐ PARTLY VERIFIED** | The decisive part was re-checked; a supporting measurement was not reproduced. |
| **○ REPORTED** | The subagent's claim, not independently reproduced. Plausible, but confirm before acting. |

## Ranked findings

| # | finding | status | resolution |
|---|---|---|---|
| 1 | `artBoxRoi` is wrong; `_findArtBox` can never fire | ✅ (upgraded from ◐) | **fixed** — ROI re-measured independently at NCC 0.996-0.999, index rebuilt |
| 2 | All pHash distances are even; `13` ≡ `12` | ✅ | **fixed** — thresholds are even and the parity reason is documented at the constant |
| 3 | False-positive rates; radius 18 is not a threshold | ✅ | **fixed** — 256-bit descriptor; the same *fraction* now costs 1.37% instead of 100% |
| 4 | `scanPaused` never pauses anything | ✅ | **fixed** — `keepAlive`, with a regression test |
| 5 | OCR stream has an unbounded backlog | ✅ | **fixed** — `passcodeReadings` is self-paced; `InputImage` bytes are copied |
| 6 | `extractPasscode` synthesises 8 digits from ATK/DEF | ✅ | **fixed** — join fallback gated on digits-and-spaces |
| 7 | Nested descent lands on the printed body frame | ○ | **deliberately not fixed** — see the note under the finding |
| 8 | A dead detector isolate wedges scanning silently | ✅ | **fixed** — request timeout, `onExit`/`onError`, `det:` diagnostics line |
| 9 | Index-load failure reported as a *camera* error | ✅ | **fixed** — distinct panel; `retry()` invalidates the index |
| 10 | `_resolveArtMatch` races the stream it resolves from | ✅ | **fixed** — pause moved before the awaits |
| 11 | Debounce compares an index passcode to a DB passcode | ✅ | **fixed** — `ScanState.matchedIndexPasscode`, guard verified to fail without it |
| 12 | `_SearchRoiOverlay` is a tautology | ✅ | **fixed** — the `frame:` diagnostics line is what actually settles the aspect |
| 13 | `_DetectionPainter` uses the preview aspect on stream data | ○ | **fixed** — both painters derive from `latestArtFrame` |
| 14 | Diagnostics costs a full sort of 14 636 entries per frame | ✅ | **fixed** — bounded partial selection in `HashIndex.rank` |
| 15 | Latency budget | ◐ | informative; the `_findArtBox` note is moot now that it can fire |
| 16 | Smaller items | mixed | **fixed** (180° retry, luma skip in passcode mode, throttle/try-catch), docs corrected |

---

## 1. `ArtMatchTuning.artBoxRoi` is not the artwork's true position, so `_findArtBox` can never fire

**◐ PARTLY VERIFIED** — the aspect arithmetic, the gate constant and the source
image dimensions were re-checked directly; the pixel-level template alignment is
the subagent's measurement, but it is self-consistent (see below).

`lib/core/theme/tokens.dart:527` · `lib/features/scan/opencv_card_detector.dart:263`
· gate at `:297-301`.

The true art window was measured by aligning YGOPRODeck's own `image_url_cropped`
inside the full render by template search, across 14 sampled cards — 13 converged
on an identical box, residual ≈0.02, stdev 0.0000.

Re-checked in session: the cropped art files really are **624×624 (square)** and
the full renders **813×1185** (JPEG SOF headers, 14 390 / 14 636 files cached).

| | left | top | right | bottom | size in a 421×614 card | aspect |
|---|---|---|---|---|---|---|
| shipped `artBoxRoi` | 0.090 | 0.190 | 0.910 | 0.680 | 345 × 301 px | **1.147** |
| measured true art box | **0.1181** | **0.1814** | **0.8831** | **0.7063** | 322 × 322 px | **1.000** |

**Self-consistency check:** the measured box has a left margin of 96 px and a
right margin of 95 px in the 813-wide render — i.e. horizontally centred, which is
what a real card's art window must be. That is what makes the measurement
credible rather than a template-matching artifact.

`_findArtBox` computes `expectedAspect = (0.82 × 421) / (0.49 × 614) = 1.147` and
rejects any candidate whose aspect error exceeds `_artBoxAspectTolerance = 1.12`.
The real artwork's error is `1.147 / 1.000 = 1.147 > 1.12` → **rejected on every
standard card**. The positional gate passes (worst edge `|0.7063 − 0.68| = 0.026`,
inside `_artBoxSlack = 0.06`), so aspect is the sole killer, and it is
unconditional.

Consequences:

- `ArtFrameResult.artBox` is essentially always null, so the diagnostics line is
  permanently `art box: fixed roi`. The evidence CLAUDE.md step 14 said it needed
  is already determined by the code.
- The step-13 correction that justified loosening 10/14 → 13/18 has never run.
  CLAUDE.md's own test — *"being unable to tighten them back is evidence the
  art-box correction isn't landing"* — resolves to **it isn't landing**.
- The design is circular even if the gate passed: `_findArtBox` hunts for *the
  artwork rectangle* but must return *the ROI the index hashed*. Those are
  different rectangles today, so a successful detection would produce a crop the
  index has never seen.

**Fix:** set `artBoxRoi = Rect.fromLTRB(0.1181, 0.1814, 0.8831, 0.7063)`, mirror it
into `ART_BOX_ROI` (`tools/build_hash_index.py:70`), and **rebuild
`assets/card_hashes.json`** — mandatory, since `HashIndex.fromJson`
(`hash_index.dart:41-57`) throws at startup on a ROI mismatch.
`_artBoxAspectTolerance = 1.12` then straddles the true 1.000 correctly. No new
package. Zero CDN hits — all 14 636 images are already cached.

> **RESOLVED — and upgraded to ✅.** The alignment was re-measured independently
> before acting on it, by normalized cross-correlation of each `image_url_cropped`
> against its full render over a random sample. Every sample converged at
> **NCC 0.996-0.999** on box (96, 214-216), size **622x622**, in the 813x1185
> render: left margin 96 px, right margin 95 px, aspect 1.0016. That is the
> review's box with `top` at the midpoint of the observed range, so its value was
> adopted verbatim. `roi_pixel_box(813, 1185, ROI)` returning a 622x622 square at
> (96, 215) is now asserted in `tools/test_build_hash_index.py`, and
> `test/features/scan/hash_index_asset_test.dart` ties the committed asset to
> `ArtMatchTuning.artBoxRoi` so the pair can never drift silently again.

## 2. Every pHash distance is even — `autoMatchMaxDistance = 13` is bit-for-bit identical to `12`

**✅ VERIFIED** — reproduced directly against the shipped index.

`lib/features/scan/phash.dart:84-97` · `lib/core/theme/tokens.dart:505,516`.

`imagehash.phash` and its Dart reproduction both threshold against the **median of
the 64 DCT coefficients**, so exactly 32 bits are set in every hash. Two
equal-weight vectors always differ in an even number of positions:

```
|A ⊕ B| = |A| + |B| − 2|A ∧ B| = 64 − 2|A ∧ B|
```

Measured on `assets/card_hashes.json`: the popcount histogram over all 14 636
entries is `{32: 14636}` — every single hash, no exceptions. Confirmed
behaviourally in finding 3, where radius 12 and radius 13 return **identical**
results.

So the tuning history "raised 10 → 13" was really "raised 10 → 12", and half the
apparent tuning resolution does not exist.

**Fix:** write the constants as even numbers and note why. Cosmetic, but it stops
the next tuning pass wasting a step.

> **RESOLVED.** `maxHammingDistance = 72` and `autoMatchMaxDistance = 48` are both
> even, and `ArtMatchTuning` now carries the `|A^B| = width - 2|A&B|` argument and
> the measured popcount histogram beside them, so the next tuning pass starts from
> the reason rather than rediscovering it.

Related, from the same scan: **41 hash values are shared by 82 different cards** —
exact collisions, unresolvable by this descriptor at any radius.

## 3. False-positive rates, and why radius 18 is not a threshold at all

**✅ VERIFIED** — the empirical table was reproduced by sampling in-session.

Binomial model (64 bits, p = 0.5, 14 636 entries):

| radius | P(d ≤ r) | 1 in | E[false hits / query] | P(≥1 false hit) |
|---|---|---|---|---|
| 10 | 9.98e-09 | 100 M | 1.5e-04 | 0.015 % |
| **13** | 9.41e-07 | 1.06 M | 1.4e-02 | **1.3 %** |
| 14 | 3.54e-06 | 283 k | 5.2e-02 | 5.0 % |
| **18** | 3.09e-04 | 3 240 | 4.5 | **98.8 %** |

But real pHashes are **not** uniform bits, and the binomial is optimistic. Measured
over the actual index — subagent figures over all pairs, alongside an independent
in-session reproduction over a random 1 200-entry sample (seed 7) against all
14 636:

| radius | subagent: P(≥1 nbr) | reproduced: P(≥1 nbr) | subagent: mean nbrs | reproduced: mean nbrs |
|---|---|---|---|---|
| 10 | 1.60 % | 1.92 % | 0.018 | 0.02 |
| **12** | 7.46 % | **8.75 %** | 0.081 | 0.09 |
| **13** | 7.46 % | **8.75 %** | 0.081 | 0.09 |
| 14 | 42.8 % | 45.58 % | 0.640 | 0.69 |
| 16 | ~99 % | 94.33 % | 4.68 | 4.73 |
| **18** | **100 %** | **100.00 %** | 26.3 | **26.56** |

The two agree within sampling noise, and r=12 vs r=13 being identical is finding 2
showing up behaviourally.

**Reading:**

- **13 is defensible.** About 1 in 12 queries picks up any spurious neighbour at
  all, and `artAgreementFrames = 2` plus the non-negotiable user-confirm gate
  absorb that.
- **18 is not a "maximum plausible distance" — it is the whole neighbourhood.**
  *Every* card has at least one other card within 18, with **26.6 on average**.
  Whenever the true match lands worse than ~16, the top-5 candidate list is five
  arbitrary cards presented to the user as plausible.

If finding 1's fix lets you tighten, the empirical cliff is between 12 and 16:
`maxHammingDistance` should come down to **14 at most**, `autoMatchMaxDistance` to
**10–12**.

> **RESOLVED, but not by tightening.** The descriptor moved to 256 bits instead
> (see the descriptor section), which changes the shape of the problem rather
> than the operating point on it. Measured over the whole rebuilt index
> (14 641 entries, hs=16, measured ROI):
>
> | radius | % of bits | P(≥1 nbr) | mean nbrs |
> |---|---|---|---|
> | 24 | 9.4 % | 1.04 % | 0.011 |
> | **48** | 18.8 % | **1.20 %** | 0.014 |
> | **72** | 28.1 % | **1.37 %** | 0.017 |
> | 84 | 32.8 % | 1.81 % | 0.023 |
> | 88 | 34.4 % | 4.04 % | 0.047 |
> | 96 | 37.5 % | 76.4 % | 1.65 |
>
> So the shipped `maxHammingDistance = 72` spends *the same fraction of the width*
> the old 18/64 did — 28.1 % — at 1.37 % instead of 100 %. Exact duplicates fell
> from 41 groups / 82 entries to **26 / 52**. Popcount is `{128: 14641}`, so the
> parity argument of finding 2 survives the width change and the constants are
> written even.

## 4. `scanPausedProvider` never pauses anything — its state is discarded before it can be read

**✅ VERIFIED** — confirmed in the generated code and reproduced with a probe test.

`lib/features/scan/scan_providers.dart:105-111` (generated:
`scan_providers.g.dart:427`, `isAutoDispose: true`) · written at
`scan_controller.dart:77` · read at `art_providers.dart:177`.

This is the exact trap `ScanViewportSize` documents and defends against with
`keepAlive: true` — but `ScanPaused` has the same shape and is **not** keepAlive.
Nothing `watch`es it; both writer and reader use `ref.read`. In riverpod 3.3.2
`ProviderContainer.read` is `listen(...)` → `sub.close()` in a `finally`, and
closing the last listener schedules disposal. Nothing about a later `state =`
write removes it from the disposal queue.

Probed directly: `scanPausedProvider.notifier.set(paused: true)` followed by a
100 ms delay (one `artPollInterval`) reads back **`false`**.

Net: step 14's "skip detect+hash while a result awaits the user" optimisation is
**inert** — the worker isolate keeps detecting and hashing behind every review
panel, for readings that are discarded. `PasscodeOcrRequested` survives only
because `passcodeReadings` genuinely `ref.watch`es it (`scan_providers.dart:146`).

**Fix:** `@Riverpod(keepAlive: true) class ScanPaused`, matching `ScanViewportSize`.
`test/features/scan/art_providers_test.dart` already has the precedent for
asserting a provider stays keepAlive.

> **RESOLVED** exactly as suggested, and the precedent was followed:
> `art_providers_test.dart` gained a case that writes the flag, waits one
> `artPollInterval`, and asserts it reads back true.

## 5. The OCR stream still has the unbounded-backlog hazard step 14 fixed for artwork

**✅ VERIFIED** — both code paths read directly.

`lib/features/scan/scan_providers.dart:152` — `await for (final image in
camera.frames)` with `await ocr.read(image)` in the body, over a **broadcast**
`StreamController` (`camera_service.dart:148`). A broadcast controller buffers for
a paused subscriber, and `await for` pauses while the body awaits. If ML Kit takes
longer than `frameInterval` (300 ms) — likely at 720p on mid-range hardware — the
queue grows without bound and every passcode reading gets progressively staler.
The N-agreement counter and the M-empty-frame debounce then run over frames from
seconds ago, so a card can be re-presented well after the user removed it.

Compounding it: `_toInputImage` (`camera_service.dart:492`) passes `plane.bytes`
**without copying**, while the sibling `_toArtFrame` explicitly copies with the
comment *"the plugin may recycle this frame's buffer"*. If that comment is true, a
queued `InputImage` OCRs a later frame's pixels.

**Fix:** make `passcodeReadings` self-paced exactly like `artReadings` — poll
`frameSequence` and a cached latest `InputImage` instead of `await for` — or at
minimum drop frames while a read is in flight (`if (_busy) continue;`).

> **RESOLVED** by the first option. `CameraService` gained `latestInputImage`,
> replaced in lockstep with `latestArtFrame` under one `frameSequence`, and
> `passcodeReadings` polls it with the same `disposed`-flag structure `artReadings`
> uses. The uncopied `plane.bytes` is copied now too — with the backlog gone that
> was no longer reachable, but the sibling path had always copied and the
> asymmetry was the bug waiting to happen.

## 6. `extractPasscode` synthesises an 8-digit run from `ATK/2500  DEF/2100`

**✅ VERIFIED** code path · **○ REPORTED** trigger rate.

`lib/features/scan/passcode_ocr.dart:64-68`:

```dart
} else {
  // No isolated 8-run: try joining space-split digit groups.
  final joined = runs.join();
  if (joined.length == 8) found.add(joined);
}
```

The join fallback exists for ML Kit splitting a passcode into `"4698 6414"`. But a
monster's stat line has two 4-digit runs and no 8-run, so it joins to
`"25002100"`. Because that is a *second distinct* value alongside the real
passcode, `found.length == 2` → the function returns **null** and the frame is
discarded.

The failure is not a wrong write — the strictness holds — it is that passcode mode
silently reads *nothing* on the monsters most worth logging, whenever ML Kit groups
ATK and DEF onto one `Line`. Whether it does depends on ML Kit's gap-splitting
heuristic, hence the frequency is unconfirmed.

Everything else enumerated is safe: the copyright line has only a 4-digit year;
set codes are `LOB-EN001` (3-digit run); `1st Edition` is a 1-run and is correctly
ignored alongside a real 8-run; a second card in frame yields two distinct 8-runs →
null (correct); a misread `469B6414` joins to 7 → rejected; `469864141` is a 9-run
→ rejected.

**Fix:** only take the joined fallback when the span contains no non-digit,
non-space characters. `"4698 6414"` still joins; `"ATK/2500 DEF/2100"` no longer
does.

> **RESOLVED** as suggested (`_joinable`). Tests cover the split passcode still
> joining, the stat line no longer joining, and a stat line no longer poisoning a
> frame that also carries the real passcode.

## 7. The single nested descent lands on the card's own printed body frame for *unsleeved* cards

**○ REPORTED** — the 25-render measurement was not reproduced in-session.

`lib/features/scan/card_quad.dart:279-295` ·
`CardDetectionTuning.innerQuadMinAreaRatio = 0.78` (`tokens.dart:412`).

The printed body frame (strongest luma edge in the outer 12 % on each side),
measured across 25 cached renders, sits at **0.936 × 0.887 of the card = 0.830 of
its area** — above the 0.78 admission threshold, with card-like aspect (0.724 vs
0.686 → error 1.055, inside `aspectTolerance` 1.35), rectangularity 1.0, side
balance 1.0, tilt 0. `_collapseDuplicates` will not merge it either
(0.830 < `duplicateAreaRatio` 0.95).

So on an unsleeved card the descent steps *inward past the true outline*, and the
crop shifts from `(0.09, 0.19, 0.91, 0.68)` to `(0.115, 0.190, 0.883, 0.624)` of
the real card — ~6 % narrower, ~11 % shorter, offset. That is the same magnitude
of mis-rectification the sleeve rule exists to remove, applied to the case that
didn't need it.

The rule cannot separate the two by area alone: a YGO-size sleeve gives
card/sleeve ≈ 0.92, a penny sleeve ≈ 0.845, and the body frame is 0.830.
`innerQuadMinAreaRatio = 0.85` separates the body frame from YGO-size sleeves but
not from penny sleeves.

**Fix:** the principled one is finding 1 — with a *correct* `artBoxRoi`,
`_findArtBox` recovers the true crop regardless of which outline won, and the
descent heuristic can be dropped rather than re-tuned.

> **DELIBERATELY NOT FIXED.** This is the one finding left standing, and on its
> own reasoning: now that `artBoxRoi` is correct, `_findArtBox` can fire for the
> first time, and it recovers the true crop whichever outline won — so the right
> next step is to find out on device whether the descent still earns its keep,
> not to re-tune a threshold that may no longer matter.
> `CardDetectionTuning.innerQuadMinAreaRatio` is untouched at 0.78. The
> underlying 25-render measurement was also never reproduced (it is still ○).

## 8. A dead detector isolate wedges scanning permanently, and the diagnostics say the camera is fine

**✅ VERIFIED** — read directly.

`lib/features/scan/detector_isolate.dart:52-76`. `detectCard` registers a completer
in `_pending` and returns its future with **no timeout**, and `responses.listen`
has no `onDone` / `onError` handler. If the worker exits or `detectCardSync` hangs,
that future never completes → `PHashArtMatcher._rank` never returns →
`artReadings`'s `while (!disposed)` loop blocks forever inside
`await matcher.rankFrame(...)` and never reaches a `yield`.

The preview keeps painting, `describeCameraHealth` keeps printing
`cam: streaming f=… Δ=…ms`, and recognition is dead with no signal anywhere.
`retry()` (`scan_controller.dart:463`) does not invalidate `cardDetectorProvider`,
which is now `keepAlive` — so it is unrecoverable for the app's lifetime.

**Fix:** `.timeout(const Duration(seconds: 2), onTimeout: () => null)` on the
returned future plus `_pending.remove(id)`, and add a `detector:` line to the
diagnostics box — it currently has camera and matching lines but nothing for
detection liveness.

> **RESOLVED**, plus the cause rather than only the symptom: `onExit` and `onError`
> ports are now registered on the spawn, so a worker that dies is *noticed*
> instead of being waited out one frame at a time. Three timeouts retire the
> worker to the in-process fallback. `DetectorHealth` /
> `describeDetectorHealth` (pure, host-tested) render the new `det:` line.

## 9. An index-load failure is reported to the user as a *camera* error, and Retry can never clear it

**✅ VERIFIED** — traced directly.

`art_providers.dart:50-54` → `artMatcher` → `artReadings` →
`scan_controller.dart:50-56` routes *any* stream error to `_onCameraError`, which
renders `_CameraErrorPanel`. A `FormatException` from the ROI header check — which
finding 1's fix will produce if the index is not rebuilt in the same commit —
therefore reads as *"the camera could not be started"*.

`retry()` invalidates `cameraServiceProvider` / `scanCameraProvider` / the reading
providers but **not** `hashIndexProvider`, which is `keepAlive` and caches its
failure for the process lifetime (deliberately, per its own doc comment). So the
user gets an unfixable camera error for an asset problem.

**Fix:** discriminate the error type in `_onCameraError`, or resolve
`hashIndexProvider` separately and surface a distinct panel.

> **RESOLVED** by the first option: `ScanController.isIndexError` discriminates on
> `FormatException` and `_CameraErrorPanel` shows distinct copy naming the index —
> which also says passcode reading and search still work, since they do. `retry()`
> now invalidates `hashIndexProvider` as well, so the button is no longer a lie.
> `ScanState.copyWith` also gained `clearError`; the error was write-once-sticky.

## 10. `_resolveArtMatch` races the reading stream it is resolving from

**✅ VERIFIED** — traced directly.

`lib/features/scan/scan_controller.dart:172-199`. `_setPaused(paused: true)` runs
at `:187`, *after* `await matcher.match(...)` — which is 1–5 `getByPasscode` DB
round trips. During those awaits the artwork stream is still live and status is
still `reading`, so a single frame with `top == null` (a glare blink, the card
shifting) drives `_onArtReading`'s empty-frame branch → status `detecting` → the
resumed `_resolveArtMatch` hits its `state.status != reading` guard and **silently
discards a match the agreement gate had already accepted**.

With `artAgreementFrames = 2` and a 300 ms cadence, this is a plausible
contributor to the "hard to lock on" complaint.

**Fix:** move `_setPaused(paused: true)` to the moment the buffer reaches N, before
the awaits, and unpause on the empty-candidates path. Free once finding 4 is fixed
and `scanPaused` actually works.

> **RESOLVED** as suggested. The empty-candidates path additionally debounces the
> hash that got there, or an unresolvable run re-agrees and re-resolves every two
> frames — which is the same defect in a different place.

## 11. The debounce compares an *index* passcode against a *DB* passcode

**✅ VERIFIED** — traced directly. **Undermines the `dismissCooldown` added in step 15.**

`scan_controller.dart:134` compares `top.passcode` (`ArtReading.top` =
`result.matches.first`, an **index key**) to `state.lastConfirmedPasscode`, which
`confirm()` (`:408`) sets from `state.matchedCard!.passcode` — and `matchedCard` is
`candidates.first`, produced by `PHashArtMatcher.match`
(`art_matcher.dart:207-210`), which **skips index passcodes absent from the `cards`
table**.

The index is deliberately richer than the app DB: every `card_images[i].id` is
indexed (14 636 entries) while the DB stores only `card_images[0]`.

So whenever the nearest hash is an alt-art id the app DB doesn't hold, the
confirmed passcode ≠ the frame's top passcode, the suppression branch never
triggers, agreement rebuilds in 2 frames, and the review panel re-opens on the card
just logged — precisely the "one card logs thirty times" failure the debounce
exists to prevent. `dismiss()` (`:437-440`) has the same mismatch, so step 15's
`dismissCooldown` is keyed on a passcode that can be the wrong one.

**Fix:** carry the matched *index* passcode on `ScanState` alongside the card, and
debounce on that.

> **RESOLVED** as suggested: `ArtCandidate.rankedPasscode` carries the index key,
> `ScanState.matchedIndexPasscode` holds it for the pending match (cleared with the
> card it describes), and `confirm`/`dismiss`/`selectCandidate` all suppress on it.
> The regression test was **verified to fail** against the old `card.passcode`
> before being kept.

## 12. `_SearchRoiOverlay` is a tautology — it cannot detect a wrong ROI mapping

**✅ VERIFIED** — the algebra checks out.

`lib/features/scan/scan_screen.dart:648-674`. `_SearchRoiPainter` computes
`detectionRoiInFrame(viewport: size, frame: frame)` and then maps the result back
with `frameFractionToViewport(..., frame, size)`. Those two are exact inverses, and
the margin inflation is linear — so the drawn rectangle is **the reticle inflated
by 8 %, for any value of `frame`**, including a wrong one.

The comment claims it *"makes the mapping checkable on a real device"*; it verifies
nothing except that the clamp to [0,1] didn't bite. The one thing the project says
it most needs to check on device is the one thing this overlay cannot show.

**Fix:** derive the aspect from `cameraService.latestArtFrame` (the buffer actually
searched) rather than from the preview controller, and print both aspects in the
diagnostics box — a one-line `frame: 720x1280 (0.563) / preview 0.750` settles it
instantly.

> **RESOLVED** — both halves, and the second is the one that matters. The overlay
> keeps its round trip (it does verify the margin and the clamp) but its doc
> comment now says plainly what it cannot show, and the new `frame:` diagnostics
> line prints the stream's dimensions and aspect beside the preview's.

## 13. `_DetectionPainter` maps stream-frame fractions through the *preview*'s aspect

**○ REPORTED** — depends on device behaviour not confirmed here.

`scan_screen.dart:483-486, 540`. `DetectedCard.quad` is in fractions of the
*image-stream* frame; the painter builds `frame` from
`controller.value.aspectRatio` (the *preview* size). `camera_android_camerax
0.7.4+1` reportedly resolves `ResolutionPreset.high` to a **720×540** preview
rather than 1280×720 (flutter/flutter#145382), and CameraX picks ImageAnalysis
resolution independently of Preview.

If the two aspects differ, the outline is mis-scaled horizontally about the centre
by their ratio (0.75 vs 0.5625 → **1.33×**) while the ROI itself is correct. Since
CLAUDE.md names *"a correctly hugging outline"* as **the** on-device acceptance
test for the ROI mapping, this would send the next debugging pass after a bug that
isn't there.

**Fix:** same one-line change as finding 12.

## 14. Diagnostics mode costs a full index scan **plus a full sort** per frame

**✅ VERIFIED** — read directly.

`art_matcher.dart:187-189` → `_index.rank(hash, n: 3, maxDistance: 64)`. With
`maxDistance: 64` every one of the 14 636 entries passes the filter, so `rank`
(`hash_index.dart:95-104`) allocates 14 636 `HashMatch` objects and then **fully
sorts** them (~200 k comparisons through a closure) to take the top 3. That is
5–20 ms plus GC churn per frame, on the UI isolate — incurred exactly when someone
has turned diagnostics on to investigate why scanning feels slow.

**Fix:** a 3-element partial selection (single pass, no allocation) when `n` is
small, or reuse the already-computed thresholded list and only widen if empty.

> **RESOLVED** by the first option, applied to `rank` generally rather than just
> the diagnostics call: allocation is bounded by `n` and the admission bound
> tightens as the list fills, so an unlimited rank costs what a thresholded one
> does after the first `n`. A test compares its output against a full sort at every
> `n`, since the whole value of the change is being indistinguishable from one.

## 15. Latency budget — where the time actually goes

**◐ PARTLY VERIFIED** — the code paths were read; the per-stage timings are
estimates, not device measurements.

Per 300 ms cycle, with `ResolutionPreset.high` on CameraX:

| stage | cost | notes |
|---|---|---|
| `_onFrame` throttle rejects ~9/10 frames | ~0 | correct as written |
| `lumaFromYPlane` copy | 0.3–1 ms | 389–922 KB memcpy |
| `TransferableTypedData.fromList` → worker | 0.3–1 ms | another O(n) copy |
| **OpenCV detect (worker isolate)** | **~15–40 ms** | blur + Otsu + Canny + dilate + findContours at ≤480 px, warp to 421×614, then a **second full `_edgeMap` + `findContours`** on the warped card for an art-box pass that (finding 1) can never succeed |
| response copy back | ~0.5 ms | 258 KB warped card |
| `phashFromLuma` | ~1 ms | 32×32 area resize + 2×(8×32×32) DCT |
| `HashIndex.rank` @ d≤18 | ~1–3 ms | 14 636 XOR + 2 SWAR popcounts — **not** the bottleneck |
| `rank` @ d≤64 (diagnostics only) | 5–20 ms | finding 14 |

**Cheapest change with the largest effect: skip the `_findArtBox` call until
finding 1 is fixed.** It is a whole second Canny + contour pass over a 421×614
image — plausibly 30–40 % of detection cost — for a result that is provably always
null. After the ROI fix it earns its keep; before it, it is pure latency.

Second: fix `scanPaused` (finding 4), which stops all of the above running behind
every review panel. Third: `frameInterval` 300 ms is fine — the linear index scan
is not the problem, so there is no reason to touch it.

Lowering `ResolutionPreset` is **not** recommended: a card filling the reticle is
only 259 px wide at 4:3 / 720×540 already.

**Related sizing note for OCR:** at whole-card framing the passcode's digits are
≈5 px tall (259 px / 59 mm × 1.2 mm), far under ML Kit's stated **16×16 px per
character** minimum. Passcode mode's separate close-up reticle isn't a nicety, it
is required — but it means the two modes need genuinely different working
distances, which nothing on screen currently says.

## 16. Smaller items

- **`_toArtFrame` copies the full luma even in passcode mode**
  (`camera_service.dart:334`), where `artReadings` `continue`s and never reads it.
  ~1 MB/s of pointless allocation. Guard on `passcodeOcrRequested`. **✅ VERIFIED**
- **A card held 180° is warped upside-down with no gate.** `quadTiltDegrees` folds
  to [0, 90), so 180° reads as tilt 0 and every other gate passes; the hash is then
  garbage. Cheap mitigation: hash both the crop and its 180° rotation, keep the
  better rank. **✅ VERIFIED**
- **`_onFrame` sets `_lastEmit = now` before the conversion**
  (`camera_service.dart:326-334`), and `lumaFromYPlane` is unguarded — a
  `RangeError` from an unexpected `bytesPerRow` throws inside the plugin callback,
  so `_frames.add` never runs and OCR loses the frame too, while the throttle
  window is already spent. Wrap `_toArtFrame` / `_toInputImage` in a try.
  **✅ VERIFIED**
- **`ScanStatus` has no `matching` member** despite CLAUDE.md step 8 describing it
  as part of the freeze guard — pre-pivot doc drift, harmless, but the guard list
  at `scan_controller.dart:109-115` should be re-read against the current enum
  rather than the doc. **○ REPORTED**
- **`count` drift**: the shipped index header says `count: 14636`; CLAUDE.md says
  14 390 in four places. (Both are real: 14 636 indexed entries, 14 390 cropped-art
  files cached.) **✅ VERIFIED**

> **RESOLVED**, except where noted. The 180° gap is now covered by a re-hash of
> the rotated crop, taken only when the first pass finds nothing in range so the
> common path pays nothing (`rotate180` in `art_frame.dart`, host-tested). The
> luma copy is skipped in passcode mode via `CameraService.artCaptureEnabled`.
> `_onFrame` no longer spends the throttle window on a frame it drops, and both
> conversions are wrapped so a malformed buffer can't take the OCR path down with
> the artwork path. The `ScanStatus.matching` drift and the 14 390/14 636 count
> are corrected in CLAUDE.md.

---

## Descriptor choice — is 64-bit pHash the right tool?

**○ REPORTED** — the subagent rebuilt the index offline over a 6 000-card sample.
Not reproduced in-session, though its 64-bit column extrapolates to the in-session
measurement of finding 3 almost exactly (2.97 % → 7.46 % predicted vs 8.75 %
observed), which is a point in its favour.

| config | bits | NN dist p1 | p5 | median | ≥1 nbr at 20 % of bits | at 25 % of bits |
|---|---|---|---|---|---|---|
| A: hs=8, shipped ROI | 64 | 12 (19 %) | 14 | 16 | 2.97 % | **78 %** |
| B: hs=8, measured art box | 64 | 12 (19 %) | 14 | 16 | 2.20 % | **62 %** |
| **C: hs=16, measured art box** | **256** | **88 (34 %)** | 92 | 98 | 0.53 % | **0.57 %** |
| D: 4×(hs=8) quadrants | 256 | 78 (30 %) | 88 | 94 | 0.53 % | 0.65 % |

The conclusion is not about tuning: **at 64 bits the nearest other card sits at
only ~19 % of the bits for the worst 1 % of cards, so any error budget large enough
to survive glare and a sleeve is already large enough to hit another card.** At
`hash_size = 16` the same 1st-percentile separation is **34 %** of bits — you can
spend a 25 %-of-bits budget and still collide only 0.6 % of the time, versus
62–78 % at 64 bits. Roughly two orders of magnitude on the collision side.

**Costs and constraints:**

- **No new package.** `phash.dart` already computes an arbitrary low-frequency
  block; `kPhashHashSize = 8 → 16` and `_buildCosTable` follow. `PerceptualHash`'s
  two-lane representation must become four lanes (or a `Uint32List`), and
  `hamming.dart`'s SWAR popcount extends trivially.
- **Index rebuild required**, and `HashIndex.fromJson` must accept
  `hash_size == 16` (it currently hard-rejects anything but 8,
  `hash_index.dart:34-36,75`). Asset grows 540 KB → ~2.1 MB as hex JSON; ranking
  quadruples to ~4–12 ms, still inside the frame budget.
- **Multi-crop concatenation (D) is not worth it** — measurably *worse* than a
  plain larger hash and costs 4 resizes and 4 DCTs. Ruled out.
- **Colour moments**: rejected by the pipeline, not by merit — the Android path
  only ever receives the NV21 **Y plane** (`art_frame.dart:50`), so no chroma is
  available without switching `imageFormatGroup` and rewriting both luma helpers.
- **ORB / feature verification as a second stage over the top-N** is the one
  alternative that stays inside the stack — `opencv_core` (dartcv4 1.1.8) ships
  `ORB` and `BFMatcher`. It would resolve the 82 exact-duplicate hashes and the
  near-identical-art families no global descriptor can separate, at the cost of
  shipping reference descriptors (~1–2 KB/card × 14 636 ≈ 20 MB) or re-extracting
  from downloaded art. Much bigger than `hash_size: 16` for a smaller marginal
  gain — do it only if 256-bit pHash leaves a residue.

**Recommendation:** fix `artBoxRoi` (finding 1) and move to `hash_size = 16` in the
same index rebuild. Together they are one regeneration of
`assets/card_hashes.json`.

> **RESOLVED — both, in one rebuild, as recommended.** Two corrections to the
> table above, from measuring all 14 641 entries rather than a 6 000-card sample:
> config C's nearest-neighbour **p1 is 22, not 88** (the near-duplicate families
> that set p1 are only present in the full set), and the asset grew to
> **1.24 MB**, not the estimated ~2.1 MB. Neither changes the conclusion, and the
> second correction makes it cheaper than advertised.
>
> The migration's real risk — "the 192 extra bits are high-frequency and so
> noisier, and error budgets won't scale" — was checked rather than assumed, and
> is false for the perturbations that matter here. The Tier-2 fixture (an
> area-average resize standing in for PIL's LANCZOS over the real art crop)
> measures **[2, 2, 4] of 256**, the same handful of bits as at 64 — a *lower*
> fraction. That is why `phash_e2e_test`'s gate stays at 12 rather than scaling
> to 48: scaled, it could no longer detect a regression.
>
> ORB second-stage verification remains unexplored, correctly — 26 residual
> duplicate groups is a much smaller problem than the one just solved.

---

## Geometry worked numerically

**○ REPORTED** — the arithmetic below is the subagent's; it was spot-checked but
not fully re-derived in-session.

Setup: viewport 1080×2340 (aspect 0.4615), 4:3 sensor delivering an upright
540×720 frame.

**`reticleRectInViewport`**: width `1080 × 0.78 = 842.4`; height
`842.4 × 86/59 = 1227.9`, under `maxHeight = 2340 × 0.62 = 1450.8` → kept. Rect =
(118.8, 556.05) → (961.2, 1783.95).

**`detectionRoiInFrame`'s cover inverse**: cover scale
`max(1080/540, 2340/720) = 3.25`; displayed 1755 × 2340; `originX = −337.5`,
`originY = 0`. Reticle → frame fractions **(0.260, 0.2376) → (0.740, 0.7624)**,
i.e. 0.48 of the frame's width from 0.78 of the screen's — exactly the 48 %
CLAUDE.md claims. In pixels the reticle is 259 × 378, ratio 0.686 = 59/86 ✓. With
`reticleRoiMargin = 0.08` the search region is (0.2216, 0.1956) → (0.7784, 0.8044)
= 401 × 438 px, and a filled reticle is **0.743** of it — `targetRoiAreaFraction =
0.75` is correct as written ✓. Long edge 438 < `_workLongEdge` 480, so no downscale
at all on a 4:3 device.

**The preview-vs-stream aspect question is a false alarm**, and worth stating
explicitly because it looks like a bug. If the preview is 4:3 and the analysis
stream is 16:9, the two are centre-crops of one another. For a portrait viewport
(`a_v = 0.4615`, below both), cover maps viewport fraction `u` to frame fraction
`0.5 + (u − 0.5)·(a_v/a)`. Preview → scene → stream gives
`0.5 + (u − 0.5)·(a_v/a_p)·(a_p/a_s) = 0.5 + (u − 0.5)·(a_v/a_s)` — precisely what
`detectionRoiInFrame` computes from the stream's own aspect. **The ROI is
self-correcting under any sensor-aspect mismatch**, provided neither source
letterboxes (impossible on a phone: every upright sensor aspect ≥ 0.5625 > 0.4615).
Verified at 16:9: (0.180, 0.2376) → (0.820, 0.7624), and 0.48/0.75 = 0.64 ✓.

The mismatch only breaks the *painters* (findings 12, 13), which use the preview
aspect on stream-space data.

**Corner ordering and the ±25° gate — sound.** At 45° the ordered corners are the
four extremes, `_meanWidth` / `_meanHeight` are the true side lengths, so aspect
(0.686) and rectangularity (1.0) both pass — but `quadTiltDegrees` reads 45 and
rejects ✓. At 90° the ordering is correct for the landscape rectangle and aspect
flips to 1.457 → error 2.12 > 1.35, rejected ✓. The gap is 180° (finding 16).

**ML Kit rotation compensation — correct.** `camera_service.dart:470-480` matches
the camera-plugin / ML-Kit reference recipe verbatim, and step 14's fallback to the
bare sensor orientation on an unmapped `deviceOrientation` is right. The same
`rotationDegrees` feeds `_rotateCode` in the detector
(`opencv_card_detector.dart:337-342`), where 90 → `ROTATE_90_CLOCKWISE` matches
`ArtFrame`'s "clockwise degrees to appear upright" contract ✓.

**NV21 row stride — correct.** `lumaFromYPlane` reads `height` rows of `width`
bytes at `bytesPerRow`, exactly the Y plane's layout in a single-plane NV21 buffer;
the same `bytesPerRow` goes to `InputImageMetadata`, so the two paths agree by
construction.

**`_decodeResponse` dropping `rotationDegrees` is correct.** `detectCardSync`
always returns `DetectedCard.image` with `rotationDegrees: 0`
(`opencv_card_detector.dart:191`) — the warped card is by definition upright. The
port omission matches. Fragile only in that nothing enforces it; an `assert` would
be cheap.

---

## Passcode ROI — what re-enabling it would require

Leaving it off was the **right call as written**, and for a stronger reason than
the doc gives:

1. **The coordinate space is wrong.** `MlKitPasscodeOcr.read` passes
   `frameSize: image.metadata?.size` — the **unrotated** sensor size (1280×720).
   ML Kit reports `boundingBox` in the coordinates of the image *after* applying
   `InputImageMetadata.rotation`. So `extractPasscode` would divide x by 1280 when
   the boxes live in a 720-wide space, and y by 720 when they run to 1280 —
   normalized y routinely > 1. The fix is to pass the *upright* size, swapping
   w/h when rotation is 90 or 270.
2. **The documented ROI is now the wrong corner.** `passcode_ocr.dart:40-43` still
   says "bottom-left", but since step 12 passcode mode draws `_PasscodeReticle` —
   a 0.42 × 0.07 box at the **centre** — and tells the user to aim just the code at
   it. A bottom-left ROI would reject exactly what the UI asks for. The ROI should
   be the passcode reticle mapped through the same `viewportToFrameFraction` cover
   math the artwork path uses.
3. **There are no ML Kit knobs to fall back on.** `google_mlkit_text_recognition
   0.16.0` exposes exactly one option:
   `TextRecognizer({TextRecognitionScript script = TextRecognitionScript.latin})`.
   No dense-text mode, no single-line mode, no digit whitelist, no ROI. Everything
   must be done by pre-cropping the `InputImage` or post-filtering boxes. Given
   that, a correct ROI filter is the *only* available precision lever — and it
   would fix finding 6 for free, since ATK/DEF sits bottom-right while the passcode
   is bottom-left.

---

## Checked and found genuinely correct

- **The reticle → frame cover mapping is self-correcting** under a preview/stream
  aspect mismatch (algebra above). The pipeline's scariest silent-failure candidate,
  and it is fine.
- **`ScanReticleTokens` / `ScanDetectionTokens` / `CardDetectionTuning` are
  numerically consistent**: at `reticleRoiMargin = 0.08` a filled reticle is 0.743
  of the search region and `targetRoiAreaFraction` is 0.75. Step 14's reasoning
  checks out exactly.
- **Limited-range NV21 luma vs PIL `convert('L')` is harmless.** Camera Y is
  `16 + 0.859·L` — affine. The DCT is linear, so all AC coefficients scale by 0.859
  and only DC picks up an offset; the median (dominated by AC) scales identically,
  every `b[i] > med` comparison is preserved, and DC stays far above the median
  regardless. The pHash is exactly invariant. This *looks* like an index/runtime
  mismatch and isn't.
- **`TransferableTypedData.fromList` copies** (only the transferable is neutered by
  sending, not the source list), so `_rank`'s whole-frame retry re-sending the same
  `raw.luma` is safe.
- **The whole-frame retry's guard is correct** — `searchRoi !=
  ArtMatchTuning.cardSearchRoi` compares `Rect` by value, so host tests (null
  viewport) correctly skip the retry rather than detecting twice.
- **`frameSequence` de-duplication in `artReadings`** genuinely prevents one
  physical frame from satisfying `artAgreementFrames` on its own, and the explicit
  `disposed` flag is necessary exactly as documented (a `continue` never reaches
  the `yield`).
- **`PerceptualHash`'s two-lane parse and SWAR popcount** are correct, and avoiding
  `int.parse('ffffffffffffffff', 16)` is a real trap correctly avoided.
- **The ROI header check in `HashIndex.fromJson`** is the right shape of guard with
  sensible tolerance — it is what will catch you if you change `artBoxRoi` without
  rebuilding.
- **`_ViewportProbe`, `_ReticleOverlay` and `_FullBleedPreview` all read
  `constraints.biggest` of the same `StackFit.expand` body**, so the drawn box, the
  searched box and the published viewport genuinely cannot drift.
- **`evaluateCardQuad`'s gate ordering and bounded 0..1 score terms** are sound; the
  `_collapseDuplicates` → single-descent sequencing does what its comment says. The
  problem is the threshold value (finding 7), not the structure.
- **`_tickSuppression` / `dismissCooldown` vs `emptyFrameCount`** — step 15's
  separation is correct, and `copyWith` zeroing the cooldown alongside
  `clearLastConfirmedPasscode` closes the obvious inconsistency. (But see finding
  11 for the passcode it is keyed on.)
- **`PHashArtMatcher._lastResult` is not stale in practice.** `match()` reads it
  synchronously before its first `await`, and `_resolveArtMatch`'s only preceding
  await is an already-resolved provider future (a microtask), while the polling
  loop is gated behind a 100 ms timer — so no `rankFrame` can interleave before the
  read. The `?? await rankFrame(...)` fallback is unreachable on the live path.
- **`hashIndexProvider` / `cardDetectorProvider` `keepAlive`** (step 15) does not
  leak across screens beyond the ~2–3 MB already accounted for; `PHashArtMatcher`
  and `CameraScanService` remain autoDispose and are rebuilt per visit.

---

## What was left open

Three things, all deliberate and all needing a device rather than more analysis:

- **Finding 7's nested descent** — see the note there. `innerQuadMinAreaRatio`
  stays 0.78 until the now-live `_findArtBox` shows whether it still matters.
- **The passcode ROI filter** stays off. Its coordinate space is genuinely wrong
  (`MlKitPasscodeOcr.read` passes the *unrotated* sensor size for boxes reported
  in rotated space) and the documented corner is stale, but it is off in
  production and finding 6's fix addresses the failure that was actually biting.
- **`HashIndex.hashes` as 14 641 separate `Uint32List`s.** A flat
  `Uint32List(n * 8)` plus a `passcode -> offset` map would be one allocation
  with linear locality in `rank`'s hot loop. It changes a constructor signature
  used by ~11 test sites, and `rank` was never the bottleneck (~1-3 ms against a
  15-40 ms detect), so it is noted rather than done.

## Suggested order

1. **Finding 4** — `scanPaused` keepAlive. One annotation, verified defect, and it
   makes finding 10's fix free.
2. **Finding 11** — index-vs-DB passcode in the debounce. Undermines both the
   post-confirm debounce and step 15's `dismissCooldown`.
3. **Findings 6, 8, 9, 16** — small, self-contained, each a verified defect.
4. **Findings 1 + descriptor `hash_size: 16`** — one index rebuild, together.
   Biggest accuracy lever, and the only item that changes the matching core. It
   also enables tightening 13/18 toward 12/14 (finding 3) and makes finding 7's
   heuristic droppable.
5. **Findings 12/13** — the diagnostics aspect line, which is what makes the next
   on-device pass trustworthy.

Verify the step-15 changes on hardware before starting item 4.

## Sources

- [flutter/flutter#152763 — CameraX image stream randomly stopping](https://github.com/flutter/flutter/issues/152763)
- [flutter/flutter#145382 — ResolutionPreset.high gives 720x540 on CameraX](https://github.com/flutter/flutter/issues/145382)
- [ML Kit text recognition v2 — input image guidelines](https://developers.google.com/ml-kit/vision/text-recognition/v2/android)
- [google_mlkit_text_recognition TextRecognizer API](https://pub.dev/documentation/google_mlkit_text_recognition/latest/google_mlkit_text_recognition/TextRecognizer-class.html)
- [Hamming distributions of popular perceptual hashing techniques](https://www.sciencedirect.com/science/article/pii/S2666281723000100)
- [A comparative study of perceptual hashing algorithms](https://ceur-ws.org/Vol-2904/81.pdf)
- [dart:isolate TransferableTypedData](https://api.flutter.dev/flutter/dart-isolate/TransferableTypedData-class.html)
