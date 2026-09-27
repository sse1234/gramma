import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'document_import_dialog.dart';
import 'l10n.dart';
import 'src/rust/api/library.dart';

/// The import door: picks a file and routes it by type — a SWORD zip or
/// OSIS XML into the library (ADR 0017), a JSON reading plan (ADR 0025),
/// a PDF or EPUB through the document model with its confirmation dialog
/// (ADR 0029) — and reports the outcome in a snackbar. The callbacks tell
/// the screen what to reload.
Future<void> importFromPicker(
  BuildContext context, {
  required VoidCallback onModulesChanged,
  required VoidCallback onPlansChanged,
}) async {
  final file = await openFile(
    acceptedTypeGroups: const [
      // iOS/macOS match on UTIs, the other platforms on extensions.
      // SWORD commentary packages (ADR 0017) arrive as zip files.
      XTypeGroup(
        label: 'OSIS XML / SWORD / Plan / PDF / EPUB / ODT',
        extensions: ['xml', 'osis', 'zip', 'json', 'pdf', 'epub', 'odt'],
        uniformTypeIdentifiers: [
          'public.xml',
          'public.text',
          'public.zip-archive',
          'public.json',
          'com.adobe.pdf',
          'org.idpf.epub-container',
          'org.oasis-open.opendocument.text',
        ],
      ),
    ],
  );
  if (file == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  try {
    final lower = file.path.toLowerCase();
    if (lower.endsWith('.pdf') || lower.endsWith('.epub') || lower.endsWith('.odt')) {
      await _importDocument(context, file.path, onModulesChanged);
      return;
    }
    if (lower.endsWith('.json')) {
      final plan = await importPlanFile(path: file.path);
      onPlansChanged();
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.importedPlan(plan.name, plan.days.toInt())),
        ),
      );
      return;
    }
    final imported = lower.endsWith('.zip')
        ? await importSwordFile(path: file.path)
        : await importOsisFile(path: file.path);
    onModulesChanged();
    messenger.showSnackBar(
      SnackBar(content: Text(_importedText(l10n, imported))),
    );
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(l10n.importFailed('$e'))));
  }
}

Future<void> _importDocument(
  BuildContext context,
  String path,
  VoidCallback onModulesChanged,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  messenger.showSnackBar(
    SnackBar(
      content: Text(l10n.importInspecting),
      duration: const Duration(seconds: 30),
    ),
  );
  final inspection = await inspectDocumentFile(path: path);
  messenger.hideCurrentSnackBar();
  if (!context.mounted) return;
  final choice = await showDocumentImportDialog(context, inspection);
  if (choice == null) return;
  final imported = await importDocumentFile(
    path: path,
    kind: choice.kind,
    code: choice.code,
    title: choice.title,
    subjectOsis: choice.subject,
  );
  if (!context.mounted) return;
  onModulesChanged();
  messenger.showSnackBar(
    SnackBar(content: Text(_importedText(l10n, imported))),
  );
}

String _importedText(AppLocalizations l10n, ModuleView imported) {
  final n = imported.verses.toInt();
  return switch (imported.kind) {
    'commentary' => l10n.importedCommentary(imported.title, n),
    'dictionary' => l10n.importedDictionary(imported.title, n),
    'book' => l10n.importedBook(imported.title, n),
    'devotional' => l10n.importedDevotional(imported.title, n),
    _ => l10n.importedModule(imported.title, n),
  };
}
