# 25. Reading plans are imported, not bundled

Date: 2026-08-29

## Status

Accepted (supersedes the asset-discovery mechanism described in ADR 0024)

## Context

ADR 0024 removed the original reading plan from the repository and left the
reading-plan feature dormant, discovering plans among bundled assets.
That made a plan a build-time artifact: using one privately meant
tweaking local builds, and no user could ever add a plan of their own.

## Decision

Plans become **imported content**, exactly like modules: a JSON file
in the established plan schema (`name`, optional `source`, `days` as
lists of `{label, osis}` readings) goes through the same import dialog
(`.json` joins the accepted types) and lands in the library's `plan`
table — validated in the Rust core, stored verbatim, keyed by name,
re-import replaces. The tools menu lists every imported plan by name;
discovery is a synchronous library query at startup, so the menu never
races an asset load. The bundled-asset mechanism is deleted.

## Consequences

- Anyone can write and share a plan file; gramma ships none until
  licensing questions (ADR 0024) are settled — and when
  permission arrives, the plan ships as a downloadable file or a
  first-run import, not as a build asset.
- Plans are per-device library content like modules, not synced
  op-log data; the plan's day is derived from the calendar, so two
  devices with the same plan agree without sync.
- The plan JSON schema is now a public interchange format; changes
  to it must stay backward-compatible.
