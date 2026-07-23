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
    repositories/settings_repository.dart
    seed/fake_collection_seed.dart
  models/
    ygo_card.dart
    printing.dart
    collection_entry.dart
    collection_entry_with_card.dart
    card_condition.dart
    card_edition.dart
    card_language.dart
    app_settings.dart
    app_theme_mode.dart
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
   freeze guard; `ScanController.matchByArtwork()` (re-checks status after the
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
