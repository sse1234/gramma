import 'dart:convert';

/// View kinds per ADR 0008. Text views send and receive reading position;
/// footnotes and commentary views (ADR 0017) are receivers only.
enum PaneKind { text, footnotes, commentary }

/// Weights are user-dragged and persisted; anything non-finite or
/// non-positive (from a corrupted store or a historical resize bug) resets
/// to 1.0 so a pane can never be squeezed out of existence on restore.
double _sanitizeWeight(num? raw) {
  final w = raw?.toDouble() ?? 1.0;
  return w.isFinite && w > 0.01 ? w : 1.0;
}

/// One view of the layout object: kind, loaded asset, link target (by pane
/// id), reading position, and its share of its column's height.
class PaneSpec {
  PaneSpec({
    String? id,
    required this.kind,
    this.module,
    this.follow,
    this.anchor,
    this.anchorEnd,
    this.weight = 1.0,
    this.badge,
  }) : id = id ?? _newId();

  /// The badge alphabet: 35 addressable panes (1-9, then a-z).
  static const badgeChars = '123456789abcdefghijklmnopqrstuvwxyz';

  static int _counter = 0;

  static String _newId() =>
      'p${DateTime.now().microsecondsSinceEpoch}-${_counter++}';

  /// Stable identity, persisted; links refer to it.
  final String id;
  PaneKind kind;
  String? module;

  /// Id of the pane whose reading position this pane follows.
  String? follow;
  String? anchor;

  /// Last visible position ("Book.Ch.V"), completing the visible range
  /// [anchor, anchorEnd] for receiver views.
  String? anchorEnd;

  /// Height share within the pane's column.
  double weight;

  /// Visible single-character identifier (from [badgeChars]); assigned by
  /// [LayoutModel.ensureBadges] and stable for the pane's lifetime.
  String? badge;

  /// Position of [badge] in the alphabet, for its palette color.
  int get badgeIndex {
    final b = badge;
    return b == null ? 0 : badgeChars.indexOf(b).clamp(0, badgeChars.length);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'module': module,
        'follow': follow,
        'anchor': anchor,
        'anchorEnd': anchorEnd,
        'weight': weight,
        'badge': badge,
      };

  static PaneSpec? fromJson(Map<String, dynamic> json) {
    final kind =
        PaneKind.values.where((k) => k.name == json['kind']).firstOrNull;
    if (kind == null) return null;
    return PaneSpec(
      id: json['id'] as String?,
      kind: kind,
      module: json['module'] as String?,
      follow: json['follow'] as String?,
      anchor: json['anchor'] as String?,
      anchorEnd: json['anchorEnd'] as String?,
      weight: _sanitizeWeight(json['weight'] as num?),
      badge: json['badge'] as String?,
    );
  }
}

/// A vertical stack of panes sharing one column of the viewport.
class PaneColumn {
  PaneColumn({required this.panes, this.weight = 1.0});

  final List<PaneSpec> panes;

  /// Width share among all columns.
  double weight;
}

/// One step of the desk's navigation history: a position in a pane.
class HistoryEntry {
  const HistoryEntry({required this.paneId, required this.osis});

  final String paneId;
  final String osis;

  Map<String, dynamic> toJson() => {'pane': paneId, 'osis': osis};
}

/// The layout object (ADR 0008, extended): a row of columns, each a stack
/// of panes, with resizable weights and the desk-global navigation
/// history — the whole reading desk.
class LayoutModel {
  LayoutModel(this.columns);

  static const historyLimit = 100;

  final List<PaneColumn> columns;

  /// Desk-global navigation history: deliberate jumps across all panes.
  final List<HistoryEntry> history = [];
  int historyCursor = -1;

  bool get canGoBack => historyCursor > 0;
  bool get canGoForward =>
      historyCursor >= 0 && historyCursor < history.length - 1;

  /// Record a deliberate navigation of [paneId] to [targetOsis]: the pane's
  /// current position becomes the departure entry (so Back returns there),
  /// any forward tail is discarded, and the target becomes the newest
  /// entry.
  void recordNavigation(String paneId, String targetOsis) {
    final pane = byId(paneId);
    if (pane == null) return;
    if (historyCursor < history.length - 1) {
      history.removeRange(historyCursor + 1, history.length);
    }
    final departure = pane.anchor;
    final last = history.lastOrNull;
    if (departure != null &&
        (last == null || last.paneId != paneId || last.osis != departure)) {
      history.add(HistoryEntry(paneId: paneId, osis: departure));
    }
    history.add(HistoryEntry(paneId: paneId, osis: targetOsis));
    while (history.length > historyLimit) {
      history.removeAt(0);
    }
    historyCursor = history.length - 1;
  }

  HistoryEntry? goBack() {
    if (!canGoBack) return null;
    historyCursor -= 1;
    return history[historyCursor];
  }

  HistoryEntry? goForward() {
    if (!canGoForward) return null;
    historyCursor += 1;
    return history[historyCursor];
  }

  HistoryEntry? jumpToHistory(int index) {
    if (index < 0 || index >= history.length) return null;
    historyCursor = index;
    return history[index];
  }

  void _pruneHistory() {
    final current =
        historyCursor >= 0 && historyCursor < history.length
            ? history[historyCursor]
            : null;
    history.removeWhere((e) => byId(e.paneId) == null);
    historyCursor =
        current == null ? history.length - 1 : history.indexOf(current);
    if (historyCursor < 0) historyCursor = history.length - 1;
  }

  Iterable<PaneSpec> get allPanes =>
      columns.expand((column) => column.panes);

  PaneSpec? byId(String? id) =>
      id == null ? null : allPanes.where((p) => p.id == id).firstOrNull;

  /// Assign every unbadged sender-capable pane the lowest unused badge
  /// character, in traversal order. Receive-only panes (footnotes) carry no
  /// badge — they can never be follow targets. Panes keep their badge for
  /// life; at most `badgeChars.length` addressable panes can exist.
  void ensureBadges() {
    for (final pane in allPanes) {
      if (pane.kind != PaneKind.text) pane.badge = null;
    }
    final used = allPanes.map((p) => p.badge).whereType<String>().toSet();
    for (final pane in allPanes) {
      if (pane.kind != PaneKind.text || pane.badge != null) continue;
      for (final ch in PaneSpec.badgeChars.split('')) {
        if (!used.contains(ch)) {
          pane.badge = ch;
          used.add(ch);
          break;
        }
      }
    }
  }

  /// Whether another addressable pane can still get a badge.
  bool get hasFreeBadge =>
      allPanes.map((p) => p.badge).whereType<String>().length <
      PaneSpec.badgeChars.length;

  /// Column containing the pane with [id], or null.
  PaneColumn? columnOf(String id) =>
      columns.where((c) => c.panes.any((p) => p.id == id)).firstOrNull;

  /// Detach the pane with [id] from its column, dropping the column if it
  /// becomes empty. Returns the pane, or null if unknown.
  PaneSpec? _detach(String id) {
    for (final column in columns) {
      final index = column.panes.indexWhere((p) => p.id == id);
      if (index >= 0) {
        final pane = column.panes.removeAt(index);
        columns.removeWhere((c) => c.panes.isEmpty);
        return pane;
      }
    }
    return null;
  }

  /// Move a pane into [target]'s stack at [index] (an insertion position in
  /// the stack as it looked before the move).
  void moveIntoStack(String id, PaneColumn target, int index) {
    final source = columnOf(id);
    if (source == null) return;
    var insertAt = index;
    if (identical(source, target)) {
      final from = source.panes.indexWhere((p) => p.id == id);
      if (from < insertAt) insertAt -= 1;
    }
    final pane = _detach(id);
    if (pane == null) return;
    if (!columns.contains(target)) {
      // The source column vanished with its only pane; re-add it.
      columns.add(PaneColumn(panes: [pane]));
      return;
    }
    target.panes.insert(insertAt.clamp(0, target.panes.length), pane);
  }

  /// Move a pane out into a new column placed after [after] (null = become
  /// the leftmost column).
  void moveToNewColumn(String id, {required PaneColumn? after}) {
    final source = columnOf(id);
    if (source == null) return;
    final sourceIndex = columns.indexOf(source);
    final pane = _detach(id);
    if (pane == null) return;
    pane.weight = 1.0;
    final column = PaneColumn(panes: [pane]);
    final int insertAt;
    if (after == null) {
      insertAt = 0;
    } else if (columns.contains(after)) {
      insertAt = columns.indexOf(after) + 1;
    } else {
      // The anchor was the pane's own singleton column: put it back where
      // that column was.
      insertAt = sourceIndex;
    }
    columns.insert(insertAt.clamp(0, columns.length), column);
  }

  void removePane(String id) {
    for (final column in columns) {
      column.panes.removeWhere((p) => p.id == id);
    }
    columns.removeWhere((c) => c.panes.isEmpty);
    for (final pane in allPanes) {
      if (pane.follow == id) pane.follow = null;
    }
    _pruneHistory();
  }

  String encode() => jsonEncode({
        'v': 2,
        'columns': [
          for (final column in columns)
            {
              'weight': column.weight,
              'panes': [for (final p in column.panes) p.toJson()],
            },
        ],
        'history': [for (final e in history) e.toJson()],
        'cursor': historyCursor,
      });

  /// Decodes a layout object (current and v1 formats); returns null for
  /// anything unreadable so the caller can fall back to a default layout.
  static LayoutModel? decode(String json) {
    try {
      final data = jsonDecode(json);
      if (data is! Map<String, dynamic>) return null;
      switch (data['v']) {
        case 2:
          final columns = <PaneColumn>[];
          for (final raw in data['columns'] as List) {
            final map = raw as Map<String, dynamic>;
            final panes = (map['panes'] as List)
                .map((p) => PaneSpec.fromJson(p as Map<String, dynamic>))
                .toList();
            if (panes.any((p) => p == null) || panes.isEmpty) return null;
            columns.add(PaneColumn(
              panes: panes.cast<PaneSpec>(),
              weight: _sanitizeWeight(map['weight'] as num?),
            ));
          }
          if (columns.isEmpty) return null;
          final model = LayoutModel(columns);
          for (final pane in model.allPanes) {
            if (model.byId(pane.follow) == null) pane.follow = null;
          }
          final rawHistory = data['history'];
          if (rawHistory is List) {
            for (final raw in rawHistory) {
              if (raw is Map<String, dynamic> &&
                  raw['pane'] is String &&
                  raw['osis'] is String) {
                model.history.add(HistoryEntry(
                  paneId: raw['pane'] as String,
                  osis: raw['osis'] as String,
                ));
              }
            }
            final cursor = data['cursor'];
            model.historyCursor = cursor is int
                ? cursor.clamp(-1, model.history.length - 1)
                : model.history.length - 1;
            model._pruneHistory();
          }
          return model;
        case 1:
          final raw = (data['panes'] as List).cast<Map<String, dynamic>>();
          if (raw.isEmpty) return null;
          final panes = <PaneSpec>[];
          for (final p in raw) {
            final kind = PaneKind.values
                .where((k) => k.name == p['kind'])
                .firstOrNull;
            if (kind == null) return null;
            panes.add(PaneSpec(
              kind: kind,
              module: p['module'] as String?,
              anchor: p['anchor'] as String?,
            ));
          }
          for (var i = 0; i < raw.length; i++) {
            final follow = raw[i]['follow'] as int?;
            if (follow != null && follow >= 0 && follow < panes.length) {
              panes[i].follow = panes[follow].id;
            }
          }
          return LayoutModel(
              [for (final p in panes) PaneColumn(panes: [p])]);
        default:
          return null;
      }
    } catch (_) {
      return null;
    }
  }
}

/// Nearest column width holding a whole number of typeset columns
/// (`n * columnWidth + (n-1) * gutter`), within [available]. When not even
/// one whole column fits (narrow screens), returns [width] unchanged — the
/// divider stays where the user put it rather than forcing an overflow.
double snapToColumns(
  double width,
  double columnWidth,
  double gutter,
  double available,
) {
  double widthFor(int n) => n * columnWidth + (n - 1) * gutter;
  if (widthFor(1) > available) return width;
  var best = widthFor(1);
  var n = 2;
  while (true) {
    final candidate = widthFor(n);
    if (candidate > available) break;
    if ((candidate - width).abs() < (best - width).abs()) {
      best = candidate;
    }
    n++;
  }
  return best;
}
