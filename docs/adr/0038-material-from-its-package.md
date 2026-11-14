# 38. Flutter 3.50: Material comes from its package

Date: 2026-11-14

## Status

Accepted. Follows ADR 0001 (Flutter owns the UI) and ADR 0015
(localization).

## Context

Flutter 3.50 takes the Material and Cupertino libraries out of the
framework. `package:flutter/material.dart` is deprecated; the widgets
live on in the packages `material_ui` and `cupertino_ui`, versioned and
released on their own. The day 3.50 became the stable channel, CI
failed: it installed "stable", and the new analyzer reported the
import in every file. CI was pinned to 3.47.1 as a stopgap; this
record is the upgrade itself.

## Decision

gramma builds with **Flutter 3.50.0** and takes Material from
**`material_ui`** (1.11.0, with `cupertino_ui` 1.1.6).

- **Imports** were migrated by the package's own fix
  (`dart fix --apply --code=migrate_design_widgets`): 34 files, no
  hand edits.
- **Localization delegates are the package's.** The delegate list
  that `flutter gen-l10n` generates still names the framework's former
  Material and Cupertino delegates. The package's widgets do not look
  those up: with the generated list a German locale had no Material
  translations at all, and the first `AppBar` refused to build. The
  app now runs with its own list — `AppLocalizations.delegate` and
  `GlobalMaterialLocalizations.delegates` from the package
  (`grammaLocalizationsDelegates` in `l10n.dart`). The generated
  localization files are excluded from analysis: they are the tool's
  output, and its template is what still carries the deprecated names.
- **No compatibility bridge.** The package offers one for dependencies
  that still render widgets of the old library. None of ours does in
  our tree: the list package imports the old library without using
  its themed widgets, and the window package's caption widgets are not
  used.
- **Android toolchain** as 3.50 asks: Android Gradle Plugin 9.3.3,
  Kotlin 2.4.20, Gradle 9.5.0. 3.50 refuses AGP 9.1.0 outright and
  announces the end of support for the versions just above it.
- **The macOS renderer stays on Skia.** The Impeller crash during live
  window resizing (flutter/flutter#185394) is still open upstream, its
  fix under review; the pin in the macOS Info.plist is unchanged.
- **CI and the release workflow name the same version**, 3.50.0, and
  are changed together. A new stable release is an upgrade to make,
  with a record like this one.

## Consequences

- How the Material widgets look and behave now follows the package's
  releases, not the framework's. The version is held by the lock file;
  raising it is a deliberate step, and its changelog is the place to
  look when a control changes (1.11 widens the tab indicator, among
  other things).
- The reader's own drawing — typeset text, marks, columns — does not
  come from Material and is untouched; the layout tests pass
  unchanged.
- The bridge plugin (`rust_lib_gramma`, built by the vendored
  cargokit) does not support Swift Package Manager. Flutter 3.50
  builds it with a warning and announces that a future version will
  not. That is the next toolchain item.
- A build directory from 3.47 does not survive the switch: the
  precompiled Swift modules of the old engine have to go
  (`build/macos/Build/Intermediates.noindex`), or the macOS build
  fails on a modified header.
