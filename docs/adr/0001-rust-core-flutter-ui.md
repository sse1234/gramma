# 0001 — Shared Rust core with a Flutter UI shell

- **Status:** accepted (2026-08-22)

## Context

gramma targets iOS/iPadOS, Android, macOS, Linux, and Windows. Two
requirements dominate the stack choice:

1. **Deterministic typesetting** — identical line breaks on every device
   (see ADR 0002) rules out platform-native text layout entirely.
2. **On-device semantic search** — inference artifacts (ONNX/CoreML) must
   be embedded in a compiled runtime (see ADR 0005).

Alternatives considered: Kotlin Multiplatform + Compose (JVM-based desktop,
younger iOS story), Tauri v2 (three different webview engines undermine
rendering determinism; mobile support young), fully native shells (4–5 UIs
to keep in parity).

## Decision

- All domain logic lives in a headless **Rust core** (`gramma-core`):
  content model, OSIS import, storage, sync, typesetting, search
  integration. UI-independent and fully testable without a UI.
- The UI is a single **Flutter** application for all five platforms.
  Flutter owns its rendering pipeline (Impeller/Skia), so glyph runs
  computed by the core paint identically everywhere; its sliver
  architecture serves the endless-scrolling requirement.
- The boundary is bridged with **flutter_rust_bridge**.

## Consequences

- Hard logic is developed TDD-style in pure Rust with no UI in the loop.
- Two languages (Rust + Dart) in the repo; the bridge boundary must stay
  narrow and well-defined.
- The app has its own typographic identity rather than platform-native
  look and feel — accepted, arguably desired, for a reading application.
