# 26. Typographic refinements: ragged dictionaries, kept headings

Date: 2026-08-29

## Status

Accepted

## Context

Field testing surfaced two typographic weaknesses. Dictionary panes
are narrow and their entries dense with special characters — full
justification stretches the few spaces per line into gaps without
buying the even color it exists for. And chapter headings could land
on the last rows of a column ("Jeremia 50" stranded at a column's
foot), separated from the text they announce.

## Decision

**Dictionary entries set ragged.** `layout_prose` takes a `justify`
flag. Off, the breaker still works the same Knuth–Plass measure, but
spaces may stretch freely into the right margin (TeX's
`\raggedright`) and every line sets at natural space width.
Dictionary entries switch off; commentaries, books, and devotionals
— long-form justified reading — stay as they are. The Bible text is
untouched.

**Headings keep their text.** The whole-module line pass reports each
line's kind (content, heading, blank), and the column plan uses it: a
heading group — consecutive heading rows, chapter title blocks
included, subheadings attached — landing at a column's foot with
fewer than **three content rows** beneath breaks the column early and
heads the next column instead. A group already at its column's top
stays (there is nowhere better). Columns thus become variable-length
windows over the canonical line stream; consumers ask the plan
instead of doing window arithmetic.

## Consequences

- The canonical line stream (ADR 0006) is unchanged — same words per
  line everywhere; only the chunking into columns adapts, and it
  stays deterministic for a given viewport height.
- A column that breaks early leaves blank rows at its foot; that
  whitespace is the feature, as in any well-set book.
- The keep-with-next constant (3) lives in one place in the column
  plan should taste evolve.
