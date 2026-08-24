import 'package:flutter/material.dart';

import 'palette.dart';
import 'src/rust/api/library.dart';

typedef SelectorResult = ({String book, int chapter, int? verse});

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
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 560),
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
          Expanded(child: _tier(theme)),
        ],
      ),
    );
  }

  Widget _tier(ThemeData theme) {
    final book = _book;
    if (book == null) {
      final brightness = theme.brightness;
      return _grid([
        for (final b in widget.books)
          _tile(
            key: Key('sel-book-${b.osis}'),
            label: b.abbrev,
            background: bookCategoryColor(b.category, brightness),
            onTap: () => setState(() => _book = b),
          ),
      ]);
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
