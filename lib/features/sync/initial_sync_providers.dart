import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/repositories/card_repository.dart';

part 'initial_sync_providers.g.dart';

/// Whether the blocking first-launch sync gate should be bypassed.
/// Defaults to [kDebugMode] — without this, every fresh debug install or
/// emulator wipe would force a real network sync before Home is reachable,
/// making the existing offline fixture-seed workflow unusable during
/// development. Overridable in tests to force real gate evaluation, since
/// `flutter test` always runs with `kDebugMode == true`.
@Riverpod(keepAlive: true)
bool debugSyncBypass(Ref ref) => kDebugMode;

@riverpod
Future<bool> needsInitialSync(Ref ref) async {
  if (ref.watch(debugSyncBypassProvider)) return false;
  final repository = await ref.watch(cardRepositoryProvider.future);
  return repository.needsSync();
}

enum InitialSyncStatus { running, success, failure }

class InitialSyncState {
  const InitialSyncState({
    required this.status,
    this.progress = 0,
    this.phase,
    this.error,
  });

  final InitialSyncStatus status;
  final double progress;
  final SyncPhase? phase;
  final Object? error;
}

@riverpod
class InitialSyncController extends _$InitialSyncController {
  @override
  InitialSyncState build() =>
      const InitialSyncState(status: InitialSyncStatus.running);

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
    } catch (e) {
      state = InitialSyncState(status: InitialSyncStatus.failure, error: e);
    }
  }
}
