import 'dart:math';
import 'dart:ui';

/// Principled categorical color, after the Grammar of Graphics: hues spaced
/// in HCL (CIE LCh(uv)), the perceptually even polar form of CIELUV that
/// ggplot2's `scale_*_hue` uses — constant chroma and luminance, so no
/// category looks heavier than another.
Color hcl(double h, double c, double l) {
  final hRad = h * pi / 180;
  final u = c * cos(hRad);
  final v = c * sin(hRad);
  if (l <= 0) return const Color(0xFF000000);
  // LUV → XYZ, D65 white point.
  const refU = 0.1978398;
  const refV = 0.4683363;
  final y = l > 8 ? pow((l + 16) / 116, 3).toDouble() : l / 903.3;
  final u1 = u / (13 * l) + refU;
  final v1 = v / (13 * l) + refV;
  final x = y * 9 * u1 / (4 * v1);
  final z = y * (12 - 3 * u1 - 20 * v1) / (4 * v1);
  // XYZ → linear sRGB → gamma.
  double gamma(double t) =>
      t <= 0.0031308 ? 12.92 * t : 1.055 * pow(t, 1 / 2.4) - 0.055;
  double channel(double t) => (gamma(t).clamp(0.0, 1.0) * 255).roundToDouble();
  final r = 3.2404542 * x - 1.5371385 * y - 0.4985314 * z;
  final g = -0.9692660 * x + 1.8760108 * y + 0.0415560 * z;
  final b = 0.0556434 * x - 0.2040259 * y + 1.0572252 * z;
  return Color.fromARGB(
    255,
    channel(r).toInt(),
    channel(g).toInt(),
    channel(b).toInt(),
  );
}

/// ggplot2's default discrete palette: n hues evenly spaced from 15°,
/// chroma 100, luminance 65.
Color ggplotHue(int k, int n) => hcl(15 + k * 360 / n, 100, 65);

/// Badge color for a pane by its badge index: golden-angle hue progression
/// at ggplot chroma/luminance, so consecutive badges stay maximally
/// distinct however many exist.
Color paneBadgeColor(int index, Brightness brightness) {
  final h = (15 + index * 137.508) % 360;
  return brightness == Brightness.light ? hcl(h, 80, 55) : hcl(h, 70, 62);
}

/// Background tint for a book tile by canon category (0..8): the eight
/// ggplot hues, softened toward the paper for grid backgrounds.
Color bookCategoryColor(int category, Brightness brightness) {
  final h = 15 + (category % 8) * 45.0;
  return brightness == Brightness.light
      ? hcl(h, 42, 85)
      : hcl(h, 34, 32);
}
