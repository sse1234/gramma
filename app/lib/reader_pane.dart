import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import 'chapter_heading.dart';
import 'column_plan.dart';
import 'column_scroller.dart';
import 'l10n.dart';
import 'note_popup.dart';
import 'column_snap_physics.dart';
import 'passage_preview.dart';
import 'pane_header.dart';
import 'pane_model.dart';
import 'reader_focus.dart';
import 'reader_selection.dart';
import 'reference_selector.dart';
import 'settings.dart';
import 'src/rust/api/library.dart';
import 'src/rust/api/typeset.dart';
import 'typeset_chapter.dart';
import 'typeset_column.dart';

/// Verse shown at [line], walking forward past spacer lines (the empty
/// rows before section headings carry no runs) to the next carrying line.
int? verseAtLineStart(List<LineView> lines, int line) {
  if (lines.isEmpty) return null;
  for (var i = line.clamp(0, lines.length - 1); i < lines.length; i++) {
    final runs = lines[i].runs;
    if (runs.isNotEmpty) return runs.first.verse;
  }
  return null;
}

/// Verse of the last run at [line], walking backward past spacer lines.
int? verseAtLineEnd(List<LineView> lines, int line) {
  if (lines.isEmpty) return null;
  for (var i = line.clamp(0, lines.length - 1); i >= 0; i--) {
    final runs = lines[i].runs;
    if (runs.isNotEmpty) return runs.last.verse;
  }
  return null;
}

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
    required this.readingMode,
    required this.onToggleMode,
    required this.badge,
    required this.onAnchor,
    required this.onAnchorEnd,
    required this.onModule,
    required this.onFollow,
    required this.onJump,
    required this.canGoBack,
    required this.canGoForward,
    required this.onBack,
    required this.onForward,
    required this.historyItems,
    required this.onHistorySelect,
    this.command,
    this.dragHandle,
    this.onClose,
    this.onWordLookup,
  });

  /// Where the floating header starts (ADR 0028): below the app bar for
  /// panes in the desk's top row, at the pane's top otherwise.

  final PaneSpec spec;
  final List<ModuleView> modules;
  final String? followedAnchor;
  final List<FollowOption> followOptions;

  /// Reading mode hides the pane's chrome; tapping the content toggles it.
  final bool readingMode;
  final VoidCallback onToggleMode;

  /// A long-pressed word, stripped for dictionary lookup (ADR 0019),
  /// with its verse context so tagged texts resolve Strong numbers
  /// directly (ADR 0020).
  final WordLookup? onWordLookup;

  /// The pane's identity badge, shown leftmost in the chrome.
  final Widget? badge;
  final ValueChanged<String> onAnchor;

  /// Last visible position, completing the pane's visible range.
  final ValueChanged<String?> onAnchorEnd;
  final ValueChanged<String> onModule;
  final ValueChanged<String?> onFollow;

  /// Reports a deliberate jump (selector pick) for the desk history.
  final ValueChanged<String> onJump;

  /// Desk-global navigation history controls.
  final bool canGoBack;
  final bool canGoForward;
  final VoidCallback onBack;
  final VoidCallback onForward;
  final List<HistoryItem> historyItems;
  final ValueChanged<int> onHistorySelect;

  /// External navigation (e.g. from a passage preview's Open action).
  final NavCommand? command;
  final Widget? dragHandle;
  final VoidCallback? onClose;

  /// Height of the floating pane header band (ADR 0028); the content
  /// shifts by exactly this much (plus [chromeInset]) while chrome shows.
  static const chromeHeight = 56.0;

  @override
  State<ReaderPane> createState() => _ReaderPaneState();
}

class _ReaderPaneState extends State<ReaderPane>
    with ReaderSelection<ReaderPane> {
  static const _cacheLimit = 80;
  static const _headingLines = 2;
  static const _gutter = 48.0;

  double _columnWidth = SettingsController.defaultColumnWidth;
  double _lineSpacing = SettingsController.defaultLineSpacing;
  double _columnAdvance = SettingsController.defaultColumnAdvance;
  int? _measure;
  String? _fontFamily;

  /// Arrow-key paging and keyboard ownership (ADR 0028).
  late final ReaderFocus _focus = ReaderFocus(
    onStep: (steps) => _columns.step(steps),
    isCurrent: () => mounted && (ModalRoute.of(context)?.isCurrent ?? true),
  );

  /// Column mode: the horizontal scroll, the plan, and the anchor line.
  late final ColumnScroller _columns = ColumnScroller(
    onScrolled: _onColumnScrolled,
  );

  @override
  List<ChapterRefView> get spine => _spine;
  @override
  String? get paneModule => widget.spec.module;
  @override
  WordLookup? get wordLookup => widget.onWordLookup;

  ModuleView? _active;
  List<ChapterRefView> _spine = const [];
  List<int>? _lineCounts;

  /// Per chapter, one entry per text line: 0 content, 1 heading, 2 blank
  /// (ADR 0026 — the column plan keeps headings with their text).
  List<List<int>>? _rowKinds;
  final Map<int, ChapterLayoutView> _layouts = {};
  final Set<int> _loading = {};

  bool _suppressEmit = false;

  /// Whether this pane has announced its position at least once; the first
  /// layout tick emits unconditionally so the desk (history, followers)
  /// always knows the starting position.
  bool _announced = false;
  String? _lastAnchor;
  String? _lastAnchorEnd;

  /// First visible verse of the top chapter (verse-level link granularity);
  /// null when unknown (layout not loaded yet).
  int? _visibleVerse;
  double _vViewportH = 0;
  double _vLineHeightPx = 20;

  final ItemScrollController _vScroll = ItemScrollController();
  final ItemPositionsListener _vPositions = ItemPositionsListener.create();
  int _topChapter = 0;

  @override
  void initState() {
    super.initState();
    _vPositions.itemPositions.addListener(_onVerticalPositions);
    if (widget.spec.badge == '1') _focus.claimAfterFrame();
  }

  @override
  void dispose() {
    _focus.dispose();
    _vPositions.itemPositions.removeListener(_onVerticalPositions);
    _columns.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final settings = SettingsScope.of(context);
    _columnWidth = settings.columnWidth;
    _lineSpacing = settings.lineSpacing;
    _columnAdvance = settings.columnAdvance;
    final measure = settings.measureEms;
    final family = settings.fontFamily;
    if (_measure == null) {
      _measure = measure;
      _fontFamily = family;
      _loadModule();
    } else if (_measure != measure || _fontFamily != family) {
      // A typeface change moves every line break, exactly like a
      // measure change.
      _measure = measure;
      _fontFamily = family;
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
    final command = widget.command;
    if (command != null && command.epoch != old.command?.epoch) {
      // Deferred: didUpdateWidget runs during build, and the jump emits a
      // position which must not reach the orchestrator mid-build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final parts = command.osis.split('-').first.split('.');
        if (parts.length < 2) return;
        final index = _indexOfOsis('${parts[0]}.${parts[1]}');
        if (index >= 0) {
          _jumpToChapter(
            index,
            verse: parts.length >= 3 ? int.tryParse(parts[2]) : null,
          );
        }
      });
    }
  }

  String _osisOf(int chapter) =>
      '${_spine[chapter].bookOsis}.${_spine[chapter].chapter}';

  String _anchorString() {
    if (_topChapter >= _spine.length) return '';
    final base = _osisOf(_topChapter);
    final verse = _visibleVerse;
    return verse == null ? base : '$base.$verse';
  }

  /// Announces the visible range whenever either end moved. The end can
  /// move without the start's verse changing (a column of one long verse
  /// paged past), so callers report every scroll and the strings decide.
  void _emitPosition() {
    if (_suppressEmit || _topChapter >= _spine.length) return;
    final anchor = _anchorString();
    final anchorEnd = _anchorEndString();
    if (_announced && anchor == _lastAnchor && anchorEnd == _lastAnchorEnd) {
      return;
    }
    _announced = true;
    _lastAnchor = anchor;
    _lastAnchorEnd = anchorEnd;
    widget.onAnchor(anchor);
    widget.onAnchorEnd(anchorEnd);
  }

  /// Last visible position: exact in column mode (last line of the last
  /// visible column), estimated in vertical mode.
  String? _anchorEndString() {
    final lastLine = _columns.lastVisibleLine;
    if (lastLine != null) {
      final plan = _columns.plan!;
      final chapter = plan.chapterOfLine(lastLine);
      final local = lastLine - plan.blockStart(chapter) - _headingLines;
      final verse = local >= 0 ? _verseAtLineEnd(chapter, local) : null;
      final entry = _spine[chapter];
      final base = '${entry.bookOsis}.${entry.chapter}';
      return verse == null ? base : '$base.$verse';
    }
    final positions = _vPositions.itemPositions.value;
    if (positions.isEmpty) return null;
    ItemPosition? bottom;
    for (final p in positions) {
      if (p.itemLeadingEdge < 1 && (bottom == null || p.index > bottom.index)) {
        bottom = p;
      }
    }
    if (bottom == null || bottom.index >= _spine.length) return null;
    final counts = _lineCounts;
    int? verse;
    if (counts != null && bottom.index < counts.length) {
      final span = bottom.itemTrailingEdge - bottom.itemLeadingEdge;
      if (span > 0) {
        final fraction = ((1 - bottom.itemLeadingEdge) / span).clamp(0.0, 1.0);
        final line =
            (fraction * (counts[bottom.index] + _headingLines)).floor() -
            _headingLines;
        verse = line > 0
            ? _verseAtLineEnd(bottom.index, line)
            : _verseAtLineEnd(bottom.index, 0);
      }
    }
    final entry = _spine[bottom.index];
    final base = '${entry.bookOsis}.${entry.chapter}';
    return verse == null ? base : '$base.$verse';
  }

  /// Verse of the last run at a chapter-local text line.
  int? _verseAtLineEnd(int chapterIndex, int line) {
    final layout = _layouts[chapterIndex];
    if (layout == null) return null;
    return verseAtLineEnd(layout.lines, line);
  }

  int _indexOfOsis(String osis) {
    final parts = osis.split('.');
    if (parts.length < 2) return -1;
    final chapter = int.tryParse(parts[1]);
    return _spine.indexWhere(
      (c) => c.bookOsis == parts[0] && c.chapter == chapter,
    );
  }

  int? _verseOfOsis(String osis) {
    final parts = osis.split('.');
    return parts.length >= 3 ? int.tryParse(parts[2]) : null;
  }

  /// First line index (within the chapter's layout) at or after which
  /// [verse] appears; null while the layout is not loaded.
  int? _lineOfVerse(int chapterIndex, int verse) {
    final layout = _layouts[chapterIndex];
    if (layout == null) {
      _requestLayout(chapterIndex);
      return null;
    }
    for (var i = 0; i < layout.lines.length; i++) {
      if (layout.lines[i].runs.any((r) => r.verse >= verse)) return i;
    }
    return null;
  }

  /// Verse shown at a chapter-local text line, from the loaded layout.
  int? _verseAtLine(int chapterIndex, int line) {
    final layout = _layouts[chapterIndex];
    if (layout == null) return null;
    return verseAtLineStart(layout.lines, line);
  }

  ColumnPlan? _linePlan({int linesPerColumn = 1, int? origin}) {
    final counts = _lineCounts;
    if (counts == null || counts.length != _spine.length || counts.isEmpty) {
      return null;
    }
    return ColumnPlan(
      textLines: counts,
      headingLines: _headingLines,
      linesPerColumn: linesPerColumn,
      rowKinds: _rowKinds,
      origin: origin,
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
      _rowKinds = null;
      _columns.reset();
      _topChapter = 0;
      _announced = false;
    });
    final active = _active;
    if (active == null) return;
    if (active.code != widget.spec.module) {
      widget.onModule(active.code);
    }
    moduleLineKinds(moduleCode: active.code, measureEms: _measure!).then((
      kinds,
    ) {
      if (!mounted || _active?.code != active.code) return;
      setState(() {
        _rowKinds = kinds;
        _lineCounts = [for (final k in kinds) k.length];
        _restoreAnchor();
      });
      // The vertical list was built before the counts arrived, sitting at
      // its initial index — move it to the restored chapter for real.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _topChapter > 0 && _vScroll.isAttached) {
          _vScroll.jumpTo(index: _topChapter);
        }
      });
      if (_spine.isNotEmpty) {
        _emitPosition();
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
      _columns.anchorLine = plan.blockStart(index);
    }
  }

  void _remeasure() {
    if (!mounted) return;
    final keepChapter = _topChapter;
    setState(() {
      _layouts.clear();
      _loading.clear();
      _lineCounts = null;
      _rowKinds = null;
      _columns.reset();
    });
    final active = _active;
    if (active == null) return;
    moduleLineKinds(moduleCode: active.code, measureEms: _measure!).then(
      (kinds) {
        if (!mounted || _active?.code != active.code) return;
        _kindsRetries = 0;
        setState(() {
          _rowKinds = kinds;
          _lineCounts = [for (final k in kinds) k.length];
          final plan = _linePlan();
          if (plan != null && keepChapter < _spine.length) {
            _columns.anchorLine = plan.blockStart(keepChapter);
            _topChapter = keepChapter;
          }
        });
      },
      onError: (Object error) {
        // Without line counts the view falls back to a single column
        // for good; a failed count (a typeface swapped mid-flight) is
        // retried rather than left there.
        if (!mounted || _active?.code != active.code) return;
        debugPrint('gramma: line kinds for ${active.code} failed: $error');
        if (_kindsRetries++ < 2) {
          Future.delayed(const Duration(milliseconds: 400), _remeasure);
        }
      },
    );
  }

  /// Failed line-count attempts since the last success (see [_remeasure]).
  int _kindsRetries = 0;

  void _requestLayout(int index) {
    if (_layouts.containsKey(index) || _loading.contains(index)) return;
    _loading.add(index);
    final entry = _spine[index];
    layoutChapter(
          moduleCode: _active!.code,
          bookOsis: entry.bookOsis,
          chapter: entry.chapter,
          measureEms: _measure!,
        )
        .then((layout) {
          if (!mounted) return;
          setState(() {
            _layouts[index] = layout;
            while (_layouts.length > _cacheLimit) {
              _layouts.remove(_layouts.keys.first);
            }
          });
        })
        .whenComplete(() => _loading.remove(index));
  }

  void _onVerticalPositions() {
    // Before the line counts arrive the list still sits at its build-time
    // index; emitting now would overwrite the stored anchor with it.
    if (_lineCounts == null) return;
    final positions = _vPositions.itemPositions.value;
    if (positions.isEmpty) return;
    ItemPosition? topPosition;
    for (final p in positions) {
      if (p.itemTrailingEdge > 0 &&
          (topPosition == null || p.index < topPosition.index)) {
        topPosition = p;
      }
    }
    if (topPosition == null) return;
    final top = topPosition.index;
    final plan = _linePlan();
    if (plan != null && top < _spine.length) {
      _columns.anchorLine = plan.blockStart(top);
    }
    // Estimate the first visible text line of the top chapter from how far
    // it has scrolled past the viewport top.
    int? verse;
    final counts = _lineCounts;
    if (counts != null && top < counts.length) {
      final span = topPosition.itemTrailingEdge - topPosition.itemLeadingEdge;
      if (span > 0 && topPosition.itemLeadingEdge < 0) {
        final scrolled = -topPosition.itemLeadingEdge / span;
        final line =
            (scrolled * (counts[top] + _headingLines)).floor() - _headingLines;
        verse = line > 0 ? _verseAtLine(top, line) : _verseAtLine(top, 0);
      } else {
        verse = _verseAtLine(top, 0);
      }
    }
    if (top != _topChapter || verse != _visibleVerse) {
      setState(() {
        _topChapter = top;
        _visibleVerse = verse;
      });
    }
    _emitPosition();
  }

  /// The first visible column changed: find its chapter and verse.
  void _onColumnScrolled() {
    final plan = _columns.plan!;
    final line = _columns.anchorLine;
    final top = plan.chapterOfLine(line.clamp(0, plan.totalLines - 1));
    final local = line - plan.blockStart(top) - _headingLines;
    final verse = local >= 0 ? _verseAtLine(top, local) : _verseAtLine(top, 0);
    if (top != _topChapter || verse != _visibleVerse) {
      setState(() {
        _topChapter = top;
        _visibleVerse = verse;
      });
    }
    _emitPosition();
  }

  void _applyRemoteAnchor(String osis) {
    final index = _indexOfOsis(osis);
    if (index < 0) return;
    final verse = _verseOfOsis(osis);
    if (index == _topChapter && (verse == null || verse == _visibleVerse)) {
      return;
    }
    _suppressEmit = true;
    _jumpToChapter(index, verse: verse);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _suppressEmit = false;
      // Announce where the follower actually landed (its visible range
      // feeds footnotes views and its own persisted position).
      if (mounted) _emitPosition();
    });
  }

  void _jumpToChapter(int index, {int? verse}) {
    final targetLine = verse == null ? null : _lineOfVerse(index, verse);
    if (_columns.attached) {
      var line = _columns.plan!.blockStart(index);
      if (targetLine != null) {
        line += _headingLines + targetLine;
      }
      _columns.jumpToLine(line);
    } else if (_vScroll.isAttached) {
      if (targetLine != null && _vViewportH > 0) {
        // Position the verse's line near the viewport top: negative
        // alignment scrolls the chapter's leading edge above the viewport.
        const headingPx = 44.0;
        final offset = headingPx + targetLine * _vLineHeightPx;
        _vScroll.jumpTo(index: index, alignment: -offset / _vViewportH);
      } else {
        _vScroll.jumpTo(index: index);
      }
    }
    if (index != _topChapter || verse != _visibleVerse) {
      setState(() {
        _topChapter = index;
        _visibleVerse = verse;
      });
      _emitPosition();
    }
  }

  /// A tap on a word: exits an active selection, otherwise opens the
  /// note popup of a mark covering the word, otherwise toggles reading
  /// mode like any plain tap.
  void _runTap(int chapterIndex, RunView run) {
    if (selection != null) {
      clearSelection();
      return;
    }
    if (chapterIndex >= _spine.length) return;
    // A reference inside a heading (parallel passages, ADR 0029)
    // previews its passage.
    final link = run.link;
    final layout = _layouts[chapterIndex];
    final module = widget.spec.module;
    if (link != null &&
        layout != null &&
        link < layout.refs.length &&
        module != null) {
      final osis = layout.refs[link];
      showPassagePreview(
        context,
        osis: osis,
        moduleCode: module,
        onOpen: () => widget.onJump(osis.split('-').first),
      );
      return;
    }
    final covering = markCovering(chapterIndex, run);
    if (covering != null) {
      editMark(covering);
    } else {
      widget.onToggleMode();
    }
  }

  void _plainTap() {
    if (selection != null) {
      clearSelection();
    } else {
      widget.onToggleMode();
    }
  }

  /// A tapped inline note marker (ADR 0016): the footnote right where
  /// the reader's eye is, with in-popup reference navigation.
  void _openNotePopup(int chapterIndex, int verse, String label) {
    final active = _active;
    if (active == null || chapterIndex >= _spine.length) return;
    final entry = _spine[chapterIndex];
    // The whole chapter's footnotes (ADR 0028), the tapped one selected
    // and scrolled into view — letters run through the chapter, so the
    // list reads as a table of the page's markers.
    final entries = [
      for (final note in chapterNotes(
        moduleCode: active.code,
        bookOsis: entry.bookOsis,
        chapter: entry.chapter,
      ))
        (chapter: entry, note: note),
    ];
    final selected = entries.indexWhere(
      (e) => e.note.verse == verse && e.note.label == label,
    );
    if (selected < 0 || !mounted) return;
    final settings = SettingsScope.of(context);
    showNotePopup(
      context,
      entries: entries,
      selected: selected,
      title: '${context.l10n.footnotesTitle} · ${entry.heading}',
      previewModule: settings.defaultModule ?? active.code,
      onOpenReference: (osis) {
        final index = _indexOfOsis(osis.split('-').first);
        if (index >= 0) {
          widget.onJump(osis.split('-').first);
          _jumpToChapter(index, verse: _verseOfOsis(osis.split('-').first));
        }
      },
    );
  }

  Future<void> _openSelector() async {
    if (_spine.isEmpty) return;
    final result = await showReferenceSelector(context, _spine);
    if (result == null || !mounted) return;
    final index = _indexOfOsis('${result.book}.${result.chapter}');
    if (index >= 0) {
      final base = '${result.book}.${result.chapter}';
      widget.onJump(result.verse == null ? base : '$base.${result.verse}');
      _jumpToChapter(index, verse: result.verse);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final position = _topChapter < _spine.length
        ? _spine[_topChapter].heading
        : null;
    final header = PaneHeader(
      title: null,
      badge: widget.badge,
      dragHandle: widget.dragHandle,
      position: position == null
          ? null
          : Tooltip(
              message: context.l10n.selectorTooltip,
              child: InkWell(
                key: const Key('open-selector'),
                borderRadius: BorderRadius.circular(14),
                onTap: _openSelector,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.grid_view_rounded,
                        size: 13,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          position,
                          key: const Key('current-position'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
      moduleCode: _active?.code,
      modules: [
        for (final m in widget.modules)
          (code: m.code, title: m.title, strongs: m.strongs),
      ],
      onModule: widget.onModule,
      canGoBack: widget.canGoBack,
      canGoForward: widget.canGoForward,
      onBack: widget.onBack,
      onForward: widget.onForward,
      historyItems: widget.historyItems,
      onHistorySelect: widget.onHistorySelect,
      followValue: widget.spec.follow,
      followOptions: widget.followOptions,
      onFollow: widget.onFollow,
      onClose: widget.onClose,
    );
    // The chrome takes its own space (ADR 0028, amended 2026-09-14): the
    // header sits above the text and the text reflows below it. The
    // reading position is kept across the toggle by the anchor; the
    // columns re-chunk, which was judged better than text hidden under
    // an overlay while reading with chrome on.
    return ScrollConfiguration(
      // No scrollbars (ADR 0028): the thumb's hit band at the column
      // edge swallowed taps on end-of-line footnote markers.
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!widget.readingMode)
            Material(
              color: theme.colorScheme.surface,
              child: SizedBox(
                height: ReaderPane.chromeHeight,
                child: Align(alignment: Alignment.topCenter, child: header),
              ),
            ),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: widget.onToggleMode,
              child: _spine.isEmpty
                  ? Center(
                      child: Text(
                        context.l10n.importToBegin,
                        style: theme.textTheme.bodyLarge,
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        _vViewportH = constraints.maxHeight;
                        final effWidth = constraints.maxWidth < _columnWidth
                            ? constraints.maxWidth
                            : _columnWidth;
                        _vLineHeightPx =
                            effWidth / (_measure ?? 26) * _lineSpacing;
                        final columns = _columnsFor(constraints.maxWidth);
                        final Widget reader;
                        if (columns >= 2 && _linePlan() != null) {
                          reader = _horizontalReader(constraints, columns);
                        } else {
                          _columns.detach();
                          reader = _verticalReader();
                        }
                        // The selection bar floats over the content: adding
                        // it to the layout would change the column height
                        // mid-gesture and shift the text under the finger.
                        return Stack(
                          children: [
                            reader,
                            if (selection != null)
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: 0,
                                child: selectionBar(theme),
                              ),
                          ],
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
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
      initial = plan.chapterOfLine(
        _columns.anchorLine.clamp(0, plan.totalLines - 1),
      );
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
    final sidePadding = ((constraints.maxWidth - contentWidth) / 2).clamp(
      0.0,
      double.infinity,
    );
    final fontSize = columnWidth / _measure!;
    final lineHeight = fontSize * _lineSpacing;
    var linesPerColumn = (constraints.maxHeight / lineHeight).floor();
    if (linesPerColumn < 1) linesPerColumn = 1;
    final stride = columnWidth + _gutter;
    final plan = _columns.layout(
      columns: columns,
      linesPerColumn: linesPerColumn,
      columnWidth: columnWidth,
      stride: stride,
      buildPlan: ({required linesPerColumn, required origin}) =>
          _linePlan(linesPerColumn: linesPerColumn, origin: origin)!,
    );
    final scale = columnWidth / (_measure! * _unitsPerEm());
    return Focus(
      focusNode: _focus.node,
      autofocus: widget.spec.badge == '1',
      onKeyEvent: (node, event) => _focus.handle(event),
      child: Listener(
        key: const ValueKey('columns-active'),
        onPointerDown: (_) => _focus.claim(),
        onPointerSignal: (event) {
          // Acting in a view — click, drag, or wheel — makes it the
          // keyboard's target; hovering alone does not.
          _focus.claim();
          // Discrete mouse wheels page by whole columns (trackpads scroll
          // through the pan-zoom gesture path and the snap physics instead).
          if (event is PointerScrollEvent &&
              event.scrollDelta.dy != 0 &&
              _columns.attached) {
            _columns.onWheel(event.scrollDelta.dy);
          }
        },
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: sidePadding),
          child: ListView.builder(
            key: Key('horizontal-reader-${_columns.params}'),
            controller: _columns.controller,
            scrollDirection: Axis.horizontal,
            physics: ColumnSnapPhysics(stride: stride, advance: _columnAdvance),
            itemExtent: stride,
            itemCount: plan.columnCount,
            itemBuilder: (context, column) => Padding(
              padding: const EdgeInsets.only(right: _gutter),
              child: _columnItem(plan, column, scale, fontSize, lineHeight),
            ),
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
    for (var row = 0; row < plan.linesInColumn(column); row++) {
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
          rows.add(
            TextRow(row, layout.lines[lineIndex], layout.numberScale, chapter),
          );
        }
      }
    }
    return TypesetColumn(
      rows: rows,
      rowCount: plan.linesPerColumn,
      scale: scale,
      fontSize: fontSize,
      lineHeight: lineHeight,
      onMarkerTap: (chapter, run) {
        if (selection != null) {
          clearSelection();
        } else {
          _openNotePopup(chapter, run.verse, run.text);
        }
      },
      onPlainTap: _plainTap,
      onRunTap: _runTap,
      onSelectStart: selectStart,
      onSelectExtend: selectExtend,
      onSelectEnd: () {},
      marksByChapter: {
        for (final row in rows.whereType<TextRow>())
          row.chapter: paintMarks(row.chapter),
      },
      paneModule: widget.spec.module,
      selection: selection == null ? null : (selectionChapter!, selection!),
    );
  }

  double _estimatedHeight(int index, double columnWidth) {
    final fontSize = columnWidth / _measure!;
    final lineHeight = fontSize * _lineSpacing;
    final charsPerLine = _measure! * 2.1;
    final lines = (_spine[index].textLength / charsPerLine).ceil() + 1;
    return lines * lineHeight;
  }

  Widget _chapterItem(BuildContext context, int index) {
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
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final fontSize = constraints.maxWidth / _measure!;
                return ChapterHeading(
                  text: entry.heading,
                  fontSize: fontSize,
                  lineHeight: fontSize * _lineSpacing,
                );
              },
            ),
          ),
          if (layout != null)
            TypesetChapter(
              layout: layout,
              lineHeightEm: _lineSpacing,
              onMarkerTap: (run) {
                if (selection != null) {
                  clearSelection();
                } else {
                  _openNotePopup(index, run.verse, run.text);
                }
              },
              onPlainTap: _plainTap,
              onRunTap: (run) => _runTap(index, run),
              onSelectStart: (run) => selectStart(index, run),
              onSelectExtend: (run) => selectExtend(index, run),
              onSelectEnd: () {},
              marks: paintMarks(index),
              paneModule: widget.spec.module,
              selection: selectionChapter == index ? selection : null,
            )
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
