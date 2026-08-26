import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'l10n.dart';
import 'note_text.dart';
import 'passage_preview.dart';
import 'settings.dart';
import 'src/rust/api/library.dart';

/// The inline note popup (ADR 0016): tapping a note marker in the text
/// opens the footnote right there. References inside the note navigate
/// within the same popup — a passage page replaces the note, with a
/// back arrow returning to it. `onOpenReference` jumps the reading view.
Future<void> showNotePopup(
  BuildContext context, {
  required NoteView note,
  required String title,
  required String previewModule,
  required ValueChanged<String> onOpenReference,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _NotePopup(
      note: note,
      title: title,
      previewModule: previewModule,
      onOpenReference: onOpenReference,
    ),
  );
}

class _NotePopup extends StatefulWidget {
  const _NotePopup({
    required this.note,
    required this.title,
    required this.previewModule,
    required this.onOpenReference,
  });

  final NoteView note;
  final String title;
  final String previewModule;
  final ValueChanged<String> onOpenReference;

  @override
  State<_NotePopup> createState() => _NotePopupState();
}

class _NotePopupState extends State<_NotePopup> {
  /// The reference shown on the passage page, or null for the note page.
  String? _osis;
  final List<TapGestureRecognizer> _recognizers = [];

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
                        child: Text.rich(
                          TextSpan(
                            children: noteSpans(
                              widget.note.text,
                              widget.note.refs,
                              textStyle,
                              refStyleFor(theme, textStyle),
                              (ref) => setState(() => _osis = ref),
                              _recognizers,
                            ),
                          ),
                          key: const Key('note-body'),
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
