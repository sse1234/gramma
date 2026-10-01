import 'settings.dart';

/// How a pane sizes its text (ADR 0032): the glyph size is the reader's
/// setting; the line length is the reader's setting where the pane is
/// wide enough for one column, and otherwise the widest whole number of
/// ems that fits. Column width follows from the two, and the gap between
/// columns is the reader's too, in ems of the glyph size (ADR 0034).
class TextGeometry {
  const TextGeometry({
    required this.fontSize,
    required this.measureEms,
    required this.columns,
    required this.gutter,
  });

  /// Space between text columns in logical pixels: the column gap
  /// setting times the glyph size.
  final double gutter;

  /// Glyph size in logical pixels.
  final double fontSize;

  /// The effective measure the pane lays out at.
  final int measureEms;

  /// Whole columns of the preferred width that fit the pane; 0 when the
  /// pane is narrower than one, in which case [measureEms] is the fitted
  /// line length and the pane shows a single column.
  final int columns;

  double get columnWidth => fontSize * measureEms;

  /// The geometry for a pane [width] wide.
  static TextGeometry fit(
    SettingsController settings,
    double width, {
    double scale = 1,
  }) {
    final fontSize = settings.glyphSize * scale;
    final gutter = fontSize * settings.columnGapEms;
    final preferred = settings.measureEms;
    final preferredWidth = fontSize * preferred;
    final columns = ((width + gutter) / (preferredWidth + gutter)).floor();
    if (columns >= 1) {
      return TextGeometry(
        fontSize: fontSize,
        measureEms: preferred,
        columns: columns,
        gutter: gutter,
      );
    }
    final fitted = (width / fontSize).floor().clamp(
      SettingsController.minMeasureEms,
      preferred,
    );
    return TextGeometry(
      fontSize: fontSize,
      measureEms: fitted,
      columns: 0,
      gutter: gutter,
    );
  }
}
