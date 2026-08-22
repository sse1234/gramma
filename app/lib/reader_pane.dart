import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import 'dart:async';

import 'column_plan.dart';
import 'column_snap_physics.dart';
import 'pane_model.dart';
import 'settings.dart';
import 'src/rust/api/library.dart';
import 'src/rust/api/references.dart';
import 'src/rust/api/typeset.dart';
import 'typeset_chapter.dart';
import 'typeset_column.dart';

typedef FollowOption = ({int index, String label});

/// One text view (ADR 0008): the endless-scrolling reader of ADR 0006 with
/// a header for choosing its module and its position link. Emits its
/// reading position and follows a linked pane's position when set.
class ReaderPane extends StatefulWidget {
  const ReaderPane({
    super.key,
    required this.spec,
    required this.modules,
    required this.followedAnchor,
    required this.followOptions,
    required this.onAnchor,
    required this.onModule,
    required this.onFollow,
    this.onClose,
  });

  final PaneSpec spec;
  final List<ModuleView> modules;
  final String? followedAnchor;
  final List<FollowOption> followOptions;
  final ValueChanged<String> onAnchor;
  final ValueChanged<String> onModule;
  final ValueChanged<int?> onFollow;
  final VoidCallback? onClose;

  @override
  State<ReaderPane> createState() => _ReaderPaneState();
}

class _ReaderPaneState extends State<ReaderPane> {
  static const _cacheLimit = 80;
  static const _headingLines = 2;
  static const _gutter = 48.0;

  double _columnWidth = SettingsController.defaultColumnWidth;
  double _lineSpacing = SettingsController.defaultLineSpacing;
  int? _measure;

  ModuleView? _active;
  List<ChapterRefView> _spine = const [];
  List<int>? _lineCounts;
  final Map<int, ChapterLayoutView> _layouts = {};
  final Set<int> _loading = {};

  int _anchorLine = 0;
  bool _suppressEmit = false;

  final ItemScrollController _vScroll = ItemScrollController();
  final ItemPositionsListener _vPositions = ItemPositionsListener.create();
  int _topChapter = 0;

  ScrollController? _hController;
  String? _hParams;
  final List<ScrollController> _staleControllers = [];
  ColumnPlan? _hPlan;
  double _hStride = 0;
  Timer? _wheelSnap;

  ParseOutcome? _outcome;
  String? _jumpMiss;

  @override
  void initState() {
    super.initState();
    _vPositions.itemPositions.addListener(_onVerticalPositions);
  }

  @override
  void dispose() {
    _vPositions.itemPositions.removeListener(_onVerticalPositions);
    _wheelSnap?.cancel();
    _hController?.dispose();
    for (final c in _staleControllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final settings = SettingsScope.of(context);
    _columnWidth = settings.columnWidth;
    _lineSpacing = settings.lineSpacing;
    final measure = settings.measureEms;
    if (_measure == null) {
      _measure = measure;
      _loadModule();
    } else if (_measure != measure) {
      _measure = measure;
      WidgetsBinding.instance.addPostFrameCallback((_) => _remeasure());
    }
  }

  @override
  void didUpdateWidget(ReaderPane old) {
    super.didUpdateWidget(old);
    if (widget.spec.module != _active?.code && widget.spec.module != null) {
      _loadModule();
    }
    if (widget.followedAnchor != old.followedAnchor &&
        widget.followedAnchor != null &&
        widget.spec.follow != null) {
      _applyRemoteAnchor(widget.followedAnchor!);
    }
  }

  String _osisOf(int chapter) =>
      '${_spine[chapter].bookOsis}.${_spine[chapter].chapter}';

  int _indexOfOsis(String osis) {
    final parts = osis.split('.');
    if (parts.length != 2) return -1;
    final chapter = int.tryParse(parts[1]);
    return _spine.indexWhere(
        (c) => c.bookOsis == parts[0] && c.chapter == chapter);
  }

  ColumnPlan? _linePlan({int linesPerColumn = 1}) {
    final counts = _lineCounts;
    if (counts == null || counts.length != _spine.length || counts.isEmpty) {
      return null;
    }
    return ColumnPlan(
      textLines: counts,
      headingLines: _headingLines,
      linesPerColumn: linesPerColumn,
    );
  }

  void _loadModule() {
    final available = widget.modules;
    setState(() {
      _active = available.isEmpty
          ? null
          : available.firstWhere(
              (m) => m.code == widget.spec.module,
              orElse: () => available.first,
            );
      _spine = _active == null ? const [] : contents(moduleCode: _active!.code);
      _layouts.clear();
      _loading.clear();
      _lineCounts = null;
      _anchorLine = 0;
      _topChapter = 0;
      _hParams = null;
      _hPlan = null;
    });
    final active = _active;
    if (active == null) return;
    if (active.code != widget.spec.module) {
      widget.onModule(active.code);
    }
    moduleLineCounts(moduleCode: active.code, measureEms: _measure!)
        .then((counts) {
      if (!mounted || _active?.code != active.code) return;
      setState(() {
        _lineCounts = counts.map((c) => c.toInt()).toList();
        _restoreAnchor();
      });
      if (_spine.isNotEmpty && !_suppressEmit) {
        widget.onAnchor(_osisOf(_topChapter));
      }
    });
  }

  void _restoreAnchor() {
    final target = widget.spec.follow != null
        ? (widget.followedAnchor ?? widget.spec.anchor)
        : widget.spec.anchor;
    if (target == null) return;
    final index = _indexOfOsis(target);
    final plan = _linePlan();
    if (index >= 0 && plan != null) {
      _topChapter = index;
      _anchorLine = plan.blockStart(index);
    }
  }

  void _remeasure() {
    if (!mounted) return;
    final keepChapter = _topChapter;
    setState(() {
      _layouts.clear();
      _loading.clear();
      _lineCounts = null;
      _hParams = null;
      _hPlan = null;
      _anchorLine = 0;
    });
    final active = _active;
    if (active == null) return;
    moduleLineCounts(moduleCode: active.code, measureEms: _measure!)
        .then((counts) {
      if (!mounted || _active?.code != active.code) return;
      setState(() {
        _lineCounts = counts.map((c) => c.toInt()).toList();
        final plan = _linePlan();
        if (plan != null && keepChapter < _spine.length) {
          _anchorLine = plan.blockStart(keepChapter);
          _topChapter = keepChapter;
        }
      });
    });
  }

  void _requestLayout(int index) {
    if (_layouts.containsKey(index) || _loading.contains(index)) return;
    _loading.add(index);
    final entry = _spine[index];
    layoutChapter(
      moduleCode: _active!.code,
      bookOsis: entry.bookOsis,
      chapter: entry.chapter,
      measureEms: _measure!,
    ).then((layout) {
      if (!mounted) return;
      setState(() {
        _layouts[index] = layout;
        while (_layouts.length > _cacheLimit) {
          _layouts.remove(_layouts.keys.first);
        }
      });
    }).whenComplete(() => _loading.remove(index));
  }

  void _setTopChapter(int top) {
    if (top == _topChapter) return;
    setState(() => _topChapter = top);
    if (!_suppressEmit && top < _spine.length) {
      widget.onAnchor(_osisOf(top));
    }
  }

  void _onVerticalPositions() {
    final positions = _vPositions.itemPositions.value;
    if (positions.isEmpty) return;
    final top = positions.where((p) => p.itemTrailingEdge > 0).fold<int?>(
        null, (min, p) => min == null || p.index < min ? p.index : min);
    if (top != null) {
      final plan = _linePlan();
      if (plan != null && top < _spine.length) {
        _anchorLine = plan.blockStart(top);
      }
      _setTopChapter(top);
    }
  }

  void _onHorizontalScroll() {
    final controller = _hController;
    final plan = _hPlan;
    if (controller == null || plan == null || !controller.hasClients) return;
    final column =
        (controller.offset / _hStride).floor().clamp(0, plan.columnCount - 1);
    final line = plan.firstLineOfColumn(column);
    if (line != _anchorLine) {
      _anchorLine = line;
      _setTopChapter(plan.chapterOfLine(line.clamp(0, plan.totalLines - 1)));
    }
  }

  void _applyRemoteAnchor(String osis) {
    final index = _indexOfOsis(osis);
    if (index < 0 || index == _topChapter) return;
    _suppressEmit = true;
    _jumpToChapter(index);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _suppressEmit = false;
    });
  }

  void _jumpToChapter(int index) {
    final plan = _hPlan;
    if (plan != null && _hController != null && _hController!.hasClients) {
      final line = plan.blockStart(index);
      _anchorLine = line;
      _hController!.jumpTo(
        (plan.columnOfLine(line) * _hStride)
            .clamp(0.0, _hController!.position.maxScrollExtent),
      );
    } else if (_vScroll.isAttached) {
      _vScroll.jumpTo(index: index);
    }
    _setTopChapter(index);
  }

  void _onInput(String input) {
    setState(() {
      _jumpMiss = null;
      _outcome = input.trim().isEmpty ? null : parseReference(input: input);
    });
    final osis = _outcome?.osis;
    if (osis == null) return;
    final parts = osis.split('-').first.split('.');
    final index = _indexOfOsis('${parts[0]}.${parts[1]}');
    if (index < 0) {
      setState(
          () => _jumpMiss = 'Not in this module: ${parts[0]} ${parts[1]}');
      return;
    }
    _jumpToChapter(index);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final position =
        _topChapter < _spine.length ? _spine[_topChapter].heading : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PaneHeader(
          title: null,
          moduleSelector: DropdownButton<String>(
            key: const Key('module-select'),
            isExpanded: true,
            underline: const SizedBox.shrink(),
            value: _active?.code,
            items: [
              for (final m in widget.modules)
                DropdownMenuItem(value: m.code, child: Text(m.title)),
            ],
            onChanged: (code) {
              if (code != null) widget.onModule(code);
            },
          ),
          followValue: widget.spec.follow,
          followOptions: widget.followOptions,
          onFollow: widget.onFollow,
          onClose: widget.onClose,
        ),
        TextField(
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            isDense: true,
            labelText: 'Go to reference',
            hintText: 'Joh 3,16 · Ps 23',
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
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = _columnsFor(constraints.maxWidth);
                    if (columns >= 2 && _linePlan() != null) {
                      return _horizontalReader(constraints, columns);
                    }
                    _hPlan = null;
                    _hParams = null;
                    return _verticalReader();
                  },
                ),
        ),
      ],
    );
  }

  int _columnsFor(double width) {
    final n = ((width + _gutter) / (_columnWidth + _gutter)).floor();
    return n < 1 ? 1 : n;
  }

  Widget _verticalReader() {
    final plan = _linePlan();
    var initial = 0;
    if (plan != null && plan.totalLines > 0) {
      initial = plan.chapterOfLine(_anchorLine.clamp(0, plan.totalLines - 1));
    }
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: _columnWidth),
        child: ScrollablePositionedList.builder(
          key: const Key('vertical-reader'),
          itemScrollController: _vScroll,
          itemPositionsListener: _vPositions,
          initialScrollIndex: initial,
          itemCount: _spine.length,
          itemBuilder: _chapterItem,
        ),
      ),
    );
  }

  Widget _horizontalReader(BoxConstraints constraints, int columns) {
    final columnWidth = _columnWidth;
    final contentWidth = columns * columnWidth + (columns - 1) * _gutter;
    final sidePadding =
        ((constraints.maxWidth - contentWidth) / 2).clamp(0.0, double.infinity);
    final fontSize = columnWidth / _measure!;
    final lineHeight = fontSize * _lineSpacing;
    var linesPerColumn = (constraints.maxHeight / lineHeight).floor();
    if (linesPerColumn < 1) linesPerColumn = 1;
    final plan = _linePlan(linesPerColumn: linesPerColumn)!;
    final stride = columnWidth + _gutter;
    final params = '$columns-$linesPerColumn-${columnWidth.round()}';
    if (params != _hParams) {
      final old = _hController;
      if (old != null) {
        old.removeListener(_onHorizontalScroll);
        _staleControllers.add(old);
      }
      _hController = ScrollController(
        initialScrollOffset: plan.columnOfLine(_anchorLine) * stride,
      )..addListener(_onHorizontalScroll);
      _hParams = params;
    }
    _hPlan = plan;
    _hStride = stride;
    final scale = columnWidth / (_measure! * _unitsPerEm());
    return Listener(
      key: const ValueKey('columns-active'),
      onPointerSignal: (event) {
        if (event is PointerScrollEvent &&
            event.scrollDelta.dy != 0 &&
            _hController!.hasClients) {
          final target = (_hController!.offset + event.scrollDelta.dy)
              .clamp(0.0, _hController!.position.maxScrollExtent);
          _hController!.jumpTo(target);
          // Wheel and trackpad deltas move freely; settle on the nearest
          // column shortly after the burst ends.
          _wheelSnap?.cancel();
          _wheelSnap = Timer(const Duration(milliseconds: 180), () {
            final controller = _hController;
            if (controller == null || !controller.hasClients || !mounted) {
              return;
            }
            final position = controller.position;
            final snapped = ColumnSnapPhysics.snapTarget(
              position.pixels,
              _hStride,
              position.minScrollExtent,
              position.maxScrollExtent,
            );
            if ((snapped - position.pixels).abs() > 0.5) {
              controller.animateTo(
                snapped,
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
              );
            }
          });
        }
      },
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: sidePadding),
        child: ListView.builder(
          key: Key('horizontal-reader-$params'),
          controller: _hController,
          scrollDirection: Axis.horizontal,
          physics: ColumnSnapPhysics(stride: stride),
          itemExtent: stride,
          itemCount: plan.columnCount,
          itemBuilder: (context, column) => Padding(
            padding: const EdgeInsets.only(right: _gutter),
            child: _columnItem(plan, column, scale, fontSize, lineHeight),
          ),
        ),
      ),
    );
  }

  double _unitsPerEm() {
    for (final layout in _layouts.values) {
      return layout.unitsPerEm.toDouble();
    }
    return 2048;
  }

  Widget _columnItem(
    ColumnPlan plan,
    int column,
    double scale,
    double fontSize,
    double lineHeight,
  ) {
    final rows = <ColumnRow>[];
    final first = plan.firstLineOfColumn(column);
    for (var row = 0; row < plan.linesPerColumn; row++) {
      final located = plan.locate(first + row);
      if (located == null) break;
      final (:chapter, :local) = located;
      if (local == 0) {
        rows.add(HeadingRow(row, _spine[chapter].heading));
      } else if (local >= _headingLines) {
        final layout = _layouts[chapter];
        if (layout == null) {
          _requestLayout(chapter);
          continue;
        }
        final lineIndex = local - _headingLines;
        if (lineIndex < layout.lines.length) {
          rows.add(TextRow(row, layout.lines[lineIndex], layout.numberScale));
        }
      }
    }
    return TypesetColumn(
      rows: rows,
      rowCount: plan.linesPerColumn,
      scale: scale,
      fontSize: fontSize,
      lineHeight: lineHeight,
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

  double _estimatedHeight(int index, double columnWidth) {
    final fontSize = columnWidth / _measure!;
    final lineHeight = fontSize * _lineSpacing;
    final charsPerLine = _measure! * 2.1;
    final lines = (_spine[index].textLength / charsPerLine).ceil() + 1;
    return lines * lineHeight;
  }

  Widget _chapterItem(BuildContext context, int index) {
    final theme = Theme.of(context);
    final entry = _spine[index];
    final layout = _layouts[index];
    if (layout == null) {
      _requestLayout(index);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 12),
            child: Text(
              entry.heading,
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontFamily: 'GentiumBookPlus'),
            ),
          ),
          if (layout != null)
            TypesetChapter(layout: layout, lineHeightEm: _lineSpacing)
          else
            LayoutBuilder(
              builder: (context, constraints) => SizedBox(
                key: const Key('chapter-placeholder'),
                height: _estimatedHeight(index, constraints.maxWidth),
              ),
            ),
        ],
      ),
    );
  }
}

/// Shared pane chrome: an optional title or module selector, the position
/// link selector, and an optional close button.
class PaneHeader extends StatelessWidget {
  const PaneHeader({
    super.key,
    required this.title,
    this.moduleSelector,
    required this.followValue,
    required this.followOptions,
    required this.onFollow,
    this.onClose,
  });

  final String? title;
  final Widget? moduleSelector;
  final int? followValue;
  final List<FollowOption> followOptions;
  final ValueChanged<int?> onFollow;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: moduleSelector ??
              Text(title ?? '', style: theme.textTheme.titleMedium),
        ),
        const SizedBox(width: 8),
        DropdownButton<int>(
          key: const Key('link-select'),
          underline: const SizedBox.shrink(),
          value: followValue,
          hint: const Text('Unlinked'),
          items: [
            const DropdownMenuItem<int>(child: Text('Unlinked')),
            for (final option in followOptions)
              DropdownMenuItem(value: option.index, child: Text(option.label)),
          ],
          onChanged: onFollow,
        ),
        if (onClose != null)
          IconButton(
            key: const Key('close-pane'),
            icon: const Icon(Icons.close, size: 18),
            tooltip: 'Close view',
            onPressed: onClose,
          ),
      ],
    );
  }
}
