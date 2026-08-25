import 'package:flutter_test/flutter_test.dart';
import 'package:gramma/reader_pane.dart';
import 'package:gramma/src/rust/api/typeset.dart';

RunView _run(int verse) => RunView(
      text: 'w',
      x: 0,
      width: 100,
      verseNumber: false,
      noteMarker: false,
      headingLevel: 0,
      verse: verse,
    );

void main() {
  // A chapter with a section heading mid-way: text of verse 1, an empty
  // spacer line, the heading line (tagged with the following verse), and
  // text of verses 2-3 — the shape layout_verses emits since headings.
  final lines = [
    const LineView(runs: []), // leading spacer would never happen; edge case
    LineView(runs: [_run(1)]),
    const LineView(runs: []), // spacer before the section heading
    LineView(runs: [_run(2)]), // heading line, anchored to verse 2
    LineView(runs: [_run(2), _run(3)]),
  ];

  test('start lookup walks forward past spacer lines', () {
    expect(verseAtLineStart(lines, 2), 2,
        reason: 'a spacer defers to the next carrying line');
    expect(verseAtLineStart(lines, 0), 1);
    expect(verseAtLineStart(lines, 4), 2);
    expect(verseAtLineStart(lines, 99), 2, reason: 'clamped to last line');
  });

  test('end lookup walks backward past spacer lines', () {
    expect(verseAtLineEnd(lines, 2), 1,
        reason: 'a spacer defers to the previous carrying line — never the '
            'whole chapter');
    expect(verseAtLineEnd(lines, 4), 3);
    expect(verseAtLineEnd(lines, 0), null,
        reason: 'nothing before the first line');
    expect(verseAtLineEnd(lines, -5), null, reason: 'clamped to first line');
  });

  test('empty layouts yield no verse', () {
    expect(verseAtLineStart(const [], 0), null);
    expect(verseAtLineEnd(const [], 0), null);
  });
}
