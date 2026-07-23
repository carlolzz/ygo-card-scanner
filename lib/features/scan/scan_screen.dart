import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/routes.dart';
import '../../core/theme/tokens.dart';
import '../../models/card_condition.dart';
import '../../models/card_edition.dart';
import '../../shared/widgets/card_thumbnail.dart';
import '../../shared/widgets/labeled_choice_chip.dart';
import 'art_matcher.dart';
import 'scan_controller.dart';
import 'scan_providers.dart';
import 'scan_state.dart';

/// The camera scan screen: live preview with a reticle, a status banner, and a
/// review panel that appears on a match. Continuous — after each confirm the
/// loop resumes for the next card.
///
/// Stateful only to bridge app lifecycle: the camera is released when the app
/// is backgrounded and restarted on return. No transition logic lives here —
/// that's all in [ScanController].
class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final active = state == AppLifecycleState.resumed;
    ref.read(scanCameraActiveProvider.notifier).set(active: active);
  }

  @override
  Widget build(BuildContext context) {
    final scan = ref.watch(scanControllerProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(AppStrings.scanTitle),
        actions: [
          // Persistent artwork-match entry point: the zero-digit OCR miss never
          // leaves `detecting`, so it needs a trigger outside the unknown panel.
          if (scan.status == ScanStatus.detecting ||
              scan.status == ScanStatus.reading)
            IconButton(
              tooltip: AppStrings.scanMatchByArtTooltip,
              icon: const Icon(Icons.image_search),
              onPressed:
                  ref.read(scanControllerProvider.notifier).matchByArtwork,
            ),
          IconButton(
            tooltip: AppStrings.scanManualTooltip,
            icon: const Icon(Icons.keyboard),
            onPressed: () => context.push(AppRoutes.addCard),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          const _CameraLayer(),
          if (scan.status == ScanStatus.detecting ||
              scan.status == ScanStatus.reading)
            const _ReticleOverlay(),
          _StatusBanner(status: scan.status),
          if (scan.status == ScanStatus.matched)
            _MatchedPanel(state: scan)
          else if (scan.status == ScanStatus.candidates)
            _CandidatePanel(candidates: scan.candidates)
          else if (scan.status == ScanStatus.unknown)
            const _UnknownPanel()
          else if (scan.status == ScanStatus.error)
            const _CameraErrorPanel(),
        ],
      ),
    );
  }
}

/// The live preview, or a neutral background until the camera is ready. Reads
/// the controller from [cameraServiceProvider] without forcing it to start —
/// starting is owned by [passcodeReadings]. Watching [scanControllerProvider]
/// (done by the parent) rebuilds this as the pipeline progresses.
class _CameraLayer extends ConsumerWidget {
  const _CameraLayer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(cameraServiceProvider).previewController;
    if (controller == null || !controller.value.isInitialized) {
      return const ColoredBox(color: AppColors.background);
    }
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => controller.value.isInitialized
          ? CameraPreview(controller)
          : const ColoredBox(color: AppColors.background),
    );
  }
}

class _ReticleOverlay extends StatelessWidget {
  const _ReticleOverlay();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth * ScanReticleTokens.widthFraction;
        final height = constraints.maxHeight * ScanReticleTokens.heightFraction;
        return Padding(
          padding: const EdgeInsets.only(bottom: ScanReticleTokens.bottomInset),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: width,
              height: height,
              decoration: BoxDecoration(
                border: Border.all(
                  color: AppColors.accent,
                  width: ScanReticleTokens.borderWidth,
                ),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              alignment: Alignment.center,
              child: const Text(
                AppStrings.scanHint,
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.onSurface),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.status});

  final ScanStatus status;

  @override
  Widget build(BuildContext context) {
    final label = switch (status) {
      ScanStatus.detecting => AppStrings.scanDetecting,
      ScanStatus.reading => AppStrings.scanReading,
      ScanStatus.matching => AppStrings.scanMatchingMessage,
      // matched/candidates/unknown/error render their own panels; confirmed is
      // transient.
      _ => null,
    };
    if (label == null) return const SizedBox.shrink();
    final busy = status == ScanStatus.matching;
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: kToolbarHeight + AppSpacing.sm),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: AppColors.surface.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (busy) ...[
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.accent,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                ],
                Text(
                  label,
                  style: const TextStyle(color: AppColors.onSurface),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The review panel shown on a match: card + editable grade + confirm. This is
/// the spec's non-negotiable "reviewable before it reaches the database" gate.
class _MatchedPanel extends ConsumerWidget {
  const _MatchedPanel({required this.state});

  final ScanState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(scanControllerProvider.notifier);
    final card = state.matchedCard!;

    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.lg),
          ),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CardThumbnail(
                      localImagePath: card.localImagePath,
                      size: CardThumbnailSizes.list,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            card.name,
                            style: const TextStyle(
                              color: AppColors.onSurface,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                          if (card.type != null)
                            Text(
                              card.type!,
                              style: const TextStyle(
                                color: AppColors.onSurfaceMuted,
                              ),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: AppStrings.scanRescanButton,
                      icon: const Icon(Icons.close, color: AppColors.onSurface),
                      onPressed: controller.dismiss,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.xs,
                  children: [
                    for (final condition in CardCondition.values)
                      LabeledChoiceChip(
                        label: condition.shortCode,
                        selected: state.condition == condition,
                        selectedColor:
                            ConditionChipColors.byShortCode[condition.shortCode]!,
                        onSelected: () => controller.setCondition(condition),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.xs,
                  children: [
                    for (final edition in CardEdition.values)
                      LabeledChoiceChip(
                        label: edition.label,
                        selected: state.edition == edition,
                        selectedColor: AppColors.accent,
                        onSelected: () => controller.setEdition(edition),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    const Text(
                      AppStrings.collectionQuantityLabel,
                      style: TextStyle(color: AppColors.onSurface),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: () =>
                          controller.setQuantity(state.quantity - 1),
                    ),
                    Text(
                      '${state.quantity}',
                      style: const TextStyle(
                        color: AppColors.onSurface,
                        fontSize: 18,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      color: AppColors.accent,
                      onPressed: () =>
                          controller.setQuantity(state.quantity + 1),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () async {
                      await controller.confirm();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(AppStrings.scanSavedMessage),
                          ),
                        );
                      }
                    },
                    child: const Text(AppStrings.scanConfirmButton),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The artwork-match result: a ranked list of candidate cards the user picks
/// from. Picking promotes the card into the [_MatchedPanel] review gate — the
/// same non-negotiable confirm step a scanned match uses.
class _CandidatePanel extends ConsumerWidget {
  const _CandidatePanel({required this.candidates});

  final List<ArtCandidate> candidates;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(scanControllerProvider.notifier);
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.xs,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            AppStrings.scanCandidatesTitle,
                            style: TextStyle(
                              color: AppColors.onSurface,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: AppStrings.scanRescanButton,
                          icon: const Icon(Icons.close,
                              color: AppColors.onSurface),
                          onPressed: controller.dismiss,
                        ),
                      ],
                    ),
                    const Text(
                      AppStrings.scanCandidatesSubtitle,
                      style: TextStyle(color: AppColors.onSurfaceMuted),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                  itemCount: candidates.length,
                  itemBuilder: (context, index) {
                    final candidate = candidates[index];
                    return ListTile(
                      leading: CardThumbnail(
                        localImagePath: candidate.card.localImagePath,
                        size: CardThumbnailSizes.list,
                      ),
                      title: Text(
                        candidate.card.name,
                        style: const TextStyle(color: AppColors.onSurface),
                      ),
                      subtitle: candidate.card.type != null
                          ? Text(
                              candidate.card.type!,
                              style: const TextStyle(
                                color: AppColors.onSurfaceMuted,
                              ),
                            )
                          : null,
                      onTap: () => controller.selectCandidate(candidate.card),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.xs,
                  AppSpacing.lg,
                  AppSpacing.md,
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () {
                      controller.dismiss();
                      context.push(AppRoutes.addCard);
                    },
                    child: const Text(AppStrings.scanUnknownSearchButton),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UnknownPanel extends ConsumerWidget {
  const _UnknownPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(scanControllerProvider.notifier);
    return _BottomMessage(
      title: AppStrings.scanUnknownTitle,
      message: AppStrings.scanUnknownMessage,
      // Try artwork first (it can surface alt-art reprints the passcode lookup
      // missed); this transitions to `matching`, so it must not dismiss.
      primaryLabel: AppStrings.scanMatchByArtButton,
      onPrimary: controller.matchByArtwork,
      secondaryLabel: AppStrings.scanUnknownSearchButton,
      onSecondary: () {
        controller.dismiss();
        context.push(AppRoutes.addCard);
      },
      tertiaryLabel: AppStrings.scanRescanButton,
      onTertiary: controller.dismiss,
    );
  }
}

class _CameraErrorPanel extends ConsumerWidget {
  const _CameraErrorPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(scanControllerProvider.notifier);
    return _BottomMessage(
      title: AppStrings.scanPermissionTitle,
      message: AppStrings.scanPermissionMessage,
      primaryLabel: AppStrings.scanRetryButton,
      onPrimary: controller.retry,
      secondaryLabel: AppStrings.scanUnknownSearchButton,
      onSecondary: () => context.push(AppRoutes.addCard),
    );
  }
}

/// A shared bottom sheet-style message with a primary + secondary action, used
/// by the unknown-passcode and camera-error states.
class _BottomMessage extends StatelessWidget {
  const _BottomMessage({
    required this.title,
    required this.message,
    required this.primaryLabel,
    required this.onPrimary,
    required this.secondaryLabel,
    required this.onSecondary,
    this.tertiaryLabel,
    this.onTertiary,
  });

  final String title;
  final String message;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String secondaryLabel;
  final VoidCallback onSecondary;
  final String? tertiaryLabel;
  final VoidCallback? onTertiary;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.lg),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.onSurface,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  message,
                  style: const TextStyle(color: AppColors.onSurfaceMuted),
                ),
                const SizedBox(height: AppSpacing.md),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: onPrimary,
                    child: Text(primaryLabel),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: onSecondary,
                    child: Text(secondaryLabel),
                  ),
                ),
                if (tertiaryLabel != null && onTertiary != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: onTertiary,
                      child: Text(tertiaryLabel!),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
