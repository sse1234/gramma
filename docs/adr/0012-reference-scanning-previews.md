# 0012 — Reference scanning, passage previews, and the default text

- **Status:** accepted (2026-08-24)
- **Builds on:** ADR 0008 (views), ADR 0011 (selector)

## Context

Footnotes and, later, secondary literature are full of verse references —
often context-dependent ("Kap. 7,11" means chapter 7 of the book at hand;
"[8,2]" chains from the previously mentioned book). Readers want to
glance into a reference before deciding to jump.

## Decision

- The core reference model gains a **prose scanner**: it finds full
  references ("1. Mose 49,25", "Joh 3,16-18", concise "Rö 8,1"),
  context references ("Kap. 7,11" against a context book), and bare
  chapter,verse pairs chained from the most recently mentioned book —
  returning byte ranges plus canonical references. It is deliberately
  conservative (word boundaries, comma-required bare pairs) to avoid
  false positives in prose.
- Notes cross the bridge with their scanned references; the footnotes
  view renders them as tappable spans opening a **passage preview
  popup**: the referenced verses with chapter context, target verses
  highlighted, resolved against the **default text** — a new setting
  naming the module used wherever no pane context applies. An "Open"
  action navigates the linked text view to the reference via one-shot
  navigation commands addressed by pane id.
- Text views emit their **visible range** (first and last visible
  position); the footnotes view shows exactly the notes visible in its
  followed view — chapter-exact everywhere, verse-trimmed at the range
  edges where layouts are loaded.
- Typed reference input is retired from the pane chrome; the selector
  (ADR 0011) and scanned references are the navigation surfaces, and the
  pane chrome collapses to a single row.

## Consequences

- Secondary literature and commentaries get reference linking for free —
  the scanner works on any prose with an optional context book.
- The preview popup is the template for the general floating-view layer.
