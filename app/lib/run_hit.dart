import 'dart:ui';

import 'src/rust/api/typeset.dart';

/// Hit-testing over typeset runs (ADR 0016): the layout engine positions
/// every word as an object with exact bounds, so a tap resolves to the
/// run under it — the foundation for interactive text (note markers now;
/// word lookup for dictionaries and notes later).
///
/// [slop] widens each run horizontally (logical px) so small targets
/// like superscript note markers stay comfortably tappable.
RunView? runInLine(
  LineView line,
  double scale,
  double dx, {
  double slop = 0,
}) {
  RunView? best;
  var bestDistance = double.infinity;
  for (final run in line.runs) {
    final left = run.x * scale - slop;
    final right = (run.x + run.width) * scale + slop;
    if (dx < left || dx > right) continue;
    // Overlapping slop zones: the run whose true box is nearest wins.
    final distance = dx < run.x * scale
        ? run.x * scale - dx
        : dx > (run.x + run.width) * scale
            ? dx - (run.x + run.width) * scale
            : 0.0;
    if (distance < bestDistance) {
      best = run;
      bestDistance = distance;
    }
  }
  return best;
}

/// The run at [position] within a stack of lines painted at [lineHeight].
RunView? runAtOffset(
  List<LineView> lines,
  double scale,
  double lineHeight,
  Offset position, {
  double slop = 0,
}) {
  if (lineHeight <= 0) return null;
  final index = position.dy ~/ lineHeight;
  if (index < 0 || index >= lines.length) return null;
  return runInLine(lines[index], scale, position.dx, slop: slop);
}
