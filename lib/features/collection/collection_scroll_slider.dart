import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/theme/tokens.dart';
import 'collection_scroll_slider_math.dart';

/// A drag-to-browse gutter down the right of a long collection.
///
/// **The gutter is its own column, not an overlay on the cards** (decided with
/// the user): `minifyFull` cells are 84pt wide and already carry a quantity
/// badge in one top corner and a selection check in the other, so a thumb
/// floating over the content would sit on both.
///
/// Takes a [builder] rather than a child, and that is what makes the whole thing
/// work: the scroll view lives *inside* this widget's subtree, so switching
/// between the standard list and either grid rebuilds only what is under the
/// builder while this [State] — and therefore the [ScrollController] — survives.
///
/// Must be given bounded height. On the collection screen it sits in the
/// existing `Expanded`, which is where the [Row]'s `Expanded` and the
/// [LayoutBuilder]'s track height both come from.
class CollectionScrollSlider extends StatefulWidget {
  const CollectionScrollSlider({
    required this.itemCount,
    required this.layoutKey,
    required this.labelForIndex,
    required this.builder,
    super.key,
  });

  final int itemCount;

  /// Changes whenever the scroll view under [builder] is a different kind of
  /// widget — the view mode. A remount discards the scroll *position*, so the
  /// slider restores the fraction rather than the pixels; see
  /// [_CollectionScrollSliderState.didUpdateWidget].
  final Object layoutKey;

  /// What the bubble says at a given item.
  final String Function(int index) labelForIndex;

  final Widget Function(BuildContext context, ScrollController controller)
  builder;

  @visibleForTesting
  static const Key thumbKey = Key('collection-scroll-slider-thumb');

  @visibleForTesting
  static const Key bubbleKey = Key('collection-scroll-slider-bubble');

  @override
  State<CollectionScrollSlider> createState() => _CollectionScrollSliderState();
}

class _CollectionScrollSliderState extends State<CollectionScrollSlider> {
  // Assigned in initState rather than a `late final` initializer: a `late final`
  // whose initializer never ran during build runs it inside `dispose()`, which
  // this project has been bitten by twice (see step 13's ticker and viewport
  // probe).
  late ScrollController _controller;

  /// Fed only from scroll notifications, never sampled off the position.
  /// `ScrollPosition.maxScrollExtent` asserts `hasContentDimensions`, so reading
  /// it before the first layout throws in debug — and the first build is exactly
  /// when the thumb wants to paint.
  late ValueNotifier<ScrollSliderMetrics?> _metrics;

  /// Null except while a drag is in progress, which is when the bubble shows.
  late ValueNotifier<double?> _dragFraction;

  /// Where inside the thumb the finger landed, so it doesn't jump on grab.
  double _grabOffset = 0;

  /// Carried across a view-mode remount, applied when metrics next arrive.
  double? _pendingFraction;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController();
    _metrics = ValueNotifier(null);
    _dragFraction = ValueNotifier(null);
  }

  @override
  void didUpdateWidget(CollectionScrollSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.layoutKey == widget.layoutKey) return;
    // A list and a grid are different widget types, so the whole scrollable is
    // remounted and attaches a fresh position at offset 0. Pixels are
    // meaningless across that change anyway — 110pt rows against grid rows of a
    // different height and column count — while the fraction is exactly what the
    // index mapping is linear in, so restoring it keeps the user on the same
    // card.
    final current = _metrics.value;
    _pendingFraction = current == null
        ? null
        : sliderFractionForOffset(
            offset: current.pixels,
            maxScrollExtent: current.maxScrollExtent,
          );
    _metrics.value = null;
  }

  @override
  void dispose() {
    _controller.dispose();
    _metrics.dispose();
    _dragFraction.dispose();
    super.dispose();
  }

  /// Records the newest metrics and, once, restores a fraction carried across a
  /// view-mode change.
  ///
  /// Safe to write notifiers and to call `jumpTo` from here: scroll
  /// notifications are dispatched after layout, not during it.
  void _onMetrics(ScrollMetrics metrics) {
    final next = (
      pixels: metrics.pixels,
      maxScrollExtent: metrics.maxScrollExtent,
      viewportDimension: metrics.viewportDimension,
    );
    _metrics.value = next;

    final pending = _pendingFraction;
    if (pending == null || next.maxScrollExtent <= 0) return;
    _pendingFraction = null;
    if (mounted && _controller.hasClients) {
      _controller.jumpTo(pending * next.maxScrollExtent);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reserved = collectionSliderReservesGutter(widget.itemCount);
    final scrollView = NotificationListener<ScrollMetricsNotification>(
      onNotification: (notification) {
        _onMetrics(notification.metrics);
        return false;
      },
      child: NotificationListener<ScrollNotification>(
        // The pair Flutter's own Scrollbar uses: the first reports content
        // dimensions changing, this one reports the user scrolling. Together
        // they are what keeps the thumb in sync when the list is dragged
        // normally, without the list itself ever rebuilding — the metrics land
        // in a notifier read only inside the gutter.
        onNotification: (notification) {
          _onMetrics(notification.metrics);
          return false;
        },
        child: widget.builder(context, _controller),
      ),
    );

    if (!reserved) return scrollView;

    return Stack(
      fit: StackFit.expand,
      children: [
        Row(
          children: [
            Expanded(child: scrollView),
            SizedBox(
              width: CollectionScrollSliderTokens.gutterWidth,
              child: _Gutter(
                metrics: _metrics,
                dragFraction: _dragFraction,
                onDragStart: _onDragStart,
                onDragUpdate: _onDragUpdate,
                onDragEnd: _endDrag,
              ),
            ),
          ],
        ),
        // Purely informational, and it overlays the cards — so it must never
        // take a hit from the list underneath it.
        IgnorePointer(
          child: _Bubble(
            metrics: _metrics,
            dragFraction: _dragFraction,
            labelForIndex: widget.labelForIndex,
            itemCount: widget.itemCount,
          ),
        ),
      ],
    );
  }

  /// Geometry of the current track, or null when there is nothing to drag.
  ({double trackExtent, double thumbExtent, double maxScrollExtent})? _track(
    double gutterHeight,
  ) {
    final metrics = _metrics.value;
    if (metrics == null || !collectionSliderIsScrollable(metrics)) return null;
    final trackExtent =
        gutterHeight - 2 * CollectionScrollSliderTokens.trackInset;
    if (trackExtent <= 0) return null;
    return (
      trackExtent: trackExtent,
      thumbExtent: sliderThumbExtent(
        trackExtent: trackExtent,
        viewportDimension: metrics.viewportDimension,
        contentExtent: metrics.maxScrollExtent + metrics.viewportDimension,
      ),
      maxScrollExtent: metrics.maxScrollExtent,
    );
  }

  void _onDragStart(double localDy, double gutterHeight) {
    final track = _track(gutterHeight);
    if (track == null) return;
    final metrics = _metrics.value!;
    final dy = localDy - CollectionScrollSliderTokens.trackInset;
    final thumbTop = sliderThumbTop(
      fraction: sliderFractionForOffset(
        offset: metrics.pixels,
        maxScrollExtent: track.maxScrollExtent,
      ),
      trackExtent: track.trackExtent,
      thumbExtent: track.thumbExtent,
    );
    // Grabbing the thumb keeps it under the finger; pressing bare track centres
    // it there instead, so the press itself is the jump.
    final onThumb = dy >= thumbTop && dy <= thumbTop + track.thumbExtent;
    _grabOffset = onThumb ? dy - thumbTop : track.thumbExtent / 2;
    _onDragUpdate(localDy, gutterHeight);
  }

  void _onDragUpdate(double localDy, double gutterHeight) {
    final track = _track(gutterHeight);
    if (track == null) return;
    final travel = (track.trackExtent - track.thumbExtent).clamp(
      0.0,
      double.infinity,
    );
    final thumbTop =
        (localDy - CollectionScrollSliderTokens.trackInset - _grabOffset).clamp(
          0.0,
          travel,
        );
    if (_controller.hasClients) {
      _controller.jumpTo(
        sliderOffsetForThumbTop(
          thumbTop: thumbTop,
          trackExtent: track.trackExtent,
          thumbExtent: track.thumbExtent,
          maxScrollExtent: track.maxScrollExtent,
        ),
      );
    }
    _dragFraction.value = travel <= 0 ? 0 : thumbTop / travel;
  }

  void _endDrag() => _dragFraction.value = null;
}

/// The rail and thumb, and the gesture target over both.
class _Gutter extends StatelessWidget {
  const _Gutter({
    required this.metrics,
    required this.dragFraction,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final ValueNotifier<ScrollSliderMetrics?> metrics;
  final ValueNotifier<double?> dragFraction;
  final void Function(double localDy, double gutterHeight) onDragStart;
  final void Function(double localDy, double gutterHeight) onDragUpdate;
  final VoidCallback onDragEnd;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        assert(
          constraints.hasBoundedHeight,
          'CollectionScrollSlider needs a bounded height: it derives the '
          'track from its own constraints.',
        );
        final height = constraints.maxHeight;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          // Vertical only. Registering horizontal drags here would put the
          // gutter into the arena against an edge-swipe back gesture.
          onVerticalDragStart: (details) =>
              onDragStart(details.localPosition.dy, height),
          onVerticalDragUpdate: (details) =>
              onDragUpdate(details.localPosition.dy, height),
          onVerticalDragEnd: (_) => onDragEnd(),
          onVerticalDragCancel: onDragEnd,
          child: Semantics(
            label: AppStrings.collectionScrollSliderLabel,
            child: ValueListenableBuilder<ScrollSliderMetrics?>(
              valueListenable: metrics,
              builder: (context, value, _) {
                // Before the first layout has reported dimensions there is
                // simply nothing to draw. The gutter is already reserved, so
                // nothing reflows when the thumb appears a frame later.
                if (value == null || !collectionSliderIsScrollable(value)) {
                  return const SizedBox.expand();
                }
                final trackExtent =
                    height - 2 * CollectionScrollSliderTokens.trackInset;
                if (trackExtent <= 0) return const SizedBox.expand();
                final thumbExtent = sliderThumbExtent(
                  trackExtent: trackExtent,
                  viewportDimension: value.viewportDimension,
                  contentExtent:
                      value.maxScrollExtent + value.viewportDimension,
                );
                final thumbTop = sliderThumbTop(
                  fraction: sliderFractionForOffset(
                    offset: value.pixels,
                    maxScrollExtent: value.maxScrollExtent,
                  ),
                  trackExtent: trackExtent,
                  thumbExtent: thumbExtent,
                );
                return Stack(
                  children: [
                    Positioned(
                      top: CollectionScrollSliderTokens.trackInset,
                      bottom: CollectionScrollSliderTokens.trackInset,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          width: CollectionScrollSliderTokens.railWidth,
                          decoration: BoxDecoration(
                            color: palette.divider,
                            borderRadius: BorderRadius.circular(
                              CollectionScrollSliderTokens.railWidth / 2,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: CollectionScrollSliderTokens.trackInset + thumbTop,
                      height: thumbExtent,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          key: CollectionScrollSlider.thumbKey,
                          width: CollectionScrollSliderTokens.thumbWidth,
                          decoration: BoxDecoration(
                            color: palette.accent,
                            borderRadius: BorderRadius.circular(
                              CollectionScrollSliderTokens.thumbWidth / 2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

/// The label beside the thumb, shown only while dragging.
class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.metrics,
    required this.dragFraction,
    required this.labelForIndex,
    required this.itemCount,
  });

  final ValueNotifier<ScrollSliderMetrics?> metrics;
  final ValueNotifier<double?> dragFraction;
  final String Function(int index) labelForIndex;
  final int itemCount;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return ValueListenableBuilder<double?>(
      valueListenable: dragFraction,
      builder: (context, fraction, _) {
        if (fraction == null || itemCount == 0) {
          return const SizedBox.shrink();
        }
        return LayoutBuilder(
          builder: (context, constraints) {
            final height = constraints.maxHeight;
            final trackExtent =
                height - 2 * CollectionScrollSliderTokens.trackInset;
            final value = metrics.value;
            if (trackExtent <= 0 || value == null) {
              return const SizedBox.shrink();
            }
            // A [Positioned] has to be a direct child of a [Stack], and the
            // [LayoutBuilder] above breaks that chain — hence this one rather
            // than positioning into the slider's outer stack.
            final thumbExtent = sliderThumbExtent(
              trackExtent: trackExtent,
              viewportDimension: value.viewportDimension,
              contentExtent: value.maxScrollExtent + value.viewportDimension,
            );
            final labelExtent =
                CollectionScrollSliderTokens.labelFontSize +
                2 * CollectionScrollSliderTokens.labelVerticalPadding;
            final top = sliderLabelTop(
              thumbTop: sliderThumbTop(
                fraction: fraction,
                trackExtent: trackExtent,
                thumbExtent: thumbExtent,
              ),
              thumbExtent: thumbExtent,
              labelExtent: labelExtent,
              trackExtent: trackExtent,
            );
            return Stack(
              children: [
                Positioned(
                  right:
                      CollectionScrollSliderTokens.gutterWidth +
                      CollectionScrollSliderTokens.labelGap,
                  top: CollectionScrollSliderTokens.trackInset + top,
                  child: Container(
                    key: CollectionScrollSlider.bubbleKey,
                    constraints: const BoxConstraints(
                      minWidth: CollectionScrollSliderTokens.labelMinWidth,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal:
                          CollectionScrollSliderTokens.labelHorizontalPadding,
                      vertical:
                          CollectionScrollSliderTokens.labelVerticalPadding,
                    ),
                    decoration: BoxDecoration(
                      color: palette.surfaceRaised,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(color: palette.accent),
                    ),
                    child: Text(
                      labelForIndex(
                        sliderIndexForFraction(fraction, itemCount),
                      ),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: palette.onSurface,
                        fontSize: CollectionScrollSliderTokens.labelFontSize,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
