# 33. Paragraphs travel with the text

Date: 2026-09-27

## Status

Accepted. Extends the verse model of ADR 0003 (storage), ADR 0004
(OSIS), ADR 0011 (SWORD) and ADR 0029 (document import); the
typesetter of ADR 0002 gains one more kind of break.

## Context

Printed Bibles structure their text with paragraphs: a verse opens a
new line where the editors saw a new thought, a psalm sets its verses
as lines, a narrative runs on for a page. gramma's verse model held
none of this. Every verse was a row of (book, chapter, verse, text),
the typesetter ran a chapter on as one justified paragraph broken only
by section headings, and an imported edition that set its verses with
care arrived as a wall of text.

The structure exists in every source gramma reads. OSIS has `<p>`
containers, `<lg>`/`<l>` line groups, and the `<milestone type="x-p"/>`
that SWORD modules such as the KJV set at a verse's start. A word
processor's file has one `text:p` per paragraph. A PDF's inference
(ADR 0029) sees a ragged line end followed by a verse number at the
head of the next line, and an EPUB has a `<p>` per paragraph — or, as
often, one per verse.

Verses, not paragraphs, remain the unit of everything else: anchors
of notes, annotations and sync, search hits, references, the column
plan. A paragraph model beside the verse table would touch all of it.

## Decision

**A verse knows whether it opens a paragraph.** One boolean travels
with the verse through every layer:

- **OSIS reader**: `<p>`, `<lg>`, `<l>` (as containers or `sID`
  milestones) and `<milestone type="x-p"/>` flag the verse they stand
  before, or the verse they stand inside when no text precedes them.
  A paragraph opening in the middle of a verse's text is one the model
  cannot hold: it is dropped, and it does not spill onto the next
  verse.
- **SWORD reader**: the same elements at the start of a verse's
  fragment (before any text, outside notes and editorial titles).
- **Document import**: a block's first verse opens a paragraph unless
  unnumbered text — a continuation of the previous verse — stands
  before it. A source that sets nearly every verse as its own
  paragraph (nine in ten of the verses that do not open a chapter,
  over at least twenty such verses) uses paragraphs as verse lines,
  not as structure: its flags say nothing and are dropped, and the
  verses run on as before. The Schlachter 2000 EPUB is such a source;
  the same text's pocket-edition PDF and the ODT of a private edition
  are not.
- **Library**: the verse table gains a `paragraph` column (default 0;
  older rows run on until their module is imported again). The
  chapter query hands it back with the text.
- **Typesetter**: `layout_verses` takes the list of paragraph-opening
  verses. The line before such a verse ends ragged and the verse
  starts the next line — no spacing line (that stays the heading's),
  no first-line indent. The verse number at the head of the line is
  the mark, as in the editions the structure comes from. Headings keep
  their own rule; a heading before a verse implies the break.
- **OSIS writer**: every chapter opens a `<p>`, every flagged verse a
  new one, and section titles stand between paragraphs, never inside
  one, so the file re-reads to the same flags. An export therefore
  carries the structure to anyone reading it, gramma or not.

Line breaks inside a verse (`<lb/>`, `text:line-break`, a poem's
half-lines) are not transported; they read as a space. The verse
model has no place for them, and the reader's column typesetting
(ADR 0006) would have to reflow them anyway.

## Consequences

- Imported and installed texts read with their editors' paragraphs.
  Where a translation sets psalms line by line, gramma does too.
- The column plan (ADR 0028) is unchanged: paragraph breaks add lines
  but no empty rows, and headings alone govern column boundaries.
- Two editions of one text may paragraph differently. Comparing the
  Schlachter 2000 pocket PDF with the ODT of the private edition, the
  ODT's paragraph openings are almost all among the PDF's (which sets
  more: poetry lines, and more section headings); the reverse holds
  only in narrative. Neither is wrong; each is its edition.
- Modules imported before this record show no paragraphs until they
  are imported again; the library migration adds the column without
  touching the rows.
- Sync (ADR 0005) is untouched: modules are not synced, and the flag
  lives in the module's own rows.
