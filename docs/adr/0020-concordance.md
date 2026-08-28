# 20. The concordance: derived, not imported

Date: 2026-08-28

## Status

Accepted

## Context

The Strong's lexicon (ADR 0019) cites example passages per meaning but
is not a concordance — its lists end in "uva.". In the SWORD ecosystem
a true concordance is not a module at all: it is derived from a
Strong's-tagged Bible text. The CrossWire KJV (zText, GPL,
`Feature=StrongsNumbers`) tags every word:
`<w lemma="strong:G3439">only begotten</w>`.

## Decision

- The clean-room reader gains the zText driver: same container as zCom,
  but verse identity comes from the slot walk itself — book and chapter
  milestones occupy their own slots (verified against the KJV: chapter
  ends are embedded, never separate slots), and each following slot is
  the next verse. Non-canonical books stay skipped (ADR 0010). Word
  `lemma` attributes become word links: byte ranges of the normalized
  verse text with their Strong numbers; notes are captured, titles
  excluded. The real KJV imports as 31,102 verses with 367,280 word
  links, John 3:16 verified.
- The library stores word links indexed by (module, strong). The
  concordance is a query: every occurrence of a number, in canon order,
  with its verse text and covered range. The first tagged module is the
  concordance source.
- Tapping the Strong-number label of a dictionary entry — with the same
  halo mechanics as note markers — opens the concordance in the pane:
  occurrence rows with the linked words emphasized, each previewing its
  passage. The pane anchor "c:G26" carries the state, synced like any
  lookup.
- Long-pressing a word in a tagged text resolves it to its Strong
  number and opens the lexicon entry directly — matching is
  whole-word, case-folded, against the link's covered text, so a word
  inside a multi-word link ("beginning" in "In the beginning") still
  resolves. Untagged texts keep the gloss search (ADR 0019). Hebrew
  numbers fall back to search until a Hebrew lexicon is installed.
- The dictionary pane's arrows now navigate the pane's own lookup
  history — entries, searches, and concordances alike — instead of
  raw entry order (which the search field still reaches directly).

## Consequences

- "Words as objects" (ADR 0016) is complete in both directions: text →
  number → lexicon entry, and entry → number → every occurrence.
- Any tagged text in any language feeds the same concordance and
  resolution — validated against the KJV (367k links), Schlachter 1951
  (GerSch, 294k), and Luther 1912 (deu1912eb, 365k, public domain), so
  German-first reading gets native word-to-number resolution.
- The slot-walk identity assumption (milestones in their own slots) is
  validated per import by construction and against the real KJV; a
  module violating it would misalign and should be caught by the
  opt-in real-package test before being trusted.
- Multiple tagged texts: the alphabetically first is the concordance
  source; a chooser can come later if anyone installs several.
