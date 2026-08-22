#!/usr/bin/env python3
"""Convert a SWORD Bible module to an OSIS XML file gramma can import.

CrossWire distributes modules in the compiled zText format; this tool uses
pysword to extract each verse's raw OSIS fragment (footnotes and markup
included) and wraps them in a container-style OSIS document.

Usage: sword_to_osis.py <module-root> <module-name> <output.osis.xml>
  <module-root> is a directory containing mods.d/ and modules/ (an
  unzipped CrossWire rawzip package).

Requires: pip install pysword
"""

import re
import sys
from xml.sax.saxutils import escape

from pysword.modules import SwordModules

AMP = re.compile(r"&(?!amp;|lt;|gt;|quot;|apos;|#)")


def main() -> None:
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    root, name, out_path = sys.argv[1:]
    modules = SwordModules(root)
    conf = modules.parse_modules()[name]
    bible = modules.get_bible_from_module(name)
    structure = bible.get_structure()
    title = conf.get("description", name)
    lang = conf.get("lang", "de")

    with open(out_path, "w", encoding="utf-8") as out:
        out.write('<?xml version="1.0" encoding="UTF-8"?>\n')
        out.write(
            '<osis xmlns="http://www.bibletechnologies.net/2003/OSIS/'
            'namespace">\n'
        )
        out.write(f'  <osisText osisIDWork="{escape(name)}" xml:lang="{lang}">\n')
        out.write("    <header>\n")
        out.write(f'      <work osisWork="{escape(name)}">\n')
        out.write(f"        <title>{escape(title)}</title>\n")
        out.write("      </work>\n")
        out.write("    </header>\n")
        verses = 0
        for testament in ("ot", "nt"):
            for book in structure.get_books().get(testament, []):
                osis_id = book.osis_name
                out.write(f'    <div type="book" osisID="{osis_id}">\n')
                for chapter in range(1, book.num_chapters + 1):
                    out.write(
                        f'      <chapter osisID="{osis_id}.{chapter}">\n'
                    )
                    for verse in range(1, book.chapter_lengths[chapter - 1] + 1):
                        try:
                            raw = bible.get(
                                books=[book.name],
                                chapters=[chapter],
                                verses=[verse],
                                clean=False,
                            )
                        except Exception:
                            continue
                        raw = AMP.sub("&amp;", raw).strip()
                        if not raw:
                            continue
                        out.write(
                            f'        <verse osisID="{osis_id}.{chapter}.'
                            f'{verse}">{raw}</verse>\n'
                        )
                        verses += 1
                    out.write("      </chapter>\n")
                out.write("    </div>\n")
        out.write("  </osisText>\n</osis>\n")
    print(f"wrote {out_path}: {verses} verses")


if __name__ == "__main__":
    main()
