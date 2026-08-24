import 'package:flutter/material.dart';

import 'palette.dart';

/// The pane's visible identity: its badge character on a square of its
/// palette color (golden-angle HCL progression by badge index).
class PaneBadge extends StatelessWidget {
  const PaneBadge({
    super.key,
    required this.badge,
    required this.badgeIndex,
    this.small = false,
  });

  final String badge;
  final int badgeIndex;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final color = paneBadgeColor(badgeIndex, brightness);
    final ink = color.computeLuminance() > 0.45 ? Colors.black : Colors.white;
    final size = small ? 18.0 : 24.0;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(small ? 4 : 5),
      ),
      child: Text(
        badge,
        style: TextStyle(
          color: ink,
          fontSize: small ? 11 : 14,
          fontWeight: FontWeight.w600,
          height: 1,
        ),
      ),
    );
  }
}
