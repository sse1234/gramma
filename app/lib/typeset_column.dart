import 'package:flutter/material.dart';

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
  const TextRow(super.row, this.line, this.numberScale);

  final LineView line;
  final double numberScale;
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
  });

  final List<ColumnRow> rows;
  final int rowCount;
  final double scale;
  final double fontSize;
  final double lineHeight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = rows
        .map((r) => switch (r) {
              HeadingRow(:final text) => text,
              TextRow(:final line) =>
                line.runs.map((run) => run.text).join(' '),
            })
        .join(' ');
    return Semantics(
      label: label,
      child: CustomPaint(
        size: Size.fromHeight(rowCount * lineHeight),
        painter: _ColumnPainter(
          rows: rows,
          scale: scale,
          fontSize: fontSize,
          lineHeight: lineHeight,
          textColor: scheme.onSurface,
          numberColor: scheme.primary,
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
  });

  final List<ColumnRow> rows;
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
    final headingStyle = TextStyle(
      fontFamily: 'GentiumBookPlus',
      fontSize: fontSize * 1.2,
      fontWeight: FontWeight.w600,
      color: textColor,
    );
    for (final row in rows) {
      final y = row.row * lineHeight;
      switch (row) {
        case HeadingRow(:final text):
          final painter = TextPainter(
            text: TextSpan(text: text, style: headingStyle),
            textDirection: TextDirection.ltr,
          )..layout();
          painter.paint(canvas, Offset(0, y + lineHeight * 0.3));
        case TextRow(:final line, :final numberScale):
          final numberStyle = TextStyle(
            fontFamily: 'GentiumBookPlus',
            fontSize: fontSize * numberScale,
            color: numberColor,
          );
          final markerStyle =
              numberStyle.copyWith(fontStyle: FontStyle.italic);
          for (final run in line.runs) {
            final painter = TextPainter(
              text: TextSpan(
                text: run.text,
                style: run.verseNumber
                    ? numberStyle
                    : run.noteMarker
                        ? markerStyle
                        : textStyle,
              ),
              textDirection: TextDirection.ltr,
            )..layout();
            painter.paint(canvas, Offset(run.x * scale, y));
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
        old.numberColor != numberColor;
  }
}
