# 34. The column gap is the reader's

Date: 2026-10-01

## Status

Accepted. Extends ADR 0032 (glyph size and line length) with a third
presentation setting; the column model of ADR 0006 stands.

## Context

The gap between text columns was a constant of 48 logical pixels,
whatever the type: three ems at the default 16 px, a bit over one em
at 40 px for low vision, nearly five at 10 px. A printed two-column
Bible sets its gutter in the body size — about 1.3 em in the pocket
edition read for ADR 0029 — and its outer margins wider than the
gutter. gramma's side margins are not a setting: whatever width is
left after the columns fit is split to both sides, and that stays so.
Neighboring pages are never rendered, so a side margin wider than the
gap costs nothing a reader would notice.

## Decision

- **Column gap** is a setting on the Reading tab beneath line length:
  one to four ems of the glyph size in half-em steps, default two. It
  is stored per device like the other presentation settings (ADR
  0032), and the controller snaps any value to the half-em grid.
- **The geometry derives the gutter** from it: glyph size times gap,
  scaled with the pane's text scale like the glyph size itself. The
  column count of a pane follows from the width, the column width and
  this gutter, so a wider gap can cost a column on a borderline pane.
- **Column views re-fit, nothing re-typesets.** The gap changes where
  columns stand, not how lines break, so the slider commits on every
  tick.
- **Desk snapping** uses the same gap: a pane divider released near a
  whole number of columns lands on the grid the reader set.
- **Side margins stay leftovers.** No minimum, no second setting.

## Consequences

- The default moves from 48 px to 32 px at 16 px type, closer to the
  printed page; a reader who liked the old look sets three ems.
- Column stride, snap physics and the column plan all take the gutter
  from the geometry; the one remaining 48 was the desk grid's and is
  gone.
- Existing installations read the default until they touch the slider.
