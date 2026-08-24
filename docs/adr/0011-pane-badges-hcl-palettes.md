# 0011 — Pane identity badges, HCL palettes, and the reference selector

- **Status:** accepted (2026-08-24)
- **Builds on:** ADR 0009 (grid), ADR 0010 (closed canon)

## Context

Panes are referenced in link selectors but had no visible identity.
Colors used for identification and categorization should come from a
principled system, not ad-hoc picks. Navigating to a passage needed a
visual path besides the typed reference field.

## Decision

- Every pane carries a **single-character badge** (1–9 then a–z; 35 panes
  is an accepted hard limit), assigned lowest-unused at creation and kept
  for the pane's lifetime, persisted in the layout object. The badge is
  rendered as a colored square leftmost in the pane chrome and beside
  every entry in link selectors.
- **Colors come from HCL (CIE LCh(uv))**, the Grammar-of-Graphics space
  behind ggplot2's discrete scales: hues at constant chroma and luminance
  are perceptually even, so no identity or category looks heavier than
  another. The implementation is validated against ggplot2's reference
  colors (`#F8766D`, `#00BFC4`, …). Badges use a golden-angle hue
  progression (stable per badge index); book categories use the eight
  evenly spaced ggplot hues, softened for tile backgrounds and adapted
  per theme brightness.
- The **reference selector** is the first popup workflow: a three-tier
  book → chapter → verse flow. The book grid is tinted by canon category
  (Law, OT history, wisdom, major/minor prophets, Gospels+Acts, epistles,
  Revelation — derived from canonical position, valid because the canon
  is closed per ADR 0010) and labeled with the most concise reference
  abbreviations (German scheme for German modules). Chapter and verse
  tiers are uncolored. It opens from the pane's position label and jumps
  verse-exact.

## Consequences

- Panes are addressable at a glance; future floating previews and
  keyboard navigation can reuse badge addressing.
- The HCL palette module is the single source for all future categorical
  color (highlight colors, diff views, sync devices).
