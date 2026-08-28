# 22. Search: tiered consumption of bibelsuche, split by lifecycle

Date: 2026-08-28

## Status

Accepted

## Context

The bibelsuche sibling project has proven offline hybrid search
end-to-end: BM25 lexical + bge-m3 dense retrieval + cross-encoder
rerank, running on-device on iOS (CPU-only, enumerated-shape int8
CoreML, ~300 MB peak) after a hard-won memory investigation. Its
footprint (542 MB encoder, 543 MB reranker, ~70 MB per-translation
index, 1.3 GB app bundle) rules out bundling and rules out dense
search on decade-old hardware. The question was whether to merge the
projects.

## Decision

**Split by lifecycle, not by topic.** Bibelsuche remains a separate
repository: it is the artifact factory — Python research, GPU
training (ROCm/WSL2), CoreML conversion, benchmarks, model
experiments — a toolchain with its own cadence and dependencies.
Gramma owns the consumer runtime. The boundary between them is the
artifact format (ADR 0005), not a folder.

Search ships in tiers:

- **Tier 0 — lexical, every device, no artifacts.** A Rust parity
  port of bibelsuche's tokenizer (NFKD→ASCII fold, guarded suffix
  stripper, verbatim alias table) and Okapi BM25 (k1=1.5, b=0.75,
  same IDF), pinned in tests against scores computed by the Python
  reference. The index builds lazily from the module's own verses in
  the library — nothing to download, runs on the oldest tablet. The
  search tool lives in the Tools menu; hits jump the reading view.
- **Tier 1 — hybrid dense, capable devices, as an optional pack**
  (future work): per-translation f16 embedding index + the enumerated
  int8 query encoder, imported like modules, never bundled. Documents
  are pre-embedded, so devices only encode bucket-64 queries; dense
  scoring is a trivial f16 mat-vec Rust can do without BLAS. Platform
  encoder runtimes (CoreML channel on Apple, ONNX elsewhere) stay
  optional; absent a pack, the UI degrades to Tier 0 unchanged.
- **Tier 2 — reranker toggle** on top of Tier 1, desktop and recent
  phones, lazy-loaded.

**Labels ride our own sync.** Result rows carry a thumb (positive
label) and the list ends in a "no good hit" row (negative) — the
bibelsuche collection semantics, recorded as synced user-store keys
(`label/<timestamp>-<device>`, JSON values schema-compatible with
bibelsuche's `labels.jsonl`, plus a `tier` field). The op-log
(ADR 0014) carries them from every device; the training side reads
them from the sync folder's JSONL logs or via `user_keys("label/")` —
replacing bibelsuche's GitHub-PAT push for gramma-collected labels.

## Consequences

- Search finally occupies its reserved Tools-menu seat, on all
  platforms including the Tab S2, with one UI across all future tiers.
- Every device using gramma search now grows the training corpus that
  bibelsuche's blend tuning and path-2 distillation consume — and a
  distilled small encoder is the honest route to semantic search on
  low-spec devices, at which point Tier 1 packs revisit them.
- The BM25 implementation is the third parity port (Python, Swift,
  Rust); the pinned-score tests are the contract. Alias-table changes
  in bibelsuche must be mirrored deliberately.
- Index build cost is paid once per module per session (in-memory
  cache, invalidated on import); whole-Bible indexing is a subsecond
  affair in Rust.
- Tier 1 requires a pack-format specification (index blob + sidecar +
  encoder identity/version); that ADR comes with its implementation.
