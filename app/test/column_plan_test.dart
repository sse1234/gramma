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

  // Keep-with-next (ADR 0026): a heading group at a column's foot with
  // fewer than three content rows beneath moves to the next column.
  // Row kinds per text line: 0 = content, 1 = heading, 2 = blank.

  test('a section heading near the column foot moves over', () {
    // Global lines: 0,1 chapter heading rows; text rows at 2..10 with a
    // blank + heading at global 6,7. Column of 8 would leave the heading
    // with no content rows beneath — it breaks early instead.
    final p = ColumnPlan(
      textLines: const [8],
      headingLines: 2,
      linesPerColumn: 8,
      rowKinds: const [
        [0, 0, 0, 0, 2, 1, 0, 0],
      ],
    );
    expect(p.totalLines, 10);
    expect(p.firstLineOfColumn(1), 7, reason: 'break lands before the heading');
    expect(p.columnOfLine(6), 0, reason: 'the blank spacer stays behind');
    expect(p.columnOfLine(7), 1);
    expect(p.columnCount, 2);
    expect(p.linesInColumn(0), 7);
    expect(p.linesInColumn(1), 3);
  });

  test('a chapter title block near the column foot moves over', () {
    // Two chapters; the second block's title rows would land on the last
    // rows of column 0 — the whole block start moves to column 1.
    final p = ColumnPlan(
      textLines: const [5, 6],
      headingLines: 2,
      linesPerColumn: 8,
      rowKinds: const [
        [0, 0, 0, 0, 0],
        [0, 0, 0, 0, 0, 0],
      ],
    );
    expect(p.totalLines, 15);
    expect(p.firstLineOfColumn(1), 7, reason: 'the block heading moves whole');
    expect(p.columnCount, 2);
  });

  test('a heading with three content rows beneath stays', () {
    final p = ColumnPlan(
      textLines: const [7],
      headingLines: 0,
      linesPerColumn: 7,
      rowKinds: const [
        [0, 0, 2, 1, 0, 0, 0],
      ],
    );
    expect(p.columnCount, 1);
    expect(p.linesInColumn(0), 7);
  });

  test('a heading at the column top never pushes', () {
    // The group already heads its column; with only two content rows in
    // the tiny column there is nothing better than staying.
    final p = ColumnPlan(
      textLines: const [5],
      headingLines: 0,
      linesPerColumn: 3,
      rowKinds: const [
        [1, 0, 0, 0, 0],
      ],
    );
    expect(p.firstLineOfColumn(1), 3, reason: 'uniform break, no pushing');
    expect(p.columnCount, 2);
  });

  test('subheadings directly after a heading move as one group', () {
    // heading, subheading at global 5,6 with one content row before the
    // uniform break: the whole group moves.
    final p = ColumnPlan(
      textLines: const [10],
      headingLines: 0,
      linesPerColumn: 8,
      rowKinds: const [
        [0, 0, 0, 0, 2, 1, 1, 0, 0, 0],
      ],
    );
    expect(
      p.firstLineOfColumn(1),
      5,
      reason: 'group of two heading rows moves',
    );
    expect(p.columnCount, 2);
    expect(p.linesInColumn(1), 5);
  });

  test('without row kinds the plan stays uniform', () {
    final p = ColumnPlan(
      textLines: const [8],
      headingLines: 2,
      linesPerColumn: 8,
    );
    expect(p.firstLineOfColumn(1), 8);
    expect(p.columnCount, 2);
    expect(p.linesInColumn(0), 8);
    expect(p.linesInColumn(1), 2);
  });

  test('an origin line starts a column, earlier columns unchanged', () {
    // 20 lines, 6 per column: plain chunks are 0, 6, 12, 18. With the
    // origin at line 9 the column holding it ends early so line 9 heads a
    // column: 0, 6, 9, 15.
    final p = ColumnPlan(
      textLines: const [20],
      headingLines: 0,
      linesPerColumn: 6,
      origin: 9,
    );
    expect(p.columnCount, 4);
    expect(p.firstLineOfColumn(0), 0);
    expect(p.firstLineOfColumn(1), 6);
    expect(p.firstLineOfColumn(2), 9);
    expect(p.linesInColumn(1), 3);
    expect(p.columnOfLine(9), 2);
    expect(p.firstLineOfColumn(3), 15);
  });

  test('an origin at a natural boundary or outside changes nothing', () {
    final base = ColumnPlan(
      textLines: const [20],
      headingLines: 0,
      linesPerColumn: 6,
    );
    for (final origin in [0, 6, 12, 20, 40]) {
      final p = ColumnPlan(
        textLines: const [20],
        headingLines: 0,
        linesPerColumn: 6,
        origin: origin,
      );
      expect(p.columnCount, base.columnCount, reason: 'origin $origin');
      for (var c = 0; c < p.columnCount; c++) {
        expect(p.firstLineOfColumn(c), base.firstLineOfColumn(c));
      }
    }
  });

  test('an origin keeps a heading with its text', () {
    // Rows: content except a heading at row 7; origin 9. The column [6, 9)
    // would leave the heading at 7 with one content row beneath, so it
    // breaks before the heading: columns 0, 6, 7, 9, 15.
    final kinds = List<int>.filled(20, 0)..[7] = 1;
    final p = ColumnPlan(
      textLines: const [20],
      headingLines: 0,
      linesPerColumn: 6,
      rowKinds: [kinds],
      origin: 9,
    );
    expect(p.firstLineOfColumn(1), 6);
    expect(p.firstLineOfColumn(2), 7);
    expect(p.firstLineOfColumn(3), 9);
    expect(p.firstLineOfColumn(4), 15);
  });
}
