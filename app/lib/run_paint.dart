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

/// Laid-out painters keyed by text and the style facets the painters use.
/// A chapter entering the viewport paints ~1500 runs in one frame; most
/// are words already shaped before, so the cache turns that frame from
/// thousands of text layouts into map lookups.
typedef _RunKey = (String, double?, int?, FontWeight?, FontStyle?, bool);
final Map<_RunKey, TextPainter> _painters = {};
const _painterCacheLimit = 8000;

TextPainter _layoutPainter(String text, TextStyle style, {required bool stroke}) {
  final key = (
    text,
    style.fontSize,
    style.color?.toARGB32(),
    style.fontWeight,
    style.fontStyle,
    stroke,
  );
  final cached = _painters.remove(key);
  if (cached != null) {
    _painters[key] = cached; // refresh LRU order
    return cached;
  }
  final effective = stroke
      ? TextStyle(
          fontFamily: style.fontFamily,
          fontSize: style.fontSize,
          fontWeight: style.fontWeight,
          fontStyle: style.fontStyle,
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = (style.fontSize ?? 14) * strokeDarkenEm
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

/// Paints one text run at [offset], with the platform darkening pass.
void paintRun(Canvas canvas, String text, TextStyle style, Offset offset) {
  _layoutPainter(text, style, stroke: false).paint(canvas, offset);
  if (_strokeDarken && style.color != null) {
    _layoutPainter(text, style, stroke: true).paint(canvas, offset);
  }
}
