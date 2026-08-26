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
