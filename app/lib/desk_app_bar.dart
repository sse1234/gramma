import 'package:flutter/material.dart';

import 'desks.dart';
import 'l10n.dart';
import 'pane_model.dart';
import 'reading_plan.dart';

/// The desk's app bar: the tools menu (search, reading plans, export),
/// the desk switcher, the add-view menu, settings, and import. Pure
/// chrome — every action is a callback into the screen.
class DeskAppBar extends StatelessWidget implements PreferredSizeWidget {
  const DeskAppBar({
    super.key,
    required this.plans,
    required this.desks,
    required this.currentDeskId,
    required this.onSearch,
    required this.onOpenPlan,
    required this.onExportLabels,
    required this.onSwitchDesk,
    required this.onNewDesk,
    required this.onRenameDesk,
    required this.onDeleteDesk,
    required this.onAddPane,
    required this.onSettings,
    required this.onImport,
  });

  final List<ReadingPlan> plans;
  final List<DeskInfo> desks;
  final String currentDeskId;
  final VoidCallback onSearch;
  final ValueChanged<ReadingPlan> onOpenPlan;
  final VoidCallback onExportLabels;
  final ValueChanged<String> onSwitchDesk;
  final VoidCallback onNewDesk;
  final VoidCallback onRenameDesk;
  final VoidCallback onDeleteDesk;
  final ValueChanged<PaneKind> onAddPane;
  final VoidCallback onSettings;
  final VoidCallback onImport;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final current = desks.where((d) => d.id == currentDeskId).firstOrNull;
    return AppBar(
      title: const Text('gramma'),
      actions: [
        PopupMenuButton<VoidCallback>(
          key: const Key('tools-menu'),
          tooltip: context.l10n.toolsTooltip,
          icon: const Icon(Icons.auto_stories_outlined),
          onSelected: (action) => action(),
          itemBuilder: (context) => [
            PopupMenuItem(
              key: const Key('tool-search'),
              value: onSearch,
              child: Text(context.l10n.searchTool),
            ),
            for (final (i, plan) in plans.indexed)
              PopupMenuItem(
                key: Key('tool-plan-$i'),
                value: () => onOpenPlan(plan),
                child: Text('${context.l10n.readingPlan} · ${plan.name}'),
              ),
            PopupMenuItem(
              key: const Key('tool-export-labels'),
              value: onExportLabels,
              child: Text(context.l10n.exportLabels),
            ),
          ],
        ),
        PopupMenuButton<VoidCallback>(
          key: const Key('desk-menu'),
          tooltip: context.l10n.desksTooltip(current?.name ?? ''),
          icon: const Icon(Icons.desk_outlined),
          onSelected: (action) => action(),
          itemBuilder: (context) => [
            for (final desk in desks)
              CheckedPopupMenuItem(
                key: Key('desk-item-${desk.name}'),
                checked: desk.id == currentDeskId,
                value: () => onSwitchDesk(desk.id),
                child: Text(desk.name),
              ),
            const PopupMenuDivider(),
            PopupMenuItem(
              key: const Key('desk-new'),
              value: onNewDesk,
              child: Text(context.l10n.newDesk),
            ),
            PopupMenuItem(
              key: const Key('desk-rename'),
              value: onRenameDesk,
              child: Text(context.l10n.renameDeskMenu),
            ),
            if (desks.length > 1)
              PopupMenuItem(
                key: const Key('desk-delete'),
                value: onDeleteDesk,
                child: Text(context.l10n.deleteDeskMenu),
              ),
          ],
        ),
        PopupMenuButton<PaneKind>(
          key: const Key('add-view'),
          tooltip: context.l10n.addViewTooltip,
          icon: const Icon(Icons.vertical_split_outlined),
          onSelected: onAddPane,
          itemBuilder: (context) => [
            PopupMenuItem(
              value: PaneKind.text,
              child: Text(context.l10n.textView),
            ),
            PopupMenuItem(
              value: PaneKind.footnotes,
              child: Text(context.l10n.footnotesView),
            ),
            PopupMenuItem(
              key: const Key('add-commentary'),
              value: PaneKind.commentary,
              child: Text(context.l10n.commentaryView),
            ),
            PopupMenuItem(
              key: const Key('add-dictionary'),
              value: PaneKind.dictionary,
              child: Text(context.l10n.dictionaryView),
            ),
            PopupMenuItem(
              key: const Key('add-book'),
              value: PaneKind.book,
              child: Text(context.l10n.bookView),
            ),
            PopupMenuItem(
              key: const Key('add-devotional'),
              value: PaneKind.devotional,
              child: Text(context.l10n.devotionalView),
            ),
            PopupMenuItem(
              key: const Key('add-notes'),
              value: PaneKind.notes,
              child: Text(context.l10n.notesTitle),
            ),
          ],
        ),
        IconButton(
          key: const Key('open-settings'),
          tooltip: context.l10n.settingsTooltip,
          icon: const Icon(Icons.settings_outlined),
          onPressed: onSettings,
        ),
        IconButton(
          key: const Key('import-osis'),
          tooltip: context.l10n.importOsisTooltip,
          icon: const Icon(Icons.library_add_outlined),
          onPressed: onImport,
        ),
      ],
    );
  }
}
