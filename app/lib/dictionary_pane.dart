import 'dart:convert';

import 'package:flutter/material.dart';

import 'l10n.dart';
import 'passage_preview.dart';
import 'reader_pane.dart';
import 'run_hit.dart';
import 'settings.dart';
import 'src/rust/api/library.dart';
import 'src/rust/api/references.dart';
import 'src/rust/api/typeset.dart';
import 'typeset_prose.dart';

/// Dictionary/lexicon view (ADR 0019): carries its own module (a Strong's
/// lexicon) and a lookup state instead of a position link. The state
/// lives in the pane's anchor — "G26" shows that entry, "q:Liebe" shows
/// search results — so the desk remembers and syncs it like any reading
/// position. Long-pressing a word in any text or commentary view routes
/// it here as a search; entries are typeset like everything else, with
/// verse references previewing their passage.
class DictionaryPane extends StatefulWidget {
  const DictionaryPane({
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
    this.dragHandle,
    this.onClose,
  });

  /// The dictionary module shown, and the installed dictionaries.
  final String? module;
  final List<ModuleView> modules;
  final ValueChanged<String> onModule;

  /// Lookup state: "G26" (an entry) or "q:term" (a search), or null.
  final String? anchor;
  final ValueChanged<String> onAnchor;

  /// Module resolving verse references found in entries.
  final String? previewModule;

  final bool readingMode;
  final VoidCallback onToggleMode;
  final Widget? badge;

  /// Navigate a text view to a reference (from a preview).
  final ValueChanged<String> onOpenReference;
  final Widget? dragHandle;
  final VoidCallback? onClose;

  @override
  State<DictionaryPane> createState() => _DictionaryPaneState();
}

/// The entry sort key of an anchor like "G26", "26", or "00026".
int? dictAnchorSort(String? anchor) {
  if (anchor == null) return null;
  final m = RegExp(r'^[Gg]?0*(\d+)$').firstMatch(anchor.trim());
  return m == null ? null : int.tryParse(m.group(1)!);
}

/// The search term of an anchor like "q:Liebe".
String? dictAnchorQuery(String? anchor) =>
    anchor != null && anchor.startsWith('q:') ? anchor.substring(2) : null;

/// The Strong number of a concordance anchor like "c:G26".
String? dictAnchorStrong(String? anchor) =>
    anchor != null && anchor.startsWith('c:') ? anchor.substring(2) : null;

class _DictionaryPaneState extends State<DictionaryPane> {
  final TextEditingController _search = TextEditingController();
  final Map<int, DictLayoutView> _layouts = {};
  final Set<int> _pending = {};
  String _signature = '';

  /// The pane's own lookup history (ADR 0020): every anchor it showed,
  /// navigated by the header arrows — entries, searches, concordances.
  final List<String> _history = [];
  int _cursor = -1;
  int? _pendingCursor;

  @override
  void initState() {
    super.initState();
    _record(widget.anchor);
    _syncSearchField();
  }

  @override
  void didUpdateWidget(DictionaryPane old) {
    super.didUpdateWidget(old);
    if (old.anchor != widget.anchor) {
      final pending = _pendingCursor;
      if (pending != null &&
          pending < _history.length &&
          _history[pending] == widget.anchor) {
        _cursor = pending;
      } else {
        _record(widget.anchor);
      }
      _pendingCursor = null;
      _syncSearchField();
    }
  }

  void _record(String? anchor) {
    if (anchor == null) return;
    if (_cursor >= 0 && _history[_cursor] == anchor) return;
    _history.removeRange(_cursor + 1, _history.length);
    _history.add(anchor);
    _cursor = _history.length - 1;
  }

  void _goHistory(int delta) {
    final target = _cursor + delta;
    if (target < 0 || target >= _history.length) return;
    _pendingCursor = target;
    widget.onAnchor(_history[target]);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _syncSearchField() {
    final query = dictAnchorQuery(widget.anchor);
    if (query != null && _search.text != query) _search.text = query;
  }

  void _submit(String raw) {
    FocusManager.instance.primaryFocus?.unfocus();
    final input = raw.trim();
    if (input.isEmpty) return;
    final sort = dictAnchorSort(input);
    widget.onAnchor(sort != null ? 'G$sort' : 'q:$input');
  }

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

  void _ensureLayout(String module, int sort, double ems) {
    if (_layouts.containsKey(sort) || _pending.contains(sort)) return;
    _pending.add(sort);
    layoutDictEntry(moduleCode: module, sort: sort, measureEms: ems)
        .then((layout) {
      if (!mounted) return;
      setState(() {
        _pending.remove(sort);
        if (layout != null) _layouts[sort] = layout;
      });
    }).catchError((_) {
      if (mounted) setState(() => _pending.remove(sort));
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
            title: context.l10n.dictionaryTitle,
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
      return _hint(theme, context.l10n.noDictionaryModules);
    }
    final sort = dictAnchorSort(widget.anchor);
    final query = dictAnchorQuery(widget.anchor);
    final strong = dictAnchorStrong(widget.anchor);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const Key('dict-search'),
                controller: _search,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search, size: 18),
                  hintText: context.l10n.dictionarySearchLabel,
                ),
                onSubmitted: _submit,
              ),
            ),
            // Back/forward through the pane's lookup history.
            IconButton(
              key: const Key('dict-prev'),
              icon: const Icon(Icons.chevron_left, size: 20),
              onPressed: _cursor > 0 ? () => _goHistory(-1) : null,
            ),
            IconButton(
              key: const Key('dict-next'),
              icon: const Icon(Icons.chevron_right, size: 20),
              onPressed:
                  _cursor < _history.length - 1 ? () => _goHistory(1) : null,
            ),
          ],
        ),
        const SizedBox(height: 6),
        Expanded(
          child: strong != null
              ? _concordanceView(theme, strong)
              : sort != null
                  ? _entryView(theme, module, sort)
                  : query != null
                      ? _resultsView(theme, module, query)
                      : GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTap: widget.onToggleMode,
                          child:
                              _hint(theme, context.l10n.searchDictionaryHint),
                        ),
        ),
      ],
    );
  }

  Widget _resultsView(ThemeData theme, String module, String query) {
    final List<DictHitView> hits;
    try {
      hits = dictSearch(moduleCode: module, query: query);
    } catch (_) {
      return _hint(theme, context.l10n.noDictionaryResults);
    }
    if (hits.isEmpty) {
      return _hint(
        theme,
        context.l10n.noDictionaryResults,
        key: const Key('dict-empty'),
      );
    }
    final family = SettingsScope.of(context).fontFamily;
    return ListView.builder(
      key: const Key('dict-results'),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: hits.length,
      itemBuilder: (context, index) {
        final hit = hits[index];
        return ListTile(
          key: Key('dict-hit-${hit.sort}'),
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          leading: Text(
            hit.displayKey,
            style: theme.textTheme.labelMedium
                ?.copyWith(color: theme.colorScheme.primary),
          ),
          title: Text(hit.headword, style: TextStyle(fontFamily: family)),
          subtitle: hit.pron.isEmpty ? null : Text(hit.pron),
          onTap: () {
            FocusManager.instance.primaryFocus?.unfocus();
            widget.onAnchor('G${hit.sort}');
          },
        );
      },
    );
  }

  /// The concordance (ADR 0020): every occurrence of [strong] in the
  /// first Strong's-tagged Bible, each previewing its passage.
  Widget _concordanceView(ThemeData theme, String strong) {
    final ConcordanceResult result;
    try {
      result = concordanceOf(strong: strong, limit: 500);
    } catch (_) {
      return _hint(theme, context.l10n.noConcordanceSource);
    }
    if (result.module == null) {
      return _hint(
        theme,
        context.l10n.noConcordanceSource,
        key: const Key('no-concordance-source'),
      );
    }
    if (result.hits.isEmpty) {
      return _hint(
        theme,
        context.l10n.noDictionaryResults,
        key: const Key('concordance-empty'),
      );
    }
    final family = SettingsScope.of(context).fontFamily;
    final refStyle = theme.textTheme.labelMedium
        ?.copyWith(color: theme.colorScheme.primary);
    final textStyle = theme.textTheme.bodyMedium
        ?.copyWith(fontFamily: family, height: 1.3);
    // The linked words carry a wash, not weight (ADR 0023).
    final strongStyle = textStyle?.copyWith(
        backgroundColor: theme.colorScheme.primary.withValues(
            alpha: theme.brightness == Brightness.light ? 0.16 : 0.28));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            '$strong · ${result.hits.length} · ${result.module}',
            key: const Key('concordance-count'),
            style: theme.textTheme.titleSmall,
          ),
        ),
        Expanded(
          child: ListView.builder(
            key: const Key('concordance-list'),
            keyboardDismissBehavior:
                ScrollViewKeyboardDismissBehavior.onDrag,
            itemCount: result.hits.length,
            itemBuilder: (context, index) {
              final hit = result.hits[index];
              final osis = '${hit.bookOsis}.${hit.chapter}.${hit.verse}';
              final bytes = utf8.encode(hit.text);
              String slice(int a, int b) =>
                  utf8.decode(bytes.sublist(a.clamp(0, bytes.length),
                      b.clamp(0, bytes.length)));
              return InkWell(
                key: Key('occ-$index'),
                onTap: () => _openPreview(osis),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(
                        text: '${formatReference(osis: osis)}  ',
                        style: refStyle,
                      ),
                      TextSpan(
                          text: slice(0, hit.start), style: textStyle),
                      TextSpan(
                        text: slice(hit.start, hit.end),
                        style: strongStyle,
                      ),
                      TextSpan(
                          text: slice(hit.end, bytes.length),
                          style: textStyle),
                    ]),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _entryView(ThemeData theme, String module, int sort) {
    final settings = SettingsScope.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        // The Bible text's glyph size, exactly as in the commentary view
        // (ADR 0018): parity by construction, free measure.
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
        _ensureLayout(module, sort, width / fontSize);
        final entry = _layouts[sort];
        if (entry == null) {
          return _pending.contains(sort)
              ? const SizedBox.shrink()
              : _hint(
                  theme,
                  context.l10n.noDictionaryResults,
                  key: const Key('dict-missing'),
                );
        }
        return SingleChildScrollView(
          key: Key('dict-entry-${entry.sort}'),
          keyboardDismissBehavior:
              ScrollViewKeyboardDismissBehavior.onDrag,
          child: Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 12),
            child: TypesetProse(
              layout: ProseLayout.ofDict(entry),
              fontSize: fontSize,
              lineHeightEm: settings.lineSpacing,
              onLinkTap: _openPreview,
              onPlainTap: widget.onToggleMode,
              onWordLongPress: (run) {
                final word = lookupWord(run);
                if (word != null) widget.onAnchor('q:$word');
              },
              onLabelTap: () =>
                  widget.onAnchor('c:${entry.displayKey}'),
            ),
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
}
