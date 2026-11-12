# 37. A scroll is drawing only

Date: 2026-11-12

## Status

Accepted. Changes how the user store of ADR 0003 commits and when the
desk of ADR 0008 persists a reading position; the op-log of ADR 0014
is untouched.

## Context

Scrolling the vertical reader was choppy on a recent mid-range Android
phone and smooth on every Apple device. The renderer was the first
suspect and the wrong one. Counting what a scroll does found two kinds
of work that are not drawing, both triggered by the reading position
moving from one verse to the next — several times a second:

- **Every visible chapter was painted again.** The pane rebuilds to
  show the new position; the list of resolved marks handed to each
  chapter's painter was built anew on every rebuild, and the painter
  repaints when its marks are a different list. Whatever else repainted
  inside a list item (the heading, a layout pass) recorded the
  chapter's thousand-odd runs again as well.
- **The desk was written to the user store, twice** (the range's start
  and its end), synchronously on the UI thread. One synced write was
  four commits, and a commit in SQLite's default mode waits for the
  medium. Apple's storage answers that wait in a millisecond because
  it does not truly flush; Android's flash flushes, at ten to fifty
  milliseconds a commit. Every verse scrolled past cost several
  frames.

A test bible scrolled by 1440 px in 120 frames painted chapters 127
times and wrote the desk 45 times.

## Decision

**A scroll moves what is painted and writes nothing.**

- Resolved marks are kept per chapter until the annotations, the pens,
  or the chapter's layout change, so a rebuild for any other reason
  hands the painter the list it already has. The chapter's text is its
  own repaint layer, so repaints around it do not reach it.
- A text view's position no longer rebuilds the desk unless another
  pane follows that view. The other pane kinds, which are handed their
  anchor by the desk, rebuild as before.
- A moved reading position is written once it has rested for half a
  second, when the app leaves the foreground, when the desk is
  switched or closed, and with every other save of the desk.
- The user store runs in write-ahead mode with NORMAL synchronization,
  and a synced write — value, clock, stamp — is one transaction.

## Consequences

- A commit no longer waits for the medium. The store stays consistent
  through a crash or a power loss; what a power loss can take is the
  last moments' writes, and only those not yet checkpointed. A killed
  app loses nothing: the log is read on the next open. Synced values
  missing from the own op-log are re-appended by the self-heal of ADR
  0014, as before.
- The store has two sidecar files beside `user.db` (`-wal`, `-shm`).
  Anything that copies the store while the app runs must copy all
  three or go through SQLite.
- The reading position on disk lags the screen by up to half a second
  while the reader scrolls. Leaving the app writes it at once, so the
  place is kept across a system-ended background app.
- The scroll test counts chapter paints and desk saves and fails when
  a scroll causes either; the two counters are test-only.
- The multi-column reader repaints its columns when a page turn ends,
  not per frame, and is left as it is.
