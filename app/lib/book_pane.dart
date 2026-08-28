import 'package:flutter/material.dart';

import 'l10n.dart';
import 'passage_preview.dart';
import 'reader_pane.dart';
import 'run_hit.dart';
import 'settings.dart';
import 'src/rust/api/library.dart';
import 'src/rust/api/typeset.dart';
import 'typeset_prose.dart';

/// General-book view (ADR 0021): carries its own module (a RawGenBook —
/// sermons, treatises) and reads it section by section. The anchor holds
/// the section ordinal ("s:12"), synced like a reading position; a table
/// of contents jumps, arrows walk the reading order. Sections typeset
/// like everything else, references preview passages, long-pressed
/// words look up in the dictionary.
class BookPane extends StatefulWidget {
  const BookPane({
    super.key,
    required this.module,
    required this.modules,
    required this.onModule,
    required this.anchor,
    required this.onAnchor,
    required this.previewModule,
    required this.readingMode,
    required this.onToggleMode,
    required this.badge,
    required this.onOpenReference,
    this.onWordLookup,
    this.dragHandle,
    this.onClose,
  });

  final String? module;
  final List<ModuleView> modules;
  final ValueChanged<String> onModule;

  /// Section state: `s:ordinal`, or null for the first section.
  final String? anchor;
  final ValueChanged<String> onAnchor;
  final String? previewModule;
  final bool readingMode;
  final VoidCallback onToggleMode;
  final Widget? badge;
  final ValueChanged<String> onOpenReference;
  final WordLookup? onWordLookup;
  final Widget? dragHandle;
  final VoidCallback? onClose;

  @override
  State<BookPane> createState() => _BookPaneState();
}

/// The section ordinal of an anchor like "s:12".
int? bookAnchorOrdinal(String? anchor) => anchor != null &&
        anchor.startsWith('s:')
    ? int.tryParse(anchor.substring(2))
    : null;

class _BookPaneState extends State<BookPane> {
  final Map<int, BookLayoutView> _layouts = {};
  final Set<int> _pending = {};
  String _signature = '';

  void _openPreview(String osis) {
    final module = widget.previewModule;
    if (module == null) return;
    showPassagePreview(
      context,
      osis: osis,
      moduleCode: module,
      onOpen: () => widget.onOpenReference(osis),
    );
  }

  void _ensureLayout(String module, int ordinal, double ems) {
    if (_layouts.containsKey(ordinal) || _pending.contains(ordinal)) return;
    _pending.add(ordinal);
    layoutBookSection(moduleCode: module, ordinal: ordinal, measureEms: ems)
        .then((layout) {
      if (!mounted) return;
      setState(() {
        _pending.remove(ordinal);
        if (layout != null) _layouts[ordinal] = layout;
      });
    }).catchError((_) {
      if (mounted) setState(() => _pending.remove(ordinal));
    });
  }

  Future<void> _openToc(String module) async {
    final List<BookTocView> toc;
    try {
      toc = bookToc(moduleCode: module);
    } catch (_) {
      return;
    }
    if (!mounted) return;
    final current = bookAnchorOrdinal(widget.anchor) ?? 1;
    final chosen = await showDialog<int>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420, maxHeight: 520),
          child: ListView.builder(
            key: const Key('book-toc'),
            itemCount: toc.length,
            itemBuilder: (context, index) {
              final row = toc[index];
              return ListTile(
                key: Key('toc-${row.ordinal}'),
                dense: true,
                selected: row.ordinal == current,
                contentPadding: EdgeInsets.only(
                    left: 12.0 + 16.0 * (row.level - 1), right: 12),
                title: Text(row.name),
                onTap: () => Navigator.of(context).pop(row.ordinal),
              );
            },
          ),
        ),
      ),
    );
    if (chosen != null) widget.onAnchor('s:$chosen');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.readingMode) ...[
          PaneHeader(
            title: context.l10n.bookTitle,
            badge: widget.badge,
            dragHandle: widget.dragHandle,
            moduleCode: widget.module,
            modules: [
              for (final m in widget.modules)
                (code: m.code, title: m.title, strongs: m.strongs),
            ],
            onModule: widget.modules.isEmpty ? null : widget.onModule,
            followValue: null,
            followOptions: const [],
            onFollow: null,
            onClose: widget.onClose,
          ),
          const SizedBox(height: 4),
        ],
        Expanded(child: _body(theme)),
      ],
    );
  }

  Widget _body(ThemeData theme) {
    final module = widget.module;
    if (module == null || widget.modules.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            context.l10n.noBookModules,
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final ordinal = bookAnchorOrdinal(widget.anchor) ?? 1;
    final settings = SettingsScope.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final effWidth =
            width < settings.columnWidth ? width : settings.columnWidth;
        final fontSize =
            effWidth / settings.measureEms * settings.commentaryScale;
        if (width <= 0 || fontSize <= 0) return const SizedBox.shrink();
        final signature =
            '$module|${settings.fontFamily}|${fontSize.toStringAsFixed(1)}|'
            '${width.toStringAsFixed(0)}';
        if (signature != _signature) {
          _signature = signature;
          _layouts.clear();
          _pending.clear();
        }
        _ensureLayout(module, ordinal, width / fontSize);
        final section = _layouts[ordinal];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  key: const Key('book-toc-button'),
                  tooltip: context.l10n.tableOfContents,
                  icon: const Icon(Icons.toc, size: 20),
                  onPressed: () => _openToc(module),
                ),
                Expanded(
                  child: Text(
                    section?.name ?? '',
                    key: const Key('book-section-name'),
                    style: theme.textTheme.titleSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  key: const Key('book-prev'),
                  icon: const Icon(Icons.chevron_left, size: 20),
                  onPressed: section?.prevOrdinal == null
                      ? null
                      : () =>
                          widget.onAnchor('s:${section!.prevOrdinal}'),
                ),
                IconButton(
                  key: const Key('book-next'),
                  icon: const Icon(Icons.chevron_right, size: 20),
                  onPressed: section?.nextOrdinal == null
                      ? null
                      : () =>
                          widget.onAnchor('s:${section!.nextOrdinal}'),
                ),
              ],
            ),
            Expanded(
              child: section == null
                  ? const SizedBox.shrink()
                  : SingleChildScrollView(
                      key: Key('book-section-${section.ordinal}'),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 4, bottom: 12),
                        child: TypesetProse(
                          layout: ProseLayout(
                            lines: section.lines,
                            refs: section.refs,
                            unitsPerEm: section.unitsPerEm,
                            measureUnits: section.measureUnits,
                            numberScale: section.numberScale,
                            plainText: section.plainText,
                          ),
                          fontSize: fontSize,
                          lineHeightEm: settings.lineSpacing,
                          onLinkTap: _openPreview,
                          onPlainTap: widget.onToggleMode,
                          onWordLongPress: (run) {
                            final word = lookupWord(run);
                            if (word != null) {
                              widget.onWordLookup?.call(word);
                            }
                          },
                        ),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}
