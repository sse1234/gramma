# 17. Commentary modules and the commentary view

Date: 2026-08-26

## Status

Accepted

## Context

Commentaries are the first non-Bible content in the library, and a
stepping stone toward dictionaries and concordances: verse-addressed
prose that accompanies the text rather than being the text. The
Kingcomments (GerKingComments) ship as a SWORD zCom package — a publicly
documented CrossWire container format, so reading it is a clean-room
implementation of an open spec (unlike CLV, which stays untouched
without permission, ADR 0002).

A zCom module stores, per testament, a block index (`.bzs`), a verse
index (`.bzv`), and zlib-compressed blocks (`.bzz`). Verse slots follow
the module's versification; a pericope entry is *linked* by pointing the
slots of several consecutive verses at the same bytes. Every content
fragment in the wild carries an `annotateRef` naming its verse range,
and ranges never cross a chapter.

## Decision

- `gramma-core::sword` reads zCom packages by walking the verse index in
  order and de-duplicating slots — no canon table is needed, because each
  fragment's `annotateRef` names its own range. Fragments without one
  (book/chapter milestones, importer notes) are structural and skipped;
  so are non-canonical books, upholding ADR 0010 by construction.
- A commentary entry is a verse range of one chapter with an optional
  heading, normalized paragraphs (separated by `\n\n`), and explicit
  references taken from the OSIS `<reference osisRef>` markup — richer
  than the prose scanning footnotes rely on, same shape on the outside.
- The library gains a module `kind` ("bible" / "commentary") and
  `comment`/`comment_ref` tables. Commentaries never appear among the
  reading texts: text views, the default-text setting, and the position
  selector see Bible modules only.
- The commentary view (per ADR 0008) is a receiver: it follows a text
  view's reading position — but unlike the footnotes view it carries its
  own module, the commentary. The followed pane supplies position and
  chapter spine; the view shows the sections overlapping the visible
  verses. References use the shared note-span rendering and preview
  popup, so in-popup passage reading and Open-to-jump behave exactly as
  in footnotes and note markers (ADR 0016).
- The import button accepts SWORD zips alongside OSIS files and
  dispatches on the extension.

## Consequences

- One more content shape confirms the pane model: "receiver with own
  module" now exists, which dictionaries will reuse (follow a text view,
  resolve the tapped word against an own module).
- The zCom reader is validated against a synthetic in-repo fixture and,
  opt-in via `GRAMMA_SWORD_ZIP`, against real packages; module content
  is never committed to the repo (Kingcomments are free for
  non-commercial distribution but stay user-imported).
- Only zCom/ZIP/OSIS/UTF-8 modules are accepted; anything else fails
  with a clear "unsupported" error rather than a wrong import. Bible
  texts keep coming from OSIS only.
- KJV-versification commentaries align verse-exactly with our canon; a
  commentary in another versification would attach entries to slightly
  shifted verses. Acceptable until a mapping layer is warranted.
