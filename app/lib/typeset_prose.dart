import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'run_hit.dart';
import 'run_paint.dart';
import 'settings.dart';
import 'src/rust/api/typeset.dart';

/// The common shape of a typeset prose layout — commentary entries
/// (ADR 0018) and dictionary entries (ADR 0019) paint identically.
class ProseLayout {
  const ProseLayout({
    required this.lines,
    required this.refs,
    required this.unitsPerEm,
    required this.measureUnits,
    required this.numberScale,
    required this.plainText,
    this.images = const {},
  });

  ProseLayout.ofComment(
    CommentLayoutView c, {
    Map<int, ui.Image> images = const {},
  }) : this(
         lines: c.lines,
         refs: c.refs,
         unitsPerEm: c.unitsPerEm,
         measureUnits: c.measureUnits,
         numberScale: c.numberScale,
         plainText: c.plainText,
         images: images,
       );

  ProseLayout.ofDict(DictLayoutView d)
    : this(
        lines: d.lines,
        refs: d.refs,
        unitsPerEm: d.unitsPerEm,
        measureUnits: d.measureUnits,
        numberScale: d.numberScale,
        plainText: d.plainText,
      );

  final List<LineView> lines;

  /// OSIS targets by run link index.
  final List<String> refs;
  final int unitsPerEm;
  final int measureUnits;
  final double numberScale;
  final String plainText;

  /// Decoded figures by the module's image index (ADR 0029); a figure
  /// line whose image is missing here paints as a blank slot.
  final Map<int, ui.Image> images;

  /// Image indices the lines refer to.
  Iterable<int> get imageIndices => lines.map((l) => l.image).whereType<int>();
}

/// Character style bits carried by runs (ADR 0029).
const styleItalic = 1;
const styleBold = 2;
const styleSmallCaps = 4;
const styleSuperscript = 8;

/// Paints one typeset prose entry: the same Knuth–Plass lines and
/// painting path as the Bible text, at the pane's own measure. Runs
/// carrying a link index are tappable references (ADR 0016 hit paths);
/// other taps fall through to [onPlainTap].
class TypesetProse extends StatelessWidget {
  const TypesetProse({
    super.key,
    required this.layout,
    required this.fontSize,
    this.lineHeightEm = 1.5,
    this.onLinkTap,
    this.onPlainTap,
    this.onWordLongPress,
    this.onLabelTap,
  });

  final ProseLayout layout;

  /// Text size in logical pixels; the measure was computed from it.
  final double fontSize;
  final double lineHeightEm;

  /// A tap on a reference run, with the resolved OSIS target.
  final ValueChanged<String>? onLinkTap;
  final VoidCallback? onPlainTap;

  /// A long press on a word (ADR 0019): dictionary lookup.
  final ValueChanged<RunView>? onWordLongPress;

  /// A tap on the entry's label run (the Strong number), with marker
  /// halo mechanics (ADR 0020): opens the concordance.
  final VoidCallback? onLabelTap;

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
          if (onLabelTap != null) {
            final label = haloNear(
              [
                for (var i = 0; i < layout.lines.length; i++)
                  (line: layout.lines[i], top: i * lineHeight),
              ],
              scale,
              fontSize * layout.numberScale,
              details.localPosition,
              where: (run) => run.verseNumber,
            );
            if (label != null) {
              onLabelTap!();
              return;
            }
          }
          final run = runAtOffset(
            layout.lines,
            scale,
            lineHeight,
            details.localPosition,
          );
          final link = run?.link;
          if (link != null && link < layout.refs.length && onLinkTap != null) {
            onLinkTap!(layout.refs[link]);
          } else {
            onPlainTap?.call();
          }
        },
        onLongPressStart: onWordLongPress == null
            ? null
            : (details) {
                final run = runAtOffset(
                  layout.lines,
                  scale,
                  lineHeight,
                  details.localPosition,
                );
                if (run != null) onWordLongPress!(run);
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

  final ProseLayout layout;
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
      final line = layout.lines[i];
      final imageIndex = line.image;
      if (imageIndex != null) {
        _paintFigure(canvas, imageIndex, y, line.imageLines * lineHeight);
        continue;
      }
      for (final run in line.runs) {
        var style = run.verseNumber
            ? labelStyle
            : run.link != null
            ? linkStyle
            : textStyle;
        // Styled runs (ADR 0029): the engine measured them at `scale`
        // and, for small caps, in capitals; italics render as a slant
        // of the same face so widths hold.
        if (run.scale != 1.0 && !run.verseNumber) {
          style = style.copyWith(fontSize: fontSize * run.scale);
        }
        if (run.style & styleItalic != 0) {
          style = style.copyWith(fontStyle: FontStyle.italic);
        }
        final bold = run.style & styleBold != 0;
        final raised = run.style & styleSuperscript != 0 || run.noteMarker;
        final dy = raised ? -fontSize * 0.35 : 0.0;
        paintRun(
          canvas,
          run.text,
          style,
          Offset(run.x * scale, y + dy),
          extraWeightEm: run.headingLevel > 0 || bold
              ? weightEm + headingStrokeEm
              : weightEm,
        );
      }
    }
  }

  /// A figure fills its reserved lines, letterboxed to keep its aspect.
  void _paintFigure(Canvas canvas, int index, double top, double height) {
    final image = layout.images[index];
    final width = layout.measureUnits * scale;
    if (image == null) {
      final paint = Paint()
        ..color = textColor.withValues(alpha: 0.06)
        ..style = PaintingStyle.fill;
      canvas.drawRect(
        Rect.fromLTWH(0, top, width, height - lineHeight * 0.3),
        paint,
      );
      return;
    }
    final aspect = image.width / image.height;
    var drawWidth = width;
    var drawHeight = width / aspect;
    if (drawHeight > height) {
      drawHeight = height;
      drawWidth = height * aspect;
    }
    final dst = Rect.fromLTWH(
      (width - drawWidth) / 2,
      top,
      drawWidth,
      drawHeight,
    );
    final src = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    canvas.drawImageRect(
      image,
      src,
      dst,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(_ProsePainter old) {
    return old.layout != layout ||
        old.layout.images != layout.images ||
        old.scale != scale ||
        old.textColor != textColor ||
        old.accentColor != accentColor ||
        old.weightEm != weightEm ||
        old.family != family;
  }
}
