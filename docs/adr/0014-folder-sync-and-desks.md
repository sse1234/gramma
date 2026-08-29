# 14. Sync through a user-provided folder; desks as synced objects

Date: 2026-08-25

## Status

Accepted

## Context

The vision (ADR 0001) requires offline-first operation with sync of
personal data — reading positions, desks, later notes — between the
user's own installations, without any gramma-operated server or account.
The user brings their own transport: a folder kept in sync by whatever
they already trust (iCloud Drive, Dropbox, Nextcloud, Syncthing, a USB
stick). gramma only reads and writes files inside that folder.

Synced folders are a hostile substrate for shared mutable files: no
atomic cross-device renames, partial uploads, and "conflicted copy"
duplicates whenever two devices write the same file. Any design that has
two devices write one file will eventually corrupt or fork it.

At the same time the desk concept (ADR 0008's layout object) is growing
into multiple desks the user can switch between. Both features shape the
same question: what is the unit of synced state?

## Decision

### One writer per file: per-device op-logs

Under `<folder>/gramma-sync/oplog/`, each installation appends only to
its own file, named by a stable random device id (`<device>.jsonl`). No
file is ever written by two devices, so provider-level write conflicts
cannot occur. Every line is one operation:

```json
{"k":"desk/3f2a…","v":"…layout json…","t":[1756100000000,0],"d":"9c41…"}
```

`k`/`v` are a key and its new value (the user store's kv pairs), `t` is
a hybrid logical clock (wall millis, counter), `d` the writing device.

### Merge: last-writer-wins per key

The synced state is the fold of all logs: for each key, the op with the
greatest `(t, d)` wins. HLC ordering makes this deterministic on every
device regardless of read order; the device id tiebreaks identical
stamps. Reading positions and desk layouts are single-user preferences,
not collaborative documents — LWW per key is semantically right, and
notes will sync as one key per note, where LWW is equally sound.

`sync_now()` pulls: it reads foreign logs, applies ops newer than the
locally applied stamp (tracked per key in `sync_state`), advances the
HLC past every stamp seen, and reports which keys changed so the UI can
react. Pushing is just appending — the provider uploads in its own time.

Resilience: a local write that cannot reach the folder (drive
unmounted) still lands in the local store; `sync_now()` self-heals by
re-appending any self-stamped key missing from the device's own log.
Logs are compacted (own file only: latest op per key) past a size
threshold. Malformed lines in foreign logs are skipped, never fatal.

### Desks are synced objects; the choice of desk is not

- `desks` — the registry: ordered list of `{id, name}`.
- `desk/<id>` — one layout object (ADR 0008) per desk.
- Which desk a device currently shows is **local** state (preferences),
  so different devices can sit on different desks while every desk's
  content flows everywhere. Continuing on another device means picking
  the same desk there and finding it exactly as it was left.

The legacy single `layout` key migrates on first run into a "Desk 1"
registry entry.

### Platform rollout

The engine is portable Rust; folder access is the per-platform part.

- **macOS / Linux / Windows**: any local path (cloud folders are plain
  directories there). The macOS app drops the App Sandbox (direct
  distribution; container data migrates on first launch). Sandboxing
  with security-scoped bookmarks can return before any App Store push.
- **Android**: paths writable by the app (v1: the app's external files
  directory, reachable by sync agents like Syncthing; Android 7 exposes
  it to other apps).
- **iOS/iPadOS** (follow-up): the app's own iCloud Drive container,
  which also appears as a plain folder on the Mac — bridging Apple
  devices via iCloud while the Mac's copy can be re-shared to Android
  by any folder-sync agent.

## Consequences

- No server, no account, no protocol lock-in: the sync state is plain
  files the user can inspect, back up, or delete per device.
- Frequent position updates append freely; compaction bounds file size.
  Providers see many small updates to one small file — their natural
  workload.
- LWW means simultaneous edits of the *same desk* on two devices keep
  only the newer arrangement. Acceptable for one person's desks; notes
  keep per-note granularity, and finer merging (per-pane keys) remains
  open behind the same wire format.
- The publisher-format constraint (ADR 0002) is untouched: only user data syncs,
  never module content.
