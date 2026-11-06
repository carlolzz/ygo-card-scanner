# YGO Scanner

A mobile app for cataloguing a physical Yu-Gi-Oh card collection. The user
points the camera at a card, the app reads the 8-digit passcode printed in
the bottom-left corner, looks it up in a local SQLite database, and logs it
to their collection along with a condition grade. Manual search-and-add is a
permanent first-class alternative to scanning, not a fallback.

## Stack

Use exactly this, do not substitute.

- Flutter (stable channel), Dart 3, null-safe
- sqflite for storage — no ORM, no drift, hand-written DAOs with raw SQL
- riverpod (flutter_riverpod + riverpod_annotation + riverpod_generator) for state management
- go_router for navigation
- freezed + json_serializable for models
- dio for HTTP
- camera + google_mlkit_text_recognition for the scan pipeline
- sqflite_common_ffi for running DAO tests on the host

"Do not substitute" governs the choices above: nothing here gets swapped for an
equivalent. Packages have been *added* where the list covers no equivalent at
all, each recorded in the build-order step that added it — `path_provider` and
`path` (file paths, step 5), `opencv_core` (the artwork-first pivot),
`share_plus` (getting exports and scan samples off the device, steps 10/18),
`file_selector` (opening a user-chosen file, step 20) and the SDK's
`flutter_localizations` (Italian for Material's own text — the Back tooltip, the
copy/paste toolbar — step 34; it pulls in `intl` transitively, but app code
still never imports `intl`). A new one needs that same justification: a
capability none of the above provides.

Generated code (`*.freezed.dart`, `*.g.dart`) is gitignored, not committed.
Regenerate with `dart run build_runner build --delete-conflicting-outputs`
after editing any annotated class.

## Directory layout

```
lib/
  main.dart
  app.dart
  core/
    theme/app_theme.dart
    theme/tokens.dart
    constants.dart                    # AppStrings, English + Italian
    money.dart
    result.dart
  data/
    assets/localized_names.dart     # the bundled card-name asset, parsed
    db/
      database.dart
      migrations.dart
      dao/card_dao.dart
      dao/card_name_dao.dart
      dao/printing_dao.dart
      dao/collection_dao.dart
      dao/card_price_dao.dart
      dao/meta_dao.dart
    api/ygoprodeck_client.dart
    api/card_image_downloader.dart
    repositories/card_repository.dart
    repositories/collection_repository.dart
    repositories/settings_repository.dart
    repositories/price_repository.dart
    seed/fake_collection_seed.dart
    export/csv_writer.dart            # escaping, shared by both writers
    export/collection_csv.dart        # writer  ┐ one format,
    export/collection_csv_parser.dart # reader  ┘ one directory
    export/collection_value_csv.dart  # the value breakdown: write-only
    export/collection_exporter.dart
    import/collection_import_plan.dart  # the pure merge rule
    import/collection_importer.dart
    import/csv_file_source.dart         # the file-picker seam
  models/
    ygo_card.dart
    printing.dart
    collection_entry.dart
    collection_entry_with_card.dart
    card_condition.dart
    card_edition.dart
    card_language.dart
    card_prices.dart
    card_search_hit.dart
    collection_sort_by.dart
    app_settings.dart
    app_theme_mode.dart
    app_language.dart
  features/
    home/
    scan/
    collection/
    add_card/
    card_search/
    pricing/
    statistics/
    sync/
    settings/
  shared/widgets/
    card_thumbnail.dart
    card_details_view.dart
    card_search_subtitle.dart
    search_language_picker.dart
    search_field.dart                 # the search box with a clear button
    justified_wrap.dart               # a Wrap whose rows fill the width
    justified_wrap_layout.dart        # its packing arithmetic, pure
test/
  data/db/
  data/repositories/
  data/seed/
  models/
  features/
  shared/widgets/
tools/
  build_hash_index.py
  build_localized_names.py
assets/
```

## Database schema (version 5)

```sql
CREATE TABLE cards (
  passcode      TEXT PRIMARY KEY,
  name          TEXT NOT NULL,
  type          TEXT,
  frame_type    TEXT,
  attribute     TEXT,
  race          TEXT,
  atk           INTEGER,
  def           INTEGER,
  level         INTEGER,
  description   TEXT,
  image_url     TEXT,
  local_image_path TEXT, -- v2
  archetype     TEXT
);
CREATE INDEX idx_cards_name ON cards(name);

CREATE TABLE printings (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  passcode      TEXT NOT NULL REFERENCES cards(passcode) ON DELETE CASCADE,
  set_code      TEXT,
  set_name      TEXT,
  rarity        TEXT,
  UNIQUE(passcode, set_code, rarity)
);
CREATE INDEX idx_printings_passcode ON printings(passcode);

CREATE TABLE collection_entries (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  passcode      TEXT NOT NULL REFERENCES cards(passcode),
  printing_id   INTEGER REFERENCES printings(id),
  condition     TEXT NOT NULL,
  edition       TEXT NOT NULL DEFAULT 'UNLIMITED',
  language      TEXT NOT NULL DEFAULT 'EN',
  quantity      INTEGER NOT NULL DEFAULT 1 CHECK(quantity > 0),
  notes         TEXT,
  created_at    INTEGER NOT NULL,
  updated_at    INTEGER NOT NULL,
  UNIQUE(passcode, printing_id, condition, edition, language)
);
CREATE INDEX idx_entries_passcode ON collection_entries(passcode);

CREATE TABLE card_prices (          -- v3, rebuilt in v4
  passcode      TEXT PRIMARY KEY REFERENCES cards(passcode) ON DELETE CASCADE,
  cardmarket    REAL,               -- EUR
  tcgplayer     REAL,               -- USD
  updated_at    INTEGER NOT NULL
);

CREATE TABLE printing_prices (      -- v4
  printing_id   INTEGER PRIMARY KEY REFERENCES printings(id) ON DELETE CASCADE,
  price         REAL,               -- USD; NULL = asked, no figure
  updated_at    INTEGER NOT NULL
);

CREATE TABLE card_names (          -- v5
  passcode      TEXT NOT NULL,     -- NO foreign key, deliberately
  language      TEXT NOT NULL,     -- this app's code ('IT'), not the API's
  name          TEXT NOT NULL,
  PRIMARY KEY (passcode, language)
);
CREATE INDEX idx_card_names_name ON card_names(name);

CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT);
```

Notes:

- `PRAGMA foreign_keys = ON` on every connection open, in `onConfigure` —
  never `onOpen`, never inside a transaction.
- Timestamps are epoch milliseconds, integers.
- The UNIQUE constraint on `collection_entries` is load-bearing: adding a
  card that already exists in the same condition/edition/language must
  increment `quantity`, not create a second row. **Subtlety**: SQLite
  treats every `NULL` as distinct under `UNIQUE`, so `printing_id IS NULL`
  rows (very common — manual add without a chosen printing) cannot rely on
  `INSERT ... ON CONFLICT DO UPDATE`; `CollectionDao.addOrIncrement`
  branches to a manual find-or-insert for that case. See
  `lib/data/db/dao/collection_dao.dart`.
- `printings.passcode` cascades on delete; `collection_entries.printing_id`
  does not (no `ON DELETE` action) — deleting a printing that still has
  collection entries pointing at it is rejected, by design, so a user's
  logged cards are never silently orphaned.
- Migrations are an ordered map of version -> list of SQL statements in
  `lib/data/db/migrations.dart`, so v2+ can be appended later. `schema_version`
  is mirrored into the `meta` table alongside sqflite's own `user_version`.
  v2 added `cards.local_image_path` (see `lib/data/db/dao/meta_dao.dart` for
  the DAO — a plain get/set(key, value), REPLACE semantics); v3 added the
  `card_prices` cache; v4 dropped and recreated it without eBay/Amazon/
  CoolStuffInc and added `printing_prices`; v5 added `card_names`.
- **`card_names` has NO foreign key to `cards`, and that is the point.** Every
  other child table here cascades from `cards` because `CardDao.insertAll` uses
  `ConflictAlgorithm.replace` and a re-sync re-inserts every card row — right
  for `printings` and the two price caches, which arrive in that same response.
  These names do not: they are imported from a bundled asset
  (`assets/card_names_it.json`, built by `tools/build_localized_names.py`), so a
  cascade would mean re-reading and re-inserting ~11.6k rows after every sync to
  end up exactly where we started. A name row whose passcode has no `cards` row
  is harmless — the search joins, so it never surfaces. The import is stamped in
  `meta` under `localized_names_<lang>` with the asset's version.
- **Both price tables are caches, and a re-sync deliberately empties them.**
  `CardDao.insertAll` uses `ConflictAlgorithm.replace`, i.e. `INSERT OR
  REPLACE`, which *deletes and re-inserts* each `cards` row — so every child row
  with an `ON DELETE CASCADE` goes with it, exactly as already happens to
  `printings` and to `cards.local_image_path`. That is wanted here: prices from
  before a re-sync are the most stale ones. Every row is re-fetchable, so
  nothing in either table is user data.
  For `printing_prices` the cascade is **load-bearing for correctness, not just
  hygiene**: `printings.id` is AUTOINCREMENT and `printings` cascades from
  `cards`, so a re-sync *re-keys* every printing — a price row that outlived its
  printing would silently describe a different set and rarity.
- **Per-set prices ARE stored, since v4** (this reverses the v3 decision).
  YGOPRODeck's card-level figures are documented as "the lowest price found
  across multiple versions of that card", and measurably so: `cardmarket_price`
  is €0.02 for Blue-Eyes White Dragon, Dark Magician and Mirror Force alike. The
  per-set `card_sets[].set_price` is the real figure (CT13-EN008 Blue-Eyes =
  $74.49) and arrives in the *same response*, so caching it costs no extra
  requests. It is **USD only** — there is no per-set Cardmarket price and never
  will be — so the collection's euro total remains a card-level floor and is
  labelled as one everywhere it appears. A `printing_prices` row with a NULL
  `price` means "asked, no figure" and is deliberately written: without it the
  TTL check could never be satisfied for such a printing and its card would be
  re-fetched on every valuation forever.
- `meta` also carries a `last_sync` key (epoch ms), written at the end of
  `CardRepository.sync()`'s transaction. `CardRepository.needsSync()`
  treats a missing `last_sync` OR an empty `cards` table as "needs sync" —
  see the first-launch sync gate below.
- **Passcodes are language- and rarity-independent** (see
  `yu_gi_oh_tcg_passcodes.md`): the same card in English and German shares one
  8-digit passcode, and so do two rarities of the same print. The schema
  already handles this without a language/rarity column on `cards`: `language`
  is part of the `collection_entries` UNIQUE key, so language variants are
  distinct **rows under one passcode** (a card owned in EN and DE is two
  entries, one `cards` row); rarity is carried by `printings` and separated via
  `printing_id`. No migration was needed to support multi-language collections.

## Enum persistence rules

Enums persist by name (SCREAMING_SNAKE via `toDb()`/`fromDb()`), never by
ordinal/index.

`CardCondition` (Cardmarket order, best -> worst, `sortOrder` = declaration
order):

| member | shortCode | label | db value |
|---|---|---|---|
| mint | MT | Mint | MINT |
| nearMint | NM | Near Mint | NEAR_MINT |
| excellent | EX | Excellent | EXCELLENT |
| good | GD | Good | GOOD |
| lightPlayed | LP | Light Played | LIGHT_PLAYED |
| played | PL | Played | PLAYED |
| poor | PO | Poor | POOR |

`CardEdition`:

| member | label | db value |
|---|---|---|
| first | 1st Edition | FIRST |
| unlimited | Unlimited | UNLIMITED |
| limited | Limited Edition | LIMITED |

## Build order

1. **Data layer + models + DAO tests** ← done
2. **Design tokens, theme, home menu shell** ← done (home menu is a fixed non-scrolling 2x2 `Row`/`Column` grid, not `GridView` — a scrollable grid pushed two tiles off-screen on short viewports; see `lib/features/home/home_screen.dart`. Routing via `go_router` — `lib/core/router.dart`/`routes.dart`. Unbuilt destinations render `shared/widgets/coming_soon_screen.dart`.)
3. **Collection screen against seeded fake data** ← done (list with search/condition/edition filters and sort, detail view with quantity +/- and delete; see `lib/features/collection/`. Fixture cards/entries live in `lib/data/seed/fake_collection_seed.dart`, auto-seeded in debug builds via a `kDebugMode`-gated, idempotent Riverpod provider — inert once step 4/5 provide real data. **Gotcha for future widget tests**: any widget test that resolves a Riverpod provider backed by the real DB must wrap interactions in `tester.runAsync()` *and* interleave real `Future.delayed` yields with `tester.pump()` — `sqflite_common_ffi` resolves queries via a background isolate, and plain `pump()`/`pumpAndSettle()` never gives it real wall-clock time to complete, even inside `runAsync()` alone. See the `pumpUntilSettled` helper in `test/features/collection/collection_screen_test.dart`.)
4. **Manual add-card flow** ← done (single wizard screen at `AppRoutes.scan`/`lib/features/add_card/add_card_screen.dart` — search step → printing step (skipped when `PrintingDao.getForPasscode` returns empty, and always has an explicit "skip / I don't have this printing" button) → condition/edition/quantity step → save, then resets to search for the next card. State lives in `AddCardSelectionController` (`lib/features/add_card/add_card_providers.dart`), not widget state, so the printing-skip logic and save/reset behavior stay out of `build()`. No new DAO/repository methods were needed — reuses `CardDao.searchByName`, `PrintingDao.getForPasscode`, `CollectionRepository.addOrIncrement`. **Gotcha**: any provider that reads from the DB (including this flow's search provider) must `await ref.watch(debugSeedCollectionProvider.future)` before querying, or it can run before the debug seed has populated the DB if that screen is opened before the Collection screen ever was — see `addCardSearchResultsProvider`. Along with this step, `CollectionEntryWithCard` was extended to `LEFT JOIN printings` and carry a nullable `Printing?`, so `collection_list_tile.dart`/`collection_detail_screen.dart` can now show which expansion a card is from — previously the schema tracked this per-entry but no UI surfaced it.)
5. **YGOPRODeck sync with progress UI, run on first launch** ← done
   (verified: `flutter analyze` clean + full `flutter test` green, 81 tests).
   `test/features/sync/app_gate_test.dart` exercises the real `App` widget
   end-to-end through the gate — sync screen first on a fresh db, then swaps to
   Home once sync completes; and Home immediately when already synced. Its
   earlier hang had **nothing** to do with the `MaterialApp(home:)` →
   `MaterialApp.router` gate swap (a red herring from a prior session): the
   real cause was opening the `sqflite_common_ffi` db **inside the testWidgets
   body** (the fake-async zone), which hangs the test at teardown — the db must
   be opened in `setUp` (a real-async zone), exactly like every DAO/collection
   test. Chasing it also surfaced and fixed the same latent bug in
   `card_thumbnail_test.dart` (its real file I/O + `Image.file` decode now run
   inside `tester.runAsync()`). See the new section in
   `.claude/skills/flutter-test-troubleshooting.md`. `App`'s `_SplashScreen`
   was also made animation-free (no indeterminate spinner), matching
   `InitialSyncScreen`'s transitional-state convention. Ahead of
   this step, card image download/display was built as its own pass (not a
   numbered step, but load-bearing for later steps too): YGOPRODeck's API
   guide prohibits hotlinking card art, so `CardRepository.ensureImageDownloaded`
   downloads a card's image to `<app documents>/card_images/<passcode>.jpg`
   the first time it's needed (via `lib/data/api/card_image_downloader.dart`)
   and persists the local path on `cards.local_image_path`. The trigger is
   `CollectionRepository.addOrIncrement` itself (fire-and-forget,
   exception-swallowing) — so it fires for every current and future path
   that logs a card (manual add today, camera/OCR in step 7 later) without
   further wiring, and the image is never fetched or shown during the
   manual add-card wizard, only after a card is actually in the collection
   (`lib/shared/widgets/card_thumbnail.dart`, wired into
   `collection_list_tile.dart`/`collection_detail_screen.dart`).
   For the sync itself: `CardRepository.sync()` (already scaffolded from
   step 1) now reports real two-phase progress — `SyncPhase.fetching` via
   Dio's `onReceiveProgress` (0-70%), `SyncPhase.writing` via chunked
   1000-row `CardDao.insertAll` batches (70-100%) — still inside one
   `_database.transaction`, so only progress *reporting* is granular, not
   the write's atomicity. `lib/features/sync/initial_sync_providers.dart` /
   `initial_sync_screen.dart` gate the app: on first launch (`needsSync()`
   true), `lib/app.dart` renders `InitialSyncScreen` directly — no router —
   until sync succeeds; failure shows an error + Retry with no skip
   (the app has no usable data without `cards` populated). **The gate is
   bypassed in debug builds** (`debugSyncBypassProvider`, defaults to
   `kDebugMode`) so a fresh dev/emulator install isn't forced through a
   real network sync before reaching Home, preserving the offline
   fixture-seed workflow from step 3 — the bypass is itself overridable via
   Riverpod, since `flutter test` always runs with `kDebugMode == true` and
   `test/features/sync/app_gate_test.dart` needs to force real gate
   evaluation. `debugSeedCollectionProvider` (step 3) was also updated to
   skip once `!needsSync()` — a real sync only ever populates
   `cards`/`printings`, never `collection_entries`, so without this check
   it would silently overwrite real synced rows for the fixture passcodes.
   **Gotcha**: `test/support/widget_test_harness.dart`'s `pumpApp()` pumps
   `MaterialApp.router` directly, bypassing `App`/the sync gate entirely —
   this is intentional (every other existing screen test relies on it) but
   means the gate itself is only exercised by `app_gate_test.dart`, which
   pumps the real `App` widget instead.
6. `tools/build_hash_index.py` — download all card art, compute pHashes, emit
   `assets/card_hashes.json` ← done (host-side Python build tool, not shipped
   in the app). Single bulk `cardinfo.php` fetch (same endpoint as
   `lib/data/api/ygoprodeck_client.dart`), then computes
   `imagehash.phash(hash_size=8)` → 16-hex-char string. (**Step 16 moved this to
   `hash_size=16` → 64-hex-char, 256-bit hashes, and re-measured `ART_BOX_ROI`;
   the shipped index is v3.**)
   **The shipped index is v2**: it downloads each artwork's **full** image
   (`image_url`) and hashes the `ART_BOX_ROI` crop of it — the same fractional
   window of a canonical upright card that the runtime crops
   (`ArtMatchTuning.artBoxRoi`), so index and runtime hash the same function of
   the same region. (v1 hashed YGOPRODeck's own `image_url_cropped`, a
   differently-shaped art crop — a systematic mismatch. The two constants must
   stay in sync; since step 13 `HashIndex.fromJson` **enforces** that by
   validating the `roi` header the file carries, so drift fails loudly at
   startup instead of quietly degrading every distance.)
   **Alt-arts**: every entry in a card's `card_images` array is indexed by its
   **own** `id` (its own passcode), so the index is richer than the app DB
   (which stores only `card_images[0]`). Output is a wrapper object
   (`version`/`algorithm`/`hash_size`/`generated_at`/`count`/`hashes`) so
   step 8 can validate algo+size before Hamming-comparing; `hashes` is a
   sorted `passcode -> hex` map for stable diffs. **API-policy-driven design**
   (`ygoprodeck.com/api-guide/`, documented in `tools/README.md`): images are
   downloaded once into `tools/.image_cache/` (gitignored) with a conservative
   default throttle (`--workers 4` + `--delay`), never hotlinked; re-runs and
   `--incremental` make **zero** CDN hits; the shipped JSON is derived hashes,
   not redistributed art. Pure functions (`build_image_jobs`, `build_output`)
   have offline pytest coverage (`tools/test_build_hash_index.py`, no network);
   `requests`/`Pillow`/`imagehash` in `tools/requirements.txt` are lazy-imported
   so the tests run without them. Full run produced **14390/14636 hashes**
   (246 skipped — genuine 404s where YGOPRODeck has no cropped variant; 0 hash
   failures). `assets/card_hashes.json` is a **committed generated artifact**,
   registered under `flutter: assets:` in `pubspec.yaml` for step 8;
   regenerate when the card DB changes. Verified: offline pytest green,
   `flutter analyze` clean, re-run byte-stable except `generated_at`.
7. Camera + ML Kit passcode OCR, continuous-scan state machine ← done
   (verified: `flutter analyze` clean + full `flutter test` green, 98 tests).
   **Navigation**: `/scan` now renders the camera `ScanScreen`
   (`lib/features/scan/scan_screen.dart`); the manual add-card wizard moved to
   a new `AppRoutes.addCard` = `/add-card`. The "Log Cards" home tile is
   unchanged (still `/scan`) — scanning is primary, manual search is a
   first-class alternative reached from the scan screen's keyboard toolbar
   action and its OCR-miss fallback. Because the tile no longer opens the
   wizard, `add_card_screen_test.dart` now pumps `AddCardScreen` directly under
   a `ProviderScope`/`MaterialApp` instead of tapping through Home.
   **Detection = reticle-guided ROI, not quad detection** (decided with the
   user): the approved stack has no contour/perspective library ("do not
   substitute"), so the UI shows a guide box and the spec's "stable
   quadrilateral across N frames" is realized as **N=3 consecutive agreeing
   8-digit OCR reads** (`ScanTuning.agreementFrames`). This satisfies the
   multi-frame-agreement rule without out-of-stack image processing.
   **Two injectable seams** (mirroring `_FakeCardRepository`), so the state
   machine runs with no hardware in tests: `CameraService`
   (`camera_service.dart` — real `CameraScanService`; its constructor does
   **no** platform work, all hardware access is in `start()`, so merely reading
   the provider in a test is inert; `CameraImage → InputImage` uses the
   canonical nv21/bgra single-plane + rotation-compensation recipe) and
   `PasscodeOcr` (`passcode_ocr.dart` — pure, offline-testable `extractPasscode`
   + ML-Kit-backed `MlKitPasscodeOcr`). They compose into
   `passcodeReadingsProvider` (`Stream<PasscodeReading>`), the **single provider
   tests override** with a fake stream. **State machine**: `ScanController` +
   `ScanState` (`scan_controller.dart`/`scan_state.dart`), modeled on
   `InitialSyncController` — `detecting → reading → matched → confirmed →
   detecting`, plus `unknown` (agreed read, no db hit) and `error` (camera
   failure) branches. Enforces the spec: strict 8-digit-or-fail (no
   pad/truncate; a frame yielding two different 8-digit values is ambiguous →
   null), disagreement discards the run, **M=5 empty frames of debounce**
   (`ScanTuning.debounceEmptyFrames`) after a confirm so one card doesn't log
   thirty times, and — non-negotiable — nothing is written until the user
   reviews the match and taps Confirm. Confirm logs via
   `CollectionRepository.addOrIncrement` with `printingId` null (a scanned
   quick-log carries no printing, like the manual add's skip path), which
   auto-fires the art download. `ScanState.ocrFailureStreak` is the reserved
   hook for step 8's pHash fallback (currently unknown → manual search, since
   only the passcode is OCR'd, so there is no legible name to prefill).
   **Gotcha**: Riverpod 3.x removed the `Raw` typedef, and a `StreamProvider`
   value-dedups (`AsyncData(null) == AsyncData(null)`), which would swallow
   consecutive identical reads and break the N-agreement/M-empty counters —
   `PasscodeReading` is therefore a plain class with **identity** equality, so
   every frame delivers to the controller's `ref.listen`. Tuning/reticle
   constants live in `lib/core/theme/tokens.dart` (`ScanTuning`,
   `ScanReticleTokens`); strings in `lib/core/constants.dart`. **Native
   config**: Android `CAMERA` permission + `uses-feature` (`required=false`),
   `minSdk` floored to 21 for ML Kit, iOS `NSCameraUsageDescription`.
   The bottom-left **ROI filter is implemented and unit-tested but left OFF in
   production** (`extractPasscode` called with `roi: null`): ML Kit bounding
   boxes are in rotated sensor space and mapping that back to an on-screen
   corner reliably needs real device samples we don't have yet — so we rely on
   the strict 8-digit uniqueness (the passcode is the only 8-digit run on a
   card) plus the reticle, echoing the skill's own caution against premature
   preprocessing. **Lifecycle**: `ScanScreen` is a `ConsumerStatefulWidget` +
   `WidgetsBindingObserver` purely to toggle `scanCameraActiveProvider`, which
   releases the camera when backgrounded and restarts it on resume; no
   transition logic lives in the widget.
8. pHash art-matching fallback for OCR misses ← done
   (verified: `flutter analyze` clean + full `flutter test` green, 147 tests).
   **User-triggered "Match by artwork", ranked candidates, never auto-log**
   (decided with the user): a runtime Dart pHash is *not* bit-identical to the
   Python-built index, so matching ranks the nearest cards and the user picks —
   the pick funnels into the same non-negotiable `matched` review gate +
   `confirm()` a scan uses. **Reproducibility, computed from the camera luma
   plane with NO new package** (the other locked decision): `lib/features/scan/
   phash.dart` reproduces `imagehash.phash(hash_size=8)` — separable DCT-II
   (`dct(dct(P,axis=0),axis=1)`, only the 8x8 low-freq block computed), median
   threshold (DC included), row-major MSB-first bit-pack — validated by a
   **two-tier offline spike** (`tools/dump_phash_fixtures.py` +
   `test/features/scan/fixtures/`): Tier 1 (identical 32x32 PIL pixels →
   `phash_test.dart`) matches the index **exactly, distance 0**; Tier 2 (full
   source luma through our own area-average resize → `phash_e2e_test.dart`) had
   a **gap of 0** on clean art — so the only production gap is handheld
   glare/angle/crop, which the top-N + `ArtMatchTuning.maxHammingDistance` (14)
   budget absorbs. `lib/features/scan/hamming.dart` stores a hash as two 32-bit
   lanes (`int.parse('ffffffff…',16)` is an overflow trap; also web-safe) with a
   SWAR popcount; `hash_index.dart` parses/validates the bundled
   `assets/card_hashes.json` (rejects non-`phash`/wrong size) and `rank`s.
   **Frame acquisition**: `CameraService` gained `latestArtFrame` (an `ArtFrame`
   = luma + dims + rotationDegrees), cached each throttled frame in
   `CameraScanService._onFrame` via pure `lumaFromYPlane` (NV21 Y-plane, strips
   row stride, always copies since the plugin recycles buffers) /`lumaFromBgra`
   (iOS 601 luma) in `art_frame.dart`; rotation is shared with the OCR path via
   `_rotationDegrees`. The **art-box ROI** (`ArtMatchTuning.artBoxRoi`,
   normalized fractions of the *upright* card — Pendulum/full-art crop
   imperfectly, acceptable for a fallback) is applied to `frame.oriented()`
   before hashing. **Seams** (mirroring `cameraService`/`passcodeOcr`):
   `hashIndexProvider` (loads the asset via `rootBundle`; tests override with an
   in-memory `HashIndex`) and `artMatcherProvider` (`PHashArtMatcher` composing
   camera+index+repo; **the single provider controller-transition tests
   override** with a fake). **State machine**: two new `ScanStatus` — `matching`
   (hashing, camera frozen) and `candidates` (awaiting a pick), both added to the
   freeze guard. (**Doc drift, corrected in step 16**: the artwork-first pivot
   later removed `matching`; the current enum is
   `detecting/reading/matched/unknown/readingCode/candidates/confirmed/error`, and
   `scan_controller.dart`'s freeze guard — not this paragraph — is the source of
   truth for which of them freeze the pipeline.)
   `ScanController.matchByArtwork()` (re-checks status after the
   await like `_lookup`; empty result → `unknown`/search-by-name),
   `selectCandidate()` (→ `matched` with defaults reset), `dismiss()` clears
   candidates. **Trigger is user-initiated, NOT `ocrFailureStreak`**: that streak
   counts agreed-passcode-not-in-DB, but the real OCR miss (no digits) never
   leaves `detecting`, so the entry points are a persistent app-bar
   `image_search` action (shown in `detecting`/`reading`) and a "Match by
   artwork" button on `_UnknownPanel`; results render in a new `_CandidatePanel`
   (tap a card → review gate). Tests: `phash_test`/`phash_e2e_test` (spike),
   `hamming_test`, `hash_index_test`, `art_matcher_test` (fake camera + in-memory
   index + repo over seeded db, asserts null-repo candidates are skipped),
   `art_frame_test` (luma/rotation helpers), and `scan_controller_test`'s
   `artwork-match fallback` group (unknown → match → pick → confirm writes one
   row). No DB migration, no new DB column, no pubspec dependency change (asset
   was already registered in step 6). `.g.dart` for the new `@riverpod` providers
   is regenerated, not committed.
9. Settings (default condition, default edition, language, re-sync, theme) ← done
   (verified: `flutter analyze` clean + full `flutter test` green, 174 tests).
   **Persistence is the existing `meta` key/value table** via `MetaDao` — four
   `settings.*` keys, **no migration, no schema change, no new dependency**
   (`shared_preferences` isn't in the approved stack, and `meta` has carried
   arbitrary keys since v1). `lib/data/repositories/settings_repository.dart`
   load/saves `AppSettings` (`lib/models/app_settings.dart` — hand-written
   immutable class + `copyWith`, matching the `AddCardSelection`/`ScanState`
   convention, *not* freezed since it is not a DB row). **Every parse is
   guarded**: `CardCondition.fromDb`/`CardEdition.fromDb`/`AppThemeMode.fromDb`
   all throw on unknown values, and settings load during app start, so a
   downgrade past a future enum member or a hand-edited db must degrade to the
   default rather than take the app down (`SettingsRepository._parse`).
   New enum `AppThemeMode` (`SYSTEM`/`LIGHT`/`DARK`, own `toDb`/`fromDb` +
   `toMaterial()`), deliberately distinct from Flutter's `ThemeMode` so the
   persisted format is ours. `kCardLanguages` (`lib/models/card_language.dart`)
   is a plain const list of the domain skill's two-letter blocks — `language`
   stays free-form TEXT so an unlisted language is still storable.
   **Theme = real Light/Dark/System** (decided with the user): `AppColors` is
   **gone**, replaced by `AppPalette extends ThemeExtension<AppPalette>` with
   `dark`/`light` instances, and all 87 call sites across 13 widget files now
   read `AppPalette.of(context).x`. Deleting rather than aliasing `AppColors`
   made `flutter analyze` the completeness check for the refactor. Light's
   accent is a deeper gold (`0xFF8A6410`) — the dark palette's `0xFFE0B341` is
   tuned against near-black and fails contrast on a light surface.
   **`AppPalette.of` falls back to `dark` when the extension isn't registered**,
   which is load-bearing: five existing widget tests pump a bare `MaterialApp`
   with no theme. Two colors are deliberately *not* palette-derived:
   `ConditionChipColors.onSelected` (chip/badge fills are identical in both
   themes, so their label ink must stay dark — a palette background would put
   near-white text on a pale green chip), and `scan_screen.dart`'s
   `_cameraScrim`/reticle/status banner, which sit on **live camera imagery**
   rather than app chrome and stay `AppPalette.dark` in every theme (the bottom
   panels do follow the palette). `buildAppTheme({brightness})` registers the
   matching palette in `extensions:`; `App` builds both themes and drives
   `themeMode`, and now **also gates on `settingsControllerProvider`** — it
   stays on `_SplashScreen` until settings resolve, so no route ever renders
   with unresolved settings and there's no light-to-dark flash.
   **Defaults wiring**: `AddCardSelectionController` and `ScanController` each
   read settings **once at build via `ref.read(...).value ?? const
   AppSettings()`** — `ref.read`, *not* `watch`, so changing a default can't
   reset a scan or wizard mid-flight; both are autoDispose, so the new value
   applies next time the screen opens. (Riverpod 3 note: `AsyncValue.valueOrNull`
   is gone — `.value` is the nullable getter.) The add-card resets in `save()`
   and `backToSearch()` go through `_initial()`, not `const AddCardSelection()`,
   or the second card would silently snap back to Near Mint. **Bug fixed along
   the way**: `ScanController.confirm()` never passed `language` at all, so
   every scanned row landed on the model's `'EN'` default regardless of
   preference — it now passes the configured language. (Step 9 made the setting
   the *only* language control; **step 10 revised this** to a per-card picker
   seeded from the setting — see step 10.)
   **Re-sync** is a separate `ResyncController` (reusing `InitialSyncState`/
   `SyncPhase`) rather than a reuse of `InitialSyncController`, so the blocking
   first-launch gate and its tests stay untouched; it has different post-success
   duties (invalidates `needsInitialSync`, `lastSyncedAt` *and*
   `collectionEntries`, since a sync rewrites the `cards`/`printings` the
   collection list joins against) and a non-blocking failure contract. UI is a
   confirm dialog then inline progress on the Settings screen, with a
   "Last synced" stamp from the new `CardRepository.lastSyncedAt()`.
   `/settings` now routes to `SettingsScreen`; **Statistics is the only
   remaining `ComingSoonScreen`**, so `home_screen_test` no longer loops over
   both tiles. **Gotcha**: the card-database section is the last item in the
   Settings `ListView` and sits below the fold in the default 800x600 test
   viewport — `settings_screen_test.dart` has a `scrollToDatabaseSection`
   helper (`dragUntilVisible`) that re-sync tests must call first. A second
   trap: after a save the "Added to your collection" SnackBar covers the bottom
   of the add-card screen, so a follow-up tap there misses — the multi-card
   test picks a zero-printing card to stay clear of it.
10. Per-card language, CSV export, collection statistics ← done
    (verified: `flutter analyze` clean + full `flutter test` green, 187 tests).
    **Per-card language (reverses step 9's "setting is the only control"):**
    passcodes are language-independent (`yu_gi_oh_tcg_passcodes.md`), so the
    schema already stored languages as distinct `collection_entries` rows under
    one passcode — no migration. The gap was UI: a language picker (a `Wrap` of
    `LabeledChoiceChip`s over `kCardLanguages`, labelled via the new
    `languageLabel`/`kCardLanguageNames` in `lib/models/card_language.dart`) now
    appears in **both** logging flows, seeded from the settings default but
    editable per card, because the camera can't read a card's language:
    `_ConditionStep` in `add_card_screen.dart` (state/plumbing already existed
    on `AddCardSelection`), and `_MatchedPanel` in `scan_screen.dart` (needed a
    new `language` field on `ScanState` + `ScanController.setLanguage`, with
    `confirm()` now writing `state.language`, seeded in `_lookup`/
    `selectCandidate`). The Settings language control stays as the *default*.
    The collection **detail** screen gained a `_LanguageBreakdown` ("Copies by
    language") that sums quantity per language across a passcode's entries via a
    new `entriesForPasscodeProvider` (reuses the existing
    `getEntriesForPasscode` passthrough — no new SQL), shown only when a card is
    held in >1 language. (Chosen over collapsing the list to one-tile-per-card.)
    **CSV export (entire collection, not the filtered view):** pure RFC-4180
    writer `collectionToCsv` in `lib/data/export/collection_csv.dart` (header +
    all columns, enum `toDb()` values, UTC ISO-8601 timestamps, quote/escape),
    offline-unit-tested; `CollectionExporter` writes it to
    `<app documents>/ygo_collection_<date>.csv` via `path_provider` and returns
    the path (no share/file-picker package — decided with the user), always
    exporting `getAll(filter: const CollectionFilter())`. Its end-to-end test
    mocks `path_provider` (new **dev-only** deps
    `path_provider_platform_interface`/`plugin_platform_interface`; runtime stack
    unchanged). **Statistics screen** (`lib/features/statistics/`, the last
    `ComingSoonScreen`, now removed from `router.dart`): total copies, distinct
    cards, and breakdowns by condition/language/card type from new
    `CollectionDao` aggregates (`sumByCondition`/`sumByLanguage`/`sumByCardType`,
    each DAO-tested) via `collectionStatsProvider`; hosts the CSV export button.
    **Test gotcha**: the `home_screen_test` "navigates to Statistics" case
    overrides `collectionStatsProvider` with a ready value rather than routing to
    a db-backed screen — navigating *through go_router* to a screen that kicks
    off the `sqflite_common_ffi` isolate mid route-transition does not settle
    under a widget test and hangs to the 10-min timeout (a direct
    `MaterialApp(home: StatisticsScreen())` pump inside `runAsync` is fine — see
    `statistics_screen_test`). The `_LanguageBreakdown` provider watch degrades
    to `SizedBox.shrink()` until it resolves, so the detail screen never blocks.
    **`.ydk` export was dropped** (decided with the user): the format is a
    *deck* list — passcodes only, one line per copy, `#main`/`#extra`/`!side`
    with ≤60/≤15/≤15 limits — so it carries none of what makes a collection
    row interesting (quantity, condition, set code, edition, language), and a
    whole collection written into it isn't a legal deck that editors will
    accept. EDOPro already covers deck building. CSV is therefore the
    deliberate interchange format: it preserves every column and feeds
    pandas/DuckDB/Polars, plus a separate web front-end the user plans to build
    over the exported data. If deck building is ever added to *this* app,
    `.ydk` export becomes worth revisiting — per deck, not per collection.
11. Post-launch on-device feedback pass — collection UX, scan tweaks, editable
    entries ← done (verified: `flutter analyze` clean + full `flutter test`
    green, 212 tests). A polish/fixes round after the first real on-device
    testing, sitting on top of steps 1-10 **and** the separately-made
    artwork-first/OpenCV scan pivot (see the [[artwork-first-scan-pivot]] memory
    and `lib/features/scan/card_detector.dart` /`opencv_card_detector.dart` —
    that pivot post-dates steps 7-8's write-up here, which still describe the
    pre-pivot pHash design). Nothing in this step changes the scan algorithm or
    the `assets/card_hashes.json` index, and there is **no DB migration, no new
    dependency, no schema change**.
    **Two new persisted settings, in the existing `meta` table** (same
    key/value convention as step 9, `settings.*` keys, guarded parse):
    `AppSettings.showScanDiagnostics` (default false) and
    `confirmBeforeDelete` (default true), with `_parseBool` in
    `SettingsRepository` (`'true'`/`'false'`, anything else → default). Booleans
    are the first non-enum, non-free-text settings; `SettingsController` gains a
    setter for each and the Settings screen gains **"Collection"** (confirm
    toggle) and **"Scanning"** (diagnostics toggle) `SwitchListTile` sections.
    **Diagnostics is now persisted, not ephemeral**: the old
    `ScanDiagnosticsEnabled` class provider became a derived functional provider
    `scanDiagnosticsEnabled` reading `settingsControllerProvider` (so the
    overlay's `watch` and `artReadings`' per-frame `read` are unchanged), and
    the scan app-bar bug icon is now a **shortcut** that writes the same setting
    (`setShowScanDiagnostics`) — kept, not removed, so both control one value.
    (`scan_providers.dart` importing `settings_providers.dart` introduces no
    cycle — settings never imports scan.)
    **Delete confirmation** (`collection_delete_confirm.dart`, one shared
    `confirmRemoveCard(context, ref)` helper): gated on `confirmBeforeDelete`,
    reused by all four removal paths — the list-row delete and
    decrement-to-last-copy (`collection_screen.dart`, whose handlers gained a
    `BuildContext` param), and the detail screen's delete and
    decrement-to-last-copy. Decrement only prompts when `quantity == 1` (the
    copy that would remove the card). `collection_screen_test`'s
    decrement-to-zero case now taps through the dialog.
    **Editable entries + auto-merge** (the load-bearing new feature): new
    `CollectionDao.updateEntryDetails(id, {printingId, condition, edition,
    language})` — one transaction that edits in place, but if the new combo
    collides with a *different* existing row for the same passcode (the
    `collection_entries` UNIQUE key, `printing_id IS NULL` handled like
    `addOrIncrement`), it **merges**: the survivor absorbs this row's quantity
    and this row is deleted. Returns the surviving id (same id = plain edit,
    different = merge), which the UI uses to pick the confirmation message. DAO
    test covers all three (in-place, merge, NULL-vs-real printing). Surfaced via
    a repo passthrough, a new `cardPrintingsProvider` (reuses
    `CardRepository.getPrintingsForPasscode`, keeping the widget off the DAO),
    and an app-bar edit icon on the collection detail screen opening
    `_EditEntrySheet` (condition/edition/language chips + a printing dropdown
    with a "no set" option). On save it pops back to the list (the passed-in
    `entryWithCard` is now stale, and a merge may have removed the row) and
    snackbars update-vs-merged.
    **Collection display fixes**: the detail screen shows the **whole card**
    (portrait `aspectRatio` + `BoxFit.contain`) instead of the old square
    centre-crop (the list tile already did); `YgoProdeckClient._firstImageUrl`
    now prefers `image_url_small` (fallback `image_url`) so **new** downloads are
    the smaller full-card image (takes effect after a re-sync; existing files
    keep their size but now display in full). The list tile centres the leading
    art + condition chip vertically (`CrossAxisAlignment.center`). Spell/Trap
    cards no longer mislabel their `race`: `YgoCard.isSpellOrTrap`
    (`frameType == 'spell' || 'trap'`) switches the detail label to
    **"Property"** and hides the redundant `attribute` row ("SPELL"/"TRAP").
    **Scan screen**: the "three ways to log a card" help box was nudged down
    (smaller bottom inset) and `ScanReticleTokens.maxHeightFraction` dropped
    0.7 → 0.62 so the reticle clears it. **Best-effort warm-up fix** for the
    "recognition gets easier after re-opening Log Cards / after a confirm"
    report (decided with the user, flagged for on-device retest): `_start()` in
    `camera_service.dart` re-asserts `FocusMode.auto` + `ExposureMode.auto`
    (guarded) on every fresh camera start — targets autofocus/exposure settling
    on a stale value under `startImageStream`. Not guaranteed; the diagnostics
    overlay is the tool for gathering data if it recurs.
12. Second on-device feedback pass — set picker while scanning, sticky scan
    mode, optional help box, list-tile layout ← done (verified: `flutter
    analyze` clean + full `flutter test` green, 218 tests). **No DB migration,
    no schema change, no new dependency.**
    **Set/expansion in the scan review gate** (a scan used to be hardwired to
    `printingId: null`): new `ScanState.printingId` + `ScanController.setPrinting`,
    written by `confirm()`. The UI is `_SetPicker` in `scan_screen.dart`, a
    dropdown over the *existing* `cardPrintingsProvider` — the collection edit
    sheet's provider, so no new SQL and no new repository method — **hidden when
    the card has no known printings**, where the only option would be "no
    specific set". It reads `.value` rather than `when`, so an unresolved load
    leaves the review panel's height alone instead of flashing a spinner. Every
    path that resolves a card clears it (`clearPrintingId` in
    `_resolveArtMatch`/`selectCandidate`/`_lookup`, and in `confirm`/`dismiss`),
    so a set can never leak onto the next card. `Printing.displayLabel`
    ("SET-CODE · Set Name · Rarity") was added to the model and now backs the
    picker, the collection detail's Set row and the edit sheet's dropdown,
    replacing two copies of the same formatter.
    **Passcode OCR is now a sticky mode, not a one-shot read** — the reported
    bug was that saving a card dropped the user back into artwork recognition,
    costing an extra tap per card when logging a stack by code. New
    `ScanMode { artwork, passcode }` on `ScanState`: `requestPasscodeRead()`
    enters it, `_beginPasscodeRead()` re-arms after every `confirm()`/`dismiss()`
    while it is on, and only `exitPasscodeMode()` (the app-bar toggle or the
    reading panel's button) or leaving the screen clears it — `ScanController`
    is autoDispose, so **re-opening Log Cards always starts in artwork mode**.
    `_onArtReading` ignores artwork outright in passcode mode, and `artReadings`
    now `continue`s (no detect+hash at all) while `passcodeOcrRequested` is true,
    so the two pipelines never run against the same frames. Consequences: the
    app-bar pin icon became a mode toggle (filled + accent when on,
    `pin_outlined` when off) and is shown in `readingCode` too;
    `ScanTuning.ocrTimeoutFrames` and `ScanState.ocrFramesSeen` are **gone** — a
    12s frame timeout that silently exited the mode is precisely the behaviour
    this step was asked to remove, and the mode is now user-owned. In exchange
    `_onReading` gained the `lastConfirmedPasscode` + M-empty-frames debounce
    that only `_onArtReading` had (and which is idle in this mode), so a card
    left under the lens after a confirm no longer re-opens the review panel —
    that moves *toward* the spec's non-optional debounce rule, not away from it.
    **The help box is optional and smaller**: `AppSettings.showScanHelp`
    (default true; `settings.show_scan_help` in `meta`, guarded `_parseBool`
    like step 11's booleans) with a "Show the how-to box" switch in Settings →
    Scanning, read by a derived `scanHelpEnabled` provider that mirrors
    `scanDiagnosticsEnabled`. Type dropped one step into `ScanHelpTokens`
    (title 14→13, lines 13→12, icons 18→16), with tighter insets and a smaller
    corner radius.
    **Collection list tile**: the condition chip now leads the row with the
    artwork after it (swapped — the chip is what the eye scans for), and the
    card name + set/edition line are centred (`CrossAxisAlignment.center` +
    `textAlign: TextAlign.center`) above the quantity/delete controls.
    **Test gotcha**: `dragUntilVisible` on the Settings `ListView` stops as soon
    as the target tile is *built*, which can still be below the fold (the new
    switch landed at y=608 in the 600px test viewport, so the tap missed) — the
    scanning switches reuse the existing `scrollToDatabaseSection` helper
    instead, since they sit just above that section.

13. Third on-device feedback pass — detection robustness, live outline, set
    search box, list-tile layout ← done (verified: `flutter analyze` clean +
    full `flutter test` green, 263 tests). **No DB migration, no schema change,
    no new dependency.**
    **Collection list tile, re-laid out** (`collection_list_tile.dart`): the row
    now reads grade → art → name/set → quantity → actions. The condition chip
    and artwork are unchanged and stay centred in their own boxes; the name and
    set/edition line moved to the *right of the artwork* (centred in the space
    between it and the quantity); the quantity is a plain number in a
    fixed-width slot (`CollectionTileTokens.quantityWidth`, fixed so the action
    column doesn't shift as the count gains a digit); and add/remove/delete are
    stacked in one column on the right, in that order. Everything is
    `CrossAxisAlignment.center`, so the quantity lands on the row's midline —
    which is exactly where the middle (remove) button sits. A plain `IconButton`
    carries a 48pt minimum on every side, and three of those make the row twice
    the height of its artwork, so the buttons render through a private
    `_TileAction` trimmed to `CollectionTileTokens.actionButtonSize` (36) while
    keeping icon, colour and ripple.
    **Set/expansion is now a search box, not a dropdown** — a reprinted card can
    carry a dozen printings and the user knows which one is in their hand.
    `PrintingPicker` (`lib/shared/widgets/printing_picker.dart`) is a text field
    that narrows the card's known printings as you type, backed by the pure
    `filterPrintings` in `lib/models/printing.dart` (every whitespace-separated
    term must appear in `Printing.displayLabel`, case-insensitive, any order —
    so "raiders super" finds `MRD-EN094 · Metal Raiders · Super Rare`). It
    replaces the `DropdownButton` in the scan review gate (`_SetPicker`) and the
    collection edit sheet, and the manual add wizard's `_PrintingStep` gained
    the same search field above its full-page list (that step keeps its own
    list shape — a capped inline list on an otherwise empty page is worse — but
    shares the one filter rule). **Search is over known printings only**
    (decided with the user): a pick always resolves to a real `printings.id`,
    so there is no free-text set, no synthetic rows and no DAO change.
    The query is local widget state in both places, deliberately: it is
    ephemeral input, not part of the card being logged. The field doubles as
    query and selection — on blur it snaps back to the selected printing's
    label, so a half-typed query can never read as a choice.
    **Scan diagnostics moved above the status banner.** They previously shared
    the *identical* top inset (`kToolbarHeight + AppSpacing.sm`), one topLeft
    and one topCenter, so on a narrow screen they overlapped and the diagnostics
    box painted over "Point at a card". Both now live in one `_TopOverlays`
    column — diagnostics first, banner below — so the order is structural
    rather than a coincidence of two equal paddings, and the banner moves down
    when diagnostics is on. Its hard-coded 12pt monospace became
    `ScanDiagnosticsTokens`.
    **Card detection, substantially reworked** — the reported failure was
    sleeved cards on a non-monochromatic surface. Four changes, in order of
    expected value:
    - **The search follows the reticle.** `detectCard` gained a `searchRoi`, and
      `scan_geometry.dart` maps the on-screen guide box into upright-frame
      fractions. This is *not* the identity mapping and that is the whole point:
      the preview is a `BoxFit.cover` crop of the sensor frame, so on a 1080x2340
      viewport against a 4:3 sensor the reticle covers 78% of the screen's width
      but only ~48% of the frame's. `reticleRectInViewport` is now the single
      source of truth for the guide's geometry — `_ReticleOverlay` draws it and
      the detector searches it, so they cannot drift apart. The viewport reaches
      the pipeline via `scanViewportSizeProvider`, written from a post-frame
      callback by a `_ViewportProbe` at the base of the stack; **null (no screen
      laid out — i.e. every host test) degrades to the old whole-frame search**.
      The provider is `keepAlive: true`, load-bearing: writer and readers all
      use `ref.read`, which holds no subscription, so an autoDispose provider
      would be torn down between the write and the next frame and the ROI would
      silently stay whole-frame forever.
      The crop is applied to the Mat **before** the edge map, not just used to
      filter candidates afterwards: Canny's thresholds come from an Otsu split,
      and over the whole frame that histogram is dominated by whatever the card
      is lying on — which is precisely why a busy surface washed the card's own
      edges out. Spending the same 480px detection budget on the guide box also
      roughly doubles the card's linear resolution, and the warp now reads from
      the **full-resolution** image (free: `warpPerspective` costs by its
      destination size) via `getPerspectiveTransform2f`, so corners are no
      longer rounded to integers.
    - **Shape scoring replaces "largest quad wins".** All the decision logic
      moved to a new **pure, host-tested** `lib/features/scan/card_quad.dart`
      with its thresholds in `CardDetectionTuning` — the detector imports
      OpenCV, so nothing left inside it could ever be tested, and a wrong
      threshold here doesn't crash, it silently recognises the wrong card.
      Candidates are gated on card aspect ratio, rectangularity, opposite-side
      balance, in-plane tilt (past ~25° the corner ordering mis-assigns corners
      and warps the card rotated — a plausible-looking detection that hashes to
      nonsense) and area *as a fraction of the search region*, then scored on
      four **bounded** 0..1 terms. The old score multiplied by raw pixel area,
      so it was still largest-wins with a shape prefilter.
    - **The sleeve fix.** A sleeve's outline is concentric with the card's and a
      few percent larger, so largest-wins picks the sleeve and shifts every
      subsequent crop — the reason `autoMatchMaxDistance` and
      `maxHammingDistance` had been loosened to 13/18. `selectCardQuad` steps
      **one** level inward into a nested quad. Exactly one: a card carries a
      printed inner border at ~0.81 of its own area, overlapping the sleeve
      ratio, so an unbounded descent walks sleeve → card → border and shrinks
      the warp ~11%. Near-duplicate quads (the two sides of one dilated edge
      band) are collapsed first so they can't consume that single step. Both
      cases are regression-tested.
    - **The crop is corrected to the located art box.** `_findArtBox` looks for
      the artwork rectangle inside the rectified card and, when it finds one,
      hashes that instead of the fixed fractions. This matters because the index
      hashes a fixed fractional ROI of a *clean* card, so any error in the outer
      outline rescales the rectification and the fixed ROI then samples the
      wrong pixels. **The standing assumption is documented at the function**:
      it treats `ArtMatchTuning.artBoxRoi` as the artwork's true position, which
      holds to the precision of those hand-rounded fractions. The trade is
      favourable (a sleeve misrectifies by ~5-8%; the ROI approximates the real
      window to a percent or two) but measuring the true rect across the cached
      reference images in `tools/.image_cache/full/` and, if it differs,
      rebuilding the index with the measured value would remove the assumption
      outright — **the one open follow-up here**. Ties break on *size*, not on
      closeness to the expected box: ranking by closeness is circular and
      prefers making no correction, discarding exactly the shifted art box the
      pass exists to find.
      The old unconditional bounding-box fallback (which warped the largest
      contour of *any* shape, so a blob of desk became a "card") is gone; a
      validated one survives, run through the same shape gate.
    **Live detection outline** (`_DetectionOutline`/`_DetectionPainter`), the
    behaviour the user saw in store apps: the detected card and the artwork
    window are drawn on the preview, the art box heavier since it is the region
    actually hashed. `DetectedCard` carries its quad in upright-frame fractions,
    which flows through `ArtFrameResult` → `ArtReading` to the painter; the
    painter repeats the preview's cover transform via `frameFractionToViewport`.
    Detections arrive on the 300ms camera throttle, so corners glide over
    `ScanOutlineTokens.transition` (260ms) from wherever the animation had
    actually reached, and a lost card fades rather than blinks. **Cosmetic
    only** — nothing here feeds back into matching, so a rotation mismatch on
    some device can never affect what gets logged; conversely a correctly
    hugging outline is the on-device acceptance test for the ROI mapping.
    **Two smaller fixes**: `PHashArtMatcher` now caches the last ranked result
    so `match()` resolves *that* frame instead of re-detecting a newer one (the
    review panel could otherwise present a different card than the outline had
    locked onto); and `camera_service` meters focus/exposure on the frame centre
    (`setFocusPoint`/`setExposurePoint`), since left alone the camera weights
    the whole scene and exposes for the desk.
    **Gotcha, twice over**: a `late final` field whose initializer runs on first
    *access* will run it inside `dispose()` if nothing touched it during build —
    both `_DetectionOutline`'s `AnimationController` (ticker assertion) and
    `_ViewportProbe`'s notifier (`Using "ref" when a widget ... has been
    unmounted`) failed this way. Assign such fields in `initState`.
    **Still open / not done** (the user scoped these out): detection and the
    14,636-entry index scan still run on the UI isolate; no multi-crop hash
    voting; `ScanTuning.frameInterval` unchanged at 300ms. And
    `autoMatchMaxDistance`/`maxHammingDistance` are still 13/18 — they were
    loosened to absorb the sleeve drift this step removes, so **being unable to
    tighten them back toward 10/14 on device is evidence the art-box correction
    isn't landing**.

14. Fourth on-device feedback pass — collection tile/detail polish, rarity
    filter, camera reliability ← done (verified: `flutter analyze` clean + full
    `flutter test` green, 291 tests). **No DB migration, no schema change, no
    new dependency.**
    **Collection list tile, shorter and re-worded** (`collection_list_tile.dart`):
    the row lost ~19pt off the top and ~19pt off the bottom. Padding alone
    couldn't do it — the row's height is set by the tallest child, which is the
    three-button action column — so it took both a new
    `CollectionTileTokens.verticalPadding` (16 → 6) and `actionButtonSize`
    30 (was 36, icons 22 → 20): `2*16 + 3*36 = 140` became `2*6 + 3*30 = 102`.
    The secondary line became **two** lines, set code then rarity, each omitted
    when absent; the **edition is gone from the list** (it stays on the detail
    screen) because rarity is what the eye looks for across reprints. Even with
    a wrapped 2-line name the block is ~88pt, inside the 90pt action column, so
    the third line costs the row nothing. The artwork is 5% larger via its own
    `CardThumbnailSizes.collectionTile` (`list * 1.05`) rather than a bump to
    `list` — the scan review/candidate panels keep the smaller size, and this
    one was flagged as possibly-revert.
    **Detail screen**: `YgoCard` gained `isSpell`/`isTrap` (`isSpellOrTrap` is
    now their disjunction, so existing call sites are untouched) and the `race`
    row is labelled **"Spell Type"/"Trap Type"/"Monster Type"** — step 11's
    generic "Property" is gone. Rarity moved out of the Set row into a row of
    its own, backed by a new `Printing.setLabel` ("SET-CODE · Set Name");
    `displayLabel` keeps the rarity because `filterPrintings` searches it.
    **Rarity filter replaces the edition filter** — `CollectionFilter.edition`
    is **removed** (nothing else read it; the CSV exporter and statistics use
    `const CollectionFilter()`) and replaced by `RarityFilter?`, a small value
    type with two constructors: `.value(rarity)` and `.noRarity()`. The second
    is load-bearing: a card logged without a printing carries no rarity and
    could otherwise only be reached under "All". Its predicate is
    `p.rarity IS NULL` over `getAll`'s existing LEFT JOIN, which is *also* what
    the new `CollectionDao.rarityFilterOptions()` reports as a null element — so
    the chips and the filter agree by construction and no chip is ever dead.
    The chip row offers only rarities actually held. **Gotcha, and the one real
    design constraint here**: `collectionRarityOptions` must **not** watch
    `collectionEntriesProvider`, even though it is a projection of the same
    rows — chaining one async provider onto another that is invalidated mid
    route-transition makes Riverpod schedule a scope refresh from inside a build
    ("setState() called during build", reproduced by
    `collection_screen_test`'s detail-increment case). Instead the mutation
    sites invalidate it explicitly alongside `collectionEntriesProvider`, and
    only those that can change *which printings are held* (add/edit/delete, plus
    re-sync) — a plain quantity change cannot.
    **Camera reliability.** Two reports drove this: the diagnostics overlay
    reading `no camera frame yet` while pointed at a card, and a preview that
    sometimes stayed black after installing a new APK.
    - **The message was lying.** `no camera frame yet` was shown for four
      different situations, only one literal: the reading stream still
      `AsyncLoading`, the camera released (backgrounded), passcode mode (where
      `artReadings` never yields), and an actual missing frame. There is now a
      `CameraHealth` snapshot on `CameraService` and a pure, host-tested
      `describeCameraHealth` rendering `cam: streaming  f=124  Δ=180ms  r=1`
      above the recognition lines. `_DiagnosticsBox` became stateful for a
      500 ms ticker, which is load-bearing: a stalled camera stops `artReadings`
      emitting, so a box that only rebuilt on a reading would freeze exactly
      when the camera state is what you need.
    - **A frame-stall watchdog.** The Android implementation resolved for
      `camera: ^0.12.0` is **`camera_android_camerax`** (CameraX, not Camera2 —
      `camera_android` is not in the lockfile), whose image stream is known to
      stop delivering frames at random (flutter/flutter#152763, an NPE in
      `ImageProxyHostApiImpl.close()` halting the analyzer) and whose preview
      can black out under `startImageStream` (flutter/flutter#27688, "worse as
      resolution increases"). Neither is fixable from Dart. `CameraScanService`
      now records frame **arrival** (unconditionally, at the top of `_onFrame`,
      before the throttle — which also fixes a dropped frame consuming the
      throttle window) and a `Timer.periodic` restarts the camera through the
      existing `_enqueue` chain when `cameraFrameStalled` (pure, tested) says
      so, with a doubling backoff to `cameraRestartMaxBackoff`.
    - **The metering fix.** `_start()` wrapped four independent best-effort
      calls in **one** `try`, so a throw from `setFocusMode` silently skipped
      `setExposureMode`/`setFocusPoint`/`setExposurePoint` — and
      `camera_android_camerax` 0.7.4+1's changelog is a fix for exactly that
      throw. Each call is now guarded individually, and the metering points are
      re-applied **after** `startImageStream`, since binding CameraX's
      image-analysis use case rebinds the camera and cancels a pending
      focus-and-metering action. Step 11's centre-metering may never have taken
      effect on device before this.
    - `_rotationDegrees` no longer returns null for an unmapped
      `deviceOrientation`; it falls back to the bare sensor orientation. A
      dropped frame is invisible from outside and presents as a permanent "no
      card detected".
    **Detection runs on a worker isolate** (`detector_isolate.dart`,
    `IsolateCardDetector`) — the plan's one genuinely risky change, and the
    biggest lever on the black preview: an edge map, contour pass, warp and
    art-box pass, three times a second, on the UI isolate is enough to stop
    Flutter painting, and a preview that stops repainting is indistinguishable
    from a dead camera. It works because nothing crosses the port but plain
    data (`ArtFrame`/`DetectedCard` hold no `Mat`, no native handle; luma travels
    as `TransferableTypedData`), and because dartcv4's bindings are lazily
    initialised top-level `final`s so the worker `dlopen`s the already-loaded
    library once — hence **one long-lived worker**, not `Isolate.run` per frame.
    It degrades rather than fails: a spawn failure or handshake timeout falls
    back to in-process `OpenCvCardDetector`. `CardDetector.detectCard` and
    `ArtMatcher.rankFrame` are now `Future`s; the OpenCV body moved to a
    top-level `detectCardSync`. **Only verifiable on device** — host tests can't
    load OpenCV.
    **`artReadings` is now self-paced**, polling `CameraService.frameSequence`
    every `ScanTuning.artPollInterval` (100 ms) instead of `await for`-ing
    `camera.frames`. With an awaited rank inside the loop that subscription was
    a hazard: a broadcast `StreamController` **buffers for a paused subscriber**,
    so a detection pass outrunning the frame interval would grow an unbounded
    backlog and the outline would drift further behind reality the longer
    scanning went. Polling always works on the newest cached frame, and
    comparing the sequence is what stops one physical frame being ranked twice
    (which would let it satisfy `artAgreementFrames` on its own). The loop needs
    an explicit `disposed` flag from `ref.onDispose`, because an iteration that
    `continue`s never reaches the `yield` where cancellation would be observed.
    A new `scanPaused` provider (written by `ScanController` where it already
    writes `passcodeOcrRequested`) skips the work entirely while a result awaits
    the user — a separate provider, not a read of `scanControllerProvider`,
    since the controller *listens* to `artReadings` and that would be a cycle.
    **The 14 636-entry index parse moved off the UI isolate** via `compute`
    (`rootBundle.load` → bytes → `utf8.decode`+`jsonDecode`+`HashIndex.fromJson`
    in the isolate). It used to land at exactly the wrong moment — the scan
    screen opening, while the camera initialises.
    **ROI**: `ScanDetectionTokens.reticleRoiMargin` 0.15 → **0.08**, for two
    reasons that point the same way. The margin inflates area by `(1 + 2m)^2`,
    so 0.15 made the search region **1.69x** the reticle: it re-admitted the
    desk into the Otsu split that sets Canny's thresholds (the very thing
    cropping to the guide box exists to prevent), and left a card perfectly
    filling the reticle at 0.59 of the region — below
    `CardDetectionTuning.targetRoiAreaFraction` (0.75), so a well-framed card
    could never earn a full fill score. At 0.08 the region is 1.35x and a filled
    reticle is 0.74 of it, making that existing target correct as written.
    `PHashArtMatcher._rank` also **retries once over the whole frame** when the
    guide-box pass finds nothing: the reticle-to-frame mapping is the one thing
    here that can be wrong with no visible symptom, and this turns "detection
    never works on this device" into a slower path, at zero cost on frames that
    already succeed. And a diagnostics-only `_SearchRoiOverlay` draws the round
    trip (reticle → frame fractions → back to the viewport), so the mapping is
    checkable on a real device, which no host test can do.
    **Still open**: `autoMatchMaxDistance`/`maxHammingDistance` are still 13/18
    and `ScanTuning.frameInterval` is still 300 ms. The new `cam:` and
    `art box:` lines are the evidence needed to decide whether the step-13
    art-box correction is landing and whether those can be tightened toward
    10/14 — next pass's question. Also still open: step 13's follow-up of
    measuring the true art-box rect across `tools/.image_cache/full/`.

15. Fifth on-device feedback pass — dismissed cards re-detectable, surface hint,
    scan-open latency ← done (verified: `flutter analyze` clean + full
    `flutter test` green, 299 tests). **No DB migration, no schema change, no
    new dependency.** Nothing here touches the detection algorithm, the tuning
    thresholds or `assets/card_hashes.json`.
    **A dismissed card could never be re-detected while it stayed in frame** —
    the report was "if the camera identifies a card and I decide not to log it,
    it's much harder to identify again", and it was literally unbounded.
    `dismiss()` reused the **post-confirm** debounce (`lastConfirmedPasscode` +
    `ScanTuning.debounceEmptyFrames`), which only advances on frames with *no*
    confident match — but the dismissed card sitting in the reticle matched
    every frame and took the suppression branch, which resets `emptyFrameCount`
    to **0**. Pinned at zero: holding the card still, the natural reaction,
    suppressed it forever; the only escape was pulling it out of frame for ~2 s.
    The same trap was on the OCR path. The fix separates the two rules rather
    than loosening either: new `ScanState.dismissCooldown` +
    `ScanTuning.dismissCooldownFrames` (3), a countdown ticked by the shared
    `ScanController._tickSuppression` on **every** reading including matching
    ones, so a dismissed card frees itself in about a second without moving.
    `confirm()` explicitly sets it to 0 and keeps the empty-frame rule verbatim
    — that one is the spec's non-optional guard against one card logging thirty
    times, and a test now asserts the cooldown can't free a *confirmed* card.
    `copyWith` zeroes the cooldown whenever `clearLastConfirmedPasscode` is set,
    so the two fields can't disagree about why a card is suppressed. `dismiss()`
    also gained a third fallback for the passcode it suppresses —
    `candidates.first` — because `showCandidates()` clears `matchedCard`, so
    "none of these" used to suppress *nothing* and the same top guess came
    straight back. Both new behaviours were verified to fail with
    `dismissCooldownFrames = 0` (which reproduces the old code exactly) before
    being kept.
    **Surface hint above the guide box** (`AppStrings.scanSurfaceHint`): the
    detector crops to the reticle and derives Canny's thresholds from an Otsu
    split of *that region*, so what the card lies on decides whether its own
    edges survive — the single biggest cause of "it won't recognise anything",
    and nothing on screen said so. `_ReticleOverlay` became a `ConsumerWidget`
    rendering a `Stack` of the unchanged centred box plus a `Positioned` hint.
    **It is anchored to the box, not stacked above it in a `Column`, and that is
    load-bearing**: `reticleRectInViewport` is a `Rect.fromCenter` on the
    viewport centre and is the shared source of truth for the drawn box *and*
    `detectionRoiInFrame`'s search region — a centred column of "text + box"
    would have shifted the drawn box up by half the text height while the
    searched region stayed put, silently breaking the correspondence step 13 was
    built around. Anchoring by the hint's **bottom** also means a two-line wrap
    grows upward, away from the box. It follows the existing `scanHelpEnabled`
    switch (decided with the user — one control for all on-screen help) and is
    additionally suppressed while diagnostics is on, since that overlay pushes
    the status banner down into this exact strip. The screen test asserts the
    *geometry* (hint bottom above the box top, box still centred), not just
    presence.
    **Scan-open and app-resume latency.** `CameraController.initialize()` is
    slow on CameraX and not fixable from Dart; everything *around* it was being
    re-paid on every entry **and every resume**, because it was all autoDispose:
    - `hashIndexProvider` and `cardDetectorProvider` are now
      `@Riverpod(keepAlive: true)`. Step 14 moved the index parse to a `compute`
      isolate, but that was only half the fix while the provider was
      autoDispose: leaving the screen dropped the parsed index, and so did
      merely backgrounding (`artReadings` returns early when `scanCameraActive`
      flips, releasing its watch on `artMatcher` → these). Every re-entry and
      resume re-read the asset, spawned an isolate, re-decoded ~14 600
      entries and copied the map back — and the **receiving** half of that copy
      runs on the UI isolate, concurrently with `initialize()`. Parsed once per
      app run costs ~2 MB resident. Consequence worth knowing: a ROI-mismatch
      `FormatException` is now cached for the app's lifetime, which is fine —
      it's a property of the build, identical on every retry.
      `test/features/scan/art_providers_test.dart` guards both against a tidy-up
      back to `@riverpod` (the assertion was itself validated against a scratch
      autoDispose provider, so it isn't a false guard).
    - `availableCameras()` is memoized in a `static List<CameraDescription>?` on
      `CameraScanService` — the answer can't change while the app runs, but it
      was a platform round-trip in front of `initialize()` on every entry,
      resume and watchdog restart. The **resolved list** is cached, not the
      future, so a failure leaves it null and the next `start()` really retries.
    - `_preview.value = controller` moved **above** the first `_meter()`, taking
      four awaited platform round-trips out from between `initialize()` and the
      first visible frame. Pure reordering; both `_meter` calls and step 14's
      after-`startImageStream` rationale are untouched.
    - `HomeScreen` gained a zero-size `_ScanPrewarm` that `ref.read`s both
      providers in `initState` (decided with the user), so even the *first* Log
      Cards tap of an app run is fast — otherwise the parse and the isolate
      spawn land while the camera is initialising, which is exactly when there
      is no budget. It deliberately does **not** `watch`: a warm-up must not
      gate or rebuild the menu, and an index failure must surface on the scan
      screen where it can be acted on.
    **Test gotcha**: `home_screen_test`'s `pumpApp` pumped `MaterialApp.router`
    with **no `ProviderScope` at all** — fine until Home touched a provider, then
    `Bad state: No ProviderScope found`. It now wraps in a scope and stubs
    `hashIndexProvider` with an empty in-memory index, since the warm-up is
    fire-and-forget and the real index parse would be pure test latency.
    (`app_gate_test` reaches Home with the real asset and is unaffected.)
    **Still open, unchanged by this pass**: `autoMatchMaxDistance` /
    `maxHammingDistance` at 13/18, `ScanTuning.frameInterval` at 300 ms, and
    step 13's follow-up of measuring the true art-box rect across
    `tools/.image_cache/full/`.
    **An adversarial review of both recognition pipelines ran after this step —
    see `docs/scan_pipeline_review.md`.** It answers two of the standing open
    questions with measurements, and the answers are "no": the true art box *was*
    measured (it is a **square**, `0.1181, 0.1814, 0.8831, 0.7063`, not the
    shipped 1.147-aspect rect), and because `_findArtBox` gates at
    `_artBoxAspectTolerance = 1.12` the step-13 correction **can never fire** —
    which is exactly the evidence step 14 said it was waiting for. Sixteen ranked
    findings, each tagged verified-vs-reported; four were re-verified in the main
    session, including that **`scanPausedProvider` is autoDispose and so step
    14's pause optimisation is inert**, and that the debounce compares an *index*
    passcode to a *DB* passcode (which undermines this step's `dismissCooldown`).
    **Implemented in step 16.**

16. Acting on the adversarial review — 256-bit pHash, measured art-box ROI,
    scan-pipeline defect fixes, collection tile polish ← done (verified:
    `flutter analyze` clean, full `flutter test` green at **321 tests**,
    `pytest tools/` green). **No DB migration, no schema change, no new
    dependency.** Fifteen of the review's sixteen findings are fixed; each
    carries a resolution note in `docs/scan_pipeline_review.md`, which is now the
    *evidence* for the constants rather than a backlog.
    **The art box was wrong, and it is now measured.** Re-derived independently
    before acting on it, by normalized cross-correlation of YGOPRODeck's own
    `image_url_cropped` against the full render: every sample converged at
    **NCC 0.996-0.999** on (96, 214-216) size **622x622** in the 813x1185 render
    — 96 px of left margin against 95 px of right, i.e. horizontally centred, and
    **square**. `ArtMatchTuning.artBoxRoi` is now
    `(0.1181, 0.1814, 0.8831, 0.7063)`. The old `(0.09, 0.19, 0.91, 0.68)` has
    aspect 1.147 and `_findArtBox` rejects past `_artBoxAspectTolerance = 1.12`,
    so **the step-13 art-box correction had never once fired on any device** —
    which is precisely the evidence step 14 said it was waiting for, resolved
    from the desk rather than the phone.
    **The descriptor is 256-bit (`hash_size = 16`).** The measured case: over the
    old 64-bit index, *every one* of 14 636 cards had another card within Hamming
    18 (mean 26.3) — `maxHammingDistance` was not a threshold, it was the whole
    neighbourhood — and 41 hash values were shared outright by 82 cards. Over the
    rebuilt index the same *fraction* of the width (72/256 = 28.1 %) admits a
    spurious neighbour for **1.37 %** of cards; the curve is flat from r=4 to
    r=84 and only cliffs at 88. Exact duplicates fell to 26 groups / 52 entries.
    So `maxHammingDistance = 72` / `autoMatchMaxDistance = 48` — the same
    fractions as before, now with two orders of magnitude more headroom, and
    **written even on purpose**: a median-thresholded hash has exactly half its
    bits set (verified: popcount histogram is `{128: 14641}`), so all distances
    are even and the old `13` was bit-for-bit `12`.
    Preserving the fraction was *measured*, not assumed — the Tier-2 fixture gap
    is `[2, 2, 4]` of 256, the same handful of bits as at 64, so
    `phash_e2e_test`'s gate stays at **12** rather than scaling to 48 (scaled, it
    could no longer detect a regression). `PerceptualHash` is now eight 32-bit
    lanes in a `Uint32List` — lanes-of-32 *preserves* the web-safety invariant the
    two-lane split existed for (every `int.parse` chunk stays under 2^32), and
    stores truncate so `~x` needs no mask. Bit-packing switched to `v * 2 + bit`;
    the old `1 << (31 - i)` goes through JS's *signed* 32-bit ops under dart2js.
    `assets/card_hashes.json` is v3, 14 641 entries, 540 KB → **1.24 MB**.
    **The rebuild was 100 % offline** — `tools/.image_cache/full/` already held
    every render, so zero CDN hits, exactly as the API policy requires.
    **Two guards were added because the failure mode here is a silent green.** No
    test had ever opened the real asset (every consumer overrides
    `hashIndexProvider`), so changing `artBoxRoi` without rebuilding would have
    left `flutter test` entirely green and broken only the running app — where it
    surfaced as *"the camera could not be started"*.
    `test/features/scan/hash_index_asset_test.dart` now ties the committed asset
    to this build's ROI and descriptor, and `tools/test_build_hash_index.py`
    asserts the 622x622 square. Relatedly, **`tools/dump_phash_fixtures.py` was
    already broken** independent of any of this: it read the *v1 cropped-art*
    cache and hashed whole files with no ROI crop, so its own cross-check against
    the index failed and the fixture tests only ever compared Dart against each
    fixture's self-recorded hash. It now imports `ART_BOX_ROI`/`roi_pixel_box`
    from the builder, so there is one definition and the cross-check is real.
    **Scan-pipeline defect fixes**, in rough order of how badly they bit:
    - **`ScanPaused` is `@Riverpod(keepAlive: true)`.** Nothing watches it —
      writer and reader both use `ref.read`, which closes its subscription in a
      `finally` and schedules disposal — so step 14's "don't detect and hash
      behind a review panel" optimisation was **inert**, exactly the trap
      `ScanViewportSize`'s own doc comment warns about.
    - **The debounce compares index passcodes now.** The index keys every
      `card_images[i].id` while `cards` stores only `card_images[0]`, so an
      alt-art match resolved to a card whose passcode was *not* what the next
      frame carried — the suppression never fired and the review panel re-opened
      on the card just logged. `ArtCandidate.rankedPasscode` +
      `ScanState.matchedIndexPasscode` fix it; the regression test was **verified
      to fail** against the old code before being kept.
    - **`_resolveArtMatch` paused before its awaits**, not after: during 1-5 DB
      round trips one glare-blink frame could move the status on and silently
      discard a match the agreement gate had already accepted.
    - **A dead detector isolate no longer wedges scanning.** `detectCard` had no
      timeout and the spawn registered no `onExit`/`onError`, so a dead worker
      blocked `artReadings` before any `yield` — recognition dead, every on-screen
      signal green. Now: 2 s request timeout, both ports registered, three
      timeouts retire the worker to the in-process fallback, and a new `det:`
      diagnostics line (`DetectorHealth`/`describeDetectorHealth`, host-tested).
    - **`passcodeReadings` is self-paced**, like `artReadings` since step 14: a
      broadcast controller buffers for a paused subscriber, and an `await for`
      whose body awaits *is* paused — so a slow ML Kit read grew an unbounded
      backlog and the counters ran over frames from seconds ago. `CameraService`
      gained `latestInputImage`, replaced in lockstep with `latestArtFrame` under
      one `frameSequence`.
    - **An index-load failure says so.** A `FormatException` from the ROI header
      guard reached the user as a camera error with a Retry that could not fix it;
      now it gets its own panel, and `retry()` invalidates `hashIndexProvider`.
    - **`extractPasscode`'s join fallback is gated on digits-and-spaces.**
      `ATK/2500  DEF/2100` used to join to `"25002100"` — a second distinct value
      alongside the real passcode, so the frame was discarded as ambiguous and
      passcode mode read *nothing* on the monsters most worth logging.
    - **`HashIndex.rank` is a bounded partial selection.** The diagnostics path
      ranks unthresholded, which allocated 14 641 `HashMatch`es and fully sorted
      them to take three, per frame, on the UI isolate — while someone was
      watching the overlay to find out why scanning felt slow. A test compares it
      against a full sort at every `n`, since being indistinguishable is the
      point.
    - **Both overlay painters derive their aspect from `latestArtFrame`**, not
      the preview: CameraX picks Preview and ImageAnalysis resolutions
      independently, and while the *ROI* mapping is self-correcting under a
      mismatch, a painter is not. `_SearchRoiOverlay` also documents what it
      cannot show (it is a round trip through exact inverses, so it verifies the
      margin, never the aspect) — the new `frame: 720x1280 (0.563) / preview
      0.750` diagnostics line is what actually settles that on a device.
    - Smaller: a 180° re-hash when the first pass finds nothing in range (tilt
      folds to [0, 90), so an upside-down card passes every shape gate and hashes
      to noise); the luma copy skipped in passcode mode via
      `CameraService.artCaptureEnabled`; `_onFrame` no longer spending the
      throttle window on a frame it drops, with both conversions wrapped so a
      malformed buffer can't take the OCR path down with the artwork path.
    **Collection tile**: the grade chip shrank (new `ConditionChipTokens` — it had
    no size tokens at all, only generic `AppSpacing` and inherited body size) and
    the artwork grew to `list * 1.2`. **The row height is unchanged**, and the
    reason is worth keeping: height is set by the tallest child, the 3×30 action
    column, so artwork below ~61.7 wide is free and anything above it grows every
    row in the list.
    **Still open**, all three deliberately and all needing hardware rather than
    more analysis: `CardDetectionTuning.innerQuadMinAreaRatio` (review finding 7)
    stays 0.78 until the now-live `_findArtBox` shows whether the nested descent
    still earns its keep; the passcode ROI filter stays off (its coordinate space
    is genuinely wrong — the *unrotated* sensor size is passed for boxes reported
    in rotated space); and `ScanTuning.frameInterval` stays 300 ms (**superseded
    in step 17**, which split it). On-device, the
    things to look at first are the `art box:` diagnostics line — it should now
    read **locked** rather than `fixed roi` on standard cards, for the first time
    ever — and the new `frame:`/`det:` lines.

17. Recognition-latency pass — split frame cadence, batched candidate lookup
    ← done (verified: `flutter analyze` clean, full `flutter test` green at
    **326 tests**, `pytest tools/` green). **No DB migration, no schema change,
    no new dependency.** Nothing here touches the descriptor, the index, the
    detection algorithm or any shape/matching threshold — this is purely about
    the ~700 ms of *waiting* between a card landing in the reticle and the review
    panel appearing (see `docs/next-session-brief.md`, changes 2 and 3).
    **`ScanTuning.frameInterval` is gone, split in two**: `ocrFrameInterval`
    (300 ms, unchanged, passcode mode) and `artFrameInterval` (**150 ms**, the
    primary artwork path). Halving the *shared* constant would have doubled the
    ML Kit `InputImage` conversion rate too, which the brief didn't ask for and
    nothing needed. Three things had to be true before the artwork cadence could
    safely drop, and all three arrived in steps 14-16: detection runs on a worker
    isolate (so a faster cadence no longer competes with Flutter painting the
    preview), `ScanPaused` genuinely pauses (it was `autoDispose` and inert), and
    `artReadings` polls `frameSequence` rather than subscribing — so it **cannot**
    build a backlog. That last point also bounds the benefit: the loop self-paces
    at `max(artFrameInterval, D)`, so if the diagnostics `det:` line reads ≥
    150 ms this bought little and detection cost is the real target. **One clock,
    not two**, because the pipelines are mutually exclusive: `artCaptureEnabled`
    is false exactly in passcode mode and `passcodeReadings` is inert outside it,
    so `_onFrame` picks its interval from that same flag. Sharing `_lastEmit`
    across a mode switch only delays the first frame after it by one interval.
    **`_onFrame` now converts exactly one representation per frame**, `if
    (wantArt) art = ... else input = ...`. Both conversions are real full-frame
    copies (~1 MB/s at this cadence), and the ML Kit one had been running in
    artwork mode where **nothing** reads it — `camera.frames` has no production
    listener, and `latestInputImage` is only read by `passcodeReadings`. This is
    step 11's `artCaptureEnabled` argument applied in the other direction, and it
    is what keeps "passcode mode's cost is unchanged" true rather than merely
    intended. Consequence documented on the interface: `latestInputImage` goes
    *stale*, not null, in artwork mode, and `frameSequence` now identifies
    whichever cache the live mode fills.
    `ScanOutlineTokens.transition` followed the cadence 260 → **160 ms**: its
    whole rationale is that each detection has just about arrived at its target
    when the next lands, and a glide longer than the interval means the outline
    trails the card permanently instead of tracking it. Cosmetic only.
    **`PHashArtMatcher.match()` does one DB read, not one per candidate.** It sat
    *after* the agreement gate, so up to `ArtMatchTuning.candidateCount` (5)
    serial round trips through the sqflite isolate were latency the user waited
    through. New `CardDao.getByPasscodes` — the **first dynamic-`IN` DAO** in the
    codebase, so it sets the convention: placeholders built from the argument's
    **length only** (never its contents, so it stays parameterized), an early
    `return const []` because `IN ()` is invalid SQL and an empty candidate list
    is a normal frame, and a documented contract of *existing rows only, in
    unspecified order*. Three invariants had to survive, all now test-pinned:
    ranked order (restored by walking `result.matches` and indexing the rows, not
    by iterating the rows), the absent-passcode skip (the index keys every
    `card_images[i].id` while `cards` stores only `card_images[0]`, so an alt-art
    key simply has no row — the map miss *is* the old null), and
    `ArtCandidate.rankedPasscode` still carrying the index key, which
    `ScanState.matchedIndexPasscode` and step 16's debounce fix depend on.
    **Gotcha worth keeping**: `passcode` is the primary key, so SQLite satisfies
    `passcode IN (...)` from that index and returns rows in **ascending passcode
    order** — *not* rowid/insertion order, which is what the ordering test was
    first written against, making it vacuously green. It now uses Blue-Eyes
    (`89631139`, the nearer card) against Mirror Force (`44095762`), so DB order
    is the exact reverse of ranked order, and it was **verified to fail** against
    a naive return-the-rows implementation before being kept.
    **Still open**, unchanged: `autoMatchMaxDistance`/`maxHammingDistance` at
    48/72, `CardDetectionTuning.innerQuadMinAreaRatio` at 0.78, the passcode ROI
    filter off, and `artAgreementFrames` at **2** — deliberately not touched.
    Dropping it to 1 would halve the remaining wait and the statistical case for
    2 is much weaker at 256 bits, but frame agreement also rejects motion blur
    and mid-movement frames, which descriptor width does nothing for; it is a
    quality trade, not a free win. On device the things to read are the `det:`
    line (whether `D` < 150 ms, i.e. whether this cadence change landed at all)
    and still the `art box:` line reading **locked** rather than `fixed roi`.

18. Sixth on-device feedback pass — frame-quality gating, honest scan feedback,
    collection browse modes and one filter sheet ← done (verified: `flutter
    analyze` clean, full `flutter test` green at **384 tests**, `pytest tools/`
    green). **No DB migration, no schema change, no new dependency.** Nothing
    here touches the descriptor, `assets/card_hashes.json`, the detection
    algorithm or any shape/matching threshold.
    Context: ~40 cards logged in ~7 minutes on device, so the concept works —
    but recognition sometimes sat in a loop showing `card detected` in
    diagnostics with nearest distances of 40–90 and never resolving.
    **On the stack question that prompted this:** Pinecone and Milvus were
    considered and rejected. The index is 14 641 × 256-bit ≈ 469 KB and
    `HashIndex.rank` is a bounded partial selection with SWAR popcount, so
    retrieval is not the bottleneck; Pinecone is a network service (kills
    offline-first) and Milvus is a server that cannot be embedded in an APK;
    both are outside the locked stack. Above all the failure is in the
    **descriptor**, not the search — no index structure recovers information a
    glare-blown crop already destroyed. ML Kit remains the passcode-OCR path
    only.
    **The status banner was lying, and that was the headline defect.** A frame
    yielding `ArtFrameStatus.detected` whose top match sat beyond
    `autoMatchMaxDistance` fell into `_onArtReading`'s **empty-frame branch** →
    `ScanStatus.detecting` → **"Point at a card"**. The app had found,
    rectified and hashed the card and was telling the user it could see
    nothing, with no explanation and no way out. New `ScanHint` enum
    (`none/blurry/glare/identifying/unidentified`) on `ScanState` — separate
    from `ScanStatus` precisely because several distinct frame outcomes all
    leave the machine in `detecting` — drives a banner that now says "Card
    found — identifying…", "Hold steady", "Reduce glare — tilt the card", or,
    after `FrameQualityTuning.unmatchedStreakForHint` frames, **"Can't identify
    this card"** with a tap action. That action is a new
    `ScanController.showBestGuesses()`: `showCandidates()` could not be reused
    (it is guarded on `status == matched`), and the ranked hits out to
    `maxHammingDistance` (72) already existed — they had simply never been
    offered from `detecting`. It pauses *before* its awaits like
    `_resolveArtMatch`, auto-selects nothing, and funnels into the same review
    gate.
    **Frame quality is measured on exactly the pixels that get hashed.** New
    pure, host-tested `lib/features/scan/frame_quality.dart` — Laplacian
    variance for blur, clipped-highlight fraction for glare — called in
    `PHashArtMatcher._rank` between `_cropFromRoi` and `phashFromLuma`. Pure
    Dart rather than OpenCV inside the detector, following `card_quad.dart` for
    the reason given there: the detector cannot be host-tested, and a wrong
    threshold here does not crash, it silently stops recognising cards.
    Checking *before* hashing means a rejected frame skips the DCT and the index
    scan, so the gate costs less than it saves. New `ArtFrameStatus.lowQuality`;
    `FrameQuality?` rides `ArtFrameResult` → `ArtReading` (nullable, because
    `ArtFrameResult.noFrame`/`.notDetected` are `const` statics).
    **A rejected frame is *skipped*, not counted as empty** — the whole point.
    Previously one glare blink or shake took the empty-frame branch and
    **cleared the agreement buffer**, so a card reading cleanly 80 % of the time
    could never accumulate two consecutive good frames. Skipping is also
    deliberately distinct from an empty frame because `emptyFrameCount` drives
    the post-confirm debounce, and a stream of blurry frames must not retire a
    confirmed card's suppression while it sits under the lens.
    `ScanState.qualitySkipStreak` + `FrameQualityTuning.maxConsecutiveSkips` is
    a **non-optional failsafe**: both thresholds are absolute values on a
    scene-dependent measure, and without a floor a bad calibration means
    recognition never works again with every on-screen signal green. Four of the
    five gate tests were **verified to fail** with `maxConsecutiveSkips = 0`
    (which reproduces the old code) before being kept.
    **Exposure compensation** (decided with the user): `CameraService` gained
    `setExposureCompensation`, implemented with the existing `_tryCamera` guard
    and clamped to the device's reported range (the plugin *throws* outside it).
    The decision is the pure, tested `nextExposureOffset` — steps down while
    glare is over the gate, back up only once it clears
    `glareRecoveryFraction` (strictly below `maxGlareFraction`, so the two form
    a hysteresis band rather than oscillating), bounded by `exposureFloor` and
    rate-limited by `exposureInterval`. Applied from the `artReadings` loop,
    which already holds the camera, and **reset whenever
    `CameraHealth.restarts` advances** — `_meter()` re-asserts
    `ExposureMode.auto` on every start, so a cached value would describe a
    setting the device no longer has. Safe for matching because a pHash
    thresholds each DCT coefficient against the block **median**, so uniform
    darkening barely moves the descriptor while un-clipping highlights moves it
    a great deal, in the right direction. Highest-risk item here; the live
    offset is on the new `qual:` diagnostics line so it is observable.
    **Failure-sample capture**, and the reason it exists:
    `.claude/skills/scan-pipeline.md` forbids adding image preprocessing
    "before you have real failure samples to test against", and there was no way
    to obtain one — the rectified card lives for a few milliseconds inside a
    detector isolate and is written nowhere. `lib/features/scan/scan_sample.dart`
    writes the card and its art crop as binary **PGM** (a 15-byte header plus the
    bytes we already hold — no encoder, no dependency, and PIL/OpenCV open it
    directly) plus a JSON sidecar carrying quality, distances and
    `artBoxLocked`, then hands them to `share_plus`. Retained **only while
    diagnostics is on** (`rankFrame(includeNearest:)` already carries that flag)
    since a rectified card is ~260 KB. Highlight normalisation with an index
    rebuild stays deferred until such samples exist.
    **Bug found by the new tests**: `assessCrop` originally strided *both* axes,
    which aliases — on a 1px checkerboard every sampled pixel lands on one parity,
    so all Laplacian responses are identical and the variance reads **zero**, i.e.
    the sharpest possible input scored as perfectly blurred. It strides **rows**
    only now (also the faster memory order), pinned by a test at four periods.
    **Scan screen UI**: the surface hint moved into `_TopOverlays`' column below
    the status banner. It used to be `Positioned` against `reticle.top` while
    the banner grew down from the app bar — two unrelated coordinate systems
    both advancing toward the middle, overlapping by ~35 pt at 360×640. This is
    *not* the trap `_ReticleOverlay` documents (a **centred** column containing
    the box would move the drawn box while `detectionRoiInFrame` kept searching
    the old region); `_TopOverlays` is top-aligned and holds no box, so the
    reticle stays a `Center` widget. Diagnostics is now gated on
    `detecting`/`reading`, so it no longer covers the review panel — it was
    stale there anyway, since `_resolveArtMatch` pauses `artReadings`. And
    `_SetPicker` moved **above** the condition/edition/language chips in the
    review gate (its gap became trailing rather than leading, so the panel
    spaces correctly whether it renders or self-hides), matching the same move
    in the collection edit sheet: the picker's search field raises the keyboard,
    which covered everything below it.
    **Collection: two minified grid modes.** New `CollectionViewMode`
    (`standard`/`minifyStandard`/`minifyFull`) persisted by name in `meta` as
    `settings.collection_view_mode`, chosen from a "View" menu beside the filter
    button. Both minified modes are **grids**, because the point of minifying is
    cards per screen and a row holds one card however little it says. New
    `collection_grid_tile.dart` carries no +/−/delete — those live on the
    standard row and the detail screen — but does keep an `xN` badge, the one
    ownership fact a cell would otherwise lose. `CardThumbnail.size` became
    **nullable**, meaning "fill the space the parent gives me" (an `AspectRatio`
    instead of the fixed `SizedBox`); it could not stretch before, which was the
    single blocker for a grid. The grid uses `maxCrossAxisExtent`, not a fixed
    column count, so the layout follows the viewport.
    **Collection: one filter sheet replaces both chip rows.** The search box is
    now followed by one row — filter button (left, with an active-count badge)
    and the view menu (right). `CollectionFilter` gained `setName`, `edition`,
    `language`, `level`, `frameType`, `race`, `attribute`, `archetype` and
    `atk`/`def` (`NumericRange`, either bound optional) — plus, first, a
    `copyWith`, since the controller used to rebuild all of it field-by-field in
    every setter and that does not survive fourteen fields. **`getAll` needed no
    join change**: it already `JOIN cards c` and selects every column involved,
    so each filter is a pure `WHERE` addition. (`cardType` had existed in the
    model *and* the SQL since step 3 and had simply never been exposed.) One new
    `CollectionDao.filterOptions()` returns a `CollectionFilterOptions` bundle —
    one method rather than nine, because the alternative is nine providers and
    nine invalidation sites, and **the invalidation is the subtle part**:
    `collectionFilterOptionsProvider` replaces `collectionRarityOptionsProvider`
    and inherits its documented constraint of never watching
    `collectionEntriesProvider` (chained async invalidation mid route-transition
    schedules a scope refresh from inside a build). Options are deliberately
    **unfiltered** — offering only what survives the current filter would strand
    the user after one narrowing — and NULLs are dropped everywhere except
    rarity, where null is the meaningful "no rarity" option. The sheet edits a
    **local draft** applied on a button: it covers the list it filters, so live
    updates would be invisible, and each change would re-run `getAll` through the
    sqflite isolate unseen. `cleared()` keeps the search query and the sort —
    Reset must not empty the box the user typed into. Sort moved to an app-bar
    `PopupMenuButton` beside its own direction toggle (it lived inside the rarity
    row that was deleted; sorting is not a filter).
    **Test gotchas**: the three chip tests in `collection_screen_test` now go
    through an `applyFilterChip` helper — tapping a chip alone would assert
    against an unchanged list, since the draft only reaches the list on Apply.
    Both the advanced tick box and the chips inside the sheet need
    `ensureVisible` in the 600 pt test viewport. The `enterText(find.byType(
    TextField))` search test still works only because the filter and view
    controls are buttons, not fields.
    **App name**: no source change was needed for Android —
    `android:label="YGO Scanner"` has been correct since `7bccff3` and the
    debug/profile manifests declare no `<application>` element, so a launcher
    reading `ygo_scanner` is a **stale install** (Android caches the label per
    package; `flutter clean` + uninstall + reinstall). iOS `CFBundleName` and
    the untouched-from-template `pubspec` description were genuinely wrong and
    are fixed. `pubspec` `name:` must stay `ygo_scanner` — 50+ files import
    `package:ygo_scanner/...`.
    **Still open**, unchanged: `autoMatchMaxDistance`/`maxHammingDistance` at
    48/72, `CardDetectionTuning.innerQuadMinAreaRatio` at 0.78, the passcode ROI
    filter off, `artAgreementFrames` at 2. **All of `FrameQualityTuning`'s
    thresholds are first guesses** and are the main thing to calibrate on device
    from the `qual:` line — `minSharpness` especially, since it is an absolute
    value on a scene-dependent measure.

19. Seventh on-device feedback pass — lenient artwork matching, top-overlay
    layout, set search box ← done (verified: `flutter analyze` clean, full
    `flutter test` green at **397 tests**, `pytest tools/` green). **No DB
    migration, no schema change, no new dependency.** Nothing here touches the
    descriptor, `assets/card_hashes.json`, the detection algorithm or any
    shape/quality threshold.
    Context: ~30 more cards logged. The recurring report was that the banner said
    "Can't identify this card", and tapping **Show best guesses** then showed the
    right card at the top — *every time*.
    **So the app was hiding an answer it already had, and that was one line.**
    `PHashArtMatcher` always ranks at `ArtMatchTuning.maxHammingDistance` (72 of
    256), but `_onArtReading` discarded any top hit worse than
    `autoMatchMaxDistance` (48) into the **empty-frame branch** — the same branch
    a frame containing no card at all takes. So the 48-72 band cost a "can't
    identify this card", a wait for `unmatchedStreakForHint` (6) frames and an
    extra tap, to reach a card the app had already found, rectified, hashed and
    ranked correctly. The gate is now `if (top == null)`.
    `autoMatchMaxDistance` **keeps its value and loses its job**: it selects how
    the review gate *describes* a match, not whether one is shown. Past it the
    panel hedges — new `ScanState.matchedDistance` + `AppStrings.scanLowConfidence`
    ("Best guess — check the picture"). The measured case for 48 (the perturbation
    study in its own doc) is exactly what makes it a meaningful *clean read vs
    usable but degraded* boundary, so the constant survives with its evidence
    intact. `matchedDistance` is bound to the card **structurally** in `copyWith`
    — a new `matchedCard` carries only the distance passed with it, null for an
    exact OCR match — rather than by a clear flag every future caller would have
    to remember.
    What makes the leniency safe is unchanged and worth naming: two agreeing
    frames (`artAgreementFrames`), the quality gate, the 72 threshold itself, and
    above all the review gate — nothing is written without an explicit confirm,
    so a marginal guess costs one tap while hiding a good one cost the whole scan.
    The statistics agree: only **1.37 %** of the 14 641 indexed cards have any
    other card within 72, and a random non-card image's nearest entry sits ~98
    away, so this band is populated by real cards photographed poorly, not by
    noise.
    **The escape hatch had to grow to match.** "Not the right card?" lost its
    `candidates.length > 1` guard (a single candidate used to hide it entirely,
    which is the case a wrong guess is most likely to produce); with alternatives
    it opens the ranked panel, with only one it goes straight to manual search.
    And since every in-threshold hit now auto-presents, reaching `showBestGuesses`
    at all means `match()` is empty — so `ArtMatcher.bestGuesses()` was added,
    re-ranking the last frame's hash **unthresholded**. `PHashArtMatcher` caches
    `_lastHash` beside `_lastResult` (dropped per frame, re-set only if that frame
    reached hashing, so guesses can never describe a card that has left the lens)
    and both paths share one `_resolve(matches)` — which carries three invariants
    that are silent when lost: ranked order, the skip for index passcodes absent
    from `cards`, and `rankedPasscode` for the debounce.
    **The top overlays are capped to the band above the reticle.** The diagnostics
    box is eleven lines growing down from the app bar while the reticle is
    centred, so it painted over the guide box the user has to aim through.
    `_TopOverlays` is now a `LayoutBuilder` whose `constraints.biggest` *is* the
    viewport (it is a non-positioned child of an expanded `Stack`), so the band is
    measured against the same `reticleRectInViewport` the detector's search region
    comes from; the column sits in a `ConstrainedBox` with the diagnostics box
    `Flexible` and scrolling internally, so the fixed-height banner below is never
    what gets squeezed out. Type dropped 12 → 10pt with a 1.3 line height and the
    `[ save this frame ]` row became an icon. **Verified to fail** with the cap
    removed.
    **Found while measuring that band: the app bar was being counted twice.**
    `Scaffold(extendBodyBehindAppBar: true)` reports the app bar to the body *as*
    `MediaQuery` padding — which the overlays' own `SafeArea` already consumes —
    and the padding then added `kToolbarHeight` again. That left a whole toolbar
    of empty space between the icons and the overlays while costing 56pt of the
    band, and it is precisely the "should sit just below the buttons" complaint.
    The inset is now just `AppSpacing.sm`.
    Order in the column is now diagnostics → **surface hint** → status banner: the
    hint says how to make recognition work at all, which is worth reading before
    the running commentary on whether it is working. The existing geometry test
    flipped with it (it asserts the order, not mere presence, and caught this
    change as intended).
    **The collection Set filter is a search box.** It was a `Wrap` of one chip per
    owned set — unbounded, with ~30-character labels, so it was taller than the
    rest of the sheet combined and still had to be read one chip at a time. New
    `lib/shared/widgets/searchable_text_picker.dart` is the `String`-keyed sibling
    of `PrintingPicker`, copying its proven contract (the field doubles as query
    and selection; blur snaps back to the selected label so a half-typed query
    can never read as a choice; results capped at
    `PrintingPickerTokens.maxListHeight`). A **separate widget** deliberately:
    `PrintingPicker` is keyed to `Printing`/`int?` across three live call sites in
    the logging flows, and making it generic would churn all of them to save a
    file. What they now share is the part that would actually be wrong if it
    drifted — the filter rule, extracted to `matchesSearchTerms` in
    `lib/core/search_terms.dart` and unit-tested there, with `filterPrintings`
    delegating to it. **Selection is always one of `options.setNames`**, so
    `CollectionFilter.setName`, `getAll`'s `p.set_name = ?` and `filterOptions()`
    are all untouched — no DAO change, and a chosen filter can never match
    nothing. The `applyFilterChip` test helper is unchanged: it only ever drove
    condition/rarity/advanced chips, which stay chips.
    **Test gotcha**: inside the filter sheet, `find.text('Metal Raiders')` also
    matches the collection list *underneath* the modal — the new test scopes its
    finders to `find.byType(SearchableTextPicker)`. And the diagnostics-geometry
    test sets a phone-shaped 393x851 viewport on purpose: the band is a function
    of viewport height, and at the default 800x600 it falls under
    `ScanDiagnosticsTokens.minBandHeight`, where the floor deliberately wins.
    **Still open**, unchanged: `maxHammingDistance` at 72,
    `CardDetectionTuning.innerQuadMinAreaRatio` at 0.78, the passcode ROI filter
    off, `artAgreementFrames` at 2, and every `FrameQualityTuning` threshold still
    uncalibrated on device. The new question this pass raises: with the 48-72 band
    now visible in use, the `d=` values on cards that previously failed are the
    evidence for whether **72 itself** is the right ceiling.

20. CSV import — merging an existing collection into this one ← done (verified:
    `flutter analyze` clean, full `flutter test` green at **464 tests**,
    `pytest tools/` green). **No DB migration, no schema change.** The first
    **new runtime dependency since step 18**: `file_selector` (see below).
    Lives on the Statistics screen, beside the export it reverses.
    **The export format is now a real interchange format, not just an output.**
    `lib/data/export/collection_csv_parser.dart` is the reader, deliberately in
    the same directory as the writer: they are one format, and the escaping
    rules (quoted fields, doubled quotes, embedded newlines, the formula guard)
    have to agree exactly. A round trip through both is the cheapest proof that
    they do, and `collection_csv_parser_test.dart` runs one. The parser is
    hand-written rather than a split on commas and newlines because `notes` is
    free text that can legitimately contain both; it accepts `\r\n`, bare `\n`
    and bare `\r`; it **matches columns by header name, not position** (a
    spreadsheet round trip reorders columns, and binding to position would
    silently read a rarity as a condition); only `passcode`, `condition` and
    `quantity` are required. It also **un-guards the formula prefix**, or a name
    would accumulate an apostrophe on every export/import cycle. One bad row is
    reported with its line number rather than failing the file — a collection
    CSV that has been through a spreadsheet is quite likely to have one stray
    value, and refusing nine hundred good rows over it is worse.
    **The merge rule is one pure function**, `planCollectionImport`
    (`lib/data/import/collection_import_plan.dart`), because every way of
    getting it wrong is silent: a duplicated row looks like a real second entry
    and a wrongly merged one looks like a card the user never owned. Two
    strategies, chosen by the user per import: `keepExisting` (the default —
    the existing row is left exactly as it is, so **re-importing this app's own
    export is a no-op**, which is test-pinned both ways) and `sumQuantities`.
    It folds rows into a **working set** rather than matching each against an
    unchanging snapshot, and that is load-bearing: a file holding two identical
    rows describes *one* entry, and a snapshot planner would emit two inserts —
    the second either violating the `collection_entries` UNIQUE constraint or,
    for a null `printing_id` where the constraint cannot fire, quietly creating
    the duplicate row the collection screen would then show twice. The key is a
    Dart record `(passcode, printingId, condition, edition, language)`, whose
    structural equality gets the null-printing case right for free — the case
    every other write path in the DAO special-cases by hand.
    **Resolution is the other half.** A CSV names a set the way a human does
    (code, name, rarity) while the collection stores a `printings.id`.
    `resolveImportRow` tries `(set_code, rarity)` first — the `printings` UNIQUE
    key, so it is exact — then `(set_name, rarity)`, then either alone, case-
    and space-insensitively. **No match imports the row without a set rather
    than dropping it** (losing the set is bad, losing the card is worse) and is
    counted so the dialog can say how often it happened. A passcode with no
    `cards` row is **skipped**: `collection_entries.passcode` is a foreign key,
    so the insert would be rejected anyway, and the row would have no name or
    art to show. Usually it means a re-sync is due.
    **Two phases, never one.** `CollectionImporter.preview` reads and resolves
    without writing; `apply` writes only what was confirmed. The counts are
    strategy-independent (test-pinned), so the dialog can report "42 new, 14
    already yours, 3 skipped" *before* asking the merge question — and the
    question is only asked when something actually matched. New DAO methods:
    `PrintingDao.getForPasscodes` and `CollectionDao.getEntriesForPasscodes`
    (both following step 17's dynamic-`IN` convention — placeholders from the
    argument's length only, early return for empty) and
    `CollectionDao.applyImport`, one transaction taking **explicit
    instructions** rather than raw rows. That split is the point: the DAO
    executes, the pure planner decides, and duplicating the "same entry" rule in
    SQL is how the two would drift. Quantities are **absolute, not deltas**, so
    an import somehow applied twice lands on the same numbers.
    **`file_selector`, not `file_picker`.** The app could not open a
    user-chosen file at all — exports go to app-documents, which Android does
    not let you browse. `file_picker` 8-11 pins `win32 ^5.9` against
    `share_plus`'s `^6.0.1` and pub resolves it down to a 2021-era **3.0.4**;
    `file_selector` is the Flutter-team package, resolves clean, and is a better
    citizen. It sits behind a `CsvFileSource` seam (`csv_file_source.dart`),
    exactly like `CameraService`/`PasscodeOcr`: it is the one part that cannot
    run in a widget test, and everything interesting is behind it, so the whole
    flow from button tap to written rows is host-testable. Its type filter is
    deliberately **broad** (`csv`/`txt` plus five MIME types) — a `.csv` from
    Drive or a mail attachment is reported under any of them, and filtering
    tightly means the user's own export shows up greyed out. Picking the wrong
    file is cheap and well explained: the parser rejects anything without the
    required columns before a row is written.
    **UI**: the export and import buttons moved into a shared `_Actions`, which
    is now rendered in the **empty-collection branch too** — importing into an
    empty collection is the *main* case for that button and it was previously
    unreachable, since the whole body was replaced by the empty message.
    Counts render as `RichText` (bold number, muted label) and each line is
    hidden at zero, because a dialog reading "0 skipped, 0 unrecognised" warns
    about problems that do not exist. `RadioGroup` rather than the per-tile
    `groupValue`/`onChanged`, which Flutter deprecated after 3.32.
    **Test gotchas**: `find.textContaining` skips `RichText` unless given
    `findRichText: true`. An "empty collection" cannot be tested with an empty
    database — `flutter test` runs with `kDebugMode == true`, so
    `debugSeedCollectionProvider` fills it first; the test stubs
    `collectionStatsProvider` instead. And the actions sit at the end of a lazy
    `ListView`, so at the default 600pt viewport they are never built and
    `ensureVisible` cannot find them — hence the `useTallViewport` helper.

21. Eighth on-device feedback pass — the scan-pause lifetime bug, a readable
    diagnostics band, lazily-fetched artwork, multi-select delete ← done
    (verified: `flutter analyze` clean, full `flutter test` green at **503
    tests**, `pytest tools/` green). **No DB migration, no schema change, no new
    dependency.** Nothing here touches the descriptor,
    `assets/card_hashes.json`, the detection algorithm or any shape/matching/
    quality threshold.
    **Scanning died for the rest of the app's life after declining one card**,
    and this was the worst defect the app has had: preview live, camera
    streaming, reticle drawn, nothing ever recognised again, and only relaunching
    fixed it. `ScanPaused` is `@Riverpod(keepAlive: true)` — correctly, since
    step 16 measured that autoDispose made the whole pause inert — while its only
    writer, `ScanController`, is autoDispose, and **nothing ever cleared it**. So
    any teardown with a result on screen pinned it `true` for the process and
    `artReadings` skipped every subsequent frame. Backing out of a review panel
    is the likely repro: `dismiss()` does clear the pause, but after a dismiss
    the panel re-opens on the same card once `dismissCooldown` expires.
    Fixed in two halves, both needed. **Releasing the pause is now structural**:
    `_resolveArtMatch` and `showBestGuesses` wrap their bodies in
    `try/catch/finally` with a single `handedOff` flag set only on the branch
    that actually puts a panel in front of the user, so the `status != reading`
    early return, the empty-candidates branch and any throw all release it by
    construction. The `catch` is not optional decoration: `_resolveArtMatch` is
    called *unawaited* from a `ref.listen` callback, so without it a matcher or
    DB failure was both an unwatched wedge and an unhandled async error, and the
    regression test could not be written at all. And **`_ScanScreenState`
    clears any residue on entry**, from a post-frame callback. On *entry*, not on
    the previous screen's exit, for two reasons: a fresh `ScanController` always
    starts in `detecting`, so unpaused is the only correct state there however
    the last session ended; and **Riverpod asserts on cross-provider writes from
    a provider's `build`, from its own `ref.onDispose`, and from any widget
    life-cycle including `dispose`** — all three were tried, all three throw, and
    a post-frame callback is outside the build phase, which is the same reason
    `_ViewportProbe` publishes its size from one. (Noted while proving that:
    `_ViewportProbeState.dispose()` writes to `ScanViewportSize` and so trips
    the same assert whenever the scan screen is torn down mid-frame. Pre-existing,
    debug-only, left alone — but it is why the reset here could not simply copy
    it.) Both halves were **verified to fail** against the pre-change code.
    Flagged, not fixed: `_MatchedPanel`'s confirm button shows the "added to your
    collection" SnackBar unconditionally, so a write failure reports success.
    **The diagnostics readout is readable, and this was arithmetic, not taste.**
    On a 393x851 phone the band above the guide box was ~91pt (floored to
    `minBandHeight` 96), the fixed-size status banner took ~44 of it first, and
    the content needed ~141 — so the box scrolled and the lines that matter for
    tuning, the last ones, were exactly the ones hidden. Four levers, all spent:
    the **status banner moved inside the orange guide box**, replacing the static
    "fit the whole card inside the box" (which the box's own shape already says)
    and freeing the whole band for the readout; `ScanReticleTokens.verticalOffsetFraction`
    = **0.03** drops the box, widening the band directly; `fontSize` 10 → **9**;
    and the frame-status line **absorbs** the art-box line
    (`card detected · art box: located`), 9 lines → 8. Result at 393x851: 116.6pt
    of band against 101.6pt of content. Two findings worth keeping:
    - **The "white rectangle covering the debug text" is the search-ROI outline
      reading *through* the box.** `_SearchRoiOverlay` is an earlier stack child,
      so its 1.5pt muted stroke showed through the 0.8-alpha scrim. Now 0.95.
    - **The existing 393x851 regression test could not see the bug.** It set
      `physicalSize` but not `tester.view.padding`, and `Scaffold` with
      `extendBodyBehindAppBar` reports the body's `padding.top` as
      `max(view padding, app bar height)` — so it measured a 130pt band where the
      device has 91. The test passed while the device clipped.
      `FakeViewPadding(top: 39)` is now part of it.
    The offset lives in `reticleRectInViewport` — the single source of truth —
    so the drawn box, the searched region and the debug outline move together;
    it is **clamped against the ROI margin, not the box**, since
    `detectionRoiInFrame` inflates by `reticleRoiMargin` and then clamps in frame
    space, where an over-large offset would silently truncate the search region on
    one edge with no visible symptom. 0.03 is capped by `_HelpPanel`: it leaves
    ~12pt of clearance at 393x851, and 0.043 overlaps. `_ReticleOverlay` is now
    `Positioned.fromRect` rather than a `Center`, which *removes* the trap its
    old doc comment warned about instead of documenting it, and carries a
    `scanReticleKey` so the screen test can assert the drawn box **equals**
    `reticleRectInViewport` on all four edges — the correct form of the old
    `center.dy == height / 2`, which was only ever a proxy for it. The new
    "fits without scrolling" test asserts `maxScrollExtent == 0` rather than a
    pixel height, so it measures the property complained about and survives
    font-metric drift; it was checked to fail with the offset and font reverted.
    `CameraScanService._meteringPoint` follows the box down.
    **CSV-imported cards had no artwork, ever.** `CollectionImporter.apply`
    writes through `CollectionDao.applyImport`, bypassing
    `CollectionRepository.addOrIncrement` — the only place
    `ensureImageDownloaded` is ever fired — so imported rows keep a NULL
    `local_image_path`, and every collection surface used the plain
    `CardThumbnail`, which reads the path and never fetches. `CardArtThumbnail`
    (which already existed for the scan candidates) was widened to
    `CardThumbnail`'s full API — nullable `size`, `aspectRatio`, `fit` — and now
    backs the list tile, both grid cells and the detail screen. Owned cards
    **never touch the provider**, which is what makes it safe on every surface
    and is the first thing its test pins. `cardArtProvider` calls `ref.keepAlive()`
    **only on a hit**: caching a miss would mean one offline moment blanked a card
    for the app's lifetime. Fixed at display rather than at import (decided with
    the user): a 900-row import would otherwise be a 900-request burst at
    YGOPRODeck for cards the user may never look at. A minified grid still puts
    15-30 cells on screen at once, so `CardImageDownloader` gained a
    `ConcurrencyLimiter` (a completer FIFO, no package) at
    `kMaxConcurrentDownloads = 4`, matching the tool's `--workers 4`; the digit
    validation stays outside the gate, and a throwing body releases its slot —
    without that, a few 404s deadlock every later download and
    `ensureImageDownloaded` swallows the reason.
    **Long-press multi-select delete**, in all three view modes. New
    `CollectionSelection` + `CollectionSelectionController` (hand-written
    immutable class, matching `AddCardSelection`; keyed on `collection_entries.id`,
    the only stable key since one passcode backs several rows). Its `build()`
    **watches `collectionFilterControllerProvider`**, and that watch *is* the
    clearing rule — the one way this feature could destroy data the user did not
    choose is a row filtered out of the list staying selected invisibly and being
    swept up by a button whose count never showed it. Unlike the scan pause this
    controller genuinely dies with its screen, because the screen `watch`es it.
    New `CollectionDao.deleteMany` follows the documented dynamic-`IN` convention
    (placeholders from the argument's **length** only); its empty early return is
    a live path, not defensive padding — the user can deselect every row without
    leaving the mode, and a `where` built without the clause deletes the table.
    `confirmRemoveCard` was **generalized rather than copied** (it is the one
    place `confirmBeforeDelete` is read, and a copy is a second place to forget
    it): passing `bulkCount` marks the multi-select path, which **always confirms
    whatever the setting says** (decided with the user — that toggle was written
    for a one-tap row delete where a mis-tap costs one card), while the wording
    still follows the count so removing one selected card doesn't say "1
    entries". On the list row the action column is **replaced, not hidden**:
    three live-looking per-row buttons inside a multi-row mode are the worst place
    for a mis-tap, and `CollectionTileTokens` documents that that column is what
    sets the row height, so removing it would reflow the whole list under the
    finger that just long-pressed. Grid cells get a check in the corner opposite
    the quantity badge plus an accent outline — in `minifyFull` the cell is
    nothing but artwork. `PopScope` makes Android back cancel the mode; the filter
    bar hides while selecting, since changing a filter clears the selection by
    design and offering it would look like silent discarding.
    **Test gotchas, both new**: `tester.longPress` **does not work inside
    `tester.runAsync`** and fails silently — no missed-hit warning, just a
    gesture that never becomes a long press, because the recognizer's deadline is
    a *real* timer while `longPress` advances the fake clock. The helper holds
    the pointer down over a real `Future.delayed` instead. And `Material` asserts
    when given both `borderRadius` and `shape`, so the selected-cell outline had
    to fold the radius into the shape.
    **Still open**, unchanged: `maxHammingDistance` at 72,
    `CardDetectionTuning.innerQuadMinAreaRatio` at 0.78, the passcode ROI filter
    off, `artAgreementFrames` at 2, and every `FrameQualityTuning` threshold still
    uncalibrated on device. The readout being fully legible for the first time is
    what makes calibrating them possible.

22. Ninth on-device feedback pass — grade on minified cells, sole-printing
    auto-select, square launcher icons ← done (verified: `flutter analyze`
    clean, full `flutter test` green at **535 tests**, `pytest tools/` green).
    **No DB migration, no schema change, no new dependency.** Nothing here
    touches the descriptor, `assets/card_hashes.json`, the detection algorithm
    or any scan/quality threshold.
    **The grade is on minified cells now.** `CollectionGridTile` carried
    artwork, a quantity badge, a language flag and a selection check — but no
    condition, which is exactly what step 12 moved to the *front* of the
    standard row on the grounds that it is what the eye scans for across
    duplicates. Both grid modes now render it beside the flag along the bottom
    edge, grade first, in the identical shape and colours as the row's chip
    (`ConditionChipColors` fill, `ConditionChipTokens` padding/radius) — a grade
    that reads differently in the two views is a grade the eye has to re-learn
    on every switch. It is the one badge with **no scrim**: an opaque colour
    fill is already legible on any artwork, and that is the same reason its
    fixed dark ink is right in both themes.
    Two consequences worth keeping. New `CollectionGridTokens.badgeFontSize`
    (10) for the grade and the count — `ConditionChipTokens.fontSize` is 12,
    sized for a full-width row, and `minifyFull`'s cell is 84pt wide. And the
    **quantity badge moved to the top-right**: three overlays along one edge
    collide at that width once the count reaches two digits. It stays in the
    corner opposite the selection check, which is the invariant that comment
    was protecting; the regression test sizes a cell to the real
    `artworkOnlyExtent` and asserts non-overlap at `x12`, and was **verified to
    fail** against the bottom-right original.
    **A card with exactly one known printing now arrives with that set already
    picked**, in both logging flows. Zero printings was already special-cased
    everywhere (the wizard skips its step, `_SetPicker` hides itself); one is
    the same situation with the answer known, and leaving it to a tap meant
    scans silently landed with no set at all when there was only one they could
    have come from. Several printings stays the user's call — the camera cannot
    tell which reprint is in hand.
    Scan side: one private `ScanController._solePrintingId(passcode)`, reusing
    `cardPrintingsProvider` rather than the DAO (which also warms the cache
    `_SetPicker` reads a frame later), called by **all three** paths that open
    the review gate — `_resolveArtMatch`, `_lookup`, `selectCandidate` — so the
    rule has one home. It swallows its own failures: a preselection is a
    convenience and must not cost a match that is already resolved. Each caller
    passes `printingId:`/`clearPrintingId: id == null` in place of the old
    unconditional `clearPrintingId: true`; `confirm`/`dismiss` still clear, so a
    pick cannot leak onto the next card.
    Two structural notes, both about the new await. `selectCandidate` became
    `Future<void>` (its only caller is an `onTap`), and re-checks `status`
    afterwards. And `_lookup`'s `_setPaused(paused: true)` **moved below every
    await and behind the last guard** — taking the pause before an await and
    then returning early on a status change is precisely the step-21 leak, and
    `ScanPaused` outliving the controller means a leaked pause kills recognition
    until relaunch.
    Wizard side: `AddCardSelectionController.selectCard` gains the third branch
    (`sole != null` → condition step with it preselected). No screen change was
    needed — `_ConditionStep` already prints the set under the card name and
    `AddCardScreen`'s back button already routes to `backToPrinting()` whenever
    `printings` is non-empty, so the auto-pick is visible and reversible,
    Skip included.
    **Test gotchas, both from the fixture's shape**: Blue-Eyes is the seed's
    only single-printing card, so two existing tests were written against it
    *assuming* a null printing — one asserted `printingId` was null at the
    review gate (moved to Mirror Force, which has two printings and is where a
    manual pick is the real subject), and one filtered saved rows by
    `printingId == null` (now keyed on the language it was actually testing).
    And Mirror Force's two seeded entries are both Unlimited, so filtering a
    saved row by edition alone matches both — the assertion keys on the chosen
    `printingId` and a condition the seed does not use for it.
    **Launcher icons**: the new source art was 2360x1640 — landscape, so
    `flutter_launcher_icons` would have *stretched* it to square, with the
    opaque icon's transparent surround flattening to a white border under
    `remove_alpha_ios: true`. `tools/normalize_icon.py` trims each input to its
    own content box and emits the two 1024x1024 PNGs the config expects,
    treating them differently because they are different things: the legacy/iOS
    icon is padded to square with the palette background and flattened opaque;
    the adaptive foreground stays transparent and is scaled into the central
    66% safe zone, since the launcher mask crops the rest. Originals are kept in
    `assets/icon/past_icons/`.
    **Deliberately not built**: a first-launch "import an existing CSV?" prompt
    was planned and then dropped by the user mid-implementation. Import stays
    where it is, on the Statistics screen beside the export.
    **Still open**, unchanged: `maxHammingDistance` at 72,
    `CardDetectionTuning.innerQuadMinAreaRatio` at 0.78, the passcode ROI filter
    off, `artAgreementFrames` at 2, and every `FrameQualityTuning` threshold
    still uncalibrated on device.

23. Tenth on-device feedback pass — collapsible filter rows, camera readiness,
    default rarity, fast-browse slider ← done (verified: `flutter analyze`
    clean, full `flutter test` green at **598 tests**, `pytest tools/` green).
    **No DB migration, no schema change, no new dependency.** Nothing here
    touches the descriptor, `assets/card_hashes.json`, the detection algorithm
    or any scan/matching/quality threshold.
    **Long filter rows collapse behind a chip.** Card type, monster/spell/trap
    type and archetype render one chip per distinct value held, which on a real
    collection is a wall read one chip at a time. All of them — plus level,
    frame, attribute, condition, edition and language — already went through the
    single `_ChipRow<T>`, so the fix landed in one place and every row inherited
    it; condition (7) and edition (3) sit under
    `CollectionFilterTokens.chipCollapseThreshold` (10) by construction and are
    untouched. The rule is the pure, host-tested `visibleFilterChoices` in
    `lib/features/collection/filter_chip_collapse.dart`. It takes an
    **`isSelected` predicate rather than a `T?`**, which is what lets `_RarityRow`
    share it: that row's values are `List<String?>` where null is the meaningful
    "no rarity" option while its selection is a `RarityFilter?`. **Keeping the
    selected chip visible past the cut is the load-bearing part** — a collapsed
    row hiding the active filter reads as an unset filter while the filter bar's
    badge still counts it — and it is appended rather than substituted for a head
    value, so the collapsed order still agrees with the expanded one. **Verified
    to fail** with that branch removed. The control is an `ActionChip` inside the
    same `Wrap` (a button below the row would look like it acted on the sheet),
    and the count is measured against `values`, not the prepended "All".
    **The scan banner says whether the camera is up.** With diagnostics off the
    screen drew a dark scrim while the banner already read "Point at a card" —
    advice about a camera that was not streaming yet — and the only readiness
    signal in the app was the developer-only `cam: opening…` line. `_StatusBanner`
    now carries `AppStrings.scanCameraOpening`/`scanCameraAvailable`. **No ticker
    is needed**, unlike `_DiagnosticsBox`: `CameraService.preview` is a
    `ValueListenable` and the controller is itself a `Listenable`, so readiness
    pushes — the same pair `_CameraLayer` subscribes to, for the same reason
    (sampling a getter latches the opening state forever). While opening, the
    line **replaces** the hint and takes the existing busy spinner; once up it
    sits above it, muted and a size down, so the answer stays on screen. Shown
    **only when diagnostics is off** — the overlay's `describeCameraHealth` line
    is richer and step 21 spent the entire band above the reticle getting that
    readout to fit. A released camera also reads as "opening", which is correct:
    the reticle is only drawn while the camera is meant to be live.
    **Gotcha**: the geometry test asserting the banner sits inside the guide box
    was matching on `AppStrings.scanDetecting`, so it broke the moment the label
    became camera-dependent. It now uses a new `scanStatusBannerKey`, following
    `scanReticleKey` — the assertion is about *where* the banner is, and coupling
    it to *what it says* was always incidental.
    **Default rarity** was added here and **removed again in step 24** — the
    option list came from `PrintingDao.distinctRarities()` over the whole synced
    database, which is ~90 open-ended YGOPRODeck `set_rarity` strings
    (`10000 Secret Rare`, `Duel Terminal Normal Parallel Rare`, the bare values
    `2` and `3`), so the control was unusable on device. `AppSettings
    .defaultRarity`, its `meta` key, `cardRaritiesProvider`,
    `CardRepository.distinctRarities` and the DAO method behind it are all gone;
    a leftover `settings.default_rarity` row is inert. What survives is
    `preferredPrinting` in `lib/models/printing.dart`, which this step created to
    **de-duplicate** the sole-printing rule both logging flows carried separately
    (`_solePrintingId`, now `_preferredPrintingId`, and `selectCard`'s local) —
    it just no longer takes a rarity: no printings → null, exactly one → that
    one, several → the user's call.
    **Test gotchas**: the fourth control pushed Appearance below the fold in the
    600pt viewport and the theme test's tap started missing. The `ListView` is
    **lazy**, so `ensureVisible` alone fails with "No element" — the widget is not
    built at all. `scrollToDatabaseSection` was generalized to a `scrollTo` that
    does `dragUntilVisible` (to build it) *then* `ensureVisible` (because
    `dragUntilVisible` stops as soon as the target is built, which can still be
    under the bottom edge — the step-12 trap). And a synthetic `CameraController`
    for the readiness test needs `previewSize` set, not just `isInitialized`:
    `CameraValue.aspectRatio` null-checks it and both `_FullBleedPreview` and
    `_DetectionOutline` read it the moment a controller appears.
    **Fast-browse slider**, in `lib/features/collection/collection_scroll_slider
    .dart` with its arithmetic split into `..._math.dart` (host-tested, per
    `card_quad.dart`'s reasoning: a wrong constant here does not crash, it puts
    the thumb somewhere plausible and slightly wrong). **The gutter is its own
    column on the right, never an overlay** (decided with the user): `minifyFull`
    cells are 84pt wide and already carry a quantity badge in one top corner and
    a selection check in the other. This is the app's **first `ScrollController`
    and first scrollbar of any kind**.
    Three things are load-bearing. **The widget takes a `builder`, not a child**,
    so the scroll view lives inside its subtree and switching view modes rebuilds
    only what is under the builder while the `State` — and the controller —
    survives. **Metrics come from `ScrollMetricsNotification` +
    `ScrollNotification`, never from `_controller.position`**: `maxScrollExtent`
    asserts `hasContentDimensions`, so reading it before the first layout throws
    in debug, which is exactly when the thumb wants to paint. They land in a
    `ValueNotifier` read only inside the gutter, so a scroll never rebuilds the
    list. **Gutter reservation is a function of `itemCount` alone**
    (`collectionSliderReservesGutter`, threshold
    `CollectionScrollSliderTokens.minItems` = 30): the gutter narrows the grid's
    cross axis, which changes the column count, which changes the scroll extent,
    so a layout-derived predicate would feed back into its own input.
    `collectionSliderIsScrollable` is the separate, layout-dependent gate on what
    is *painted* inside an already-reserved gutter, which starts no loop.
    A list and a grid are different widget types, so a mode switch remounts the
    scrollable at offset 0. Pixels are meaningless across that change (110pt rows
    against grid rows of another height and column count), so `didUpdateWidget`
    carries the **fraction** and reapplies it from the first metrics notification
    — **verified to fail** (offset 0) with the restore disabled. The bubble names
    the position under the active sort via `collectionScrollLabel`, whose every
    branch reads the same field the DAO orders by, so it cannot disagree with the
    ordering it describes; `sliderIndexForFraction` is deliberately linear rather
    than trying to name the top *visible* row, which would need the grid delegate's
    maths re-implemented and is wrong at the bottom end anyway.
    **Gotchas**: `Positioned` must be a direct child of `Stack`, so the bubble's
    `LayoutBuilder` needed its own `Stack` rather than positioning into the
    slider's outer one; the bubble is wrapped in `IgnorePointer` since it overlays
    the cards; the `ScrollController` is assigned in `initState`, not a
    `late final` (step 13's dispose-time-initializer trap, twice over); and the
    slider is tested **directly over a synthetic list**, not through the
    collection screen, because that screen resolves providers through the sqflite
    isolate and so must run inside `runAsync`, where gesture timing is unreliable.
    Existing collection tests are untouched by construction — the fixture seed is
    far under `minItems`, so no gutter is reserved and no padding changes.
    **Still open**, unchanged: `maxHammingDistance` at 72,
    `CardDetectionTuning.innerQuadMinAreaRatio` at 0.78, the passcode ROI filter
    off, `artAgreementFrames` at 2, and every `FrameQualityTuning` threshold
    still uncalibrated on device.

24. Card pricing, global card search, collection value — and the default-rarity
    removal ← done (verified: `flutter analyze` clean, full `flutter test` green
    at **649 tests**, `pytest tools/` green). **One DB migration (v2 → v3), no
    new dependency.** Nothing here touches the descriptor,
    `assets/card_hashes.json`, the detection algorithm or any scan/quality
    threshold.
    **Default rarity is gone** (see step 23's entry, amended). The picker's
    options came from the whole synced database's `set_rarity` values — ~90
    open-ended strings including `10000 Secret Rare` and the bare `2` and `3` —
    so the control was unusable. Removed end to end: the `AppSettings` field and
    its `copyWith` clear flag, the `meta` key and `SettingsRepository
    ._parseOptionalText`, `SettingsController.setDefaultRarity`, the Settings
    control, `cardRaritiesProvider`, `CardRepository.distinctRarities` and
    `PrintingDao.distinctRarities` (a DAO method with no feature behind it is
    dead code by this file's own rule). `preferredPrinting` keeps the
    sole-printing rule and loses its parameter. `SearchableTextPicker` **stays**
    — the collection filter sheet's Set box uses it.
    **The pricing constraint, and it is not negotiable.** YGOPRODeck reports
    prices at two granularities that do not line up: `card_prices[0]` is
    *card-level* (`cardmarket_price` in **EUR**, `tcgplayer`/`ebay`/`amazon`/
    `coolstuffinc` in **USD**), documented as "the lowest price found across
    multiple versions of that card"; `card_sets[].set_price` is per set+rarity
    and is **a single USD figure**. So there is no per-set Cardmarket price and
    there never will be from this API. The UI says so in both halves rather than
    implying one exists, and the collection total is reported as **two separate
    figures**, never summed — this app carries no exchange rate, and inventing
    one turns a stated estimate into a wrong number.
    **Data layer.** Migration v3 adds `card_prices` (card-level only; see the
    schema section for why its cascade means a re-sync empties it). New
    `CardPriceDao` follows step 17's dynamic-`IN` convention; new
    `CollectionDao.quantityByPasscode()` groups by passcode rather than per entry
    because pricing is a property of the *card* — a card held in two languages is
    two rows and one lookup — and that key set is exactly what bounds the request
    count. `YgoProdeckClient` gained `fetchPrices` over `cardinfo.php?id=` with
    the parsing extracted to top-level `parsePricingEntry`/`parsePrice`, pure and
    host-tested (a wrong parse here does not crash, it reports a plausible wrong
    valuation — the `card_quad.dart` argument). Two behaviours worth keeping:
    prices arrive as **strings** (`"0.29"`), and `parsePrice` folds `"0.00"` into
    **null**, because that value means "no figure" rather than "free" — which is
    what lets every display site and the total share one rule. `?id=` with no
    match answers **HTTP 400**, caught per chunk and returned as empty rather
    than failing a whole valuation. `BaseOptions` finally has timeouts
    (15s connect / 30s receive — Dio's receive timeout is the gap *between*
    chunks, so the 15 MB bulk sync is unaffected); there were none anywhere
    before.
    `PriceRepository` chunks at `kPriceChunkSize` (50) — 18 sequential requests
    for a 900-card collection, trivially inside the 20/second limit — writes each
    chunk as it lands so an interrupted run keeps its progress, and reuses cached
    rows under `kPriceTtl` (24 h). `asOf` is the **oldest** price in the total, so
    the stamp describes all of it. `lib/core/money.dart` formats both currencies
    by hand (`intl` is not in the stack and two fixed-decimal symbols need no
    locale machinery) and renders an em dash, never `0.00`, for an unknown.
    **Riverpod 3 retries failed providers by default, and that is a UI bug here.**
    A provider that throws is re-run on a doubling backoff and stays
    `AsyncLoading` *carrying* the error while it waits — so `.when(error:)` never
    fires and an offline device sits on a spinner forever instead of seeing
    "could not load prices" and a Retry. Both pricing providers therefore set
    `retry: _noRetry`. Found by a test that could not reach its own error branch;
    `card_prices_view_test` documents the symptom so a "tidy-up" cannot silently
    restore it.
    **UI.** Home is five destinations: the 2x2 grid is unchanged and Card Search
    is a **full-width tile beneath it** (`HomeMenuTokens.gridRowFlex` /
    `wideTileFlex`, `HomeMenuTile(wide: true)` laying icon and label out in a row).
    A sixth empty slot would have shortened every tile by a third to show
    nothing, and the fixed non-scrolling layout is not negotiable — a scrolling
    grid once pushed tiles off short viewports. New `lib/features/card_search/`
    (search screen + `CardDetailScreen`) and `lib/features/pricing/`
    (`CardPricesView`, `CardPriceEstimate`, providers). Both card screens are
    `DefaultTabController(length: 2)` — **Details / Prices** — and the split is
    not cosmetic: Details is answered entirely from the local database while
    Prices needs the network, so folding them together would make reading a
    card's effect text depend on being online. The card's own facts moved to
    `lib/shared/widgets/card_details_view.dart` (`CardDetailsView` +
    `CardDetailRow`, the old private `_DetailRow`), shared verbatim by both
    screens: the Spell/Trap label switch, the hidden redundant attribute and the
    flavour-vs-effect heading are *rules*, and a second copy would drift.
    `CollectionDetailScreen` keeps everything entry-specific (grade pill,
    quantity ±, set/rarity/edition/language, `_LanguageBreakdown`) on its Details
    tab and passes it through `CardDetailsView`'s new `leading` slot. The
    "button to see the pricing" is `CardPriceEstimate` — a tappable row showing
    one *stack's* worth (priced by quantity) that calls
    `DefaultTabController.of(context).animateTo(1)`, i.e. a link to the tab
    beside it rather than a second destination. It renders **nothing** while
    unresolved or unpriced, so a card's effect text is never pushed down or made
    to look broken by a missing price.
    Statistics gained `_CollectionValueSection` + `CollectionValueController`,
    shaped like `ResyncController` (nullable state, inline progress, non-blocking
    failure). **On demand, never on open** — it is a burst of network requests,
    which is why it is a controller starting at null and not a `FutureProvider`
    the screen watches into existence. Progress is real counts ("Priced 120 / 340
    cards") because this can be a dozen sequential requests. Rendered only in the
    populated branch, unlike the import button beside it.
    **The collection row: 32 % more artwork in an 11 % shorter row — and the
    tokens had been lying.** `_TileAction` sized its buttons through
    `constraints`, but Material 3 builds `IconButton` through a `ButtonStyle`
    whose `minimumSize`/`tapTargetSize` apply *outside* those — so every button
    rendered at `visualDensity: compact`'s 40pt floor whatever `actionButtonSize`
    said, and the row was **132pt while `CollectionTileTokens` documented 102**.
    Nothing caught it because nothing measured the row. Fixing it needs three
    things together (`tapTargetSize: shrinkWrap`, a pinned `minimumSize`/
    `maximumSize`, and `VisualDensity.standard` — density is applied *after* the
    size and `compact` subtracts a further 8pt, which left the first attempt at
    27 rather than 35). With that real, `actionButtonSize` 35 puts the row at
    `2*6 + 3*35 = 117`.
    The artwork became a **square crop** (`CardThumbnailSizes.collectionTile` 80,
    `BoxFit.cover`, `CollectionTileTokens.artAlignment` `(0, -0.55)`), the one
    place in the app that did not draw the whole card — **reverted in step 25**,
    where it turned out to read as a stretched card on device. That is what makes
    "bigger picture, shorter row" possible at all: a card is 1.46x as tall as it
    is wide, so its *height* is what competed with the action column, and every
    previous attempt to enlarge it grew the row. At 80x80 it is 39 % wider and
    32 % larger in area than the 57.6x84 portrait, and still inside the 105pt
    column. The alignment is load-bearing — a centred square crop of a card opens
    below its name; at -0.55 the window runs 7.1 %-75.7 % and keeps the name and
    the whole art box. `CardThumbnail`/`CardArtThumbnail` gained an `alignment`
    parameter for it. `CollectionTileTokens.secondaryFontSize` (12) is arithmetic
    rather than taste: at the inherited body size a wrapped name plus set and
    rarity lands ~88pt and becomes the tallest child, holding the row at ~100.
    `collection_list_tile_geometry_test.dart` measures the row, the buttons and
    the crop, because the failure mode here is a silent green.
    **Test gotchas**: `flutter_riverpod` does not re-export Riverpod's `Override`
    type, so a helper cannot be parameterized by it — pass the *value* and build
    the override inside. And `tester.pumpWidget` reuses the `ProviderScope`
    element between two pumps in one test, so the container survives and a
    controller keeps its state; a distinct `ValueKey` is what forces a genuinely
    fresh scope (`collection_value_test`'s cache-reuse case needs one).
    **Still open**, unchanged: `maxHammingDistance` at 72,
    `CardDetectionTuning.innerQuadMinAreaRatio` at 0.78, the passcode ROI filter
    off, `artAgreementFrames` at 2, and every `FrameQualityTuning` threshold
    still uncalibrated on device. New and open: whether `kPriceTtl` at 24 h is
    right, and whether the per-set USD table is useful enough on its own given
    Cardmarket cannot appear beside it.

25. Eleventh on-device feedback pass — row artwork reverted, value breakdown
    export, one icon size on the home menu ← done (verified: `flutter analyze`
    clean, full `flutter test` green at **668 tests**, `pytest tools/` green).
    **No DB migration, no schema change, no new dependency.** Nothing here
    touches the descriptor, `assets/card_hashes.json`, the detection algorithm
    or any scan/matching/quality threshold.
    **The collection row's square crop is reverted, apparatus and all.** Step
    24's 80x80 `BoxFit.cover` window was not geometrically distorted, but a card
    cropped to a square and enlarged 39 % reads as *stretched*, which is what it
    was reported as. `CardThumbnailSizes.collectionTile` is `list * 1.2` again
    (57.6 x 84, `aspectRatio: ScanReticleTokens.cardAspectRatio`,
    `BoxFit.contain`). **The doc comment was not restored verbatim**: the old one
    computed its ceiling as 61.7 against `actionButtonSize = 30`, a number step
    24 proved was fiction — the real column is `3 * 35 = 105`, so a 59/86 card
    fits up to ~72pt wide and 57.6 is comfortably inside. Step 24's other two
    row changes (the honest button size, `secondaryFontSize`) are **kept**, so
    the row stays 117pt rather than returning to 132.
    The crop existed only for this row, so `CollectionTileTokens.artAlignment`
    and the `alignment` parameter on **both** `CardThumbnail` and
    `CardArtThumbnail` went with it — a widget API with no call site is dead
    code by this file's own rule. The geometry test's crop case became a
    whole-card case, and its "fits inside the action column" check now measures
    **height** (`collectionTile / cardAspectRatio`), since with a portrait
    thumbnail height is again what competes for the row.
    **One icon size on the home menu.** The Card Search tile drew a 28pt glyph
    against the grid's 40 — an explicit ternary in `home_menu_tile.dart`, not a
    layout artifact. `HomeMenuTokens.wideIconSize` is replaced by a single
    `iconSize = 40` used by both branches, which also retires the bare `40`
    literal that let the two drift apart in the first place. The wide tile still
    fits it: laid out in a row its content is `40 + 2 * AppSpacing.md` = 72pt
    against a `wideTileFlex` share of ~140 at 360x640, and `wideTileFlex` keeps
    its smaller share for the reason that actually holds — icon *beside* label
    rather than above it. Nothing pinned icon size before, so
    `home_screen_test` now compares the wide tile's against a grid tile's
    (**verified to fail** against the old ternary).
    **The collection value can be exported, one row per card.** That is the
    granularity the prices have: YGOPRODeck's card-level figure is the lowest
    across a card's printings, so condition, edition and set are invisible to
    it, and a per-entry file would repeat one unit price across rows and read as
    if a Near Mint 1st Edition were quoted separately from a Played one. Join it
    to a collection export on `passcode` for that detail.
    `CollectionValue` now **carries the rows it used to discard**: a
    `List<CollectionValueLine>` (passcode, name, quantity, both unit prices,
    `pricedAt`) built in the same pass that accumulates the totals. That is the
    whole design — the exported numbers *are* the displayed numbers, with no
    second fetch, no second pass over the price cache and no way for the file to
    disagree with the screen. **Unpriced cards get a line too**, carrying nulls:
    they are the detail behind the existing `unpricedCards` count, which says
    how many the totals leave out but never which. Names come from the existing
    `CardDao.getByPasscodes`, so `PriceRepository` gained a third DAO and one
    round trip; lines are sorted by name, since `quantityByPasscode` groups in
    whatever order SQLite returns.
    The escaping moved to **`lib/data/export/csv_writer.dart`** (`csvRow`,
    `csvEscape`, `csvGuardFormula`, `csvIsoUtc`), shared by both writers: the
    quoting, the doubled quotes and the formula guard must not exist twice, and
    `collection_csv_parser.dart` is written against exactly those rules.
    `collection_value_csv.dart` is the second format. Numbers are raw
    `toStringAsFixed(2)` — **not** `core/money.dart`'s `formatEur`/`formatUsd`,
    which embed a currency symbol and render an em dash, both right on screen
    and wrong in a column something else parses. **An unknown price is an empty
    cell, never a zero**: the API's own "0.00" already means "no figure", and a
    zero would let an unquoted card read as a worthless one. Currency lives in
    the column *name* (`cardmarket_eur`, `tcgplayer_usd`), the two are never
    summed, and there is no trailing totals row — this feeds pandas/DuckDB,
    where a summary line inside the data is a nuisance.
    **It cannot be imported back, by construction**: no `condition` column, so
    `parseCollectionCsv` refuses it outright rather than reading it half-way
    into rows with a defaulted grade. A parser test pins that, which is also the
    live justification for `condition` being on the required-column list.
    `CollectionExporter.exportValueToCsv` takes the value **as an argument**, so
    it needs no `PriceRepository` and no new provider dependency, and writes
    `ygo_collection_value_<date>.csv` — its own name, since it is its own
    format and must not overwrite the collection export. The button lives in
    `_ValueResult`, stacked under Refresh, **not** in `_Actions`: there is
    nothing to export until a calculation has succeeded, and `_Actions` also
    renders in the empty-collection branch where it would be live with nothing
    behind it.
    **Test gotcha**: the widget tests assert the export button's *presence*
    only, before and after a calculation and after a failure. Tapping it reaches
    the real OS share sheet — there is still no `share_plus` mock anywhere in
    this repo, which is why the collection export's own test stops at the
    returned path too.
    **Still open**, unchanged: `maxHammingDistance` at 72,
    `CardDetectionTuning.innerQuadMinAreaRatio` at 0.78, the passcode ROI filter
    off, `artAgreementFrames` at 2, every `FrameQualityTuning` threshold still
    uncalibrated on device, and whether `kPriceTtl` at 24 h is right.

26. Pricing by printing, the in-app value breakdown, and the vendor cleanup ←
    done (verified: `flutter analyze` clean, full `flutter test` green at **715
    tests**, `pytest tools/` green). **One DB migration (v3 → v4), no new
    dependency.** Nothing here touches the descriptor,
    `assets/card_hashes.json`, the detection algorithm or any scan/quality
    threshold.
    Context: the report was that the individual values in the exported value CSV
    "look way off". They were — and **the arithmetic was not**. The accumulation
    loop was read and checked line by line: quantity summed per passcode, unit ×
    quantity, currencies never mixed, `"0.00"` folded to null by `parsePrice`,
    the export reusing the on-screen object so file and screen cannot disagree.
    Nothing was double-counted. Only the **grain** was wrong.
    **The input was the problem, measured against the live API.**
    `cardmarket_price` is **€0.02** for Blue-Eyes White Dragon, Dark Magician
    *and* Mirror Force; `tcgplayer_price` is 0.15 / 0.30 / 0.65. The API guide
    says each figure is "the lowest price found across multiple versions of that
    card", so the euro total was roughly `€0.02 × copies owned`. Meanwhile
    `card_sets[].set_price` is per set *and* rarity and realistic — CT13-EN008
    Blue-Eyes is **$74.49**, LOB-001 is $236.85.
    **And it was already being downloaded and thrown away.** `fetchPrices`
    returns `CardPricing.sets` in the same response and `collectionValue()`
    discarded it, while `collection_entries.printing_id` has recorded which
    printing each copy is since v1. So pricing by printing costs **zero extra
    requests** — the fetch is still bounded by distinct passcodes, and the
    "Priced 120 / 340 cards" progress line is unchanged.
    **Schema v4**: `printing_prices` (`printing_id` PK → `printings(id)` ON
    DELETE CASCADE, `price` REAL, `updated_at`), plus `card_prices` **dropped
    and recreated** without `ebay`/`amazon`/`coolstuffinc` — `ALTER TABLE …
    DROP COLUMN` needs SQLite 3.35 and sqflite uses Android's system SQLite
    (API 30 ships 3.28), and dropping is safe precisely because the table is a
    pure re-fetchable cache a re-sync already empties. See the schema notes for
    why the cascade and the NULL-price row are both load-bearing.
    **The valuation regrouped from passcode to `(passcode, printing_id)`.**
    `CollectionDao.quantityByPasscode` is **replaced** by
    `quantityByPasscodeAndPrinting` (deleted, not kept alongside — one caller,
    and a DAO method with no feature behind it is dead code by this file's own
    rule), returning an `OwnedPrintingQuantity` record. **`GROUP BY printing_id`
    folds every NULL into one group** — the exact opposite of how the
    `collection_entries` UNIQUE key treats NULL, which `addOrIncrement`
    special-cases by hand. That is wanted (every copy logged without a set is
    one group priced at the floor) and is pinned by a test.
    Dollars prefer the printing's own `set_price` and fall back to the card
    floor; euros are *always* the floor. `PriceBasis` (`printing`/`cardFloor`/
    `none`) rides every `CollectionValueLine` and is surfaced on screen and in
    the CSV, because a total built mostly from fallbacks is barely better than
    the one this replaced and the numbers alone cannot say which it is.
    **`pricedCards`/`unpricedCards` stay distinct-passcode counts** while
    `lines.length` is per group — the strings say "cards", the fetch is bounded
    by passcodes, and `CollectionValueController` derives its progress from them
    and would otherwise contradict the line it just displayed.
    **The `SetPrice` → `printings.id` match is the exact `(passcode, set_code,
    rarity)` triple**, the `printings` UNIQUE key. Both sides come from the same
    three fields of the same endpoint (`_parseEntry` and `parsePricingEntry`
    read `set_code`/`set_rarity` identically), so string equality is an
    *identity*, not a heuristic — none of `resolveImportRow`'s case-and-space
    ladder applies, since that exists because a human typed the CSV. `set_name`
    is excluded: it is not in the UNIQUE key, so a renamed set would stop
    matching. Rarity is half the key on purpose — matching on set code alone
    would give a Common the Secret Rare's price, an order of magnitude wrong
    with nothing on screen to suggest it. Duplicate entries collapsing onto one
    printing take the **lowest** non-null price; any deterministic rule would
    do, but an unstated "last one seen" is how two runs report two different
    totals. `asOf` now spans both tables, since a line can draw its dollars from
    a printing row and its euros from a card row fetched at different times.
    **eBay, Amazon and CoolStuffInc are gone end to end** — the `CardPrices`
    fields, `parsePricingEntry`, the three rows on the Prices tab, the
    `AppStrings`, and the columns. They were displayed and fed nothing else.
    **The value CSV is now one row per `(card, printing)`** with `set_code`,
    `set_name`, `rarity` and a `tcgplayer_basis` column reading
    `printing`/`card_floor`/empty. `cardmarket_eur` was **renamed
    `cardmarket_eur_floor`** (totals likewise): a column called `cardmarket_eur`
    beside a per-printing `tcgplayer_usd` implies the two are the same
    measurement, which is the exact misreading this step exists to end. *A
    downstream script reading the old name will need updating.* Everything else
    is preserved verbatim — empty cell for unknown and never `0`, currency in
    the column name, bare `toStringAsFixed(2)` rather than `money.dart`, no
    totals row, and still **not importable** (no `condition` column, so
    `parseCollectionCsv` refuses it outright). The file's doc comment was
    *rewritten* rather than extended: it argued for per-card granularity **on
    the grounds that prices are card-level**, a rationale this step kills.
    **The breakdown is visible in the app**, at `AppRoutes.collectionValue` =
    `/statistics/value`, reached from a "View breakdown" button that appears in
    `_ValueResult` only after a calculation succeeds — same contract as the
    export button beside it, and the `CollectionValue` travels as `state.extra`
    like `collectionDetail`/`cardDetail`. `CollectionValueScreen` **reads
    nothing from Riverpod**: everything comes from `widget.value`, which makes
    it a pure function of its argument and so testable by pumping it under a
    bare `MaterialApp`, sidestepping the documented hang when a route transition
    kicks off the sqflite isolate. Rows show name, set, rarity, `×N` and the
    **line totals** (not unit prices), with a muted `card floor` tag only where
    the dollars fell back — a word, not a colour, so it survives a colour-blind
    reader. Unpriced lines stay in the list showing `kNoPrice`; they are the
    detail behind the count above, and hiding them would repeat the mistake the
    lines were kept to fix. Sorting is by line total descending (default,
    unpriced last) or by name; the pure `sortValueLines` is host-tested and
    non-mutating, so the export keeps the repository's name order and stays
    diff-stable. **`CardArtThumbnail` is deliberately absent** and documented as
    such: it needs a `YgoCard`, reaching one means the database, and that would
    cost the screen its pure-`extra` property, fire a burst of art lookups over
    a now-per-printing list, and double every row's height on a dense money
    list. Rows are untappable for the same reason. `_StatTile` was extracted to
    a public `StatTile` in its own file rather than copied.
    **Copy**: `statisticsValueNote` was rewritten to carry the asymmetry (the
    old text is now false of the USD side and still true of the EUR side), and
    the tiles are labelled **"Cardmarket (floor)"** vs "TCGplayer" — calling
    both by a plain vendor name would imply they are the same measurement.
    **Bundled bug fix, pre-existing and latent**: the dynamic-`IN` DAO methods
    were called with the *full* owned passcode list, and
    `SQLITE_MAX_VARIABLE_NUMBER` is **999** before SQLite 3.32 — which Android
    API 30 still ships. A collection past ~1000 distinct cards already threw
    there, and this step makes the id lists longer. `lib/data/db/dao/
    sql_chunks.dart` (`kSqlVariableLimit = 900`, headroom for extra
    `whereArgs`) is now applied *inside* `CardDao.getByPasscodes`,
    `CardPriceDao.getForPasscodes`, `PrintingDao.getForPasscodes`,
    `CollectionDao.getEntriesForPasscodes`, `CollectionDao.deleteMany` (every
    slice inside the one transaction — chunking must not turn an atomic delete
    into a partial one) and the new `getForPrintings`. In the DAO, where a
    caller cannot forget it.
    **Verified to fail before being kept**: the "a second run makes no request
    even for figureless printings" test, against a `_matchSetPrices` that skips
    unmatched printings — it requested twice, i.e. forever.
    **Still open**, unchanged: `maxHammingDistance` at 72,
    `CardDetectionTuning.innerQuadMinAreaRatio` at 0.78, the passcode ROI filter
    off, `artAgreementFrames` at 2, every `FrameQualityTuning` threshold still
    uncalibrated on device, and whether `kPriceTtl` at 24 h is right. New and
    open: whether the card-level Cardmarket floor earns its place on the screen
    at all now that it sits beside a genuinely per-printing dollar figure.

27. Persisted collection sort order ← done (verified: `flutter analyze` clean,
    full `flutter test` green at **723 tests**). **No DB migration, no schema
    change, no new dependency.** Nothing here touches the descriptor,
    `assets/card_hashes.json`, the detection algorithm or any scan threshold.
    The report: pick a sort in the collection app bar, go back to the home menu,
    return — it is back on Name ascending. `CollectionFilterController` is
    autoDispose (correctly — the screen watches it) and `build()` returned
    `const CollectionFilter()`, so leaving the screen discarded the sort along
    with everything else.
    **Only the sort is persisted, and the asymmetry is the design.** A filter
    *hides* cards, and a collection still narrowed on the next visit reads as
    lost data; a sort only reorders what is already all there. So `build()`
    seeds `sortBy`/`sortDescending` from settings and leaves every other field
    empty — the same split `CollectionFilter.cleared()` already makes for the
    sheet's Reset button.
    Storage is the `meta` table via two new `settings.*` keys, exactly like
    `collectionViewMode` (step 18) and with the same rationale for having **no
    Settings row**: the control lives where the effect is visible.
    `CollectionSortBy` **moved to `lib/models/collection_sort_by.dart`** and
    gained `toDb`/`fromDb` — every persisted enum lives there, and `AppSettings`
    must not import the DAO layer. `collection_dao.dart` re-exports it, so the
    call sites that reach it through `CollectionFilter` keep their single
    import.
    **`ref.read`, not `watch`, in `build()`** — matching `ScanController` and
    `AddCardSelectionController`. Watching would rebuild the notifier on its own
    write-through and so wipe every filter the user had applied; a test pins
    that. The setters publish first and persist unawaited: the list must reorder
    on the tap, and a failed write is not worth reverting a reorder the user can
    repeat.
    **Bug found by the new test, and it predates this step**:
    `SettingsController._update` read `state.value`, awaited the repository,
    then published — so two changes made before the first write landed both
    started from the *same* snapshot and the second silently reverted the first.
    Choosing a sort field and then flipping its direction is exactly that
    sequence. `_update` now chains onto a `_writes` future, applying each change
    only once the previous one has published; the queue swallows failures so one
    bad write cannot wedge every later preference change, while the caller still
    sees the error.
    **Verified to fail** before being kept: with `build()` reverted to
    `const CollectionFilter()`, both the leave-and-return and the restart tests
    fail — which also proves the autoDispose teardown in the test is real rather
    than a subscription quietly holding the notifier alive.
    **Gotcha**: `dart format` on this toolchain reformats ~90 untouched files
    (formatter version drift against what the repo was written with). Format the
    files you changed, not the tree, or the diff buries the change.
    **Still open**, unchanged: `maxHammingDistance` at 72,
    `CardDetectionTuning.innerQuadMinAreaRatio` at 0.78, the passcode ROI filter
    off, `artAgreementFrames` at 2, every `FrameQualityTuning` threshold still
    uncalibrated on device, and whether `kPriceTtl` at 24 h is right.

28. Twelfth on-device feedback pass — camera lifetime, honest readiness, share
    cancellation, panel overlap ← done (verified: `flutter analyze` clean, full
    `flutter test` green at **736 tests**, `pytest tools/` green). **No DB
    migration, no schema change, no new dependency.** Nothing here touches the
    descriptor, `assets/card_hashes.json`, the detection algorithm or any
    shape/matching/quality threshold.
    **The camera opens once per app run.** The whole chain below the scan screen
    was autoDispose, so leaving Log Cards was a full teardown — screen unmounts →
    `ScanController` → `artReadings` → `scanCamera` → its
    `onDispose(camera.stop)` → `cameraServiceProvider` loses its last listener →
    `service.dispose()` sets `_disposed` **permanently**. A re-entry could not
    even reuse the instance; it built a new one and paid `initialize()` plus eight
    metering round-trips and a `startImageStream` again, which is the reported
    second of black on every return from Settings. `cameraService` and
    `scanCamera` are now `@Riverpod(keepAlive: true)`; nothing reads `scanCamera`
    before the first Log Cards entry, so the camera is *kept*, never opened early.
    **The lifecycle signal had to move with it.** It came from a
    `WidgetsBindingObserver` on `_ScanScreenState`, which only exists while that
    screen is mounted — fine while the camera died with the screen, and nothing at
    all once it outlives it: the camera would stay bound while the app sat in
    recents. `ScanCameraActive` now owns an `AppLifecycleListener` in its own
    `build()` with `ref.onDispose(listener.dispose)`, and is `keepAlive` for the
    same reason. The provider that *means* "the camera should be running" owning
    the signal that decides it is the smallest correct home, and it keeps `App`
    stateless. The switch carries over verbatim, `inactive → active` included
    (step 15's permission-dialog fix). `_ScanScreenState` drops the mixin and
    keeps only its post-frame `ScanPaused` reset.
    **New `CameraService.frameProcessingEnabled`, and it is not optional.** With
    the camera live off-screen, `_onFrame` would keep doing a full-frame luma copy
    (~1 MB/s at `artFrameInterval`) into a cache nobody polls, forever.
    `ScanController` owns it — set in `build()`, cleared from `ref.onDispose` —
    since that controller's lifetime *is* "a screen is scanning". Checked **after**
    the arrival bookkeeping, so the watchdog still measures the camera and not our
    own gating. Two traps found writing it: the service must be **captured** in
    `build()` rather than `ref.read` again inside the callback (Riverpod asserts on
    any `Ref` use from a life-cycle, `onDispose` included — the same rule that
    forces the `ScanPaused` reset to happen on entry), and **`retry()` has to
    re-arm it on the replacement service**, because invalidating
    `cameraServiceProvider` builds a fresh one whose flag starts false while the
    controller is not itself rebuilt — without that line a retry brought the camera
    back and left recognition permanently inert.
    **The camera freeze: two real bugs, both in the watchdog.**
    - **A failed restart killed the watchdog permanently.** `_restart()` enqueues
      `_stop` then `_start` un-awaited, and `_enqueue`'s chain swallows errors —
      so a `_start` that threw (camera busy, permission revoked mid-session, a
      CameraX bind failure) never reached the `_startWatchdog()` that used to sit
      at its tail. `_controller` stayed null → `_streamingSince` null →
      `health.sinceLastFrame` null → the periodic callback returned early forever.
      **Camera dead, screen black, no error surfaced** (the throw never reaches
      `scanCamera`, so no `ScanStatus.error` either) for the rest of the process.
      The best candidate for the report.
    - **A restart could reopen a camera the app had just released**, since
      `_start` never consulted whether the camera was still wanted: a lifecycle
      `_stop` landing between the restart's `_stop` and `_start` was simply undone.
    One `_wantRunning` flag fixes both. `start()` sets it and **arms the watchdog
    itself** — the ordering *is* the fix, since a watchdog created by a successful
    start cannot recover a failed one; `stop()` clears it and cancels. `_start()`
    early-returns when it is false. The decision moved into a new pure,
    host-tested `cameraNeedsRestart` beside `cameraFrameStalled` (which is
    unchanged and called from inside it), covering "wanted but no controller" as
    well as the stall, per `card_quad.dart`'s reasoning: a mistake here does not
    crash, it silently removes the only way back from a dead camera.
    `_startInFlight` is required rather than defensive — opening a camera takes far
    longer than one `cameraWatchdogInterval`, so without it every start would be
    aborted by a restart of itself on the next tick.
    **A third, silent failure is now visible**: `_onFrame`'s conversion `catch` and
    the two `return null` paths dropped frames with no counter, which presents as
    `cam: streaming f=<rising> Δ=<small>` with `frameSequence` frozen and nothing
    ever recognised — and the watchdog cannot help, because frames genuinely are
    arriving. `CameraHealth.droppedFrames` and an `x=<n>` field on the `cam:` line
    (omitted at zero, like `r=`).
    **And the one that cannot be fixed gets a button.** flutter/flutter#27688 —
    CameraX blacking out the *preview surface* while analysis frames keep flowing —
    is undetectable from Dart: every signal reads healthy and the screen is black.
    New `CameraService.restart()`, surfaced by making the **readiness line
    tappable** rather than adding a fifth app-bar action (with diagnostics on there
    are already four, which overflows a 360pt bar). It is the right place on its
    own merits: the line claiming the camera is available is exactly what the user
    is staring at when it is not. No "restarting…" SnackBar — the banner flipping
    back to `Camera: opening…` with its spinner is the feedback, in the place they
    are already looking. `GETTING_STARTED.md`'s "close the app fully" now names it.
    **`Camera: available` only once frames actually flow.** Readiness was
    `controller.value.isInitialized`, and `_start` publishes the controller the
    instant `initialize()` returns — before metering, before `startImageStream`,
    deliberately, since the picture is worth showing that early. So the banner
    announced an available camera over a preview that had not streamed anything.
    New `ValueListenable<bool> streaming` on the interface, set on the **first
    frame after a start** and cleared at the top of `_stop` (so a watchdog restart
    correctly reads as opening); `_StatusBanner` subscribes to that one notifier
    and drops the nested `ListenableBuilder` on the controller. This is the signal
    `describeCameraHealth` has always used, so the plain-language line and the
    `cam:` line now flip at the same moment instead of contradicting each other.
    **The review panel and the app-bar icons, both halves.** `extendBodyBehindAppBar`
    with a transparent `AppBar` means the body owns the full screen, and
    `_MatchedPanel`'s height is content-driven — set picker, three chip rows,
    quantity, two buttons — so it grew up behind the icons until bug/save/keyboard
    sat on the card name and the set field. New `_ScanBottomPanel` extracts the
    `Align(bottomCenter)` → rounded surface → `SafeArea(top: false)` shape the four
    panels each repeated, and reserves `MediaQuery.padding.top` — which under
    `extendBodyBehindAppBar` *already includes* `kToolbarHeight`, the same fact
    `_TopOverlays` documents after step 19 found it being added twice. Nothing
    overflows under the cap; the panels already scroll or use `Flexible`.
    Separately, every app-bar action is now gated on the `scanning` predicate
    `_TopOverlays` already computed, lifted to one local so the two cannot drift.
    That **overrules step 19's deliberate decision** to leave the save-frame button
    up during `matched`/`candidates`: `matcher.lastSample` survives a dismiss, so
    the frame behind a wrong answer is still one tap away, and not overlapping the
    form is worth more than saving that tap.
    **Cancelling a share no longer reports success.** All three call sites chose
    their SnackBar text the moment the file was written, then opened the sheet and
    **discarded the `ShareResult`** — so swiping the sheet away still said
    "Exported — choose where to save it." about a file in the app-documents
    directory, which Android will not let the user browse to. New
    `lib/data/export/file_share.dart` is a `FileShare` seam with our own
    `ShareOutcome` enum, so `share_plus` stays out of the widget layer — same
    pattern and same reason as `CsvFileSource`: the sheet is the one part that
    cannot run in a widget test, and the logic on either side of it is exactly what
    was wrong. `unknown` reads as success on purpose (the file was written and the
    sheet was offered; claiming a cancellation that may not have happened is the
    worse error), and the written file is **not** deleted — exporting again reuses
    it, and deleting is the one irreversible option. The dead
    `statisticsExportEmptyMessage` went with it. This is the first coverage the
    export messaging has ever had.
    **Not fixed, and not fixable**: being returned to the app after sharing to
    Telegram. `file_selector_android 0.5.2+9` does not implement `getSaveLocation`,
    so the base class's `UnimplementedError` stands and an SAF save dialog — which
    *would* hand control straight back — is unavailable on Android. Once the target
    app takes the intent it runs in its own task and Android returns to *its* back
    stack. Nothing in Dart or the manifest changes that.
    **`Printing.displayLabel` is now "SET-CODE (Rarity) Set Name"** (was
    "SET-CODE · Set Name · Rarity"). Set names run long enough to be ellipsised in
    a picker row, and a list of reprints showing a truncated name and *no rarity*
    cannot be picked from — which is the entire job of that picker. Set code and
    rarity together are the `printings` UNIQUE key, so the two fields that identify
    the row lead it and the human-readable gloss is what gets lost to the edge.
    Safe by construction: `filterPrintings` searches this string through
    `matchesSearchTerms`, which is order-independent, so no query changes meaning.
    `setLabel` is untouched (the detail screen gives rarity its own row).
    **Verified to fail before being kept**: the panel-cap case with the padding
    removed, and the camera-keepAlive guard reverted to `@riverpod`. The cap test
    needed **Mirror Force on a 393x640 viewport** to mean anything — Dark Magician
    has no printings, so `_SetPicker` self-hides and the short panel on a tall
    screen never collided; it passed with the fix removed until both were changed.
    **Still open**, unchanged: `maxHammingDistance` at 72,
    `CardDetectionTuning.innerQuadMinAreaRatio` at 0.78, the passcode ROI filter
    off, `artAgreementFrames` at 2, every `FrameQualityTuning` threshold still
    uncalibrated on device, and whether `kPriceTtl` at 24 h is right. New and
    accepted: while browsing the collection after a scan the camera stays bound and
    the OS privacy indicator stays lit — the trade the "open for the whole
    foreground" choice makes, held to an idle preview by `frameProcessingEnabled`.
    (**Step 29 made that trade the user's**, via a Settings switch; the paragraph
    above describes the switch's default, not a constant.)

29. Camera-lifetime toggle and em dashes out of the frontend ← done (verified:
    `flutter analyze` clean, full `flutter test` green at **738 tests**). **No DB
    migration, no schema change, no new dependency.** Nothing here touches the
    descriptor, `assets/card_hashes.json`, the detection algorithm or any
    scan/matching/quality threshold.
    **Step 28's camera lifetime is now a preference, not a constant.** That step
    made `cameraService`/`scanCamera` `@Riverpod(keepAlive: true)` and recorded the
    cost as *accepted*: a bound camera and a lit OS privacy indicator while
    browsing the collection afterwards. New `AppSettings.keepCameraReady`
    ("Keep the camera ready", **default true**, `settings.keep_camera_ready` in
    `meta`, guarded `_parseBool` like every bool since step 11), with a switch in
    Settings → Scanning whose subtitle names the *cost* — the benefit is obvious
    once felt, the indicator is not, and that asymmetry is the only reason the
    switch exists.
    **The mechanism is a `KeepAliveLink`, which is the per-value form of
    `keepAlive:` that the annotation cannot express.** Both providers are back to
    plain `@riverpod` and call one private `_pinWhileCameraKeptReady(ref)`: on, it
    takes `ref.keepAlive()` and the behaviour is step 28's exactly; off, nothing
    pins and the old teardown chain runs again on every scan-screen exit
    (`ScanScreen` unmounts → `ScanController` → `artReadings` → `scanCamera`'s
    `onDispose(camera.stop)` → `cameraService` → `service.dispose()`). **Both
    halves are still needed** for the reason `scanCamera`'s doc already gave: a
    pinned service behind an unpinned gate is stopped anyway. And the *provider*
    disposing alongside the service is load-bearing rather than incidental —
    `_disposed` is one-way, so re-entry can only work by building a new instance,
    which is precisely what an unpinned provider gives for free.
    **Three things this design is avoiding, all of them already-paid-for
    knowledge.** There is no exit-time provider write: step 21 established that
    Riverpod asserts on cross-provider writes from a provider's `build`, its own
    `ref.onDispose`, and every widget life-cycle including `dispose`. The decision
    is `ref.read`, **never `ref.watch`** — watching would *rebuild* `cameraService`
    on a toggle, replacing the `CameraScanService` while `scanCamera` reopens the
    camera behind it, i.e. opening the camera in Settings, the exact thing the
    switch exists to prevent. And the listener only ever **closes** the link, which
    keeps `ref.keepAlive()` out of a callback where `Ref` asserts on life-cycle
    use; `KeepAliveLink.close` touches no `Ref`, double-closing is a no-op, and
    closing the last link *schedules* disposal rather than reentering it. The
    consequence, deliberate and documented: turning the setting **off** releases
    the camera at once, turning it **on** takes effect at the next Log Cards entry.
    `ScanCameraActive` stays unconditionally `keepAlive` — one bool and one
    `AppLifecycleListener`, so there is nothing to release.
    **Both halves were verified to fail before being kept**, which mattered more
    than usual here because either failure is silent: with the pin made
    unconditional the new "the setting releases the camera" case fails, and with it
    removed the pre-existing "the camera survives leaving and re-entering" case
    fails. That older case also had to gain
    `keepCameraReadyProvider.overrideWithValue(true)` — it builds a bare
    `ProviderContainer`, which would otherwise reach the real settings controller
    and the database.
    **Em dashes are gone from everything the user can read.** Eleven code lines:
    ten `AppStrings` constants and `kNoPrice`, which is now `'-'` (a dash is still
    not `0.00`, which is the whole argument that constant's doc makes). Replacements
    are colons, full stops or parentheses as each sentence wanted; the three
    status-banner strings are the same length or shorter, so the fixed-height
    banner inside the reticle is unaffected. **No test assertion broke**, because
    every consumer references the constant symbolically rather than retyping the
    literal — only prose needed updating (`money_test.dart`'s comment,
    `collection_value_csv.dart`'s doc contrasting the CSV's empty cell with
    money.dart's mark). Two developer-facing literals went too: `hash_index.dart`'s
    ROI-mismatch `FormatException`, which can reach the screen through step 16's
    index-load error panel, and `collection_scroll_slider.dart`'s `assert`.
    **Explicitly out of scope**: the ~800 `///` and `//` comments in `lib/` and
    ~200 in `test/`. The check is `grep -rn '—' lib --include='*.dart'` returning
    nothing on a line that is not a comment.
    **Still open**, unchanged: `maxHammingDistance` at 72,
    `CardDetectionTuning.innerQuadMinAreaRatio` at 0.78, the passcode ROI filter
    off, `artAgreementFrames` at 2, every `FrameQualityTuning` threshold still
    uncalibrated on device, and whether `kPriceTtl` at 24 h is right.

30. Thirteenth on-device feedback pass — filter-sheet inset, import dates,
    Italian search, chip flicker ← done (verified: `flutter analyze` clean, full
    `flutter test` green at **773 tests**, `pytest tools/` green). **One DB
    migration (v4 → v5), no new dependency.** Nothing here touches the
    descriptor, `assets/card_hashes.json`, the detection algorithm or any
    scan/matching/quality threshold.
    **The filter sheet ran under the status bar**, and it was one missing
    parameter. `showModalBottomSheet` without `useSafeArea` wraps the sheet in
    `MediaQuery.removePadding(removeTop: true)` — so the `SafeArea` the sheet
    already had was a **no-op on top**, and with `isScrollControlled: true` and
    fourteen filters' worth of content the sheet reached the very top of the
    screen with its title 24pt below it, beside the clock. Everything else in
    the app clears the inset via an `AppBar`, which consumes it. `useSafeArea:
    true` on the filter sheet and on `_EditEntrySheet`, which had the identical
    omission. The regression test needs
    `tester.view.padding = const FakeViewPadding(top: 39)` to mean anything —
    without a real inset the assertion is vacuous, the trap step 21 documents —
    and was **verified to fail** with the parameter removed.
    **Every CSV-imported card was logged at the same instant.**
    `collectionToCsv` has always written `created_at`/`updated_at`, and
    `parseCollectionCsv` never read them: `CsvCollectionRow` had no timestamp
    fields at all, so `planCollectionImport` stamped every insert with the one
    import time. `getAll` orders by `ORDER BY ce.created_at <dir>, c.name ASC`,
    so with the primary key tied across the whole collection the
    **always-ascending** `c.name` tie-break decided the entire list — which is
    exactly the report: sorting by "Date added" did nothing in either direction,
    except for cards added after the import. The parser now reads both columns
    (`_epochMillis`: ISO-8601 first, a bare epoch integer second, since a
    spreadsheet will happily turn a date column into a number), `ResolvedImportRow`
    carries them, and inserts use `row.createdAt ?? now` /
    `row.updatedAt ?? row.createdAt ?? now`.
    **An unreadable date is null, never a row error** — a date is metadata about
    a card, not what the card *is*, and rejecting a card because a spreadsheet
    reformatted its date is the all-or-nothing failure the parser's whole
    error-per-row design exists to avoid. A matched entry's `created_at` is
    still never rewritten under either strategy. Four tests were **verified to
    fail** against the old `createdAt: now`.
    **Known limitation, stated rather than engineered around**: rows imported
    *before* this keep their shared timestamp, and re-importing the same file
    will not repair them, because `keepExisting` by contract does not write to a
    matched row.
    **Manual search can run against Italian names**, chosen from a dropdown
    beside the search box on both search screens. Nothing else changes: names,
    artwork and every downstream screen stay English, and a non-English hit
    carries its matched name as a muted italic second line, so a search for
    "Drago Bianco" returns rows that visibly contain what was typed
    (`CardSearchSubtitle`, shared by both screens because the *rule* is the
    interesting part).
    **The data is a committed generated asset**, the `assets/card_hashes.json`
    precedent exactly. Measured before choosing: `cardinfo.php?language=it` is
    **18 MB** over the wire for 11,599 cards — on top of the English sync's
    21 MB — but only **435 KB** reduced to id → name. Fetching it per sync would
    nearly double every sync, and every re-sync, for data that changes about as
    often as the hash index does. So `tools/build_localized_names.py` makes
    **one** request on the host and writes `assets/card_names_it.json`
    (`version`/`language`/`generated_at`/`count`/`names`, sorted keys for stable
    diffs). **The passcode key is `str(entry["id"])`, unpadded** — precisely what
    `YgoProdeckClient._parseEntry` stores in `cards.passcode`
    (`json['id'].toString()`); a padded key would join to nothing, and a pytest
    pins it. `card_images` is deliberately *not* walked, unlike the hash
    builder: an alt art is the same card with the same name, so indexing it
    would make the search return the card twice.
    **Runtime**: migration v5 adds `card_names` (see the schema section for why
    it has no foreign key — the one child table here that must *survive* a
    re-sync). `CardNameDao` owns the import; the search itself is
    `CardDao.searchByLocalizedName`, an **inner join** keeping the existing
    prefix-over-substring ranking but computed on the *localized* name — ordering
    on `c.name` would rank Italian results by the English alphabet, which reads
    as no order at all. The join is inner so a card the asset has no translation
    for is absent rather than listed under its English name, which would make it
    impossible to tell the two apart in one list.
    `CardRepository.search(query, language:)` is the single entry point both
    screens use, returning one `CardSearchHit` type (`models/card_search_hit.dart`,
    not the DAO file — it crosses into two widget trees).
    **The version check runs against a build constant, not the file.**
    `ensureLocalizedNames` compares `meta`'s `localized_names_it` stamp to
    `kLocalizedNamesVersion` *before* loading anything, so the steady state is
    one `meta` read rather than a 435 KB decode per keystroke;
    `parseLocalizedNames` throws if the asset's own version disagrees, which is
    what keeps the constant honest — the `HashIndex` ROI-header guard in
    miniature. Decoding runs in a `compute` isolate: small next to the hash
    index, but this loads while a search screen is live and someone is typing.
    An **English search never touches any of it** — no asset, no import, no
    `card_names` row — which is the first thing its test pins.
    `AppSettings.searchLanguage` (default `EN`, `settings.search_language`,
    guarded by a new `_parseChoice` against `kSearchLanguages`) has **no Settings
    row**, the documented precedent from `collectionViewMode` and the collection
    sort: the control lives where the effect is visible. Both search providers
    `watch` it — right here, unlike the read-once defaults in `ScanController`
    and `AddCardSelectionController`, because the language *is* a search input.
    `kSearchLanguages` is deliberately a different list from `kCardLanguages`:
    one is what a name can be matched in (needs a shipped asset), the other is
    what language a card in the collection is printed in (free-form TEXT).
    An asset test ties the committed file to the build, because as with the hash
    index nothing else opens it and the failure mode is a silent green.
    **The chip flicker was Material's checkmark.** `ChoiceChip` defaults to
    `showCheckmark: true`, so selecting a chip *widens* it, and in a `Wrap` that
    reflows the whole run — the chips after it shift right and can jump a line,
    under the finger that just tapped. `showCheckmark: false` on
    `LabeledChoiceChip` fixes every chip row in the app at once (condition,
    edition, language, the filter sheet) and changes no size, so it needed no
    layout work: selection stays unmistakable from `selectedColor` plus the dark
    `ConditionChipColors.onSelected` ink. Equal-width chips were considered and
    dropped — "Asian-English" would set the width for all nine. The four `Wrap`s
    that were missing `runSpacing` got it. Both chip tests were **verified to
    fail** with the line removed, and the second asserts the *other* chips have
    not moved, which is the symptom that was actually reported.

31. Fourteenth on-device feedback pass — Fast log, wizard artwork, help-box
    scrim, dropdown alignment ← done (verified: `flutter analyze` clean, full
    `flutter test` green at **814 tests**, `pytest tools/` green). **No DB
    migration, no schema change, no new dependency.** Nothing here touches the
    descriptor, `assets/card_hashes.json`, the detection algorithm or any
    scan/matching/quality threshold.
    **Fast log: log a card without being asked everything each time.** New
    `AppSettings.fastLogEnabled` + `fastLogFields`, a `Set<FastLogField>` over a
    new three-member enum (`condition`/`edition`/`language`). **Ticking a field
    means "still ask me about it"**; anything unticked is written from its
    Settings default with no control shown. The **set is never asked** while
    Fast log is on: `preferredPrinting` is untouched, so a card with one known
    printing is still logged against it and a card with several is logged
    without one.
    **The auto-disable rule is one derived getter**, `AppSettings.fastLogActive`
    = `fastLogEnabled && !fastLogFields.containsAll(values)`. Ticking everything
    asks for everything, so Fast log changes nothing and is treated as off. It
    lives on the model, not in either flow, because the failure mode is silent
    disagreement: the scan gate hiding a control the wizard still shows means
    the same card is logged differently depending on how it was entered.
    `fastLogAskedFields` is its companion, returning **everything** when
    inactive so no caller has to ask both questions. The user originally phrased
    the rule as "if nothing is selected" — that only holds under the opposite
    tick semantics, and was settled the other way, so the degenerate case is
    all-ticked rather than none.
    **Two fields, not one.** `fastLogEnabled` is intent, `fastLogFields` is
    configuration: folding them (an empty or null set meaning off) would make
    the switch destroy the ticks, so turning Fast log off and on again would
    lose what was configured. The default is the **empty set**, so the switch
    does its whole job at the first tap instead of needing a second trip into a
    sub-screen to do anything. And `AppSettings` still has **no `==`** —
    `copyWith` always yields a non-identical object so Riverpod always notifies,
    and adding deep set equality would newly suppress no-op writes across all
    fourteen fields. `Set.unmodifiable` goes at the two producer boundaries,
    never in the constructor, which would kill `const`.
    **`_parseFields` is the first guard here whose cases are deliberately not
    uniform**, and the asymmetry is the design: a missing key falls back; `''`
    is the **empty set**, because "ask about nothing" is the maximal Fast log
    and a real reachable configuration that must round-trip; unreadable members
    are dropped individually; but a non-empty value with *nothing* readable
    falls back rather than reading as empty. That last direction is the one that
    matters — a value we cannot read must degrade toward asking **more**, since
    the other way silently logs details the user was never shown. `save` writes
    the set in **declaration order** (`values.where(contains)`), not the set's
    own: a `{...set, field}` literal preserves insertion order, so without it
    the identical configuration stores two different strings depending on which
    switch was flipped first.
    **`setFastLogField(field, {asked})` takes one field, never a whole set.**
    `_update` composes each change onto the value the previous write published,
    so a caller passing a set it computed from the snapshot it rendered is
    exactly the stale-snapshot bug the `_writes` queue exists to prevent (step
    27) — and three switches on one screen is precisely the "two changes before
    the first write lands" case. **Verified to fail**: swapped for a whole-set
    setter, the two-ticks-in-succession test goes red with the second reverting
    the first.
    **The Configure surface is a flat route**, `AppRoutes.fastLog =
    '/settings/fast-log'`, the eleventh `GoRoute` and a sibling path like
    `/statistics/value` (this router still has no nesting). Not a dialog: the
    one dialog Settings owns is a *confirmation*, and an `AlertDialog` of
    switches inherits OK/Cancel semantics that would force local draft state,
    i.e. a second source of truth for a preference, where every other settings
    control writes through immediately. Concretely it also keeps three tiles
    titled Condition/Edition/Language off the Settings screen, where they would
    collide with the Defaults section's identical `_FieldLabel`s and ambiguate
    every finder.
    **Both controllers read the rule once, at build, through a passthrough
    getter** (`askedFields`/`fastLogActive` off the existing `late final
    _settings`) — **not** `ref.watch` in the panel, which would be a second,
    later read of the same setting: the panel could then render a different
    field set than the state was seeded under, hiding the grade chips while
    `state.condition` still holds a picked value that `confirm` still writes.
    Not a `ScanState`/`AddCardSelection` field either: it never changes after
    `build()`, and `AddCardSelection` has no `copyWith` at all, so it would mean
    ten field-by-field rebuilds each able to drop it. **`scan_controller.dart`
    gained no logic** — every gate-opening path already seeded
    condition/edition/language from the defaults, so Fast log changes only
    whether a control is *shown*, never what is written when one is left alone.
    **Each hidden block owns its trailing gap, and the off-state is
    pixel-identical.** `AppSpacing.md == 2 * sm` and `lg == md + sm`, so three
    trailing `sm`s plus the quantity row's own leading `sm` reproduces the scan
    panel's old `sm, sm, md`, and three trailing `md`s plus a leading `sm`
    reproduces the wizard's `md, md, lg`. Commented at both sites so it is not
    tidied back. The wizard's language block hides its muted label **and** its
    `xs` spacer with the chips — the scan panel has no such label, so that one
    is easy to leave orphaned above nothing.
    **The wizard's phase-1 step is `search`, not `condition`.** `selectCard` is
    two-phase with a stale-response guard, and jumping straight to the condition
    step under Fast log would expose a live Save button *before*
    `preferredPrinting` had been applied. On a cold sqflite isolate that is a
    real race, and Fast log is precisely the mode that encourages tapping a
    result then Save immediately, so losing it logs `printingId` null silently.
    The cost is one local query's worth of no feedback on the tap; if that reads
    badly on device the fix is a busy flag, not a step change. The app-bar back
    button gained `&& !controller.fastLogActive` so it cannot route into a step
    that is no longer offered, where Skip would null out an auto-picked set —
    **verified to fail** without it. Consequence, and both comments were
    corrected rather than left false: `preferredPrinting`'s rule 2 stays
    *visible* under Fast log (the set line still prints) but is no longer
    reversible in place, only correctable from the collection detail edit sheet.
    **`FastLogSummary` is an addition beyond the brief, and the reason is the
    review gate.** `_MatchedPanel`'s own doc calls it "the spec's non-negotiable
    'reviewable before it reaches the database' gate", and with every field
    hidden that panel is a picture, a quantity and a button while Confirm writes
    a grade, an edition and a language appearing nowhere on screen: the tap
    survives, its meaning does not. One muted `Logging as: NM · Unlimited · EN`
    line, listing only the **unasked** values, in exactly the space the hidden
    chip rows vacated. It returns `SizedBox.shrink()` when everything is asked,
    so both flows build it unconditionally. Deliberately synchronous and
    set-free: the wizard already prints the set, and reaching it in the scan
    panel would mean a second `cardPrintingsProvider` read.
    **The help box's scrim went 0.82 → 0.95**, which is the *same* fix
    `_DiagnosticsBox` already carries with its reasoning written out.
    `_SearchRoiOverlay` draws the reticle inflated by
    `ScanDetectionTokens.reticleRoiMargin` (0.08), so on a 393x851 phone its
    bottom edge lands ~36pt below the reticle border, inside the bottom-anchored
    help box — `ScanReticleTokens.verticalOffsetFraction`'s 12pt clearance
    budget is measured from the **border**, not the inflated search region. It
    is an earlier stack child, so its opaque `onSurfaceMuted` stroke read
    straight through. Suppressing the help box under diagnostics (the way
    `_SurfaceHint` is) was rejected: the hint is suppressed because diagnostics
    takes its slot in the capped band, while this box contends with nothing.
    **`SearchLanguageDropdown`**, the only dropdown in the manual add flow (the
    per-card language control is chips): `alignment: AlignmentDirectional.center`
    because the selected value renders in an `IndexedStack` sized to the widest
    item, so the shorter label sat left in a box shaped by the longer one; and
    `focusColor: Colors.transparent` + `vertical: AppSpacing.sm` on the
    container + `isDense: true`, because with the underline hidden the button is
    wrapped in an `InkWell` whose focus highlight painted the whole box, and the
    container had horizontal padding only. `isDense` offsets the added padding,
    which `itemHeight` would otherwise pin at 48 and leave taller than the
    search field beside it. **A rendering detail, so it wants a look on device.**
    **The wizard shows artwork now**, on both the printing and condition steps,
    via a shared private `_CardIdentity` shaped after the scan gate's identity
    row. It was the only logging surface with no picture, so a name in a search
    list was the only confirmation the right card had been picked.
    `CardArtThumbnail`, **not** `CardThumbnail`: the card is not owned yet, so
    `cards.local_image_path` is NULL and the plain thumbnail would render
    nothing.
    **Test gotchas, four.** `AppStrings.settingsFastLogLabel` is **"Use Fast
    log"**, not "Fast log" — the section header already says that, so two
    identical lines read as a rendering fault *and* made every `find.text`
    ambiguous. The Settings group's scroll helper is anchored on the **switch**,
    the first of the two tiles: scrolling to the Configure row below it carries
    the switch off the top of the lazy `ListView`, where it is disposed and
    finders miss it again. Any test whose subject is a setting must write the
    `meta` rows **and resolve `settingsControllerProvider`** before `pumpWidget`
    — both controllers read `.value` synchronously at build, so the flip-it-
    afterwards trick the `showScanHelp`/diagnostics cases use cannot reach them,
    and an unresolved load silently hands them `const AppSettings()`; the scan
    group needs a `ProviderContainer`/`UncontrolledProviderScope` for this, and
    `openWithSettings` was lifted out of its group in the wizard's suite. And
    `contains` on a `List<Map>` compares by identity, so a saved-row assertion
    needs `anyElement(equals({...}))`.
    **Still open**, unchanged: `maxHammingDistance` at 72,
    `CardDetectionTuning.innerQuadMinAreaRatio` at 0.78, the passcode ROI filter
    off, `artAgreementFrames` at 2, every `FrameQualityTuning` threshold still
    uncalibrated on device, and whether `kPriceTtl` at 24 h is right.

32. "Log again" — re-opening the review gate on the card just logged ← done
    (verified: `flutter analyze` clean, full `flutter test` green at **829
    tests**). **No DB migration, no schema change, no new dependency.** Nothing
    here touches the descriptor, `assets/card_hashes.json`, the detection
    algorithm or any shape/matching/quality threshold.
    Logging a stack of duplicates was slower than it should be, and the reason
    was a guard doing its job: `confirm()` sets `lastConfirmedPasscode` with
    `dismissCooldown: 0`, which only retires after
    `ScanTuning.debounceEmptyFrames` (5) frames with **no card in view**. So the
    second copy meant pulling the card out of the reticle, waiting ~1s, putting
    it back, and paying for detection, hashing and the two-frame agreement gate
    again. That debounce is the spec's non-optional guard against one card
    logging thirty times, so this pass goes around it rather than through it:
    one tap re-opens that card's review gate directly.
    **The offer hangs off a state field, not off `ScanStatus.confirmed`.** That
    status lasts about one frame — `_onArtReading`'s freeze guard deliberately
    excludes it so the post-confirm empty-frame debounce keeps advancing — so
    anything keyed to it blinks out immediately, and adding it to the guard
    would freeze the pipeline and mean the suppression could never retire. New
    `LoggedCard` (`scan_state.dart`, a const carrier beside `ScanState`,
    following `ArtCandidate`) is captured inside the very `copyWith` that clears
    the match, because `confirm()` destroys everything the gate reads:
    `matchedCard`, `matchedIndexPasscode`, `matchedDistance`, `candidates` and
    `printingId`.
    **`indexPasscode` is the load-bearing field on it.** The index keys every
    `card_images[i].id` while `cards` stores only `card_images[0]`, so on an
    alt-art match the resolved card's passcode is not the one the next frame
    carries; without carrying it across, the *second* confirm suppresses in the
    wrong namespace and the panel re-opens on the card just logged — step 16's
    bug, re-entered through the side door. The regression test was **verified to
    fail** with the field dropped.
    **`matchedDistance` is deliberately absent**, and gets it for free:
    `copyWith` replaces the distance whenever a non-null `matchedCard` is passed,
    so omitting it yields null and the "best guess, check the picture" hedge does
    not reappear on a card the user has already looked at and accepted.
    **Verified to fail** with a distance forced through.
    **`ScanController.logAgain()` is synchronous, and that is the point.** Every
    other path into the gate (`_resolveArtMatch`, `showBestGuesses`, `_lookup`,
    `selectCandidate`) awaits a DB read for the preferred printing and therefore
    needs the `handedOff`/`finally` discipline that keeps a leaked pause from
    killing recognition for the process lifetime (step 21). Here the printing is
    already known, so the pause is taken and handed to the panel in one step and
    a leak is structurally impossible. Do not "make it consistent" by adding an
    await. The form comes back on the set, grade, edition and language just
    logged rather than the settings defaults — the common case is another copy
    from the same pack — with quantity reset to 1.
    **Honest scoping of one claim**: `logAgain` leaves `lastConfirmedPasscode`
    and `dismissCooldown` untouched, but that is intent, not a load-bearing
    invariant. The pipeline is paused while the re-opened gate is up, and both
    `confirm` and `dismiss` rewrite the suppression on the way out, so clearing
    it there would not actually be observable — a mutation test proved exactly
    that, and the doc comment and the test's name were corrected rather than
    left overclaiming.
    **The SnackBar had to go where the bar goes, and finding that was the one
    real surprise.** Both are anchored to the bottom of the screen and a SnackBar
    floats over everything, so "Added to your collection." covered the offer —
    leaving its button not merely hidden but **untappable** for the four seconds
    the user is most likely to want the next copy. (It surfaced as two widget
    taps silently missing, which is the step-9 gotcha in a new place.) New
    `ScanState.offersLogAgain` is the single source of truth: the screen renders
    `_LogAgainBar` on it, `_MatchedPanel`'s confirm button suppresses its
    SnackBar on its negation, so the two cannot drift. The bar names the card it
    just logged, which is the same confirmation and a better one; passcode mode,
    where the bar does not render, keeps the SnackBar as its only feedback.
    **UI**: `_LogAgainBar` is modelled on `_HelpPanel`, **not** `_ScanBottomPanel`
    — the camera behind it is still live and a full-width sheet reads as a result
    waiting to be dealt with. It takes the help box's slot rather than stacking
    with it (same corner; the how-to is a first-run aid that has served its
    purpose by the time a card is logged), carries the same 0.95 scrim for the
    same `_SearchRoiOverlay` bleed-through reason, and uses `CardArtThumbnail`
    because the art download `addOrIncrement` fires is fire-and-forget and
    `cards.local_image_path` is very often still NULL a moment after a confirm.
    New `ScanLogAgainTokens`, three `AppStrings`, and a `scanLogAgainKey`
    following `scanReticleKey`/`scanStatusBannerKey`.
    **Passcode mode is deliberately not covered**: `confirm()` re-arms the OCR
    pass, so the status is `readingCode` and `_ReadingCodePanel` owns that slot.
    Offering it from that panel later is purely additive — `logAgain()` would
    need `readingCode` in its status guard and a `_stopOcr()`.
    The manual add-card wizard is **unchanged** (decided with the user): the
    duplicate-stack workflow happens at the camera.
    **Still open**, unchanged: `maxHammingDistance` at 72,
    `CardDetectionTuning.innerQuadMinAreaRatio` at 0.78, the passcode ROI filter
    off, `artAgreementFrames` at 2, every `FrameQualityTuning` threshold still
    uncalibrated on device, and whether `kPriceTtl` at 24 h is right.

33. Fifteenth on-device feedback pass — compact language picker, collection
    search by language, grid by default ← done (verified: `flutter analyze`
    clean, full `flutter test` green at **846 tests**, `pytest tools/` green).
    **No DB migration, no schema change, no new dependency.** Nothing here
    touches the descriptor, `assets/card_hashes.json`, the detection algorithm
    or any scan/matching/quality threshold.
    **`SearchLanguageDropdown` is now `SearchLanguagePicker`, and a
    `PopupMenuButton`.** The report was that the control beside the search box
    is too big and its menu nearly touches the screen edges. Both follow from
    one fact: it rendered `languageLabel(code)` — "English" / "Italian" — and a
    `DropdownButton` sizes its **menu to the button**, so the widest label set
    the width of both. A popup menu is sized to its own content, which is what
    lets the closed control shrink to a flag and two letters while the menu
    still spells the languages out; the full name had previously to live in the
    closed box to be readable anywhere. The conversion also retires the three
    `DropdownButton` workarounds step 31 added (`alignment`, `isDense`,
    `focusColor`) — they existed to fight the `IndexedStack` sizing and the
    `InkWell` focus highlight a popup menu does not have.
    The rename is honest rather than churn: the widget stops being a dropdown,
    and deleting the old file rather than aliasing it made `flutter analyze` the
    completeness check for the three call sites, the same technique step 9 used
    for `AppColors`. `LanguageFlag` is reused, not reinvented — it already
    handles the code-that-names-no-country case (`AE`) with an outlined badge
    and already wraps itself in `Semantics(label: languageLabel(...))`. Its
    documented caveat matters for tests: **on Windows and in the test
    environment the emoji font has no coverage and a regional-indicator pair
    renders as two letters**, so assertions match the *code*, never the glyph.
    New `SearchLanguagePickerTokens.height` = `AppTapTarget.minSize` (56), which
    is exactly what a filled `TextField` with an `OutlineInputBorder` and a
    prefix icon measures — pinning it is what keeps the two boxes level, and a
    widget test measures it, since a mismatch here reads as a misaligned control
    rather than as a wrong number.
    A `bare: true` form (the flag alone, no box and no code) is the app-bar
    shape. One widget with a flag rather than two widgets: what would actually
    be wrong if it drifted is the menu and the preference wiring, and those are
    shared.
    **The collection can be searched in Italian.** `CollectionDao.getAll`
    matched `c.name LIKE ?` against `cards.name`, which the sync only ever fills
    in English, so a card findable in the card database was not findable in the
    user's own collection. `getAll` gained a `nameLanguage` parameter and, past
    the default, an `EXISTS` on `card_names` beside the English predicate.
    **It is an OR, and that is the whole design decision** (settled with the
    user). `CardDao.searchByLocalizedName` uses an *inner join* on purpose — a
    card with no translation is absent rather than listed under its English name
    — but these rows are cards the user demonstrably owns: the asset covers
    ~11.6k of ~14.6k cards, so localized-only matching would make a card in the
    collection unfindable in the collection. Two DAO cases were **verified to
    fail** against a localized-only predicate before being kept.
    `EXISTS` rather than a `LEFT JOIN card_names`: nothing here displays the
    matched name, and a join would change the row shape of a query whose
    `SELECT` list every consumer reads by column. `card_names` is keyed on
    `(passcode, language)`, so the subquery is index-served.
    **`nameLanguage` is deliberately *not* a `CollectionFilter` field.** The
    language is already a persisted preference with its own provider
    (`searchLanguageProvider`, shared with both card-search screens), and a copy
    on the filter would be a second source of truth plus the exact
    `ref.read`-vs-`watch` trap `CollectionFilterController.build()` documents.
    So `activeCount`, `cleared()` and the exporter's and statistics'
    `const CollectionFilter()` call sites are all untouched.
    `collectionEntries` **watches** the language (unlike the sort, which is read
    once at build) because it is a search input, not a starting position, and
    calls `ensureLocalizedNames` **only when there is a query** — its first run
    decodes a 435 KB asset and inserts ~11.6k rows, and merely picking a
    language must not pay for that. A failure there degrades to English rather
    than propagating: the OR means every owned card is still findable, so a
    missing asset costs reach, not the list, and the collection is the wrong
    screen to report an asset fault on.
    The control is `SearchLanguagePicker(bare: true)`, **first** in the app
    bar's actions so sort and its direction toggle stay adjacent, and
    deliberately **absent from `_selectionAppBar`**. That closes a real hazard:
    `CollectionSelectionController` clears the selection by watching the
    *filter*, and this preference does not live there, so changing it
    mid-selection would narrow the list while leaving invisible rows selected
    for the bulk delete. Unreachable is what makes it impossible — the same
    argument that already hides the filter bar while selecting. Test-pinned.
    **The collection opens on "Artwork + name".** `AppSettings
    .collectionViewMode` defaults to `minifyStandard`; a collection is browsed
    far more often than edited, and the full row exists for the quantity and
    delete controls, which the detail screen also carries. The two
    `?? CollectionViewMode.standard` fallbacks that stand in while settings
    resolve became `const AppSettings().collectionViewMode`, so one source of
    truth and no flash of the wrong layout.
    **Known and accepted, not a bug**: `SettingsRepository.save` writes every
    key on every call, so any device that has ever changed a setting already has
    `settings.collection_view_mode` stored and keeps it. The new default reaches
    fresh installs only; an existing phone picks it once from the View menu. A
    one-time migration was considered and dropped (decided with the user) — it
    would silently override a mode the user may have chosen deliberately.
    **Test gotcha, and it is the real cost of that default.** About fifteen
    cases in `collection_screen_test` reach the +/− / delete controls or the
    long press, all of which live only on the standard row, and every one of
    them relied on `standard` being the default. Rather than editing each,
    `openCollection` gained
    `{CollectionViewMode? viewMode = CollectionViewMode.standard}` and writes
    that mode to `meta` before `pumpApp` — so every existing call site keeps its
    behaviour untouched, and **`viewMode: null`** (leave the row unwritten) is
    the one way to reach the real default, which the renamed
    "artwork + name is the default" case uses.
    **Still open**, unchanged: `maxHammingDistance` at 72,
    `CardDetectionTuning.innerQuadMinAreaRatio` at 0.78, the passcode ROI filter
    off, `artAgreementFrames` at 2, every `FrameQualityTuning` threshold still
    uncalibrated on device, and whether `kPriceTtl` at 24 h is right. New and
    open: the View button tints itself accent whenever the mode is not
    `standard`, so with the new default it reads "active" on first launch. Still
    literally true (you are in a grid), left alone pending a look on device.

34. Sixteenth on-device feedback pass — Italian interface, clear-search button,
    full-width filter chips, uncropped artwork, a shorter "Export cancelled" ←
    done (verified: `flutter analyze` clean, full `flutter test` green at **883
    tests**, `pytest tools/` green; **not yet checked on a device**). **No DB
    migration, no schema change.** One addition to the stack:
    `flutter_localizations` (see below). Nothing here touches the descriptor,
    `assets/card_hashes.json`, the detection algorithm or any
    scan/matching/quality threshold.
    **The interface is available in Italian, chosen in Settings → Appearance.**
    New `AppLanguage` enum (`ENGLISH`/`ITALIAN`) and `AppSettings.appLanguage`
    (default English, `settings.app_language` in `meta`, guarded `_parse`). Its
    labels are endonyms and never translated, so someone who switched by mistake
    can read the way back. **Interface text only** (decided with the user): card
    names, effect text and the API's type/race/attribute values stay as
    YGOPRODeck supplies them. Also deliberately untranslated: the scan
    diagnostics lines (a developer readout, kept comparable with the code that
    writes them) and `CardCondition.label`, since Cardmarket uses those grade
    names as-is in every language.
    **Every string is a getter written as `_t('English', 'Italiano')`**, all in
    `lib/core/constants.dart`. Both arguments are required, so a missing
    translation is a compile error. Keeping the name `AppStrings.x` meant none of
    the ~560 call sites and test references had to be rewritten, only the ~65
    `const` contexts around them, which the analyzer listed. **Consequences**:
    never read a string in a `const` context, and never capture one in a `final`
    or `static final`, which freezes the language it was first read in — hence
    `home_screen.dart`'s `_tiles` is a getter. Enum `label`s moved from
    constructor fields to getters for the same reason, and
    `kCardLanguageNames` became `AppStrings.cardLanguageNames`.
    **A `ValueKey` on `MaterialApp` looks like the fix and does not work.** That
    was the first implementation. go_router's navigator has a `GlobalKey`, so it
    is *moved* into the new tree intact, and `const HomeScreen()`, which watches
    nothing, keeps its English text. Screens that watch settings update anyway,
    which hides the bug: the first route-survival test passed on Fast log. `App`
    now `ref.listen`s for a language change and marks **every descendant element**
    dirty, the same walk a hot reload does, which also keeps the route, scroll
    positions and all other `State`. `SettingsController` calls
    `AppStrings.select` immediately before publishing, on load and in `_update`,
    so nothing can rebuild against the old table. Home is what
    `app_language_switch_test` asserts on, precisely because only the walk can
    reach it; **verified to fail** with the walk removed.
    `flutter_localizations` is an SDK package and the only source of Italian for
    Material's own text (the Back tooltip, the copy/paste toolbar). It pulls in
    `intl` transitively; app code still does not import it.
    `money.dart` uses a decimal comma in Italian, symbol still leading. The CSV
    writers do not use it, so exports stay `0.29`.
    `CsvFormatException` gained `missingColumn`, and the Statistics screen words
    the refusal, keeping interface text out of `lib/data/`. Its English `message`
    stays for developers and logs. Sentences glued to a number at the call site
    were kept wherever the number comes first in both languages; only the import
    summary (`'$n added'`) needed real functions.
    **How the longer text was checked**: the whole suite was run once with Italian
    as a temporary default. Tests read strings through `AppStrings` so they keep
    matching, and a string too long for its layout surfaces as an overflow. There
    were **no overflows**, and all 18 failures were tests pinning English
    literals. Worth repeating after adding strings to a fixed-size layout.
    **Clear button on search**: new `SearchField` replaces the three hand-rolled
    fields (collection, card search, manual add), which had no controller to clear
    through. `TextEditingController.clear()` does not fire `onChanged`, so the
    button reports `''` itself, or the field would empty over a list that stayed
    filtered. Each field is seeded from its provider's query, so a remount cannot
    show an empty box over a filtered list.
    **Filter chips fill the row** (the filter sheet only; the logging flows and
    Settings keep `Wrap`). New `JustifiedWrap` packs exactly as `Wrap` does and
    shares each run's leftover space equally, the last partial run included
    (decided with the user). The arithmetic is the pure, host-tested
    `justifyRuns`. `LabeledChoiceChip(expand: true)` centres its label with a
    `Center`, whose intrinsic width is still the text's, so packing is unaffected.
    It must stay off inside a plain `Wrap`, where a `Center` label would grow every
    chip to the full row. **Test gotcha**: measure the chip's `Material`, not the
    `ChoiceChip`. `RawChip` centres a natural-width pill inside whatever it is
    given, so the widget's box fills its slot even when the visible pill does not;
    the first version of the test passed with the centring removed.
    **Uncropped artwork**: `_CardIdentity` in the wizard passed no `aspectRatio`,
    which makes the thumbnail a square `cover` crop. It and the three scan-screen
    sites with the same omission (the review gate, the log-again bar, the guesses
    list) now draw the whole card.
    **"Export cancelled." lasts 2 s** (`SnackBarTokens.briefDuration`), on both
    export buttons via `_exportSnackBar`. Every other notice keeps Material's 4 s,
    including "Sharing cancelled." on the scan screen (decided with the user).
    **Still open**, unchanged: `maxHammingDistance` at 72,
    `CardDetectionTuning.innerQuadMinAreaRatio` at 0.78, the passcode ROI filter
    off, `artAgreementFrames` at 2, every `FrameQualityTuning` threshold still
    uncalibrated on device, and whether `kPriceTtl` at 24 h is right. New: the
    Italian wording has only been checked by its author, so it wants a native
    read on device, and the overflow check above used the test font, not Roboto.

## Standing rules

- No ORM. Raw SQL in DAOs only. No SQL outside `lib/data/db/`.
- Widgets never touch DAOs — screens depend on repositories via Riverpod providers.
- Every DAO method gets a test before the feature that consumes it.
- Enums persist by name, never by index.
- No business logic in `build()` methods.
- Prefer adding a migration over editing an existing one once version 1 is committed.

## Design direction (later sessions)

Dark-first, high-contrast, minimal. A single accent color, generous
spacing, large tap targets — this app is used one-handed while holding a
stack of cards in the other hand. Card condition renders as compact colored
chips using the MT/NM/EX short codes. The home menu is four large tiles:
Log Cards, My Collection, Statistics, Settings. These decisions live in
`lib/core/theme/tokens.dart` as named constants, not scattered magic numbers.

Dark is still the default, but since step 9 the colors are **not** constants
read directly by widgets: they live on `AppPalette` (a `ThemeExtension` with
`dark`/`light` instances) and widgets read `AppPalette.of(context).x`. Adding a
color means adding a field to `AppPalette` and giving it a value in *both*
palettes — never a bare `Color` const in widget code.
