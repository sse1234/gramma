# 18. Typeset prose: the engine beyond the Bible text

Date: 2026-08-26

## Status

Accepted

## Context

Commentary entries (ADR 0017) first rendered as plain Flutter text with
per-view size scales, like footnotes and previews. But commentaries are
a different category of text: not glance material, but prose read in
long stints — it deserves the same Knuth–Plass treatment that defines
the reading views. Unlike the Bible text, commentary does not carry the
protected canonical measure (ADR 0007): there is no same-words-per-line
doctrine to protect for secondary literature.

## Decision

- `layout_prose` in the core: an entry = optional label (set at
  verse-number scale, bound unbreakably to what follows), optional
  level-1 heading directly above its body, and justified, hyphenated
  paragraphs separated by one blank line. Same items, same breaker,
  same glue setting, same escalation passes as `layout_verses`.
- Runs gain `link: Option<u32>`: a reference word carries the index of
  its entry's reference. This generalizes words-as-objects (ADR 0016) —
  interactivity is now a property a layout can assign to any run, and
  the pure hit-testing resolves it with zero new machinery. Dictionaries
  will attach lookups the same way.
- The commentary renders with the Bible text's exact properties minus
  the fixed measure: its glyph size is the reader's own em —
  min(pane width, column width) / measure — times the commentary scale
  (default 1.0 = pixel-identical twins), with the same line spacing
  setting, typeface, and weight stroke. Only the measure stays free: it
  reflows with the pane — deliberately unprotected. The same rule will
  apply to secondary literature later.
- A structural tiling change (new pane, drag into or out of a column,
  close) snaps all column boundaries to whole Bible-column multiples
  immediately — the same snap a divider release applies — so a fresh
  50 % split never sits off the grid.
- One painting path: `paintRun` with the per-brightness weight stroke,
  so commentary text carries the user's font weight exactly like the
  reader. References paint underlined in the accent color; labels use
  the verse-number style.
- Entry layouts are computed asynchronously per chapter and cached
  against a signature of module, typeface, text size, and pane width.

## Consequences

- The engine is no longer Bible-shaped: any verse-anchored prose
  (dictionary articles, user notes) can be typeset with one call — the
  view supplies label, heading, paragraphs, and link ranges.
- Painted prose exposes its text through semantics labels, like
  chapters; tests assert content there and tap references at positions
  recomputed from the deterministic layout.
- Commentary reflow is width-dependent by design. If the canonical
  measure doctrine (ADR 0007) is ever relaxed for the Bible text, this
  pane is the working precedent for how unprotected measures feel.
- The footnotes pane and previews stay plain text: they are short
  glance material, and their scales already serve them well.
