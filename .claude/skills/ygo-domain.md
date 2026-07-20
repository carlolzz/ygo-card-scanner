# YGO Domain

Yu-Gi-Oh domain facts. Consult before writing any recognition, parsing, or card-model code.

## Passcodes

- 8 digits, printed bottom-left on the card face. Leading zeros are significant — store as TEXT, never INTEGER.
- Not universal: Token cards, Skill cards, most tournament/prize promos, and some very early printings have no passcode. The data model must tolerate a null passcode on the scan path even though `cards.passcode` is the primary key — unmatched scans go to a manual-resolution flow, not a crash.
- The passcode identifies the card, not the printing. Alternate artworks usually share a passcode; a few have their own.

## Set codes

- Format is `SET-LLNNN`, e.g. `LOB-EN001`, `SDK-001` (older English printings omit the language block), `RA01-EN001`.
- Printed bottom-right on modern cards. This is the second OCR target and the only way to distinguish printings of the same card.
- The two-letter language block: EN, DE, FR, IT, SP, PT, JP, KR, AE (Asian-English).

## Rarity codes

C Common, R Rare, SR Super Rare, UR Ultra Rare, ScR Secret Rare, UtR Ultimate Rare, GR Ghost Rare, PScR Prismatic Secret Rare, StR Starlight Rare, QCScR Quarter Century Secret Rare. The YGOPRODeck API returns full names, not codes — map on ingest.

## Editions

1st Edition is marked by text under the set code. Unlimited has no marking — absence of the marking is the signal, so never infer edition from OCR confidence alone. Limited Edition is stamped in gold/silver.

## YGOPRODeck API shape

`GET https://db.ygoprodeck.com/api/v7/cardinfo.php` returns `{ "data": [...] }`, roughly 13,000 entries, several MB. Each entry contains nested arrays that must be flattened:

- `card_sets[]` → one printings row each (set_code, set_name, set_rarity)
- `card_images[]` → multiple artworks per card; `id` on each image differs from the card id for alternate arts
- `card_prices[]` → ignore for v1

Rate-limited to roughly 20 requests/second. Fetch the full dump once, not per-card. Respect it; do not add a retry storm.

## Naming traps

Card names contain apostrophes, hyphens, ampersands, accented characters, and #. Always use parameterized SQL. Search must be diacritic- and case-insensitive.
