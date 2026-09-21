#!/usr/bin/env python3
"""Generate the SWORD zCom commentary test fixture (ADR 0017).

Writes app/test/fixtures/commentary.sword.zip: a minimal, self-authored
commentary module in the CrossWire zCom package layout, matching the books
of app/test/fixtures/reader.osis.xml. Deterministic output so the fixture
only changes when this script does.
"""

import struct
import zipfile
import zlib
from pathlib import Path

CONF = """\
[KomTest]
Description=Testkommentar
DataPath=./modules/comments/zcom/komtest/
ModDrv=zCom
SourceType=OSIS
Encoding=UTF-8
CompressType=ZIP
Versification=KJV
Lang=de
"""

FRAG_BOOK = '<div osisID="Gen" sID="k1" type="book"/>'
FRAG_CHAPTER = '<chapter osisID="Gen.1" sID="k2"/> '
FRAG_A = (
    '<div annotateRef="Gen.1.1-Gen.1.2" annotateType="commentary" sID="k3" type="section"/>'
    '<div sID="k4" type="x-p"/><title>Der Anfang</title><div eID="k4" type="x-p"/> '
    '<div sID="k5" type="x-p"/>Alles beginnt hier, '
    'vgl. <reference osisRef="Gen.3.1">Kap. 3,1</reference>.<div eID="k5" type="x-p"/>'
    '<div sID="k6" type="x-p"/>Zweiter Absatz der Auslegung.<div eID="k6" type="x-p"/>'
)
FRAG_B = (
    '<div annotateRef="Gen.1.3" annotateType="commentary" sID="k7" type="section"/>'
    '<div sID="k8" type="x-p"/>Licht wird.<div eID="k8" type="x-p"/>'
)


def main() -> None:
    block = (FRAG_BOOK + FRAG_CHAPTER + FRAG_A + FRAG_B).encode()
    compressed = zlib.compress(block, 6)

    bzs = struct.pack("<III", 0, len(compressed), len(block))

    def slot(off: int, size: int) -> bytes:
        return struct.pack("<IIH", 0, off, size)

    frags = [FRAG_BOOK, FRAG_CHAPTER, FRAG_A, FRAG_A, FRAG_B]  # verse 2 linked
    bzv = slot(0, 0)  # testament intro, empty
    for f in frags:
        bzv += slot(block.index(f.encode()), len(f.encode()))

    out = Path(__file__).resolve().parent.parent / "app/test/fixtures/commentary.sword.zip"
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        stamp = (2026, 1, 1, 0, 0, 0)

        def add(name: str, data: bytes) -> None:
            info = zipfile.ZipInfo(name, date_time=stamp)
            z.writestr(info, data)

        add("mods.d/komtest.conf", CONF.encode())
        add("modules/comments/zcom/komtest/ot.bzs", bzs)
        add("modules/comments/zcom/komtest/ot.bzv", bzv)
        add("modules/comments/zcom/komtest/ot.bzz", compressed)
    print(f"wrote {out}")


if __name__ == "__main__":
    main()


DICT_CONF = """\
[WbTest]
Description=Testlexikon
DataPath=./modules/lexdict/zld/wbtest/dict
ModDrv=zLD
SourceType=TEI
Encoding=UTF-8
CompressType=ZIP
Lang=de
"""

DICT_ENTRIES = [
    (
        "00001",
        '<entryFree n="00001"><orth>ἀγαθός</orth>'
        '<pron rend="italic">ag-ath-os\'</pron><lb/>'
        "<def>gut, brauchbar; vgl. 1. Mose 1,2</def></entryFree>",
    ),
    (
        "00002",
        '<entryFree n="00002"><orth>ἀγάπη</orth>'
        '<pron rend="italic">ag-ah\'-pay</pron><lb/>'
        "<def>I) d. Liebe<lb/>1) d. höchste Form d. Liebe.</def></entryFree>",
    ),
    (
        "00003",
        '<entryFree n="00003"><orth>οὐρανός</orth>'
        '<pron rend="italic">oo-ran-os\'</pron><lb/>'
        "<def>d. Himmel; d. sichtbare Himmelsgewölbe.</def></entryFree>",
    ),
]


def dictionary() -> None:
    def block(entries):
        header = struct.pack("<I", len(entries))
        body = b""
        base = 4 + len(entries) * 8
        pairs = b""
        for _, e in entries:
            raw = e.encode()
            pairs += struct.pack("<II", base + len(body), len(raw))
            body += raw
        return header[:4] + pairs + body

    blocks = [block(DICT_ENTRIES[:2]), block(DICT_ENTRIES[2:])]
    zdx = b""
    zdt = b""
    for b in blocks:
        compressed = zlib.compress(b, 6)
        zdx += struct.pack("<II", len(zdt), len(compressed))
        zdt += compressed
    idx = b""
    dat = b""
    placements = [("00001", 0, 0), ("00002", 0, 1), ("00003", 1, 0)]
    for key, block_no, entry_no in placements:
        idx += struct.pack("<II", len(dat), 15)
        dat += key.encode() + b"\r\n" + struct.pack("<II", block_no, entry_no)

    out = Path(__file__).resolve().parent.parent / "app/test/fixtures/dictionary.sword.zip"
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        stamp = (2026, 1, 1, 0, 0, 0)

        def add(name: str, data: bytes) -> None:
            info = zipfile.ZipInfo(name, date_time=stamp)
            z.writestr(info, data)

        add("mods.d/wbtest.conf", DICT_CONF.encode())
        add("modules/lexdict/zld/wbtest/dict.idx", idx)
        add("modules/lexdict/zld/wbtest/dict.dat", dat)
        add("modules/lexdict/zld/wbtest/dict.zdx", zdx)
        add("modules/lexdict/zld/wbtest/dict.zdt", zdt)
    print(f"wrote {out}")


dictionary()


BIBLE_CONF = """\
[KjvTest]
Description=Testbibel mit Strongs
DataPath=./modules/texts/ztext/kjvtest/
ModDrv=zText
SourceType=OSIS
Encoding=UTF-8
CompressType=ZIP
Versification=KJV
Lang=en
"""

BIBLE_SLOTS = [
    '<milestone type="x-importer" subType="x-osis2mod" n="test"/>',
    '<div canonical="true" sID="b1" subType="x-OT" type="bookGroup"/> '
    '<div canonical="true" osisID="Gen" sID="b2" type="book"/> '
    '<title type="main">GENESIS</title> ',
    '<chapter chapterTitle="CHAPTER 1." osisID="Gen.1" sID="c1"/> '
    '<title type="chapter">CHAPTER 1.</title> ',
    '<w lemma="strong:G1">In the beginning</w> '
    '<w lemma="strong:G3">heaven</w> appeared.',
    '<w lemma="strong:G2">Love</w> and <w lemma="strong:G3">heaven</w> abide.',
]


def bible() -> None:
    block = "".join(BIBLE_SLOTS).encode()
    compressed = zlib.compress(block, 6)
    bzs = struct.pack("<III", 0, len(compressed), len(block))
    bzv = struct.pack("<IIH", 0, 0, 0)  # testament intro, empty
    off = 0
    for s in BIBLE_SLOTS:
        raw = s.encode()
        bzv += struct.pack("<IIH", 0, off, len(raw))
        off += len(raw)

    out = Path(__file__).resolve().parent.parent / "app/test/fixtures/bible.sword.zip"
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        stamp = (2026, 1, 1, 0, 0, 0)

        def add(name: str, data: bytes) -> None:
            info = zipfile.ZipInfo(name, date_time=stamp)
            z.writestr(info, data)

        add("mods.d/kjvtest.conf", BIBLE_CONF.encode())
        add("modules/texts/ztext/kjvtest/ot.bzs", bzs)
        add("modules/texts/ztext/kjvtest/ot.bzv", bzv)
        add("modules/texts/ztext/kjvtest/ot.bzz", compressed)
    print(f"wrote {out}")


bible()


BOOK_CONF = """\
[BuchTest]
Description=Testbuch Predigten
DataPath=./modules/genbook/rawgenbook/buchtest/buchtest
ModDrv=RawGenBook
SourceType=OSIS
Encoding=UTF-8
Lang=de
"""


def genbook() -> None:
    bodies = [
        "<title>Teil 1</title><p>Einleitung des Teils.</p>",
        "<p>Erster Absatz der Predigt, vgl. 1. Mose 1,2.</p><p>Zweiter Absatz.</p>",
        "<p>Inhalt der zweiten Predigt.</p>",
    ]
    bdt = b""
    spans = []
    for b in bodies:
        raw = b.encode()
        spans.append((len(bdt), len(raw)))
        bdt += raw
    NONE = 0xFFFFFFFF
    nodes = [
        (NONE, NONE, 4, "", None),
        (0, NONE, 8, "Teil 1", spans[0]),
        (4, 12, NONE, "Erste Predigt", spans[1]),
        (4, NONE, NONE, "Zweite Predigt", spans[2]),
    ]
    idx = b""
    dat = b""
    for parent, nxt, child, name, payload in nodes:
        idx += struct.pack("<I", len(dat))
        dat += struct.pack("<III", parent, nxt, child)
        dat += name.encode() + b"\x00"
        off, size = payload if payload else (0, 0)
        dat += struct.pack("<HII", 8, off, size)

    out = Path(__file__).resolve().parent.parent / "app/test/fixtures/book.sword.zip"
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        stamp = (2026, 1, 1, 0, 0, 0)

        def add(name: str, data: bytes) -> None:
            z.writestr(zipfile.ZipInfo(name, date_time=stamp), data)

        add("mods.d/buchtest.conf", BOOK_CONF.encode())
        add("modules/genbook/rawgenbook/buchtest/buchtest.idx", idx)
        add("modules/genbook/rawgenbook/buchtest/buchtest.dat", dat)
        add("modules/genbook/rawgenbook/buchtest/buchtest.bdt", bdt)
    print(f"wrote {out}")


DEVOTIONAL_CONF = """\
[AndachtTest]
Description=Testandachten
DataPath=./modules/lexdict/zld/devotionals/andachttest/dict
ModDrv=zLD
SourceType=OSIS
Encoding=UTF-8
CompressType=ZIP
Feature=DailyDevotion
Lang=de
"""


def devotional() -> None:
    import calendar

    entries = []
    for month in range(1, 13):
        for day in range(1, calendar.monthrange(2024, month)[1] + 1):
            key = f"{month:02d}.{day:02d}"
            entries.append(
                (
                    key,
                    f'<div type="entry" osisID="{key}">'
                    f'<div type="section" osisID="{key}.am">'
                    f"<title>Morgen, {day}. im Monat {month}</title>"
                    f"<p>Andacht {key} zum Tag.</p></div></div>",
                )
            )

    def block(chunk):
        header = struct.pack("<I", len(chunk))
        pairs = b""
        body = b""
        base = 4 + len(chunk) * 8
        for _, e in chunk:
            raw = e.encode()
            pairs += struct.pack("<II", base + len(body), len(raw))
            body += raw
        return header + pairs + body

    zdx = b""
    zdt = b""
    placements = []
    for block_no in range(0, len(entries), 100):
        chunk = entries[block_no:block_no + 100]
        raw = block(chunk)
        compressed = zlib.compress(raw, 6)
        zdx += struct.pack("<II", len(zdt), len(compressed))
        zdt += compressed
        for i, (key, _) in enumerate(chunk):
            placements.append((key, block_no // 100, i))
    idx = b""
    dat = b""
    for key, block_no, entry_no in placements:
        idx += struct.pack("<II", len(dat), 15)
        dat += key.encode() + b"\r\n" + struct.pack("<II", block_no, entry_no)

    out = Path(__file__).resolve().parent.parent / "app/test/fixtures/devotional.sword.zip"
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        stamp = (2026, 1, 1, 0, 0, 0)

        def add(name: str, data: bytes) -> None:
            z.writestr(zipfile.ZipInfo(name, date_time=stamp), data)

        add("mods.d/andachttest.conf", DEVOTIONAL_CONF.encode())
        add("modules/lexdict/zld/devotionals/andachttest/dict.idx", idx)
        add("modules/lexdict/zld/devotionals/andachttest/dict.dat", dat)
        add("modules/lexdict/zld/devotionals/andachttest/dict.zdx", zdx)
        add("modules/lexdict/zld/devotionals/andachttest/dict.zdt", zdt)
    print(f"wrote {out}")


genbook()
devotional()
