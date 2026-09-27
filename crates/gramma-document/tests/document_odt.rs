//! ODT reading (ADR 0029, 2026-09-27) against a synthetic package built
//! in the test: outline headings, a book-title paragraph style, verse
//! number spaces, inline styles through automatic styles, whitespace
//! elements, footnotes with their citation as label, the document
//! language and title — and the Bible interpretation of the result.

use std::io::{Cursor, Write};

use gramma_document::interpret::to_bible;
use gramma_document::odt;
use gramma_document::{Block, Inline, plain_text};
use zip::write::SimpleFileOptions;

fn odt_with(files: &[(&str, &str)]) -> Cursor<Vec<u8>> {
    let mut zip = zip::ZipWriter::new(Cursor::new(Vec::new()));
    let stored = SimpleFileOptions::default().compression_method(zip::CompressionMethod::Stored);
    zip.start_file("mimetype", stored).unwrap();
    zip.write_all(b"application/vnd.oasis.opendocument.text")
        .unwrap();
    for (name, data) in files {
        zip.start_file(*name, stored).unwrap();
        zip.write_all(data.as_bytes()).unwrap();
    }
    Cursor::new(zip.finish().unwrap().into_inner())
}

const NS: &str = r##"xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0" xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:meta="urn:oasis:names:tc:opendocument:xmlns:meta:1.0""##;

fn styles() -> String {
    format!(
        r##"<?xml version="1.0" encoding="UTF-8"?>
<office:document-styles {NS}>
<office:styles>
<style:default-style style:family="paragraph"><style:text-properties fo:language="de" fo:country="DE"/></style:default-style>
<style:style style:name="Standard" style:family="paragraph"/>
<style:style style:name="Buchtitel" style:family="paragraph" style:parent-style-name="Standard"><style:text-properties fo:font-weight="bold"/></style:style>
<style:style style:name="Verszahl" style:family="text"><style:text-properties fo:font-weight="bold" fo:font-size="8pt"/></style:style>
<style:style style:name="Kursiv" style:family="text"><style:text-properties fo:font-style="italic"/></style:style>
<style:style style:name="Kapitaelchen" style:family="text"><style:text-properties fo:font-variant="small-caps"/></style:style>
<style:style style:name="Hochgestellt" style:family="text"><style:text-properties style:text-position="super 58%"/></style:style>
</office:styles>
</office:document-styles>"##
    )
}

fn content() -> String {
    format!(
        r##"<?xml version="1.0" encoding="UTF-8"?>
<office:document-content {NS}>
<office:automatic-styles>
<style:style style:name="P1" style:family="paragraph" style:parent-style-name="Buchtitel"/>
<style:style style:name="T1" style:family="text" style:parent-style-name="Verszahl"/>
</office:automatic-styles>
<office:body><office:text>
<text:h text:outline-level="1">Das Alte Testament</text:h>
<text:p text:style-name="P1">Das erste Buch Mose</text:p>
<text:h text:outline-level="3">1 Mo 1</text:h>
<text:p text:style-name="Standard"><text:span text:style-name="T1">1</text:span> Im Anfang schuf <text:span text:style-name="Kapitaelchen">Gott</text:span> die Himmel und<text:s text:c="3"/>die Erde. <text:span text:style-name="Verszahl">2</text:span> Die Erde aber war <text:span text:style-name="Kursiv">wüst</text:span><text:note text:id="ftn1" text:note-class="footnote"><text:note-citation>1</text:note-citation><text:note-body><text:p>od. öde.</text:p><text:p>Zweiter Absatz.</text:p></text:note-body></text:note> und leer.</text:p>
<text:p text:style-name="Standard"><text:span text:style-name="T1">3</text:span> Und Gott sprach:<text:line-break/>Es werde Licht!<text:tab/>Und es wurde Licht.<text:span text:style-name="Hochgestellt">a</text:span></text:p>
<text:p text:style-name="Standard"/>
</office:text></office:body>
</office:document-content>"##
    )
}

fn meta() -> String {
    format!(
        r##"<?xml version="1.0" encoding="UTF-8"?>
<office:document-meta {NS}><office:meta><dc:title>Probe</dc:title><meta:generator>Test</meta:generator></office:meta></office:document-meta>"##
    )
}

fn describe(inlines: &[Inline]) -> String {
    inlines
        .iter()
        .map(|i| match i {
            Inline::VerseNumber(n) => format!("[{n}]"),
            Inline::NoteRef(i) => format!("{{n{i}}}"),
            Inline::LineBreak => "/".to_string(),
            Inline::Reference { text, .. } => text.clone(),
            Inline::Text { text, style } => {
                let mut tags = String::new();
                if style.bold {
                    tags.push('b');
                }
                if style.italic {
                    tags.push('i');
                }
                if style.superscript {
                    tags.push('^');
                }
                if style.small_caps {
                    tags.push('s');
                }
                if tags.is_empty() {
                    text.clone()
                } else {
                    format!("<{tags}>{text}</{tags}>")
                }
            }
        })
        .collect()
}

fn read() -> gramma_document::Document {
    let source = odt_with(&[
        ("styles.xml", &styles()),
        ("content.xml", &content()),
        ("meta.xml", &meta()),
    ]);
    odt::read(source).unwrap()
}

#[test]
fn headings_paragraphs_styles_and_notes_are_read_as_written() {
    let doc = read();
    assert_eq!(doc.title, "Probe");
    assert_eq!(doc.language, "de");
    let shapes: Vec<String> = doc
        .blocks
        .iter()
        .map(|b| match b {
            Block::Heading { level, inlines } => format!("H{level} {}", plain_text(inlines)),
            Block::Paragraph { inlines, .. } => format!("P {}", describe(inlines)),
            other => format!("{other:?}"),
        })
        .collect();
    assert_eq!(
        shapes,
        [
            "H1 Das Alte Testament",
            "H2 Das erste Buch Mose",
            "H3 1 Mo 1",
            "P [1]Im Anfang schuf <s>Gott</s> die Himmel und die Erde. [2]Die Erde aber war <i>wüst</i>{n0} und leer.",
            "P [3]Und Gott sprach:/Es werde Licht! Und es wurde Licht.<^>a</^>",
        ]
    );
    assert_eq!(doc.notes.len(), 1);
    assert_eq!(doc.notes[0].label, "1");
    let body = match &doc.notes[0].blocks[0] {
        Block::Paragraph { inlines, .. } => describe(inlines),
        other => panic!("{other:?}"),
    };
    assert_eq!(body, "od. öde./Zweiter Absatz.");
}

#[test]
fn the_document_interprets_as_a_bible_with_paragraphs() {
    let doc = read();
    let osis = to_bible(&doc, "Probe").unwrap();
    let verses: Vec<(&str, u16, u16, bool)> = osis
        .verses
        .iter()
        .map(|v| (v.book.info().osis, v.chapter, v.verse, v.paragraph))
        .collect();
    assert_eq!(
        verses,
        [
            ("Gen", 1, 1, true),
            ("Gen", 1, 2, false),
            ("Gen", 1, 3, true)
        ]
    );
    assert_eq!(osis.verses[1].text, "Die Erde aber war wüst und leer.");
    assert_eq!(osis.notes.len(), 1);
    assert_eq!(osis.notes[0].verse, 2);
    assert!(
        osis.notes[0].text.starts_with("od. öde."),
        "{:?}",
        osis.notes[0].text
    );
}
