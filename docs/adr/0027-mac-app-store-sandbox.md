# 27. The Mac returns to the App Sandbox

Date: 2026-08-29

## Status

Accepted

## Context

The Mac App Store requires the App Sandbox; gramma had left it (a
note in the old Release entitlements promised its return "before an
App Store push"). The sandbox challenges exactly the features that
touch the file system by user intent: the folder-sync transport
(ADR 0004/0014) and module import.

## Decision

**Sandboxed everywhere, one build.** Release and debug carry
`app-sandbox`, `files.user-selected.read-write` (module import and
the sync-folder picker), `network.client` (the Dropbox transport),
and the iCloud container entitlements mirrored from iOS.

**Security-scoped bookmarks carry the sync-folder grant.** A
picker-chosen folder yields a bookmark (base64 in device-local
prefs — never the synced store), resolved at startup on a
`gramma/bookmarks` platform channel: access restarts, a moved folder
reconfigures sync, a stale bookmark refreshes. Access is held for
the app's lifetime — the sync engine works the folder throughout.

**The iCloud container resolves through FileManager** on both Apple
platforms (one shared `gramma/icloud` channel); composing the path
from `$HOME` dies under the sandbox. The container needs no
bookmark — its entitlement is the grant, so choosing it clears any
stored bookmark. Manually typed paths cannot receive a sandbox grant
and fail politely on the Mac; the picker is the way.

**Store declarations** ride along: `ITSAppUsesNonExemptEncryption`
false on both platforms (the op-log's end-to-end encryption uses
standard algorithms — exempt, self-classification duty noted) and
the `public.app-category.reference` category on the Mac.

## Consequences

- Existing unsandboxed installations start with a fresh container;
  desks, notes, and labels return over sync, modules by re-import
  (or a one-time manual copy into the container).
- The sandbox-to-unsandboxed migration helper from the earlier exit
  is deleted — dead in both directions now.
- Direct-distribution builds are sandboxed too: one behavior, one
  test surface; Syncthing-style folders just need one re-pick.
