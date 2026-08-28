import 'package:flutter/material.dart';

import 'annotations.dart';
import 'run_hit.dart';
import 'run_paint.dart';
import 'settings.dart';
import 'src/rust/api/typeset.dart';

/// Paints a chapter laid out by gramma-core's Knuth–Plass engine.
///
/// The core computes line breaks and run positions in font units at the
/// canonical em measure; this widget only scales those units to the column's
/// pixel width — so the font size follows the column and the words per line
/// stay identical on every device.
class TypesetChapter extends StatelessWidget {
  const TypesetChapter({
    super.key,
    required this.layout,
    this.lineHeightEm = 1.5,
    this.onMarkerTap,
    this.onPlainTap,
    this.onSelectStart,
    this.onSelectExtend,
    this.onSelectEnd,
    this.onRunTap,
    this.marks = const [],
    this.paneModule,
    this.selection,
  });

  final ChapterLayoutView layout;

  /// Line height as a multiple of the font size.
  final double lineHeightEm;

  /// A tap on an inline note marker (ADR 0016); other taps fall through
  /// to [onPlainTap] (the reading-mode toggle).
  final void Function(RunView run)? onMarkerTap;
  final VoidCallback? onPlainTap;

  /// Selection gestures (ADR 0023): a steady long press anchors on the
  /// word under the finger; dragging in the same touch cycle extends;
  /// release finalizes. The pane owns the selection state.
  final ValueChanged<RunView>? onSelectStart;
  final ValueChanged<RunView>? onSelectExtend;
  final VoidCallback? onSelectEnd;

  /// A tap that resolved to a word run (marks open their note popup);
  /// taps hitting nothing still fall to [onPlainTap].
  final ValueChanged<RunView>? onRunTap;

  /// Color marks to wash behind the text, pre-resolved to theme colors.
  final List<(NoteMark, Color)> marks;
  final String? paneModule;
  final VerseSelection? selection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final settings = SettingsScope.of(context);
    final weightEm = settings.fontWeightFor(theme.brightness);
    final family = settings.fontFamily;
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = constraints.maxWidth / layout.measureUnits;
        final fontSize = scale * layout.unitsPerEm;
        final lineHeight = fontSize * lineHeightEm;
        return Semantics(
          label: layout.plainText,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) {
              final marker = markerNear(
                [
                  for (var i = 0; i < layout.lines.length; i++)
                    (line: layout.lines[i], top: i * lineHeight),
                ],
                scale,
                fontSize * layout.numberScale,
                details.localPosition,
              );
              if (marker != null && onMarkerTap != null) {
                onMarkerTap!(marker);
                return;
              }
              final run = runAtOffset(
                  layout.lines, scale, lineHeight, details.localPosition);
              if (run != null &&
                  !run.verseNumber &&
                  !run.noteMarker &&
                  onRunTap != null) {
                onRunTap!(run);
              } else {
                onPlainTap?.call();
              }
            },
            onLongPressStart: onSelectStart == null
                ? null
                : (details) {
                    final run = runAtOffset(layout.lines, scale, lineHeight,
                        details.localPosition);
                    if (run != null && !run.verseNumber && !run.noteMarker) {
                      onSelectStart!(run);
                    }
                  },
            onLongPressMoveUpdate: onSelectExtend == null
                ? null
                : (details) {
                    final run = runAtOffset(layout.lines, scale, lineHeight,
                        details.localPosition);
                    if (run != null && !run.verseNumber && !run.noteMarker) {
                      onSelectExtend!(run);
                    }
                  },
            onLongPressEnd:
                onSelectEnd == null ? null : (_) => onSelectEnd!(),
            child: CustomPaint(
              size:
                  Size(constraints.maxWidth, layout.lines.length * lineHeight),
              painter: _ChapterPainter(
                layout: layout,
                scale: scale,
                fontSize: fontSize,
                lineHeight: lineHeight,
                textColor: scheme.onSurface,
                numberColor: scheme.primary,
                weightEm: weightEm,
                family: family,
                marks: marks,
                paneModule: paneModule,
                selection: selection,
                selectionColor: scheme.primary.withValues(
                    alpha: theme.brightness == Brightness.light ? 0.22 : 0.34),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ChapterPainter extends CustomPainter {
  _ChapterPainter({
    required this.layout,
    required this.scale,
    required this.fontSize,
    required this.lineHeight,
    required this.textColor,
    required this.numberColor,
    required this.weightEm,
    required this.family,
    required this.marks,
    required this.paneModule,
    required this.selection,
    required this.selectionColor,
  });

  final ChapterLayoutView layout;
  final double scale;
  final double fontSize;
  final double lineHeight;
  final Color textColor;
  final Color numberColor;

  /// Extra stroke weight (user setting) in ems of the font size.
  final double weightEm;

  /// The reading typeface (user setting).
  final String family;

  final List<(NoteMark, Color)> marks;
  final String? paneModule;
  final VerseSelection? selection;
  final Color selectionColor;

  /// Washes behind one line: user marks, then the live selection.
  void _paintWashes(Canvas canvas, LineView line, double y) {
    void wash(bool Function(RunView) covers, Color color) {
      for (final (start, end) in coveredSpans(line, covers)) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(start * scale - 2, y + fontSize * 0.08,
                end * scale + 2, y + fontSize * 1.26),
            const Radius.circular(3),
          ),
          Paint()..color = color,
        );
      }
    }

    for (final (mark, color) in marks) {
      wash((run) => markCoversRun(mark, run, paneModule), color);
    }
    final sel = selection;
    if (sel != null) {
      wash(sel.coversRun, selectionColor);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final textStyle = TextStyle(
      fontFamily: family,
      fontSize: fontSize,
      color: textColor,
    );
    final numberStyle = TextStyle(
      fontFamily: family,
      fontSize: fontSize * layout.numberScale,
      color: numberColor,
    );
    final markerStyle = numberStyle.copyWith(fontStyle: FontStyle.italic);
    final subSectionStyle = textStyle.copyWith(fontStyle: FontStyle.italic);
    // Washes first, text second — in one pass a line's wash would
    // conceal the previous line's descenders.
    for (var i = 0; i < layout.lines.length; i++) {
      _paintWashes(canvas, layout.lines[i], i * lineHeight);
    }
    for (var i = 0; i < layout.lines.length; i++) {
      final y = i * lineHeight;
      for (final run in layout.lines[i].runs) {
        final style = run.verseNumber
            ? numberStyle
            : run.noteMarker
                ? markerStyle
                : run.headingLevel == 2
                    ? subSectionStyle
                    : textStyle;
        // Tops align, so the smaller verse numbers sit raised.
        paintRun(canvas, run.text, style, Offset(run.x * scale, y),
            extraWeightEm: run.headingLevel == 1
                ? weightEm + headingStrokeEm
                : weightEm);
      }
    }
  }

  @override
  bool shouldRepaint(_ChapterPainter old) {
    return old.layout != layout ||
        old.scale != scale ||
        old.textColor != textColor ||
        old.numberColor != numberColor ||
        old.weightEm != weightEm ||
        old.family != family ||
        !identical(old.marks, marks) ||
        old.selection != selection;
  }
}
