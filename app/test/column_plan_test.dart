import 'package:flutter_test/flutter_test.dart';
import 'package:gramma/column_plan.dart';

void main() {
  // Two chapters of 3 and 5 text lines, 2 heading lines each, 4 lines per
  // column: blocks are [0..5) and [5..12), total 12 lines, 3 columns.
  final plan = ColumnPlan(
    textLines: const [3, 5],
    headingLines: 2,
    linesPerColumn: 4,
  );

  test('computes totals and column count', () {
    expect(plan.totalLines, 12);
    expect(plan.columnCount, 3);
  });

  test('locates heading and text lines within blocks', () {
    expect(plan.locate(0), (chapter: 0, local: 0));
    expect(plan.locate(1), (chapter: 0, local: 1));
    expect(plan.locate(2), (chapter: 0, local: 2));
    expect(plan.locate(4), (chapter: 0, local: 4));
    expect(plan.locate(5), (chapter: 1, local: 0));
    expect(plan.locate(11), (chapter: 1, local: 6));
    expect(plan.locate(12), isNull);
  });

  test('maps lines to columns and back', () {
    expect(plan.columnOfLine(0), 0);
    expect(plan.columnOfLine(3), 0);
    expect(plan.columnOfLine(4), 1);
    expect(plan.columnOfLine(11), 2);
    expect(plan.firstLineOfColumn(2), 8);
  });

  test('reports chapter block starts', () {
    expect(plan.blockStart(0), 0);
    expect(plan.blockStart(1), 5);
  });

  test('finds the chapter containing a line', () {
    expect(plan.chapterOfLine(0), 0);
    expect(plan.chapterOfLine(4), 0);
    expect(plan.chapterOfLine(5), 1);
    expect(plan.chapterOfLine(11), 1);
  });

  test('handles an empty module', () {
    final empty = ColumnPlan(
      textLines: const [],
      headingLines: 2,
      linesPerColumn: 4,
    );
    expect(empty.totalLines, 0);
    expect(empty.columnCount, 0);
    expect(empty.locate(0), isNull);
  });

  test('last column may be partial', () {
    final p = ColumnPlan(
      textLines: const [1],
      headingLines: 2,
      linesPerColumn: 4,
    );
    expect(p.totalLines, 3);
    expect(p.columnCount, 1);
  });
}
