# 39. The library is the reader's to manage: delete and rename

Date: 2026-11-14

## Status

Accepted. Completes the import side of ADR 0003 (the library holds
content, the user store holds what the reader wrote) and ADR 0025
(plans are imported content).

## Context

Content came into the library and never left. A module could be
replaced by importing a file with the same code, but not removed, and
it kept whatever title its source carried — a long publisher's line as
often as a usable name. The first hurt most after import fixes: a text
imported by an older parser stays as it was read then, and the way to
the corrected text is to import it again, which wants the old one out
of the way first. A view also kept the text it had loaded: a module
imported over itself showed its old content until the app restarted.

## Decision

**A module can be deleted.** Deleting removes the module and
everything it brought — verses, notes, headings, entries, sections,
word links, images — from this device's library, in one transaction.
What the reader wrote — notes, markings, labels, desks — is not
library content and stays; it is bound to passages, not to the text
that showed them. A deleted text can be imported again at any time.
Reading plans are deleted the same way.

**A module can be renamed.** The name is the reader's and is kept
beside the module, not in it: the module's code remains its identity
for views, markings and re-imports, and the source's title is still
there underneath. Importing the same source again leaves the reader's
name standing. An empty name returns to the source's title; deleting
the module takes the name with it.

**The settings have a Library tab** listing every module and plan with
its kind and code, where both are done. Deleting asks first and says
what goes and what stays.

**The desk follows at once.** A change to the library's contents —
import, delete, rename — is announced; the desk reads its module lists
again, a view whose module is gone lets go of it (a text view takes
the next Bible text, the other kinds show their empty state), and
every text view loads its text anew. That also ends the stale view
after importing a text over itself.

## Consequences

- Names and deletions are per device, like the library itself: the
  library is not synced (ADR 0014), so a text renamed on the phone
  keeps its source title on the desktop.
- Freed pages stay in the library file for reuse; the file does not
  shrink when a large text is deleted.
- The search index of a deleted Bible text is dropped with the next
  search, like after an import.
- A desk on another device that names a deleted text falls back the
  way it always did for a text that is not installed.
