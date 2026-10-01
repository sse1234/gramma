import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gramma/l10n.dart';
import 'package:gramma/settings.dart';
import 'package:gramma/settings_screen.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<SettingsController> _controller() async {
  SharedPreferences.setMockInitialValues({});
  return SettingsController(await SharedPreferences.getInstance());
}

Widget _harness(SettingsController controller) {
  return ListenableBuilder(
    listenable: controller,
    builder: (context, _) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: controller.localeOverride,
      themeMode: controller.themeMode,
      theme: grammaTheme(
        Brightness.light,
        controller.contrast,
        tone: controller.tone,
      ),
      darkTheme: grammaTheme(
        Brightness.dark,
        controller.contrast,
        trueBlack: controller.trueBlackDark,
        tone: controller.tone,
      ),
      builder: (context, child) =>
          SettingsScope(controller: controller, child: child!),
      home: const SettingsScreen(),
    ),
  );
}

/// Opens one part of the settings (they are tabbed, ADR 0031).
Future<void> _openTab(WidgetTester tester, String id) async {
  // The tab row scrolls: a far tab is brought into view first.
  await tester.ensureVisible(find.byKey(Key('settings-tab-$id')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key('settings-tab-$id')));
  await tester.pumpAndSettle();
}

void main() {
  test('line length and text size apply directly (ADR 0032)', () async {
    final controller = await _controller();
    expect(controller.measureEms, SettingsController.defaultMeasureEms);
    controller.setMeasureEms(30);
    expect(controller.measureEms, 30);
    controller.setGlyphSize(20);
    expect(controller.glyphSize, 20);
    expect(controller.columnWidth, 600);
  });

  test('an installation from before ADR 0032 keeps its reading', () async {
    // Column width 416 at 26 em was a 16 px glyph; the width setting is
    // retired and the glyph size stored in its place.
    SharedPreferences.setMockInitialValues({
      'columnWidth': 416.0,
      'measureEms': 26,
    });
    final prefs = await SharedPreferences.getInstance();
    final controller = SettingsController(prefs);
    expect(controller.glyphSize, 16);
    expect(controller.measureEms, 26);
    expect(prefs.getDouble('glyphSize'), 16);
    expect(prefs.containsKey('columnWidth'), isFalse);
  });

  test('line spacing reaches down to solid', () async {
    final controller = await _controller();
    controller.setLineSpacing(1.0);
    expect(controller.lineSpacing, 1.0);
    controller.setLineSpacing(0.5);
    expect(controller.lineSpacing, SettingsController.minLineSpacing);
  });

  test('the measure reaches down to a few ems for very large type', () async {
    final controller = await _controller();
    controller.setMeasureEms(4);
    expect(controller.measureEms, 4);
    controller.setMeasureEms(1);
    expect(controller.measureEms, SettingsController.minMeasureEms);
  });

  test('settings persist across controller instances', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final first = SettingsController(prefs)
      ..setGlyphSize(18)
      ..setContrast(0.7)
      ..setLineSpacing(2.0)
      ..setDefaultModule('GerNeUe')
      ..setTone(ToneTheme.sage)
      ..setFootnoteScale(1.2)
      ..setPreviewScale(1.4)
      ..setThemeMode(ThemeMode.dark);
    first.setMeasureEms(30);
    final second = SettingsController(prefs);
    expect(second.glyphSize, 18);
    expect(second.contrast, 0.7);
    expect(second.lineSpacing, 2.0);
    expect(second.defaultModule, 'GerNeUe');
    expect(second.tone, ToneTheme.sage);
    expect(second.footnoteScale, 1.2);
    expect(second.previewScale, 1.4);
    expect(second.themeMode, ThemeMode.dark);
    expect(second.measureEms, 30);
  });

  test('contrast reaches the extended soft end', () async {
    final controller = await _controller();
    controller.setContrast(0.0);
    expect(controller.contrast, SettingsController.minContrast);
    final softest = grammaTheme(Brightness.light, controller.contrast);
    final mid = grammaTheme(Brightness.light, 0.5);
    expect(
      softest.scaffoldBackgroundColor.computeLuminance(),
      lessThan(mid.scaffoldBackgroundColor.computeLuminance()),
    );
    expect(
      softest.colorScheme.onSurface.computeLuminance(),
      greaterThan(mid.colorScheme.onSurface.computeLuminance()),
    );
  });

  test(
    'true black keeps the background at pure black and dims only text',
    () async {
      final dim = grammaTheme(Brightness.dark, 0.5, trueBlack: true);
      final full = grammaTheme(Brightness.dark, 1.0, trueBlack: true);
      expect(dim.scaffoldBackgroundColor, Colors.black);
      expect(full.scaffoldBackgroundColor, Colors.black);
      expect(
        dim.colorScheme.onSurface.computeLuminance(),
        lessThan(full.colorScheme.onSurface.computeLuminance()),
      );
      final controller = await _controller();
      controller.setTrueBlackDark(true);
      final reloaded = SettingsController(
        await SharedPreferences.getInstance(),
      );
      expect(reloaded.trueBlackDark, isTrue);
    },
  );

  test(
    'tones tint the softened surface distinctly, neutral stone included',
    () {
      final backgrounds = [
        for (final tone in ToneTheme.values)
          grammaTheme(
            Brightness.light,
            SettingsController.minContrast,
            tone: tone,
          ).scaffoldBackgroundColor,
      ];
      for (var i = 0; i < backgrounds.length; i++) {
        for (var j = i + 1; j < backgrounds.length; j++) {
          expect(
            backgrounds[i],
            isNot(backgrounds[j]),
            reason: 'tones $i and $j must differ',
          );
        }
      }
      final stone = grammaTheme(
        Brightness.light,
        SettingsController.minContrast,
        tone: ToneTheme.stone,
      ).scaffoldBackgroundColor;
      int ch(double x) => (x * 255).round();
      expect(
        (ch(stone.r) - ch(stone.b)).abs(),
        lessThan(3),
        reason: 'stone is neutral',
      );
      // Full contrast converges to pure white regardless of tone.
      expect(
        grammaTheme(
          Brightness.light,
          1.0,
          tone: ToneTheme.mist,
        ).scaffoldBackgroundColor,
        Colors.white,
      );
      // True black stays black in every tone.
      expect(
        grammaTheme(
          Brightness.dark,
          0.5,
          trueBlack: true,
          tone: ToneTheme.sepia,
        ).scaffoldBackgroundColor,
        Colors.black,
      );
    },
  );

  test('lower contrast softens ink and background', () {
    final full = grammaTheme(Brightness.light, 1.0);
    final soft = grammaTheme(Brightness.light, 0.5);
    expect(full.scaffoldBackgroundColor, Colors.white);
    expect(soft.scaffoldBackgroundColor, isNot(Colors.white));
    expect(
      soft.colorScheme.onSurface.computeLuminance(),
      greaterThan(full.colorScheme.onSurface.computeLuminance()),
    );
    final dark = grammaTheme(Brightness.dark, 0.5);
    expect(dark.scaffoldBackgroundColor, isNot(const Color(0xFF0D0D0F)));
  });

  testWidgets('the language override renders the German UI', (tester) async {
    tester.view.physicalSize = const Size(800, 1900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = await _controller();
    controller.setLocaleCode('de');
    await tester.pumpWidget(_harness(controller));
    expect(find.text('Einstellungen'), findsOneWidget);
    expect(find.text('Erscheinungsbild'), findsOneWidget);
    expect(find.text('Zeilenlänge'), findsOneWidget);
    controller.setLocaleCode(null);
    await tester.pumpAndSettle();
    expect(
      find.text('Settings'),
      findsOneWidget,
      reason: 'system locale (en in tests) returns',
    );
  });

  testWidgets('theme mode selection applies', (tester) async {
    // Tall viewport: the settings page has grown past the default 600px.
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = await _controller();
    await tester.pumpWidget(_harness(controller));
    await _openTab(tester, 'appearance');
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(controller.themeMode, ThemeMode.dark);
    final context = tester.element(find.byType(SettingsScreen));
    expect(Theme.of(context).brightness, Brightness.dark);
  });

  testWidgets('the line length slider commits on release', (tester) async {
    tester.view.physicalSize = const Size(800, 1900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = await _controller();
    await tester.pumpWidget(_harness(controller));
    final slider = find.byKey(const Key('measure-slider'));
    expect(slider, findsOneWidget, reason: 'on the Reading tab, unlocked');
    await tester.drag(slider, const Offset(-200, 0));
    await tester.pumpAndSettle();
    expect(
      controller.measureEms,
      lessThan(SettingsController.defaultMeasureEms),
    );
  });

  testWidgets('column gap slider updates the controller', (tester) async {
    tester.view.physicalSize = const Size(800, 1900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = await _controller();
    await tester.pumpWidget(_harness(controller));
    final slider = find.byKey(const Key('gap-slider'));
    await tester.ensureVisible(slider);
    await tester.pumpAndSettle();
    await tester.drag(slider, const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(
      controller.columnGapEms,
      greaterThan(SettingsController.defaultColumnGapEms),
    );
    expect(controller.columnGapEms * 2, controller.columnGapEms * 2 ~/ 1);
  });

  testWidgets('contrast slider updates the controller', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = await _controller();
    await tester.pumpWidget(_harness(controller));
    await _openTab(tester, 'appearance');
    final slider = find.byKey(const Key('contrast-slider'));
    await tester.drag(slider, const Offset(-200, 0));
    await tester.pumpAndSettle();
    expect(controller.contrast, lessThan(SettingsController.defaultContrast));
  });

  test('column turn effort clamps and persists', () async {
    final controller = await _controller();
    expect(controller.columnAdvance, SettingsController.defaultColumnAdvance);
    controller.setColumnAdvance(0.01);
    expect(controller.columnAdvance, SettingsController.minColumnAdvance);
    controller.setColumnAdvance(0.3);
    final reloaded = SettingsController(await SharedPreferences.getInstance());
    expect(reloaded.columnAdvance, 0.3);
  });

  test('the typeface applies directly and refuses unknown families', () async {
    final controller = await _controller();
    expect(controller.fontFamily, 'GentiumBookPlus');
    controller.setFontFamily('NoSuchFont');
    expect(
      controller.fontFamily,
      'GentiumBookPlus',
      reason: 'unknown families are refused',
    );
    controller.setFontFamily('GentiumPlus');
    final reloaded = SettingsController(await SharedPreferences.getInstance());
    expect(reloaded.fontFamily, 'GentiumPlus');
  });

  test('font weight is separate per brightness and persists', () async {
    final controller = await _controller();
    expect(controller.fontWeightLight, SettingsController.defaultFontWeight);
    expect(controller.fontWeightDark, SettingsController.defaultFontWeight);
    controller.setFontWeightDark(0.04);
    controller.setFontWeightLight(0.9);
    expect(
      controller.fontWeightLight,
      SettingsController.maxFontWeight,
      reason: 'clamped',
    );
    expect(controller.fontWeightFor(Brightness.dark), 0.04);
    expect(
      controller.fontWeightFor(Brightness.light),
      SettingsController.maxFontWeight,
    );
    final reloaded = SettingsController(await SharedPreferences.getInstance());
    expect(reloaded.fontWeightDark, 0.04);
  });

  testWidgets('column turn effort slider runs light to firm', (tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = await _controller();
    await tester.pumpWidget(_harness(controller));
    final slider = find.byKey(const Key('advance-slider'));
    // Dragging left (toward "light") must lower the required advance.
    await tester.drag(slider, const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(
      controller.columnAdvance,
      lessThan(SettingsController.defaultColumnAdvance),
    );
  });

  test('keep-screen-on persists and hides off mobile', () async {
    final controller = await _controller();
    expect(controller.keepScreenOn, isFalse);
    controller.setKeepScreenOn(true);
    expect(controller.keepScreenOn, isTrue);
    final reloaded = SettingsController(await SharedPreferences.getInstance());
    expect(reloaded.keepScreenOn, isTrue);
    // The test host is a desktop: the switch stays out of the screen.
    expect(SettingsController.keepScreenOnAvailable, isFalse);
  });

  testWidgets('the version and build number close the settings', (
    tester,
  ) async {
    PackageInfo.setMockInitialValues(
      appName: 'gramma',
      packageName: 'io.sse.gramma',
      version: '1.1.0',
      buildNumber: '6',
      buildSignature: '',
    );
    final controller = await _controller();
    await tester.pumpWidget(_harness(controller));
    await _openTab(tester, 'about');
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const Key('app-version'))).data,
      startsWith('Version 1.1.0 (6)'),
    );
  });
}
