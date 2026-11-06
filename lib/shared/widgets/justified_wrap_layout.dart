/// The arithmetic behind `JustifiedWrap`, kept free of Flutter so it can be
/// host-tested directly — a wrong number here does not crash, it just leaves a
/// row a few points short or pushes a chip off the edge, which is easy to miss
/// by eye and easy to pin with a test.
library;

/// Packs children of the given natural widths into runs, then stretches every
/// run to fill [maxWidth].
///
/// Children are taken in order and a run is closed as soon as the next child
/// would overflow it, exactly as `Wrap` does — so the rows hold the same chips
/// they would have held unstretched, and only their widths change. Each run's
/// leftover space is shared **equally** between its children rather than in
/// proportion to their width: equal shares keep short labels ("All", "NM")
/// from staying visibly smaller than their neighbours, which is most of what
/// makes a stretched row read as a grid.
///
/// Every run is stretched, the last one included — a final run of two chips
/// fills the width just as a full one does.
///
/// A child wider than [maxWidth] on its own gets a run to itself, clamped to
/// [maxWidth]; the chip then truncates its label rather than overflowing.
///
/// Returns one list per run, holding the assigned width of each child in that
/// run in order. Flattening the result gives one width per input, in input
/// order. An unbounded [maxWidth] (an unconstrained parent) puts everything in
/// one run at natural width, since there is nothing to fill.
List<List<double>> justifyRuns(
  List<double> naturalWidths, {
  required double maxWidth,
  required double spacing,
}) {
  if (naturalWidths.isEmpty) return const [];
  if (!maxWidth.isFinite) return [List.of(naturalWidths)];

  final runs = <List<double>>[];
  var run = <double>[];
  // The children's widths only; the gaps between them are added separately.
  var used = 0.0;

  void closeRun() {
    if (run.isEmpty) return;
    final gaps = spacing * (run.length - 1);
    final leftover = maxWidth - used - gaps;
    final share = leftover > 0 ? leftover / run.length : 0.0;
    runs.add([for (final width in run) width + share]);
    run = <double>[];
    used = 0.0;
  }

  for (final natural in naturalWidths) {
    final width = natural > maxWidth ? maxWidth : natural;
    // Adding a child to a run of n adds the child and one more gap: n gaps in
    // all, against the n - 1 the run already had.
    final needed = used + spacing * run.length + width;
    if (run.isNotEmpty && needed > maxWidth) closeRun();
    run.add(width);
    used += width;
  }
  closeRun();
  return runs;
}
