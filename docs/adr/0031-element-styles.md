# 31. Element styles: presence is the reader's, breaks are the engine's

Date: 2026-09-25

## Status

Accepted.

## Context

Field use of an imported Bible text showed the chapter title with less
presence than the section titles beneath it, and the wish followed at
once: let the reader set how the text's elements look — book and chapter
headings, section headings, parallel-passage lines, verse numbers,
footnote markers. Until now their look was fixed in the painters, and
differed between the vertical and the column reader.

The constraint is ADR 0002: line breaks are computed once, at the
canonical measure, from the regular face's advances, and the reader's
visual memory rests on them never moving. Any style setting that changed
a glyph's advance would move breaks and break that promise.

## Decision

**Each element gets a style the reader may set**: extra stroke weight,
italic slant, and — for the chapter heading only — a size factor. The
chapter heading is a row of its own outside the line stream, so its size
is free; every other element sits inside typeset lines, so its size
stays what the engine measured. Weight comes by stroke over the regular
face, never by a bold cut (a real semibold has wider advances); italics
are a synthesized slant of the same advances. No setting can move a
line break.

**One resolver paints them.** The vertical and the column reader route
every run through the same style resolution, and the vertical reader's
chapter heading is painted like the column reader's heading row. The
defaults encode the intended hierarchy: chapter heading a quarter larger
and heaviest, section heading a shade heavier than text, parallel
passages and note markers in italics.

**Settings in parts.** The settings screen splits into tabs — Reading,
Appearance, Typesetting, Text styles, Sync, About — so each part stays
short on a phone and in the desktop dialog alike.

## Consequences

- Styles are local settings for now; when they join the synced profile
  (ADR 0004) they travel like the measure does.
- A new element (a book title row, a caption) is a new entry in the
  element enum with a default and, if it lives outside the line stream,
  a size factor; the painters need no new branches.
- The chapter heading's size cap (1.8× text) keeps it inside its row in
  the column reader.
