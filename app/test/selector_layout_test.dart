import 'package:flutter_test/flutter_test.dart';
import 'package:gramma/reference_selector.dart';

void main() {
  test('rows chunk uniformly and preserve order', () {
    final rows = chunkRows(List.generate(21, (i) => i), 7);
    expect(rows.map((r) => r.length).toList(), [7, 7, 7]);
    expect(rows.expand((r) => r).toList(), List.generate(21, (i) => i));
  });

  test('short groups stay in one row', () {
    expect(chunkRows([1, 2, 3], 7).length, 1);
  });

  test('remainders form a last partial row', () {
    expect(chunkRows(List.generate(12, (i) => i), 5).map((r) => r.length),
        [5, 5, 2]);
  });
}
