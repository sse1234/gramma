import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'l10n.dart';
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
    return spine
        .indexWhere((c) => c.bookOsis == parts[0] && c.chapter == chapter);
  }

  final start = indexOf(anchor);
  if (start < 0) return const [];
  var end = anchorEnd == null ? start : indexOf(anchorEnd);
  if (end < start) end = start;
  return [for (var i = start; i <= end; i++) i];
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
    final indexes =
        visibleChapterIndexes(spine, anchor, widget.followedAnchorEnd);
    if (indexes.isEmpty) return const SizedBox.shrink();
    final startVerse = _verseOf(anchor);
    final endVerse = _verseOf(widget.followedAnchorEnd ?? '');
    final multiChapter = indexes.length > 1;
    final entries = <({ChapterRefView chapter, NoteView note})>[];
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
            widget.followedAnchorEnd != null &&
            note.verse > endVerse) {
          continue;
        }
        entries.add((chapter: chapter, note: note));
      }
    }
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
    final refStyle = textStyle?.copyWith(
      color: theme.colorScheme.primary,
      decoration: TextDecoration.underline,
      decorationColor: theme.colorScheme.primary.withValues(alpha: 0.5),
    );
    return ListView.builder(
      key: const Key('footnotes-list'),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        final prefix = multiChapter
            ? '${entry.chapter.chapter},${entry.note.verse}${entry.note.label}'
            : '${entry.note.verse}${entry.note.label}';
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: '$prefix  ', style: numberStyle),
              ..._noteSpans(entry.note, textStyle, refStyle),
            ]),
          ),
        );
      },
    );
  }

  int? _verseOf(String osis) {
    final parts = osis.split('.');
    return parts.length >= 3 ? int.tryParse(parts[2]) : null;
  }

  /// The note text as spans, with scanned references tappable. Reference
  /// offsets are byte positions in UTF-8, so slicing goes through utf8.
  List<TextSpan> _noteSpans(
    NoteView note,
    TextStyle? textStyle,
    TextStyle? refStyle,
  ) {
    if (note.refs.isEmpty) {
      return [TextSpan(text: note.text, style: textStyle)];
    }
    final bytes = utf8.encode(note.text);
    final spans = <TextSpan>[];
    var cursor = 0;
    for (final ref in note.refs) {
      if (ref.start > cursor) {
        spans.add(TextSpan(
          text: utf8.decode(bytes.sublist(cursor, ref.start)),
          style: textStyle,
        ));
      }
      final recognizer = TapGestureRecognizer()
        ..onTap = () => _openPreview(ref.osis);
      _recognizers.add(recognizer);
      spans.add(TextSpan(
        text: utf8.decode(bytes.sublist(ref.start, ref.end)),
        style: refStyle,
        recognizer: recognizer,
      ));
      cursor = ref.end;
    }
    if (cursor < bytes.length) {
      spans.add(TextSpan(
        text: utf8.decode(bytes.sublist(cursor)),
        style: textStyle,
      ));
    }
    return spans;
  }
}
