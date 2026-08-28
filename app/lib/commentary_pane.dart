import 'package:flutter/material.dart';

import 'footnotes_pane.dart' show visibleChapterIndexes;
import 'l10n.dart';
import 'passage_preview.dart';
import 'run_hit.dart';
import 'reader_pane.dart';
import 'settings.dart';
import 'src/rust/api/library.dart';
import 'src/rust/api/typeset.dart';
import 'typeset_prose.dart';

/// Receiver view for a commentary module (ADR 0017): follows a text view's
/// reading position and shows the commentary sections covering the visible
/// verses. Unlike the footnotes pane it carries its own module — the
/// commentary — while the followed pane provides position and chapter
/// spine.
///
/// Commentary is long-form reading, so entries are typeset by the
/// Knuth–Plass engine like the Bible text (ADR 0018) — at the pane's own
/// measure, which reflows freely with pane width and the commentary text
/// size setting. References are tappable runs previewing their passage.
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
    this.onWordLookup,
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

  /// A long-pressed word, stripped for dictionary lookup (ADR 0019).
  final WordLookup? onWordLookup;

  @override
  State<CommentaryPane> createState() => _CommentaryPaneState();
}

class _CommentaryPaneState extends State<CommentaryPane> {
  List<ChapterRefView>? _spine;
  String? _spineModule;

  /// Typeset entry layouts per "Book.Ch", valid for [_signature] — module,
  /// typeface, text size, and pane measure all shape the layout.
  final Map<String, List<CommentLayoutView>> _layouts = {};
  final Set<String> _pending = {};
  String _signature = '';

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

  void _ensureLayout(String module, String book, int chapter, double ems) {
    final key = '$book.$chapter';
    if (_layouts.containsKey(key) || _pending.contains(key)) return;
    _pending.add(key);
    layoutComments(
      moduleCode: module,
      bookOsis: book,
      chapter: chapter,
      measureEms: ems,
    ).then((layouts) {
      if (!mounted) return;
      setState(() {
        _pending.remove(key);
        _layouts[key] = layouts;
      });
    }).catchError((_) {
      if (!mounted) return;
      setState(() {
        _pending.remove(key);
        _layouts[key] = const [];
      });
    });
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
    final settings = SettingsScope.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        // The Bible text's own glyph size — a canonical column's em,
        // min(pane width, column width) / measure — so reader and
        // commentary set the same face at the same size and leading;
        // the commentary scale multiplies from that parity point. Only
        // the measure stays free: it reflows with the pane (ADR 0018).
        final effWidth =
            width < settings.columnWidth ? width : settings.columnWidth;
        final fontSize =
            effWidth / settings.measureEms * settings.commentaryScale;
        if (width <= 0 || fontSize <= 0) return const SizedBox.shrink();
        final ems = width / fontSize;
        final signature =
            '$module|${settings.fontFamily}|${fontSize.toStringAsFixed(1)}|'
            '${width.toStringAsFixed(0)}';
        if (signature != _signature) {
          _signature = signature;
          _layouts.clear();
          _pending.clear();
        }
        final startVerse = _verseOf(anchor);
        final endVerse = _verseOf(widget.followedAnchorEnd ?? '');
        final multiChapter = indexes.length > 1;
        var loading = false;
        final items = <Widget>[];
        for (final index in indexes) {
          final chapter = spine[index];
          final key = '${chapter.bookOsis}.${chapter.chapter}';
          _ensureLayout(module, chapter.bookOsis, chapter.chapter, ems);
          final layouts = _layouts[key];
          if (layouts == null) {
            loading = true;
            continue;
          }
          final visible = layouts.where((c) {
            // An entry is shown while any of its verses is visible.
            if (index == indexes.first &&
                startVerse != null &&
                c.verseEnd < startVerse) {
              return false;
            }
            if (index == indexes.last &&
                endVerse != null &&
                widget.followedAnchorEnd != null &&
                c.verseStart > endVerse) {
              return false;
            }
            return true;
          }).toList();
          if (multiChapter && visible.isNotEmpty) {
            items.add(Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 4),
              child: Text(chapter.heading, style: theme.textTheme.titleSmall),
            ));
          }
          for (final entry in visible) {
            items.add(Padding(
              key: Key('comment-$key.${entry.verseStart}'),
              padding: const EdgeInsets.only(top: 6, bottom: 10),
              child: TypesetProse(
                layout: ProseLayout.ofComment(entry),
                fontSize: fontSize,
                lineHeightEm: settings.lineSpacing,
                onLinkTap: _openPreview,
                onPlainTap: widget.onToggleMode,
                onWordLongPress: (run) {
                  final word = lookupWord(run);
                  if (word != null) widget.onWordLookup?.call(word);
                },
              ),
            ));
          }
        }
        if (items.isEmpty) {
          if (loading) return const SizedBox.shrink();
          return _hint(
            theme,
            context.l10n.noCommentary,
            key: const Key('no-commentary'),
          );
        }
        return ListView(
          key: const Key('commentary-list'),
          children: items,
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
