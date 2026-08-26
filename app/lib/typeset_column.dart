import 'package:flutter/material.dart';

import 'run_hit.dart';
import 'run_paint.dart';
import 'settings.dart';
import 'src/rust/api/typeset.dart';

/// One resolved row of a column: a chapter heading or a typeset text line.
sealed class ColumnRow {
  const ColumnRow(this.row);

  /// Row index within the column (0-based from the top).
  final int row;
}

class HeadingRow extends ColumnRow {
  const HeadingRow(super.row, this.text);

  final String text;
}

class TextRow extends ColumnRow {
  const TextRow(super.row, this.line, this.numberScale, this.chapter);

  final LineView line;
  final double numberScale;

  /// Spine index of the chapter this line belongs to (for note lookup).
  final int chapter;
}

/// Paints one column of the horizontal reader: a fixed window of global
/// lines, with chapter headings flowing inline.
class TypesetColumn extends StatelessWidget {
  const TypesetColumn({
    super.key,
    required this.rows,
    required this.rowCount,
    required this.scale,
    required this.fontSize,
    required this.lineHeight,
    this.onMarkerTap,
    this.onPlainTap,
  });

  /// A tap on an inline note marker (ADR 0016); other taps fall through
  /// to [onPlainTap] (the reading-mode toggle).
  final void Function(int chapter, RunView run)? onMarkerTap;
  final VoidCallback? onPlainTap;

  final List<ColumnRow> rows;
  final int rowCount;
  final double scale;
  final double fontSize;
  final double lineHeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final settings = SettingsScope.of(context);
    final weightEm = settings.fontWeightFor(theme.brightness);
    final family = settings.fontFamily;
    final label = rows
        .map((r) => switch (r) {
              HeadingRow(:final text) => text,
              TextRow(:final line) =>
                line.runs.map((run) => run.text).join(' '),
            })
        .join(' ');
    return Semantics(
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (details) {
          final index = details.localPosition.dy ~/ lineHeight;
          final hit = rows
              .whereType<TextRow>()
              .where((r) => r.row == index)
              .firstOrNull;
          final run = hit == null
              ? null
              : runInLine(hit.line, scale, details.localPosition.dx, slop: 6);
          if (hit != null &&
              run != null &&
              run.noteMarker &&
              onMarkerTap != null) {
            onMarkerTap!(hit.chapter, run);
          } else {
            onPlainTap?.call();
          }
        },
        child: CustomPaint(
          size: Size.fromHeight(rowCount * lineHeight),
          painter: _ColumnPainter(
          rows: rows,
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
  }
}

class _ColumnPainter extends CustomPainter {
  _ColumnPainter({
    required this.rows,
    required this.scale,
    required this.fontSize,
    required this.lineHeight,
    required this.textColor,
    required this.numberColor,
    required this.weightEm,
    required this.family,
  });

  final List<ColumnRow> rows;
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
    final headingStyle = TextStyle(
      fontFamily: family,
      fontSize: fontSize * 1.2,
      fontWeight: FontWeight.w600,
      color: textColor,
    );
    for (final row in rows) {
      final y = row.row * lineHeight;
      switch (row) {
        case HeadingRow(:final text):
          paintRun(canvas, text, headingStyle, Offset(0, y + lineHeight * 0.3),
              extraWeightEm: weightEm);
        case TextRow(:final line, :final numberScale):
          final numberStyle = TextStyle(
            fontFamily: family,
            fontSize: fontSize * numberScale,
            color: numberColor,
          );
          final markerStyle =
              numberStyle.copyWith(fontStyle: FontStyle.italic);
          final sectionStyle =
              textStyle.copyWith(fontWeight: FontWeight.w600);
          final subSectionStyle =
              textStyle.copyWith(fontStyle: FontStyle.italic);
          for (final run in line.runs) {
            final style = run.verseNumber
                ? numberStyle
                : run.noteMarker
                    ? markerStyle
                    : run.headingLevel == 1
                        ? sectionStyle
                        : run.headingLevel == 2
                            ? subSectionStyle
                            : textStyle;
            paintRun(canvas, run.text, style, Offset(run.x * scale, y),
                extraWeightEm: weightEm);
          }
      }
    }
  }

  @override
  bool shouldRepaint(_ColumnPainter old) {
    return old.rows != rows ||
        old.scale != scale ||
        old.lineHeight != lineHeight ||
        old.textColor != textColor ||
        old.numberColor != numberColor ||
        old.weightEm != weightEm ||
        old.family != family;
  }
}
