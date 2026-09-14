//! EPUB reading (ADR 0029) against synthetic packages built in the test:
//! spine order, tag and class styling, verse numbers, notes, lists,
//! tables, figures, navigation stripping, and the DRM refusal.

use std::io::{Cursor, Write};

use gramma_core::document::epub;
use gramma_core::document::{Block, DocumentError, Inline, ParagraphStyle, Style, plain_text};
use zip::write::SimpleFileOptions;

fn epub_with(files: &[(&str, &[u8])]) -> Cursor<Vec<u8>> {
    let mut zip = zip::ZipWriter::new(Cursor::new(Vec::new()));
    let stored = SimpleFileOptions::default().compression_method(zip::CompressionMethod::Stored);
    zip.start_file("mimetype", stored).unwrap();
    zip.write_all(b"application/epub+zip").unwrap();
    zip.start_file("META-INF/container.xml", stored).unwrap();
    zip.write_all(
        br##"<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
<rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>"##,
    )
    .unwrap();
    for (name, data) in files {
        zip.start_file(*name, stored).unwrap();
        zip.write_all(data).unwrap();
    }
    let cursor = zip.finish().unwrap();
    Cursor::new(cursor.into_inner())
}

fn opf(spine: &[&str], extra_items: &str) -> String {
    let items: String = spine
        .iter()
        .map(|f| {
            format!(r##"<item id="{f}" href="Text/{f}" media-type="application/xhtml+xml"/>"##)
        })
        .collect();
    let refs: String = spine
        .iter()
        .map(|f| format!(r##"<itemref idref="{f}"/>"##))
        .collect();
    format!(
        r##"<?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="id">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>Probe</dc:title><dc:language>de</dc:language><dc:creator>Test Author</dc:creator></metadata>
<manifest>{items}<item id="css" href="Styles/s.css" media-type="text/css"/>{extra_items}</manifest>
<spine>{refs}</spine></package>"##
    )
}

fn xhtml(body: &str) -> String {
    format!(
        r##"<?xml version="1.0" encoding="utf-8"?><html xmlns="http://www.w3.org/1999/xhtml"><head><title>t</title><link href="../Styles/s.css" rel="stylesheet" type="text/css"/></head><body>{body}</body></html>"##
    )
}

const CSS: &str = r##"
/* producer stylesheet */
.kursiv { font-style: oblique; }
.sc { font-variant: small-caps; }
.verszahl { font-size: smaller; font-weight: bold; color: #8B0000; }
.hidden { display: none; }
p.bibelvers, .bibelvers { font-size: .8em; }
span.bsup { vertical-align: text-top; line-height: 0; font-size: .6em; }
"##;

#[test]
fn spine_order_headings_paragraphs_and_class_styles() {
    let a = xhtml(
        r##"<h2 id="g">Das erste Buch Mose (Genesis)</h2>
           <p class="textspalte"><span class="verszahl">1</span> Im Anfang schuf <span class="sc">Gott</span> die Himmel und   die Erde.</p>
           <p class="textspalte"><span class="verszahl">2</span> Die Erde aber war <span class="kursiv">wüst</span> und leer.</p>"##,
    );
    let b = xhtml(r##"<h3 class="hidden" id="c2">2</h3><p>Also ward vollendet.</p>"##);
    let source = epub_with(&[
        (
            "OEBPS/content.opf",
            opf(&["a.xhtml", "b.xhtml"], "").as_bytes(),
        ),
        ("OEBPS/Styles/s.css", CSS.as_bytes()),
        ("OEBPS/Text/a.xhtml", a.as_bytes()),
        ("OEBPS/Text/b.xhtml", b.as_bytes()),
    ]);
    let doc = epub::read(source).unwrap();
    assert_eq!(doc.title, "Probe");
    assert_eq!(doc.language, "de");
    assert_eq!(doc.authors, vec!["Test Author".to_string()]);
    assert_eq!(doc.blocks.len(), 5, "{:#?}", doc.blocks);
    assert!(
        matches!(&doc.blocks[0], Block::Heading { level: 2, inlines } if plain_text(inlines) == "Das erste Buch Mose (Genesis)")
    );
    let Block::Paragraph { style, inlines } = &doc.blocks[1] else {
        panic!("paragraph expected: {:?}", doc.blocks[1]);
    };
    assert_eq!(*style, ParagraphStyle::Body);
    assert_eq!(inlines[0], Inline::VerseNumber(1));
    assert_eq!(inlines[1], Inline::text("Im Anfang schuf "));
    assert_eq!(
        inlines[2],
        Inline::styled(
            "Gott",
            Style {
                small_caps: true,
                ..Style::PLAIN
            }
        ),
        "class rule from the stylesheet"
    );
    assert_eq!(
        plain_text(inlines),
        "Im Anfang schuf Gott die Himmel und die Erde.",
        "whitespace collapsed"
    );
    let Block::Paragraph { inlines, .. } = &doc.blocks[2] else {
        panic!()
    };
    assert!(
        inlines
            .iter()
            .any(|i| matches!(i, Inline::Text { text, style } if text == "wüst" && style.italic))
    );
    // A hidden heading keeps its structural value (chapter number).
    assert!(
        matches!(&doc.blocks[3], Block::Heading { level: 3, inlines } if plain_text(inlines) == "2")
    );
}

#[test]
fn notes_lists_tables_figures_and_navigation() {
    let png: &[u8] = &[
        0x89, b'P', b'N', b'G', b'\r', b'\n', 0x1a, b'\n', 0, 0, 0, 13, b'I', b'H', b'D', b'R', 0,
        0, 0, 40, 0, 0, 0, 30, 8, 2, 0, 0, 0,
    ];
    let body = xhtml(
        r##"<div class="nav"><a href="toc.xhtml">[Inhalt]</a> | <a href="#c1">[1]</a></div>
           <p class="textspalte"><a href="../Text/TOC.xhtml">[Inhaltsverzeichnis]</a> | <a href="#x">[2]</a></p>
           <p>Text mit Anmerkung<a class="noteref" href="#fn1"><sup>1</sup></a> und zweiter<span class="noteref">2</span>.</p>
           <p>Ein Aussätziger<a href="#footnote-9-3" id="footnote-9-3-backlink"><sup>a</sup></a>&#160;kam.</p>
           <ol><li>Erstens</li><li>Zweitens <b>fett</b></li></ol>
           <table><tr><th>Größe</th><th>Einheit</th></tr><tr><td>Länge</td><td>Meter</td></tr></table>
           <figure><img src="../Images/f.png"/><figcaption>Abb. 1</figcaption></figure>
           <blockquote>Zitat.</blockquote>
           <div class="notesContainer"><p class="note" id="fn1">1 Erste Anmerkung.</p><p class="note">2. Zweite.</p></div>"##,
    );
    let source = epub_with(&[
        (
            "OEBPS/content.opf",
            opf(
                &["a.xhtml"],
                r##"<item id="img" href="Images/f.png" media-type="image/png"/>"##,
            )
            .as_bytes(),
        ),
        ("OEBPS/Styles/s.css", CSS.as_bytes()),
        ("OEBPS/Text/a.xhtml", body.as_bytes()),
        ("OEBPS/Images/f.png", png),
    ]);
    let doc = epub::read(source).unwrap();
    let kinds: Vec<&str> = doc
        .blocks
        .iter()
        .map(|b| match b {
            Block::Paragraph {
                style: ParagraphStyle::Quote,
                ..
            } => "quote",
            Block::Paragraph { .. } => "p",
            Block::List { .. } => "list",
            Block::Table { .. } => "table",
            Block::Figure { .. } => "figure",
            other => panic!("unexpected {other:?}"),
        })
        .collect();
    assert_eq!(
        kinds,
        vec!["p", "p", "list", "table", "figure", "quote"],
        "{:#?}",
        doc.blocks
    );

    let Block::Paragraph { inlines, .. } = &doc.blocks[0] else {
        panic!()
    };
    assert_eq!(
        inlines,
        &vec![
            Inline::text("Text mit Anmerkung"),
            Inline::NoteRef(0),
            Inline::text(" und zweiter"),
            Inline::NoteRef(1),
            Inline::text("."),
        ]
    );
    // A plain in-page link wrapping a raised letter is a marker too; the
    // non-breaking space after it keeps the next word apart.
    let Block::Paragraph { inlines, .. } = &doc.blocks[1] else {
        panic!()
    };
    assert_eq!(
        inlines,
        &vec![
            Inline::text("Ein Aussätziger"),
            Inline::NoteRef(2),
            Inline::text("\u{a0}kam."),
        ],
        "{inlines:?}"
    );
    assert_eq!(doc.notes.len(), 3);
    assert_eq!(doc.notes[0].label, "fn1");
    assert!(
        matches!(&doc.notes[0].blocks[0], Block::Paragraph { inlines, .. } if plain_text(inlines) == "Erste Anmerkung."),
        "{:?}",
        doc.notes[0]
    );
    assert!(
        matches!(&doc.notes[1].blocks[0], Block::Paragraph { inlines, .. } if plain_text(inlines) == "Zweite."),
        "ordinal match strips its label: {:?}",
        doc.notes[1]
    );
    assert_eq!(doc.notes[1].label, "2");

    let Block::List { ordered, items } = &doc.blocks[2] else {
        panic!()
    };
    assert!(ordered);
    assert_eq!(items.len(), 2);
    assert!(
        matches!(&items[1][0], Block::Paragraph { inlines, .. } if plain_text(inlines) == "Zweitens fett")
    );

    let Block::Table { header_rows, rows } = &doc.blocks[3] else {
        panic!()
    };
    assert_eq!(*header_rows, 1);
    assert_eq!(rows.len(), 2);
    assert_eq!(plain_text(&rows[1][1]), "Meter");

    let Block::Figure { image, caption } = &doc.blocks[4] else {
        panic!()
    };
    assert_eq!(plain_text(caption), "Abb. 1");
    assert_eq!(doc.images[*image].media_type, "image/png");
    assert_eq!(
        (doc.images[*image].width, doc.images[*image].height),
        (40, 30)
    );
}

#[test]
fn osis_named_files_mark_chapters() {
    let body = xhtml(
        r##"<h2>Esther 4</h2><p><span class="verseNum">1 </span>Und als Mordokai alles erfuhr.</p>"##,
    );
    let items = r##"<item id="e4" href="Esth-4.html" media-type="application/xhtml+xml"/>"##;
    let opf = format!(
        r##"<?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf" version="2.0"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>B</dc:title><dc:language>de</dc:language></metadata><manifest>{items}</manifest><spine><itemref idref="e4"/></spine></package>"##
    );
    let source = epub_with(&[
        ("OEBPS/content.opf", opf.as_bytes()),
        ("OEBPS/Esth-4.html", body.as_bytes()),
    ]);
    let doc = epub::read(source).unwrap();
    assert_eq!(
        doc.blocks[0],
        Block::Milestone {
            osis: "Esth.4".into()
        }
    );
    assert!(
        matches!(&doc.blocks[2], Block::Paragraph { inlines, .. } if inlines[0] == Inline::VerseNumber(1))
    );
}

#[test]
fn drm_protected_files_are_refused() {
    let encryption = br##"<?xml version="1.0"?><encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><EncryptedData xmlns="http://www.w3.org/2001/04/xmlenc#"><EncryptionMethod Algorithm="http://www.w3.org/2001/04/xmlenc#aes128-cbc"/></EncryptedData></encryption>"##;
    let source = epub_with(&[
        ("META-INF/encryption.xml", encryption),
        ("OEBPS/content.opf", opf(&["a.xhtml"], "").as_bytes()),
        ("OEBPS/Text/a.xhtml", xhtml("<p>x</p>").as_bytes()),
    ]);
    assert!(matches!(
        epub::read(source),
        Err(DocumentError::Protected(_))
    ));

    // Font obfuscation alone is not DRM.
    let fonts = br##"<?xml version="1.0"?><encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><EncryptedData xmlns="http://www.w3.org/2001/04/xmlenc#"><EncryptionMethod Algorithm="http://www.idpf.org/2008/embedding"/></EncryptedData></encryption>"##;
    let source = epub_with(&[
        ("META-INF/encryption.xml", fonts),
        ("OEBPS/content.opf", opf(&["a.xhtml"], "").as_bytes()),
        ("OEBPS/Text/a.xhtml", xhtml("<p>x</p>").as_bytes()),
    ]);
    assert!(epub::read(source).is_ok());
}
