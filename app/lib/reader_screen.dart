import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'desks.dart';
import 'l10n.dart';
import 'footnotes_pane.dart';
import 'reading_plan.dart';
import 'sync_transport.dart';
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

class _ReaderScreenState extends State<ReaderScreen>
    with WidgetsBindingObserver {
  static const _gripThickness = 12.0;
  static const _minPaneExtent = 140.0;
  static const _gutter = 48.0;

  List<ModuleView> _modules = const [];
  late LayoutModel _layout;
  DeskRegistry _registry = DeskRegistry([DeskInfo(id: '', name: 'Desk 1')]);
  String _deskId = '';
  bool _initialized = false;

  /// Pane id currently being dragged for rearrangement, if any.
  String? _draggingPane;

  /// One-shot navigation commands per pane id.
  final Map<String, NavCommand> _commands = {};
  int _commandEpoch = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _modules = modules();
    try {
      syncNow();
    } catch (_) {
      // An unreachable sync folder never blocks startup.
    }
    _loadDesks();
    _initialized = true;
    // A second, asynchronous pull covers transports with download latency
    // (iCloud placeholders); it reloads the desk if anything arrived.
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncPull());
  }

  /// Pull remote changes whenever the app comes back to the foreground —
  /// the "continue on another device" moment (ADR 0014).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _syncPull();
  }

  void _loadDesks() {
    final settings = SettingsScope.of(context);
    var registry = DeskRegistry.decode(userGet(key: 'desks') ?? '');
    if (registry == null) {
      // First run, or migration from the single-layout era: the legacy
      // 'layout' value becomes Desk 1.
      final id = newDeskId();
      registry = DeskRegistry(
          [DeskInfo(id: id, name: '${context.l10n.deskDefaultPrefix} 1')]);
      final legacy = userGet(key: 'layout');
      if (legacy != null) {
        userSet(key: 'desk/$id', value: legacy);
      }
      userSet(key: 'desks', value: registry.encode());
    }
    _registry = registry;
    final chosen =
        registry.byId(settings.currentDeskId) ?? registry.desks.first;
    _deskId = chosen.id;
    if (settings.currentDeskId != chosen.id) {
      // Deferred: notifying settings listeners mid-build is not allowed.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) settings.setCurrentDeskId(chosen.id);
      });
    }
    _layout = _loadDeskLayout(chosen.id);
  }

  LayoutModel _loadDeskLayout(String id) {
    final stored = userGet(key: 'desk/$id');
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
    return _freshLayout();
  }

  LayoutModel _freshLayout() {
    return LayoutModel([
      PaneColumn(panes: [
        PaneSpec(kind: PaneKind.text, module: _modules.firstOrNull?.code),
      ]),
    ])
      ..ensureBadges();
  }

  void _save() {
    userSet(key: 'desk/$_deskId', value: _layout.encode());
  }

  Future<void> _syncPull() async {
    final changed = await pullSync();
    if (changed.isEmpty || !mounted) return;
    setState(() {
      if (changed.contains('desks')) {
        final registry = DeskRegistry.decode(userGet(key: 'desks') ?? '');
        if (registry != null) {
          _registry = registry;
          if (registry.byId(_deskId) == null) {
            // The shown desk was deleted on another device.
            _deskId = registry.desks.first.id;
            _layout = _loadDeskLayout(_deskId);
            _commands.clear();
            return;
          }
        }
      }
      if (changed.contains('desk/$_deskId')) {
        _layout = _loadDeskLayout(_deskId);
        _commands.clear();
      }
    });
  }

  void _switchDesk(String id) {
    if (id == _deskId) return;
    setState(() {
      _deskId = id;
      _layout = _loadDeskLayout(id);
      _commands.clear();
    });
    SettingsScope.of(context).setCurrentDeskId(id);
  }

  void _newDesk() {
    final id = newDeskId();
    _registry.desks.add(DeskInfo(
        id: id, name: _registry.nextName(context.l10n.deskDefaultPrefix)));
    userSet(key: 'desks', value: _registry.encode());
    userSet(key: 'desk/$id', value: _freshLayout().encode());
    _switchDesk(id);
  }

  Future<void> _renameDesk() async {
    final desk = _registry.byId(_deskId);
    if (desk == null) return;
    final controller = TextEditingController(text: desk.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.renameDeskTitle),
        content: TextField(
          key: const Key('desk-name-field'),
          controller: controller,
          autofocus: true,
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.l10n.cancel),
          ),
          TextButton(
            key: const Key('desk-rename-confirm'),
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(context.l10n.rename),
          ),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    setState(() => desk.name = name.trim());
    userSet(key: 'desks', value: _registry.encode());
  }

  Future<void> _deleteDesk() async {
    if (_registry.desks.length < 2) return;
    final desk = _registry.byId(_deskId);
    if (desk == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.deleteDeskTitle(desk.name)),
        content: Text(context.l10n.deleteDeskBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.keep),
          ),
          TextButton(
            key: const Key('desk-delete-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    _registry.desks.removeWhere((d) => d.id == _deskId);
    userSet(key: 'desks', value: _registry.encode());
    _switchDesk(_registry.desks.first.id);
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
    _navigatePane(
        source.follow ??
            _layout.allPanes
                .where((p) => p.kind == PaneKind.text)
                .firstOrNull
                ?.id,
        osis);
  }

  /// Navigate the first text view (reading plans, later search results).
  void _openOsis(String osis) {
    _navigatePane(
        _layout.allPanes
            .where((p) => p.kind == PaneKind.text)
            .firstOrNull
            ?.id,
        osis);
  }

  void _navigatePane(String? targetId, String osis) {
    if (targetId == null) return;
    setState(() {
      _layout.recordNavigation(targetId, osis);
      _commands[targetId] = (epoch: ++_commandEpoch, osis: osis);
    });
    _save();
  }

  Future<void> _openReadingPlan() async {
    final plan = await ReadingPlan.loadBundled();
    if (plan == null || !mounted) return;
    await showReadingPlan(context, plan: plan, onOpen: _openOsis);
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
    final l10n = context.l10n;
    try {
      final imported = await importOsisFile(path: file.path);
      setState(() => _modules = modules());
      messenger.showSnackBar(SnackBar(
        content: Text(
            l10n.importedModule(imported.title, imported.verses.toInt())),
      ));
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text(l10n.importFailed('$e'))));
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
      final lower = minWeight - a.weight;
      final upper = b.weight - minWeight;
      // Too narrow for two minimum-width panes: nothing to resize.
      if (lower > upper) return;
      final applied = dw.clamp(lower, upper);
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
      final lower = minWeight - a.weight;
      final upper = b.weight - minWeight;
      if (lower > upper) return;
      final applied = dw.clamp(lower, upper);
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
  /// at every stack boundary (drop = insert into that stack). Boundaries
  /// where the drop would recreate the current layout (the dragged pane's
  /// own position) are not offered.
  List<Widget> _dropTargets(BoxConstraints constraints) {
    final columns = _layout.columns;
    final dragColumn = _layout.columnOf(_draggingPane ?? '');
    final dragColumnIndex =
        dragColumn == null ? -1 : columns.indexOf(dragColumn);
    final dragAlone = dragColumn != null && dragColumn.panes.length == 1;
    final dragPaneIndex =
        dragColumn?.panes.indexWhere((p) => p.id == _draggingPane) ?? -1;
    bool columnNoop(int k) =>
        dragAlone && (k == dragColumnIndex || k == dragColumnIndex + 1);
    bool stackNoop(int k, int j) =>
        k == dragColumnIndex && (j == dragPaneIndex || j == dragPaneIndex + 1);
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
      if (!columnNoop(k)) {
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
      }
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
          if (!stackNoop(k, j)) {
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
          }
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
          PopupMenuButton<VoidCallback>(
            key: const Key('tools-menu'),
            tooltip: context.l10n.toolsTooltip,
            icon: const Icon(Icons.auto_stories_outlined),
            onSelected: (action) => action(),
            itemBuilder: (context) => [
              PopupMenuItem(
                key: const Key('tool-plan'),
                value: _openReadingPlan,
                child: Text(context.l10n.readingPlanBibelliga),
              ),
              // Search joins this menu once it lands.
            ],
          ),
          PopupMenuButton<VoidCallback>(
            key: const Key('desk-menu'),
            tooltip: context.l10n
                .desksTooltip(_registry.byId(_deskId)?.name ?? ''),
            icon: const Icon(Icons.desk_outlined),
            onSelected: (action) => action(),
            itemBuilder: (context) => [
              for (final desk in _registry.desks)
                CheckedPopupMenuItem(
                  key: Key('desk-item-${desk.name}'),
                  checked: desk.id == _deskId,
                  value: () => _switchDesk(desk.id),
                  child: Text(desk.name),
                ),
              const PopupMenuDivider(),
              PopupMenuItem(
                key: const Key('desk-new'),
                value: _newDesk,
                child: Text(context.l10n.newDesk),
              ),
              PopupMenuItem(
                key: const Key('desk-rename'),
                value: _renameDesk,
                child: Text(context.l10n.renameDeskMenu),
              ),
              if (_registry.desks.length > 1)
                PopupMenuItem(
                  key: const Key('desk-delete'),
                  value: _deleteDesk,
                  child: Text(context.l10n.deleteDeskMenu),
                ),
            ],
          ),
          PopupMenuButton<PaneKind>(
            key: const Key('add-view'),
            tooltip: context.l10n.addViewTooltip,
            icon: const Icon(Icons.vertical_split_outlined),
            onSelected: _addPane,
            itemBuilder: (context) => [
              PopupMenuItem(
                value: PaneKind.text,
                child: Text(context.l10n.textView),
              ),
              PopupMenuItem(
                value: PaneKind.footnotes,
                child: Text(context.l10n.footnotesView),
              ),
            ],
          ),
          IconButton(
            key: const Key('open-settings'),
            tooltip: context.l10n.settingsTooltip,
            icon: const Icon(Icons.settings_outlined),
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
              // Sync may have been (re)configured there.
              _syncPull();
            },
          ),
          IconButton(
            key: const Key('import-osis'),
            tooltip: context.l10n.importOsisTooltip,
            icon: const Icon(Icons.library_add_outlined),
            onPressed: _importOsis,
          ),
        ],
      ),
      // SafeArea keeps the desk clear of the status bar, notch, and home
      // indicator — with hidden chrome in reading mode the body would
      // otherwise extend under all of them.
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, outer) {
            final narrow = outer.maxWidth < 500;
            return Padding(
              padding: EdgeInsets.fromLTRB(
                  narrow ? 10 : 24, reading ? 16 : 12, narrow ? 10 : 24, 0),
              child: _desk(),
            );
          },
        ),
      ),
    );
  }

  Widget _desk() {
    return LayoutBuilder(
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
