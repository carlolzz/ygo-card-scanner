import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/theme/tokens.dart';
import '../../data/repositories/card_repository.dart';
import 'initial_sync_providers.dart';

/// Blocking full-screen progress UI shown on first launch, before any
/// route is reachable, while the initial YGOPRODeck sync runs. No skip
/// affordance on failure: the app has no usable data until a sync
/// completes, so the only way forward is Retry.
class InitialSyncScreen extends ConsumerStatefulWidget {
  const InitialSyncScreen({super.key});

  @override
  ConsumerState<InitialSyncScreen> createState() => _InitialSyncScreenState();
}

class _InitialSyncScreenState extends ConsumerState<InitialSyncScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(initialSyncControllerProvider.notifier).start(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(initialSyncControllerProvider);

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: switch (state.status) {
            InitialSyncStatus.running => _RunningView(state: state),
            InitialSyncStatus.failure => const _FailureView(),
            // Transitional only — App swaps away to the router as soon as
            // needsInitialSyncProvider recomputes. An indeterminate spinner
            // here would animate forever and hang pumpAndSettle() in tests.
            InitialSyncStatus.success => const SizedBox.shrink(),
          },
        ),
      ),
    );
  }
}

class _RunningView extends StatelessWidget {
  const _RunningView({required this.state});

  final InitialSyncState state;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LinearProgressIndicator(value: state.progress),
        const SizedBox(height: AppSpacing.md),
        Text(
          state.phase == SyncPhase.writing
              ? AppStrings.syncWritingMessage
              : AppStrings.syncFetchingMessage,
          style: TextStyle(color: AppPalette.of(context).onSurfaceMuted),
        ),
      ],
    );
  }
}

class _FailureView extends ConsumerWidget {
  const _FailureView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.cloud_off, color: palette.onSurfaceMuted, size: 48),
        const SizedBox(height: AppSpacing.md),
        Text(
          AppStrings.syncErrorMessage,
          textAlign: TextAlign.center,
          style: TextStyle(color: palette.onSurfaceMuted),
        ),
        const SizedBox(height: AppSpacing.md),
        FilledButton(
          onPressed: () =>
              ref.read(initialSyncControllerProvider.notifier).start(),
          child: const Text(AppStrings.syncRetryButton),
        ),
      ],
    );
  }
}
