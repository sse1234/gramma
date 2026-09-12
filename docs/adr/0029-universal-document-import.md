# 29. Universal document import: PDF and EPUB through one document model

Date: 2026-09-12

## Status

Accepted — first stage shipped (readers, inference, interpretation,
storage, import dialog); rich typesetting of lists, tables, figures,
and inline styles follows as the second stage.

## Context

Readers own study material far beyond SWORD modules: commentaries
and books as PDF, Bible editions as EPUB. Today gramma imports only
OSIS and SWORD (ADRs 0017, 0020, 0021), and its library stores entry
text as plain paragraphs, so even a rich source would arrive flat.

Five sample documents shaped this decision: two commentary PDFs (one
of 1088 pages), a general book PDF with tables, enumerations, and
figures, and two Bible EPUBs from different producers. Findings:

- The PDFs are publisher exports (InDesign, Word). Their text layer is
  clean, with reliable font roles: one body face and size, a bold or
  semibold face for headings, a smaller size for footnotes, a distinct
  face for running heads. Soft hyphens survive as U+00AD. None is
  tagged (no structure tree), so structure must be inferred from
  layout.
- Both EPUBs are unencrypted, XHTML with verse-number spans, chapter
  anchors, and CSS classes for small caps, italics, and notes. One
  even names its files by OSIS id.
- The commentaries carry ~2,500 explicit references ("Röm 8,23",
  "Gal 2,17-21") and ~1,900 context-dependent ones ("V. 15-16",
  "Kapitel 2") whose meaning depends on the surrounding section.
- A pure-Rust reader (`pdf` crate, MIT) extracts positioned text with
  font, size, and matrix-correct positions from all three PDFs. No
  C engine (pdfium: extra binaries per platform; MuPDF: AGPL) is
  needed.

## Decision

**One document model between every source and the library.** Every
importer produces a `Document`: a tree of blocks (heading, paragraph
with a style, list, table, figure, rule, chapter milestone) over
inlines (styled text, verse number, note reference, recognized
reference), plus notes and image assets. OSIS and SWORD keep their
current readers; PDF and EPUB feed the new model, and the model is
what interpretation, storage, and typesetting see.

**Structure is inferred, not guessed by a model.** PDF pages become
lines of positioned fragments; lines become blocks by layout rules:
the dominant font and size define body text; larger or bolder
standalone lines are headings ranked by size; running heads and page
numbers are recognized by position and repetition and dropped;
smaller text at the page foot introduced by a number is a footnote,
matched to raised numbers in the body; an indented first line or a
vertical gap opens a paragraph; a line-final soft hyphen joins the
next line; numbered or bulleted paragraphs form lists; consecutive
lines sharing cell positions form tables; images keep their place as
figures. The rules are deterministic and unit-tested against
synthetic fixtures; the publishers' consistency is what makes them
sufficient.

**Three document types, detected then confirmed.** A document is a
Bible text, a commentary, or a general book. Detection: verse-number
markers with chapter structure mean Bible; sections anchored to
passages of one book with dense verse references mean commentary;
otherwise book. The import dialog shows the detected type and lets
the user change it. Bible texts flow into the existing verse, heading,
and note tables so every reader feature works unchanged; commentaries
and books keep their block trees, stored beside the plain text the
existing views use, so old modules and new ones share one schema.

**References are resolved with context.** The reference scanner gains
a context stack: a book from the document title or a passage heading,
a chapter from the nearest chapter heading or scripture block, so
"V. 15" and "Kapitel 2" resolve like full references. Commentary
sections are anchored to OSIS ranges from their headings and quoted
scripture blocks, which is what lets an imported commentary follow the
Bible view.

**Rich formatting reaches the page.** The typesetting engine gains
inline styles (italic, bold, small caps, superscript), hanging indents
for lists, tables with per-column measures set cell by cell, and
figure slots. Paragraphs keep the Knuth–Plass setting; the new
primitives are layout around it, never a second engine.

**Rights are respected at the door.** Encrypted PDFs without a user
password and EPUBs with an encryption manifest beyond font obfuscation
are refused with a plain message; PDF permission flags that forbid
extraction are honored. The library is device-local (only annotations
sync, ADR 0014), so an imported document never leaves the device by
itself. The importer states that imports are for content the user has
the right to use; converting a lawfully obtained file for one's own
reading is private use, and the tool takes no position beyond that.

## Prototype findings (2026-09-12)

Against the five samples: both Bible EPUBs import complete (31,165 and
31,176 verses, every chapter, notes bound by marker or locator); the
Romans commentary yields 388 passage-anchored entries with 272 notes
and its references resolved; the 1088-page Treasury volume yields 425
verse-anchored entries after two-column pages are read column-wise;
the general book keeps 193 sections, its footnotes, 20 figures, and
its tables. Whole-file reads take 50–370 ms.

## Refinements (2026-09-12, after reading the imports)

Rules added once real pages were read; each is unit-tested:

- **Hyphens by advance.** Producers map both the printed hyphen and the
  unprinted discretionary hyphen to U+00AD; the glyph's advance tells
  them apart (printed → "-", zero-width → dropped). A zero-width space
  glyph inside a word is the same device and vanishes too. A line-final
  hyphen joins the next line, also across a page break, and a hyphen
  set as its own fragment at the margin stays glued to its word.
- **Word gaps by geometry only.** Kerning values in the text stream say
  nothing about words; only the distance between fragments does.
- **Columns per size class.** A page's columns are found for the whole
  page, else for the size class (small type, or the page's own dominant
  size under a heading) that forms them; a centered heading crossing
  the gutter does not hide it. Endnotes bind to their markers across
  pages; unmarked note lines return to the flow.
- **Enumerations inside prose.** "1) … 2) …" at a line start is a list
  item only where a paragraph could begin (short previous line, gap,
  indent, colon, or the next number of an open list); ordered lists
  restart at "1.".
- **Poetry.** A run of single short lines is set line by line without
  blank lines between (a quoted psalm in a commentary).
- **Split titles.** Consecutive headings of one size are one heading
  ("Psalm" over "1"; a title page's lines).
- **Two-column apparatus.** Aligned cells wrapping over many rows are
  two columns of running text, read column-wise, not a table.
- **Verse anchoring in commentaries.** A paragraph opening with "V. 6."
  or a bold "6.", and a self-numbered list item, opens the entry for
  that verse; sections treating the same verse (exposition, notes,
  homiletics) merge into one entry.
- **Bible headings.** Short italic or bold paragraphs are section
  titles, lines made only of references are parallel-passage lines
  (level 2); a drop-cap chapter number opens verse 1.
- **Closed loop.** `tool/compare_extraction.py` compares gramma's words
  with a reference extractor's, so lost or invented words are counted
  per document rather than noticed by eye. After this round the three
  sample PDFs lose 0.6–1.4% of the reference's words, nearly all of
  them running heads dropped on purpose.
- **Book view.** A general book reads as one continuous column of
  sections, laid out as they scroll into view; the arrows and the
  table of contents scroll rather than swap.
- **Headings link.** References inside a Bible text's headings (the
  parallel-passage lines) are tappable and preview their passage.

## Consequences

- One reader per source, one inference pass, one storage shape: a new
  source (DOCX, Markdown) is a reader, nothing else.
- Layout heuristics have limits: multi-column PDFs, scanned pages
  without a text layer, and heavily designed books will import worse
  than publisher exports. The import dialog will say what it found
  (pages, headings, notes, references) so the user can judge.
- The block store adds a column to the section tables; existing
  modules keep NULL there and render as before.
- Public documentation, screenshots, and fixtures use public-domain
  or synthetic material only; the sample commentaries stay private
  (ADR 0002 stance on partner content).
- Images add weight to the library database; figures are stored at
  their embedded resolution, never upscaled, and a size cap per
  document keeps a picture book from swallowing the store.
