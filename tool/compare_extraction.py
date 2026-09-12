#!/usr/bin/env python3
"""Closed-loop check of the PDF reader (ADR 0029): compare the words gramma
extracts from a PDF with a reference extractor (PyMuPDF). Words the
reference sees but gramma does not point at lost text or wrong joins
("gesel len" for "gesellen"); words gramma invents point at false joins.

Usage: compare_extraction.py <file.pdf> <gramma-text-dump> [--show N]

The dump comes from `inspect_document --text <path>`. Needs pymupdf.
"""
import re
import sys
from collections import Counter

import pymupdf as fitz

WORD = re.compile(r"[\w\u00c0-\u024f\u1e00-\u1eff]+(?:[-\u2010][\w\u00c0-\u024f]+)*", re.UNICODE)


def words(text):
    return Counter(w for w in WORD.findall(text) if not w.isdigit() and len(w) > 2)


def reference_text(path):
    doc = fitz.open(path)
    parts = []
    for page in doc:
        # PyMuPDF renders soft hyphens as "-" at line ends; join them like a
        # reader would, and drop the ones inside words.
        t = page.get_text("text")
        t = re.sub(r"[\u00ad-]\n(?=[a-zäöüß])", "", t)
        t = t.replace("\u00ad", "")
        parts.append(t)
    return "\n".join(parts)


def main():
    pdf, dump = sys.argv[1], sys.argv[2]
    show = int(sys.argv[sys.argv.index("--show") + 1]) if "--show" in sys.argv else 25
    ref = words(reference_text(pdf))
    ours = words(open(dump, encoding="utf-8").read())
    missing = ref - ours
    extra = ours - ref
    ref_total = sum(ref.values())
    print(f"reference words: {ref_total}  gramma words: {sum(ours.values())}")
    print(f"missing in gramma: {sum(missing.values())} ({100*sum(missing.values())/max(ref_total,1):.2f}%)  "
          f"invented by gramma: {sum(extra.values())}")
    print("--- most frequent missing (reference has, gramma lacks)")
    for w, n in missing.most_common(show):
        print(f"  {n:5d}  {w}")
    print("--- most frequent invented (gramma has, reference lacks)")
    for w, n in extra.most_common(show):
        print(f"  {n:5d}  {w}")


if __name__ == "__main__":
    main()
