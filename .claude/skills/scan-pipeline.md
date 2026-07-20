# Scan Pipeline

Write this file now; the implementation lands in a later session.

## State machine

`IDLE → DETECTING → READING → MATCHED → CONFIRMED → IDLE`

- **DETECTING**: a card-shaped quadrilateral is present and stable across N consecutive frames (start with N=3). Stability means corner positions move less than a small threshold — this rejects motion blur before wasting an OCR pass.
- **READING**: crop the passcode region from the perspective-corrected frame, OCR it, require 8 digits.
- **MATCHED**: database hit. Show the card, its art, and the condition chips.
- **CONFIRMED**: user accepts. Write to the database.

## Debounce

After a CONFIRMED, the same passcode is rejected until the frame has gone empty — no card detected for M consecutive frames (start with M=5). Without this, one card scans thirty times in two seconds. This rule is not optional and must not be relaxed to make demos feel faster.

## Confidence and fallback

- OCR returning fewer or more than 8 digits is a failure, not a partial result. Do not pad or truncate.
- Two disagreeing reads across consecutive frames → discard both and keep reading. Only accept when consecutive frames agree.
- On repeated OCR failure, fall back to perceptual-hash matching against the artwork crop. Return the top-3 candidates with distances and let the user pick — do not silently auto-select the nearest.
- If both paths fail, offer manual search prefilled with anything legible. Never log a card the app is guessing at.

## Non-negotiable UX rule

Every scan result is reviewable and editable before it reaches the database. The app never writes a row the user did not see. A collection silently corrupted by misreads is worse than no scanner at all, because the user has no way to know which entries to distrust.

## Performance

Process every Nth frame, not every frame. Run detection and OCR off the UI isolate. Target a sustained scan rate of roughly one card per second in the hand — the bottleneck is the human flipping cards, so optimize for stability over raw throughput.

## Sleeves and glare

Sleeved cards are the common case, not the exception. Expect specular highlights over the passcode region. Multi-frame agreement is the mitigation; do not add aggressive image preprocessing before you have real failure samples to test against.
