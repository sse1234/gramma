import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'footnotes_pane.dart';
import 'pane_model.dart';
import 'reader_pane.dart';
import 'settings_screen.dart';
import 'src/rust/api/library.dart';
import 'src/rust/api/user.dart';

/// Orchestrates the layout object (ADR 0008): an ordered set of views with
/// their assets, position links, and reading positions — persisted in the
/// user store and restored on start.
class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key});

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  List<ModuleView> _modules = const [];
  List<PaneSpec> _panes = [];
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _modules = modules();
    _panes = _loadPanes();
    _initialized = true;
  }

  List<PaneSpec> _loadPanes() {
    final stored = loadLayout();
    if (stored != null) {
      final decoded = PaneSpec.decodeList(stored);
      if (decoded != null) {
        for (final pane in decoded) {
          if (pane.module != null &&
              !_modules.any((m) => m.code == pane.module)) {
            pane.module = null;
          }
        }
        return decoded;
      }
    }
    return [
      PaneSpec(kind: PaneKind.text, module: _modules.firstOrNull?.code),
    ];
  }

  void _save() {
    saveLayout(json: PaneSpec.encodeList(_panes));
  }

  void _setAnchor(int index, String osis) {
    if (_panes[index].anchor == osis) return;
    setState(() => _panes[index].anchor = osis);
    _save();
  }

  void _setModule(int index, String code) {
    if (_panes[index].module == code) return;
    setState(() => _panes[index].module = code);
    _save();
  }

  void _setFollow(int index, int? follow) {
    setState(() => _panes[index].follow = follow);
    _save();
  }

  void _closePane(int index) {
    setState(() {
      _panes.removeAt(index);
      for (final pane in _panes) {
        final follow = pane.follow;
        if (follow == null) continue;
        if (follow == index) {
          pane.follow = null;
        } else if (follow > index) {
          pane.follow = follow - 1;
        }
      }
    });
    _save();
  }

  void _addPane(PaneKind kind) {
    setState(() {
      switch (kind) {
        case PaneKind.text:
          _panes.add(PaneSpec(
            kind: PaneKind.text,
            module: _modules.firstOrNull?.code,
            anchor: _panes.firstOrNull?.anchor,
          ));
        case PaneKind.footnotes:
          final source = _panes.indexWhere((p) => p.kind == PaneKind.text);
          _panes.add(PaneSpec(
            kind: PaneKind.footnotes,
            follow: source >= 0 ? source : null,
          ));
      }
    });
    _save();
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
      setState(() => _modules = modules());
      messenger.showSnackBar(SnackBar(
        content: Text('Imported ${imported.title} (${imported.verses} verses)'),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Import failed: $e')));
    }
  }

  List<FollowOption> _followOptionsFor(int index) {
    return [
      for (var j = 0; j < _panes.length; j++)
        if (j != index && _panes[j].kind == PaneKind.text)
          (index: j, label: 'View ${j + 1}'),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) return const SizedBox.shrink();
    return Scaffold(
      appBar: AppBar(
        title: const Text('gramma'),
        actions: [
          PopupMenuButton<PaneKind>(
            key: const Key('add-view'),
            tooltip: 'Add view',
            icon: const Icon(Icons.vertical_split_outlined),
            onSelected: _addPane,
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: PaneKind.text,
                child: Text('Text view'),
              ),
              PopupMenuItem(
                value: PaneKind.footnotes,
                child: Text('Footnotes view'),
              ),
            ],
          ),
          IconButton(
            key: const Key('open-settings'),
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
          IconButton(
            key: const Key('import-osis'),
            tooltip: 'Import OSIS…',
            icon: const Icon(Icons.library_add_outlined),
            onPressed: _importOsis,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < _panes.length; i++) ...[
              if (i > 0) const VerticalDivider(width: 25),
              Expanded(child: _pane(i)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _pane(int index) {
    final spec = _panes[index];
    final followedAnchor =
        spec.follow != null ? _panes[spec.follow!].anchor : null;
    final closable = _panes.length > 1;
    switch (spec.kind) {
      case PaneKind.text:
        return ReaderPane(
          key: ValueKey('pane-${spec.id}'),
          spec: spec,
          modules: _modules,
          followedAnchor: followedAnchor,
          followOptions: _followOptionsFor(index),
          onAnchor: (osis) => _setAnchor(index, osis),
          onModule: (code) => _setModule(index, code),
          onFollow: (follow) => _setFollow(index, follow),
          onClose: closable ? () => _closePane(index) : null,
        );
      case PaneKind.footnotes:
        return FootnotesPane(
          key: ValueKey('pane-${spec.id}'),
          followedAnchor: followedAnchor,
          sourceModule:
              spec.follow != null ? _panes[spec.follow!].module : null,
          followValue: spec.follow,
          followOptions: _followOptionsFor(index),
          onFollow: (follow) => _setFollow(index, follow),
          onClose: closable ? () => _closePane(index) : null,
        );
    }
  }
}
