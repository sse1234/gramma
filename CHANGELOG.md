# Changelog

All notable changes to gramma. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions
are the app's `pubspec.yaml` version, tags are `v<version>`.

## [Unreleased]

### Added
- Column gap setting (ADR 0034): the space between text columns is the
  reader's, one to four ems of the text size in half-em steps, default
  two (was a fixed 48 px). Side margins stay as they were.

## [1.1.4] - 2026-09-27

### Added
- The PDF reader takes pocket-edition Bibles: pages with an offset
  origin, MacRoman fonts, ligatures, two narrow columns, letterspaced
  lines, bold verse numbers, lettered margin notes, and chapter numbers
  drawn rather than set (ADR 0029, refinements of 2026-09-27).
- `inspect_document --osis <file>` exports a Bible import as OSIS XML
  that gramma reads back, for sharing an import without the app.
- ODT import (ADR 0029): a word processor's own file read as written —
  outline headings, a "Buchtitel" paragraph style, "Verszahl" spans as
  verse numbers, inline styles, footnotes with their citation as label.
- Paragraphs travel with the text (ADR 0033): a verse that opens a
  paragraph in its source (OSIS `<p>`, `<lg>`, x-p milestones; SWORD
  modules; imported PDF, EPUB and ODT documents) starts a fresh line in
  the reader, and the OSIS export carries the structure as `<p>`.
  Sources that set every verse as its own paragraph run on as before.
  Texts imported earlier show paragraphs after a fresh import.

### Fixed
- PDF import: a running head sharing its line with the page number no
  longer slips through as a heading (two cells spanning the gutter are
  not a centered title; a digits-only cell marks the line as furniture).

## [1.1.3] - 2026-09-26

### Fixed
- Multi-column views no longer leave a stub column behind the reading
  position after a jump and a menu toggle: the lines before the anchor
  chunk backward from it, so every column is full and only the module's
  first column may be short.
- The single-column reader's chapter heading no longer overlaps the
  first line of text.

## [1.1.2] - 2026-09-26

### Changed
- Presentation is the reader's (ADR 0032): "Text size" is the glyph
  size and "Line length" the measure, shown as characters, both plain
  sliders on the Reading tab. The confirmation dialog and the lock on
  the line width are gone; the typeface dialog no longer warns. A pane
  narrower than one column keeps the text size and takes the widest
  line that fits. Existing installations keep their reading: the glyph
  size is derived once from the stored column width.

### Added
- Text styles (ADR 0031): the weight and slant of chapter and section
  headings, parallel-passage lines, verse numbers, and footnote markers,
  and the size of chapter headings, are settings; line breaks never
  move. The settings screen is split into tabs.
- A divider released near the middle splits the desk evenly, even when
  a text view then carries margins around its columns.

### Fixed
- Imported Bible texts: parallel-passage lines with verse lists or
  cross-chapter ranges ("Kol 2; 2Kor 11,1-4.13-15") are headings, not
  text glued to the previous verse, and their references are links;
  verse lists ("11,1-4.13-15") resolve as one reference.
- The vertical reader's chapter heading has the same presence as the
  column reader's.
- Footnote markers at a column's edge have a finger-sized target.
- The view drag handle is finger-sized on touch screens.
- Line spacing adjusts in steps of 0.05.

## [1.1.1] - 2026-09-19

### Added
- The line width goes down to 4 ems for very large type: lines still
  break and hyphenate instead of holding one word each; line spacing
  goes down to 1.0.

### Fixed
- The first arrow press after a click on a toolbar button pages instead
  of only moving the focus.
- A failed line count after a typeface change no longer leaves the view
  in a single column; it is retried.
- Toggling menus and pane headers keeps the line at the top left where
  it was instead of moving back into the text.

## [1.1.0] - 2026-09-12

### Fixed
- Linux: the app icon shows in launchers, task bars and window
  switchers. The icon set now ships in the standard sizes (16–512 px)
  and the tarball and AppImage carry it together with the desktop
  entry under `share/`; the window icon is also set directly for X11
  sessions.

### Added
- PDF and EPUB import (ADR 0029): Bible texts, commentaries, and
  general books read through one document model; structure inferred
  from layout (headings, paragraphs, lists, tables, footnotes,
  figures); the detected kind is confirmed in an import dialog;
  commentaries anchor to passages with references resolved in context.
  Imported entries set with their formatting: italics, bold, small
  caps, superscript note markers, hanging lists, tables, figures,
  quotations, and footnotes at the entry's end.
- Arch Linux: a `PKGBUILD` (package `gramma-bin`) is rendered for each
  release and attached to it; `makepkg -si` installs the release
  tarball with desktop integration.
- Book views read as one continuous column of sections; references in
  a Bible text's headings (parallel passages) preview their passage.
- Release notes per version for the stores; a closed-loop extraction
  check (`tool/compare_extraction.py`) for the PDF reader.
- Settings shows the app version, build number, and build time.

### Changed
- Menus and pane headers take their own space again (reverting the
  1.0.1 overlay): with them shown, the first lines of a column are no
  longer hidden. Toggling them reflows the text.

## [1.0.1] - 2026-09-05

### Changed
- Menus and pane headers float over the text: showing or hiding them
  no longer moves the reading position, also in multi-column layouts.
- Footnote markers run a–z through the chapter; tapping one lists the
  whole chapter's footnotes with the tapped one highlighted.
- Keyboard paging follows the view you last clicked, dragged, or
  scrolled in; the first arrow press pages immediately.
- Dictionary entries are set ragged-right.
- Headings keep at least three rows of text with them at column ends.

### Added
- Reading plans import from JSON files.
- Optional keep-screen-on while reading.
- Notes overview pane.
- Windows and Linux builds (x64 and ARM64) as GitHub release
  downloads.

### Fixed
- Footnote markers at the right column edge open the popup instead of
  scrolling.
- Follower views report their real visible range to footnotes views.
- Modules with untagged superscriptions import correctly.

## [1.0.0] - 2026-08-29

First release: iOS, iPadOS, macOS (App Store), Android.

[1.1.0]: https://github.com/sse1234/gramma/releases/tag/v1.1.0
[1.0.1]: https://github.com/sse1234/gramma/releases/tag/v1.0.1
