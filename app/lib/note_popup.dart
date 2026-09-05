import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'footnotes_pane.dart' show FootnoteEntry, footnoteLabels;
import 'l10n.dart';
import 'note_text.dart';
import 'passage_preview.dart';
import 'settings.dart';

/// The footnote popup (ADR 0016, 0028): tapping a note marker opens the
/// footnotes of the view's visible range, the tapped one highlighted and
/// scrolled into view — the reader sees every letter on the page
/// resolved at once. References inside a note navigate within the popup:
/// a passage page replaces the list, a back arrow returns to it.
/// `onOpenReference` jumps the reading view.
Future<void> showNotePopup(
  BuildContext context, {
  required List<FootnoteEntry> entries,
  required int selected,
  required String title,
  required String previewModule,
  required ValueChanged<String> onOpenReference,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _NotePopup(
      entries: entries,
      selected: selected,
      title: title,
      previewModule: previewModule,
      onOpenReference: onOpenReference,
    ),
  );
}

class _NotePopup extends StatefulWidget {
  const _NotePopup({
    required this.entries,
    required this.selected,
    required this.title,
    required this.previewModule,
    required this.onOpenReference,
  });

  final List<FootnoteEntry> entries;
  final int selected;
  final String title;
  final String previewModule;
  final ValueChanged<String> onOpenReference;

  @override
  State<_NotePopup> createState() => _NotePopupState();
}

class _NotePopupState extends State<_NotePopup> {
  /// The reference shown on the passage page, or null for the list.
  String? _osis;
  final List<TapGestureRecognizer> _recognizers = [];
  final GlobalKey _selectedKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _selectedKey.currentContext;
      if (target != null) {
        Scrollable.ensureVisible(target, alignment: 0.2);
      }
    });
  }

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = SettingsScope.of(context);
    final osis = _osis;
    final textStyle = theme.textTheme.bodyMedium?.copyWith(
      fontFamily: settings.fontFamily,
      height: 1.3,
      color: theme.colorScheme.onSurface,
      fontSize:
          (theme.textTheme.bodyMedium?.fontSize ?? 14) * settings.previewScale,
    );
    final labelStyle = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.primary,
      fontFamily: settings.fontFamily,
      fontSize:
          (theme.textTheme.labelMedium?.fontSize ?? 12) * settings.previewScale,
    );
    final refStyle = refStyleFor(theme, textStyle);
    final labels = footnoteLabels(widget.entries);
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 460),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (osis != null)
                    IconButton(
                      key: const Key('note-back'),
                      tooltip: context.l10n.back,
                      icon: const Icon(Icons.arrow_back, size: 18),
                      onPressed: () => setState(() => _osis = null),
                    ),
                  Expanded(
                    child: Text(
                      osis == null
                          ? widget.title
                          : previewTitle(osis, widget.previewModule),
                      key: const Key('note-title'),
                      style: theme.textTheme.titleSmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (osis != null)
                    TextButton.icon(
                      key: const Key('note-open'),
                      onPressed: () {
                        Navigator.of(context).pop();
                        widget.onOpenReference(osis);
                      },
                      icon: const Icon(Icons.open_in_new, size: 16),
                      label: Text(context.l10n.open),
                    ),
                  IconButton(
                    key: const Key('note-close'),
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Flexible(
                child: osis == null
                    ? SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final (i, entry) in widget.entries.indexed)
                              Container(
                                key: i == widget.selected
                                    ? _selectedKey
                                    : Key('note-entry-$i'),
                                margin: const EdgeInsets.only(bottom: 4),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 6,
                                ),
                                decoration: i == widget.selected
                                    ? BoxDecoration(
                                        color: theme.colorScheme.primary
                                            .withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(6),
                                      )
                                    : null,
                                child: Text.rich(
                                  TextSpan(
                                    children: [
                                      TextSpan(
                                        text: '${labels[i]}  ',
                                        style: labelStyle,
                                      ),
                                      ...noteSpans(
                                        entry.note.text,
                                        entry.note.refs,
                                        textStyle,
                                        refStyle,
                                        (ref) => setState(() => _osis = ref),
                                        _recognizers,
                                      ),
                                    ],
                                  ),
                                  key: i == widget.selected
                                      ? const Key('note-body')
                                      : null,
                                ),
                              ),
                          ],
                        ),
                      )
                    : PassageList(osis: osis, moduleCode: widget.previewModule),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
