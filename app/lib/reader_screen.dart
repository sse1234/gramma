import 'package:flutter/material.dart';

import 'annotations.dart';
import 'book_pane.dart';
import 'commentary_pane.dart';
import 'devotional_pane.dart';
import 'dictionary_pane.dart';
import 'desk_app_bar.dart';
import 'desk_grid.dart';
import 'desks.dart';
import 'import_flow.dart';
import 'l10n.dart';
import 'footnotes_pane.dart';
import 'notes_pane.dart';
import 'reading_plan.dart';

import 'package:path_provider/path_provider.dart';

import 'search_tool.dart';
import 'sync_transport.dart';
import 'pane_badge.dart';
import 'pane_model.dart';
import 'pane_header.dart';
import 'reader_focus.dart';
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
  List<ModuleView> _modules = const [];
  late LayoutModel _layout;
  DeskRegistry _registry = DeskRegistry([DeskInfo(id: '', name: 'Desk 1')]);
  String _deskId = '';
  bool _initialized = false;

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
    _plans = ReadingPlan.fromLibrary();
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
      registry = DeskRegistry([
        DeskInfo(id: id, name: '${context.l10n.deskDefaultPrefix} 1'),
      ]);
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
      PaneColumn(
        panes: [
          PaneSpec(
            kind: PaneKind.text,
            module: _bibleModules.firstOrNull?.code,
          ),
        ],
      ),
    ])..ensureBadges();
  }

  /// Bible texts carry the reading views; commentaries and dictionaries
  /// live in their own view kinds (ADR 0017, 0019).
  List<ModuleView> get _bibleModules => [
    for (final m in _modules)
      if (m.kind == 'bible') m,
  ];

  List<ModuleView> get _commentaryModules => [
    for (final m in _modules)
      if (m.kind == 'commentary') m,
  ];

  List<ModuleView> get _dictionaryModules => [
    for (final m in _modules)
      if (m.kind == 'dictionary') m,
  ];

  List<ModuleView> get _bookModules => [
    for (final m in _modules)
      if (m.kind == 'book') m,
  ];

  List<ModuleView> get _devotionalModules => [
    for (final m in _modules)
      if (m.kind == 'devotional') m,
  ];

  void _save() {
    userSet(key: 'desk/$_deskId', value: _layout.encode());
  }

  Future<void> _syncPull() async {
    final changed = await pullSync();
    if (changed.isEmpty || !mounted) return;
    Annotations.invalidate();
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
    _registry.desks.add(
      DeskInfo(
        id: id,
        name: _registry.nextName(context.l10n.deskDefaultPrefix),
      ),
    );
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
      osis,
    );
  }

  /// Navigate the first text view (reading plans, later search results).
  void _openOsis(String osis) {
    _navigatePane(
      _layout.allPanes.where((p) => p.kind == PaneKind.text).firstOrNull?.id,
      osis,
    );
  }

  void _navigatePane(String? targetId, String osis) {
    if (targetId == null) return;
    setState(() {
      _layout.recordNavigation(targetId, osis);
      _commands[targetId] = (epoch: ++_commandEpoch, osis: osis);
    });
    _save();
  }

  Future<void> _openSearch() async {
    final settings = SettingsScope.of(context);
    await showSearchTool(
      context,
      modules: _bibleModules,
      initialModule: settings.defaultModule,
      onOpen: _openOsis,
    );
  }

  Future<void> _exportLabels() async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    if (labelExportJsonl().isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.noLabelsYet)));
      return;
    }
    final directory = await getTemporaryDirectory();
    await exportLabels(directory.path);
  }

  List<ReadingPlan> _plans = const [];

  Future<void> _openReadingPlan(ReadingPlan plan) async {
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
    _structureEpoch++;
    _save();
  }

  /// Bumped when the tiling changed structurally here (a pane added or
  /// closed); the grid snaps its column boundaries on the next build.
  int _structureEpoch = 0;

  PaneSpec? _addPane(PaneKind kind) {
    if (!_layout.hasFreeBadge) return null;
    PaneSpec? created;
    setState(() {
      switch (kind) {
        case PaneKind.text:
          created = PaneSpec(
            kind: PaneKind.text,
            module: _bibleModules.firstOrNull?.code,
            anchor: _layout.allPanes.firstOrNull?.anchor,
          );
          _layout.columns.add(PaneColumn(panes: [created!]));
        case PaneKind.footnotes:
        case PaneKind.commentary:
        case PaneKind.dictionary:
        case PaneKind.book:
        case PaneKind.devotional:
        case PaneKind.notes:
          final source = _layout.allPanes
              .where((p) => p.kind == PaneKind.text)
              .firstOrNull;
          final pane = PaneSpec(
            kind: kind,
            module: switch (kind) {
              PaneKind.commentary => _commentaryModules.firstOrNull?.code,
              PaneKind.dictionary => _dictionaryModules.firstOrNull?.code,
              PaneKind.book => _bookModules.firstOrNull?.code,
              PaneKind.devotional => _devotionalModules.firstOrNull?.code,
              _ => null,
            },
            follow: kind == PaneKind.footnotes || kind == PaneKind.commentary
                ? source?.id
                : null,
            weight: 0.5,
          );
          created = pane;
          final column = source == null ? null : _layout.columnOf(source.id);
          if (column != null) {
            column.panes.add(pane);
          } else {
            _layout.columns.add(PaneColumn(panes: [pane]));
          }
      }
      _layout.ensureBadges();
    });
    _structureEpoch++;
    _save();
    return created;
  }

  /// Route a long-pressed word (ADR 0019) into the desk's dictionary
  /// views; with none open yet, one is created first. In a Strong's-
  /// tagged text the word resolves directly to its entry (ADR 0020);
  /// anywhere else it becomes a search.
  void _lookupWord(
    String word, {
    String? module,
    String? bookOsis,
    int? chapter,
    int? verse,
  }) {
    if (_dictionaryModules.isEmpty) return;
    var anchor = 'q:$word';
    if (module != null &&
        bookOsis != null &&
        chapter != null &&
        verse != null) {
      try {
        final strongs = strongsFor(
          moduleCode: module,
          bookOsis: bookOsis,
          chapter: chapter,
          verse: verse,
          word: word,
        );
        // Greek numbers resolve to the lexicon directly; others (Hebrew,
        // until a Hebrew lexicon arrives) fall back to the search.
        final greek = strongs.where((s) => s.startsWith('G')).firstOrNull;
        final sort = greek == null ? null : int.tryParse(greek.substring(1));
        if (sort != null) anchor = 'G$sort';
      } catch (_) {}
    }
    var targets = _layout.allPanes
        .where((p) => p.kind == PaneKind.dictionary)
        .toList();
    if (targets.isEmpty) {
      final created = _addPane(PaneKind.dictionary);
      if (created == null) return;
      targets = [created];
    }
    setState(() {
      for (final pane in targets) {
        pane.anchor = anchor;
      }
    });
    _save();
  }

  Future<void> _import() => importFromPicker(
    context,
    onModulesChanged: () => setState(() => _modules = modules()),
    onPlansChanged: () => setState(() => _plans = ReadingPlan.fromLibrary()),
  );

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

  @override
  Widget build(BuildContext context) {
    if (!_initialized) return const SizedBox.shrink();
    final settings = SettingsScope.of(context);
    final reading = settings.readingMode;
    final appBar = DeskAppBar(
      plans: _plans,
      desks: _registry.desks,
      currentDeskId: _deskId,
      onSearch: _openSearch,
      onOpenPlan: _openReadingPlan,
      onExportLabels: _exportLabels,
      onSwitchDesk: _switchDesk,
      onNewDesk: _newDesk,
      onRenameDesk: _renameDesk,
      onDeleteDesk: _deleteDesk,
      onAddPane: _addPane,
      onSettings: () async {
        await showSettings(context);
        // Sync may have been (re)configured there.
        _syncPull();
      },
      onImport: _import,
    );
    // SafeArea keeps the desk clear of the status bar, notch, and home
    // indicator. The app bar takes its own space (ADR 0028, amended):
    // with chrome shown the desk starts below it and reflows.
    // Arrow keys not taken by the focused widget page the last active
    // text view (ADR 0028): a click on a toolbar button must not cost the
    // first arrow press.
    return Focus(
      skipTraversal: true,
      includeSemantics: false,
      onKeyEvent: (node, event) => ReaderFocus.handleStray(event),
      child: Scaffold(
        appBar: reading ? null : appBar,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, outer) {
              final narrow = outer.maxWidth < 500;
              return Padding(
                padding: EdgeInsets.fromLTRB(
                  narrow ? 10 : 24,
                  16,
                  narrow ? 10 : 24,
                  0,
                ),
                child: DeskGrid(
                  layout: _layout,
                  structureEpoch: _structureEpoch,
                  paneBuilder: _pane,
                  onChanged: _save,
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _pane(PaneSpec spec, Widget dragHandle) {
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
          modules: _bibleModules,
          onWordLookup: _lookupWord,
          followedAnchor: followedAnchor,
          followOptions: _followOptionsFor(spec),
          readingMode: settings.readingMode,
          onToggleMode: toggleMode,
          badge: badge,
          dragHandle: dragHandle,
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
          dragHandle: dragHandle,
          onFollow: (follow) => _setFollow(spec.id, follow),
          onClose: closable ? () => _closePane(spec.id) : null,
        );
      case PaneKind.dictionary:
        return DictionaryPane(
          key: ValueKey('pane-${spec.id}'),
          module: spec.module,
          modules: _dictionaryModules,
          onModule: (code) => _setModule(spec.id, code),
          anchor: spec.anchor,
          onAnchor: (anchor) => _setAnchor(spec.id, anchor),
          previewModule:
              settings.defaultModule ?? _bibleModules.firstOrNull?.code,
          readingMode: settings.readingMode,
          onToggleMode: toggleMode,
          badge: badge,
          onOpenReference: (osis) => _openReference(spec, osis),
          dragHandle: dragHandle,
          onClose: closable ? () => _closePane(spec.id) : null,
        );
      case PaneKind.book:
        return BookPane(
          key: ValueKey('pane-${spec.id}'),
          module: spec.module,
          modules: _bookModules,
          onModule: (code) => _setModule(spec.id, code),
          anchor: spec.anchor,
          onAnchor: (anchor) => _setAnchor(spec.id, anchor),
          previewModule:
              settings.defaultModule ?? _bibleModules.firstOrNull?.code,
          readingMode: settings.readingMode,
          onToggleMode: toggleMode,
          badge: badge,
          onOpenReference: (osis) => _openReference(spec, osis),
          onWordLookup: _lookupWord,
          dragHandle: dragHandle,
          onClose: closable ? () => _closePane(spec.id) : null,
        );
      case PaneKind.devotional:
        return DevotionalPane(
          key: ValueKey('pane-${spec.id}'),
          module: spec.module,
          modules: _devotionalModules,
          onModule: (code) => _setModule(spec.id, code),
          anchor: spec.anchor,
          onAnchor: (anchor) => _setAnchor(spec.id, anchor),
          previewModule:
              settings.defaultModule ?? _bibleModules.firstOrNull?.code,
          readingMode: settings.readingMode,
          onToggleMode: toggleMode,
          badge: badge,
          onOpenReference: (osis) => _openReference(spec, osis),
          onWordLookup: _lookupWord,
          dragHandle: dragHandle,
          onClose: closable ? () => _closePane(spec.id) : null,
        );
      case PaneKind.notes:
        return NotesPane(
          key: ValueKey('pane-${spec.id}'),
          readingMode: settings.readingMode,
          onToggleMode: toggleMode,
          badge: badge,
          onOpenReference: (osis) => _openReference(spec, osis),
          dragHandle: dragHandle,
          onClose: closable ? () => _closePane(spec.id) : null,
        );
      case PaneKind.commentary:
        return CommentaryPane(
          key: ValueKey('pane-${spec.id}'),
          module: spec.module,
          modules: _commentaryModules,
          onModule: (code) => _setModule(spec.id, code),
          followedAnchor: followedAnchor,
          followedAnchorEnd: _layout.byId(spec.follow)?.anchorEnd,
          sourceModule: _layout.byId(spec.follow)?.module,
          onOpenReference: (osis) => _openReference(spec, osis),
          onWordLookup: _lookupWord,
          followValue: spec.follow,
          followOptions: _followOptionsFor(spec),
          readingMode: settings.readingMode,
          onToggleMode: toggleMode,
          badge: badge,
          dragHandle: dragHandle,
          onFollow: (follow) => _setFollow(spec.id, follow),
          onClose: closable ? () => _closePane(spec.id) : null,
        );
    }
  }
}
