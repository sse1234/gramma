import 'package:flutter/material.dart';

import 'src/rust/api/typeset.dart';

/// Paints a chapter laid out by gramma-core's Knuth–Plass engine.
///
/// The core computes line breaks and run positions in font units at the
/// canonical em measure; this widget only scales those units to the column's
/// pixel width — so the font size follows the column and the words per line
/// stay identical on every device.
class TypesetChapter extends StatelessWidget {
  const TypesetChapter({super.key, required this.layout, this.lineHeightEm = 1.5});

  final ChapterLayoutView layout;

  /// Line height as a multiple of the font size.
  final double lineHeightEm;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = constraints.maxWidth / layout.measureUnits;
        final fontSize = scale * layout.unitsPerEm;
        final lineHeight = fontSize * lineHeightEm;
        return Semantics(
          label: layout.plainText,
          child: CustomPaint(
            size: Size(constraints.maxWidth, layout.lines.length * lineHeight),
            painter: _ChapterPainter(
              layout: layout,
              scale: scale,
              fontSize: fontSize,
              lineHeight: lineHeight,
              textColor: scheme.onSurface,
              numberColor: scheme.primary,
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
  });

  final ChapterLayoutView layout;
  final double scale;
  final double fontSize;
  final double lineHeight;
  final Color textColor;
  final Color numberColor;

  @override
  void paint(Canvas canvas, Size size) {
    final textStyle = TextStyle(
      fontFamily: 'GentiumBookPlus',
      fontSize: fontSize,
      color: textColor,
    );
    final numberStyle = TextStyle(
      fontFamily: 'GentiumBookPlus',
      fontSize: fontSize * layout.numberScale,
      color: numberColor,
    );
    final markerStyle = numberStyle.copyWith(fontStyle: FontStyle.italic);
    final sectionStyle = textStyle.copyWith(fontWeight: FontWeight.w600);
    final subSectionStyle = textStyle.copyWith(fontStyle: FontStyle.italic);
    for (var i = 0; i < layout.lines.length; i++) {
      final y = i * lineHeight;
      for (final run in layout.lines[i].runs) {
        final painter = TextPainter(
          text: TextSpan(
            text: run.text,
            style: run.verseNumber
                ? numberStyle
                : run.noteMarker
                    ? markerStyle
                    : run.headingLevel == 1
                        ? sectionStyle
                        : run.headingLevel == 2
                            ? subSectionStyle
                            : textStyle,
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        // Tops align, so the smaller verse numbers sit raised.
        painter.paint(canvas, Offset(run.x * scale, y));
      }
    }
  }

  @override
  bool shouldRepaint(_ChapterPainter old) {
    return old.layout != layout ||
        old.scale != scale ||
        old.textColor != textColor ||
        old.numberColor != numberColor;
  }
}
