import 'dart:ui' show Brightness, Offset;

import 'package:flutter_test/flutter_test.dart';
import 'package:gramma/annotations.dart';
import 'package:gramma/mark_paint.dart';
import 'package:gramma/pens.dart';
import 'package:gramma/src/rust/api/typeset.dart';

RunView _run(
  int verse,
  double x,
  String text, {
  bool number = false,
  int heading = 0,
}) => RunView(
  style: 0,
  scale: 1.0,
  text: text,
  x: x,
  width: 10,
  verseNumber: number,
  noteMarker: false,
  headingLevel: heading,
  verse: verse,
  offset: 0,
);

NoteMark _mark(int color, {int verseEnd = 2}) => NoteMark(
  id: 'n1',
  module: 'FixDe',
  bookOsis: 'Gen',
  chapter: 1,
  verseStart: 1,
  verseEnd: verseEnd,
  startOffset: 0,
  endOffset: 1 << 30,
  colorIndex: color,
  text: 'Randnotiz',
  created: '',
);

void main() {
  // ADR 0035: pens are the reader's; marks reference them by index.
  test('a pen encodes and decodes, with strength clamped', () {
    final pen = Pen(hue: 200, strength: 0.5, style: PenStyle.underline);
    final back = Pen.fromJson(
      '{"v":1,"hue":200,"strength":0.5,"style":"underline"}',
    );
    expect(back, pen);
    expect(
      Pen.fromJson('{"hue":30,"strength":0.01}')!.strength,
      Pen.minStrength,
    );
    expect(Pen.fromJson('{"hue":390}')!.hue, 30);
    expect(Pen.fromJson('{"hue":30,"style":"neon"}')!.style, PenStyle.wash);
    expect(Pen.fromJson('garbage'), isNull);
  });

  test('the standard pens are the eight washes of ADR 0023', () {
    for (var i = 0; i < Pens.count; i++) {
      final pen = Pen.standard(i);
      expect(pen.hue, 15 + i * 45.0);
      expect(pen.strength, 1);
      expect(pen.style, PenStyle.wash);
      expect(pen.wash(Brightness.light).a, 1);
    }
    expect(
      Pen.standard(0).copyWith(strength: 0.4).wash(Brightness.dark).a,
      closeTo(0.4, 0.01),
      reason: 'strength is the pen\'s opacity over the paper',
    );
  });

  test('a note without a pen anchors on the last word of its end verse', () {
    final layout = ChapterLayoutView(
      lines: [
        LineView(
          runs: [
            _run(1, 0, '1', number: true),
            _run(1, 10, 'Im'),
            _run(1, 30, 'Anfang'),
          ],
          image: null,
          imageLines: 0,
        ),
        LineView(
          runs: [
            _run(2, 0, '2', number: true),
            _run(2, 10, 'Die'),
            _run(2, 30, 'Erde'),
          ],
          image: null,
          imageLines: 0,
        ),
        LineView(
          runs: [
            _run(2, 0, 'war'),
            _run(3, 20, '3', number: true),
            _run(3, 30, 'Und'),
          ],
          image: null,
          imageLines: 0,
        ),
      ],
      refs: const [],
      plainText: '',
      measureUnits: 1000,
      unitsPerEm: 100,
      numberScale: 0.65,
    );
    final painted = MarkPaint.resolve([_mark(Pens.none), _mark(3)], layout);
    expect(painted[0].iconOnly, isTrue);
    expect(painted[0].anchorLine, 2, reason: 'verse 2 ends on the third line');
    expect(painted[0].anchorX, 10, reason: 'after "war"');
    expect(painted[1].iconOnly, isFalse);
    expect(painted[1].pen, Pens.of(3));

    // The icon's halo is a finger-sized target around the glyph above
    // the end of the verse; a tap elsewhere hits nothing.
    final lines = [for (var i = 0; i < 3; i++) (index: i, top: i * 24.0)];
    final rect = noteIconRect(painted[0], 48, 1, 16);
    expect(
      noteIconAt(lines, 1, 16, painted, rect.center),
      same(painted[0].mark),
    );
    expect(noteIconAt(lines, 1, 16, painted, const Offset(400, 0)), isNull);
    // Painting such a mark washes nothing: no pen, no span.
    expect(
      MarkPaint.resolve([_mark(Pens.none)], null).single.anchorLine,
      isNull,
      reason: 'no layout yet, no anchor',
    );
  });
}
