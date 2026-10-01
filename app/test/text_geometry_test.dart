import 'package:flutter_test/flutter_test.dart';
import 'package:gramma/settings.dart';
import 'package:gramma/text_geometry.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<SettingsController> _settings({double glyph = 16, int ems = 25}) async {
  SharedPreferences.setMockInitialValues({});
  final controller = SettingsController(await SharedPreferences.getInstance())
    ..setGlyphSize(glyph)
    ..setMeasureEms(ems);
  return controller;
}

void main() {
  // ADR 0032: text size is the reader's; line length holds where a column
  // fits and gives way where it does not.
  test('a wide pane keeps the line length and multiplies columns', () async {
    final s = await _settings();
    final g = TextGeometry.fit(s, 1300);
    expect(g.fontSize, 16);
    expect(g.measureEms, 25);
    expect(g.columnWidth, 400);
    // 2 * 400 + 32 = 832 fits, 3 * 400 + 2 * 32 = 1264 fits too.
    expect(g.columns, 3);
    expect(g.gutter, 32, reason: '2 em of 16 px');
  });

  // ADR 0034: the gap between columns is the reader's, in ems.
  test('the column gap follows the glyph size and the setting', () async {
    final s = await _settings();
    s.setColumnGapEms(4);
    final g = TextGeometry.fit(s, 1300);
    expect(g.gutter, 64);
    // 3 * 400 + 2 * 64 = 1328 no longer fits.
    expect(g.columns, 2);
    expect(TextGeometry.fit(s, 1300, scale: 1.5).gutter, 96);
    s.setColumnGapEms(1.3);
    expect(s.columnGapEms, 1.5, reason: 'half-em steps');
    s.setColumnGapEms(9);
    expect(s.columnGapEms, SettingsController.maxColumnGapEms);
  });

  test('a pane just wide enough holds one column at the line length', () async {
    final s = await _settings();
    expect(TextGeometry.fit(s, 400).columns, 1);
    expect(TextGeometry.fit(s, 400).measureEms, 25);
    expect(TextGeometry.fit(s, 399).columns, 0);
  });

  test('a narrow pane keeps the text size and fits the line', () async {
    final s = await _settings();
    final g = TextGeometry.fit(s, 300);
    expect(g.fontSize, 16, reason: 'the glyph size never shrinks');
    expect(g.measureEms, 18, reason: '300 / 16 = 18.75 ems, floored');
    expect(g.columns, 0);
    expect(g.columnWidth, 288);
  });

  test('the fitted line never drops below the floor', () async {
    final s = await _settings(glyph: 40);
    expect(
      TextGeometry.fit(s, 50).measureEms,
      SettingsController.minMeasureEms,
    );
  });

  test('a scale multiplies the glyph size before fitting', () async {
    final s = await _settings();
    final g = TextGeometry.fit(s, 300, scale: 1.5);
    expect(g.fontSize, 24);
    expect(g.measureEms, 12);
  });
}
