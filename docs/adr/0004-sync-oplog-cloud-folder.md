# 0004 — Sync via encrypted operation log in a user-provided folder

- **Status:** accepted (2026-08-22)

## Context

Sync exchanges notes, reading position, and similar personal data between
installations of the same user. Offline-first means devices are routinely
out of contact and must merge without conflicts. Running a server is
undesirable at this stage.

## Decision

- Every user-data change is recorded as an entry in a **mergeable,
  CRDT-style operation log** (deterministic merge; last-writer-wins with
  hybrid logical clocks where sufficient, e.g. reading position).
- Devices exchange **end-to-end-encrypted log segments as files** in a
  folder the user provides and syncs by any means they like (iCloud
  Drive, Syncthing, Nextcloud, Dropbox, a USB stick).
- The transport is behind a trait, so a self-hosted or managed sync
  server can be added later without touching the merge logic.

## Consequences

- No server to build, operate, or trust; the user controls their data.
- Sync latency is whatever the user's folder-sync provides — acceptable
  for notes and positions.
- Merge logic is a pure function over logs → highly testable (property
  tests: convergence, idempotence, commutativity).
