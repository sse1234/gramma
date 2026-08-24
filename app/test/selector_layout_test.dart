import 'package:flutter_test/flutter_test.dart';
import 'package:gramma/reference_selector.dart';

void main() {
  test('brick rows alternate capacities', () {
    final rows = brickRows(List.generate(21, (i) => i), 7, 6);
    expect(rows.map((r) => r.length).toList(), [7, 6, 7, 1]);
    expect(rows.expand((r) => r).toList(), List.generate(21, (i) => i));
  });

  test('short groups stay in one row', () {
    expect(brickRows([1, 2, 3], 7, 6).length, 1);
  });

  test('exact fills leave no empty row', () {
    final rows = brickRows(List.generate(13, (i) => i), 7, 6);
    expect(rows.map((r) => r.length).toList(), [7, 6]);
  });
}
