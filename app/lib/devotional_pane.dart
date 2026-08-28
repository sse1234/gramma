import 'package:flutter/material.dart';

import 'l10n.dart';
import 'passage_preview.dart';
import 'reader_pane.dart';
import 'run_hit.dart';
import 'settings.dart';
import 'src/rust/api/library.dart';
import 'src/rust/api/typeset.dart';
import 'typeset_prose.dart';

/// Daily-devotional view (ADR 0021): a general book keyed by the day of
/// the year. Shows the day's readings (morning and evening sections),
/// defaults to today, and walks days with the arrows. The anchor holds
/// the day ("d:0101"), synced like a reading position.
class DevotionalPane extends StatefulWidget {
  const DevotionalPane({
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

  /// Day state: "d:MMDD", or null for today.
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
  State<DevotionalPane> createState() => _DevotionalPaneState();
}

/// The (month, day) of an anchor like "d:0101", or null.
(int, int)? devotionalAnchorDay(String? anchor) {
  if (anchor == null || !anchor.startsWith('d:')) return null;
  final raw = int.tryParse(anchor.substring(2));
  if (raw == null) return null;
  final month = raw ~/ 100;
  final day = raw % 100;
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  return (month, day);
}

class _DevotionalPaneState extends State<DevotionalPane> {
  final Map<int, List<DictLayoutView>> _layouts = {};
  final Set<int> _pending = {};
  String _signature = '';

  (int, int) get _day {
    final anchored = devotionalAnchorDay(widget.anchor);
    if (anchored != null) return anchored;
    final now = DateTime.now();
    return (now.month, now.day);
  }

  /// Walk [delta] days on the leap-year calendar (every date exists).
  void _step(int delta) {
    final (month, day) = _day;
    final date = DateTime(2024, month, day).add(Duration(days: delta));
    widget.onAnchor('d:${date.month * 100 + date.day}');
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

  void _ensureLayout(String module, int month, int day, double ems) {
    final key = month * 100 + day;
    if (_layouts.containsKey(key) || _pending.contains(key)) return;
    _pending.add(key);
    layoutDevotionalDay(
      moduleCode: module,
      month: month,
      day: day,
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
            title: context.l10n.devotionalTitle,
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
            context.l10n.noDevotionalModules,
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final (month, day) = _day;
    final settings = SettingsScope.of(context);
    final locale = Localizations.localeOf(context).toString();
    final dateLabel = MaterialLocalizations.of(context)
        .formatShortMonthDay(DateTime(2024, month, day));
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final effWidth =
            width < settings.columnWidth ? width : settings.columnWidth;
        final fontSize =
            effWidth / settings.measureEms * settings.commentaryScale;
        if (width <= 0 || fontSize <= 0) return const SizedBox.shrink();
        final signature =
            '$module|$locale|${settings.fontFamily}|'
            '${fontSize.toStringAsFixed(1)}|${width.toStringAsFixed(0)}';
        if (signature != _signature) {
          _signature = signature;
          _layouts.clear();
          _pending.clear();
        }
        _ensureLayout(module, month, day, width / fontSize);
        final entries = _layouts[month * 100 + day];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  key: const Key('devo-prev'),
                  icon: const Icon(Icons.chevron_left, size: 20),
                  onPressed: () => _step(-1),
                ),
                Expanded(
                  child: Text(
                    dateLabel,
                    key: const Key('devo-date'),
                    style: theme.textTheme.titleSmall,
                    textAlign: TextAlign.center,
                  ),
                ),
                IconButton(
                  key: const Key('devo-today'),
                  tooltip: context.l10n.today,
                  icon: const Icon(Icons.today, size: 18),
                  onPressed: () {
                    final now = DateTime.now();
                    widget.onAnchor('d:${now.month * 100 + now.day}');
                  },
                ),
                IconButton(
                  key: const Key('devo-next'),
                  icon: const Icon(Icons.chevron_right, size: 20),
                  onPressed: () => _step(1),
                ),
              ],
            ),
            Expanded(
              child: entries == null
                  ? const SizedBox.shrink()
                  : entries.isEmpty
                      ? Center(
                          child: Text(
                            context.l10n.noDictionaryResults,
                            key: const Key('devo-empty'),
                            style: theme.textTheme.bodyMedium,
                          ),
                        )
                      : ListView(
                          key: const Key('devo-list'),
                          children: [
                            for (final entry in entries)
                              Padding(
                                key: Key('devo-entry-${entry.sort}'),
                                padding:
                                    const EdgeInsets.only(top: 4, bottom: 12),
                                child: TypesetProse(
                                  layout: ProseLayout.ofDict(entry),
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
                          ],
                        ),
            ),
          ],
        );
      },
    );
  }
}
