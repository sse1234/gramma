import 'package:flutter/material.dart';

import 'annotations.dart';
import 'l10n.dart';
import 'mark_popup.dart';
import 'palette.dart';
import 'pane_model.dart';
import 'src/rust/api/library.dart';
import 'src/rust/api/references.dart';
import 'src/rust/api/typeset.dart';

/// Live word selection and marks of a text view (ADR 0023): the
/// long-press range, its floating bar, and the mark popups. The host
/// supplies its chapters, its module, and the word lookup; everything
/// else about selecting and marking lives here.
mixin ReaderSelection<T extends StatefulWidget> on State<T> {
  /// The chapters a selection indexes into.
  List<ChapterRefView> get spine;

  /// The module the marks belong to.
  String? get paneModule;

  /// Where a selected word is looked up (ADR 0019).
  WordLookup? get wordLookup;

  /// The chapter index the selection belongs to, the long-press anchor
  /// run, and the normalized range.
  int? selectionChapter;
  RunView? _selectionAnchor;
  VerseSelection? selection;

  void selectStart(int chapterIndex, RunView run) {
    setState(() {
      selectionChapter = chapterIndex;
      _selectionAnchor = run;
      selection = VerseSelection.ofRun(run);
    });
  }

  void selectExtend(int chapterIndex, RunView run) {
    final anchor = _selectionAnchor;
    if (anchor == null || chapterIndex != selectionChapter) return;
    setState(() => selection = VerseSelection.between(anchor, run));
  }

  void clearSelection() {
    if (selection == null) return;
    setState(() {
      selection = null;
      _selectionAnchor = null;
      selectionChapter = null;
    });
  }

  /// The last mark covering [run] in its chapter, if any.
  NoteMark? markCovering(int chapterIndex, RunView run) {
    final chapter = spine[chapterIndex];
    return Annotations.forChapter(
      chapter.bookOsis,
      chapter.chapter,
    ).where((m) => markCoversRun(m, run, paneModule)).lastOrNull;
  }

  String selectionLabel(int chapterIndex, VerseSelection sel) {
    final chapter = spine[chapterIndex];
    final start = formatReference(
      osis: '${chapter.bookOsis}.${chapter.chapter}.${sel.verseStart}',
    );
    return sel.verseStart == sel.verseEnd ? start : '$start–${sel.verseEnd}';
  }

  void selectionDictionary() {
    final sel = selection;
    final chapterIndex = selectionChapter;
    final word = sel?.word;
    if (sel == null || chapterIndex == null || word == null) return;
    final chapter = spine[chapterIndex];
    clearSelection();
    wordLookup?.call(
      word,
      module: paneModule,
      bookOsis: chapter.bookOsis,
      chapter: chapter.chapter,
      verse: sel.verseStart,
    );
  }

  void selectionMark() {
    final sel = selection;
    final chapterIndex = selectionChapter;
    final module = paneModule;
    if (sel == null || chapterIndex == null || module == null) return;
    final chapter = spine[chapterIndex];
    final draft = NoteMark(
      id: Annotations.newId(),
      module: module,
      bookOsis: chapter.bookOsis,
      chapter: chapter.chapter,
      verseStart: sel.verseStart,
      verseEnd: sel.verseEnd,
      startOffset: sel.startOffset,
      endOffset: sel.endOffset,
      colorIndex: 0,
      text: '',
      created: DateTime.now().toUtc().toIso8601String(),
    );
    showMarkPopup(
      context,
      title: selectionLabel(chapterIndex, sel),
      draft: draft,
      isNew: true,
      onSave: (mark) {
        Annotations.save(mark);
        clearSelection();
        setState(() {});
      },
    );
  }

  void editMark(NoteMark mark) {
    showMarkPopup(
      context,
      title:
          formatReference(osis: mark.osis.split('-').first) +
          (mark.verseStart == mark.verseEnd ? '' : '–${mark.verseEnd}'),
      draft: mark,
      isNew: false,
      onSave: (updated) {
        Annotations.save(updated);
        setState(() {});
      },
      onDelete: () {
        Annotations.delete(mark.id);
        setState(() {});
      },
    );
  }

  /// Marks of one chapter with their theme colors, for the painters.
  List<(NoteMark, Color)> paintMarks(int chapterIndex) {
    if (chapterIndex >= spine.length) return const [];
    final chapter = spine[chapterIndex];
    final brightness = Theme.of(context).brightness;
    return [
      for (final m in Annotations.forChapter(chapter.bookOsis, chapter.chapter))
        (m, markColor(m.colorIndex, brightness)),
    ];
  }

  /// The floating bar of an active selection: its reference, dictionary
  /// lookup, mark, and close.
  Widget selectionBar(ThemeData theme) {
    final sel = selection!;
    final chapterIndex = selectionChapter!;
    return Material(
      key: const Key('selection-bar'),
      elevation: 6,
      color: theme.colorScheme.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                selectionLabel(chapterIndex, sel),
                key: const Key('selection-label'),
                style: theme.textTheme.titleSmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              key: const Key('selection-dictionary'),
              tooltip: context.l10n.dictionaryTitle,
              icon: const Icon(Icons.translate_outlined, size: 20),
              onPressed: sel.word == null ? null : selectionDictionary,
            ),
            IconButton(
              key: const Key('selection-mark'),
              tooltip: context.l10n.markSelection,
              icon: const Icon(Icons.brush_outlined, size: 20),
              onPressed: selectionMark,
            ),
            IconButton(
              key: const Key('selection-close'),
              icon: const Icon(Icons.close, size: 20),
              onPressed: clearSelection,
            ),
          ],
        ),
      ),
    );
  }
}
