import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import 'src/rust/api/library.dart';
import 'src/rust/api/references.dart';
import 'src/rust/api/typeset.dart';
import 'typeset_chapter.dart';

/// Endless-scrolling reader: the module's chapter spine backs a lazily
/// loaded continuous text stream; the reference field jumps to a position.
class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key});

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  ModuleView? _active;
  List<ChapterRefView> _spine = const [];
  final Map<int, ChapterLayoutView> _chapterCache = {};
  final ItemScrollController _scroll = ItemScrollController();
  final ItemPositionsListener _positions = ItemPositionsListener.create();
  int? _topIndex;
  ParseOutcome? _outcome;
  String? _jumpMiss;

  @override
  void initState() {
    super.initState();
    _positions.itemPositions.addListener(_onPositionsChanged);
    _refreshModules();
  }

  @override
  void dispose() {
    _positions.itemPositions.removeListener(_onPositionsChanged);
    super.dispose();
  }

  void _onPositionsChanged() {
    final positions = _positions.itemPositions.value;
    if (positions.isEmpty) return;
    final top = positions
        .where((p) => p.itemTrailingEdge > 0)
        .fold<int?>(null, (min, p) => min == null || p.index < min ? p.index : min);
    if (top != null && top != _topIndex) {
      setState(() => _topIndex = top);
    }
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
      _spine = _active == null ? const [] : contents(moduleCode: _active!.code);
      _chapterCache.clear();
      _topIndex = _spine.isEmpty ? null : 0;
    });
  }

  ChapterLayoutView _layoutFor(int index) {
    return _chapterCache.putIfAbsent(index, () {
      final entry = _spine[index];
      return layoutChapter(
        moduleCode: _active!.code,
        bookOsis: entry.bookOsis,
        chapter: entry.chapter,
      );
    });
  }

  void _onInput(String input) {
    setState(() {
      _jumpMiss = null;
      _outcome = input.trim().isEmpty ? null : parseReference(input: input);
    });
    final osis = _outcome?.osis;
    if (osis == null) return;
    final parts = osis.split('-').first.split('.');
    final book = parts[0];
    final chapter = int.parse(parts[1]);
    final index =
        _spine.indexWhere((c) => c.bookOsis == book && c.chapter == chapter);
    if (index < 0) {
      setState(() => _jumpMiss = 'Not in this module: $book $chapter');
    } else if (_scroll.isAttached) {
      _scroll.jumpTo(index: index);
    }
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
        content:
            Text('Imported ${imported.title} (${imported.verses} verses)'),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Import failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final position = _topIndex == null ? null : _spine[_topIndex!].heading;
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
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    isDense: true,
                    labelText: 'Go to reference',
                    hintText: 'Joh 3,16 · 1 Kor 13,4-7 · Ps 23',
                    helperText: _active == null
                        ? 'No module imported yet — use the library button above'
                        : _active!.title,
                  ),
                  onChanged: _onInput,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (position != null)
                      Text(
                        position,
                        key: const Key('current-position'),
                        style: theme.textTheme.labelLarge
                            ?.copyWith(color: theme.colorScheme.primary),
                      ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: _statusText(theme),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: _spine.isEmpty
                      ? Center(
                          child: Text(
                            'Import an OSIS module to begin reading',
                            style: theme.textTheme.bodyLarge,
                          ),
                        )
                      : ScrollablePositionedList.builder(
                          key: const Key('reader'),
                          itemScrollController: _scroll,
                          itemPositionsListener: _positions,
                          itemCount: _spine.length,
                          itemBuilder: _chapterItem,
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _statusText(ThemeData theme) {
    final outcome = _outcome;
    if (outcome?.error != null) {
      return Text(
        outcome!.error!,
        key: const Key('parse-error'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelMedium
            ?.copyWith(color: theme.colorScheme.error),
      );
    }
    if (_jumpMiss != null) {
      return Text(
        _jumpMiss!,
        key: const Key('jump-miss'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelMedium
            ?.copyWith(color: theme.colorScheme.error),
      );
    }
    if (outcome?.osis != null) {
      return Text(
        outcome!.osis!,
        key: const Key('osis-result'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelMedium
            ?.copyWith(color: theme.colorScheme.outline),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _chapterItem(BuildContext context, int index) {
    final theme = Theme.of(context);
    final entry = _spine[index];
    final layout = _layoutFor(index);
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 12),
            child: Text(
              entry.heading,
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontFamily: 'GentiumBookPlus'),
            ),
          ),
          TypesetChapter(layout: layout),
        ],
      ),
    );
  }
}
