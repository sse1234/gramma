# 19. Dictionaries: the lexicon view and the word gesture

Date: 2026-08-28

## Status

Accepted

## Context

Dictionaries and concordances are the destination the words-as-objects
work (ADR 0016, 0018) has been building toward. The first asset is the
Griechisch-Deutsch Strong Lexikon (GerStrongsGreek), a SWORD zLD
package: a key index (`.idx`/`.dat`) mapping Strong's numbers to a
block and entry slot, and zlib blocks (`.zdx`/`.zdt`) holding TEI
`entryFree` fragments — headword (`orth`), transliteration (`pron`),
and a body whose verse references are plain prose in colon style
("Mt 24:12", chained "Apg 2:46 20:11", lists "Hld 2:4,5,7").

None of the user's Bible texts carry Strong's tags, so word-to-number
resolution is not yet possible; what is possible — and genuinely useful
— is the reverse: the entry bodies are German glosses, so searching a
German word finds its Greek candidates.

## Decision

- The clean-room SWORD reader (ADR 0017) gains the zLD driver and
  dispatches by `ModDrv`; the same import button handles both. Only
  ZIP/TEI/UTF-8 lexica are accepted.
- The library stores entries by numeric sort key with module kind
  "dictionary"; search ranks headword/transliteration/key hits before
  body hits and folds case in Rust (SQLite's LIKE folds only ASCII).
  Greek matching is exact-codepoint for now; diacritic folding is
  future work.
- The reference scanner accepts the colon chapter:verse style, and a
  bare pair hanging directly on a comma is never chained (it is a verse
  list of the previous reference). The lexicon's abbreviations resolve
  through the existing alias table.
- The dictionary view is the third receiver species: it carries its own
  module and a *lookup state* instead of a position link — the pane's
  anchor holds "G26" (an entry) or "q:Liebe" (a search), so the desk
  persists and syncs lookups like reading positions. Entries typeset
  through `layout_prose` at the Bible text's glyph size (ADR 0018
  parity); scanned references are tappable link runs previewing their
  passage; prev/next browse the lexicon in Strong order.
- The word gesture: **long-press a word** — in a text view, a
  commentary entry, or a dictionary entry itself — to search it in the
  desk's dictionary views; if none is open and a dictionary is
  installed, one is created. Tap stays the reading-mode toggle.
- Hit-boxes (refining ADR 0016): words resolve by their exact painted
  box; note markers get a halo of 1.5× their glyph box on every side,
  searched across neighboring lines with the nearest marker winning.

## Consequences

- The full "resolve the tapped run, look it up" pipeline exists
  end-to-end; when a Strong's-tagged Bible text is imported one day,
  word-to-number resolution can slot into the same gesture and pane.
- Hyphenation-split words long-press as their visible fragment (a run
  does not know its full word); acceptable, revisit if it bites.
- Strong's keys display as "G<number>"; non-numeric lexicon keys pass
  through unchanged, so other TEI lexica import today, just without
  the Strong's niceties.
- The pane-header link selector hides for views without a position
  link; the header chrome at marginal pane widths (~460–540 px) with
  every control visible can still overflow by a few pixels — tracked
  as separate polish.
