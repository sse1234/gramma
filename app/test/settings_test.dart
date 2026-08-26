import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gramma/settings.dart';
import 'package:gramma/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<SettingsController> _controller() async {
  SharedPreferences.setMockInitialValues({});
  return SettingsController(await SharedPreferences.getInstance());
}

Widget _harness(SettingsController controller) {
  return ListenableBuilder(
    listenable: controller,
    builder: (context, _) => MaterialApp(
      themeMode: controller.themeMode,
      theme: grammaTheme(Brightness.light, controller.contrast,
          tone: controller.tone),
      darkTheme: grammaTheme(Brightness.dark, controller.contrast,
          trueBlack: controller.trueBlackDark, tone: controller.tone),
      builder: (context, child) =>
          SettingsScope(controller: controller, child: child!),
      home: const SettingsScreen(),
    ),
  );
}

void main() {
  test('measure changes require explicit confirmation', () async {
    final controller = await _controller();
    expect(
      () => controller.setMeasureEms(30, confirmed: false),
      throwsStateError,
    );
    expect(controller.measureEms, SettingsController.defaultMeasureEms);
    controller.setMeasureEms(30, confirmed: true);
    expect(controller.measureEms, 30);
  });

  test('settings persist across controller instances', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final first = SettingsController(prefs)
      ..setColumnWidth(460)
      ..setContrast(0.7)
      ..setLineSpacing(2.0)
      ..setDefaultModule('GerNeUe')
      ..setTone(ToneTheme.sage)
      ..setFootnoteScale(1.2)
      ..setPreviewScale(1.4)
      ..setThemeMode(ThemeMode.dark);
    first.setMeasureEms(30, confirmed: true);
    final second = SettingsController(prefs);
    expect(second.columnWidth, 460);
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

  test('true black keeps the background at pure black and dims only text',
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
    final reloaded =
        SettingsController(await SharedPreferences.getInstance());
    expect(reloaded.trueBlackDark, isTrue);
  });

  test('tones tint the softened surface distinctly, neutral stone included',
      () {
    final backgrounds = [
      for (final tone in ToneTheme.values)
        grammaTheme(Brightness.light, SettingsController.minContrast,
                tone: tone)
            .scaffoldBackgroundColor,
    ];
    for (var i = 0; i < backgrounds.length; i++) {
      for (var j = i + 1; j < backgrounds.length; j++) {
        expect(backgrounds[i], isNot(backgrounds[j]),
            reason: 'tones $i and $j must differ');
      }
    }
    final stone = grammaTheme(Brightness.light, SettingsController.minContrast,
            tone: ToneTheme.stone)
        .scaffoldBackgroundColor;
    int ch(double x) => (x * 255).round();
    expect((ch(stone.r) - ch(stone.b)).abs(), lessThan(3),
        reason: 'stone is neutral');
    // Full contrast converges to pure white regardless of tone.
    expect(
      grammaTheme(Brightness.light, 1.0, tone: ToneTheme.mist)
          .scaffoldBackgroundColor,
      Colors.white,
    );
    // True black stays black in every tone.
    expect(
      grammaTheme(Brightness.dark, 0.5,
              trueBlack: true, tone: ToneTheme.sepia)
          .scaffoldBackgroundColor,
      Colors.black,
    );
  });

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

  testWidgets('theme mode selection applies', (tester) async {
    // Tall viewport: the settings page has grown past the default 600px.
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = await _controller();
    await tester.pumpWidget(_harness(controller));
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(controller.themeMode, ThemeMode.dark);
    final context = tester.element(find.byType(SettingsScreen));
    expect(Theme.of(context).brightness, Brightness.dark);
  });

  testWidgets('measure slider is locked behind a confirmation dialog',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = await _controller();
    await tester.pumpWidget(_harness(controller));
    expect(find.byKey(const Key('measure-slider')), findsNothing);

    await tester.tap(find.byKey(const Key('change-measure')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('measure-cancel')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('measure-slider')), findsNothing);

    await tester.tap(find.byKey(const Key('change-measure')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('measure-confirm')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('measure-slider')), findsOneWidget);
  });

  testWidgets('contrast slider updates the controller', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = await _controller();
    await tester.pumpWidget(_harness(controller));
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
    final reloaded =
        SettingsController(await SharedPreferences.getInstance());
    expect(reloaded.columnAdvance, 0.3);
  });

  test('the typeface is protected like the measure', () async {
    final controller = await _controller();
    expect(controller.fontFamily, 'GentiumBookPlus');
    expect(
      () => controller.setFontFamily('GentiumPlus', confirmed: false),
      throwsStateError,
    );
    controller.setFontFamily('NoSuchFont', confirmed: true);
    expect(controller.fontFamily, 'GentiumBookPlus',
        reason: 'unknown families are refused');
    controller.setFontFamily('GentiumPlus', confirmed: true);
    final reloaded =
        SettingsController(await SharedPreferences.getInstance());
    expect(reloaded.fontFamily, 'GentiumPlus');
  });

  test('font weight is separate per brightness and persists', () async {
    final controller = await _controller();
    expect(controller.fontWeightLight, SettingsController.defaultFontWeight);
    expect(controller.fontWeightDark, SettingsController.defaultFontWeight);
    controller.setFontWeightDark(0.04);
    controller.setFontWeightLight(0.9);
    expect(controller.fontWeightLight, SettingsController.maxFontWeight,
        reason: 'clamped');
    expect(controller.fontWeightFor(Brightness.dark), 0.04);
    expect(controller.fontWeightFor(Brightness.light),
        SettingsController.maxFontWeight);
    final reloaded =
        SettingsController(await SharedPreferences.getInstance());
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
    await tester.scrollUntilVisible(slider, 200);
    // Dragging left (toward "light") must lower the required advance.
    await tester.drag(slider, const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(controller.columnAdvance,
        lessThan(SettingsController.defaultColumnAdvance));
  });
}
