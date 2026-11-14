import 'dart:math' as math;
import 'dart:ui';

import 'annotations.dart';
import 'pens.dart';
import 'run_hit.dart';
import 'src/rust/api/typeset.dart';

/// A mark resolved for painting (ADR 0035): its pen, or — for a note
/// without a pen — the place of its icon: the end of the last word of
/// its end verse, as a line index and an x position in font units.
class MarkPaint {
  const MarkPaint({
    required this.mark,
    required this.pen,
    this.anchorLine,
    this.anchorX,
  });

  final NoteMark mark;

  /// Null for a note shown by its icon alone.
  final Pen? pen;
  final int? anchorLine;
  final double? anchorX;

  bool get iconOnly => pen == null;

  /// Resolves [marks] against a chapter's [layout]: pens by index, icon
  /// anchors by the last run of the end verse.
  static List<MarkPaint> resolve(
    Iterable<NoteMark> marks,
    ChapterLayoutView? layout,
  ) {
    final out = <MarkPaint>[];
    for (final mark in marks) {
      if (mark.colorIndex != Pens.none) {
        out.add(MarkPaint(mark: mark, pen: Pens.of(mark.colorIndex)));
        continue;
      }
      int? line;
      double? x;
      if (layout != null) {
        for (var i = 0; i < layout.lines.length; i++) {
          for (final run in layout.lines[i].runs) {
            if (run.verse == mark.verseEnd &&
                !run.verseNumber &&
                !run.noteMarker &&
                run.headingLevel == 0) {
              line = i;
              x = run.x + run.width;
            }
          }
        }
      }
      out.add(MarkPaint(mark: mark, pen: null, anchorLine: line, anchorX: x));
    }
    return out;
  }
}

/// The icon box of a note on [line] (its anchor line), top-aligned at
/// [y]: a small glyph in the leading above the end of the verse, so it
/// sits beside the text rather than on the next verse's number.
Rect noteIconRect(MarkPaint mark, double y, double scale, double fontSize) {
  final left = mark.anchorX! * scale + fontSize * 0.08;
  final size = fontSize * 0.42;
  return Rect.fromLTWH(left, y - fontSize * 0.2, size, size);
}

/// Thickness of a pen's underline.
double underlineThickness(double fontSize) =>
    (fontSize * 0.07).clamp(1.0, 4.0).toDouble();

/// Where a pen's underline starts below the top of its line (ADR 0035,
/// amended): under the text's [baseline] — the distance from the line's
/// top to where the letters stand — with a gap of 0.18 em, so the line
/// reads as drawn under the words and not through their feet. In lines
/// set tightly the gap gives way, down to 0.08 em, so the underline
/// keeps clear of the next line's ascenders too.
///
/// The underline used to sit at a fixed 1.1 em from the line's top,
/// which is the baseline itself in the Gentium faces and above it in
/// Literata.
double underlineOffset(double fontSize, double baseline, double lineHeight) {
  // From the baseline down to the next line's ascenders, which stand
  // about 0.72 em above their own baseline.
  final room = lineHeight - 0.72 * fontSize;
  final centered = (room - underlineThickness(fontSize)) / 2;
  final gap = math.max(0.08 * fontSize, math.min(0.18 * fontSize, centered));
  return baseline + gap;
}

/// Washes and underlines of [marks] behind one line at [y]. [baseline]
/// is the distance from the line's top to the text's baseline,
/// [lineHeight] the distance to the next line.
void paintMarkLine(
  Canvas canvas,
  LineView line,
  double y,
  double scale,
  double fontSize,
  Brightness brightness,
  List<MarkPaint> marks,
  String? paneModule, {
  required double baseline,
  required double lineHeight,
}) {
  for (final m in marks) {
    final pen = m.pen;
    if (pen == null) continue;
    bool covers(RunView run) => markCoversRun(m.mark, run, paneModule);
    for (final (start, end) in coveredSpans(line, covers)) {
      switch (pen.style) {
        case PenStyle.wash:
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTRB(
                start * scale - 2,
                y + fontSize * 0.08,
                end * scale + 2,
                y + fontSize * 1.26,
              ),
              const Radius.circular(3),
            ),
            Paint()..color = pen.wash(brightness),
          );
        case PenStyle.underline:
          final top = y + underlineOffset(fontSize, baseline, lineHeight);
          canvas.drawRect(
            Rect.fromLTRB(
              start * scale,
              top,
              end * scale,
              top + underlineThickness(fontSize),
            ),
            Paint()..color = pen.ink(brightness),
          );
      }
    }
  }
}

/// The note icons anchored on line [lineIndex], painted at [y] in
/// [color]: a small page with two text lines.
void paintNoteIcons(
  Canvas canvas,
  int lineIndex,
  double y,
  double scale,
  double fontSize,
  List<MarkPaint> marks,
  Color color,
  Color paper,
) {
  for (final m in marks) {
    if (!m.iconOnly || m.anchorLine != lineIndex) continue;
    final rect = noteIconRect(m, y, scale, fontSize);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(rect.width * 0.18)),
      Paint()..color = color,
    );
    final stroke = Paint()
      ..color = paper
      ..strokeWidth = (rect.height * 0.1).clamp(0.8, 2.0);
    for (final f in [0.38, 0.62]) {
      canvas.drawLine(
        Offset(rect.left + rect.width * 0.25, rect.top + rect.height * f),
        Offset(rect.right - rect.width * 0.25, rect.top + rect.height * f),
        stroke,
      );
    }
  }
}

/// The note whose icon's halo contains [position]; [lines] pairs each
/// line index with its top edge in pixels.
NoteMark? noteIconAt(
  Iterable<({int index, double top})> lines,
  double scale,
  double fontSize,
  List<MarkPaint> marks,
  Offset position,
) {
  NoteMark? best;
  var bestDistance = double.infinity;
  for (final entry in lines) {
    for (final m in marks) {
      if (!m.iconOnly || m.anchorLine != entry.index) continue;
      final rect = noteIconRect(m, entry.top, scale, fontSize);
      final pad = (markerPad * rect.width).clamp(markerMinHalo, 1e9);
      final halo = rect.inflate(pad);
      if (!halo.contains(position)) continue;
      final distance =
          (position.dx - rect.center.dx).abs() +
          (position.dy - rect.center.dy).abs();
      if (distance < bestDistance) {
        best = m.mark;
        bestDistance = distance;
      }
    }
  }
  return best;
}
