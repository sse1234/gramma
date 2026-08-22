# 0007 — User settings and the protected measure

- **Status:** accepted (2026-08-22)
- **Builds on:** ADR 0002, ADR 0006

## Context

Reading settings must exist (text size, theme, contrast, line spacing),
but one "setting" is categorically different: the measure (line width in
ems) determines where every line breaks and thereby the reader's visual
memory of the text — the core promise of the app.

## Decision

- Settings are persisted locally (`shared_preferences`) and applied live:
  - **Text size** = the fixed column width in logical pixels (ADR 0006's
    constant zoom).
  - **Line spacing** = line height as a multiple of the font size; a pure
    vertical metric that never affects line breaks.
  - **Theme**: system/light/dark. **Contrast** interpolates ink and
    background between maximum contrast and soft, warm book tones; an
    additional dark-mode **true black** toggle pins the background at
    pure black and lets contrast dim only the text.
- The **measure is protected twice**: the UI requires a confirmation
  dialog that states the consequence in plain language, and
  `SettingsController.setMeasureEms` throws on any call not carrying an
  explicit confirmation flag — no other code path can change it silently.
  A confirmed change invalidates all line counts and layouts and
  re-anchors at the chapter being read.
- Bridge layout functions take the measure as a parameter; nothing in the
  Rust core holds measure state.

## Consequences

- Zoom, spacing, theme, and contrast changes are free (repaint or
  re-chunk only); measure changes cost a sub-second background re-count.
- When sync arrives (ADR 0004), the measure belongs in the *synced*
  profile: visual memory across devices holds only if all installations
  share one measure. The confirmation-gate design transfers — a synced
  change arrives as a confirmed decision made on another device.
