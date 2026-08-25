#!/usr/bin/env python3
"""Converts the Bibelliga reading plan ("Gottes Wort entdecken — in 366
Tagen durch die Bibel") from its PDF into gramma's reading-plan JSON:
366 days, each a list of references with a display label and the OSIS
address of the reading's start.

Usage: pdftotext -layout Bibelleseplan-A4.pdf plan.txt
       python3 tools/bibelliga_from_pdf.py plan.txt > app/assets/plans/bibelliga.json
"""

import json
import re
import sys

BOOKS = {
    "1. Mose": "Gen", "2. Mose": "Exod", "3. Mose": "Lev",
    "4. Mose": "Num", "5. Mose": "Deut", "Josua": "Josh",
    "Richter": "Judg", "Rut": "Ruth", "Ruth": "Ruth",
    "1. Samuel": "1Sam", "2. Samuel": "2Sam",
    "1. Könige": "1Kgs", "2. Könige": "2Kgs",
    "1. Chronik": "1Chr", "2. Chronik": "2Chr",
    "1. Chronika": "1Chr", "2. Chronika": "2Chr",
    "Esra": "Ezra", "Nehemia": "Neh", "Ester": "Esth", "Esther": "Esth",
    "Hiob": "Job", "Ijob": "Job", "Psalm": "Ps", "Psalmen": "Ps",
    "Sprüche": "Prov", "Prediger": "Eccl",
    "Hohelied": "Song", "Hoheslied": "Song",
    "Jesaja": "Isa", "Jeremia": "Jer", "Klagelieder": "Lam",
    "Hesekiel": "Ezek", "Ezechiel": "Ezek", "Daniel": "Dan",
    "Hosea": "Hos", "Joel": "Joel", "Amos": "Amos", "Obadja": "Obad",
    "Jona": "Jonah", "Micha": "Mic", "Nahum": "Nah", "Habakuk": "Hab",
    "Zefanja": "Zeph", "Zephanja": "Zeph", "Haggai": "Hag",
    "Sacharja": "Zech", "Maleachi": "Mal",
    "Matthäus": "Matt", "Markus": "Mark", "Lukas": "Luke",
    "Johannes": "John", "Apostelgeschichte": "Acts", "Römer": "Rom",
    "1. Korinther": "1Cor", "2. Korinther": "2Cor", "Galater": "Gal",
    "Epheser": "Eph", "Philipper": "Phil", "Kolosser": "Col",
    "1. Thessalonicher": "1Thess", "2. Thessalonicher": "2Thess",
    "1. Timotheus": "1Tim", "2. Timotheus": "2Tim", "Titus": "Titus",
    "Philemon": "Phlm", "Hebräer": "Heb", "Jakobus": "Jas",
    "1. Petrus": "1Pet", "2. Petrus": "2Pet",
    "1. Johannes": "1John", "2. Johannes": "2John",
    "3. Johannes": "3John", "Judas": "Jude", "Offenbarung": "Rev",
}

BOOKS["Habakkuk"] = "Hab"
# The PDF sometimes drops the space in numbered books ("1.Petrus").
for name in list(BOOKS):
    if re.match(r"\d\. ", name):
        BOOKS[name.replace(". ", ".", 1)] = BOOKS[name]

# Longest names first, so "1. Johannes" wins over "Johannes". No leading
# word boundary: the layout sometimes glues the day number to the book
# ("155Josua").
BOOK_ALT = "|".join(
    re.escape(name) for name in sorted(BOOKS, key=len, reverse=True)
)
# A reference: book, optional chapter, optional ",verse", optional range.
# A chapter belongs to its book only across one or two spaces — a larger
# gap means the next number is the neighboring column's day number, and
# the book stands chapterless (whole short books: Obadja, Haggai …).
REF = re.compile(
    rf"({BOOK_ALT})(?:[ ]{{1,2}}(\d+)\s*(?:,\s*(\d+))?"
    rf"(?:\s*-\s*(\d+)\s*(?:,\s*(\d+))?)?)?"
)


def parse_ref(match):
    book, ch, verse, r1, r2 = match.groups()
    if ch is None:
        return {"label": book, "osis": f"{BOOKS[book]}.1"}
    osis = f"{BOOKS[book]}.{ch}" + (f".{verse}" if verse else "")
    label = f"{book} {ch}"
    if verse:
        label += f",{verse}"
    if r1:
        label += f"-{r1}"
        if r2:
            label += f",{r2}"
    return {"label": label, "osis": osis}


def main(path):
    text = open(path, encoding="utf-8").read()
    days = {}
    for line in text.splitlines():
        refs = list(REF.finditer(line))
        spans = [(m.start(), m.end()) for m in refs]

        def in_ref(pos):
            return any(s <= pos < e for s, e in spans)

        # A day number is an integer outside any reference whose next
        # token is the start of a reference; its entry runs to the next
        # day number.
        entries = []
        for m in re.finditer(r"\d{1,3}", line):
            if in_ref(m.start()):
                continue
            # Some rows lose the space after the day number entirely
            # ("155Josua 20-21"), so a zero-width gap counts too.
            gap = re.match(r"\s*", line[m.end():])
            if any(s == m.end() + gap.end() for s, _ in spans):
                entries.append((int(m.group(0)), m.start()))
        for i, (day, num_start) in enumerate(entries):
            end = entries[i + 1][1] if i + 1 < len(entries) else len(line)
            mine = [
                parsed
                for r in refs
                if num_start < r.start() < end
                and (parsed := parse_ref(r)) is not None
            ]
            if not 1 <= day <= 366 or len(mine) != 3:
                continue
            if day in days:
                raise SystemExit(f"day {day} appears twice")
            days[day] = mine
    missing = [d for d in range(1, 367) if d not in days]
    if missing:
        raise SystemExit(f"missing days: {missing}")
    plan = {
        "name": "Bibelliga",
        "source": "Gottes Wort entdecken — in 366 Tagen durch die Bibel",
        "days": [days[d] for d in range(1, 367)],
    }
    json.dump(plan, sys.stdout, ensure_ascii=False, separators=(",", ":"))


if __name__ == "__main__":
    main(sys.argv[1])
