import 'package:flutter/widgets.dart';

/// Scroll physics for the horizontal column reader: flings run their
/// natural ballistic course, then settle on a column boundary with a
/// spring, so no column is left partially visible.
class ColumnSnapPhysics extends ScrollPhysics {
  const ColumnSnapPhysics({
    required this.stride,
    this.advance = defaultAdvance,
    super.parent,
  });

  /// Column width plus gutter — the scroll distance of one column.
  final double stride;

  /// Fraction of a column a swipe's natural travel must cover to count as
  /// a column turn (the user-facing "turn effort"). 0.5 is plain
  /// round-to-nearest; lower values let gentler swipes advance.
  final double advance;

  static const defaultAdvance = 0.5;

  @override
  ColumnSnapPhysics applyTo(ScrollPhysics? ancestor) => ColumnSnapPhysics(
      stride: stride, advance: advance, parent: buildParent(ancestor));

  /// Whole columns a natural scroll of [delta] pixels turns, requiring
  /// [advance] of a column beyond each boundary; signed like [delta].
  static int columnsCrossed(double delta, double stride, double advance) {
    if (stride <= 0) return 0;
    final travelled = delta.abs() / stride - advance;
    if (travelled < 0) return 0;
    return (travelled.floor() + 1) * (delta < 0 ? -1 : 1);
  }

  /// The grid-aligned landing position for a scroll that would naturally
  /// end at [naturalEnd]. Targets beyond the last full alignment fall back
  /// to the last aligned column rather than the off-grid maximum, so the
  /// leftmost visible column stays whole.
  static double snapTarget(
    double naturalEnd,
    double stride,
    double minExtent,
    double maxExtent,
  ) {
    var target = (naturalEnd / stride).roundToDouble() * stride;
    if (target > maxExtent) {
      target = (maxExtent / stride).floorToDouble() * stride;
    }
    if (target < minExtent) target = minExtent;
    return target;
  }

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    if (position.outOfRange) {
      return super.createBallisticSimulation(position, velocity);
    }
    final tolerance = toleranceFor(position);
    final natural = super.createBallisticSimulation(position, velocity);
    final naturalEnd = natural?.x(10.0) ?? position.pixels;
    // Turn as many columns as the natural travel earns past the advance
    // threshold, measured from the current aligned column.
    final base = snapTarget(
      position.pixels,
      stride,
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    final crossed =
        columnsCrossed(naturalEnd - position.pixels, stride, advance);
    final target = snapTarget(
      base + crossed * stride,
      stride,
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((target - position.pixels).abs() < tolerance.distance &&
        velocity.abs() < tolerance.velocity) {
      return null;
    }
    return ScrollSpringSimulation(
      spring,
      position.pixels,
      target,
      velocity,
      tolerance: tolerance,
    );
  }

  @override
  bool get allowImplicitScrolling => false;
}
