# 15. Internationalization of the interface

Date: 2026-08-26

## Status

Accepted

## Context

The app's primary audience reads German Bibles, yet every interface
string was hardcoded English. Each new feature minted more of them, so
the cost of internationalizing grew with every commit. For a FOSS
release, contributors must also be able to add languages without
touching Dart code.

The distinction that matters: **content** (module texts, book names,
footnotes, the Bibelliga plan labels) already speaks the language of its
source and never goes through UI translation. Only the **chrome** —
menus, dialogs, tooltips, settings, snackbars — is internationalized.

## Decision

Flutter's standard `gen_l10n` pipeline: ARB resource files under
`app/lib/l10n/`, with English (`app_en.arb`) as the template locale and
German (`app_de.arb`) as the first translation. `flutter gen-l10n`
generates typed accessors; a `context.l10n` extension keeps call sites
short. Placeholders are typed, and counts use proper ICU plurals — no
`change(s)` hacks.

The app follows the system locale by default; a Language setting
(System / English / Deutsch) overrides it per device, which also lets
any user verify a translation without reconfiguring their OS.

Localized text can be *data* as well as labels: generated desk names
("Desk 1" / "Schreibtisch 1") are minted through the active locale at
creation time and then live unchanged in the synced registry — a name
is user data, not a label, so it never re-translates.

Out of scope, deliberately: Rust-side error strings (developer-facing,
they surface inside localized error templates), module content, and the
Reference display forms (German canon names are part of the reference
model, ADR 0010, not the chrome).

## Consequences

- New languages are one ARB file, no code changes; `flutter gen-l10n`
  and the analyzer catch missing or malformed entries.
- Tests run under the template locale (English); a dedicated test pins
  the German rendering and the override round-trip.
- Every future string must be born in the ARB files — the code review
  habit is now "no naked string literals in widgets".
- The English texts remain the semantic source of truth; German is a
  translation and may lag briefly during development.
