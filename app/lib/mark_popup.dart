import 'package:flutter/material.dart';

import 'annotations.dart';
import 'l10n.dart';
import 'pen_editor.dart';
import 'pens.dart';

/// The note/marker popup (ADR 0023, 0035): the reader's pens, "note
/// only" for a note shown by its icon alone, an optional note text,
/// save — and delete for existing marks. An empty text saves a pure
/// color mark; a note without a pen needs text.
Future<void> showMarkPopup(
  BuildContext context, {
  required String title,
  required NoteMark draft,
  required bool isNew,
  required ValueChanged<NoteMark> onSave,
  VoidCallback? onDelete,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _MarkDialog(
      title: title,
      draft: draft,
      isNew: isNew,
      onSave: onSave,
      onDelete: onDelete,
    ),
  );
}

class _MarkDialog extends StatefulWidget {
  const _MarkDialog({
    required this.title,
    required this.draft,
    required this.isNew,
    required this.onSave,
    this.onDelete,
  });

  final String title;
  final NoteMark draft;
  final bool isNew;
  final ValueChanged<NoteMark> onSave;
  final VoidCallback? onDelete;

  @override
  State<_MarkDialog> createState() => _MarkDialogState();
}

class _MarkDialogState extends State<_MarkDialog> {
  late final TextEditingController _text = TextEditingController(
    text: widget.draft.text,
  );
  late int _color = widget.draft.colorIndex;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.title, style: theme.textTheme.titleSmall),
              const SizedBox(height: 12),
              ValueListenableBuilder<int>(
                valueListenable: Pens.revision,
                builder: (context, _, _) => Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (var i = 0; i < Pens.count; i++)
                      InkWell(
                        key: Key('mark-color-$i'),
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => setState(() => _color = i),
                        onLongPress: () => showPenEditor(context, i),
                        child: PenSwatch(
                          pen: Pens.of(i),
                          selected: i == _color,
                        ),
                      ),
                    Tooltip(
                      message: context.l10n.noteOnly,
                      child: InkWell(
                        key: const Key('mark-color-none'),
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => setState(() => _color = Pens.none),
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _color == Pens.none
                                  ? theme.colorScheme.onSurface
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: Icon(
                            Icons.sticky_note_2_outlined,
                            size: 16,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      key: const Key('mark-pen-edit'),
                      tooltip: context.l10n.editPen,
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.tune, size: 18),
                      onPressed: _color == Pens.none
                          ? null
                          : () => showPenEditor(context, _color),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('mark-text'),
                controller: _text,
                onChanged: (_) => setState(() {}),
                minLines: 2,
                maxLines: 6,
                decoration: InputDecoration(
                  hintText: context.l10n.noteHint,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  if (!widget.isNew)
                    TextButton(
                      key: const Key('mark-delete'),
                      onPressed: () {
                        Navigator.of(context).pop();
                        widget.onDelete?.call();
                      },
                      child: Text(
                        context.l10n.deleteNote,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(context.l10n.cancel),
                  ),
                  FilledButton(
                    key: const Key('mark-save'),
                    // A note without a pen is its text: nothing to show
                    // without one.
                    onPressed: _color == Pens.none && _text.text.trim().isEmpty
                        ? null
                        : () {
                            Navigator.of(context).pop();
                            widget.onSave(
                              NoteMark(
                                id: widget.draft.id,
                                module: widget.draft.module,
                                bookOsis: widget.draft.bookOsis,
                                chapter: widget.draft.chapter,
                                verseStart: widget.draft.verseStart,
                                verseEnd: widget.draft.verseEnd,
                                startOffset: widget.draft.startOffset,
                                endOffset: widget.draft.endOffset,
                                colorIndex: _color,
                                text: _text.text.trim(),
                                created: widget.draft.created,
                              ),
                            );
                          },
                    child: Text(context.l10n.save),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
