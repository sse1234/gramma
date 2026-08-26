import 'package:flutter/material.dart';

import 'run_hit.dart';
import 'run_paint.dart';
import 'settings.dart';
import 'src/rust/api/typeset.dart';

/// Paints one typeset commentary entry (ADR 0018): the same Knuth–Plass
/// lines and painting path as the Bible text, at the pane's own measure.
/// Runs carrying a link index are tappable references (ADR 0016 hit
/// paths); other taps fall through to [onPlainTap].
class TypesetProse extends StatelessWidget {
  const TypesetProse({
    super.key,
    required this.layout,
    required this.fontSize,
    this.lineHeightEm = 1.5,
    this.onLinkTap,
    this.onPlainTap,
  });

  final CommentLayoutView layout;

  /// Text size in logical pixels; the measure was computed from it.
  final double fontSize;
  final double lineHeightEm;

  /// A tap on a reference run, with the resolved OSIS target.
  final ValueChanged<String>? onLinkTap;
  final VoidCallback? onPlainTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final settings = SettingsScope.of(context);
    final scale = fontSize / layout.unitsPerEm;
    final lineHeight = fontSize * lineHeightEm;
    final width = layout.measureUnits * scale;
    return Semantics(
      label: layout.plainText,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (details) {
          final run = runAtOffset(
              layout.lines, scale, lineHeight, details.localPosition,
              slop: 6);
          final link = run?.link;
          if (link != null && link < layout.refs.length && onLinkTap != null) {
            onLinkTap!(layout.refs[link]);
          } else {
            onPlainTap?.call();
          }
        },
        child: CustomPaint(
          size: Size(width, layout.lines.length * lineHeight),
          painter: _ProsePainter(
            layout: layout,
            scale: scale,
            fontSize: fontSize,
            lineHeight: lineHeight,
            textColor: scheme.onSurface,
            accentColor: scheme.primary,
            weightEm: settings.fontWeightFor(theme.brightness),
            family: settings.fontFamily,
          ),
        ),
      ),
    );
  }
}

class _ProsePainter extends CustomPainter {
  _ProsePainter({
    required this.layout,
    required this.scale,
    required this.fontSize,
    required this.lineHeight,
    required this.textColor,
    required this.accentColor,
    required this.weightEm,
    required this.family,
  });

  final CommentLayoutView layout;
  final double scale;
  final double fontSize;
  final double lineHeight;
  final Color textColor;

  /// Labels and references share the reader's accent (verse-number) color.
  final Color accentColor;
  final double weightEm;
  final String family;

  @override
  void paint(Canvas canvas, Size size) {
    final textStyle = TextStyle(
      fontFamily: family,
      fontSize: fontSize,
      color: textColor,
    );
    final labelStyle = TextStyle(
      fontFamily: family,
      fontSize: fontSize * layout.numberScale,
      color: accentColor,
    );
    final linkStyle = textStyle.copyWith(
      color: accentColor,
      decoration: TextDecoration.underline,
      decorationColor: accentColor.withValues(alpha: 0.5),
    );
    for (var i = 0; i < layout.lines.length; i++) {
      final y = i * lineHeight;
      for (final run in layout.lines[i].runs) {
        final style = run.verseNumber
            ? labelStyle
            : run.link != null
                ? linkStyle
                : textStyle;
        paintRun(canvas, run.text, style, Offset(run.x * scale, y),
            extraWeightEm: run.headingLevel > 0
                ? weightEm + headingStrokeEm
                : weightEm);
      }
    }
  }

  @override
  bool shouldRepaint(_ProsePainter old) {
    return old.layout != layout ||
        old.scale != scale ||
        old.textColor != textColor ||
        old.accentColor != accentColor ||
        old.weightEm != weightEm ||
        old.family != family;
  }
}
