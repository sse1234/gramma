import 'dart:convert';

/// One desk: a named layout object (ADR 0008, 0014).
class DeskInfo {
  DeskInfo({required this.id, required this.name});

  final String id;
  String name;
}

/// The synced desk registry: the ordered list of the user's desks,
/// stored under the `desks` key. Which desk a device shows is local
/// state and deliberately not part of this object.
class DeskRegistry {
  DeskRegistry(this.desks);

  final List<DeskInfo> desks;

  DeskInfo? byId(String? id) =>
      desks.where((d) => d.id == id).firstOrNull;

  String encode() => jsonEncode({
        'v': 1,
        'desks': [
          for (final d in desks) {'id': d.id, 'name': d.name},
        ],
      });

  static DeskRegistry? decode(String json) {
    try {
      final data = jsonDecode(json);
      if (data is! Map<String, dynamic>) return null;
      final raw = data['desks'];
      if (raw is! List || raw.isEmpty) return null;
      final desks = <DeskInfo>[];
      for (final entry in raw) {
        if (entry is! Map<String, dynamic>) return null;
        final id = entry['id'];
        final name = entry['name'];
        if (id is! String || name is! String) return null;
        desks.add(DeskInfo(id: id, name: name));
      }
      return DeskRegistry(desks);
    } catch (_) {
      return null;
    }
  }

  /// A name for the next new desk that does not collide; [prefix] is the
  /// localized word for a desk.
  String nextName(String prefix) {
    var n = desks.length + 1;
    while (desks.any((d) => d.name == '$prefix $n')) {
      n++;
    }
    return '$prefix $n';
  }
}

var _deskCounter = 0;

/// A practically unique desk id (time plus an in-process counter).
String newDeskId() =>
    'd${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}'
    '${(_deskCounter++).toRadixString(16)}';
