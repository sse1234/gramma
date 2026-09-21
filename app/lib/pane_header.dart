import 'package:flutter/material.dart';

import 'l10n.dart';
import 'pane_badge.dart';

/// A position link a pane can follow (ADR 0008): the source pane and how
/// it is shown in the link menu.
typedef FollowOption = ({
  String id,
  String label,
  String badge,
  int badgeIndex,
});

/// One dropdown row of the desk history (most recent first).
typedef HistoryItem = ({
  int index,
  String label,
  String badge,
  int badgeIndex,
  bool current,
});

typedef ModuleOption = ({String code, String title, bool strongs});

/// The small chrome badge of a Strong's-tagged text (ADR 0020).
class StrongsBadge extends StatelessWidget {
  const StrongsBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: context.l10n.strongsTagged,
      child: Icon(
        Icons.tag,
        size: 14,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }
}

/// Shared pane chrome: badge, module and position-link selectors, the
/// navigation cluster, and close/drag controls. Wide panes show everything
/// in one row; panes too narrow for that (phones) collapse the module,
/// history, link, and close controls into an overflow menu so nothing runs
/// off the screen edge.
class PaneHeader extends StatelessWidget {
  const PaneHeader({
    super.key,
    required this.title,
    this.badge,
    this.moduleCode,
    this.modules = const [],
    this.onModule,
    this.position,
    this.canGoBack = false,
    this.canGoForward = false,
    this.onBack,
    this.onForward,
    this.historyItems = const [],
    this.onHistorySelect,
    required this.followValue,
    required this.followOptions,
    required this.onFollow,
    this.dragHandle,
    this.onClose,
  });

  /// The pane width below which the chrome collapses to its compact form.
  static const compactBelow = 460.0;

  final String? title;
  final Widget? badge;

  /// Loaded module and the available alternatives (text panes only).
  final String? moduleCode;
  final List<ModuleOption> modules;
  final ValueChanged<String>? onModule;

  /// Position chip (the reference-selector trigger) for text panes.
  final Widget? position;

  /// Desk-global navigation (sender panes only; onBack == null hides it).
  final bool canGoBack;
  final bool canGoForward;
  final VoidCallback? onBack;
  final VoidCallback? onForward;
  final List<HistoryItem> historyItems;
  final ValueChanged<int>? onHistorySelect;

  final Widget? dragHandle;
  final String? followValue;
  final List<FollowOption> followOptions;

  /// Null hides the link selector entirely (views without a position
  /// link, e.g. the dictionary).
  final ValueChanged<String?>? onFollow;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth < compactBelow
          ? _compact(context, theme)
          : _wide(context, theme),
    );
  }

  Widget _wide(BuildContext context, ThemeData theme) {
    return Row(
      children: [
        if (badge != null) ...[badge!, const SizedBox(width: 8)],
        Expanded(
          child: onModule != null
              ? DropdownButton<String>(
                  key: const Key('module-select'),
                  isExpanded: true,
                  underline: const SizedBox.shrink(),
                  value: moduleCode,
                  items: [
                    for (final m in modules)
                      DropdownMenuItem(
                        value: m.code,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                m.title,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (m.strongs) ...[
                              const SizedBox(width: 4),
                              const StrongsBadge(),
                            ],
                          ],
                        ),
                      ),
                  ],
                  onChanged: (code) {
                    if (code != null) onModule!(code);
                  },
                )
              : Text(title ?? '', style: theme.textTheme.titleMedium),
        ),

        if (position != null) ...[
          const SizedBox(width: 8),
          Flexible(child: position!),
        ],
        if (onBack != null) ...[
          const SizedBox(width: 4),
          _backForward(context),
          _historyButton(context, theme),
        ],
        if (onFollow != null) ...[
          const SizedBox(width: 8),
          DropdownButton<String>(
            key: const Key('link-select'),
            underline: const SizedBox.shrink(),
            value: followValue,
            hint: Text(context.l10n.unlinked),
            items: [
              DropdownMenuItem<String>(child: Text(context.l10n.unlinked)),
              for (final option in followOptions)
                DropdownMenuItem(value: option.id, child: _linkRow(option)),
            ],
            onChanged: onFollow,
          ),
        ],
        if (onClose != null)
          IconButton(
            key: const Key('close-pane'),
            icon: const Icon(Icons.close, size: 18),
            tooltip: context.l10n.closeView,
            onPressed: onClose,
          ),
        ?dragHandle,
      ],
    );
  }

  Widget _compact(BuildContext context, ThemeData theme) {
    return Row(
      children: [
        if (badge != null) ...[badge!, const SizedBox(width: 6)],
        Expanded(
          child:
              position ??
              Text(
                title ?? '',
                style: theme.textTheme.titleMedium,
                overflow: TextOverflow.ellipsis,
              ),
        ),
        // The module chooser hides in the overflow menu here, so the
        // tagged badge is the only visible hint (ADR 0020).
        if (modules.any((m) => m.code == moduleCode && m.strongs))
          const StrongsBadge(key: Key('strongs-badge')),
        if (onBack != null) _backForward(context),
        _overflowMenu(context),
        ?dragHandle,
      ],
    );
  }

  Widget _backForward(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          key: const Key('nav-back'),
          tooltip: context.l10n.back,
          visualDensity: VisualDensity.compact,
          iconSize: 16,
          icon: const Icon(Icons.arrow_back),
          onPressed: canGoBack ? onBack : null,
        ),
        IconButton(
          key: const Key('nav-forward'),
          tooltip: context.l10n.forward,
          visualDensity: VisualDensity.compact,
          iconSize: 16,
          icon: const Icon(Icons.arrow_forward),
          onPressed: canGoForward ? onForward : null,
        ),
      ],
    );
  }

  Widget _historyButton(BuildContext context, ThemeData theme) {
    return PopupMenuButton<int>(
      key: const Key('nav-history'),
      tooltip: context.l10n.history,
      enabled: historyItems.isNotEmpty,
      icon: Icon(
        Icons.history,
        size: 16,
        color: historyItems.isEmpty
            ? theme.disabledColor
            : theme.colorScheme.onSurfaceVariant,
      ),
      onSelected: onHistorySelect,
      itemBuilder: (context) => [
        for (final item in historyItems) _historyRow(item),
      ],
    );
  }

  PopupMenuItem<int> _historyRow(HistoryItem item) {
    return PopupMenuItem(
      value: item.index,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PaneBadge(
            badge: item.badge,
            badgeIndex: item.badgeIndex,
            small: true,
          ),
          const SizedBox(width: 6),
          Text(
            item.label,
            style: item.current
                ? const TextStyle(fontWeight: FontWeight.w700)
                : null,
          ),
        ],
      ),
    );
  }

  Widget _linkRow(FollowOption option) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PaneBadge(
          badge: option.badge,
          badgeIndex: option.badgeIndex,
          small: true,
        ),
        const SizedBox(width: 6),
        Text(option.label),
      ],
    );
  }

  /// Everything that has no room in the compact row, as one menu whose
  /// items carry their own action.
  Widget _overflowMenu(BuildContext context) {
    final entries = <PopupMenuEntry<VoidCallback>>[];
    if (onModule != null) {
      for (final m in modules) {
        entries.add(
          CheckedPopupMenuItem(
            key: Key('menu-module-${m.code}'),
            checked: m.code == moduleCode,
            value: () => onModule!(m.code),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(child: Text(m.title, overflow: TextOverflow.ellipsis)),
                if (m.strongs) ...[
                  const SizedBox(width: 4),
                  const StrongsBadge(),
                ],
              ],
            ),
          ),
        );
      }
    }
    if (onHistorySelect != null && historyItems.isNotEmpty) {
      if (entries.isNotEmpty) entries.add(const PopupMenuDivider());
      for (final item in historyItems.take(6)) {
        entries.add(
          PopupMenuItem(
            value: () => onHistorySelect!(item.index),
            child: _historyRow(item).child!,
          ),
        );
      }
    }
    final follow = onFollow;
    if (follow != null) {
      if (entries.isNotEmpty) entries.add(const PopupMenuDivider());
      entries.add(
        CheckedPopupMenuItem(
          key: const Key('menu-unlinked'),
          checked: followValue == null,
          value: () => follow(null),
          child: Text(context.l10n.unlinked),
        ),
      );
      for (final option in followOptions) {
        entries.add(
          CheckedPopupMenuItem(
            key: Key('menu-link-${option.badge}'),
            checked: followValue == option.id,
            value: () => follow(option.id),
            child: _linkRow(option),
          ),
        );
      }
    }
    if (onClose != null) {
      entries.add(const PopupMenuDivider());
      entries.add(
        PopupMenuItem(
          key: const Key('menu-close'),
          value: onClose,
          child: Text(context.l10n.closeView),
        ),
      );
    }
    return PopupMenuButton<VoidCallback>(
      key: const Key('pane-menu'),
      tooltip: context.l10n.viewMenuTooltip,
      icon: const Icon(Icons.more_vert, size: 18),
      onSelected: (action) => action(),
      itemBuilder: (context) => entries,
    );
  }
}
