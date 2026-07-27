# Next session: artwork-recognition latency

**Written:** 2026-07-28 · **Against:** branch `scan-detection-and-collection-ux`
at commit `6e9959d` (CLAUDE.md build-order step 16).

**Baseline to start from:** `flutter analyze` clean, **321** tests green,
`pytest tools/` green.

`CLAUDE.md` step 16 and `docs/scan_pipeline_review.md` have the full background.
This file only covers what is *not* written down there: the task, the reasoning
that makes it safe now when it wasn't before, and the one thing to measure first.

---

## The problem

On device, identifying a card takes **1–2 seconds**. Most of that is waiting, not
computing. A match needs `ScanTuning.artAgreementFrames = 2` agreeing frames, and
frames arrive every `ScanTuning.frameInterval = 300 ms`:

```
300 ms   wait for the first frame after the card lands
+  D     detect + hash + rank          (frame 1)
+ 300    throttle to the next frame
+  D     detect + hash + rank          (frame 2)  → agreement reached
+  M     match(): up to 5 serial DB reads
+ 0-100  artPollInterval jitter
```

≈ **700 ms + 2D + M** before anything can appear on screen — of which **~600 ms is
pure throttle**, with nothing computing.

Note that `D` probably *rose* in step 16, in two ways introduced deliberately: the
256-bit DCT is 8× the multiply-adds of the old 64-bit one, and `_findArtBox` — a
second Canny + contour pass over the rectified card — can now actually fire for the
first time. Both were the right calls for accuracy, but neither is free.

---

## Measure before changing anything

The scan diagnostics overlay (Settings → Scanning, or the bug icon on the scan
screen) now shows a **`det:`** line reading e.g. `det: isolate  87ms`. That is how
long one detect + hash pass takes — the `D` above.

**This decides whether change (2) is worth doing at all.** `artReadings` is
self-paced: it polls `CameraService.frameSequence` and works on the newest cached
frame, so the loop naturally runs at `max(frameInterval, D)`. If `D` is already
≥ 150 ms, lowering `frameInterval` to 150 ms buys **nothing**, and the real cost is
inside detection instead. Do not tune this constant blind.

---

## Change 2 — `frameInterval` 300 ms → 150 ms

`lib/core/theme/tokens.dart`, `ScanTuning.frameInterval`.

This has been listed "still open" since step 13, each time with the reason *"the
linear index scan is not the problem, so there is no reason to touch it."* That
reasoning was about **throughput**; the cost the user actually feels is **latency**.

Three things that made it genuinely unsafe before are now fixed:

- detection runs on a worker isolate (step 14), so a faster cadence no longer
  competes with Flutter painting the preview;
- `scanPaused` genuinely pauses (step 16) — it was `autoDispose` and therefore
  inert, so a faster cadence would previously have meant more wasted work behind
  every review panel;
- `artReadings` polls rather than subscribing, so it **cannot** build a backlog the
  way an `await for` over a broadcast stream could.

Expected saving: ~300 ms, subject to the `det:` measurement above.

---

## Change 3 — batch the DB reads in `match()`

`lib/features/scan/art_matcher.dart`, in `PHashArtMatcher.match()` (~line 210).

It currently `await`s `CardRepository.getByPasscode` **once per candidate** — up to
`ArtMatchTuning.candidateCount` (5) serial round trips through the sqflite isolate.
This sits *after* the agreement gate, so all of it is perceived latency.

Collapse to one `WHERE passcode IN (?,?,?,?,?)`:

- new batched method on `lib/data/db/dao/card_dao.dart`;
- a passthrough on `lib/data/repositories/card_repository.dart`;
- `match()` preserves ranked order and still **skips passcodes absent from the
  `cards` table** — that skip is load-bearing (the index keys every
  `card_images[i].id`, the DB stores only `card_images[0]`), and
  `ArtCandidate.rankedPasscode` must keep carrying the index key or the debounce
  regresses. See `ScanState.matchedIndexPasscode`.

Project rules that apply: **no SQL outside `lib/data/db/`**, and **every DAO method
gets a test before the feature that consumes it**.

---

## Do *not* change `artAgreementFrames` (2 → 1) as part of this

It would halve the remaining wait, and the statistical case for 2 is much weaker
than it was — with the 256-bit descriptor only ~1.2 % of cards have a spurious
neighbour within `autoMatchMaxDistance`, where at 64 bits the gate was meaningless.

But frame agreement also rejects **motion blur and mid-movement frames**, which no
amount of descriptor width helps with. Only revisit if it still feels slow after
changes 2 and 3, and treat it as a quality trade rather than a free win.

---

## Separate, more important, still unverified

The diagnostics **`art box:`** line should now read **`locked`** rather than
`fixed roi` on a standard (non-Pendulum, non-full-art) card.

That has never been true on any previous build: step 16 corrected an
`ArtMatchTuning.artBoxRoi` whose 1.147 aspect made `_findArtBox` reject on every
standard card, unconditionally, on every device. See
`docs/scan_pipeline_review.md` finding 1.

**If it still says `fixed roi` on device, that is a bigger thread than latency and
should be chased first** — it would mean the corrected ROI is not reaching the
detector, and recognition accuracy is still resting on the fixed fractions.

Two related items are also still deliberately open, both needing hardware rather
than analysis: `CardDetectionTuning.innerQuadMinAreaRatio` (still 0.78 — find out
whether the now-live `_findArtBox` makes the nested descent unnecessary before
re-tuning it), and the passcode ROI filter (still off; its coordinate space is
genuinely wrong — the *unrotated* sensor size is passed for boxes ML Kit reports in
rotated space).

---

## Verification

```
flutter analyze                    # must be clean
flutter test                       # 321 baseline; expect more with the new DAO test
```

Then on device: re-read the `det:` line to confirm the cadence change landed, and
time a few identifications by feel against the 1–2 s starting point.
