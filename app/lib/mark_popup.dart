import 'package:flutter/material.dart';

import 'annotations.dart';
import 'l10n.dart';
import 'palette.dart';

/// The note/marker popup (ADR 0023): HCL color swatches, an optional
/// note text, save — and delete for existing marks. An empty text saves
/// a pure color mark.
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
  late final TextEditingController _text =
      TextEditingController(text: widget.draft.text);
  late int _color = widget.draft.colorIndex;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
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
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (var i = 0; i < markColorCount; i++)
                    InkWell(
                      key: Key('mark-color-$i'),
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => setState(() => _color = i),
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: markColor(i, brightness),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: i == _color
                                ? theme.colorScheme.onSurface
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('mark-text'),
                controller: _text,
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
                    onPressed: () {
                      Navigator.of(context).pop();
                      widget.onSave(NoteMark(
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
                      ));
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
