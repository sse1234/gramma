# 32. Presentation is the reader's: glyph size and line length

Date: 2026-09-26

## Status

Accepted. Supersedes the protected measure of ADR 0007 and the
"same words per line everywhere" goal of ADR 0006; the canonical line
stream, the adaptive columns, and the typesetting engine of those
records stand.

## Context

ADR 0006 and 0007 built the reader around a stable visual memory of the
text: every line breaks in the same place on every device, so a reader
recognizes a page by its shape. Column width in pixels was the "text
size" setting, the measure in ems was protected behind a confirmation
dialog, and the glyph size fell out as column width divided by measure.

A month of use across a phone, a tablet, a laptop, and a desktop showed
that the memory does not form. A phone shows one column of a text the
desktop shows in three; the reader sees the same line breaks but never
the same page, and the little that repeats is not what memory holds
on to. Meanwhile the price was paid daily: the setting people want
first — how big the type is — was a by-product of two others, a phone
shrank the type whenever it shrank the column, and the measure's
confirmation dialog explained a promise nobody could feel.

## Decision

**Two settings, in the reader's own terms.**

- **Text size** is the glyph size in logical pixels. It never
  re-typesets: the engine lays out in ems, and a size change is a
  repaint at a new scale.
- **Line length** is the measure in ems, presented as an approximate
  character count. Changing it re-typesets in the background, as any
  measure change did, but from a plain slider that commits on release.
  No confirmation, no lock.

**Column width is derived**: line length times text size. A pane holds
as many such columns as fit, with the gutter between them, exactly as
ADR 0006 laid out.

**The fit rule for narrow panes.** When a pane is narrower than one
column, the text size holds and the line length gives way: the
effective measure becomes the widest whole number of ems that fits the
pane, never below the 4 em floor of ADR 0007's amendment. A phone thus
reads at the size the reader chose and the widest line it can hold; a
wide desk reads at the chosen line length in several columns. Every
pane computes its own effective measure from its width, and lays out
and counts lines at that measure — a pane re-measures when its width
crosses a column boundary, which on a phone happens on rotation and on
a desk when a divider moves.

**Settings are per device.** A phone and a desk want different glyph
sizes; nothing about presentation joins the synced profile.

**Migration.** An existing installation keeps its reading unchanged:
its glyph size is computed once from its stored column width and
measure, and its measure stays. New installations start at 16 px and
25 em, a 400 px column of about 52 characters.

**Prose views** (commentaries, books, dictionaries, devotionals) take
the glyph size times their own scale and, as before, reflow their
measure freely with the pane.

## Consequences

- The typesetting engine, hyphenation, the column plan, the origin
  re-chunk, the element styles — none of it changes. Only the source
  of the measure moves from a global setting to a per-pane derivation.
- Line breaks differ between panes of different widths. That is the
  guarantee given up, and nothing else depended on it.
- A re-measure costs a background line count, sub-second per module;
  it now also happens when a pane's width crosses a column boundary.
- The settings screen loses a dialog, a lock, and an explanation, and
  gains a sample line that shows the size being chosen.
