import 'dart:ui';

import 'src/rust/api/typeset.dart';

/// Pure hit-testing over run geometry (ADR 0016, refined in ADR 0019).
///
/// Words resolve by their exact painted box — a tap in the whitespace
/// between words hits nothing and falls through. Note markers, tiny
/// superscripts, get a forgiving halo instead: [markerPad] times their
/// glyph box added on every side, searched across neighboring lines,
/// with the nearest marker winning.

/// Halo around a note marker, as a multiple of its glyph box per side.
const markerPad = 1.5;

/// The run whose exact box contains [dx] on [line], or null.
RunView? runInLine(LineView line, double scale, double dx) {
  for (final run in line.runs) {
    if (dx >= run.x * scale && dx <= (run.x + run.width) * scale) {
      return run;
    }
  }
  return null;
}

/// Exact-box hit in stacked [lines] of height [lineHeight].
RunView? runAtOffset(
  List<LineView> lines,
  double scale,
  double lineHeight,
  Offset position,
) {
  if (position.dy < 0) return null;
  final index = position.dy ~/ lineHeight;
  if (index >= lines.length) return null;
  return runInLine(lines[index], scale, position.dx);
}

/// The note marker whose halo contains [position], nearest first.
/// [lines] pairs each line with its top edge in pixels; [markerHeight]
/// is the marker glyph size in pixels (markers paint top-aligned).
RunView? markerNear(
  Iterable<({LineView line, double top})> lines,
  double scale,
  double markerHeight,
  Offset position,
) {
  RunView? best;
  var bestDistance = double.infinity;
  for (final entry in lines) {
    for (final run in entry.line.runs) {
      if (!run.noteMarker) continue;
      final w = run.width * scale;
      final left = run.x * scale - markerPad * w;
      final right = run.x * scale + w + markerPad * w;
      final top = entry.top - markerPad * markerHeight;
      final bottom = entry.top + markerHeight + markerPad * markerHeight;
      if (position.dx < left ||
          position.dx > right ||
          position.dy < top ||
          position.dy > bottom) {
        continue;
      }
      final center = Offset(run.x * scale + w / 2, entry.top + markerHeight / 2);
      final distance =
          (position.dx - center.dx).abs() + (position.dy - center.dy).abs();
      if (distance < bestDistance) {
        best = run;
        bestDistance = distance;
      }
    }
  }
  return best;
}

/// A tapped word stripped for lookup: surrounding punctuation removed.
/// Returns null for runs that are not lookup material (markers, verse
/// numbers) or dissolve into punctuation entirely.
String? lookupWord(RunView run) {
  if (run.noteMarker || run.verseNumber) return null;
  final word = run.text.replaceAll(
      RegExp(r'^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$', unicode: true), '');
  return word.isEmpty ? null : word;
}
