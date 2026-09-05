import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'l10n.dart';
import 'note_text.dart';
import 'passage_preview.dart';
import 'reader_pane.dart';
import 'settings.dart';
import 'src/rust/api/library.dart';

/// Spine indexes of the chapters in the visible range [anchor, anchorEnd]
/// of the followed view (both "Book.Ch(.V)"); anchorEnd may be null or
/// malformed, in which case only the anchor chapter is visible.
List<int> visibleChapterIndexes(
  List<ChapterRefView> spine,
  String anchor,
  String? anchorEnd,
) {
  int indexOf(String osis) {
    final parts = osis.split('.');
    if (parts.length < 2) return -1;
    final chapter = int.tryParse(parts[1]);
    return spine.indexWhere(
      (c) => c.bookOsis == parts[0] && c.chapter == chapter,
    );
  }

  final start = indexOf(anchor);
  if (start < 0) return const [];
  var end = anchorEnd == null ? start : indexOf(anchorEnd);
  if (end < start) end = start;
  return [for (var i = start; i <= end; i++) i];
}

typedef FootnoteEntry = ({ChapterRefView chapter, NoteView note});

/// The footnotes of [module] within the visible range [anchor, anchorEnd]
/// of a text view (both "Book.Ch(.V)"), in reading order.
List<FootnoteEntry> visibleFootnotes(
  List<ChapterRefView> spine,
  String module,
  String anchor,
  String? anchorEnd,
) {
  final indexes = visibleChapterIndexes(spine, anchor, anchorEnd);
  final startVerse = verseOfOsis(anchor);
  final endVerse = verseOfOsis(anchorEnd ?? '');
  final entries = <FootnoteEntry>[];
  for (final index in indexes) {
    final chapter = spine[index];
    final notes = chapterNotes(
      moduleCode: module,
      bookOsis: chapter.bookOsis,
      chapter: chapter.chapter,
    );
    for (final note in notes) {
      if (index == indexes.first &&
          startVerse != null &&
          note.verse < startVerse) {
        continue;
      }
      if (index == indexes.last &&
          endVerse != null &&
          anchorEnd != null &&
          note.verse > endVerse) {
        continue;
      }
      entries.add((chapter: chapter, note: note));
    }
  }
  return entries;
}

/// Display labels for [entries] (ADR 0028): the running marker letter
/// alone while the letters are unambiguous in the visible range; when
/// two chapters' letters collide, chapter and verse join the letter.
List<String> footnoteLabels(List<FootnoteEntry> entries) {
  final letters = [for (final e in entries) e.note.label];
  if (letters.toSet().length == letters.length) return letters;
  return [
    for (final e in entries)
      '${e.chapter.chapter},${e.note.verse}${e.note.label}',
  ];
}

int? verseOfOsis(String osis) {
  final parts = osis.split('.');
  return parts.length >= 3 ? int.tryParse(parts[2]) : null;
}

/// Receiver-only view (ADR 0008): shows the footnotes visible in the
/// followed text view's range. Note text is scanned for verse references,
/// which preview their passage in a floating popup.
class FootnotesPane extends StatefulWidget {
  const FootnotesPane({
    super.key,
    required this.followedAnchor,
    required this.followedAnchorEnd,
    required this.sourceModule,
    required this.followValue,
    required this.followOptions,
    required this.readingMode,
    required this.onToggleMode,
    required this.badge,
    required this.onFollow,
    required this.onOpenReference,
    this.dragHandle,
    this.onClose,
  });

  /// Canonical "Book.Ch.V" bounds of the followed pane's visible range.
  final String? followedAnchor;
  final String? followedAnchorEnd;

  /// Module code of the followed pane, whose notes are shown.
  final String? sourceModule;

  final String? followValue;
  final List<FollowOption> followOptions;
  final bool readingMode;
  final VoidCallback onToggleMode;
  final Widget? badge;
  final ValueChanged<String?> onFollow;

  /// Navigate the linked text view to a reference (from a preview).
  final ValueChanged<String> onOpenReference;
  final Widget? dragHandle;
  final VoidCallback? onClose;

  @override
  State<FootnotesPane> createState() => _FootnotesPaneState();
}

class _FootnotesPaneState extends State<FootnotesPane> {
  List<ChapterRefView>? _spine;
  String? _spineModule;
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  List<ChapterRefView> _spineFor(String module) {
    if (_spineModule != module) {
      _spine = contents(moduleCode: module);
      _spineModule = module;
    }
    return _spine!;
  }

  void _openPreview(String osis) {
    final settings = SettingsScope.of(context);
    final module = settings.defaultModule ?? widget.sourceModule;
    if (module == null) return;
    showPassagePreview(
      context,
      osis: osis,
      moduleCode: module,
      onOpen: () => widget.onOpenReference(osis),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.readingMode) ...[
          PaneHeader(
            title: context.l10n.footnotesTitle,
            badge: widget.badge,
            dragHandle: widget.dragHandle,
            followValue: widget.followValue,
            followOptions: widget.followOptions,
            onFollow: widget.onFollow,
            onClose: widget.onClose,
          ),
          const SizedBox(height: 8),
        ],
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: widget.onToggleMode,
            child: _body(theme),
          ),
        ),
      ],
    );
  }

  Widget _body(ThemeData theme) {
    _disposeRecognizers();
    final anchor = widget.followedAnchor;
    final module = widget.sourceModule;
    if (anchor == null || module == null) {
      return Center(
        child: Text(
          context.l10n.linkFootnotesHint,
          style: theme.textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
      );
    }
    final spine = _spineFor(module);
    final entries = visibleFootnotes(
      spine,
      module,
      anchor,
      widget.followedAnchorEnd,
    );
    if (entries.isEmpty) {
      return Center(
        child: Text(
          context.l10n.noFootnotes,
          key: const Key('no-footnotes'),
          style: theme.textTheme.bodyMedium,
        ),
      );
    }
    final settings = SettingsScope.of(context);
    final scale = settings.footnoteScale;
    final family = settings.fontFamily;
    final numberStyle = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.primary,
      fontFamily: family,
      fontSize: (theme.textTheme.labelMedium?.fontSize ?? 12) * scale,
    );
    final textStyle = theme.textTheme.bodyMedium?.copyWith(
      fontFamily: family,
      height: 1.3,
      color: theme.colorScheme.onSurface,
      fontSize: (theme.textTheme.bodyMedium?.fontSize ?? 14) * scale,
    );
    final refStyle = refStyleFor(theme, textStyle);
    final labels = footnoteLabels(entries);
    return ListView.builder(
      key: const Key('footnotes-list'),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        final prefix = labels[index];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: '$prefix  ', style: numberStyle),
                ...noteSpans(
                  entry.note.text,
                  entry.note.refs,
                  textStyle,
                  refStyle,
                  _openPreview,
                  _recognizers,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
