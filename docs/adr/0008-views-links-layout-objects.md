# 0008 — Views, position links, and layout objects

- **Status:** accepted (2026-08-22)
- **Builds on:** ADR 0003 (storage), ADR 0004 (sync), ADR 0006 (columns)

## Context

The base requirement of synchronized side-by-side reading generalizes:
Bible text next to a second translation, a commentary, its footnotes, a
dictionary, or a concordance. These differ in how reading position may
flow between them, and a user's arrangement of views is itself state
worth persisting and syncing between devices.

## Decision

- A **view** is an instance of (asset × presentation): a Bible text pane,
  a footnotes pane, later commentary/dictionary/concordance panes. Views
  share the viewport side by side; each text view keeps its own column
  machinery (ADR 0006) within its share.
- Views are connected by **position links**: a directed graph where the
  reading position (canonical book+chapter reference, verse-level later)
  flows from a followed view to its followers. Each view's role constrains
  the graph:
  - **Sender and receiver:** Bible texts, commentaries, versified
    secondary literature.
  - **Receiver only:** footnotes, dictionaries, concordances — they follow
    a text view and can never drive position.
  Mutual following of two text views is permitted; propagation suppresses
  re-emission while a remote position is being applied, so no feedback
  loops occur.
- Positions map between views by **canonical reference** (per ADR 0002's
  versification model), not by line numbers — different modules have
  different line streams.
- A **layout object** is the serializable description of the whole
  arrangement: the ordered list of views with their kind, loaded asset,
  link target, and reading position. It is versioned JSON, persisted in
  the **user store** (the user-data SQLite database of ADR 0003, separate
  from the content library) and later exchanged through the sync op-log
  (ADR 0004) so a reading desk can be resumed on another device.
- **Footnotes** become first-class content: the OSIS importer extracts
  `<note>` elements (previously discarded) into a notes table addressed by
  verse; a footnotes view shows the notes for the followed view's visible
  passage.

## Consequences

- The side-by-side base requirement is one configuration of a general
  mechanism; new view kinds are additive.
- The user store finally exists, giving notes/highlights and the op-log a
  home to grow into.
- Verse-level (rather than chapter-level) link granularity and inline
  footnote markers in the text are deliberate next refinements.
