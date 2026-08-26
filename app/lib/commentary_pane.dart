import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'footnotes_pane.dart' show visibleChapterIndexes;
import 'l10n.dart';
import 'note_text.dart';
import 'passage_preview.dart';
import 'reader_pane.dart';
import 'settings.dart';
import 'src/rust/api/library.dart';

/// Receiver view for a commentary module (ADR 0017): follows a text view's
/// reading position and shows the commentary sections covering the visible
/// verses. Unlike the footnotes pane it carries its own module — the
/// commentary — while the followed pane provides position and chapter
/// spine. References inside entries preview their passage in a popup.
class CommentaryPane extends StatefulWidget {
  const CommentaryPane({
    super.key,
    required this.module,
    required this.modules,
    required this.onModule,
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

  /// The commentary module shown, and the installed commentaries.
  final String? module;
  final List<ModuleView> modules;
  final ValueChanged<String> onModule;

  /// Canonical "Book.Ch.V" bounds of the followed pane's visible range.
  final String? followedAnchor;
  final String? followedAnchorEnd;

  /// Module code of the followed pane, providing the chapter spine.
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
  State<CommentaryPane> createState() => _CommentaryPaneState();
}

class _CommentaryPaneState extends State<CommentaryPane> {
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
            title: context.l10n.commentaryTitle,
            badge: widget.badge,
            dragHandle: widget.dragHandle,
            moduleCode: widget.module,
            modules: [
              for (final m in widget.modules)
                (code: m.code, title: m.title),
            ],
            onModule: widget.modules.isEmpty ? null : widget.onModule,
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
    final module = widget.module;
    if (module == null || widget.modules.isEmpty) {
      return _hint(theme, context.l10n.noCommentaryModules);
    }
    final anchor = widget.followedAnchor;
    final sourceModule = widget.sourceModule;
    if (anchor == null || sourceModule == null) {
      return _hint(theme, context.l10n.linkCommentaryHint);
    }
    final spine = _spineFor(sourceModule);
    final indexes =
        visibleChapterIndexes(spine, anchor, widget.followedAnchorEnd);
    if (indexes.isEmpty) return const SizedBox.shrink();
    final startVerse = _verseOf(anchor);
    final endVerse = _verseOf(widget.followedAnchorEnd ?? '');
    final multiChapter = indexes.length > 1;
    final entries = <({ChapterRefView chapter, CommentView comment})>[];
    for (final index in indexes) {
      final chapter = spine[index];
      final List<CommentView> comments;
      try {
        comments = chapterComments(
          moduleCode: module,
          bookOsis: chapter.bookOsis,
          chapter: chapter.chapter,
        );
      } catch (_) {
        continue;
      }
      for (final comment in comments) {
        // An entry is shown while any of its verses is visible.
        if (index == indexes.first &&
            startVerse != null &&
            comment.verseEnd < startVerse) {
          continue;
        }
        if (index == indexes.last &&
            endVerse != null &&
            widget.followedAnchorEnd != null &&
            comment.verseStart > endVerse) {
          continue;
        }
        entries.add((chapter: chapter, comment: comment));
      }
    }
    if (entries.isEmpty) {
      return _hint(
        theme,
        context.l10n.noCommentary,
        key: const Key('no-commentary'),
      );
    }
    final settings = SettingsScope.of(context);
    final scale = settings.footnoteScale;
    final family = settings.fontFamily;
    final headingStyle = theme.textTheme.titleSmall?.copyWith(
      fontFamily: family,
      fontSize: (theme.textTheme.titleSmall?.fontSize ?? 14) * scale,
    );
    final rangeStyle = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.primary,
      fontFamily: family,
      fontSize: (theme.textTheme.labelMedium?.fontSize ?? 12) * scale,
    );
    final textStyle = theme.textTheme.bodyMedium?.copyWith(
      fontFamily: family,
      height: 1.35,
      color: theme.colorScheme.onSurface,
      fontSize: (theme.textTheme.bodyMedium?.fontSize ?? 14) * scale,
    );
    final refStyle = refStyleFor(theme, textStyle);
    return ListView.builder(
      key: const Key('commentary-list'),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        final c = entry.comment;
        final verses = c.verseStart == c.verseEnd
            ? '${c.verseStart}'
            : '${c.verseStart}-${c.verseEnd}';
        final range = multiChapter
            ? '${entry.chapter.chapter},$verses'
            : verses;
        return Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(children: [
                  TextSpan(text: '$range  ', style: rangeStyle),
                  if (c.heading != null)
                    TextSpan(text: c.heading, style: headingStyle),
                ]),
              ),
              const SizedBox(height: 4),
              Text.rich(
                TextSpan(
                  children: noteSpans(c.text, c.refs, textStyle, refStyle,
                      _openPreview, _recognizers),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _hint(ThemeData theme, String message, {Key? key}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          message,
          key: key,
          style: theme.textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  int? _verseOf(String osis) {
    final parts = osis.split('.');
    return parts.length >= 3 ? int.tryParse(parts[2]) : null;
  }
}
