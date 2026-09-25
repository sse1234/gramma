import 'package:flutter/material.dart';

import 'pane_model.dart';
import 'settings.dart';

/// The desk's tiling (ADR 0008): resizable columns of stacked panes with
/// grips between the tiles, column widths snapped to whole column-width
/// multiples (constant zoom, ADR 0006), and drag-and-drop rearrangement.
/// Owns the geometry only: the layout model belongs to the screen, which
/// is told whenever a weight or the structure changed so it can persist.
class DeskGrid extends StatefulWidget {
  const DeskGrid({
    super.key,
    required this.layout,
    required this.structureEpoch,
    required this.paneBuilder,
    required this.onChanged,
  });

  final LayoutModel layout;

  /// Bumped by the owner after a structural change made elsewhere (a pane
  /// added or closed): the next build snaps all column boundaries.
  final int structureEpoch;

  /// Builds a pane's content; [dragHandle] goes into its header and starts
  /// a rearrangement drag.
  final Widget Function(PaneSpec spec, Widget dragHandle) paneBuilder;

  /// A weight or the structure changed and should be persisted.
  final VoidCallback onChanged;

  static const gripThickness = 12.0;
  static const minPaneExtent = 140.0;
  static const gutter = 48.0;

  @override
  State<DeskGrid> createState() => _DeskGridState();
}

class _DeskGridState extends State<DeskGrid> {
  /// Pane id currently being dragged for rearrangement, if any.
  String? _draggingPane;

  /// Set when the tiling changed structurally; the next build snaps all
  /// column boundaries to the grid.
  bool _snapPending = false;

  /// Last content width the desk was built at, to snap on window resize.
  double? _deskWidth;

  LayoutModel get _layout => widget.layout;

  @override
  void didUpdateWidget(DeskGrid old) {
    super.didUpdateWidget(old);
    if (widget.structureEpoch != old.structureEpoch) _snapPending = true;
  }

  void _dragColumns(int left, double dx, double contentWidth) {
    final columns = _layout.columns;
    final sum = columns.fold(0.0, (a, c) => a + c.weight);
    final minWeight = DeskGrid.minPaneExtent / contentWidth * sum;
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
    if (!_applySnap(left, contentWidth, fromDrag: true)) return;
    setState(() {});
    widget.onChanged();
  }

  bool _applySnap(
    int left,
    double contentWidth, {
    bool fromDrag = false,
    bool keepEven = false,
  }) {
    final columns = _layout.columns;
    final sum = columns.fold(0.0, (a, c) => a + c.weight);
    final leftWidth = columns[left].weight / sum * contentWidth;
    final rightWidth = columns[left + 1].weight / sum * contentWidth;
    final available = leftWidth + rightWidth - DeskGrid.minPaneExtent;
    final columnWidth = SettingsScope.of(context).columnWidth;
    final onGrid = snapToColumns(
      leftWidth,
      columnWidth,
      DeskGrid.gutter,
      available,
    );
    // A divider released nearer the middle than a whole number of text
    // columns splits the pair evenly — a desk split down the middle is
    // wanted even when a text view then carries margins around its
    // columns. A window resize keeps an even split that exists; a
    // structural change (a new or moved pane) takes the grid.
    final even = (leftWidth + rightWidth) / 2;
    final isEven = (even - leftWidth).abs() < 1;
    final target =
        (fromDrag && (even - leftWidth).abs() < (onGrid - leftWidth).abs()) ||
            (keepEven && isEven)
        ? even
        : onGrid;
    final dw = (target - leftWidth) / contentWidth * sum;
    if (dw.abs() < 1e-6) return false;
    columns[left].weight += dw;
    columns[left + 1].weight -= dw;
    return true;
  }

  /// A structural tiling change (new pane, drag, close) or a window
  /// resize lands on the column grid immediately — the same snap a
  /// divider release applies — instead of waiting for a manual drag.
  void _snapAllColumns(double contentWidth, {required bool keepEven}) {
    if (_layout.columns.length < 2) return;
    var moved = false;
    for (var left = 0; left < _layout.columns.length - 1; left++) {
      moved = _applySnap(left, contentWidth, keepEven: keepEven) || moved;
    }
    if (!moved) return;
    setState(() {});
    widget.onChanged();
  }

  void _dragRows(PaneColumn column, int top, double dy, double contentHeight) {
    final sum = column.panes.fold(0.0, (a, p) => a + p.weight);
    final minWeight = DeskGrid.minPaneExtent / contentHeight * sum;
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
            child: Icon(switch (spec.kind) {
              PaneKind.footnotes => Icons.notes_outlined,
              PaneKind.commentary => Icons.comment_outlined,
              PaneKind.dictionary => Icons.translate_outlined,
              PaneKind.book => Icons.auto_stories_outlined,
              PaneKind.devotional => Icons.today_outlined,
              PaneKind.notes => Icons.edit_note_outlined,
              PaneKind.text => Icons.menu_book_outlined,
            }, size: 20),
          ),
        ),
        // A taller grab area (the icon alone was hard to catch on touch
        // screens): the header row has no width to spare, so the target
        // grows in height only; transparent color keeps the box hittable.
        child: Container(
          key: Key('drag-handle-${spec.id}'),
          width: 26,
          height: 44,
          color: Colors.transparent,
          alignment: Alignment.center,
          child: Icon(
            Icons.drag_indicator,
            size: 20,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  void _dropIntoStack(PaneColumn column, int index, String id) {
    setState(() => _layout.moveIntoStack(id, column, index));
    _snapPending = true;
    widget.onChanged();
  }

  void _dropAsNewColumn(PaneColumn? after, String id) {
    setState(() => _layout.moveToNewColumn(id, after: after));
    _snapPending = true;
    widget.onChanged();
  }

  /// Drop zones shown while a pane is being dragged: vertical strips at
  /// every column boundary (drop = new column there) and horizontal strips
  /// at every stack boundary (drop = insert into that stack). Boundaries
  /// where the drop would recreate the current layout (the dragged pane's
  /// own position) are not offered.
  List<Widget> _dropTargets(BoxConstraints constraints) {
    const grip = DeskGrid.gripThickness;
    final columns = _layout.columns;
    final dragColumn = _layout.columnOf(_draggingPane ?? '');
    final dragColumnIndex = dragColumn == null
        ? -1
        : columns.indexOf(dragColumn);
    final dragAlone = dragColumn != null && dragColumn.panes.length == 1;
    final dragPaneIndex =
        dragColumn?.panes.indexWhere((p) => p.id == _draggingPane) ?? -1;
    bool columnNoop(int k) =>
        dragAlone && (k == dragColumnIndex || k == dragColumnIndex + 1);
    bool stackNoop(int k, int j) =>
        k == dragColumnIndex && (j == dragPaneIndex || j == dragPaneIndex + 1);
    final contentWidth = constraints.maxWidth - (columns.length - 1) * grip;
    final sumW = columns.fold(0.0, (a, c) => a + c.weight);
    final widths = [for (final c in columns) c.weight / sumW * contentWidth];
    final targets = <Widget>[];
    var x = 0.0;
    for (var k = 0; k <= columns.length; k++) {
      final centerX = k == 0
          ? 0.0
          : k == columns.length
          ? constraints.maxWidth
          : x - grip / 2;
      if (!columnNoop(k)) {
        targets.add(
          Positioned(
            left: (centerX - 28).clamp(0.0, constraints.maxWidth - 56),
            width: 56,
            top: 0,
            height: constraints.maxHeight,
            child: _DropZone(
              key: Key('drop-column-$k'),
              onAccept: (id) =>
                  _dropAsNewColumn(k == 0 ? null : columns[k - 1], id),
            ),
          ),
        );
      }
      if (k < columns.length) {
        final columnLeft = x;
        final width = widths[k];
        final panes = columns[k].panes;
        final contentHeight = constraints.maxHeight - (panes.length - 1) * grip;
        final sumH = panes.fold(0.0, (a, p) => a + p.weight);
        var y = 0.0;
        for (var j = 0; j <= panes.length; j++) {
          final centerY = j == 0
              ? 0.0
              : j == panes.length
              ? constraints.maxHeight
              : y - grip / 2;
          if (!stackNoop(k, j)) {
            targets.add(
              Positioned(
                left: columnLeft + 64,
                width: (width - 128).clamp(48.0, double.infinity),
                top: (centerY - 30).clamp(0.0, constraints.maxHeight - 60),
                height: 60,
                child: _DropZone(
                  key: Key('drop-stack-$k-$j'),
                  onAccept: (id) => _dropIntoStack(columns[k], j, id),
                ),
              ),
            );
          }
          if (j < panes.length) {
            y += panes[j].weight / sumH * contentHeight + grip;
          }
        }
        x += width + grip;
      }
    }
    return targets;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = _layout.columns;
        final contentWidth =
            constraints.maxWidth -
            (columns.length - 1) * DeskGrid.gripThickness;
        final resized =
            _deskWidth != null && (_deskWidth! - contentWidth).abs() > 0.5;
        _deskWidth = contentWidth;
        if (_snapPending || resized) {
          final structural = _snapPending;
          _snapPending = false;
          if (columns.length > 1) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _snapAllColumns(contentWidth, keepEven: !structural);
              }
            });
          }
        }
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
            constraints.maxHeight - (panes.length - 1) * DeskGrid.gripThickness;
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
                  onEnd: widget.onChanged,
                ),
              SizedBox(
                height: panes[j].weight / sum * contentHeight,
                child: widget.paneBuilder(panes[j], _dragHandle(panes[j])),
              ),
            ],
          ],
        );
      },
    );
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
        onHorizontalDragUpdate: horizontal ? (d) => onDrag(d.delta.dx) : null,
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
