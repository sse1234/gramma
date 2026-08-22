# 0006 — Canonical line stream and adaptive columns

- **Status:** accepted (2026-08-22)
- **Builds on:** ADR 0002 (deterministic typesetting)

## Context

The vision requires one column on narrow viewports and as many columns as
fit on wide ones — with identical words per line everywhere, endless
scrolling, and live adaptation to window resizing. Naive approaches
re-layout text per viewport, which is slow and breaks the "stable visual
memory" requirement.

## Decision

- Because layout happens at the **canonical em measure** (ADR 0002), a
  chapter's line count is a viewport-independent constant. The module
  therefore has one **global line stream**: per chapter, a fixed number of
  heading lines followed by its text lines. Per-chapter line counts are
  computed once per module (sub-second for a full Bible) and give every
  line a global index.
- A **column is a window of N consecutive global lines**, where N is
  `floor(column_height / line_height)`. Column membership is arithmetic
  (`ColumnPlan`); no layout work depends on the viewport.
- **Constant zoom:** columns have a fixed width (the text-size setting);
  viewport width that is not an integer multiple becomes symmetric side
  padding. Type size never changes when columns are added or removed.
- When two or more columns fit, the reader scrolls **horizontally** through
  fixed-extent columns; otherwise it is a single vertical column. The
  **anchor line** (first visible global line) carries the reading position
  across resizes, re-chunking, and mode switches — and is the value that
  will be persisted and synced (ADR 0004).
- Rendering refines ADR 0002: the core emits **positioned text runs**
  (merged word fragments with x-offsets and shaped widths in font units);
  the Flutter layer paints each run with the bundled font at the column's
  pixel scale. Glue setting distributes line slack with the same shaped
  widths the painter uses, so justified lines end flush by construction.

## Consequences

- Window resizing costs arithmetic only — no re-shaping, no re-breaking.
- Side-by-side views become two panes, each with its own line stream and
  plan, synchronized by mapping anchors through verse references.
- Chapter headings can currently be orphaned at a column's last line;
  keep-with-next rules require variable column starts and are deferred.
- Painted text is invisible to the accessibility tree; every column/chapter
  exposes its text as a semantics label.
