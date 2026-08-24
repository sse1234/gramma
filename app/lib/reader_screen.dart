import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'footnotes_pane.dart';
import 'pane_badge.dart';
import 'pane_model.dart';
import 'reader_pane.dart';
import 'settings.dart';
import 'settings_screen.dart';
import 'src/rust/api/library.dart';
import 'src/rust/api/references.dart';
import 'src/rust/api/user.dart';

/// Orchestrates the layout object (ADR 0008): a resizable grid of columns,
/// each a stack of views, with position links by pane id — persisted in the
/// user store and restored on start.
class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key});

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  static const _gripThickness = 12.0;
  static const _minPaneExtent = 140.0;
  static const _gutter = 48.0;

  List<ModuleView> _modules = const [];
  late LayoutModel _layout;
  bool _initialized = false;

  /// Pane id currently being dragged for rearrangement, if any.
  String? _draggingPane;

  /// One-shot navigation commands per pane id.
  final Map<String, NavCommand> _commands = {};
  int _commandEpoch = 0;

  @override
  void initState() {
    super.initState();
    _modules = modules();
    _layout = _loadLayout();
    _initialized = true;
  }

  LayoutModel _loadLayout() {
    final stored = loadLayout();
    if (stored != null) {
      final decoded = LayoutModel.decode(stored);
      if (decoded != null) {
        for (final pane in decoded.allPanes) {
          if (pane.module != null &&
              !_modules.any((m) => m.code == pane.module)) {
            pane.module = null;
          }
        }
        decoded.ensureBadges();
        return decoded;
      }
    }
    return LayoutModel([
      PaneColumn(panes: [
        PaneSpec(kind: PaneKind.text, module: _modules.firstOrNull?.code),
      ]),
    ])
      ..ensureBadges();
  }

  void _save() {
    saveLayout(json: _layout.encode());
  }

  void _setAnchor(String id, String osis) {
    final pane = _layout.byId(id);
    if (pane == null || pane.anchor == osis) return;
    setState(() => pane.anchor = osis);
    _save();
  }

  void _setAnchorEnd(String id, String? osis) {
    final pane = _layout.byId(id);
    if (pane == null || pane.anchorEnd == osis) return;
    setState(() => pane.anchorEnd = osis);
    _save();
  }

  /// Navigate the pane a footnotes view follows (from a passage preview);
  /// recorded in the desk history like any deliberate jump.
  void _openReference(PaneSpec source, String osis) {
    final targetId = source.follow ??
        _layout.allPanes
            .where((p) => p.kind == PaneKind.text)
            .firstOrNull
            ?.id;
    if (targetId == null) return;
    setState(() {
      _layout.recordNavigation(targetId, osis);
      _commands[targetId] = (epoch: ++_commandEpoch, osis: osis);
    });
    _save();
  }

  void _recordJump(String paneId, String osis) {
    setState(() => _layout.recordNavigation(paneId, osis));
    _save();
  }

  void _applyHistoryEntry(HistoryEntry? entry) {
    if (entry == null) return;
    setState(() {
      _commands[entry.paneId] = (epoch: ++_commandEpoch, osis: entry.osis);
    });
    _save();
  }

  List<HistoryItem> _historyItems() {
    final items = <HistoryItem>[];
    for (var i = _layout.history.length - 1; i >= 0; i--) {
      final entry = _layout.history[i];
      final pane = _layout.byId(entry.paneId);
      items.add((
        index: i,
        label: formatReference(osis: entry.osis),
        badge: pane?.badge ?? '?',
        badgeIndex: pane?.badgeIndex ?? 0,
        current: i == _layout.historyCursor,
      ));
    }
    return items;
  }

  void _setModule(String id, String code) {
    final pane = _layout.byId(id);
    if (pane == null || pane.module == code) return;
    setState(() => pane.module = code);
    _save();
  }

  void _setFollow(String id, String? follow) {
    final pane = _layout.byId(id);
    if (pane == null) return;
    setState(() => pane.follow = follow);
    _save();
  }

  void _closePane(String id) {
    setState(() => _layout.removePane(id));
    _save();
  }

  void _addPane(PaneKind kind) {
    if (!_layout.hasFreeBadge) return;
    setState(() {
      switch (kind) {
        case PaneKind.text:
          _layout.columns.add(PaneColumn(panes: [
            PaneSpec(
              kind: PaneKind.text,
              module: _modules.firstOrNull?.code,
              anchor: _layout.allPanes.firstOrNull?.anchor,
            ),
          ]));
        case PaneKind.footnotes:
          final source = _layout.allPanes
              .where((p) => p.kind == PaneKind.text)
              .firstOrNull;
          final pane = PaneSpec(
            kind: PaneKind.footnotes,
            follow: source?.id,
            weight: 0.5,
          );
          final column =
              source == null ? null : _layout.columnOf(source.id);
          if (column != null) {
            column.panes.add(pane);
          } else {
            _layout.columns.add(PaneColumn(panes: [pane]));
          }
      }
      _layout.ensureBadges();
    });
    _save();
  }

  Future<void> _importOsis() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        // iOS/macOS match on UTIs, the other platforms on extensions.
        XTypeGroup(
          label: 'OSIS XML',
          extensions: ['xml', 'osis'],
          uniformTypeIdentifiers: ['public.xml', 'public.text'],
        ),
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

  List<FollowOption> _followOptionsFor(PaneSpec spec) {
    return [
      for (final pane in _layout.allPanes)
        if (pane.id != spec.id && pane.kind == PaneKind.text)
          (
            id: pane.id,
            label: pane.module ?? 'Text',
            badge: pane.badge ?? '?',
            badgeIndex: pane.badgeIndex,
          ),
    ];
  }

  void _dragColumns(int left, double dx, double contentWidth) {
    final columns = _layout.columns;
    final sum = columns.fold(0.0, (a, c) => a + c.weight);
    final minWeight = _minPaneExtent / contentWidth * sum;
    final dw = dx / contentWidth * sum;
    setState(() {
      final a = columns[left];
      final b = columns[left + 1];
      final applied = dw.clamp(
        minWeight - a.weight,
        b.weight - minWeight,
      );
      a.weight += applied;
      b.weight -= applied;
    });
  }

  /// Vertical tiling only makes sense at whole column-width multiples
  /// (constant zoom): snap the divider there on release.
  void _snapColumns(int left, double contentWidth) {
    final columns = _layout.columns;
    final sum = columns.fold(0.0, (a, c) => a + c.weight);
    final leftWidth = columns[left].weight / sum * contentWidth;
    final rightWidth = columns[left + 1].weight / sum * contentWidth;
    final available = leftWidth + rightWidth - _minPaneExtent;
    final columnWidth = SettingsScope.of(context).columnWidth;
    final target = snapToColumns(leftWidth, columnWidth, _gutter, available);
    final dw = (target - leftWidth) / contentWidth * sum;
    setState(() {
      _layout.columns[left].weight += dw;
      _layout.columns[left + 1].weight -= dw;
    });
    _save();
  }

  void _dragRows(PaneColumn column, int top, double dy, double contentHeight) {
    final sum = column.panes.fold(0.0, (a, p) => a + p.weight);
    final minWeight = _minPaneExtent / contentHeight * sum;
    final dw = dy / contentHeight * sum;
    setState(() {
      final a = column.panes[top];
      final b = column.panes[top + 1];
      final applied = dw.clamp(
        minWeight - a.weight,
        b.weight - minWeight,
      );
      a.weight += applied;
      b.weight -= applied;
    });
  }

  Widget _dragHandle(PaneSpec spec) {
    return MouseRegion(
      cursor: SystemMouseCursors.grab,
      child: Draggable<String>(
        data: spec.id,
        onDragStarted: () => setState(() => _draggingPane = spec.id),
        onDragEnd: (_) => setState(() => _draggingPane = null),
        feedback: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(
              spec.kind == PaneKind.footnotes
                  ? Icons.notes_outlined
                  : Icons.menu_book_outlined,
              size: 20,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Icon(
            Icons.drag_indicator,
            size: 18,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  void _dropIntoStack(PaneColumn column, int index, String id) {
    setState(() => _layout.moveIntoStack(id, column, index));
    _save();
  }

  void _dropAsNewColumn(PaneColumn? after, String id) {
    setState(() => _layout.moveToNewColumn(id, after: after));
    _save();
  }

  /// Drop zones shown while a pane is being dragged: vertical strips at
  /// every column boundary (drop = new column there) and horizontal strips
  /// at every stack boundary (drop = insert into that stack).
  List<Widget> _dropTargets(BoxConstraints constraints) {
    final columns = _layout.columns;
    final contentWidth =
        constraints.maxWidth - (columns.length - 1) * _gripThickness;
    final sumW = columns.fold(0.0, (a, c) => a + c.weight);
    final widths = [
      for (final c in columns) c.weight / sumW * contentWidth,
    ];
    final targets = <Widget>[];
    var x = 0.0;
    for (var k = 0; k <= columns.length; k++) {
      final centerX = k == 0
          ? 0.0
          : k == columns.length
              ? constraints.maxWidth
              : x - _gripThickness / 2;
      targets.add(Positioned(
        left: (centerX - 28).clamp(0.0, constraints.maxWidth - 56),
        width: 56,
        top: 0,
        height: constraints.maxHeight,
        child: _DropZone(
          key: Key('drop-column-$k'),
          onAccept: (id) =>
              _dropAsNewColumn(k == 0 ? null : columns[k - 1], id),
        ),
      ));
      if (k < columns.length) {
        final columnLeft = x;
        final width = widths[k];
        final panes = columns[k].panes;
        final contentHeight =
            constraints.maxHeight - (panes.length - 1) * _gripThickness;
        final sumH = panes.fold(0.0, (a, p) => a + p.weight);
        var y = 0.0;
        for (var j = 0; j <= panes.length; j++) {
          final centerY = j == 0
              ? 0.0
              : j == panes.length
                  ? constraints.maxHeight
                  : y - _gripThickness / 2;
          targets.add(Positioned(
            left: columnLeft + 64,
            width: (width - 128).clamp(48.0, double.infinity),
            top: (centerY - 30).clamp(0.0, constraints.maxHeight - 60),
            height: 60,
            child: _DropZone(
              key: Key('drop-stack-$k-$j'),
              onAccept: (id) => _dropIntoStack(columns[k], j, id),
            ),
          ));
          if (j < panes.length) {
            y += panes[j].weight / sumH * contentHeight + _gripThickness;
          }
        }
        x += width + _gripThickness;
      }
    }
    return targets;
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) return const SizedBox.shrink();
    final settings = SettingsScope.of(context);
    final reading = settings.readingMode;
    return Scaffold(
      appBar: reading ? null : AppBar(
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
        padding: EdgeInsets.fromLTRB(24, reading ? 16 : 12, 24, 0),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final columns = _layout.columns;
            final contentWidth = constraints.maxWidth -
                (columns.length - 1) * _gripThickness;
            final sum = columns.fold(0.0, (a, c) => a + c.weight);
            return Stack(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < columns.length; i++) ...[
                      if (i > 0)
                        _Grip(
                          key: Key('column-grip-${i - 1}'),
                          axis: Axis.horizontal,
                          onDrag: (delta) =>
                              _dragColumns(i - 1, delta, contentWidth),
                          onEnd: () => _snapColumns(i - 1, contentWidth),
                        ),
                      SizedBox(
                        width: columns[i].weight / sum * contentWidth,
                        child: _columnWidget(columns[i]),
                      ),
                    ],
                  ],
                ),
                if (_draggingPane != null) ..._dropTargets(constraints),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _columnWidget(PaneColumn column) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final panes = column.panes;
        final contentHeight =
            constraints.maxHeight - (panes.length - 1) * _gripThickness;
        final sum = panes.fold(0.0, (a, p) => a + p.weight);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var j = 0; j < panes.length; j++) ...[
              if (j > 0)
                _Grip(
                  key: Key('row-grip-${panes[j - 1].id}'),
                  axis: Axis.vertical,
                  onDrag: (delta) =>
                      _dragRows(column, j - 1, delta, contentHeight),
                  onEnd: _save,
                ),
              SizedBox(
                height: panes[j].weight / sum * contentHeight,
                child: _pane(panes[j]),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _pane(PaneSpec spec) {
    final settings = SettingsScope.of(context);
    final followedAnchor = _layout.byId(spec.follow)?.anchor;
    final closable = _layout.allPanes.length > 1;
    void toggleMode() => settings.setReadingMode(!settings.readingMode);
    final badge = spec.badge == null
        ? null
        : PaneBadge(
            key: Key('badge-${spec.badge}'),
            badge: spec.badge!,
            badgeIndex: spec.badgeIndex,
          );
    switch (spec.kind) {
      case PaneKind.text:
        return ReaderPane(
          key: ValueKey('pane-${spec.id}'),
          spec: spec,
          modules: _modules,
          followedAnchor: followedAnchor,
          followOptions: _followOptionsFor(spec),
          readingMode: settings.readingMode,
          onToggleMode: toggleMode,
          badge: badge,
          dragHandle: _dragHandle(spec),
          onAnchor: (osis) => _setAnchor(spec.id, osis),
          onAnchorEnd: (osis) => _setAnchorEnd(spec.id, osis),
          onJump: (osis) => _recordJump(spec.id, osis),
          canGoBack: _layout.canGoBack,
          canGoForward: _layout.canGoForward,
          onBack: () => _applyHistoryEntry(_layout.goBack()),
          onForward: () => _applyHistoryEntry(_layout.goForward()),
          historyItems: _historyItems(),
          onHistorySelect: (index) =>
              _applyHistoryEntry(_layout.jumpToHistory(index)),
          command: _commands[spec.id],
          onModule: (code) => _setModule(spec.id, code),
          onFollow: (follow) => _setFollow(spec.id, follow),
          onClose: closable ? () => _closePane(spec.id) : null,
        );
      case PaneKind.footnotes:
        return FootnotesPane(
          key: ValueKey('pane-${spec.id}'),
          followedAnchor: followedAnchor,
          followedAnchorEnd: _layout.byId(spec.follow)?.anchorEnd,
          onOpenReference: (osis) => _openReference(spec, osis),
          sourceModule: _layout.byId(spec.follow)?.module,
          followValue: spec.follow,
          followOptions: _followOptionsFor(spec),
          readingMode: settings.readingMode,
          onToggleMode: toggleMode,
          badge: badge,
          dragHandle: _dragHandle(spec),
          onFollow: (follow) => _setFollow(spec.id, follow),
          onClose: closable ? () => _closePane(spec.id) : null,
        );
    }
  }
}

/// A draggable divider between tiles; horizontal axis resizes columns,
/// vertical axis resizes stacked panes.
class _Grip extends StatelessWidget {
  const _Grip({
    super.key,
    required this.axis,
    required this.onDrag,
    required this.onEnd,
  });

  final Axis axis;
  final ValueChanged<double> onDrag;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final horizontal = axis == Axis.horizontal;
    return MouseRegion(
      cursor: horizontal
          ? SystemMouseCursors.resizeColumn
          : SystemMouseCursors.resizeRow,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate:
            horizontal ? (d) => onDrag(d.delta.dx) : null,
        onHorizontalDragEnd: horizontal ? (_) => onEnd() : null,
        onVerticalDragUpdate: horizontal ? null : (d) => onDrag(d.delta.dy),
        onVerticalDragEnd: horizontal ? null : (_) => onEnd(),
        child: SizedBox(
          width: horizontal ? 12 : null,
          height: horizontal ? null : 12,
          child: Center(
            child: Container(
              width: horizontal ? 2.5 : 36,
              height: horizontal ? 36 : 2.5,
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A rearrangement drop zone, highlighted while a drag hovers over it.
class _DropZone extends StatelessWidget {
  const _DropZone({super.key, required this.onAccept});

  final ValueChanged<String> onAccept;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DragTarget<String>(
      onAcceptWithDetails: (details) => onAccept(details.data),
      builder: (context, candidates, rejected) => Container(
        decoration: BoxDecoration(
          color: candidates.isEmpty
              ? Colors.transparent
              : scheme.primary.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(8),
          border: candidates.isEmpty
              ? null
              : Border.all(color: scheme.primary, width: 1.5),
        ),
      ),
    );
  }
}
