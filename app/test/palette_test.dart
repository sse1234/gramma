import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:gramma/palette.dart';

int _dist(Color a, Color b) {
  int ch(double x) => (x * 255).round();
  return (ch(a.r) - ch(b.r)).abs() +
      (ch(a.g) - ch(b.g)).abs() +
      (ch(a.b) - ch(b.b)).abs();
}

void main() {
  test('HCL reproduces the classic ggplot2 colors', () {
    // scales::hue_pal()(2) in R: #F8766D and #00BFC4.
    expect(_dist(ggplotHue(0, 2), const Color(0xFFF8766D)), lessThan(9));
    expect(_dist(ggplotHue(1, 2), const Color(0xFF00BFC4)), lessThan(9));
    // hue_pal()(3) adds #00BA38 at 135°.
    expect(_dist(ggplotHue(1, 3), const Color(0xFF00BA38)), lessThan(9));
  });

  test('badge colors are pairwise distinct across the address space', () {
    final colors = [
      for (var i = 0; i < 35; i++) paneBadgeColor(i, Brightness.light),
    ];
    for (var i = 0; i < colors.length; i++) {
      for (var j = i + 1; j < colors.length; j++) {
        expect(_dist(colors[i], colors[j]), greaterThan(8),
            reason: 'badges $i and $j too similar');
      }
    }
  });

  test('category tiles are soft in light mode and dark in dark mode', () {
    for (var k = 0; k < 9; k++) {
      final light = bookCategoryColor(k, Brightness.light);
      final dark = bookCategoryColor(k, Brightness.dark);
      expect(light.computeLuminance(), greaterThan(0.5));
      expect(dark.computeLuminance(), lessThan(0.2));
    }
  });
}
