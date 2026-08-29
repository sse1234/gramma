# 0003 — SQLite, offline-first storage

- **Status:** accepted (2026-08-22)

## Context

Offline operation is the primary mode. Content arrives as imported modules
(initially OSIS from CrossWire); user data (notes, reading positions,
highlights) is small, personal, and must sync (ADR 0004).

## Decision

- **SQLite** embedded in `gramma-core` on all platforms.
- **Library database**: imported modules normalized to a verse-addressed
  content model (per versification scheme), plus asset storage for rich
  media (bitmaps, vector graphics). FTS5 provides lexical full-text search
  as a complement to semantic search.
- **User database**: notes, positions, highlights — kept separate from the
  library so sync and backup never touch content with licensing
  constraints.
- Import is a one-way pipeline: source format (OSIS now, others later) →
  normalized schema. Original source files are not required at runtime.

## Consequences

- Fully functional with zero network access.
- New content formats (e.g. a publisher's, pending permission) only require a new
  importer, not storage or rendering changes.
- Content licensing boundaries are respected structurally: user data and
  licensed content never share a database file.
