# 0009 — Tiled layout grid with resizable, snapping dividers

- **Status:** accepted (2026-08-24)
- **Extends:** ADR 0008 (layout objects)

## Context

The flat side-by-side row of views cannot express essential arrangements:
a phone in portrait wants footnotes *below* the text; a desktop wants
mixed stacks next to full-height columns. Users also need to adjust how
the viewport is divided — but under the constant-zoom model (ADR 0006/
0007), a view's width is only meaningful in whole multiples of the
typeset column width.

## Decision

- The layout object becomes a **grid: a row of columns, each a vertical
  stack of panes**, with float weights for column widths and pane heights.
  Version 2 of the serialized layout; v1 layouts migrate on load.
- **Position links refer to stable pane ids** instead of list indices, so
  structural edits (moving, stacking, closing panes) never re-target
  links. Ids are generated once and persisted.
- **Dividers are draggable.** Horizontal dividers (between stacked panes)
  resize freely. Vertical dividers (between columns) drag freely but
  **snap on release to whole column-width multiples** — the only widths
  at which resizing changes anything but margins.
- New footnotes views stack **below** their followed text view's column by
  default (the phone-portrait arrangement); new text views open a new
  column.
- Weights, structure, and links all live in the layout object (user
  store, later synced per ADR 0004). Window geometry stays per-device.

## Consequences

- Phone portrait (text above, footnotes below) and arbitrary desktop
  desks are the same model at different weights.
- Pane ids are the addressing scheme that floating/popup preview views
  (planned) will also use.
- Drag-to-rearrange (moving panes between columns) is a natural follow-up
  on the same model.
