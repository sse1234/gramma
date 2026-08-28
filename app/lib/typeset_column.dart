import 'package:flutter/material.dart';

import 'annotations.dart';
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
    this.onSelectStart,
    this.onSelectExtend,
    this.onSelectEnd,
    this.onRunTap,
    this.marksByChapter = const {},
    this.paneModule,
    this.selection,
  });

  /// A tap on an inline note marker (ADR 0016); other taps fall through
  /// to [onPlainTap] (the reading-mode toggle).
  final void Function(int chapter, RunView run)? onMarkerTap;
  final VoidCallback? onPlainTap;

  /// Selection gestures (ADR 0023), with the chapter index of the row.
  final void Function(int chapter, RunView run)? onSelectStart;
  final void Function(int chapter, RunView run)? onSelectExtend;
  final VoidCallback? onSelectEnd;

  /// A tap resolved to a word run (marks open their note popup).
  final void Function(int chapter, RunView run)? onRunTap;

  /// Color marks per chapter index, pre-resolved to theme colors.
  final Map<int, List<(NoteMark, Color)>> marksByChapter;
  final String? paneModule;

  /// The live selection with its chapter index, if any.
  final (int, VerseSelection)? selection;

  final List<ColumnRow> rows;
  final int rowCount;
  final double scale;
  final double fontSize;
  final double lineHeight;

  TextRow? _rowAt(double dy) {
    final index = dy ~/ lineHeight;
    return rows.whereType<TextRow>().where((r) => r.row == index).firstOrNull;
  }

  void _selectAt(Offset position, void Function(int, RunView) callback) {
    final hit = _rowAt(position.dy);
    final run =
        hit == null ? null : runInLine(hit.line, scale, position.dx);
    if (hit != null && run != null && !run.verseNumber && !run.noteMarker) {
      callback(hit.chapter, run);
    }
  }

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
          // Markers carry their forgiving halo (ADR 0019), searched
          // across neighboring rows; anything else falls through.
          final marker = markerNear(
            [
              for (final r in rows.whereType<TextRow>())
                (line: r.line, top: r.row * lineHeight),
            ],
            scale,
            fontSize * (rows.whereType<TextRow>().firstOrNull?.numberScale ??
                    0.65),
            details.localPosition,
          );
          if (marker != null && onMarkerTap != null) {
            final row = rows
                .whereType<TextRow>()
                .where((r) => r.line.runs.contains(marker))
                .firstOrNull;
            if (row != null) {
              onMarkerTap!(row.chapter, marker);
              return;
            }
          }
          final hit = _rowAt(details.localPosition.dy);
          final run = hit == null
              ? null
              : runInLine(hit.line, scale, details.localPosition.dx);
          if (hit != null &&
              run != null &&
              !run.verseNumber &&
              !run.noteMarker &&
              onRunTap != null) {
            onRunTap!(hit.chapter, run);
          } else {
            onPlainTap?.call();
          }
        },
        onLongPressStart: onSelectStart == null
            ? null
            : (details) => _selectAt(details.localPosition, onSelectStart!),
        onLongPressMoveUpdate: onSelectExtend == null
            ? null
            : (details) => _selectAt(details.localPosition, onSelectExtend!),
        onLongPressEnd: onSelectEnd == null ? null : (_) => onSelectEnd!(),
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
            marksByChapter: marksByChapter,
            paneModule: paneModule,
            selection: selection,
            selectionColor: scheme.primary.withValues(
                alpha: theme.brightness == Brightness.light ? 0.22 : 0.34),
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
    required this.marksByChapter,
    required this.paneModule,
    required this.selection,
    required this.selectionColor,
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

  final Map<int, List<(NoteMark, Color)>> marksByChapter;
  final String? paneModule;
  final (int, VerseSelection)? selection;
  final Color selectionColor;

  void _paintWashes(Canvas canvas, TextRow row, double y) {
    void wash(bool Function(RunView) covers, Color color) {
      for (final (start, end) in coveredSpans(row.line, covers)) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(start * scale - 2, y - fontSize * 0.06,
                end * scale + 2, y + fontSize * 1.12),
            const Radius.circular(3),
          ),
          Paint()..color = color,
        );
      }
    }

    for (final (mark, color)
        in marksByChapter[row.chapter] ?? const <(NoteMark, Color)>[]) {
      wash((run) => markCoversRun(mark, run, paneModule), color);
    }
    final sel = selection;
    if (sel != null && sel.$1 == row.chapter) {
      wash(sel.$2.coversRun, selectionColor);
    }
  }

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
          _paintWashes(canvas, row, y);
          final numberStyle = TextStyle(
            fontFamily: family,
            fontSize: fontSize * numberScale,
            color: numberColor,
          );
          final markerStyle =
              numberStyle.copyWith(fontStyle: FontStyle.italic);
          final subSectionStyle =
              textStyle.copyWith(fontStyle: FontStyle.italic);
          for (final run in line.runs) {
            final style = run.verseNumber
                ? numberStyle
                : run.noteMarker
                    ? markerStyle
                    : run.headingLevel == 2
                        ? subSectionStyle
                        : textStyle;
            paintRun(canvas, run.text, style, Offset(run.x * scale, y),
                extraWeightEm: run.headingLevel == 1
                    ? weightEm + headingStrokeEm
                    : weightEm);
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
