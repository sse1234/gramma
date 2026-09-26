import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

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

/// The text's elements whose presence the reader may set (ADR 0031).
enum TextElement {
  /// The chapter title row ("2. Mose 3").
  chapterHeading,

  /// A section title inside the text (level 1).
  sectionHeading,

  /// A line of parallel passages under a section title (level 2).
  passageLine,

  /// Verse numbers.
  verseNumber,

  /// Footnote markers.
  noteMarker,
}

/// Presence of one element: a size factor (chapter headings only — the
/// other elements sit inside typeset lines, whose breaks their size
/// would move), extra stroke weight in ems over the reading weight, and
/// an italic slant.
class ElementStyle {
  const ElementStyle({this.scale = 1, this.weightEm = 0, this.italic = false});

  final double scale;
  final double weightEm;
  final bool italic;

  ElementStyle copyWith({double? scale, double? weightEm, bool? italic}) =>
      ElementStyle(
        scale: scale ?? this.scale,
        weightEm: weightEm ?? this.weightEm,
        italic: italic ?? this.italic,
      );

  @override
  bool operator ==(Object other) =>
      other is ElementStyle &&
      other.scale == scale &&
      other.weightEm == weightEm &&
      other.italic == italic;

  @override
  int get hashCode => Object.hash(scale, weightEm, italic);
}

/// User settings, persisted locally.
///
/// Presentation is the reader's (ADR 0032): the glyph size and the line
/// length are plain settings, per device. The engine lays out in ems, so
/// a size change repaints and a line-length change re-typesets in the
/// background.
class SettingsController extends ChangeNotifier {
  SettingsController(this._prefs) {
    _contrast = _prefs.getDouble('contrast') ?? defaultContrast;
    _lineSpacing = _prefs.getDouble('lineSpacing') ?? defaultLineSpacing;
    _measureEms = (_prefs.getInt('measureEms') ?? defaultMeasureEms).clamp(
      minMeasureEms,
      maxMeasureEms,
    );
    // Before ADR 0032 the column width was the size setting and the glyph
    // size fell out of it; an existing installation keeps its reading.
    final storedGlyph = _prefs.getDouble('glyphSize');
    final legacyColumn = _prefs.getDouble('columnWidth');
    _glyphSize =
        (storedGlyph ??
                (legacyColumn == null
                    ? defaultGlyphSize
                    : legacyColumn / _measureEms))
            .clamp(minGlyphSize, maxGlyphSize);
    if (storedGlyph == null && legacyColumn != null) {
      _prefs.setDouble('glyphSize', _glyphSize);
      _prefs.remove('columnWidth');
    }
    _trueBlackDark = _prefs.getBool('trueBlackDark') ?? false;
    _readingMode = _prefs.getBool('readingMode') ?? false;
    _keepScreenOn = _prefs.getBool('keepScreenOn') ?? false;
    _applyWakelock();
    _defaultModule = _prefs.getString('defaultModule');
    _tone =
        ToneTheme.values
            .where((t) => t.name == _prefs.getString('tone'))
            .firstOrNull ??
        ToneTheme.paper;
    _footnoteScale = _prefs.getDouble('footnoteScale') ?? 1.0;
    _previewScale = _prefs.getDouble('previewScale') ?? 1.0;
    _commentaryScale = _prefs.getDouble('commentaryScale') ?? 1.0;
    _columnAdvance = _prefs.getDouble('columnAdvance') ?? defaultColumnAdvance;
    _currentDeskId = _prefs.getString('currentDesk');
    _fontWeightLight = _prefs.getDouble('fontWeightLight') ?? defaultFontWeight;
    _fontWeightDark = _prefs.getDouble('fontWeightDark') ?? defaultFontWeight;
    final family = _prefs.getString('fontFamily');
    if (family != null && fontAssets.containsKey(family)) {
      _fontFamily = family;
    }
    _localeCode = _prefs.getString('locale');
    for (final element in TextElement.values) {
      final base = defaultElementStyles[element]!;
      final key = 'style.${element.name}';
      _elementStyles[element] = ElementStyle(
        scale: (_prefs.getDouble('$key.scale') ?? base.scale).clamp(
          minElementScale,
          maxElementScale,
        ),
        weightEm: (_prefs.getDouble('$key.weight') ?? base.weightEm).clamp(
          0.0,
          maxElementWeight,
        ),
        italic: _prefs.getBool('$key.italic') ?? base.italic,
      );
    }
    _themeMode = switch (_prefs.getString('themeMode')) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  /// The bundled typefaces (all SIL OFL): Gentium Book Plus is the
  /// default, Gentium Plus its slightly lighter companion cut, and
  /// Literata a visibly different voice designed for e-reading.
  static const fontAssets = {
    'GentiumBookPlus': 'fonts/GentiumBookPlus-Regular.ttf',
    'GentiumPlus': 'fonts/GentiumPlus-Regular.ttf',
    'Literata': 'fonts/Literata-Regular.ttf',
  };

  static const fontDisplayNames = {
    'GentiumBookPlus': 'Gentium Book Plus',
    'GentiumPlus': 'Gentium Plus',
    'Literata': 'Literata',
  };

  /// Glyph size in logical pixels; 16 px at 25 em is a 400 px column.
  static const defaultGlyphSize = 16.0;
  static const minGlyphSize = 10.0;
  static const maxGlyphSize = 40.0;
  static const defaultContrast = 0.85;
  static const minContrast = 0.3;
  static const defaultMeasureEms = 25;

  /// The measure runs down to a few ems: at very large type (low vision)
  /// a column holds only a handful of characters, and the setter still
  /// breaks and hyphenates rather than leaving one word per line.
  static const minMeasureEms = 4;
  static const maxMeasureEms = 36;
  static const defaultLineSpacing = 1.5;

  /// Solid setting (1.0) is the floor: very large type wants its lines
  /// close, and the font's own ascent and descent keep them apart.
  static const minLineSpacing = 1.0;
  static const maxLineSpacing = 2.6;
  static const defaultColumnAdvance = 0.5;
  static const minColumnAdvance = 0.15;
  static const maxColumnAdvance = 0.6;

  final SharedPreferences _prefs;

  double _glyphSize = defaultGlyphSize;
  double _contrast = defaultContrast;
  double _lineSpacing = defaultLineSpacing;
  int _measureEms = defaultMeasureEms;
  ThemeMode _themeMode = ThemeMode.system;
  bool _trueBlackDark = false;
  bool _readingMode = false;
  bool _keepScreenOn = false;
  String? _defaultModule;
  ToneTheme _tone = ToneTheme.paper;
  double _footnoteScale = 1.0;
  double _previewScale = 1.0;
  double _commentaryScale = 1.0;
  double _columnAdvance = defaultColumnAdvance;
  String? _currentDeskId;
  double _fontWeightLight = 0;
  double _fontWeightDark = 0;
  String _fontFamily = 'GentiumBookPlus';
  String? _localeCode;

  /// UI language override; null follows the system locale (ADR 0015).
  Locale? get localeOverride =>
      _localeCode == null ? null : Locale(_localeCode!);

  String? get localeCode => _localeCode;

  void setLocaleCode(String? code) {
    _localeCode = code;
    if (code == null) {
      _prefs.remove('locale');
    } else {
      _prefs.setString('locale', code);
    }
    notifyListeners();
  }

  /// The reading typeface; a change re-typesets in the background.
  String get fontFamily => _fontFamily;

  void setFontFamily(String family) {
    if (!fontAssets.containsKey(family)) return;
    _fontFamily = family;
    _prefs.setString('fontFamily', family);
    notifyListeners();
  }

  /// The elements' presence as designed: the chapter title a size larger
  /// and heaviest, section titles a shade heavier than text, parallel
  /// passages and note markers in italics (ADR 0029, 0031).
  static const defaultElementStyles = {
    TextElement.chapterHeading: ElementStyle(scale: 1.25, weightEm: 0.03),
    TextElement.sectionHeading: ElementStyle(weightEm: 0.02),
    TextElement.passageLine: ElementStyle(italic: true),
    TextElement.verseNumber: ElementStyle(),
    TextElement.noteMarker: ElementStyle(italic: true),
  };
  static const minElementScale = 0.9;
  static const maxElementScale = 1.8;
  static const maxElementWeight = 0.08;

  final Map<TextElement, ElementStyle> _elementStyles = {};

  ElementStyle styleOf(TextElement element) =>
      _elementStyles[element] ?? defaultElementStyles[element]!;

  void setElementStyle(TextElement element, ElementStyle style) {
    final key = 'style.${element.name}';
    final clamped = ElementStyle(
      scale: style.scale.clamp(minElementScale, maxElementScale),
      weightEm: style.weightEm.clamp(0.0, maxElementWeight),
      italic: style.italic,
    );
    _elementStyles[element] = clamped;
    _prefs.setDouble('$key.scale', clamped.scale);
    _prefs.setDouble('$key.weight', clamped.weightEm);
    _prefs.setBool('$key.italic', clamped.italic);
    notifyListeners();
  }

  /// Back to the designed presence for every element.
  void resetElementStyles() {
    for (final element in TextElement.values) {
      _elementStyles[element] = defaultElementStyles[element]!;
      final key = 'style.${element.name}';
      _prefs.remove('$key.scale');
      _prefs.remove('$key.weight');
      _prefs.remove('$key.italic');
    }
    notifyListeners();
  }

  /// Extra stroke weight over the font's natural stems, in ems of the
  /// font size, separately per brightness: dim rooms with dim screens
  /// want heavier dark-mode strokes. 0 = the font as designed, matching
  /// the footnote and preview text exactly.
  static const maxFontWeight = 0.06;

  /// Impeller (iOS/Android) rasterizes glyphs visibly lighter than the
  /// desktop renderer, so those platforms default one notch up; the
  /// setting itself is the only mechanism — no hidden baseline.
  static final defaultFontWeight =
      !kIsWeb &&
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

  /// Text size: the glyph size in logical pixels (ADR 0032).
  double get glyphSize => _glyphSize;

  /// The preferred column width in logical pixels — line length times
  /// glyph size; a pane narrower than this fits its line length instead.
  double get columnWidth => _glyphSize * _measureEms;

  /// Text/background contrast, [minContrast] (soft) … 1.0 (maximum).
  double get contrast => _contrast;

  /// Line height as a multiple of the font size.
  double get lineSpacing => _lineSpacing;

  /// Line length in ems (about 2.1 characters each); a pane narrower
  /// than one column of it lays out at what fits (ADR 0032).
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

  /// Text scale of the commentary view's typeset text (ADR 0018).
  double get commentaryScale => _commentaryScale;

  /// Fraction of a column a swipe must naturally travel to turn to the
  /// next column ([minColumnAdvance] light … [maxColumnAdvance] firm).
  double get columnAdvance => _columnAdvance;

  /// Module used to resolve references outside any pane context
  /// (passage previews, later cross-references in secondary literature).
  String? get defaultModule => _defaultModule;

  void setGlyphSize(double value) {
    _glyphSize = value.clamp(minGlyphSize, maxGlyphSize);
    _prefs.setDouble('glyphSize', _glyphSize);
    notifyListeners();
  }

  void setContrast(double value) {
    _contrast = value.clamp(minContrast, 1.0);
    _prefs.setDouble('contrast', _contrast);
    notifyListeners();
  }

  void setLineSpacing(double value) {
    _lineSpacing = value.clamp(minLineSpacing, maxLineSpacing);
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

  void setCommentaryScale(double value) {
    _commentaryScale = value.clamp(0.8, 1.6);
    _prefs.setDouble('commentaryScale', _commentaryScale);
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

  /// Keep-screen-on is a mobile concern: desktops manage their own
  /// display sleep, and the plugin is absent under flutter_test.
  static bool get keepScreenOnAvailable =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  bool get keepScreenOn => _keepScreenOn;

  void setKeepScreenOn(bool value) {
    _keepScreenOn = value;
    _prefs.setBool('keepScreenOn', value);
    _applyWakelock();
    notifyListeners();
  }

  void _applyWakelock() {
    if (!keepScreenOnAvailable) return;
    WakelockPlus.toggle(enable: _keepScreenOn).ignore();
  }

  /// The security-scoped bookmark for the Mac sync folder (ADR 0027);
  /// device-local by nature, so it lives in prefs, not the synced
  /// store. No listener notification: nothing visible depends on it.
  String? get macSyncBookmark => _prefs.getString('macSyncBookmark');

  void setMacSyncBookmark(String? value) {
    if (value == null) {
      _prefs.remove('macSyncBookmark');
    } else {
      _prefs.setString('macSyncBookmark', value);
    }
  }

  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    _prefs.setString('themeMode', mode.name);
    notifyListeners();
  }

  /// The line length; every text view re-typesets in the background.
  void setMeasureEms(int value) {
    _measureEms = value.clamp(minMeasureEms, maxMeasureEms);
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
ThemeData grammaTheme(
  Brightness brightness,
  double contrast, {
  bool trueBlack = false,
  ToneTheme tone = ToneTheme.paper,
}) {
  final t =
      ((contrast - SettingsController.minContrast) /
              (1.0 - SettingsController.minContrast))
          .clamp(0.0, 1.0);
  final Color background;
  final Color ink;
  if (brightness == Brightness.light) {
    background = Color.lerp(toneBackground(tone, brightness), Colors.white, t)!;
    ink = Color.lerp(toneInk(tone, brightness), const Color(0xFF14120F), t)!;
  } else {
    background = trueBlack
        ? Colors.black
        : Color.lerp(
            toneBackground(tone, brightness),
            const Color(0xFF0D0D0F),
            t,
          )!;
    ink = Color.lerp(toneInk(tone, brightness), const Color(0xFFF2EFE8), t)!;
  }
  final base = ThemeData(
    brightness: brightness,
    colorSchemeSeed: const Color(0xFF7A5C3E),
  );
  return base.copyWith(
    scaffoldBackgroundColor: background,
    colorScheme: base.colorScheme.copyWith(surface: background, onSurface: ink),
  );
}
