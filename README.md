# gramma

*A multi-platform Bible study application.* (working title)

## Vision

gramma aims to make reading and studying Scripture easy and enjoyable, with
typesetting quality in the tradition of Gutenberg and Knuth — not merely
"text on a screen".

### Target platforms

- iOS / iPadOS
- Android
- macOS
- Linux
- Windows

### Core principles

- **Offline-first.** The app is fully functional without a network
  connection. Sync is an enhancement, never a requirement.
- **Sync between a user's own installations** — notes, reading position,
  and similar personal data are exchanged between devices.
- **Typesetting as a craft.** Line breaking and page layout build on prior
  art (TeX / Knuth–Plass). One column on phones, two or more columns on
  tablet/desktop — but with the same words per line everywhere, so the
  reader can build up a stable visual memory of the text.
- **Endless scrolling** as the primary navigation mode.
- **Synchronized side-by-side views** of at least two versified assets
  (e.g. Bible text + commentary, or Bible text + a book with verse
  references) as a base requirement.
- **On-device semantic search** (planned; developed independently, to be
  integrated later).

### Content

- Initial format: **OSIS**, to import content provided by the CrossWire
  Bible Society.
- Later: content from CLV Verlag (pending permission from the publisher).
- Asset types beyond Bible text: commentaries, dictionaries, concordances
  (esp. Strong's), and books with verse references, including rich media
  (bitmaps, vector graphics).

## Engineering approach

Quality and robustness come first: test-driven development, deterministic
core logic that is testable without a UI, and recorded architecture
decisions (see [docs/adr](docs/adr/)).

## Status

Early — technology selection in progress.
