import 'package:flutter/material.dart';

import 'l10n.dart';
import 'src/rust/api/library.dart';

/// What the user decided for a document import (ADR 0029).
class DocumentImportChoice {
  const DocumentImportChoice({
    required this.kind,
    required this.title,
    required this.code,
    required this.subject,
  });

  /// "bible", "commentary", or "book".
  final String kind;
  final String title;
  final String code;

  /// OSIS id of the book a commentary treats, when given.
  final String? subject;
}

/// Confirms an inspected PDF or EPUB before it enters the library: the
/// detected kind (changeable), the title, the module code, and for a
/// commentary the book it treats. Returns null when cancelled.
Future<DocumentImportChoice?> showDocumentImportDialog(
  BuildContext context,
  DocumentInspectionView inspection,
) {
  return showDialog<DocumentImportChoice>(
    context: context,
    builder: (context) => _DocumentImportDialog(inspection: inspection),
  );
}

class _DocumentImportDialog extends StatefulWidget {
  const _DocumentImportDialog({required this.inspection});

  final DocumentInspectionView inspection;

  @override
  State<_DocumentImportDialog> createState() => _DocumentImportDialogState();
}

class _DocumentImportDialogState extends State<_DocumentImportDialog> {
  late String _kind = widget.inspection.kind;
  late final TextEditingController _title = TextEditingController(
    text: widget.inspection.title,
  );
  late final TextEditingController _code = TextEditingController(
    text: moduleCodeFromTitle(title: widget.inspection.title),
  );
  late final TextEditingController _subject = TextEditingController(
    text: widget.inspection.subjectBook ?? '',
  );
  bool _codeEdited = false;

  @override
  void dispose() {
    _title.dispose();
    _code.dispose();
    _subject.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final i = widget.inspection;
    return AlertDialog(
      title: Text(l10n.importDocumentTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const Key('import-title'),
              controller: _title,
              decoration: InputDecoration(
                labelText: l10n.importDocumentTitleField,
              ),
              onChanged: (value) {
                if (!_codeEdited) {
                  _code.text = moduleCodeFromTitle(title: value);
                }
              },
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('import-code'),
              controller: _code,
              decoration: InputDecoration(
                labelText: l10n.importDocumentCodeField,
              ),
              onChanged: (_) => _codeEdited = true,
            ),
            const SizedBox(height: 12),
            Text(l10n.importDocumentKind, style: theme.textTheme.labelLarge),
            RadioGroup<String>(
              groupValue: _kind,
              onChanged: (value) => setState(() => _kind = value ?? _kind),
              child: Column(
                children: [
                  RadioListTile<String>(
                    key: const Key('import-kind-bible'),
                    value: 'bible',
                    title: Text(l10n.importKindBible),
                    dense: true,
                  ),
                  RadioListTile<String>(
                    key: const Key('import-kind-commentary'),
                    value: 'commentary',
                    title: Text(l10n.importKindCommentary),
                    dense: true,
                  ),
                  RadioListTile<String>(
                    key: const Key('import-kind-book'),
                    value: 'book',
                    title: Text(l10n.importKindBook),
                    dense: true,
                  ),
                ],
              ),
            ),
            if (_kind == 'commentary')
              TextField(
                key: const Key('import-subject'),
                controller: _subject,
                decoration: InputDecoration(
                  labelText: l10n.importDocumentSubject,
                ),
              ),
            const SizedBox(height: 12),
            Text(
              l10n.importDocumentEvidence(
                i.blocks.toInt(),
                i.headings.toInt(),
                i.chapters.toInt(),
                i.verseNumbers.toInt(),
                i.references.toInt(),
                i.notes.toInt(),
                i.images.toInt(),
              ),
              key: const Key('import-evidence'),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Text(l10n.importDocumentRights, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          key: const Key('import-confirm'),
          onPressed: () {
            final subject = _subject.text.trim();
            Navigator.of(context).pop(
              DocumentImportChoice(
                kind: _kind,
                title: _title.text.trim(),
                code: _code.text.trim(),
                subject: _kind == 'commentary' && subject.isNotEmpty
                    ? subject
                    : null,
              ),
            );
          },
          child: Text(l10n.importDocumentAction),
        ),
      ],
    );
  }
}
