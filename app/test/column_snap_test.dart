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
}
