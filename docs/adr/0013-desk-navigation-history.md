# 0013 — Desk-global navigation history

- **Status:** accepted (2026-08-24)
- **Builds on:** ADR 0009 (grid), ADR 0012 (previews)

## Context

Deliberate jumps (selector picks, preview "Open") need browser-style
back/forward and a history list. Reading is a desk-wide activity: a jump
may happen in any pane, and returning means returning that pane.

## Decision

- The **history belongs to the layout object**: a desk-global list of
  (pane id, position) entries with a cursor, persisted and later synced
  with the desk. Multiple desks each carry their own history (postponed
  with multi-desk support).
- **Entries record deliberate navigation only** — selector jumps and
  preview opens — never scroll drift. Browser semantics: the departure
  position is pushed before the target, so Back returns exactly where
  the reader was, even if reached by scrolling; navigating after going
  back truncates the forward tail; entries of removed panes are pruned.
- Back/forward/history controls live in the chrome of **sender-capable
  panes** (any of them operates the same desk history); entries display
  as pane badge plus the concise reference form ("1Mo 3,1") provided by
  the core. Application of an entry reuses the one-shot pane command
  mechanism from ADR 0012.
- Panes announce their position unconditionally on their first layout
  tick, so the desk always knows a starting position before the first
  deliberate jump.

## Consequences

- History survives restarts with the desk and will travel with it.
- The 100-entry cap bounds the layout object's size.
