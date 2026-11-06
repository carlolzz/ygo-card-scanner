import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'justified_wrap_layout.dart';

/// A `Wrap` whose rows are stretched to the full width.
///
/// Children are packed into rows at their natural width, exactly as `Wrap`
/// packs them, and then each row's leftover space is shared out between its
/// children (see [justifyRuns]) — so a row holding three short chips reads as
/// three equal-ish columns across the sheet instead of a cluster on the left.
/// The last row is stretched too.
///
/// Children must lay out at whatever width they are given, and look right
/// doing so: a chip has to centre its label, or the extra width lands as
/// empty space on one side. `LabeledChoiceChip(expand: true)` does that.
///
/// Natural widths come from each child's max intrinsic width, which is why a
/// child that *fills* when given room (a `Center`-wrapped label) still packs
/// at the width of its content.
class JustifiedWrap extends MultiChildRenderObjectWidget {
  const JustifiedWrap({
    super.key,
    this.spacing = 0,
    this.runSpacing = 0,
    super.children,
  });

  /// Horizontal gap between children in one row.
  final double spacing;

  /// Vertical gap between rows.
  final double runSpacing;

  @override
  RenderJustifiedWrap createRenderObject(BuildContext context) =>
      RenderJustifiedWrap(spacing, runSpacing);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderJustifiedWrap renderObject,
  ) {
    renderObject
      ..spacing = spacing
      ..runSpacing = runSpacing;
  }
}

class _JustifiedWrapParentData extends ContainerBoxParentData<RenderBox> {}

class RenderJustifiedWrap extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _JustifiedWrapParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _JustifiedWrapParentData> {
  RenderJustifiedWrap(this._spacing, this._runSpacing);

  double _spacing;
  double get spacing => _spacing;
  set spacing(double value) {
    if (value == _spacing) return;
    _spacing = value;
    markNeedsLayout();
  }

  double _runSpacing;
  double get runSpacing => _runSpacing;
  set runSpacing(double value) {
    if (value == _runSpacing) return;
    _runSpacing = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _JustifiedWrapParentData) {
      child.parentData = _JustifiedWrapParentData();
    }
  }

  List<RenderBox> get _children {
    final children = <RenderBox>[];
    var child = firstChild;
    while (child != null) {
      children.add(child);
      child = childAfter(child);
    }
    return children;
  }

  /// Lays out (or, for a dry layout, measures) every child and returns the
  /// overall size. [place] is given each child's offset once it is known; a
  /// dry layout passes null and positions nothing.
  Size _layout(
    BoxConstraints constraints, {
    required Size Function(RenderBox child, BoxConstraints constraints) sizeOf,
    void Function(RenderBox child, Offset offset)? place,
  }) {
    final children = _children;
    if (children.isEmpty) return constraints.smallest;

    final naturals = [
      for (final child in children) child.getMaxIntrinsicWidth(double.infinity),
    ];
    final runs = justifyRuns(
      naturals,
      maxWidth: constraints.maxWidth,
      spacing: spacing,
    );

    var index = 0;
    var y = 0.0;
    var widest = 0.0;
    for (final (runIndex, run) in runs.indexed) {
      if (runIndex > 0) y += runSpacing;
      final sizes = <Size>[];
      for (final width in run) {
        sizes.add(
          sizeOf(
            children[index + sizes.length],
            BoxConstraints.tightFor(width: width),
          ),
        );
      }
      final runHeight = sizes.fold(0.0, (h, s) => math.max(h, s.height));
      var x = 0.0;
      for (final (i, size) in sizes.indexed) {
        if (i > 0) x += spacing;
        // Vertically centred in the row, so a chip that wraps to two lines
        // does not leave its neighbours hanging from the top.
        place?.call(
          children[index + i],
          Offset(x, y + (runHeight - size.height) / 2),
        );
        x += size.width;
      }
      widest = math.max(widest, x);
      y += runHeight;
      index += run.length;
    }

    final width = constraints.maxWidth.isFinite ? constraints.maxWidth : widest;
    return constraints.constrain(Size(width, y));
  }

  @override
  void performLayout() {
    size = _layout(
      constraints,
      sizeOf: (child, childConstraints) {
        child.layout(childConstraints, parentUsesSize: true);
        return child.size;
      },
      place: (child, offset) =>
          (child.parentData! as _JustifiedWrapParentData).offset = offset,
    );
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) => _layout(
    constraints,
    sizeOf: (child, childConstraints) => child.getDryLayout(childConstraints),
  );

  @override
  double computeMinIntrinsicWidth(double height) => _children.fold(
    0.0,
    (widest, child) => math.max(widest, child.getMinIntrinsicWidth(height)),
  );

  @override
  double computeMaxIntrinsicWidth(double height) {
    final children = _children;
    if (children.isEmpty) return 0;
    final total = children.fold(
      0.0,
      (sum, child) => sum + child.getMaxIntrinsicWidth(height),
    );
    return total + spacing * (children.length - 1);
  }

  @override
  double computeMinIntrinsicHeight(double width) =>
      getDryLayout(BoxConstraints(maxWidth: width)).height;

  @override
  double computeMaxIntrinsicHeight(double width) =>
      computeMinIntrinsicHeight(width);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);
}
