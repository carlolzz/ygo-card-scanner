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
`share_plus` (getting exports and scan samples off the device, steps 10/18) and
`file_selector` (opening a user-chosen file, step 20). A new one needs that same
justification: a capability none of the above provides.

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
    export/collection_csv.dart        # writer  ┐ one format,
    export/collection_csv_parser.dart # reader  ┘ one directory
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
