import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'l10n.dart';
import 'settings.dart';
import 'src/rust/api/library.dart';
import 'src/rust/api/references.dart';
import 'package:share_plus/share_plus.dart';

import 'src/rust/api/user.dart';

/// The search tool (ADR 0022, Tier 0): lexical BM25 search over a Bible
/// module — the bibelsuche parity port running in the Rust core, so it
/// works on every device down to the oldest tablet. Rows jump the
/// reading view; the thumb records a positive training label and the
/// red row a negative one, both stored as synced user data (ADR 0014)
/// so every device contributes to the bibelsuche training corpus.
Future<void> showSearchTool(
  BuildContext context, {
  required List<ModuleView> modules,
  required String? initialModule,
  required ValueChanged<String> onOpen,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _SearchDialog(
      modules: modules,
      initialModule: initialModule,
      onOpen: onOpen,
    ),
  );
}

/// All collected labels as JSONL, one bibelsuche-compatible record per
/// line — the export payload (ADR 0022).
String labelExportJsonl() {
  final keys = userKeys(prefix: 'label/');
  final lines = <String>[];
  for (final key in keys) {
    final value = userGet(key: key);
    if (value != null && value.isNotEmpty) lines.add(value);
  }
  return lines.isEmpty ? '' : '${lines.join('\n')}\n';
}

/// Write the labels to a file and hand it to the platform share sheet
/// (AirDrop, Files, mail, …). Returns the number of labels, 0 when
/// there is nothing to export.
Future<int> exportLabels(String directory) async {
  final jsonl = labelExportJsonl();
  if (jsonl.isEmpty) return 0;
  final count = '\n'.allMatches(jsonl).length;
  final stamp = DateTime.now().toIso8601String().split('T').first;
  final file = File('$directory/gramma-labels-$stamp.jsonl');
  await file.writeAsString(jsonl);
  await SharePlus.instance.share(
    ShareParams(files: [XFile(file.path, mimeType: 'application/json')]),
  );
  return count;
}

/// One training label, schema-compatible with bibelsuche's collector.
void recordSearchLabel({
  required String query,
  required String module,
  required String label,
  String? osis,
  int? rank,
  double? score,
}) {
  final key =
      'label/${DateTime.now().toUtc().microsecondsSinceEpoch}-${deviceId()}';
  userSet(
    key: key,
    value: jsonEncode({
      'v': 1,
      'ts': DateTime.now().toUtc().toIso8601String(),
      'query': query,
      'corpus': module,
      'osis': osis,
      'label': label,
      'rank': rank,
      'score': score,
      'tier': 'lexical',
      'device': deviceId(),
    }),
  );
}

class _SearchDialog extends StatefulWidget {
  const _SearchDialog({
    required this.modules,
    required this.initialModule,
    required this.onOpen,
  });

  final List<ModuleView> modules;
  final String? initialModule;
  final ValueChanged<String> onOpen;

  @override
  State<_SearchDialog> createState() => _SearchDialogState();
}

class _SearchDialogState extends State<_SearchDialog> {
  final TextEditingController _query = TextEditingController();
  String? _module;
  List<SearchHitView> _hits = const [];
  bool _searched = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _module = widget.initialModule ?? widget.modules.firstOrNull?.code;
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search(String raw) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final module = _module;
    final query = raw.trim();
    if (module == null || query.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      final hits =
          await searchVerses(moduleCode: module, query: query, limit: 25);
      if (!mounted) return;
      setState(() {
        _hits = hits;
        _searched = true;
        _busy = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _hits = const [];
        _searched = true;
        _busy = false;
      });
    }
  }

  void _labelSnack() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.labelRecorded)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = SettingsScope.of(context);
    final family = settings.fontFamily;
    final refStyle = theme.textTheme.labelMedium
        ?.copyWith(color: theme.colorScheme.primary);
    final textStyle = theme.textTheme.bodyMedium
        ?.copyWith(fontFamily: family, height: 1.3);
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 620),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      context.l10n.searchTool,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  if (widget.modules.length > 1)
                    DropdownButton<String>(
                      key: const Key('search-module'),
                      underline: const SizedBox.shrink(),
                      value: _module,
                      items: [
                        for (final m in widget.modules)
                          DropdownMenuItem(
                              value: m.code, child: Text(m.code)),
                      ],
                      onChanged: (code) {
                        if (code == null) return;
                        setState(() {
                          _module = code;
                          _hits = const [];
                          _searched = false;
                        });
                      },
                    ),
                  IconButton(
                    key: const Key('search-close'),
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              TextField(
                key: const Key('search-query'),
                controller: _query,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search, size: 18),
                  hintText: context.l10n.searchQueryHint,
                ),
                onSubmitted: _search,
              ),
              const SizedBox(height: 8),
              Flexible(
                child: !_searched
                    ? const SizedBox.shrink()
                    : _hits.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                context.l10n.noDictionaryResults,
                                key: const Key('search-empty'),
                                style: theme.textTheme.bodyMedium,
                              ),
                            ),
                          )
                        : ListView.builder(
                            key: const Key('search-results'),
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            shrinkWrap: true,
                            itemCount: _hits.length + 1,
                            itemBuilder: (context, index) {
                              if (index == _hits.length) {
                                return _noGoodHitRow(theme);
                              }
                              final hit = _hits[index];
                              final osis =
                                  '${hit.bookOsis}.${hit.chapter}.${hit.verse}';
                              return InkWell(
                                key: Key('search-hit-$index'),
                                onTap: () {
                                  Navigator.of(context).pop();
                                  widget.onOpen(osis);
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 4),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Text.rich(
                                          TextSpan(children: [
                                            TextSpan(
                                              text:
                                                  '${formatReference(osis: osis)}  ',
                                              style: refStyle,
                                            ),
                                            TextSpan(
                                                text: hit.text,
                                                style: textStyle),
                                          ]),
                                        ),
                                      ),
                                      IconButton(
                                        key: Key('search-good-$index'),
                                        tooltip: context.l10n.goodHit,
                                        visualDensity:
                                            VisualDensity.compact,
                                        iconSize: 16,
                                        icon: const Icon(
                                            Icons.thumb_up_outlined),
                                        onPressed: () {
                                          recordSearchLabel(
                                            query: _query.text.trim(),
                                            module: _module!,
                                            label: 'good_hit',
                                            osis: osis,
                                            rank: index,
                                            score: hit.score,
                                          );
                                          _labelSnack();
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _noGoodHitRow(ThemeData theme) {
    return InkWell(
      key: const Key('search-no-good-hit'),
      onTap: () {
        final top = _hits.firstOrNull;
        recordSearchLabel(
          query: _query.text.trim(),
          module: _module!,
          label: 'no_good_hit',
          osis: top == null
              ? null
              : '${top.bookOsis}.${top.chapter}.${top.verse}',
          rank: top == null ? null : 0,
          score: top?.score,
        );
        _labelSnack();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          context.l10n.noGoodHit,
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.error),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
