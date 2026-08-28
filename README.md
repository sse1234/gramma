# gramma

*A multi-platform Bible study application.* (working title)

Free, open source, offline. No price tag, no paid modules, no accounts,
no analytics — and none of that will ever change.

## Vision

gramma aims to make reading and studying Scripture easy and enjoyable,
with typesetting quality in the tradition of Gutenberg and Knuth — not
merely "text on a screen".

### Core principles

- **Offline-first.** The app is fully functional without a network
  connection. Sync is an enhancement, never a requirement.
- **Your data stays yours.** Notes, marks, desks, and reading position
  sync between a user's own installations as end-to-end-encrypted
  files in a folder the user controls — no gramma server, no account,
  and nothing readable in transit.
- **Typesetting as a craft.** Line breaking builds on prior art
  (TeX / Knuth–Plass): our own engine with rustybuzz shaping, German
  and English hyphenation, and a protected measure. One column on
  phones, more on tablet and desktop — with the same words per line
  everywhere, so the reader builds a stable visual memory of the text.
  Layout is deterministic across platforms, verified by golden tests.
- **Words as objects.** Every typeset word is addressable: tappable,
  linkable, resolvable through Strong's numbers, searchable, and
  markable.

## What works today

- **Reader**: endless scrolling over whole modules, adaptive
  multi-column layout at constant zoom, synchronized side-by-side
  panes (text ↔ text, text ↔ commentary, …), footnotes, desks
  (saved workspace layouts), light/dark themes, English and German UI.
- **Content**: clean-room readers for SWORD modules — Bibles (zText),
  commentaries (zCom), dictionaries and daily devotionals (zLD),
  general books (RawGenBook) — plus direct OSIS import, all into a
  local SQLite library.
- **Study tools**: Strong's dictionaries with pane history,
  concordance built from Strong's-tagged Bibles, cross-reference and
  passage previews, lexical search (BM25 with German-aware token
  folding), daily devotional navigation.
- **Annotations**: word-precise color marks and notes anchored to
  verses and passages — exact words in the origin translation, whole
  verses in every other — synced over the user's own op-log.
- **Sync**: an end-to-end-encrypted operation log written as files
  into a folder the user provides and syncs by any means they like
  (iCloud Drive, Syncthing, Nextcloud, a USB stick) — no gramma
  server, no account.

Platforms exercised today: macOS, iOS/iPadOS, Android (a 2015 tablet
is a supported reality, not a footnote). Windows and Linux are on the
road to release.

## Content and licensing

The repository contains **code only** — no Bible texts, no publisher
content. Users import their own SWORD modules (e.g. from the
[CrossWire Bible Society](https://crosswire.org/)) or OSIS files;
module licenses are the modules' own. Content from CLV Verlag awaits
the publisher's permission before any support ships (see ADR 0002) —
the same ask-first stance applies to all third-party content.

- Code: [MIT](LICENSE)
- Bundled fonts (Literata, Gentium Plus, Gentium Book Plus):
  [SIL OFL 1.1](app/fonts/OFL.txt)
- Vendored build tooling (`app/rust_builder/cargokit`): MIT,
  Matej Knopp

All Rust and Dart dependencies are under permissive licenses
(MIT/Apache-2.0/BSD class); see ADR 0024 for the audit.

## Repository layout

```text
crates/gramma-core/   headless Rust domain core (all logic lives here)
app/                  Flutter application for all platforms
app/rust/             bridge crate exposing gramma-core via flutter_rust_bridge
docs/adr/             architecture decision records — the project's memory
tools/                fixture generators and asset pipelines
```

## Development

Quality and robustness come first: test-driven development, a
deterministic core testable without a UI, and an ADR for every
decision that shaped the design (see [docs/adr](docs/adr/)).

```bash
cargo test --workspace          # core + bridge tests
cargo build -p rust_lib_gramma  # bridge library, needed by Flutter host tests
cd app && flutter test          # widget tests (load the bridge library above)
cd app && flutter run           # run the app on a connected device/desktop

# import an OSIS file into a library database from the command line:
cargo run --release --example import_osis -- <library.db> <file.osis.xml>
```

After changing the bridge API in `app/rust/src/api/`, regenerate
bindings with `flutter_rust_bridge_codegen generate` (run inside
`app/`).

## Roadmap to release

Windows and Linux bring-up (x86 and arm), an annotations overview
pane, and tiered semantic search: today's lexical tier runs anywhere;
a dense-retrieval tier (on-device embeddings) follows for devices
that can carry it.
