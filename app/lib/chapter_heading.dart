import 'package:flutter/material.dart';

import 'run_paint.dart';
import 'settings.dart';

/// A chapter's title above its text, painted with the same presence in
/// the vertical reader as the column reader's heading row: the text size
/// times the chapter-heading scale, the user's weight plus the chapter
/// heading's own (ADR 0031).
class ChapterHeading extends StatelessWidget {
  const ChapterHeading({
    super.key,
    required this.text,
    required this.fontSize,
    required this.lineHeight,
  });

  final String text;

  /// The body text size the heading scales from.
  final double fontSize;

  /// The body line height; the heading takes one and a half.
  final double lineHeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = SettingsScope.of(context);
    final style = settings.styleOf(TextElement.chapterHeading);
    return CustomPaint(
      size: Size(double.infinity, lineHeight * 1.5),
      painter: _HeadingPainter(
        text: text,
        style: TextStyle(
          fontFamily: settings.fontFamily,
          fontSize: fontSize * style.scale,
          fontStyle: style.italic ? FontStyle.italic : FontStyle.normal,
          color: theme.colorScheme.onSurface,
        ),
        baseline: lineHeight * 0.3,
        weightEm: settings.fontWeightFor(theme.brightness) + style.weightEm,
      ),
    );
  }
}

class _HeadingPainter extends CustomPainter {
  _HeadingPainter({
    required this.text,
    required this.style,
    required this.baseline,
    required this.weightEm,
  });

  final String text;
  final TextStyle style;
  final double baseline;
  final double weightEm;

  @override
  void paint(Canvas canvas, Size size) {
    paintRun(canvas, text, style, Offset(0, baseline), extraWeightEm: weightEm);
  }

  @override
  bool shouldRepaint(_HeadingPainter old) =>
      old.text != text ||
      old.style != style ||
      old.baseline != baseline ||
      old.weightEm != weightEm;
}
