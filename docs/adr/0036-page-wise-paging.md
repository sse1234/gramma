# 36. Paging by screens

Date: 2026-10-04

## Status

Accepted. Extends the column paging of ADR 0006 and ADR 0026.

## Context

A multi-column view pages one column at a time: an arrow key, a wheel
notch or a swipe moves every column one place to the left, and the
reader's eye has to find where it was. Readers used to turning pages
asked for the other behavior: all visible columns replaced at once,
like a page turn in a book.

## Decision

**A setting, "turn whole screens"**, on the Reading tab, off by
default. With it on, the step of a multi-column view is the screen: as
many columns as are visible, moved together. Arrow keys, wheel notches
and swipe snapping all use the screen as their unit; the snap physics
settle on screen boundaries.

**Pages are fixed groups of columns** counted from the module's start,
so a page is the same page whichever way the reader arrives at it. A
jump to a verse lands on the page that holds its column, and the
anchor line — what survives a re-chunk — is the first line of that
page's first column.

**Page Up and Page Down always turn screens**, in either mode; the
arrow keys follow the setting.

## Consequences

- The column scroller gains a unit (column or screen) and a page grid;
  the plan, the chunking and the column widths are untouched.
- A single-column view behaves the same in both modes.
- Toggling the setting re-aligns the open views to the page grid, so a
  view may shift by up to a screen's width minus one column.
