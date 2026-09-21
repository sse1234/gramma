# 30. One repository, layered crates

Date: 2026-09-21

## Status

Accepted — the Rust split is done; the Flutter split follows file by
file.

## Context

A month of feature work (document import, rich typesetting, chrome
layout, store tooling) has grown the project to some 10,000 lines of
Rust in one crate and 10,000 lines of Dart in one package, with two
Dart files near 1,500 lines each. The question came up whether several
repositories would keep the parts apart better.

Observations from the history that shaped this decision:

- Nearly every feature touched the Rust core, the bridge crate, the
  Flutter app, and an ADR in one commit. The bridge is generated from
  the Rust API, so the two sides are one unit in practice.
- One tag drives every release: App Store, Play, and the GitHub release
  workflow. Several repositories would mean several tags and a
  compatibility matrix.
- The ADRs are the project's memory and work because the decision and
  the code sit together.
- The one split made so far, bibelsuche, has its own lifecycle and its
  own consumers — the conditions under which a separate repository
  pays for itself.

## Decision

**One repository.** A part leaves it only when a second consumer
exists — a project that wants the typesetter or the importer without
the app. Until then, a repository split would add release plumbing and
remove the one-commit atomicity the work depends on.

**Layered crates inside it.** The former `gramma-core` becomes a
workspace of crates with a fixed dependency direction, bottom up:

| Crate | Holds | May depend on |
|---|---|---|
| `gramma-reference` | the canon, aliases, reference parsing and scanning | — |
| `gramma-osis` | OSIS XML and SWORD module readers | reference |
| `gramma-document` | the document model, PDF/EPUB readers, inference, interpretation (ADR 0029) | reference, osis |
| `gramma-typeset` | Knuth–Plass breaking, shaping, block layout (ADR 0002) | reference, document |
| `gramma-library` | the content library in SQLite, lexical search (ADR 0003, 0022) | reference, osis, document |
| `gramma-user` | the user store and op-log sync (ADR 0003, 0014) | — |
| `gramma-core` | a facade re-exporting the crates under their old module names | all |

Cargo enforces the direction: a crate cannot reach a layer above it
without declaring the dependency, and a cycle fails the build. Each
crate carries its own tests and fixtures, so `cargo test -p
gramma-typeset` exercises the typesetter alone. The facade keeps every
existing path (`gramma_core::typeset::…`) valid for the bridge and the
examples, and is the one crate the bridge depends on. External
dependency versions are declared once in the workspace manifest.

**The same rule for the Flutter package**, applied file by file rather
than as a second package: the reader pane splits by responsibility
(column plan and scroll anchoring, keyboard and focus, selection and
popups) and the reader screen by model (desks, pane tree, import
flows), each behind a narrow interface, with the widget tests as the
safety net. A Dart package boundary is introduced only where a
dependency direction needs enforcing that the file layout cannot.

## Consequences

- A new content source is a module in `gramma-osis` or a reader in
  `gramma-document`; a new storage feature is confined to
  `gramma-library`; none of them can reach into the typesetter by
  accident.
- Publishing `gramma-typeset` or `gramma-document` to crates.io later
  is a manifest change, not a restructuring; extracting a repository is
  a `git subtree split` of one directory.
- The facade is a thin indirection the bridge pays for in one extra
  crate name; if it ever proves confusing, the bridge can depend on the
  layer crates directly.
- Build times improve for inner-loop work: a change in the typesetter
  no longer recompiles the library or the readers.
