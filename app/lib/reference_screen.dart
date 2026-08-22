import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'src/rust/api/library.dart';
import 'src/rust/api/references.dart';

/// Walking-skeleton reading screen: resolve a typed reference through
/// gramma-core and, once a module is imported, show the containing chapter.
class ReferenceScreen extends StatefulWidget {
  const ReferenceScreen({super.key});

  @override
  State<ReferenceScreen> createState() => _ReferenceScreenState();
}

class _ReferenceScreenState extends State<ReferenceScreen> {
  ModuleView? _active;
  String _input = '';
  ParseOutcome? _outcome;
  ChapterView? _chapter;

  @override
  void initState() {
    super.initState();
    _refreshModules();
  }

  void _refreshModules({String? select}) {
    final available = modules();
    setState(() {
      _active = available.isEmpty
          ? null
          : available.firstWhere(
              (m) => m.code == (select ?? _active?.code),
              orElse: () => available.first,
            );
    });
    _resolve(_input);
  }

  void _resolve(String input) {
    setState(() {
      _input = input;
      if (input.trim().isEmpty) {
        _outcome = null;
        _chapter = null;
        return;
      }
      _outcome = parseReference(input: input);
      final active = _active;
      _chapter = (_outcome?.osis != null && active != null)
          ? chapter(moduleCode: active.code, reference: input)
          : null;
    });
  }

  Future<void> _importOsis() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'OSIS XML', extensions: ['xml', 'osis']),
      ],
    );
    if (file == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final imported = await importOsisFile(path: file.path);
      _refreshModules(select: imported.code);
      messenger.showSnackBar(SnackBar(
        content: Text(
          'Imported ${imported.title} (${imported.verses} verses)',
        ),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Import failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final outcome = _outcome;
    final chapterView = _chapter;
    return Scaffold(
      appBar: AppBar(
        title: const Text('gramma'),
        actions: [
          IconButton(
            key: const Key('import-osis'),
            tooltip: 'Import OSIS…',
            icon: const Icon(Icons.library_add_outlined),
            onPressed: _importOsis,
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  autofocus: true,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: 'Bible reference',
                    hintText: 'Joh 3,16 · 1 Kor 13,4-7 · Ps 23',
                    helperText: _active == null
                        ? 'No module imported yet — use the library button above'
                        : _active!.title,
                  ),
                  onChanged: _resolve,
                ),
                const SizedBox(height: 16),
                if (outcome?.osis != null)
                  Text(
                    outcome!.osis!,
                    key: const Key('osis-result'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(color: theme.colorScheme.primary),
                  ),
                if (outcome?.error != null)
                  Text(
                    outcome!.error!,
                    key: const Key('parse-error'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge
                        ?.copyWith(color: theme.colorScheme.error),
                  ),
                const SizedBox(height: 8),
                if (chapterView != null && chapterView.verses.isNotEmpty)
                  Expanded(
                    child: ListView.builder(
                      key: const Key('chapter-list'),
                      itemCount: chapterView.verses.length,
                      itemBuilder: (context, index) {
                        final verse = chapterView.verses[index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text.rich(
                            TextSpan(children: [
                              TextSpan(
                                text: '${verse.verse} ',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                              TextSpan(
                                text: verse.text,
                                style: theme.textTheme.bodyLarge,
                              ),
                            ]),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
