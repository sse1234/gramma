import 'package:flutter_test/flutter_test.dart';
import 'package:gramma/column_snap_physics.dart';

void main() {
  const stride = 448.0;

  test('snaps to the nearest column boundary', () {
    expect(ColumnSnapPhysics.snapTarget(0, stride, 0, 4000), 0);
    expect(ColumnSnapPhysics.snapTarget(200, stride, 0, 4000), 0);
    expect(ColumnSnapPhysics.snapTarget(230, stride, 0, 4000), stride);
    expect(ColumnSnapPhysics.snapTarget(900, stride, 0, 4000), 2 * stride);
  });

  test('never lands off-grid at the scroll end', () {
    // max extent between grid points: fall back to the last aligned column.
    const max = 3 * stride + 48;
    expect(ColumnSnapPhysics.snapTarget(max, stride, 0, max), 3 * stride);
    expect(
      ColumnSnapPhysics.snapTarget(max + 500, stride, 0, max),
      3 * stride,
    );
  });

  test('clamps to the start', () {
    expect(ColumnSnapPhysics.snapTarget(-300, stride, 0, 4000), 0);
  });

  test('the advance threshold decides when a swipe turns the column', () {
    // At the default (0.5, plain rounding) a gentle swipe snaps back …
    expect(ColumnSnapPhysics.columnsCrossed(100, stride, 0.5), 0);
    expect(ColumnSnapPhysics.columnsCrossed(230, stride, 0.5), 1);
    // … while a light setting turns on the same gentle swipe, both ways.
    expect(ColumnSnapPhysics.columnsCrossed(100, stride, 0.15), 1);
    expect(ColumnSnapPhysics.columnsCrossed(-100, stride, 0.15), -1);
    // Long flings still cross several columns.
    expect(ColumnSnapPhysics.columnsCrossed(3.4 * stride, stride, 0.5), 3);
    expect(ColumnSnapPhysics.columnsCrossed(3.6 * stride, stride, 0.5), 4);
    // Below the threshold nothing turns.
    expect(ColumnSnapPhysics.columnsCrossed(0.14 * stride, stride, 0.15), 0);
    expect(ColumnSnapPhysics.columnsCrossed(0, stride, 0.15), 0);
  });
}
