# 0002 — Deterministic Knuth–Plass typesetting engine in the core

- **Status:** accepted (2026-08-22)

## Context

Requirements: TeX-quality line breaking; one column on phones and two or
more on tablet/desktop **with the same words per line everywhere**, so the
reader builds a stable visual memory; endless scrolling; synchronized
side-by-side views of versified assets.

Platform text stacks (UIKit, Android, Pango, DirectWrite) break lines
greedily and each differently; none can guarantee identical breaks across
devices.

## Decision

- Line breaking and paragraph layout are computed in `gramma-core` by our
  own implementation of the **Knuth–Plass optimal-fit algorithm**, over
  runs shaped with **rustybuzz** (HarfBuzz port), segmented with **icu4x**,
  and hyphenated with TeX (Knuth–Liang) patterns via the `hyphenation`
  crate — German patterns are first-class, as German compounds make
  hyphenation essential for good measure.
- Layout is computed against a **canonical measure** (em-based line
  width). Columns are instances of that same measure; devices differ in
  column count and scale, never in line breaks.
- The engine outputs positioned glyph runs; the Flutter layer only paints.
- Assets are addressed by canonical verse reference **per versification
  scheme**, with mapping tables between schemes (cf. CrossWire av11n),
  so side-by-side scroll synchronization works across traditions
  (e.g. Luther vs. KJV numbering).

## Consequences

- Typesetting is a pure function → golden-file and property-based tests.
- We take on font shaping/rendering responsibility ourselves (bundled
  fonts, not system fonts, for determinism).
- Versification mapping is in the content model from day one rather than
  retrofitted.
