import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/repositories/card_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../models/app_settings.dart';
import '../../models/app_theme_mode.dart';
import '../../models/card_condition.dart';
import '../../models/card_edition.dart';
import '../../models/collection_view_mode.dart';
import '../collection/collection_providers.dart';
import '../sync/initial_sync_providers.dart';

part 'settings_providers.g.dart';

/// The user's preferences, loaded once and written through on every change.
///
/// `keepAlive` because `App` watches this for the theme and every logging flow
/// reads it — it must not be torn down between screens.
@Riverpod(keepAlive: true)
class SettingsController extends _$SettingsController {
  @override
  Future<AppSettings> build() async {
    final repository = await ref.watch(settingsRepositoryProvider.future);
    return repository.load();
  }

  Future<void> setDefaultCondition(CardCondition condition) =>
      _update((s) => s.copyWith(defaultCondition: condition));

  Future<void> setDefaultEdition(CardEdition edition) =>
      _update((s) => s.copyWith(defaultEdition: edition));

  Future<void> setLanguage(String language) =>
      _update((s) => s.copyWith(language: language));

  Future<void> setThemeMode(AppThemeMode themeMode) =>
      _update((s) => s.copyWith(themeMode: themeMode));

  Future<void> setShowScanDiagnostics(bool value) =>
      _update((s) => s.copyWith(showScanDiagnostics: value));

  Future<void> setShowScanHelp(bool value) =>
      _update((s) => s.copyWith(showScanHelp: value));

  Future<void> setConfirmBeforeDelete(bool value) =>
      _update((s) => s.copyWith(confirmBeforeDelete: value));

  /// Set from the collection screen's minify menu, not the Settings screen —
  /// the effect is only visible where the control is.
  Future<void> setCollectionViewMode(CollectionViewMode value) =>
      _update((s) => s.copyWith(collectionViewMode: value));

  /// Persist first, then publish: if the write fails the in-memory state must
  /// not claim a preference the database doesn't hold.
  Future<void> _update(AppSettings Function(AppSettings) change) async {
    final current = state.value;
    if (current == null) return;
    final next = change(current);
    final repository = await ref.read(settingsRepositoryProvider.future);
    await repository.save(next);
    state = AsyncData(next);
  }
}

/// When the card database was last synced, for the Settings screen's
/// "Last synced" line. Invalidated by [ResyncController] on success.
@riverpod
Future<DateTime?> lastSyncedAt(Ref ref) async {
  final repository = await ref.watch(cardRepositoryProvider.future);
  return repository.lastSyncedAt();
}

/// A user-triggered re-run of [CardRepository.sync], reported inline on the
/// Settings screen.
///
/// Deliberately separate from `InitialSyncController` even though it consumes
/// the same stream and reuses its state types: that one is the blocking
/// first-launch gate, and this one has different post-success duties (the
/// collection list and the last-synced stamp both go stale) and a different
/// failure contract — here the user can simply walk away.
@riverpod
class ResyncController extends _$ResyncController {
  @override
  InitialSyncState? build() => null;

  Future<void> start() async {
    state = const InitialSyncState(status: InitialSyncStatus.running);
    try {
      final repository = await ref.read(cardRepositoryProvider.future);
      await for (final p in repository.sync()) {
        state = InitialSyncState(
          status: InitialSyncStatus.running,
          progress: p.fraction,
          phase: p.phase,
        );
      }
      state = const InitialSyncState(
        status: InitialSyncStatus.success,
        progress: 1,
      );
      ref.invalidate(needsInitialSyncProvider);
      ref.invalidate(lastSyncedAtProvider);
      // A sync rewrites `cards`/`printings`, which the collection list joins
      // against — names, art paths and set data can all have changed, and with
      // them the rarities the collection filter row offers.
      ref.invalidate(collectionEntriesProvider);
      ref.invalidate(collectionFilterOptionsProvider);
    } catch (e) {
      state = InitialSyncState(status: InitialSyncStatus.failure, error: e);
    }
  }
}
