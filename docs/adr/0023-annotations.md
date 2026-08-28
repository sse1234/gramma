# 23. Annotations: selection, marks, and notes

Date: 2026-08-28

## Status

Accepted

## Context

The last pre-release feature: text markings and note taking. Notes in a
Bible study app always reference a verse or a passage; what makes or
breaks the feature is the interaction with the typeset text.

## Decision

**Selection paradigm** (Bible text views only; prose panes keep their
direct long-press dictionary lookup):

- A steady **long press** enters selection mode with the word under
  the finger selected.
- **Dragging in the same touch cycle** grows the selection live from
  the anchor to the word under the pointer; release finalizes.
- A finalized selection is never edited: **tapping anywhere exits**
  selection mode and the user starts over. Scrolling stays live —
  the only captured drag is inside the long-press cycle, which the
  gesture arena already owns.
- The **selection bar** sits at the bottom of the pane: the reference
  label, the dictionary action (single word only — the former direct
  long-press lookup, Strong's resolution included), the mark/note
  action, and close.

**Anchoring and rendering:** runs carry their byte offset within their
verse (an engine addition that also resolves ADR 0019's hyphenation
limitation — a split fragment knows its mid-word position). A mark
stores the canonical passage of one chapter, word-precision byte
offsets, the origin module, an HCL palette color index, and optional
note text. In the **origin module** it washes exactly the marked
words; in **every other translation** it washes the whole verses —
the note is canonical, the brushstroke is local. Washes paint as
rounded background spans behind the Knuth–Plass runs (consecutive
covered runs merge across their spaces); the typesetting itself is
never touched — no weight, no metrics.

**Interaction with existing marks:** tapping a marked word opens the
note popup (view, edit, recolor, delete). The popup offers eight
evenly spaced HCL washes tuned for text legibility in both themes;
saving with empty text keeps a pure color mark.

**Sync:** marks are `note/<id>` keys in the synced user store,
riding the ADR 0014 op-log like desks and labels; edits are LWW
rewrites, deletion is an empty-value tombstone.

**System highlights speak the same language:** passage previews and
concordance emphasis now use color washes instead of bold — added
font weight is no longer used as a highlight anywhere, completing
the intent noted back when the weight slider became the only source
of weight.

## Consequences

- The words-as-objects arc now covers its final noun: words are
  tappable (ADR 0016), linkable (0018), resolvable (0019/0020),
  searchable (0022) — and now writable-upon.
- Cross-chapter passages are deliberately out: a selection lives in
  one chapter (the osis schema supports ranges, lifting this later is
  cheap). A notes overview pane (list of all annotations, jumpable)
  is the designated follow-up arc.
- Word offsets are byte positions into the origin module's verse
  text; re-importing a revised text can shift them — the canonical
  verse reference keeps the annotation meaningful, the wash degrades
  to whole-verse at worst.
- Selection edges snap to painted runs; a hyphen-split word selected
  by its first fragment anchors at that fragment's true offset.
