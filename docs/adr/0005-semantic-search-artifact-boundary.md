# 0005 — Semantic search integrates via build-time artifacts

- **Status:** accepted (2026-08-22)

## Context

Semantic search is developed independently in the **bibelsuche** project
(Python: sentence-transformers, hybrid BM25 + dense retrieval, currently
`bge-m3`-based with a distillation path planned). Its own mobile plan
already targets CoreML/ONNX artifacts for on-device inference — Python is
the research and build-time environment, not the runtime.

## Decision

- **bibelsuche remains the offline pipeline** (ingestion, chunking,
  embedding, benchmarking, model export). gramma never embeds Python.
- The contract between the projects is a versioned **artifact bundle**:
  exported encoder model (ONNX; CoreML variant where beneficial on Apple
  platforms), tokenizer definition, precomputed chunk embeddings, and
  chunk metadata keyed by OSIS reference — an evolution of bibelsuche's
  existing `manifest.json` + `verse_chunks.jsonl` / `passage_chunks.jsonl`
  + embedding-cache outputs.
- `gramma-core` exposes a **search-provider trait**; the semantic provider
  embeds an inference runtime (ONNX Runtime via the `ort` crate as the
  cross-platform default) and uses the HuggingFace `tokenizers` crate —
  which is itself Rust and the reference implementation — giving
  tokenizer parity with the Python pipeline by construction.
- Hybrid ranking (lexical via FTS5/BM25 + dense) follows bibelsuche's
  benchmarked configuration.

## Consequences

- Search quality work continues in Python with GPUs, on its own cadence;
  gramma consumes results by artifact version.
- Tokenizer-parity risk (the classic silent mobile regression) is
  addressed by sharing the same Rust tokenizer library, verified by a
  cross-project parity test on a held-out verse set.
- Until the first artifact bundle lands, gramma ships lexical search only
  (FTS5), behind the same provider trait.
