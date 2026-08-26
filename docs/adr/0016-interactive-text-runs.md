# 16. Words as objects: the interactive text surface

Date: 2026-08-26

## Status

Accepted

## Context

The roadmap needs user notes/remarks and dictionaries/concordances
(Strong's). Both require that a word in the typeset text is not merely
painted but addressable: something the reader can touch and the app can
resolve. The layout engine has always known this — every `RunView`
carries its exact position, width, line, and verse — but no interaction
reached that knowledge.

## Decision

Hit-testing over the run geometry, kept deliberately pure: `runInLine` /
`runAtOffset` map a tap position through the painter's scale and line
height to the run under it, with a slop that widens small targets. The
functions know nothing about gestures or widgets, so they are unit-
tested against constructed lines, and both readers (vertical chapters
and horizontal columns) share them.

Taps on the painted text resolve first: a hit on an interactive run
consumes the tap; anything else falls through to the reading-mode
toggle, so the page keeps feeling like a page.

The first interactive runs are the inline note markers. Tapping one
opens the footnote in a popup right where the reader's eye is — an
alternative to (not a replacement of) the footnotes pane. References
inside the note navigate within the same popup: a passage page replaces
the note text, a back arrow returns, and an Open action jumps the
reading view (recorded in the desk history). The note-span rendering and
the passage list are shared between the pane, the floating preview, and
the popup.

## Consequences

- The word-as-object foundation is in place: dictionaries and word-level
  notes become "resolve the tapped run, look it up" — the geometry, hit
  paths, and popup patterns already exist.
- Interactivity lives entirely in the Flutter layer; the Rust engine
  stays a pure function from text to positioned runs (ADR 0005 spirit).
- Marker targets carry tap slop; on dense lines the nearest true box
  wins, so neighboring words stay tappable-correct.
- Reading-mode toggling now shares the tap surface with interactions;
  the fallthrough rule keeps its semantics exactly for non-interactive
  text.
