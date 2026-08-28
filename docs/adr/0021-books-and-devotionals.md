# 21. General books and daily devotionals

Date: 2026-08-28

## Status

Accepted

## Context

Beyond Bible texts, commentaries, and lexica, the library wants general
books (sermons, treatises — reference: GerLutPredigten) and daily
devotionals (reference: SME, Spurgeon's Morning and Evening). The two
categories are "one and a half": a devotional is a general book whose
sections are addressed by the day of the year — and their SWORD
containers confirm it. General books are RawGenBook modules (a TreeKey:
node records with parent/sibling/child pointers and a payload into the
body file); devotionals are zLD modules — the dictionary container —
with `Feature=DailyDevotion`, OSIS entries, and `MM.DD` keys holding
morning/evening sections.

## Decision

- The clean-room reader gains the RawGenBook driver: the TreeKey
  flattens depth-first into reading order — ordinal, level, tree-key
  name, optional leading title, paragraphs. Kind "book", stored as
  ordered sections.
- The zLD driver accepts OSIS besides TEI: with `DailyDevotion` (or
  OSIS entries generally) each `section` div becomes one dictionary
  entry sorted `(month·100+day)·10 + index`, its title the headword.
  Kind "devotional" — reusing the dictionary storage and typeset
  layout wholesale; a day's readings are a sort-range query.
- The book view carries its own module and a section anchor ("s:12"),
  synced like a reading position: a table of contents (indented by
  level) jumps, arrows walk the reading order.
- The devotional view carries a day anchor ("d:0101"), defaulting to
  today; arrows walk the calendar (on the leap-year anchor, as reading
  plans do), a today button returns. The day's sections render stacked.
- Both render through `layout_prose` at Bible-text parity; references
  scan from the prose (German and English styles); long-pressed words
  look up in the dictionary. Import stays the one button.

## Consequences

- Validated against the real modules: GerLutPredigten (57 sections,
  all with text), SME (732 entries — 366 days × morning/evening).
- The kind taxonomy is now bible / commentary / dictionary /
  devotional / book; module lists filter by kind everywhere, so
  categories never leak into the wrong chooser.
- A lesson recorded in a test: `import_dictionary` once returned the
  right kind while storing 'dictionary' in the row — the assertion now
  checks the stored module list, which is what the app reads.
- Psalm-style canonical titles inside book bodies are excluded with
  structural titles; revisit if a book module relies on them.
- Secondary-literature annotation (the next arc) will meet these
  categories as ordinary prose panes — nothing here is special-cased
  against it.
