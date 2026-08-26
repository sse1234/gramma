import 'package:flutter/painting.dart';

/// Laid-out painters keyed by text and the style facets the painters use.
/// A chapter entering the viewport paints ~1500 runs in one frame; most
/// are words already shaped before, so the cache turns that frame from
/// thousands of text layouts into map lookups.
typedef _RunKey = (String, double?, int?, FontWeight?, FontStyle?, double);
final Map<_RunKey, TextPainter> _painters = {};
const _painterCacheLimit = 8000;

TextPainter _layoutPainter(String text, TextStyle style, double strokeEm) {
  final key = (
    text,
    style.fontSize,
    style.color?.toARGB32(),
    style.fontWeight,
    style.fontStyle,
    strokeEm,
  );
  final cached = _painters.remove(key);
  if (cached != null) {
    _painters[key] = cached; // refresh LRU order
    return cached;
  }
  final effective = strokeEm > 0
      ? TextStyle(
          fontFamily: style.fontFamily,
          fontSize: style.fontSize,
          fontWeight: style.fontWeight,
          fontStyle: style.fontStyle,
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = (style.fontSize ?? 14) * strokeEm
            ..color = style.color!,
        )
      : style;
  final painter = TextPainter(
    text: TextSpan(text: text, style: effective),
    textDirection: TextDirection.ltr,
  )..layout();
  _painters[key] = painter;
  if (_painters.length > _painterCacheLimit) {
    _painters.remove(_painters.keys.first)?.dispose();
  }
  return painter;
}

/// Paints one text run at [offset]. [extraWeightEm] adds stroke weight in
/// ems of the font size — the user's per-brightness font weight setting,
/// the only source of added weight: 0 paints the font exactly as
/// designed, identical to any Text widget. (Impeller's lighter
/// rasterization on mobile is compensated by the setting's platform
/// default, not by hidden magic here.)
void paintRun(
  Canvas canvas,
  String text,
  TextStyle style,
  Offset offset, {
  double extraWeightEm = 0,
}) {
  _layoutPainter(text, style, 0).paint(canvas, offset);
  if (extraWeightEm > 0 && style.color != null) {
    _layoutPainter(text, style, extraWeightEm).paint(canvas, offset);
  }
}
