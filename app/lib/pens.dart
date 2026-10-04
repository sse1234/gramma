import 'dart:convert';
import 'dart:ui' show Brightness, Color;

import 'package:flutter/foundation.dart' show ValueNotifier;

import 'palette.dart';
import 'src/rust/api/user.dart';

/// How a pen shows on the text (ADR 0035): a wash behind the words, or
/// a line beneath them.
enum PenStyle { wash, underline }

/// One of the reader's marking pens (ADR 0035): a hue, a strength, and
/// a style. Marks reference pens by index; the pens are user data in
/// the synced store, so a mark looks the same on every device.
class Pen {
  const Pen({required this.hue, required this.strength, required this.style});

  /// HCL hue in degrees.
  final double hue;

  /// Opacity of the pen's color over the paper, 0.2 … 1.
  final double strength;
  final PenStyle style;

  static const minStrength = 0.2;
  static const maxStrength = 1.0;

  /// The pens of ADR 0023: eight evenly spaced hues at full strength.
  static Pen standard(int index) => Pen(
    hue: 15 + (index % Pens.count) * 45.0,
    strength: 1,
    style: PenStyle.wash,
  );

  Pen copyWith({double? hue, double? strength, PenStyle? style}) => Pen(
    hue: hue ?? this.hue,
    strength: strength ?? this.strength,
    style: style ?? this.style,
  );

  /// The wash color: the ADR 0023 wash at this hue, faded by strength.
  Color wash(Brightness brightness) =>
      (brightness == Brightness.light ? hcl(hue, 48, 87) : hcl(hue, 40, 34))
          .withValues(alpha: strength);

  /// The ink color for lines and glyphs: saturated enough to carry a
  /// thin stroke, faded by strength.
  Color ink(Brightness brightness) =>
      (brightness == Brightness.light ? hcl(hue, 80, 55) : hcl(hue, 70, 62))
          .withValues(alpha: strength);

  /// The color a swatch shows for this pen: the wash, or the ink of an
  /// underlining pen.
  Color swatch(Brightness brightness) =>
      style == PenStyle.wash ? wash(brightness) : ink(brightness);

  Map<String, dynamic> toJson() => {
    'v': 1,
    'hue': hue,
    'strength': strength,
    'style': style.name,
  };

  static Pen? fromJson(String raw) {
    try {
      final m = jsonDecode(raw);
      if (m is! Map<String, dynamic>) return null;
      return Pen(
        hue: (m['hue'] as num).toDouble() % 360,
        strength: ((m['strength'] as num?)?.toDouble() ?? 1).clamp(
          minStrength,
          maxStrength,
        ),
        style: PenStyle.values.firstWhere(
          (s) => s.name == m['style'],
          orElse: () => PenStyle.wash,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is Pen &&
      other.hue == hue &&
      other.strength == strength &&
      other.style == style;

  @override
  int get hashCode => Object.hash(hue, strength, style);
}

/// The pen set: `pen/<index>` keys in the synced user store (ADR 0014
/// op-log), cached in memory; a pen never written is the standard one.
class Pens {
  static const count = 8;

  /// The mark index that means "no pen": a note shown by its icon alone.
  static const none = -1;

  static List<Pen>? _cache;

  /// Bumped on every change so open views repaint.
  static final ValueNotifier<int> revision = ValueNotifier(0);

  static List<Pen> all() {
    final cached = _cache;
    if (cached != null) return cached;
    final pens = <Pen>[];
    for (var i = 0; i < count; i++) {
      Pen? pen;
      try {
        final value = userGet(key: 'pen/$i');
        if (value != null && value.isNotEmpty) pen = Pen.fromJson(value);
      } catch (_) {}
      pens.add(pen ?? Pen.standard(i));
    }
    _cache = pens;
    return pens;
  }

  static Pen of(int index) => all()[index.clamp(0, count - 1)];

  static void save(int index, Pen pen) {
    userSet(key: 'pen/$index', value: jsonEncode(pen.toJson()));
    _cache = null;
    revision.value++;
  }

  static void reset(int index) {
    userSet(key: 'pen/$index', value: '');
    _cache = null;
    revision.value++;
  }

  /// Drop the cache after external changes (a sync pull).
  static void invalidate() {
    _cache = null;
    revision.value++;
  }
}
