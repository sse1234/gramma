# 28. Chrome floats; footnotes letter through the chapter

Date: 2026-09-05

## Status

Accepted

## Context

Four observations from daily reading after the 1.0 launch:

- Toggling between reading mode and chrome moved the reading
  position, badly so in multi-column layouts: the chrome changed the
  content height, the column plan re-chunked, and the eye lost its
  place.
- The first arrow-key press after launch only focused the pane; the
  second one paged.
- Tapping a footnote marker showed that one note, though the page
  usually carries several.
- Footnote labels restarted at every verse, so the list needed
  chapter and verse to disambiguate ("9,24a") even when one letter
  would have done.

## Decision

**Chrome overlays the text.** The app bar and every text pane's
header float over the content in a Stack, exactly as the annotation
selection bar already did (ADR 0023). The content keeps its geometry
in both modes; the column plan never re-chunks on a toggle. The
lines under the floating chrome are covered while the chrome shows —
a deliberate trade, since chrome is the transient state and reading
the resting one.

**The first text view owns the keyboard.** It requests focus after
its first frame; a pane also takes focus on hover and on any pointer
down. One arrow press pages.

**Footnote letters run through the chapter** — a … z, then aa, ab —
never restarting at a verse or a heading, in the engine's inline
markers and the bridge's note rows alike. Lists show the letter alone
while it is unambiguous in the visible range; only when two visible
chapters' letters collide do chapter and verse join the letter.

**The footnote popup shows the page.** Tapping a marker opens every
footnote of the view's visible range, the tapped one highlighted and
scrolled into view; references inside notes still navigate within
the popup.

## Consequences

- Column geometry becomes independent of chrome state — a property
  tests can (and do) assert directly.
- A note's label is stable within its chapter, so a label identifies
  a note together with its verse; nothing persisted referenced the
  old per-verse letters.
- Overlaid chrome hides the top lines while shown; users who read
  with chrome permanently visible see slightly less text — the
  reading-mode default is the intended way to read.
