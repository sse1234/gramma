# 0010 — The 66-book Protestant canon, and nothing else

- **Status:** accepted (2026-08-24)

## Context

OSIS sources and SWORD modules may carry deuterocanonical books.
Supporting them would ripple through every layer: the canon table,
versification schemes, reference parsing, book selection, and content
alignment across modules.

## Decision

**gramma supports exactly the 66-book Protestant canon in every part of
the application, permanently.** Deuterocanonical books are silently
skipped at import (as the parser has done from the start) and never
appear in any model, index, selector, or view. This matches the same
standing decision in the bibelsuche search project.

## Consequences

- The canon table is a closed, fixed structure: book identity, category,
  and ordering can be derived from a book's index, forever.
- Importers need no configurability here; alignment between modules is
  always over the same 66 books.
