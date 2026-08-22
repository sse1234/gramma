import 'package:file_selector/file_selector.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import 'column_plan.dart';
import 'src/rust/api/library.dart';
import 'src/rust/api/references.dart';
import 'src/rust/api/typeset.dart';
import 'typeset_chapter.dart';
import 'typeset_column.dart';

/// Endless-scrolling reader over a module's chapter spine.
///
/// Narrow viewports read as one vertical column. When two or more columns
/// fit, the same canonical line stream wraps into viewport-height columns
/// scrolled horizontally; resizing re-chunks the stream without any
/// re-layout, and the reading position carries across mode switches.
class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key});

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  static const _cacheLimit = 80;
  static const _headingLines = 2;
  /// Fixed column width: the constant zoom level (a user setting later).
  /// Viewport width that is not an integer multiple of columns becomes side
  /// padding instead of scaling the type.
  static const _baseColumnWidth = 400.0;
  static const _gutter = 48.0;
  static const _measureEms = 26.0;

  ModuleView? _active;
  List<ChapterRefView> _spine = const [];
  List<int>? _lineCounts;
  final Map<int, ChapterLayoutView> _layouts = {};
  final Set<int> _loading = {};

  /// Global line at the top/left of the viewport; survives mode switches
  /// and window resizes.
  int _anchorLine = 0;

  // Vertical mode.
  final ItemScrollController _vScroll = ItemScrollController();
  final ItemPositionsListener _vPositions = ItemPositionsListener.create();
  int _topChapter = 0;

  // Horizontal mode; the controller is recreated when the chunking changes.
  ScrollController? _hController;
  String? _hParams;
  final List<ScrollController> _staleControllers = [];
  ColumnPlan? _hPlan;
  double _hStride = 0;

  ParseOutcome? _outcome;
  String? _jumpMiss;

  @override
  void initState() {
    super.initState();
    _vPositions.itemPositions.addListener(_onVerticalPositions);
    _refreshModules();
  }

  @override
  void dispose() {
    _vPositions.itemPositions.removeListener(_onVerticalPositions);
    _hController?.dispose();
    for (final c in _staleControllers) {
      c.dispose();
    }
    super.dispose();
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

  void _refreshModules({String? select}) {
    final available = modules();
    setState(() {
      _active = available.isEmpty
          ? null
          : available.firstWhere(
              (m) => m.code == (select ?? _active?.code),
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
    if (active != null) {
      moduleLineCounts(moduleCode: active.code).then((counts) {
        if (!mounted || _active?.code != active.code) return;
        setState(() => _lineCounts = counts.map((c) => c.toInt()).toList());
      });
    }
  }

  void _requestLayout(int index) {
    if (_layouts.containsKey(index) || _loading.contains(index)) return;
    _loading.add(index);
    final entry = _spine[index];
    layoutChapter(
      moduleCode: _active!.code,
      bookOsis: entry.bookOsis,
      chapter: entry.chapter,
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

  void _onVerticalPositions() {
    final positions = _vPositions.itemPositions.value;
    if (positions.isEmpty) return;
    final top = positions.where((p) => p.itemTrailingEdge > 0).fold<int?>(
        null, (min, p) => min == null || p.index < min ? p.index : min);
    if (top != null && top != _topChapter) {
      setState(() {
        _topChapter = top;
        final plan = _linePlan();
        if (plan != null) {
          _anchorLine = plan.blockStart(top);
        }
      });
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
      setState(() {
        _anchorLine = line;
        _topChapter = plan.chapterOfLine(line.clamp(0, plan.totalLines - 1));
      });
    }
  }

  void _onInput(String input) {
    setState(() {
      _jumpMiss = null;
      _outcome = input.trim().isEmpty ? null : parseReference(input: input);
    });
    final osis = _outcome?.osis;
    if (osis == null) return;
    final parts = osis.split('-').first.split('.');
    final book = parts[0];
    final chapter = int.parse(parts[1]);
    final index =
        _spine.indexWhere((c) => c.bookOsis == book && c.chapter == chapter);
    if (index < 0) {
      setState(() => _jumpMiss = 'Not in this module: $book $chapter');
      return;
    }
    final plan = _hPlan;
    if (plan != null && _hController != null && _hController!.hasClients) {
      final line = plan.blockStart(index);
      final column = plan.columnOfLine(line);
      _anchorLine = line;
      _hController!.jumpTo(
        (column * _hStride).clamp(0.0, _hController!.position.maxScrollExtent),
      );
    } else if (_vScroll.isAttached) {
      _vScroll.jumpTo(index: index);
    }
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
      _refreshModules(select: imported.code);
      messenger.showSnackBar(SnackBar(
        content: Text('Imported ${imported.title} (${imported.verses} verses)'),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Import failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final position =
        _topChapter < _spine.length ? _spine[_topChapter].heading : null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('gramma'),
        actions: [
          IconButton(
            key: const Key('import-osis'),
            tooltip: 'Import OSIS…',
            icon: const Icon(Icons.library_add_outlined),
            onPressed: _importOsis,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: TextField(
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    isDense: true,
                    labelText: 'Go to reference',
                    hintText: 'Joh 3,16 · 1 Kor 13,4-7 · Ps 23',
                    helperText: _active == null
                        ? 'No module imported yet — use the library button above'
                        : _active!.title,
                  ),
                  onChanged: _onInput,
                ),
              ),
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
        ),
      ),
    );
  }

  int _columnsFor(double width) {
    final n = ((width + _gutter) / (_baseColumnWidth + _gutter)).floor();
    return n < 1 ? 1 : n;
  }

  Widget _verticalReader() {
    final plan = _linePlan();
    var initial = 0;
    if (plan != null && plan.totalLines > 0) {
      initial =
          plan.chapterOfLine(_anchorLine.clamp(0, plan.totalLines - 1));
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _baseColumnWidth),
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
    const columnWidth = _baseColumnWidth;
    final contentWidth = columns * columnWidth + (columns - 1) * _gutter;
    final sidePadding = ((constraints.maxWidth - contentWidth) / 2)
        .clamp(0.0, double.infinity);
    final fontSize = columnWidth / _measureEms;
    final lineHeight = fontSize * TypesetChapter.lineHeightEm;
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
    final scale = columnWidth / (_measureEms * _unitsPerEm());
    return Listener(
      key: const ValueKey('columns-active'),
      onPointerSignal: (event) {
        if (event is PointerScrollEvent &&
            event.scrollDelta.dy != 0 &&
            _hController!.hasClients) {
          final target = (_hController!.offset + event.scrollDelta.dy)
              .clamp(0.0, _hController!.position.maxScrollExtent);
          _hController!.jumpTo(target);
        }
      },
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: sidePadding),
        child: ListView.builder(
          key: Key('horizontal-reader-$params'),
          controller: _hController,
          scrollDirection: Axis.horizontal,
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

  /// Rough chapter height before its layout arrives, from the spine's text
  /// length: ~55 characters per line at the 26em measure.
  double _estimatedHeight(int index, double columnWidth) {
    final fontSize = columnWidth / _measureEms;
    final lineHeight = fontSize * TypesetChapter.lineHeightEm;
    final lines = (_spine[index].textLength / 55).ceil() + 1;
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
            TypesetChapter(layout: layout)
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
