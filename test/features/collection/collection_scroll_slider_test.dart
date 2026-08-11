import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygo_scanner/core/theme/tokens.dart';
import 'package:ygo_scanner/features/collection/collection_scroll_slider.dart';
import 'package:ygo_scanner/models/collection_view_mode.dart';

/// The slider is exercised directly over a synthetic list rather than through
/// the collection screen, deliberately: that screen resolves providers through
/// the `sqflite_common_ffi` isolate and so has to run inside `tester.runAsync`,
/// where gesture timing is unreliable. Nothing here touches a database, so
/// drags behave normally.
void main() {
  const rowHeight = 60.0;

  /// Mirrors the collection screen's own shape: the standard mode is a
  /// `ListView` and the minified ones are `GridView`s, so switching really does
  /// remount the scrollable — which is the situation the position restore
  /// exists for, and a harness that always built a list would test nothing.
  Widget harness({
    required int itemCount,
    CollectionViewMode viewMode = CollectionViewMode.standard,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: CollectionScrollSlider(
          itemCount: itemCount,
          layoutKey: viewMode,
          labelForIndex: (index) => 'item $index',
          builder: (context, controller) => viewMode.isGrid
              ? GridView.builder(
                  controller: controller,
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                      ),
                  itemCount: itemCount,
                  itemBuilder: (context, index) => Text('cell $index'),
                )
              : ListView.builder(
                  controller: controller,
                  itemCount: itemCount,
                  itemBuilder: (context, index) => SizedBox(
                    height: rowHeight,
                    child: Text('row $index'),
                  ),
                ),
        ),
      ),
    );
  }

  /// The metrics that place the thumb arrive on a microtask after the first
  /// layout, so one extra pump is needed before it exists.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
  }

  ScrollController controllerOf(WidgetTester tester) {
    final grid = find.byType(GridView);
    if (grid.evaluate().isNotEmpty) {
      return tester.widget<GridView>(grid).controller!;
    }
    return tester.widget<ListView>(find.byType(ListView)).controller!;
  }


  testWidgets('a short collection gets no gutter at all', (tester) async {
    await tester.pumpWidget(
      harness(itemCount: CollectionScrollSliderTokens.minItems - 1),
    );
    await settle(tester);

    // No thumb, and — the part that matters for every existing collection test
    // — no reserved column narrowing the content.
    expect(find.byKey(CollectionScrollSlider.thumbKey), findsNothing);
    expect(
      tester.getSize(find.byType(ListView)).width,
      tester.getSize(find.byType(CollectionScrollSlider)).width,
    );
  });

  testWidgets('a long collection reserves the gutter and shows a thumb', (
    tester,
  ) async {
    await tester.pumpWidget(harness(itemCount: 200));
    await settle(tester);

    expect(find.byKey(CollectionScrollSlider.thumbKey), findsOneWidget);
    // The gutter is taken out of the content's width rather than painted over
    // it, so nothing sits under the thumb.
    expect(
      tester.getSize(find.byType(ListView)).width,
      tester.getSize(find.byType(CollectionScrollSlider)).width -
          CollectionScrollSliderTokens.gutterWidth,
    );
  });

  testWidgets('dragging the thumb scrolls the list', (tester) async {
    await tester.pumpWidget(harness(itemCount: 200));
    await settle(tester);

    final controller = controllerOf(tester);
    expect(controller.offset, 0);

    await tester.drag(
      find.byKey(CollectionScrollSlider.thumbKey),
      const Offset(0, 200),
    );
    await settle(tester);

    expect(controller.offset, greaterThan(0));
  });

  testWidgets('the thumb follows the list when it is scrolled normally', (
    tester,
  ) async {
    await tester.pumpWidget(harness(itemCount: 200));
    await settle(tester);

    final before = tester.getTopLeft(
      find.byKey(CollectionScrollSlider.thumbKey),
    );

    controllerOf(tester).jumpTo(3000);
    await settle(tester);

    final after = tester.getTopLeft(
      find.byKey(CollectionScrollSlider.thumbKey),
    );
    expect(
      after.dy,
      greaterThan(before.dy),
      reason: 'a scroll notification has to move the thumb, or the two '
          'disagree about where the user is',
    );
  });

  testWidgets('the bubble appears only while dragging, naming the position', (
    tester,
  ) async {
    await tester.pumpWidget(harness(itemCount: 200));
    await settle(tester);

    expect(find.byKey(CollectionScrollSlider.bubbleKey), findsNothing);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(CollectionScrollSlider.thumbKey)),
    );
    await gesture.moveBy(const Offset(0, 100));
    await settle(tester);

    expect(find.byKey(CollectionScrollSlider.bubbleKey), findsOneWidget);

    await gesture.up();
    await settle(tester);

    expect(find.byKey(CollectionScrollSlider.bubbleKey), findsNothing);
  });

  // A list and a grid are different widget types, so switching remounts the
  // scrollable and it attaches a fresh position at offset 0. Pixels are
  // meaningless across that change; the fraction is what keeps the user on the
  // same card.
  testWidgets('a view-mode change keeps the reading position', (tester) async {
    await tester.pumpWidget(harness(itemCount: 200));
    await settle(tester);

    controllerOf(tester).jumpTo(3000);
    await settle(tester);

    await tester.pumpWidget(
      harness(itemCount: 200, viewMode: CollectionViewMode.minifyFull),
    );
    await settle(tester);
    // One more: the restore is applied from the first metrics notification the
    // remounted sliver produces.
    await settle(tester);

    expect(
      controllerOf(tester).offset,
      greaterThan(0),
      reason: 'the scroll position is restored by fraction after a remount',
    );
  });

  testWidgets('a gutter whose content still fits paints no thumb', (
    tester,
  ) async {
    // Above the item threshold, so the gutter is reserved — but on a viewport
    // tall enough to hold everything, so there is nothing to scroll. The
    // reservation is by item count on purpose (it cannot depend on layout), and
    // the painting gate is what covers this case.
    tester.view.physicalSize = const Size(800, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      harness(itemCount: CollectionScrollSliderTokens.minItems),
    );
    await settle(tester);

    expect(find.byKey(CollectionScrollSlider.thumbKey), findsNothing);
  });
}
