/// Global line numbering over a module's chapter blocks, chunked into
/// viewport-sized columns.
///
/// Layout happens at the canonical em measure, so a chapter's line count is
/// viewport-independent; a column is nothing but a window of
/// [linesPerColumn] consecutive global lines. Each chapter block is
/// [headingLines] heading lines followed by its text lines.
class ColumnPlan {
  ColumnPlan({
    required List<int> textLines,
    required this.headingLines,
    required this.linesPerColumn,
  }) : _blockStarts = List<int>.filled(textLines.length, 0) {
    var offset = 0;
    for (var i = 0; i < textLines.length; i++) {
      _blockStarts[i] = offset;
      offset += headingLines + textLines[i];
    }
    totalLines = offset;
  }

  final int headingLines;
  final int linesPerColumn;
  final List<int> _blockStarts;
  late final int totalLines;

  int get columnCount =>
      totalLines == 0 ? 0 : (totalLines + linesPerColumn - 1) ~/ linesPerColumn;

  int columnOfLine(int line) => line ~/ linesPerColumn;

  int firstLineOfColumn(int column) => column * linesPerColumn;

  int blockStart(int chapter) => _blockStarts[chapter];

  /// Chapter whose block contains [line] (which must be < [totalLines]).
  int chapterOfLine(int line) {
    var lo = 0;
    var hi = _blockStarts.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) ~/ 2;
      if (_blockStarts[mid] <= line) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  /// Chapter and block-local index for a global line: local values below
  /// [headingLines] are heading rows, the rest are text lines at
  /// `local - headingLines`.
  ({int chapter, int local})? locate(int line) {
    if (line < 0 || line >= totalLines) return null;
    final chapter = chapterOfLine(line);
    return (chapter: chapter, local: line - _blockStarts[chapter]);
  }
}
