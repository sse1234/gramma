# Changelog

All notable changes to gramma. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions
are the app's `pubspec.yaml` version, tags are `v<version>`.

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
