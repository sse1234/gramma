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
      theme: grammaTheme(Brightness.light, controller.contrast),
      darkTheme: grammaTheme(Brightness.dark, controller.contrast),
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
      ..setThemeMode(ThemeMode.dark);
    first.setMeasureEms(30, confirmed: true);
    final second = SettingsController(prefs);
    expect(second.columnWidth, 460);
    expect(second.contrast, 0.7);
    expect(second.themeMode, ThemeMode.dark);
    expect(second.measureEms, 30);
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
    final controller = await _controller();
    await tester.pumpWidget(_harness(controller));
    final slider = find.byKey(const Key('contrast-slider'));
    await tester.drag(slider, const Offset(-200, 0));
    await tester.pumpAndSettle();
    expect(controller.contrast, lessThan(SettingsController.defaultContrast));
  });
}
