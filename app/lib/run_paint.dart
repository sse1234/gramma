import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Impeller (iOS, and Android when it lands there) rasterizes glyphs
/// visibly lighter than the desktop renderer's antialiasing; a hairline
/// stroke pass over the fill restores the stem weight so the page reads
/// the same on every platform. Width in ems of the run's font size.
const strokeDarkenEm = 0.022;

final bool _strokeDarken = !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android);

/// Paints one text run at [offset], with the platform darkening pass.
void paintRun(Canvas canvas, String text, TextStyle style, Offset offset) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
  )..layout();
  painter.paint(canvas, offset);
  final color = style.color;
  if (!_strokeDarken || color == null) return;
  final stroke = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontFamily: style.fontFamily,
        fontSize: style.fontSize,
        fontWeight: style.fontWeight,
        fontStyle: style.fontStyle,
        foreground: Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = (style.fontSize ?? 14) * strokeDarkenEm
          ..color = color,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  stroke.paint(canvas, offset);
}
