import 'package:flutter_test/flutter_test.dart';
import 'package:gramma/column_plan.dart';
import 'package:gramma/column_scroller.dart';

void main() {
  ColumnPlan build({required int linesPerColumn, required int origin}) =>
      ColumnPlan(
        textLines: const [30, 30, 30],
        headingLines: 2,
        linesPerColumn: linesPerColumn,
        origin: origin,
      );

  ColumnPlan lay(ColumnScroller s, double stride) => s.layout(
    columns: 2,
    linesPerColumn: 10,
    columnWidth: 400,
    stride: stride,
    buildPlan: build,
  );

  // ADR 0034: a new column gap changes the stride and nothing else; the
  // view must land on the same column in the new stride.
  test('a stride change rebinds the controller at the anchor column', () {
    final s = ColumnScroller(onScrolled: () {});
    final plan = lay(s, 448);
    final first = s.controller!;
    final firstKey = s.params;
    s.anchorLine = plan.firstLineOfColumn(3);
    expect(lay(s, 448), same(s.plan), reason: 'nothing changed');
    expect(s.controller, same(first));

    final again = lay(s, 432);
    expect(s.controller, isNot(same(first)));
    expect(s.params, isNot(firstKey), reason: 'the list rebuilds');
    expect(
      s.controller!.initialScrollOffset,
      again.columnOfLine(s.anchorLine) * 432,
    );
    expect(s.stride, 432);
    expect(
      again.firstLineOfColumn(3),
      plan.firstLineOfColumn(3),
      reason: 'no re-chunk: the columns stand where they were',
    );
  });
}
