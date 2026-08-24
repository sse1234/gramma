import 'dart:convert';

/// View kinds per ADR 0008. Text views send and receive reading position;
/// footnotes views are receivers only.
enum PaneKind { text, footnotes }

/// One view of the layout object: kind, loaded asset, link target (by pane
/// id), reading position, and its share of its column's height.
class PaneSpec {
  PaneSpec({
    String? id,
    required this.kind,
    this.module,
    this.follow,
    this.anchor,
    this.weight = 1.0,
  }) : id = id ?? _newId();

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

  /// Height share within the pane's column.
  double weight;

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'module': module,
        'follow': follow,
        'anchor': anchor,
        'weight': weight,
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
      weight: (json['weight'] as num?)?.toDouble() ?? 1.0,
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

/// The layout object (ADR 0008, extended): a row of columns, each a stack
/// of panes, with resizable weights — the whole reading desk.
class LayoutModel {
  LayoutModel(this.columns);

  final List<PaneColumn> columns;

  Iterable<PaneSpec> get allPanes =>
      columns.expand((column) => column.panes);

  PaneSpec? byId(String? id) =>
      id == null ? null : allPanes.where((p) => p.id == id).firstOrNull;

  /// Column containing the pane with [id], or null.
  PaneColumn? columnOf(String id) =>
      columns.where((c) => c.panes.any((p) => p.id == id)).firstOrNull;

  void removePane(String id) {
    for (final column in columns) {
      column.panes.removeWhere((p) => p.id == id);
    }
    columns.removeWhere((c) => c.panes.isEmpty);
    for (final pane in allPanes) {
      if (pane.follow == id) pane.follow = null;
    }
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
              weight: (map['weight'] as num?)?.toDouble() ?? 1.0,
            ));
          }
          if (columns.isEmpty) return null;
          final model = LayoutModel(columns);
          for (final pane in model.allPanes) {
            if (model.byId(pane.follow) == null) pane.follow = null;
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
/// (`n * columnWidth + (n-1) * gutter`), at least one and within
/// [available]. Vertical tiling is only meaningful at these widths under
/// the constant-zoom model.
double snapToColumns(
  double width,
  double columnWidth,
  double gutter,
  double available,
) {
  double widthFor(int n) => n * columnWidth + (n - 1) * gutter;
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
