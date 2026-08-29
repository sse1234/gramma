import 'package:flutter/material.dart';

import 'annotations.dart';
import 'l10n.dart';
import 'mark_popup.dart';
import 'palette.dart';
import 'reader_pane.dart';
import 'src/rust/api/references.dart';

/// The notes overview (ADR 0023 follow-up): every annotation in the
/// store, in canonical order, jumpable. Tapping a row opens its passage
/// in the desk's text view; the edit action reopens the note popup.
class NotesPane extends StatefulWidget {
  const NotesPane({
    super.key,
    required this.readingMode,
    required this.onToggleMode,
    required this.badge,
    required this.onOpenReference,
    this.dragHandle,
    this.onClose,
  });

  final bool readingMode;
  final VoidCallback onToggleMode;
  final Widget? badge;

  /// Navigate the desk's text view to a mark's passage.
  final ValueChanged<String> onOpenReference;
  final Widget? dragHandle;
  final VoidCallback? onClose;

  @override
  State<NotesPane> createState() => _NotesPaneState();
}

class _NotesPaneState extends State<NotesPane> {
  @override
  void initState() {
    super.initState();
    Annotations.revision.addListener(_changed);
  }

  @override
  void dispose() {
    Annotations.revision.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  /// All marks in canonical order (book, chapter, verse), newest first
  /// within the same verse.
  List<NoteMark> _sorted() {
    final marks = [...Annotations.all()];
    marks.sort((a, b) {
      final book = bookSortIndex(osis: a.bookOsis)
          .compareTo(bookSortIndex(osis: b.bookOsis));
      if (book != 0) return book;
      if (a.chapter != b.chapter) return a.chapter.compareTo(b.chapter);
      if (a.verseStart != b.verseStart) {
        return a.verseStart.compareTo(b.verseStart);
      }
      return b.created.compareTo(a.created);
    });
    return marks;
  }

  String _label(NoteMark mark) =>
      formatReference(osis: '${mark.bookOsis}.${mark.chapter}.${mark.verseStart}') +
      (mark.verseStart == mark.verseEnd ? '' : '–${mark.verseEnd}');

  void _edit(NoteMark mark) {
    showMarkPopup(
      context,
      title: _label(mark),
      draft: mark,
      isNew: false,
      onSave: Annotations.save,
      onDelete: () => Annotations.delete(mark.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final marks = _sorted();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.readingMode) ...[
          PaneHeader(
            title: context.l10n.notesTitle,
            badge: widget.badge,
            dragHandle: widget.dragHandle,
            followValue: null,
            followOptions: const [],
            onFollow: null,
            onClose: widget.onClose,
          ),
          const SizedBox(height: 8),
        ],
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: widget.onToggleMode,
            child: marks.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        context.l10n.noNotesYet,
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: marks.length,
                    itemBuilder: (context, i) {
                      final mark = marks[i];
                      return ListTile(
                        key: Key('note-row-$i'),
                        leading: Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: markColor(
                                mark.colorIndex, theme.brightness),
                            shape: BoxShape.circle,
                          ),
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(_label(mark),
                                  overflow: TextOverflow.ellipsis),
                            ),
                            Text(
                              mark.module,
                              style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                        subtitle: mark.text.isEmpty
                            ? Text(
                                context.l10n.pureMark,
                                style: const TextStyle(
                                    fontStyle: FontStyle.italic),
                              )
                            : Text(
                                mark.text,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                        trailing: IconButton(
                          key: Key('note-edit-$i'),
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _edit(mark),
                        ),
                        onTap: () => widget.onOpenReference(
                            '${mark.bookOsis}.${mark.chapter}.${mark.verseStart}'),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}
