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
    constants.dart
    result.dart
  data/
    db/
      database.dart
      migrations.dart
      dao/card_dao.dart
      dao/printing_dao.dart
      dao/collection_dao.dart
      dao/meta_dao.dart
    api/ygoprodeck_client.dart
    api/card_image_downloader.dart
    repositories/card_repository.dart
    repositories/collection_repository.dart
    seed/fake_collection_seed.dart
  models/
    ygo_card.dart
    printing.dart
    collection_entry.dart
    collection_entry_with_card.dart
    card_condition.dart
    card_edition.dart
  features/
    home/
    scan/
    collection/
    add_card/
    sync/
    settings/
  shared/widgets/
    card_thumbnail.dart
test/
  data/db/
  data/repositories/
  data/seed/
  models/
  features/
  shared/widgets/
tools/
  build_hash_index.py
assets/
```

## Database schema (version 2)

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
  the DAO — a plain get/set(key, value), REPLACE semantics).
- `meta` also carries a `last_sync` key (epoch ms), written at the end of
  `CardRepository.sync()`'s transaction. `CardRepository.needsSync()`
  treats a missing `last_sync` OR an empty `cards` table as "needs sync" —
  see the first-launch sync gate below.

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
   `lib/data/api/ygoprodeck_client.dart`), then downloads each artwork's
   **cropped** variant (`image_url_cropped` — art box only, matching the scan
   crop) and computes `imagehash.phash(hash_size=8)` → 16-hex-char string.
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
8. pHash art-matching fallback for OCR misses
9. Settings (default condition, default edition, language, re-sync, theme)
10. Export to CSV and .ydk; collection statistics. **Requirement**: must include an
    option to export the entire local database to a CSV file (not just the
    currently filtered/visible collection view).

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
