/// Global line numbering over a module's chapter blocks, chunked into
/// viewport-sized columns.
///
/// Layout happens at the canonical em measure, so a chapter's line count is
/// viewport-independent; a column is a window of at most [linesPerColumn]
/// consecutive global lines. Each chapter block is [headingLines] heading
/// lines followed by its text lines.
///
/// With [rowKinds] provided (per chapter, one entry per text line: 0 =
/// content, 1 = heading, 2 = blank), columns keep headings with their
/// text (ADR 0026): a heading group — consecutive heading rows, chapter
/// title blocks included — landing at a column's foot with fewer than
/// [keptContentRows] content rows beneath breaks the column early and
/// heads the next one instead. A group already at its column's top stays.
class ColumnPlan {
  ColumnPlan({
    required List<int> textLines,
    required this.headingLines,
    required this.linesPerColumn,
    this.rowKinds,
  }) : _blockStarts = List<int>.filled(textLines.length, 0) {
    var offset = 0;
    for (var i = 0; i < textLines.length; i++) {
      _blockStarts[i] = offset;
      offset += headingLines + textLines[i];
    }
    totalLines = offset;
    _columnStarts = _computeStarts();
  }

  /// A pushed heading keeps at least this many content rows beneath it.
  static const keptContentRows = 3;

  final int headingLines;
  final int linesPerColumn;
  final List<int> _blockStarts;
  final List<List<int>>? rowKinds;
  late final int totalLines;
  late final List<int> _columnStarts;

  int get columnCount => _columnStarts.length;

  int columnOfLine(int line) {
    var lo = 0;
    var hi = _columnStarts.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) ~/ 2;
      if (_columnStarts[mid] <= line) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  int firstLineOfColumn(int column) => _columnStarts[column];

  /// Lines actually placed in [column] — at most [linesPerColumn], fewer
  /// when a heading group broke the column early or the stream ends.
  int linesInColumn(int column) {
    final next = column + 1 < _columnStarts.length
        ? _columnStarts[column + 1]
        : totalLines;
    return next - _columnStarts[column];
  }

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

  /// Row kind of a global line: block heading rows count as headings.
  int _kind(int line) {
    final kinds = rowKinds!;
    final chapter = chapterOfLine(line);
    final local = line - _blockStarts[chapter];
    if (local < headingLines) return 1;
    final rows = kinds[chapter];
    final textRow = local - headingLines;
    return textRow < rows.length ? rows[textRow] : 0;
  }

  List<int> _computeStarts() {
    final starts = <int>[];
    if (totalLines == 0) return starts;
    final aware = rowKinds != null && rowKinds!.length == _blockStarts.length;
    var s = 0;
    while (s < totalLines) {
      starts.add(s);
      var e = s + linesPerColumn;
      if (e > totalLines) e = totalLines;
      if (aware) {
        var changed = true;
        while (changed) {
          changed = false;
          var i = s + 1;
          while (i < e) {
            if (_kind(i) == 1 && _kind(i - 1) != 1) {
              final g = i;
              var gEnd = g;
              while (gEnd < totalLines && _kind(gEnd) == 1) {
                gEnd++;
              }
              var content = 0;
              for (var j = gEnd; j < e; j++) {
                if (_kind(j) == 0) content++;
              }
              if (gEnd > e || content < keptContentRows) {
                e = g;
                changed = true;
                break;
              }
              i = gEnd;
            } else {
              i++;
            }
          }
        }
      }
      s = e;
    }
    return starts;
  }
}
