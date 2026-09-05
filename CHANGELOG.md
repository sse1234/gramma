# Changelog

All notable changes to gramma. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions
are the app's `pubspec.yaml` version, tags are `v<version>`.

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

[1.0.1]: https://github.com/sse1234/gramma/releases/tag/v1.0.1
