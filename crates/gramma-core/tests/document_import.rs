//! Documents into the library (ADR 0029): a converted Bible reads back
//! through the verse, heading, and note tables; a commentary keeps its
//! entries, references, block trees, and images; a book keeps sections
//! with content; SWORD-imported rows have no block tree.

use gramma_core::document::interpret::DocumentKind;
use gramma_core::document::{Block, Document, ImageAsset, Inline, Note, ParagraphStyle};
use gramma_core::library::Library;
use gramma_core::reference::book_by_osis;

fn p(text: &str) -> Block {
    Block::Paragraph {
        style: ParagraphStyle::Body,
        inlines: vec![Inline::text(text)],
    }
}

fn h(level: u8, text: &str) -> Block {
    Block::Heading {
        level,
        inlines: vec![Inline::text(text)],
    }
}

#[test]
fn a_bible_document_lands_in_the_verse_tables() {
    let mut blocks = vec![h(2, "Esther 4")];
    for n in 1..=60u16 {
        blocks.push(Block::Paragraph {
            style: ParagraphStyle::Body,
            inlines: vec![Inline::VerseNumber(n), Inline::text(format!("Vers {n}."))],
        });
        if n == 1 {
            blocks.push(h(3, "Mordokais Trauer"));
        }
    }
    blocks.push(Block::Milestone {
        osis: "Esth.5".into(),
    });
    blocks.push(Block::Paragraph {
        style: ParagraphStyle::Body,
        inlines: vec![
            Inline::VerseNumber(1),
            Inline::text("Am dritten Tag"),
            Inline::NoteRef(0),
            Inline::text("."),
        ],
    });
    let doc = Document {
        title: "Probebibel".into(),
        language: "de".into(),
        blocks,
        notes: vec![Note {
            label: "a".into(),
            blocks: vec![p("W. am dritten Tag.")],
        }],
        ..Document::default()
    };
    let mut library = Library::open_in_memory().unwrap();
    let info = library
        .import_document(&doc, DocumentKind::Bible, "Probe", None)
        .unwrap();
    assert_eq!(info.kind, "bible");
    assert_eq!(info.verses, 61);
    let esth = book_by_osis("Esth").unwrap();
    let verses = library.chapter("Probe", esth, 4).unwrap();
    assert_eq!(verses.len(), 60);
    assert_eq!(verses[1].text, "Vers 2.");
    let headings = library.headings("Probe", esth, 4).unwrap();
    assert_eq!(headings.len(), 1);
    assert_eq!(headings[0].verse, 2, "the heading stands before verse 2");
    let notes = library.notes("Probe", esth, 5).unwrap();
    assert_eq!(notes.len(), 1);
    assert_eq!(notes[0].offset, "Am dritten Tag".len() as u32);
    assert_eq!(notes[0].text, "W. am dritten Tag.");
}

#[test]
fn a_commentary_document_keeps_entries_references_blocks_and_images() {
    let png = ImageAsset {
        media_type: "image/png".into(),
        data: vec![1, 2, 3],
        width: 4,
        height: 5,
    };
    let doc = Document {
        title: "Kommentar zum Römerbrief".into(),
        blocks: vec![
            h(1, "Der Gruß (1,1-7)"),
            p("Paulus, ein Knecht (V. 1), grüßt wie in Gal 1,3."),
            Block::Figure {
                image: 0,
                caption: vec![Inline::text("Abb. 1")],
            },
            Block::Paragraph {
                style: ParagraphStyle::Scripture,
                inlines: vec![Inline::text("7 Allen Geliebten Gottes in Rom.")],
            },
            Block::Paragraph {
                style: ParagraphStyle::Body,
                inlines: vec![
                    Inline::text("Die Heiligen"),
                    Inline::NoteRef(0),
                    Inline::text(" sind berufen (V. 7)."),
                ],
            },
        ],
        notes: vec![Note {
            label: "1".into(),
            blocks: vec![p("Vgl. 1Kor 1,2.")],
        }],
        images: vec![png.clone()],
        ..Document::default()
    };
    let mut library = Library::open_in_memory().unwrap();
    let info = library
        .import_document(&doc, DocumentKind::Commentary, "RoemK", None)
        .unwrap();
    assert_eq!(info.kind, "commentary");
    let rom = book_by_osis("Rom").unwrap();
    let comments = library.comments("RoemK", rom, 1).unwrap();
    assert_eq!(comments.len(), 2, "{comments:?}");
    assert_eq!((comments[0].verse_start, comments[0].verse_end), (1, 7));
    assert_eq!(comments[0].heading.as_deref(), Some("Der Gruß (1,1-7)"));
    let osis: Vec<&str> = comments[0].refs.iter().map(|r| r.osis.as_str()).collect();
    assert_eq!(osis, vec!["Rom.1.1", "Gal.1.3"]);
    assert_eq!((comments[1].verse_start, comments[1].verse_end), (7, 7));
    assert!(
        comments[1].text.contains("[1] Vgl. 1Kor 1,2."),
        "{}",
        comments[1].text
    );

    let content = library
        .comment_content("RoemK", rom, 1, 7)
        .unwrap()
        .unwrap();
    assert_eq!(content.notes.len(), 1);
    assert!(content.blocks.iter().any(|b| matches!(
        b,
        Block::Paragraph {
            style: ParagraphStyle::Scripture,
            ..
        }
    )));
    assert!(content.blocks.iter().any(|b| matches!(b, Block::Paragraph { inlines, .. } if inlines.iter().any(|i| matches!(i, Inline::Reference { osis, .. } if osis == "Rom.1.7")))));
    let intro = library
        .comment_content("RoemK", rom, 1, 1)
        .unwrap()
        .unwrap();
    assert!(
        intro
            .blocks
            .iter()
            .any(|b| matches!(b, Block::Figure { image: 0, .. }))
    );
    assert_eq!(library.image("RoemK", 0).unwrap(), Some(png));
    assert_eq!(library.image("RoemK", 1).unwrap(), None);
}

#[test]
fn a_book_document_keeps_sections_with_content() {
    let doc = Document {
        title: "Information".into(),
        blocks: vec![
            h(1, "Einführung"),
            p("Eine Einführung in das Thema."),
            Block::Table {
                header_rows: 1,
                rows: vec![
                    vec![vec![Inline::text("Größe")], vec![Inline::text("Einheit")]],
                    vec![vec![Inline::text("Länge")], vec![Inline::text("Meter")]],
                ],
            },
        ],
        ..Document::default()
    };
    let mut library = Library::open_in_memory().unwrap();
    let info = library
        .import_document(&doc, DocumentKind::Book, "Info", None)
        .unwrap();
    assert_eq!((info.kind.as_str(), info.verses), ("book", 1));
    let (section, _, _) = library.book_section("Info", 1).unwrap().unwrap();
    assert_eq!(section.name, "Einführung");
    assert_eq!(
        section.text,
        "Eine Einführung in das Thema.\n\nGröße · Einheit\n\nLänge · Meter"
    );
    let content = library.book_section_content("Info", 1).unwrap().unwrap();
    assert!(matches!(&content.blocks[1], Block::Table { header_rows: 1, rows } if rows.len() == 2));
}
