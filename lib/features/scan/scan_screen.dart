import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

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
import 'camera_service.dart';
import 'card_detector.dart';
import 'detector_isolate.dart';
import 'frame_quality.dart';
import 'scan_controller.dart';
import 'scan_sample.dart';
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
    // **Clear any pause left behind by a previous scanning session.**
    //
    // [ScanPaused] is `keepAlive` — deliberately, since its writer and reader
    // both use `ref.read` and autoDispose made the whole optimisation inert —
    // while its only writer, [ScanController], is autoDispose. So a screen torn
    // down with a review panel, candidate list or camera error on it left the
    // flag `true` for the rest of the process, after which `artReadings` skipped
    // every frame forever: the camera restarted correctly on every re-entry, the
    // preview was live, the reticle was drawn, and nothing was ever recognised
    // again until the app was relaunched. That is the reported "decline a card
    // and the camera stops working" bug, and it is why closing the app fixed it.
    //
    // Reset on **entry**, not on the previous screen's exit, for two reasons: a
    // fresh [ScanController] always starts in `detecting`, so unpaused is the
    // only correct state here whatever happened last time; and Riverpod asserts
    // on provider writes from any widget life-cycle, `dispose` included (the
    // same latent trap `_ViewportProbeState.dispose` sits in). A post-frame
    // callback is outside the build phase, which is what makes the write legal —
    // the same reason `_ViewportProbe` publishes its size from one.
    //
    // The controller releases the pause structurally on every resolution path;
    // this is the backstop for the paths that end by leaving the screen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(scanPausedProvider.notifier).set(paused: false);
    });
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
            _ReticleOverlay(status: scan.status, hint: scan.hint),
            const _SearchRoiOverlay(),
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
/// fills the frame.
///
/// The box's geometry comes from [reticleRectInViewport], the same function the
/// detector's search region is derived from — so the box the user is asked to
/// fill and the box actually searched cannot drift apart.
///
/// **The box is placed from that rect and nothing else.** It used to be a
/// `Center`, with a doc warning that wrapping it in a `Column` alongside
/// anything else would push the drawn box off-centre while the searched region
/// stayed put — a silent desync. `Positioned.fromRect` removes the hazard
/// rather than documenting it: the box is the rect, wherever the rect is. The
/// surface hint still lives in [_TopOverlays], where it belongs anyway.
///
/// Content placed *inside* the fixed-size `Container` is free, however, and that
/// is where the status banner now sits: the box has an explicit `width`/`height`
/// from the rect, so its child cannot move it. Putting the banner there is what
/// frees the band above the guide for the diagnostics readout — which the
/// banner used to take the bottom ~44pt of. It replaces the old static "fit the
/// whole card inside the box" line, which the box's own shape already says.
class _ReticleOverlay extends StatelessWidget {
  const _ReticleOverlay({required this.status, required this.hint});

  final ScanStatus status;
  final ScanHint hint;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final reticle = reticleRectInViewport(constraints.biggest);
        // `Positioned.fromRect`, not a `Center`: the box is no longer at the
        // viewport's centre, and placing it from the rect itself states the
        // invariant instead of re-deriving it.
        return Stack(
          children: [
            Positioned.fromRect(
              rect: reticle,
              child: Container(
                key: scanReticleKey,
                alignment: Alignment.bottomCenter,
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: AppPalette.dark.accent,
                    width: ScanReticleTokens.borderWidth,
                  ),
                  borderRadius: BorderRadius.circular(
                    ScanReticleTokens.cornerRadius,
                  ),
                ),
                child: _StatusBanner(status: status, hint: hint),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Identifies the drawn guide box for tests, which assert it is exactly
/// [reticleRectInViewport] — the invariant that keeps the box the user aims
/// through and the region the detector searches the same rectangle.
@visibleForTesting
const Key scanReticleKey = Key('scan-reticle');

/// The "lay the cards on a plain dark surface" note. Scrimmed like
/// [_HelpPanel], since it sits on live camera imagery and has to stay legible
/// over bright artwork; fixed to the dark palette for the same reason.
class _SurfaceHint extends StatelessWidget {
  const _SurfaceHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: _cameraScrim.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Text(
        AppStrings.scanSurfaceHint,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: AppPalette.dark.onSurfaceMuted,
          fontSize: ScanHelpTokens.lineFontSize,
        ),
      ),
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

    // The outline has to repeat the preview's `BoxFit.cover` transform to land
    // on the card, but the quad's *own* space is the analysis stream — see
    // [_streamFrameAspect]. Fall back to the preview's aspect (flipped for
    // portrait exactly as `_FullBleedPreview` does) until a frame has arrived.
    return ValueListenableBuilder<CameraController?>(
      valueListenable: ref.watch(cameraServiceProvider).preview,
      builder: (context, controller, _) {
        if (controller == null || !controller.value.isInitialized) {
          return const SizedBox.shrink();
        }
        final ratio =
            _streamFrameAspect(ref) ??
            (MediaQuery.orientationOf(context) == Orientation.landscape
                ? controller.value.aspectRatio
                : 1 / controller.value.aspectRatio);
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

/// Aspect (width/height) of the **upright image-stream frame** — the space
/// `DetectedCard.quad` and [detectionRoiInFrame] both live in.
///
/// Not the preview's. CameraX chooses Preview and ImageAnalysis resolutions
/// independently, so the two can differ (`ResolutionPreset.high` has been
/// reported resolving to a 720x540 preview against a 16:9 analysis stream). The
/// ROI mapping is self-correcting under that mismatch — cover-mapping through
/// either aspect composes to the same thing — but a *painter* is not: feeding it
/// the preview aspect mis-scales the drawn outline about the centre by the ratio
/// of the two, while the region actually searched stays correct. Since a
/// correctly hugging outline is the on-device acceptance test for the ROI
/// mapping, that would send the next debugging pass after a bug that isn't there.
///
/// Null before the first frame; callers fall back to the preview's aspect, which
/// is the best available guess and no worse than the old behaviour.
double? _streamFrameAspect(WidgetRef ref) {
  final frame = ref.read(cameraServiceProvider).latestArtFrame;
  if (frame == null) return null;
  final swap = frame.rotationDegrees == 90 || frame.rotationDegrees == 270;
  final width = swap ? frame.height : frame.width;
  final height = swap ? frame.width : frame.height;
  return height == 0 ? null : width / height;
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

/// Outlines the region the detector actually searches, shown only while
/// diagnostics is on.
///
/// The reticle-to-frame mapping ([detectionRoiInFrame]) is the one part of this
/// pipeline that can be wrong with no visible symptom: the preview is a
/// `BoxFit.cover` crop, so the guide box's on-screen fractions are *not* its
/// frame fractions, and getting that conversion wrong just makes recognition
/// quietly unreliable.
///
/// **What this can and cannot show.** The round trip drawn here — reticle →
/// frame fractions → back to the viewport — is a pair of exact inverses, so the
/// rectangle is the reticle inflated by the ROI margin *for any frame aspect*,
/// including a wrong one. It confirms the margin and that the clamp to [0,1]
/// didn't bite; it cannot confirm the aspect. What settles that is the
/// `frame:` line in the diagnostics box, which prints the stream's own aspect
/// beside the preview's. Feeding this painter the stream aspect (rather than the
/// preview's) at least makes the two agree about which space they are in.
class _SearchRoiOverlay extends ConsumerWidget {
  const _SearchRoiOverlay();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(scanDiagnosticsEnabledProvider)) {
      return const SizedBox.shrink();
    }
    return ValueListenableBuilder<CameraController?>(
      valueListenable: ref.watch(cameraServiceProvider).preview,
      builder: (context, controller, _) {
        if (controller == null || !controller.value.isInitialized) {
          return const SizedBox.shrink();
        }
        final ratio =
            _streamFrameAspect(ref) ??
            (MediaQuery.orientationOf(context) == Orientation.landscape
                ? controller.value.aspectRatio
                : 1 / controller.value.aspectRatio);
        return IgnorePointer(
          child: CustomPaint(
            painter: _SearchRoiPainter(
              frameAspect: ratio,
              color: AppPalette.dark.onSurfaceMuted,
            ),
          ),
        );
      },
    );
  }
}

class _SearchRoiPainter extends CustomPainter {
  const _SearchRoiPainter({required this.frameAspect, required this.color});

  /// Upright frame width / height, for the cover transform.
  final double frameAspect;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Any size with the right aspect works — only the shape feeds the scale.
    final frame = Size(frameAspect * size.height, size.height);
    final roi = detectionRoiInFrame(viewport: size, frame: frame);
    final topLeft = frameFractionToViewport(roi.topLeft, frame, size);
    final bottomRight = frameFractionToViewport(roi.bottomRight, frame, size);
    canvas.drawRect(
      Rect.fromPoints(topLeft, bottomRight),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ScanDiagnosticsTokens.searchRoiStrokeWidth
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_SearchRoiPainter old) =>
      old.frameAspect != frameAspect || old.color != color;
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

/// The overlays pinned under the app bar: the developer diagnostics box, and
/// the surface hint when diagnostics is off. They are mutually exclusive today,
/// but they stay in one column so their order is structural rather than a
/// coincidence of two independent insets — which is exactly how they used to
/// collide.
///
/// **The column is capped to the band above the reticle.** Everything here grows
/// downward from the app bar while the guide box is fixed, so an uncapped
/// diagnostics box reached well into the box the user is trying to fill with a
/// card — the one region on this screen that must stay clear. The band is
/// measured, not guessed: this widget is a non-positioned child of an expanded
/// `Stack`, so its constraints *are* the viewport, the same space
/// [reticleRectInViewport] answers in.
///
/// **The status banner is not here — it lives inside the guide box.** It was the
/// fixed-size last child of this column and so took its height off the top of
/// the band before the flexible diagnostics box saw any, leaving the readout
/// about a third of the room it needed on a 393x851 phone. Inside the box it
/// costs the band nothing (see [_ReticleOverlay] for why that is safe), and
/// [ScanReticleTokens.verticalOffsetFraction] lowers the box to widen the band
/// further.
///
/// **The surface hint lives here, not next to the reticle.** It used to be a
/// `Positioned` anchored to `reticle.top` inside [_ReticleOverlay], while the
/// banner grew downward from the app bar — two unrelated coordinate systems both
/// growing toward the middle of the screen, which overlapped by ~35pt on a
/// 360x640 viewport and closed entirely under text scaling or a taller status
/// bar.
///
/// Both are fixed to the dark palette — they sit on live camera imagery.
class _TopOverlays extends ConsumerWidget {
  const _TopOverlays({required this.status});

  final ScanStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Only while the camera is actually being pointed at something. During a
    // review the diagnostics box is *stale* anyway — `_resolveArtMatch` sets
    // `scanPaused`, so `artReadings` stops emitting and its recognition lines
    // freeze on the last pre-match frame — and it sits over the review panel
    // while the user is entering card details.
    final scanning =
        status == ScanStatus.detecting || status == ScanStatus.reading;
    final diagnostics = scanning && ref.watch(scanDiagnosticsEnabledProvider);
    // Part of the on-screen help, so it follows the same Settings switch as the
    // bottom how-to box. Suppressed while diagnostics is on purely for clutter
    // now that an overlap is structurally impossible.
    final showHint =
        scanning &&
        ref.watch(scanHelpEnabledProvider) &&
        !ref.watch(scanDiagnosticsEnabledProvider);
    return LayoutBuilder(
      builder: (context, constraints) {
        // Where this column starts, in viewport coordinates. `Scaffold` with
        // `extendBodyBehindAppBar` reports the app bar to the body *as*
        // `MediaQuery` padding, which the SafeArea below already consumes — so
        // the only inset left to add is the gap. This used to add
        // `kToolbarHeight` on top of that, counting the app bar twice and
        // leaving a whole toolbar's worth of empty space between the icons and
        // the overlays, at the expense of the band above the reticle.
        final top = MediaQuery.paddingOf(context).top + AppSpacing.sm;
        final band =
            reticleRectInViewport(constraints.biggest).top -
            top -
            ScanDiagnosticsTokens.reticleGap;
        return SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
              ).copyWith(top: AppSpacing.sm),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: math.max(
                    band,
                    ScanDiagnosticsTokens.minBandHeight,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Flexible, and it now gets the whole band: with the banner
                    // moved into the guide box there is no fixed-size sibling
                    // taking its height first. It still scrolls internally, as
                    // the failsafe for landscape or large-text viewports where
                    // `minBandHeight` wins.
                    if (diagnostics) const Flexible(child: _DiagnosticsBox()),
                    if (showHint) const _SurfaceHint(),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Developer readout of the camera's state and each frame's detection status and
/// nearest candidate distances, so a recognition failure can be diagnosed as
/// camera (no frames at all), detection (frames, no card found) or matching
/// (card found, but distances large).
///
/// Stateful for a ticker, and that is load-bearing: the camera line is the whole
/// reason this exists, and a stalled camera stops [artReadings] emitting — so a
/// box that only rebuilt on a reading would freeze on its last value precisely
/// when the camera state is what you need to see.
class _DiagnosticsBox extends ConsumerStatefulWidget {
  const _DiagnosticsBox();

  @override
  ConsumerState<_DiagnosticsBox> createState() => _DiagnosticsBoxState();
}

class _DiagnosticsBoxState extends ConsumerState<_DiagnosticsBox> {
  /// Created in [initState] rather than as a lazy `late final`, so it can never
  /// be constructed inside [dispose] (the trap that bit `_DetectionOutline` and
  /// `_ViewportProbe`).
  late final Timer _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(
      ScanDiagnosticsTokens.refreshInterval,
      (_) => setState(() {}),
    );
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  /// `frame: 720x1280 (0.563) / preview 0.750` — the analysis stream's upright
  /// dimensions and aspect, beside the preview's. They *should* match; when they
  /// don't, the detection outline is the thing that suffers, not the search ROI
  /// (whose cover mapping is self-correcting either way).
  String _describeFrame(CameraService camera, Orientation orientation) {
    final frame = camera.latestArtFrame;
    final controller = camera.preview.value;
    final preview = controller == null || !controller.value.isInitialized
        ? null
        : (orientation == Orientation.landscape
              ? controller.value.aspectRatio
              : 1 / controller.value.aspectRatio);
    if (frame == null) {
      return preview == null
          ? 'frame: -'
          : 'frame: -  / preview ${preview.toStringAsFixed(3)}';
    }
    final swap = frame.rotationDegrees == 90 || frame.rotationDegrees == 270;
    final width = swap ? frame.height : frame.width;
    final height = swap ? frame.width : frame.height;
    final aspect = height == 0 ? 0.0 : width / height;
    return 'frame: ${width}x$height (${aspect.toStringAsFixed(3)})'
        '${preview == null ? '' : ' / preview ${preview.toStringAsFixed(3)}'}';
  }

  @override
  Widget build(BuildContext context) {
    final reading = ref.watch(artReadingsProvider).value;
    final palette = AppPalette.dark;

    final camera = ref.read(cameraServiceProvider);
    final detector = ref.read(cardDetectorProvider);
    final status = reading?.status ?? ArtFrameStatus.noFrame;
    final lines = <String>[
      describeCameraHealth(camera.health),
      // The two aspects side by side. This is the one thing on screen that can
      // actually settle whether the analysis stream and the preview agree —
      // CameraX picks their resolutions independently, and the overlays are the
      // only thing that mismatch breaks. A single glance beats any host test.
      _describeFrame(camera, MediaQuery.orientationOf(context)),
      if (detector is IsolateCardDetector)
        'det: ${describeDetectorHealth(detector.health)}',
      // The frame's outcome, with the art-box result appended rather than given
      // a line of its own: they are one sentence about one frame, both are
      // short, and every line saved is a line of the readout that fits in the
      // band. The `noFrame`/`notDetected` branches stay whole — no crop was
      // assessed there, so there is no art box to report.
      switch (status) {
        ArtFrameStatus.noFrame => AppStrings.scanDiagnosticsNoFrame,
        ArtFrameStatus.notDetected => AppStrings.scanDiagnosticsNotDetected,
        ArtFrameStatus.lowQuality =>
          AppStrings.scanDiagnosticsLowQuality + _artBoxSuffix(reading),
        ArtFrameStatus.detected =>
          AppStrings.scanDiagnosticsDetected + _artBoxSuffix(reading),
      },
    ];
    // Shown for both statuses that assessed a crop, because the interesting
    // reading is the one *without* a `!`: a sharp, glare-free frame whose
    // nearest card is still far away means the crop is landing in the wrong
    // place, not that the photograph is bad. That is the single measurement
    // this overlay exists to make possible.
    if (reading != null &&
        (status == ArtFrameStatus.detected ||
            status == ArtFrameStatus.lowQuality)) {
      lines.add(
        describeFrameQuality(
          reading.quality,
          ref.watch(scanExposureOffsetProvider),
        ),
      );
    }
    if (reading != null && status == ArtFrameStatus.detected) {
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
        // Nearly opaque, not the 0.8 the other overlays use: the search-ROI
        // outline is drawn *under* this box (it is an earlier stack child) and
        // read straight through it, which is what "the debug text is covered by
        // the white rectangle" was describing.
        color: _cameraScrim.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      // The capture icon is *overlaid* on the readout rather than following it
      // in the column: as a row of its own it cost more than a line and a half
      // of a band that is a hard budget (see [_TopOverlays]). The lines are
      // short and left-aligned, so the top-right corner is free.
      child: Stack(
        children: [
          // Scrollable as the failsafe: the line count varies with what the
          // pipeline has to report, and the alternative on a cramped viewport
          // is an overflow stripe.
          SingleChildScrollView(
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
                      height: ScanDiagnosticsTokens.lineHeight,
                      fontFamily: ScanDiagnosticsTokens.fontFamily,
                    ),
                  ),
              ],
            ),
          ),
          const Positioned(top: 0, right: 0, child: _CaptureSampleButton()),
        ],
      ),
    );
  }

  /// The art-box outcome, appended to the frame-status line.
  static String _artBoxSuffix(ArtReading? reading) => reading == null
      ? ''
      : (reading.artBoxLocked
            ? AppStrings.scanDiagnosticsArtBoxLockedSuffix
            : AppStrings.scanDiagnosticsArtBoxFallbackSuffix);
}

/// Saves the pixels the pipeline last hashed, and hands them to the share sheet.
///
/// The point is not debugging convenience — it is that
/// `.claude/skills/scan-pipeline.md` forbids adding image preprocessing "before
/// you have real failure samples to test against", and there was previously no
/// way to obtain one: the rectified card lives for a few milliseconds inside a
/// detector isolate and is never written anywhere. A glare-blown Secret Rare
/// photographed by *this* phone on *this* table is the only honest input for
/// evaluating a fix, and clean YGOPRODeck renders cannot stand in for it.
class _CaptureSampleButton extends ConsumerStatefulWidget {
  const _CaptureSampleButton();

  @override
  ConsumerState<_CaptureSampleButton> createState() =>
      _CaptureSampleButtonState();
}

class _CaptureSampleButtonState extends ConsumerState<_CaptureSampleButton> {
  bool _busy = false;

  Future<void> _capture() async {
    setState(() => _busy = true);
    String message;
    List<String> paths = const [];
    try {
      final matcher = await ref.read(artMatcherProvider.future);
      final sample = matcher.lastSample;
      if (sample == null) {
        message = AppStrings.scanCaptureNothingMessage;
      } else {
        paths = await writeArtSample(sample);
        message = AppStrings.scanCaptureDoneMessage;
      }
    } catch (_) {
      message = AppStrings.scanCaptureFailedMessage;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    // App documents isn't browsable on Android, so sharing is the only way the
    // files reach a machine that can look at them — same route as the CSV
    // export.
    if (paths.isNotEmpty) {
      await SharePlus.instance.share(
        ShareParams(
          files: [for (final path in paths) XFile(path)],
          subject: AppStrings.scanCaptureSubject,
        ),
      );
    }
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    // An icon, not the old full-width `[ save this frame ]` row: every point it
    // takes is a diagnostics line pushed out of the band above the reticle. The
    // label survives as the tooltip and the semantic name.
    return Align(
      alignment: Alignment.centerRight,
      child: IconButton(
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        visualDensity: VisualDensity.compact,
        iconSize: ScanDiagnosticsTokens.captureIconSize,
        color: AppPalette.dark.accent,
        tooltip: AppStrings.scanCaptureButton,
        icon: const Icon(Icons.save_alt),
        onPressed: _busy ? null : _capture,
      ),
    );
  }
}

/// The one line of feedback while scanning — and the only thing on screen that
/// can explain a card the app is looking straight at but cannot name.
///
/// It used to switch on [ScanStatus] alone, which conflated four different frame
/// outcomes into `detecting` and so rendered **"Point at a card"** at a card
/// already centred, rectified and hashed. [ScanHint] carries that distinction;
/// see the enum for why it isn't a status.
class _StatusBanner extends ConsumerWidget {
  const _StatusBanner({required this.status, required this.hint});

  final ScanStatus status;
  final ScanHint hint;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // matched/candidates/readingCode/unknown/error render their own panels;
    // confirmed is transient.
    if (status != ScanStatus.detecting && status != ScanStatus.reading) {
      return const SizedBox.shrink();
    }
    final label = switch (hint) {
      ScanHint.blurry => AppStrings.scanBlurry,
      ScanHint.glare => AppStrings.scanGlare,
      ScanHint.identifying => AppStrings.scanIdentifying,
      ScanHint.unidentified => AppStrings.scanUnidentified,
      ScanHint.none when status == ScanStatus.reading => AppStrings.scanReading,
      ScanHint.none => AppStrings.scanDetecting,
    };
    // A spinner means "working on it". Blur/glare advice is the opposite —
    // nothing progresses until the user changes something — so it gets none.
    final busy =
        status == ScanStatus.reading || hint == ScanHint.identifying;
    final actionable = hint == ScanHint.unidentified;

    final banner = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: _cameraScrim.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
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
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppPalette.dark.onSurface),
                ),
              ),
            ],
          ),
          // The escape hatch. The ranked hits exist out to
          // `ArtMatchTuning.maxHammingDistance`, well past the automatic gate —
          // they simply were never offered, so a card the index knows but cannot
          // confidently place had no route into the review gate at all.
          if (actionable)
            TextButton(
              onPressed: ref
                  .read(scanControllerProvider.notifier)
                  .showBestGuesses,
              child: Text(
                AppStrings.scanShowGuessesButton,
                style: TextStyle(color: AppPalette.dark.accent),
              ),
            ),
        ],
      ),
    );
    // Bounded so a two-line hint wraps inside the overlay column rather than
    // stretching the banner across the whole preview.
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.8,
      ),
      child: banner,
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
                          // Say so when the app is guessing. Matches past
                          // `autoMatchMaxDistance` are shown rather than
                          // withheld, which is only defensible if the user can
                          // tell the difference — the picture above plus this
                          // line are how they check before confirming.
                          if (_isLowConfidence(state))
                            Padding(
                              padding: const EdgeInsets.only(
                                top: AppSpacing.xs,
                              ),
                              child: Text(
                                AppStrings.scanLowConfidence,
                                style: TextStyle(
                                  color: palette.accent,
                                  fontSize: ScanHelpTokens.lineFontSize,
                                ),
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
                // First, above the chips: its search field opens the keyboard,
                // which covers everything below it. Self-hides (and supplies its
                // own trailing gap) when the card has no known printings.
                _SetPicker(
                  passcode: card.passcode,
                  printingId: state.printingId,
                ),
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
                // An automatic artwork guess can be wrong, so always offer a way
                // off it — the escape hatch is what makes presenting a marginal
                // guess reasonable in the first place. Shown for every artwork
                // match; an OCR passcode match is exact and carries no
                // candidates, so it keeps the panel it always had.
                if (state.candidates.isNotEmpty)
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () {
                        // With alternatives, show them; the candidate panel ends
                        // in "search by name" anyway. With only this one, skip
                        // the middle step — a one-row "is it one of these?"
                        // listing the card just rejected is noise.
                        if (state.candidates.length > 1) {
                          controller.showCandidates();
                        } else {
                          controller.dismiss();
                          context.push(AppRoutes.addCard);
                        }
                      },
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

/// Whether the pending match is far enough out that the panel should hedge.
///
/// [ArtMatchTuning.autoMatchMaxDistance] no longer decides whether a card is
/// offered — [ArtMatchTuning.maxHammingDistance] does — so this is the whole of
/// what it decides now. Null distance means an exact OCR passcode match, which
/// never hedges.
bool _isLowConfidence(ScanState state) {
  final distance = state.matchedDistance;
  return distance != null && distance > ArtMatchTuning.autoMatchMaxDistance;
}

/// The set/expansion picker inside the review gate. The camera can't tell which
/// reprint is in hand — passcodes are rarity- and set-independent — so it is
/// chosen here, from the card's known printings, exactly like the manual add
/// flow's printing step. Defaults to "no specific set", which is what a scan
/// used to log unconditionally.
///
/// Hidden when the card has no known printings: the only option would then be
/// "no specific set", and a dead control on the fast path is worse than none.
///
/// It sits **above** the condition/edition/language chips, because its search
/// field raises the keyboard and everything below it would be covered. Its gap
/// is therefore *trailing* rather than leading, so the panel spaces correctly
/// whether it renders or collapses to nothing.
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
        const SizedBox(height: AppSpacing.md),
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

/// The failure panel for the artwork pipeline.
///
/// Both the camera and the bundled index reach the controller down the same
/// stream, so this discriminates rather than blaming the camera for everything:
/// a bad `assets/card_hashes.json` (the ROI/descriptor header guard) used to
/// read as *"the camera could not be started"*, with a Retry that could not
/// possibly fix it.
class _CameraErrorPanel extends ConsumerWidget {
  const _CameraErrorPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(scanControllerProvider.notifier);
    final isIndex = ScanController.isIndexError(
      ref.watch(scanControllerProvider).error,
    );
    return _BottomMessage(
      title: isIndex
          ? AppStrings.scanIndexErrorTitle
          : AppStrings.scanPermissionTitle,
      message: isIndex
          ? AppStrings.scanIndexErrorMessage
          : AppStrings.scanPermissionMessage,
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
