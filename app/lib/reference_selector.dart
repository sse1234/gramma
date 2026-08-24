import 'package:flutter/material.dart';

import 'palette.dart';
import 'src/rust/api/library.dart';

typedef SelectorResult = ({String book, int chapter, int? verse});

/// Splits [items] into rows of at most [capacity].
List<List<T>> chunkRows<T>(List<T> items, int capacity) {
  return [
    for (var i = 0; i < items.length; i += capacity)
      items.sublist(i, (i + capacity).clamp(0, items.length).toInt()),
  ];
}

/// The book → chapter → verse selector: the first popup workflow. Books are
/// a grid tinted by canon category (Grammar-of-Graphics hues); chapters and
/// verses are plain grids.
Future<SelectorResult?> showReferenceSelector(
  BuildContext context,
  List<ChapterRefView> spine,
) {
  final books = <_Book>[];
  for (final chapter in spine) {
    if (books.isEmpty || books.last.osis != chapter.bookOsis) {
      books.add(_Book(
        osis: chapter.bookOsis,
        abbrev: chapter.bookAbbrev,
        category: chapter.bookCategory,
      ));
    }
    books.last.chapters.add(chapter);
  }
  return showDialog<SelectorResult>(
    context: context,
    builder: (context) => Dialog(
      // Height follows the content (the book grid with one row group per
      // category); the dialog's inset padding caps it at the window.
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: _SelectorFlow(books: books),
      ),
    ),
  );
}

class _Book {
  _Book({required this.osis, required this.abbrev, required this.category});

  final String osis;
  final String abbrev;
  final int category;
  final List<ChapterRefView> chapters = [];
}

class _SelectorFlow extends StatefulWidget {
  const _SelectorFlow({required this.books});

  final List<_Book> books;

  @override
  State<_SelectorFlow> createState() => _SelectorFlowState();
}

class _SelectorFlowState extends State<_SelectorFlow> {
  _Book? _book;
  ChapterRefView? _chapter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final book = _book;
    final chapter = _chapter;
    final title = book == null
        ? 'Book'
        : chapter == null
            ? book.abbrev
            : '${book.abbrev} ${chapter.chapter}';
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (book != null)
                IconButton(
                  key: const Key('selector-back'),
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => setState(() {
                    if (_chapter != null) {
                      _chapter = null;
                    } else {
                      _book = null;
                    }
                  }),
                ),
              Expanded(
                child: Text(title, style: theme.textTheme.titleMedium),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Flexible(child: _tier(theme)),
        ],
      ),
    );
  }

  Widget _tier(ThemeData theme) {
    final book = _book;
    if (book == null) {
      final brightness = theme.brightness;
      // One row group per canon category: the grid reads like a table of
      // contents, with the category tint carrying the separation.
      final groups = <List<_Book>>[];
      for (final b in widget.books) {
        if (groups.isEmpty || groups.last.last.category != b.category) {
          groups.add([]);
        }
        groups.last.add(b);
      }
      // Categories alternate between zero and half-a-tile left offset; all
      // rows of one category share its offset, so each group is a solid
      // block and the zigzag marks every category boundary.
      const tileWidth = 56.0;
      const spacing = 6.0;
      const shift = (tileWidth + spacing) / 2;
      return LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final capacity =
              ((width + spacing) / (tileWidth + spacing)).floor().clamp(1, 66);
          final shiftedCapacity =
              ((width - shift + spacing) / (tileWidth + spacing))
                  .floor()
                  .clamp(1, 66);
          return ListView(
            shrinkWrap: true,
            children: [
              for (final (groupIndex, group) in groups.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final (rowIndex, row) in chunkRows(
                              group,
                              groupIndex.isOdd
                                  ? shiftedCapacity
                                  : capacity)
                          .indexed)
                        Padding(
                          padding: EdgeInsets.only(
                            top: rowIndex > 0 ? spacing : 0,
                            left: groupIndex.isOdd ? shift : 0,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (final (i, b) in row.indexed)
                                Padding(
                                  padding: EdgeInsets.only(
                                      left: i > 0 ? spacing : 0),
                                  child: SizedBox(
                                    width: tileWidth,
                                    height: 40,
                                    child: _tile(
                                      key: Key('sel-book-${b.osis}'),
                                      label: b.abbrev,
                                      background: bookCategoryColor(
                                          b.category, brightness),
                                      onTap: () =>
                                          setState(() => _book = b),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          );
        },
      );
    }
    final chapter = _chapter;
    if (chapter == null) {
      return _grid([
        for (final c in book.chapters)
          _tile(
            key: Key('sel-ch-${c.chapter}'),
            label: '${c.chapter}',
            background: theme.colorScheme.surfaceContainerHighest,
            onTap: () => setState(() => _chapter = c),
          ),
      ]);
    }
    return _grid([
      for (var v = 1; v <= chapter.maxVerse; v++)
        _tile(
          key: Key('sel-v-$v'),
          label: '$v',
          background: theme.colorScheme.surfaceContainerHighest,
          onTap: () => Navigator.of(context).pop(
            (book: book.osis, chapter: chapter.chapter, verse: v),
          ),
        ),
    ]);
  }

  Widget _grid(List<Widget> tiles) {
    return GridView.extent(
      shrinkWrap: true,
      maxCrossAxisExtent: 64,
      mainAxisSpacing: 6,
      crossAxisSpacing: 6,
      children: tiles,
    );
  }

  Widget _tile({
    required Key key,
    required String label,
    required Color background,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return Material(
      key: key,
      color: background,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Center(
          child: Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
