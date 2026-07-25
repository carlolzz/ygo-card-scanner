import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/routes.dart';
import '../../core/theme/tokens.dart';
import '../../models/card_condition.dart';
import '../../models/card_edition.dart';
import '../../models/card_language.dart';
import '../../shared/widgets/card_art_thumbnail.dart';
import '../../shared/widgets/labeled_choice_chip.dart';
import '../../shared/widgets/printing_picker.dart';
import '../collection/collection_providers.dart';
import '../settings/settings_providers.dart';
import 'art_matcher.dart';
import 'art_providers.dart';
import 'scan_controller.dart';
import 'scan_geometry.dart';
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
    // Keep the camera through the transient `inactive` state: on first launch
    // the OS camera-permission dialog briefly makes the app inactive, and
    // releasing the camera there (then restarting on resume) is exactly the
    // churn that used to leave the preview dead until you re-entered the screen.
    // Release only on a genuine background.
    switch (state) {
      case AppLifecycleState.resumed:
      case AppLifecycleState.inactive:
        ref.read(scanCameraActiveProvider.notifier).set(active: true);
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        ref.read(scanCameraActiveProvider.notifier).set(active: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scan = ref.watch(scanControllerProvider);
    final palette = AppPalette.of(context);

    return Scaffold(
      backgroundColor: palette.background,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(AppStrings.scanTitle),
        actions: [
          // Developer aid: overlay the per-frame detection status + candidate
          // distances so recognition can be tuned from real numbers. A shortcut
          // for the persisted Settings toggle — both write the same value.
          IconButton(
            tooltip: AppStrings.scanDiagnosticsTooltip,
            icon: Icon(
              ref.watch(scanDiagnosticsEnabledProvider)
                  ? Icons.bug_report
                  : Icons.bug_report_outlined,
            ),
            onPressed: () => ref
                .read(settingsControllerProvider.notifier)
                .setShowScanDiagnostics(
                  !ref.read(scanDiagnosticsEnabledProvider),
                ),
          ),
          // The other recognition tool: read the printed 8-digit code when the
          // artwork won't resolve (glare, two near-identical arts, etc.). A
          // toggle, not a one-shot — it stays on until switched off here (or on
          // the reading panel), so a whole stack can be logged by code.
          if (scan.status == ScanStatus.detecting ||
              scan.status == ScanStatus.reading ||
              scan.status == ScanStatus.readingCode)
            IconButton(
              tooltip: scan.mode == ScanMode.passcode
                  ? AppStrings.scanExitCodeTooltip
                  : AppStrings.scanReadCodeTooltip,
              icon: Icon(
                scan.mode == ScanMode.passcode ? Icons.pin : Icons.pin_outlined,
                color: scan.mode == ScanMode.passcode
                    ? AppPalette.dark.accent
                    : null,
              ),
              onPressed: scan.mode == ScanMode.passcode
                  ? ref.read(scanControllerProvider.notifier).exitPasscodeMode
                  : ref
                        .read(scanControllerProvider.notifier)
                        .requestPasscodeRead,
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
          const _ViewportProbe(),
          const _CameraLayer(),
          if (scan.status == ScanStatus.detecting ||
              scan.status == ScanStatus.reading) ...[
            const _ReticleOverlay(),
            const _DetectionOutline(),
          ] else if (scan.status == ScanStatus.readingCode)
            const _PasscodeReticle(),
          if (scan.status == ScanStatus.matched)
            _MatchedPanel(state: scan)
          else if (scan.status == ScanStatus.candidates)
            _CandidatePanel(candidates: scan.candidates)
          else if (scan.status == ScanStatus.readingCode)
            const _ReadingCodePanel()
          else if (scan.status == ScanStatus.unknown)
            const _UnknownPanel()
          else if (scan.status == ScanStatus.error)
            const _CameraErrorPanel()
          // The bottom is free while scanning — show the how-to there, unless
          // the user has switched it off. It never coexists with the panels
          // above (all other statuses render one).
          else if ((scan.status == ScanStatus.detecting ||
                  scan.status == ScanStatus.reading) &&
              ref.watch(scanHelpEnabledProvider))
            const _HelpPanel(),
          // Last, so the top overlays stay above every panel.
          _TopOverlays(status: scan.status),
        ],
      ),
    );
  }
}

/// Backdrop for the camera layer and its overlays. Fixed to the dark palette
/// regardless of the user's theme: these sit on live camera imagery rather than
/// on app chrome, and a light scrim behind a viewfinder reads as a glitch.
final Color _cameraScrim = AppPalette.dark.background;

/// The live preview, or a neutral background until the camera is ready. Reads
/// the controller from [cameraServiceProvider] without forcing it to start —
/// starting is owned by [passcodeReadings].
///
/// Subscribes to [CameraService.preview] rather than sampling a getter: this
/// widget is const and [cameraServiceProvider] never publishes a new value, so
/// nothing else here would ever rebuild it. It would otherwise build exactly
/// once, while the camera is still opening, and hold the scrim forever.
class _CameraLayer extends ConsumerWidget {
  const _CameraLayer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ValueListenableBuilder<CameraController?>(
      valueListenable: ref.watch(cameraServiceProvider).preview,
      builder: (context, controller, _) {
        if (controller == null) return ColoredBox(color: _cameraScrim);
        return ListenableBuilder(
          listenable: controller,
          builder: (context, _) => controller.value.isInitialized
              ? _FullBleedPreview(controller: controller)
              : ColoredBox(color: _cameraScrim),
        );
      },
    );
  }
}

/// [CameraPreview] scaled to cover the viewport without distorting the image.
///
/// The scan body is a `StackFit.expand` stack, which hands `CameraPreview`
/// tight screen-sized constraints — its internal `AspectRatio` cannot honour
/// the sensor ratio under those, so the picture stretches to the screen's shape
/// (very visible on a tall phone against a 4:3 sensor). Sizing the preview
/// ourselves and letting a `FittedBox` cover-crop it keeps the geometry true,
/// which matters here: the reticle is a framing guide for the card.
class _FullBleedPreview extends StatelessWidget {
  const _FullBleedPreview({required this.controller});

  final CameraController controller;

  /// Arbitrary; only the ratio of the [SizedBox] matters, since the
  /// [FittedBox] rescales it to the viewport.
  static const double _baseHeight = 1000;

  @override
  Widget build(BuildContext context) {
    // Mirrors CameraPreview's own portrait/landscape flip of the sensor ratio,
    // so the box it is given matches the ratio it wants.
    final ratio = MediaQuery.orientationOf(context) == Orientation.landscape
        ? controller.value.aspectRatio
        : 1 / controller.value.aspectRatio;
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: ratio * _baseHeight,
          height: _baseHeight,
          child: CameraPreview(controller),
        ),
      ),
    );
  }
}

/// Publishes the preview's size to [scanViewportSizeProvider] so the detector
/// can map the on-screen guide box into camera-frame coordinates and search
/// only that region.
///
/// Its own zero-cost widget rather than a `LayoutBuilder` wrapped around the
/// stack: the write has to happen in a post-frame callback (never during
/// layout), and keeping it isolated means nothing else rebuilds when it lands.
class _ViewportProbe extends ConsumerStatefulWidget {
  const _ViewportProbe();

  @override
  ConsumerState<_ViewportProbe> createState() => _ViewportProbeState();
}

class _ViewportProbeState extends ConsumerState<_ViewportProbe> {
  /// Captured eagerly in [initState]: `dispose` can't do an inherited-widget
  /// lookup, and a lazy `late` field would run its initializer *during*
  /// dispose, which is exactly the unsafe `ref` use it's meant to avoid.
  late final ScanViewportSize _viewport;

  @override
  void initState() {
    super.initState();
    _viewport = ref.read(scanViewportSizeProvider.notifier);
  }

  @override
  void dispose() {
    // The detector falls back to the whole frame once the screen is gone.
    _viewport.set(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _viewport.set(size);
        });
        return const SizedBox.expand();
      },
    );
  }
}

/// A card-shaped guide the user fills with the *whole* card so its artwork
/// fills the frame. Its geometry comes from [reticleRectInViewport], the same
/// function the detector's search region is derived from — so the box the user
/// is asked to fill and the box actually searched cannot drift apart.
class _ReticleOverlay extends StatelessWidget {
  const _ReticleOverlay();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final reticle = reticleRectInViewport(constraints.biggest);
        return Center(
          child: Container(
            width: reticle.width,
            height: reticle.height,
            alignment: Alignment.bottomCenter,
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              border: Border.all(
                color: AppPalette.dark.accent,
                width: ScanReticleTokens.borderWidth,
              ),
              borderRadius:
                  BorderRadius.circular(ScanReticleTokens.cornerRadius),
            ),
            child: Text(
              AppStrings.scanHint,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppPalette.dark.onSurface),
            ),
          ),
        );
      },
    );
  }
}

/// Draws the card the detector just found, and the artwork window inside it,
/// directly onto the preview — so the user can see the app lock on instead of
/// guessing from a static guide box, and can tell at once whether a failure is
/// "it can't see the card" or "it sees it but can't name it".
///
/// Cosmetic only: nothing here feeds back into detection or matching, so a
/// geometry mismatch on some device can never affect what gets logged.
///
/// Detections arrive on the camera throttle (~300 ms), which would strobe if
/// painted raw, so the outline glides from its last position to the new one
/// over [ScanOutlineTokens.transition] and fades rather than blinks.
class _DetectionOutline extends ConsumerStatefulWidget {
  const _DetectionOutline();

  @override
  ConsumerState<_DetectionOutline> createState() => _DetectionOutlineState();
}

class _DetectionOutlineState extends ConsumerState<_DetectionOutline>
    with SingleTickerProviderStateMixin {
  /// Created in [initState], not as a `late final` initializer: the widget can
  /// be disposed without ever building (the scan screen swaps this out the
  /// moment a match arrives), and a lazy field would then construct a
  /// controller *inside* `dispose` — which trips the ticker assertion.
  late final AnimationController _controller;

  /// Where the outline is coming from, and where it is heading. A null [_to] is
  /// "no card this frame" — [_from] then fades out in place.
  List<Offset>? _from;
  List<Offset>? _to;

  /// The artwork window inside the card, as fractions of it — the region
  /// actually hashed. Falls back to the nominal ROI when the detector couldn't
  /// locate it, which is exactly what the matcher then crops.
  Rect _artBox = ArtMatchTuning.artBoxRoi;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: ScanOutlineTokens.transition,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onQuad(List<Offset>? quad, Rect? artBox) {
    _artBox = artBox ?? ArtMatchTuning.artBoxRoi;
    // Re-target from wherever the outline has actually reached, so a detection
    // landing mid-glide doesn't snap.
    final current = _interpolate(_controller.value);
    if (quad == null) {
      if (_to == null) return;
      _from = current;
      _to = null;
    } else {
      _from = current;
      _to = quad;
    }
    _controller.forward(from: 0);
  }

  /// The quad to paint at animation position [t], or null if there's nothing.
  List<Offset>? _interpolate(double t) {
    final from = _from;
    final to = _to;
    if (to == null) return from;
    if (from == null || from.length != to.length) return to;
    return [
      for (var i = 0; i < to.length; i++) Offset.lerp(from[i], to[i], t)!,
    ];
  }

  /// 0..1 — fades in on a new detection, out when the card leaves.
  double _opacity(double t) {
    if (_to == null) return _from == null ? 0 : 1 - t;
    return _from == null ? t : 1;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(artReadingsProvider, (_, next) {
      final reading = next.value;
      if (reading == null) return;
      _onQuad(reading.quad, reading.artBox);
    });

    // The preview's own aspect ratio, flipped for portrait exactly as
    // `_FullBleedPreview` does — the outline has to repeat the preview's
    // `BoxFit.cover` transform to land on the card.
    return ValueListenableBuilder<CameraController?>(
      valueListenable: ref.watch(cameraServiceProvider).preview,
      builder: (context, controller, _) {
        if (controller == null || !controller.value.isInitialized) {
          return const SizedBox.shrink();
        }
        final ratio =
            MediaQuery.orientationOf(context) == Orientation.landscape
            ? controller.value.aspectRatio
            : 1 / controller.value.aspectRatio;
        return IgnorePointer(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final quad = _interpolate(_controller.value);
              final opacity = _opacity(_controller.value);
              if (quad == null || opacity <= 0) {
                return const SizedBox.shrink();
              }
              // Repaints every frame for the length of the transition, so keep
              // it off the rest of the scan screen's layer.
              return RepaintBoundary(
                child: CustomPaint(
                  painter: _DetectionPainter(
                    quad: quad,
                    artBox: _artBox,
                    frameAspect: ratio,
                    opacity: opacity,
                    color: AppPalette.dark.accent,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _DetectionPainter extends CustomPainter {
  const _DetectionPainter({
    required this.quad,
    required this.artBox,
    required this.frameAspect,
    required this.opacity,
    required this.color,
  });

  /// Card corners as fractions of the upright frame: TL, TR, BR, BL.
  final List<Offset> quad;

  /// The hashed region, as fractions of the card.
  final Rect artBox;

  /// Upright frame width / height, for the cover transform.
  final double frameAspect;
  final double opacity;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Any size with the right aspect works — only the shape feeds the scale.
    final frame = Size(frameAspect * size.height, size.height);
    Offset toViewport(Offset fraction) =>
        frameFractionToViewport(fraction, frame, size);

    final corners = [for (final corner in quad) toViewport(corner)];
    final cardPath = _pathThrough(corners);

    final tint = color.withValues(alpha: opacity);
    canvas.drawPath(
      cardPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ScanOutlineTokens.cardStrokeWidth
        ..color = tint.withValues(alpha: opacity * 0.7),
    );

    // The artwork window — the region actually hashed — placed on the card by
    // blending the quad's corners: exact for an affine view, and close enough
    // for the mild perspective a hand-held card actually shows.
    final roi = artBox;
    final artPath = _pathThrough([
      toViewport(_onQuad(roi.left, roi.top)),
      toViewport(_onQuad(roi.right, roi.top)),
      toViewport(_onQuad(roi.right, roi.bottom)),
      toViewport(_onQuad(roi.left, roi.bottom)),
    ]);
    canvas.drawPath(
      artPath,
      Paint()
        ..style = PaintingStyle.fill
        ..color = tint.withValues(
          alpha: opacity * ScanOutlineTokens.artFillOpacity,
        ),
    );
    canvas.drawPath(
      artPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ScanOutlineTokens.artStrokeWidth
        ..color = tint,
    );
  }

  /// Bilinear point inside the detected quad, in frame fractions.
  Offset _onQuad(double u, double v) {
    final top = Offset.lerp(quad[0], quad[1], u)!;
    final bottom = Offset.lerp(quad[3], quad[2], u)!;
    return Offset.lerp(top, bottom, v)!;
  }

  static Path _pathThrough(List<Offset> points) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    return path..close();
  }

  @override
  bool shouldRepaint(_DetectionPainter old) =>
      old.opacity != opacity ||
      old.frameAspect != frameAspect ||
      old.color != color ||
      old.artBox != artBox ||
      !listEquals(old.quad, quad);
}

/// A small centered box for the on-demand passcode read: the user aims just the
/// 8-digit code at the screen's centre at a medium distance, keeping the small
/// text in focus (see [ScanPasscodeReticleTokens]).
class _PasscodeReticle extends StatelessWidget {
  const _PasscodeReticle();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Center(
          child: Container(
            width: constraints.maxWidth * ScanPasscodeReticleTokens.widthFraction,
            height:
                constraints.maxHeight * ScanPasscodeReticleTokens.heightFraction,
            decoration: BoxDecoration(
              border: Border.all(
                color: AppPalette.dark.accent,
                width: ScanPasscodeReticleTokens.borderWidth,
              ),
              borderRadius:
                  BorderRadius.circular(ScanPasscodeReticleTokens.cornerRadius),
            ),
          ),
        );
      },
    );
  }
}

/// A compact how-to card at the bottom of the scan screen, shown only while
/// scanning (`detecting`/`reading`) and only while the Settings toggle is on.
/// Explains the three ways to log a card, keyed to the AppBar actions. Fixed to
/// the dark palette — it sits on camera.
///
/// Deliberately tight: type one step below body size ([ScanHelpTokens]) and
/// smaller insets, so it takes as little of the viewfinder as it can.
class _HelpPanel extends StatelessWidget {
  const _HelpPanel();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        top: false,
        child: Padding(
          // Less bottom inset than the sides so the box sits lower, clear of the
          // reticle above it.
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.sm,
          ),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: _cameraScrim.withValues(alpha: 0.82),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppStrings.scanHelpTitle,
                  style: TextStyle(
                    color: AppPalette.dark.onSurface,
                    fontWeight: FontWeight.bold,
                    fontSize: ScanHelpTokens.titleFontSize,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                const _HelpLine(
                    Icons.center_focus_strong, AppStrings.scanHelpArtwork),
                const _HelpLine(Icons.pin, AppStrings.scanHelpCode),
                const _HelpLine(Icons.keyboard, AppStrings.scanHelpManual),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HelpLine extends StatelessWidget {
  const _HelpLine(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.dark;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: ScanHelpTokens.iconSize, color: palette.accent),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: palette.onSurfaceMuted,
                fontSize: ScanHelpTokens.lineFontSize,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The stack of overlays pinned under the app bar, in a single column so their
/// order is structural rather than a coincidence of two equal top insets: the
/// developer diagnostics box sits **above** the status banner, and the banner
/// moves down to make room whenever diagnostics is on.
///
/// Both are fixed to the dark palette — they sit on live camera imagery.
class _TopOverlays extends ConsumerWidget {
  const _TopOverlays({required this.status});

  final ScanStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final diagnostics = ref.watch(scanDiagnosticsEnabledProvider);
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: kToolbarHeight + AppSpacing.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (diagnostics) ...[
                const _DiagnosticsBox(),
                const SizedBox(height: AppSpacing.sm),
              ],
              _StatusBanner(status: status),
            ],
          ),
        ),
      ),
    );
  }
}

/// Developer readout of each frame's detection status and nearest candidate
/// distances, so a recognition failure can be diagnosed as detection (no card
/// found) vs matching (found, but distances large).
class _DiagnosticsBox extends ConsumerWidget {
  const _DiagnosticsBox();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reading = ref.watch(artReadingsProvider).value;
    final palette = AppPalette.dark;

    final status = reading?.status ?? ArtFrameStatus.noFrame;
    final lines = <String>[
      switch (status) {
        ArtFrameStatus.noFrame => AppStrings.scanDiagnosticsNoFrame,
        ArtFrameStatus.notDetected => AppStrings.scanDiagnosticsNotDetected,
        ArtFrameStatus.detected => AppStrings.scanDiagnosticsDetected,
      },
    ];
    if (reading != null && status == ArtFrameStatus.detected) {
      lines.add(
        reading.artBoxLocked
            ? AppStrings.scanDiagnosticsArtBoxLocked
            : AppStrings.scanDiagnosticsArtBoxFallback,
      );
      if (reading.nearest.isEmpty) {
        lines.add(AppStrings.scanDiagnosticsNoCandidates);
      } else {
        for (final match in reading.nearest) {
          lines.add('${match.passcode}  d=${match.distance}');
        }
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: _cameraScrim.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final line in lines)
            Text(
              line,
              style: TextStyle(
                color: palette.onSurface,
                fontSize: ScanDiagnosticsTokens.fontSize,
                fontFamily: ScanDiagnosticsTokens.fontFamily,
              ),
            ),
        ],
      ),
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
      // matched/candidates/readingCode/unknown/error render their own panels;
      // confirmed is transient.
      _ => null,
    };
    if (label == null) return const SizedBox.shrink();
    final busy = status == ScanStatus.reading;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: _cameraScrim.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy) ...[
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppPalette.dark.accent,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          Text(label, style: TextStyle(color: AppPalette.dark.onSurface)),
        ],
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
    final palette = AppPalette.of(context);

    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: palette.surface,
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
                    CardArtThumbnail(
                      card: card,
                      size: CardThumbnailSizes.list,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            card.name,
                            style: TextStyle(
                              color: palette.onSurface,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                          if (card.type != null)
                            Text(
                              card.type!,
                              style: TextStyle(
                                color: palette.onSurfaceMuted,
                              ),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: AppStrings.scanRescanButton,
                      icon: Icon(Icons.close, color: palette.onSurface),
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
                        selectedColor: palette.accent,
                        onSelected: () => controller.setEdition(edition),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.xs,
                  children: [
                    for (final language in kCardLanguages)
                      LabeledChoiceChip(
                        label: languageLabel(language),
                        selected: state.language == language,
                        selectedColor: palette.accent,
                        onSelected: () => controller.setLanguage(language),
                      ),
                  ],
                ),
                _SetPicker(
                  passcode: card.passcode,
                  printingId: state.printingId,
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Text(
                      AppStrings.collectionQuantityLabel,
                      style: TextStyle(color: palette.onSurface),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: () =>
                          controller.setQuantity(state.quantity - 1),
                    ),
                    Text(
                      '${state.quantity}',
                      style: TextStyle(
                        color: palette.onSurface,
                        fontSize: 18,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      color: palette.accent,
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
                // An automatic artwork guess can be wrong, so offer the ranked
                // alternatives right here (only when there are any — an OCR
                // passcode match is exact and carries none).
                if (state.candidates.length > 1)
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: controller.showCandidates,
                      child: const Text(AppStrings.scanNotThisCardButton),
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

/// The set/expansion picker inside the review gate. The camera can't tell which
/// reprint is in hand — passcodes are rarity- and set-independent — so it is
/// chosen here, from the card's known printings, exactly like the manual add
/// flow's printing step. Defaults to "no specific set", which is what a scan
/// used to log unconditionally.
///
/// Hidden when the card has no known printings: the only option would then be
/// "no specific set", and a dead control on the fast path is worse than none.
class _SetPicker extends ConsumerWidget {
  const _SetPicker({required this.passcode, required this.printingId});

  final String passcode;
  final int? printingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // `.value`, not `when`: a spinner would make the review panel jump on every
    // match, and this is optional detail — it can appear a frame later.
    final printings = ref.watch(cardPrintingsProvider(passcode)).value;
    if (printings == null || printings.isEmpty) return const SizedBox.shrink();

    final palette = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.sm),
        Text(
          AppStrings.scanSetLabel,
          style: TextStyle(color: palette.onSurfaceMuted),
        ),
        const SizedBox(height: AppSpacing.xs),
        PrintingPicker(
          printings: printings,
          selectedId: printingId,
          noSetLabel: AppStrings.scanNoSetOption,
          onSelected: ref.read(scanControllerProvider.notifier).setPrinting,
        ),
      ],
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
    final palette = AppPalette.of(context);
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: palette.surface,
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
                        Expanded(
                          child: Text(
                            AppStrings.scanCandidatesTitle,
                            style: TextStyle(
                              color: palette.onSurface,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: AppStrings.scanRescanButton,
                          icon: Icon(Icons.close, color: palette.onSurface),
                          onPressed: controller.dismiss,
                        ),
                      ],
                    ),
                    Text(
                      AppStrings.scanCandidatesSubtitle,
                      style: TextStyle(color: palette.onSurfaceMuted),
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
                      leading: CardArtThumbnail(
                        card: candidate.card,
                        size: CardThumbnailSizes.list,
                      ),
                      title: Text(
                        candidate.card.name,
                        style: TextStyle(color: palette.onSurface),
                      ),
                      subtitle: candidate.card.type != null
                          ? Text(
                              candidate.card.type!,
                              style: TextStyle(
                                color: palette.onSurfaceMuted,
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

/// Shown when the on-demand passcode read resolved to a code that's in no card
/// in the local DB — the card isn't in our data, so artwork wouldn't help
/// either. The way forward is a manual search or another scan.
class _UnknownPanel extends ConsumerWidget {
  const _UnknownPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(scanControllerProvider.notifier);
    return _BottomMessage(
      title: AppStrings.scanUnknownTitle,
      message: AppStrings.scanUnknownMessage,
      primaryLabel: AppStrings.scanUnknownSearchButton,
      onPrimary: () {
        controller.dismiss();
        context.push(AppRoutes.addCard);
      },
      secondaryLabel: AppStrings.scanRescanButton,
      onSecondary: controller.dismiss,
    );
  }
}

/// The on-demand OCR fallback in progress: a spinner + how-to, with a way out.
/// The artwork path is frozen while this runs (see [ScanController]).
class _ReadingCodePanel extends ConsumerWidget {
  const _ReadingCodePanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(scanControllerProvider.notifier);
    final palette = AppPalette.of(context);
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: palette.accent,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      AppStrings.scanReadingCodeTitle,
                      style: TextStyle(
                        color: palette.onSurface,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  AppStrings.scanReadingCodeMessage,
                  style: TextStyle(color: palette.onSurfaceMuted),
                ),
                const SizedBox(height: AppSpacing.md),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: controller.exitPasscodeMode,
                    child: const Text(AppStrings.scanReadCodeCancelButton),
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
  });

  final String title;
  final String message;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String secondaryLabel;
  final VoidCallback onSecondary;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: palette.surface,
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
                  style: TextStyle(
                    color: palette.onSurface,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  message,
                  style: TextStyle(color: palette.onSurfaceMuted),
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
