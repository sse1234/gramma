import 'package:flutter/material.dart';

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
  });

  final ChapterLayoutView layout;

  /// Line height as a multiple of the font size.
  final double lineHeightEm;

  /// A tap on an inline note marker (ADR 0016); other taps fall through
  /// to [onPlainTap] (the reading-mode toggle).
  final void Function(RunView run)? onMarkerTap;
  final VoidCallback? onPlainTap;

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
              final run = runAtOffset(
                  layout.lines, scale, lineHeight, details.localPosition,
                  slop: 6);
              if (run != null && run.noteMarker && onMarkerTap != null) {
                onMarkerTap!(run);
              } else {
                onPlainTap?.call();
              }
            },
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
        old.family != family;
  }
}
