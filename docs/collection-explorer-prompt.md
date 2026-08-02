# Project: YGO Collection Explorer

> **This file specifies a separate project.** It lives in the scanner's repo only
> because the scanner produces this project's input. Nothing here is built in
> Flutter and nothing here is built in this repository.
>
> The input contract below is **derived from the code that writes the CSV** —
> `lib/data/export/collection_csv.dart` in this repo. That file, not this
> document, is the authority. If they disagree, read it and fix this.

A local web app for browsing, analyzing and valuing my Yu-Gi-Oh card collection.

The collection itself is catalogued by a separate Flutter app (a camera scanner
that recognizes cards by artwork, or reads the 8-digit passcode, and logs them to
SQLite). That app exports its collection table to CSV. This project consumes that
CSV. It is **read-only**: the scanner app is the single source of truth for what I
own, and nothing here ever writes back to it.

---

## Input data contract

A single CSV, one row per collection entry — a distinct stack of the same card in
the same condition/edition/language/printing. Treat this schema as a contract and
validate it on load: **fail loudly on a missing or renamed column** rather than
silently producing wrong numbers.

**The export has exactly these twelve columns, in this order:**

| # | column | type | notes |
|---|---|---|---|
| 1 | `passcode` | text | 8 digits. **Leading zeros are significant — never parse as int** |
| 2 | `name` | text | apostrophes, hyphens, `&`, `#`, accented chars. See the apostrophe guard below |
| 3 | `set_code` | text | e.g. `LOB-EN001`. **Empty when the card was logged without a printing** |
| 4 | `set_name` | text | empty under the same condition |
| 5 | `rarity` | text | empty under the same condition |
| 6 | `condition` | text | `MINT`, `NEAR_MINT`, `EXCELLENT`, `GOOD`, `LIGHT_PLAYED`, `PLAYED`, `POOR` (Cardmarket order, best→worst) |
| 7 | `edition` | text | `FIRST`, `UNLIMITED`, `LIMITED` |
| 8 | `language` | text | `EN`, `DE`, `FR`, `IT`, `SP`, `PT`, `JP`, `KR`, `AE` — free-form, so treat unlisted values as valid |
| 9 | `quantity` | int | ≥ 1 |
| 10 | `notes` | text | free text, often empty |
| 11 | `created_at` | text | **UTC ISO-8601**, e.g. `2026-07-28T09:41:02.000Z` |
| 12 | `updated_at` | text | same |

### Five things that will bite you if you skip them

**1. The card's own attributes are NOT in the CSV.** There is no `type`,
`frame_type`, `attribute`, `race`, `atk`, `def`, `level`, `archetype` or
description column. The export carries *ownership* facts, not *card* facts.

Design around this with two sources rather than trying to widen the export:

- **The CSV is the ownership ledger** — what I own, how many, in what condition,
  edition, language and printing.
- **YGOPRODeck's bulk `cardinfo.php` dump is the card catalogue** — type, frame
  type, attribute, race, atk/def/level, archetype, description, image URLs, **and
  `card_prices`**. Join it to the CSV on `passcode`, cache it on disk.

This is not a workaround, it's the better architecture: the dump has to be
downloaded for pricing anyway, so every card attribute the filter bar and the
statistics need arrives at **zero additional request cost**, and it stays current
without re-exporting the collection. A card in the CSV with no matching dump entry
must still appear in the UI (name and ownership are known) with card attributes
shown as unknown — never dropped.

**2. Timestamps are UTC ISO-8601 strings, not epoch milliseconds.** The scanner's
*database* stores epoch ms; the exporter converts on the way out. Parse them as
timestamps. (If you ever read the scanner's SQLite file directly instead, *then*
you'll be dealing with epoch milliseconds — that caveat belongs to that path, not
to the CSV.)

**3. Missing values are empty strings, never a NULL token.** `set_code`,
`set_name`, `rarity` and `notes` are written as `''` when absent. DuckDB will read
them as empty strings, so **normalize `''` → NULL in the loading view**, once, up
front. Skip this and every "cards with no printing" predicate silently matches
nothing while looking correct.

**4. A leading apostrophe may have been added to `name` and `notes`.** The
exporter guards against CSV formula (DDE) injection: any field starting with `=`,
`+`, `-`, `@`, tab or CR is prefixed with `'` so spreadsheets treat it as text. In
practice only `name` and `notes` can trigger it — numbers, enum codes and ISO
timestamps never start with those characters. Strip a single leading `'` from
those two columns on load.

**5. There is no row id and no `printing_id`.** A row's natural identity is
`(passcode, set_code, set_name, rarity, condition, edition, language)` — the
scanner's UNIQUE key with the surrogate printing id projected away. Rows are
already deduplicated by the scanner; do not attempt to merge them further.

### And the two counting rules to design around from the start

- A card appears in several rows (different condition, edition, or printing).
  "How many cards do I own" is `SUM(quantity)`. "How many distinct cards" is
  `COUNT(DISTINCT passcode)`. **Never conflate them**, and never let a UI label
  be ambiguous about which one it's showing.
- `set_code` is frequently empty. **Any per-printing logic must degrade to
  per-passcode rather than dropping the row** — including valuation, which is
  where it matters most.

The format itself: RFC 4180, `\r\n` line endings, no BOM, header row always
present, fields containing a comma/quote/CR/LF quoted with internal quotes
doubled.

---

## Stack

- Python 3.12+, `uv` for dependency management
- **FastAPI** for the API
- **DuckDB** as the query engine, reading the CSV directly. Polars for anything
  DuckDB is awkward at. No ORM, no Postgres — the dataset is thousands of rows,
  not millions
- **Vite + React + TypeScript** frontend
- A charting library of your choice, picked once and used consistently
- `pytest` for the Python side

---

## Features

**1. Browse.** A card grid showing real artwork, with a detail view: stats and
card text (from the dump), the printings I own, and the
condition/edition/language breakdown per copy.

**2. Filter and search.** Name (diacritic- and case-insensitive), type, frame
type, attribute, race, level, archetype, set, rarity, condition, edition,
language. Filters compose; the URL reflects the filter state so a view is
shareable and bookmarkable. Ownership filters come from the CSV, card-attribute
filters from the joined dump — the user should never be able to tell which.

For name search, fold both sides with Unicode NFKD and drop combining marks
before comparing, so `Necrovalley` and `Nécrovalley` are the same query. Do this
in one named function, not inline at each call site.

**3. Statistics.** Totals (copies, distinct cards, sets represented);
distribution by condition, type, attribute, archetype, set; acquisition over time
from `created_at`; and the long tail — which cards I hold the most copies of.

**4. Valuation, on demand.** See the next two sections; this is the feature with
the most design in it.

---

## Valuation — explicitly user-triggered, never automatic

Two actions, both initiated by a click and nothing else:

- **"Calculate value"** on a single card's detail view — values that card's
  rows.
- **"Calculate collection value"** on the valuation page — values everything.

Nothing fetches a price on page load, on scroll, on filter change, or on a
timer. A price that appears without being asked for is a bug, not a convenience:
it makes the request volume a function of how the user browses, which is exactly
what the API rules below forbid.

### The cost model, which is better than it looks

`card_prices` is part of the single bulk `cardinfo.php` dump. So **once that dump
is cached on disk, valuing the entire collection costs zero network requests** —
it is a local join between the CSV and the cached dump, plus a condition
multiplier. "Calculate collection value" should complete in well under a second
on a few thousand rows and must not show a progress bar pretending otherwise.

The only per-row network work is the optional **per-printing refinement**:
`cardsetsinfo.php?setcode=LOB-EN001` returns a printing-specific `set_price`,
which is strictly better than the per-passcode number where a `set_code` is
known. That is the one thing that needs a job:

- a bounded-concurrency worker queue behind a **token-bucket limiter well under
  20 req/s**;
- **progress reported to the UI** as `n / total` with the current set code;
- **cancellable** mid-run, leaving already-fetched snapshots intact;
- **resumable** — a re-run skips `(passcode, set_code)` pairs that already have a
  fresh snapshot, so an interrupted run costs only what it hadn't done;
- **no retry storm.** A failed set code is recorded as failed with its reason and
  moved past. At most one retry, on a genuine transient (timeout, 5xx), after a
  fixed delay. Never a loop.

Rows with no `set_code` are simply valued at passcode level — they are not errors
and must not be excluded from the total.

### The UI must say it's an estimate

YGOPRODeck's `card_prices` are **per passcode, not per printing or rarity**, so a
Secret Rare and a Common of the same card get the same number unless a `set_price`
refinement landed for that printing. Every total therefore shows:

- that it is an estimate, in plain words, next to the number — not in a footnote;
- **how many rows were priced per-printing vs per-passcode**, and how many
  couldn't be priced at all;
- the currency, explicitly (see below);
- how old the underlying price data is.

A confidently wrong total is worse than an obviously approximate one.

---

## Pricing — design this as pluggable from day one

Define a `PriceProvider` protocol and implement providers behind it. Do not
scatter provider-specific code through the app.

```python
class PriceProvider(Protocol):
    name: str
    def price(self, passcode: str, set_code: str | None = None) -> Money | None: ...
    def prices(self, keys: Sequence[tuple[str, str | None]]) -> dict[tuple[str, str | None], Money | None]: ...
```

The batch method is not optional sugar: the YGOPRODeck provider is dump-backed,
so a one-at-a-time interface would be an actively misleading API shape for it,
and the whole-collection path only makes sense in batch.

- **YGOPRODeck** — the only source that works with no credentials, so build this
  one first and make the app fully functional on it alone. Prices come from the
  cached bulk dump; `cardsetsinfo.php` provides the per-printing refinement.
- **Cardmarket** — implement as a stub raising a clear "needs credentials" error.
  Their API requires a registered app and OAuth, granted on request; assume I
  don't have it until I say otherwise.
- **TCGplayer** — same treatment. Public API access has been partner-gated; check
  the current state before building against it.

### Money and currency

**All money is a single `Money` type with an explicit currency.** This is not
pedantry — YGOPRODeck mixes currencies inside one response:

| field | currency |
|---|---|
| `cardmarket_price` | **EUR** |
| `tcgplayer_price` | **USD** |
| `ebay_price` | **USD** |
| `amazon_price` | **USD** |
| `coolstuffinc_price` | **USD** |

Summing across those silently produces a confidently wrong total. Rules:

- A valuation run picks **one** source field, and therefore one currency, and
  records which.
- Never convert implicitly. Either present per-currency totals side by side, or
  convert through an **explicit, dated FX rate stored alongside the result** so a
  saved valuation can always be re-explained. An implicit 1:1 is forbidden.
- Amounts are stored as integer minor units or `Decimal`, never float.

### Condition modulates value

A Poor copy is not worth a Near Mint copy's price. One named multiplier table, in
one module, **clearly labelled a heuristic**:

```python
CONDITION_MULTIPLIERS = {   # heuristic, tune from real sales; not a source of truth
    "MINT":         1.05,
    "NEAR_MINT":    1.00,   # the reference grade — YGOPRODeck prices approximate NM
    "EXCELLENT":    0.90,
    "GOOD":         0.75,
    "LIGHT_PLAYED": 0.65,
    "PLAYED":       0.50,
    "POOR":         0.40,
}
```

All seven grades, in Cardmarket order. An unknown grade is an error, not a
silent 1.0. Edition (`FIRST` vs `UNLIMITED`) also moves price in reality; do
**not** invent a multiplier for it — surface edition in the breakdown and leave
it unmodelled rather than guessed.

### Snapshot store

Store every price fetched in a local DuckDB/Parquet table:

```
(passcode, set_code, provider, currency, source_field, amount, fetched_at, status)
```

Two reasons, both load-bearing: it caches aggressively against a rate-limited
API, and it makes "collection value over time" possible later without
re-deriving history you never recorded. Therefore:

- **Every price fetch goes through this layer.** No provider is ever called
  directly from a request handler.
- A **staleness rule**, named in one place: snapshots newer than N days are
  reused; older ones are refetched only when the user asks. The UI shows
  "priced 12 days ago" so the number is never mistaken for live.
- Failures are recorded too (`status`), so a resumed run knows the difference
  between "not tried" and "tried and unavailable".
- Rows are append-only. Never update a snapshot in place — that is the history.

---

## API usage rules — non-negotiable

From YGOPRODeck's API guide (`ygoprodeck.com/api-guide/`). Read it before writing
any client code; it changes.

- **Fetch the full card dump once**, not per card. It's a single several-MB
  request covering ~13k cards. Cache it on disk with a timestamp; re-fetch on
  explicit demand, never on page load.
- Rate limit is roughly **20 requests/second**. Respect it with a real limiter
  shared by every provider, and never build a retry storm.
- **Do not hotlink card images.** Download each image once into a local cache
  directory, keyed by passcode, and serve it from there. This is an explicit
  requirement in their guide, and it's also what makes the UI fast. Bounded
  concurrency, resumable, a placeholder for art that 404s. (The scanner app
  already does exactly this and it works — reuse the shape, not the code.)
- Card art is not mine to redistribute — this stays a local, personal tool.

---

## Non-goals

- Deck building or `.ydk` export — EDOPro already does this well.
- Editing the collection. Changes happen in the scanner app; this reads its
  export.
- Card scanning or recognition of any kind.
- Multi-user support, auth, or public deployment.

---

## Build order

1. **CSV loader + schema validation + DuckDB views**, with tests over a small
   fixture CSV. Get the "how many cards do I own" family of questions provably
   right before any UI exists.
2. **Bulk dump client + on-disk cache + the passcode join**, so card attributes
   exist for everything downstream. Prices come along for free in the same file.
3. **FastAPI read endpoints**: list with filters, single card, aggregate stats.
4. **Frontend shell**: card grid, filter bar, detail view, URL-driven filter
   state.
5. **Image cache**: bulk download, local serving, missing-art placeholder.
6. **Statistics views and charts.**
7. **Valuation**: provider protocol, YGOPRODeck implementation, snapshot store,
   condition multipliers, the two "Calculate value" actions, the per-printing
   refinement job, and the estimate caveat in the UI.
8. **Cardmarket / TCGplayer adapters** — only if credentials materialize.

### Acceptance criteria for step 1

Before any UI, a fixture CSV plus tests must pin all of:

- a missing or renamed column **raises**, naming the column;
- `SUM(quantity)` and `COUNT(DISTINCT passcode)` on a fixture where they differ,
  asserted separately;
- a passcode with a leading zero survives the round trip **as a string**;
- an empty `set_code` reads as NULL and is still counted in every total;
- a `name` beginning with `'` has exactly one apostrophe stripped;
- `created_at` parses to the expected UTC instant.

---

## Standing rules

- The CSV is read-only input. Never write to it.
- Passcodes are strings, always. Leading zeros are real.
- All money is a `Money` with an explicit currency. Never sum across currencies.
- Every price fetch goes through the snapshot/cache layer; no provider is called
  directly from a request handler.
- Nothing hits the network except in response to an explicit user action or an
  explicit cache refresh.
- The CSV supplies ownership; the cached dump supplies card attributes. A row
  present in one and absent from the other is displayed, not dropped.
