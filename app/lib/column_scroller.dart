import 'package:flutter/widgets.dart';

import 'column_plan.dart';
import 'column_snap_physics.dart';

/// The column paging state of one text view in multi-column mode
/// (ADR 0006, 0026, 0028): the horizontal scroll controller, the column
/// plan it scrolls, and the anchor line — the first line of the first
/// visible column — which is what survives a re-chunk, a mode toggle, and
/// a module reload.
///
/// The owner builds plans (it holds the line counts); this object decides
/// when a new one is needed and keeps the reader's place across it.
class ColumnScroller {
  ColumnScroller({required this.onScrolled});

  /// Called after a scroll moved [anchorLine] to a new line.
  final VoidCallback onScrolled;

  /// Wheel travel that advances one column.
  static const wheelTick = 50.0;

  /// Wheel ticks and key presses closer than this chain onto one target.
  static const _chain = Duration(milliseconds: 600);

  ScrollController? controller;
  ColumnPlan? plan;
  double stride = 0;
  int columns = 1;

  /// First line of the first visible column.
  int anchorLine = 0;

  int _origin = 0;
  String? _params;
  final List<ScrollController> _stale = [];

  double _wheelAccum = 0;
  double? _wheelTarget;
  DateTime _lastWheel = DateTime.fromMillisecondsSinceEpoch(0);

  /// Whether a plan is laid out and its controller drives a list.
  bool get attached => plan != null && (controller?.hasClients ?? false);

  /// The geometry key of the current layout, for widget keys.
  String get params => _params ?? '';

  /// Lays the columns out for a viewport. A changed geometry — column
  /// count, lines per column, or width — re-chunks the lines with the
  /// anchor as the plan's origin, so the line the reader was looking at
  /// heads the first column again rather than landing inside one
  /// (ADR 0028 as amended), and replaces the controller at that column.
  ColumnPlan layout({
    required int columns,
    required int linesPerColumn,
    required double columnWidth,
    required double stride,
    required ColumnPlan Function({
      required int linesPerColumn,
      required int origin,
    })
    buildPlan,
  }) {
    final params = '$columns-$linesPerColumn-${columnWidth.round()}';
    final changed = params != _params;
    if (changed) _origin = anchorLine;
    final built = buildPlan(linesPerColumn: linesPerColumn, origin: _origin);
    if (changed) {
      final old = controller;
      if (old != null) {
        old.removeListener(_onScroll);
        _stale.add(old);
      }
      controller = ScrollController(
        initialScrollOffset: built.columnOfLine(anchorLine) * stride,
      )..addListener(_onScroll);
      _params = params;
    }
    plan = built;
    this.stride = stride;
    this.columns = columns;
    return built;
  }

  /// Vertical mode: no plan; the next [layout] starts from the anchor.
  void detach() {
    plan = null;
    _params = null;
  }

  /// A module reload or re-measure: everything starts over at line 0.
  void reset() {
    detach();
    anchorLine = 0;
  }

  void _onScroll() {
    final c = controller;
    final p = plan;
    if (c == null || p == null || !c.hasClients) return;
    final column = (c.offset / stride).floor().clamp(0, p.columnCount - 1);
    final line = p.firstLineOfColumn(column);
    if (line == anchorLine) return;
    anchorLine = line;
    onScrolled();
  }

  /// Last line of the last visible column; null outside column mode.
  int? get lastVisibleLine {
    final p = plan;
    if (p == null || p.totalLines == 0) return null;
    final lastColumn = (p.columnOfLine(anchorLine) + columns - 1).clamp(
      0,
      p.columnCount - 1,
    );
    return (p.firstLineOfColumn(lastColumn) + p.linesInColumn(lastColumn) - 1)
        .clamp(0, p.totalLines - 1);
  }

  /// Shows the column holding [line] first, without animation. The
  /// anchor is that column's first line, so a later re-chunk starts a
  /// column there and not at a verse in the column's middle.
  void jumpToLine(int line) {
    final c = controller;
    final p = plan;
    if (c == null || p == null || !c.hasClients) return;
    anchorLine = p.firstLineOfColumn(p.columnOfLine(line));
    c.jumpTo(
      (p.columnOfLine(line) * stride).clamp(0.0, c.position.maxScrollExtent),
    );
  }

  /// Discrete mouse wheels page by whole columns: one column per wheel
  /// motion, however large the accelerated delta — a notch is a discrete
  /// step, not a distance.
  void onWheel(double delta) {
    final now = DateTime.now();
    if (now.difference(_lastWheel) > _chain) {
      _wheelAccum = 0;
      _wheelTarget = null;
    }
    _lastWheel = now;
    _wheelAccum += delta;
    if (_wheelAccum.abs() < wheelTick) return;
    final steps = _wheelAccum.sign.toInt();
    _wheelAccum = 0;
    step(steps);
  }

  /// Page by [steps] whole columns; wheel ticks and arrow keys share the
  /// chained target so rapid input queues cleanly.
  void step(int steps) {
    final c = controller;
    if (c == null || !c.hasClients) return;
    if (DateTime.now().difference(_lastWheel) > _chain) {
      _wheelTarget = null;
    }
    final position = c.position;
    final base =
        _wheelTarget ??
        ColumnSnapPhysics.snapTarget(
          position.pixels,
          stride,
          position.minScrollExtent,
          position.maxScrollExtent,
        );
    final target = ColumnSnapPhysics.snapTarget(
      base + steps * stride,
      stride,
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    _wheelTarget = target;
    _lastWheel = DateTime.now();
    if ((target - position.pixels).abs() > 0.5) {
      c.animateTo(
        target,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void dispose() {
    controller?.dispose();
    for (final c in _stale) {
      c.dispose();
    }
  }
}
