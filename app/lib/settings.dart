import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User settings, persisted locally.
///
/// The measure (line width in ems) is deliberately hard to change: it
/// defines where every line breaks, and with that the reader's visual
/// memory of the text. [setMeasureEms] therefore refuses to apply unless
/// the caller confirms an explicit user decision.
class SettingsController extends ChangeNotifier {
  SettingsController(this._prefs) {
    _columnWidth = _prefs.getDouble('columnWidth') ?? defaultColumnWidth;
    _contrast = _prefs.getDouble('contrast') ?? defaultContrast;
    _measureEms = _prefs.getInt('measureEms') ?? defaultMeasureEms;
    _trueBlackDark = _prefs.getBool('trueBlackDark') ?? false;
    _themeMode = switch (_prefs.getString('themeMode')) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  static const defaultColumnWidth = 400.0;
  static const defaultContrast = 0.85;
  static const defaultMeasureEms = 26;

  final SharedPreferences _prefs;

  double _columnWidth = defaultColumnWidth;
  double _contrast = defaultContrast;
  int _measureEms = defaultMeasureEms;
  ThemeMode _themeMode = ThemeMode.system;
  bool _trueBlackDark = false;

  /// Column width in logical pixels — the zoom level.
  double get columnWidth => _columnWidth;

  /// Text/background contrast, 0.5 (soft) … 1.0 (maximum).
  double get contrast => _contrast;

  /// Line width in ems; the protected measure.
  int get measureEms => _measureEms;

  ThemeMode get themeMode => _themeMode;

  /// Dark mode keeps a pure-black background; contrast dims only the text.
  bool get trueBlackDark => _trueBlackDark;

  void setColumnWidth(double value) {
    _columnWidth = value.clamp(320.0, 520.0);
    _prefs.setDouble('columnWidth', _columnWidth);
    notifyListeners();
  }

  void setContrast(double value) {
    _contrast = value.clamp(0.5, 1.0);
    _prefs.setDouble('contrast', _contrast);
    notifyListeners();
  }

  void setTrueBlackDark(bool value) {
    _trueBlackDark = value;
    _prefs.setBool('trueBlackDark', value);
    notifyListeners();
  }

  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    _prefs.setString('themeMode', mode.name);
    notifyListeners();
  }

  /// Applies a new measure only for a confirmed, deliberate user decision;
  /// programmatic calls without confirmation are an error.
  void setMeasureEms(int value, {required bool confirmed}) {
    if (!confirmed) {
      throw StateError(
        'the measure defines the reader\'s visual memory and must only be '
        'changed after explicit user confirmation',
      );
    }
    _measureEms = value.clamp(18, 36);
    _prefs.setInt('measureEms', _measureEms);
    notifyListeners();
  }
}

/// Makes the [SettingsController] available below the MaterialApp so routes
/// and the reader can depend on it.
class SettingsScope extends InheritedNotifier<SettingsController> {
  const SettingsScope({
    super.key,
    required SettingsController controller,
    required super.child,
  }) : super(notifier: controller);

  static SettingsController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<SettingsScope>();
    assert(scope != null, 'SettingsScope missing above this context');
    return scope!.notifier!;
  }
}

/// Reading themes: at full contrast, near-black ink on white (or the
/// inverse); lower contrast settles toward warm paper and softened ink, in
/// the tradition of printed books rather than terminals.
///
/// With [trueBlack], the dark background stays pure black (for OLED panels
/// and dark rooms) and the contrast setting dims only the text.
ThemeData grammaTheme(Brightness brightness, double contrast,
    {bool trueBlack = false}) {
  final t = ((contrast - 0.5) / 0.5).clamp(0.0, 1.0);
  final Color background;
  final Color ink;
  if (brightness == Brightness.light) {
    background = Color.lerp(const Color(0xFFF5EFE3), Colors.white, t)!;
    ink = Color.lerp(const Color(0xFF4A453D), const Color(0xFF14120F), t)!;
  } else {
    background = trueBlack
        ? Colors.black
        : Color.lerp(const Color(0xFF26262B), const Color(0xFF0D0D0F), t)!;
    ink = Color.lerp(const Color(0xFFB8B5AD), const Color(0xFFF2EFE8), t)!;
  }
  final base = ThemeData(
    brightness: brightness,
    colorSchemeSeed: const Color(0xFF7A5C3E),
  );
  return base.copyWith(
    scaffoldBackgroundColor: background,
    colorScheme: base.colorScheme.copyWith(
      surface: background,
      onSurface: ink,
    ),
  );
}
