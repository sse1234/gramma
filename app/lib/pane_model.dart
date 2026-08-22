import 'dart:convert';

/// View kinds per ADR 0008. Text views send and receive reading position;
/// footnotes views are receivers only.
enum PaneKind { text, footnotes }

/// One view of the layout object: kind, loaded asset, link target, and
/// reading position (canonical "Book.Chapter" reference).
class PaneSpec {
  PaneSpec({required this.kind, this.module, this.follow, this.anchor})
      : id = _nextId++;

  static int _nextId = 0;

  /// Session-stable identity for widget state preservation.
  final int id;
  PaneKind kind;
  String? module;
  int? follow;
  String? anchor;

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'module': module,
        'follow': follow,
        'anchor': anchor,
      };

  static PaneSpec? _fromJson(Map<String, dynamic> json) {
    final kind = PaneKind.values
        .where((k) => k.name == json['kind'])
        .firstOrNull;
    if (kind == null) return null;
    return PaneSpec(
      kind: kind,
      module: json['module'] as String?,
      follow: json['follow'] as int?,
      anchor: json['anchor'] as String?,
    );
  }

  static String encodeList(List<PaneSpec> panes) =>
      jsonEncode({'v': 1, 'panes': [for (final p in panes) p.toJson()]});

  /// Decodes a layout object; returns null for anything unreadable so the
  /// caller can fall back to a default layout.
  static List<PaneSpec>? decodeList(String json) {
    try {
      final data = jsonDecode(json);
      if (data is! Map<String, dynamic> || data['v'] != 1) return null;
      final panes = (data['panes'] as List)
          .map((p) => _fromJson(p as Map<String, dynamic>))
          .toList();
      if (panes.any((p) => p == null) || panes.isEmpty) return null;
      final result = panes.cast<PaneSpec>();
      for (final p in result) {
        final follow = p.follow;
        if (follow != null && (follow < 0 || follow >= result.length)) {
          p.follow = null;
        }
      }
      return result;
    } catch (_) {
      return null;
    }
  }
}
