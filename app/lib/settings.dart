import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'palette.dart';

/// Tone families for the reading surface: the hue anchor of the softened
/// background and ink. Parameters, not hand-picked colors — each tone is
/// (hue, chroma-light, chroma-dark) fed to the HCL engine.
enum ToneTheme {
  paper(85, 22, 8),
  sepia(55, 30, 10),
  stone(85, 0, 0),
  sage(140, 16, 8),
  mist(250, 14, 8);

  const ToneTheme(this.hue, this.chromaLight, this.chromaDark);

  final double hue;
  final double chromaLight;
  final double chromaDark;
}

/// The tone's softened background, for swatches and theme building.
Color toneBackground(ToneTheme tone, Brightness brightness) {
  return brightness == Brightness.light
      ? hcl(tone.hue, tone.chromaLight, 91)
      : hcl(tone.hue, tone.chromaDark, 19);
}

/// The tone's softened ink.
Color toneInk(ToneTheme tone, Brightness brightness) {
  return brightness == Brightness.light
      ? hcl(tone.hue, tone.chromaLight.clamp(0, 8), 38)
      : hcl(tone.hue, tone.chromaDark.clamp(0, 6), 62);
}

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
    _lineSpacing = _prefs.getDouble('lineSpacing') ?? defaultLineSpacing;
    _measureEms = _prefs.getInt('measureEms') ?? defaultMeasureEms;
    _trueBlackDark = _prefs.getBool('trueBlackDark') ?? false;
    _readingMode = _prefs.getBool('readingMode') ?? false;
    _defaultModule = _prefs.getString('defaultModule');
    _tone = ToneTheme.values
            .where((t) => t.name == _prefs.getString('tone'))
            .firstOrNull ??
        ToneTheme.paper;
    _footnoteScale = _prefs.getDouble('footnoteScale') ?? 1.0;
    _previewScale = _prefs.getDouble('previewScale') ?? 1.0;
    _columnAdvance = _prefs.getDouble('columnAdvance') ?? defaultColumnAdvance;
    _currentDeskId = _prefs.getString('currentDesk');
    _fontWeightLight =
        _prefs.getDouble('fontWeightLight') ?? defaultFontWeight;
    _fontWeightDark =
        _prefs.getDouble('fontWeightDark') ?? defaultFontWeight;
    _themeMode = switch (_prefs.getString('themeMode')) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  static const defaultColumnWidth = 400.0;
  static const defaultContrast = 0.85;
  static const minContrast = 0.3;
  static const defaultMeasureEms = 26;
  static const defaultLineSpacing = 1.5;
  static const defaultColumnAdvance = 0.5;
  static const minColumnAdvance = 0.15;
  static const maxColumnAdvance = 0.6;

  final SharedPreferences _prefs;

  double _columnWidth = defaultColumnWidth;
  double _contrast = defaultContrast;
  double _lineSpacing = defaultLineSpacing;
  int _measureEms = defaultMeasureEms;
  ThemeMode _themeMode = ThemeMode.system;
  bool _trueBlackDark = false;
  bool _readingMode = false;
  String? _defaultModule;
  ToneTheme _tone = ToneTheme.paper;
  double _footnoteScale = 1.0;
  double _previewScale = 1.0;
  double _columnAdvance = defaultColumnAdvance;
  String? _currentDeskId;
  double _fontWeightLight = 0;
  double _fontWeightDark = 0;

  /// Extra stroke weight over the font's natural stems, in ems of the
  /// font size, separately per brightness: dim rooms with dim screens
  /// want heavier dark-mode strokes. 0 = the font as designed, matching
  /// the footnote and preview text exactly.
  static const maxFontWeight = 0.06;

  /// Impeller (iOS/Android) rasterizes glyphs visibly lighter than the
  /// desktop renderer, so those platforms default one notch up; the
  /// setting itself is the only mechanism — no hidden baseline.
  static final defaultFontWeight = !kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.iOS ||
              defaultTargetPlatform == TargetPlatform.android)
      ? 0.02
      : 0.0;

  double get fontWeightLight => _fontWeightLight;
  double get fontWeightDark => _fontWeightDark;

  /// The extra stroke weight for the given brightness.
  double fontWeightFor(Brightness brightness) =>
      brightness == Brightness.dark ? _fontWeightDark : _fontWeightLight;

  void setFontWeightLight(double value) {
    _fontWeightLight = value.clamp(0.0, maxFontWeight);
    _prefs.setDouble('fontWeightLight', _fontWeightLight);
    notifyListeners();
  }

  void setFontWeightDark(double value) {
    _fontWeightDark = value.clamp(0.0, maxFontWeight);
    _prefs.setDouble('fontWeightDark', _fontWeightDark);
    notifyListeners();
  }

  /// Column width in logical pixels — the zoom level.
  double get columnWidth => _columnWidth;

  /// Text/background contrast, [minContrast] (soft) … 1.0 (maximum).
  double get contrast => _contrast;

  /// Line height as a multiple of the font size.
  double get lineSpacing => _lineSpacing;

  /// Line width in ems; the protected measure.
  int get measureEms => _measureEms;

  ThemeMode get themeMode => _themeMode;

  /// Dark mode keeps a pure-black background; contrast dims only the text.
  bool get trueBlackDark => _trueBlackDark;

  /// Reading mode hides all chrome (app bar, pane headers); setup mode
  /// shows it. Toggled by tapping any pane's content.
  bool get readingMode => _readingMode;

  /// Tone family of the softened reading surface.
  ToneTheme get tone => _tone;

  /// Text scale of the footnotes view (1.0 = theme default).
  double get footnoteScale => _footnoteScale;

  /// Text scale of passage preview popups.
  double get previewScale => _previewScale;

  /// Fraction of a column a swipe must naturally travel to turn to the
  /// next column ([minColumnAdvance] light … [maxColumnAdvance] firm).
  double get columnAdvance => _columnAdvance;

  /// Module used to resolve references outside any pane context
  /// (passage previews, later cross-references in secondary literature).
  String? get defaultModule => _defaultModule;

  void setColumnWidth(double value) {
    _columnWidth = value.clamp(320.0, 520.0);
    _prefs.setDouble('columnWidth', _columnWidth);
    notifyListeners();
  }

  void setContrast(double value) {
    _contrast = value.clamp(minContrast, 1.0);
    _prefs.setDouble('contrast', _contrast);
    notifyListeners();
  }

  void setLineSpacing(double value) {
    _lineSpacing = value.clamp(1.2, 2.6);
    _prefs.setDouble('lineSpacing', _lineSpacing);
    notifyListeners();
  }

  void setTone(ToneTheme tone) {
    _tone = tone;
    _prefs.setString('tone', tone.name);
    notifyListeners();
  }

  void setFootnoteScale(double value) {
    _footnoteScale = value.clamp(0.8, 1.6);
    _prefs.setDouble('footnoteScale', _footnoteScale);
    notifyListeners();
  }

  void setPreviewScale(double value) {
    _previewScale = value.clamp(0.8, 1.6);
    _prefs.setDouble('previewScale', _previewScale);
    notifyListeners();
  }

  void setColumnAdvance(double value) {
    _columnAdvance = value.clamp(minColumnAdvance, maxColumnAdvance);
    _prefs.setDouble('columnAdvance', _columnAdvance);
    notifyListeners();
  }

  /// Raw preferences for subsystems keeping their own keys (the Dropbox
  /// transport's rev cache and tokens).
  SharedPreferences get prefs => _prefs;

  /// The user-brought Dropbox app key and refresh token (ADR 0014's
  /// direct transport); null while not connected.
  String? get dropboxAppKey => _prefs.getString('dropboxAppKey');
  String? get dropboxRefreshToken => _prefs.getString('dropboxRefreshToken');

  void setDropbox({String? appKey, String? refreshToken}) {
    if (appKey == null) {
      _prefs.remove('dropboxAppKey');
    } else {
      _prefs.setString('dropboxAppKey', appKey);
    }
    if (refreshToken == null) {
      _prefs.remove('dropboxRefreshToken');
    } else {
      _prefs.setString('dropboxRefreshToken', refreshToken);
    }
    notifyListeners();
  }

  /// The desk this device currently shows — local state by design
  /// (ADR 0014): other devices may sit on other desks.
  String? get currentDeskId => _currentDeskId;

  void setCurrentDeskId(String id) {
    _currentDeskId = id;
    _prefs.setString('currentDesk', id);
    notifyListeners();
  }

  void setDefaultModule(String? code) {
    _defaultModule = code;
    if (code == null) {
      _prefs.remove('defaultModule');
    } else {
      _prefs.setString('defaultModule', code);
    }
    notifyListeners();
  }

  void setReadingMode(bool value) {
    _readingMode = value;
    _prefs.setBool('readingMode', value);
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
    {bool trueBlack = false, ToneTheme tone = ToneTheme.paper}) {
  final t = ((contrast - SettingsController.minContrast) /
          (1.0 - SettingsController.minContrast))
      .clamp(0.0, 1.0);
  final Color background;
  final Color ink;
  if (brightness == Brightness.light) {
    background =
        Color.lerp(toneBackground(tone, brightness), Colors.white, t)!;
    ink = Color.lerp(
        toneInk(tone, brightness), const Color(0xFF14120F), t)!;
  } else {
    background = trueBlack
        ? Colors.black
        : Color.lerp(
            toneBackground(tone, brightness), const Color(0xFF0D0D0F), t)!;
    ink = Color.lerp(
        toneInk(tone, brightness), const Color(0xFFF2EFE8), t)!;
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
