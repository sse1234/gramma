import 'package:flutter/widgets.dart';

/// Scroll physics for the horizontal column reader: flings run their
/// natural ballistic course, then settle on a column boundary with a
/// spring, so no column is left partially visible.
class ColumnSnapPhysics extends ScrollPhysics {
  const ColumnSnapPhysics({required this.stride, super.parent});

  /// Column width plus gutter — the scroll distance of one column.
  final double stride;

  @override
  ColumnSnapPhysics applyTo(ScrollPhysics? ancestor) =>
      ColumnSnapPhysics(stride: stride, parent: buildParent(ancestor));

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
    final target = snapTarget(
      naturalEnd,
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
