//! Interpretation (ADR 0029): detection of Bible, commentary, and book
//! shapes; Bible conversion with chapters, verses, headings, marked and
//! located notes; commentary anchoring by headings and quoted verses with
//! context-resolved references; book sectioning.

use gramma_core::document::interpret::{DocumentKind, detect, to_bible, to_book, to_commentary};
use gramma_core::document::{Block, Document, Inline, Note, ParagraphStyle, Style};
use gramma_core::reference::book_by_osis;

fn p(inlines: Vec<Inline>) -> Block {
    Block::Paragraph {
        style: ParagraphStyle::Body,
        inlines,
    }
}

fn h(level: u8, text: &str) -> Block {
    Block::Heading {
        level,
        inlines: vec![Inline::text(text)],
    }
}

fn note(text: &str) -> Note {
    Note {
        label: String::new(),
        blocks: vec![p(vec![Inline::text(text)])],
    }
}

/// A two-chapter Bible in the producer style seen in the wild: book
/// heading with the name in parentheses, hidden numeric chapter headings,
/// verse-number spans, a section heading, a marked note, a note located
/// by "(2,1)".
fn bible() -> Document {
    Document {
        title: "Die Bibel".into(),
        language: "de".into(),
        blocks: vec![
            h(2, "Das erste Buch Mose (Genesis)"),
            h(3, "Die Urzeit"),
            p(vec![Inline::text(
                "1 Im Anfang schuf Gott die Himmel und die Erde.",
            )]),
            h(3, "Der erste Tag"),
            p(vec![
                Inline::VerseNumber(2),
                Inline::text("Die Erde aber war "),
                Inline::styled(
                    "wüst",
                    Style {
                        italic: true,
                        ..Style::PLAIN
                    },
                ),
                Inline::NoteRef(0),
                Inline::text(" und leer."),
            ]),
            p(vec![
                Inline::VerseNumber(3),
                Inline::text("Und Gott sprach: Es werde Licht!"),
            ]),
            h(3, "2"),
            // A drop-cap chapter number opens the chapter's first verse.
            p(vec![Inline::text("2 So wurden vollendet.")]),
            p(vec![
                Inline::VerseNumber(2),
                Inline::text("Und Gott ruhte."),
            ]),
            Block::Milestone {
                osis: "Exod.1".into(),
            },
            h(2, "Exodus 1"),
            p(vec![
                Inline::VerseNumber(1),
                Inline::text("Dies sind die Namen."),
            ]),
        ],
        notes: vec![note("od. öde."), note("(2,1) Das Werk war vollendet.")],
        ..Document::default()
    }
    .with_verse_count()
}

trait Grow {
    fn with_verse_count(self) -> Self;
}

impl Grow for Document {
    /// Detection needs volume: repeat the Genesis 2 verses to pass 50 markers.
    fn with_verse_count(mut self) -> Self {
        let filler: Vec<Block> = (3..60)
            .map(|n| {
                p(vec![
                    Inline::VerseNumber(n),
                    Inline::text(format!("Vers {n}.")),
                ])
            })
            .collect();
        let at = self
            .blocks
            .iter()
            .position(|b| matches!(b, Block::Milestone { .. }))
            .unwrap();
        self.blocks.splice(at..at, filler);
        self
    }
}

#[test]
fn a_bible_is_detected_and_converted() {
    let doc = bible();
    let detection = detect(&doc);
    assert_eq!(detection.kind, DocumentKind::Bible, "{detection:?}");
    assert_eq!(detection.chapters, 3);

    let osis = to_bible(&doc, "Probe").unwrap();
    let genesis = book_by_osis("Gen").unwrap();
    let exod = book_by_osis("Exod").unwrap();
    let verses: Vec<(String, u16, u16, &str)> = osis
        .verses
        .iter()
        .take(6)
        .map(|v| {
            (
                v.book.info().osis.to_string(),
                v.chapter,
                v.verse,
                v.text.as_str(),
            )
        })
        .collect();
    assert_eq!(
        verses,
        vec![
            (
                "Gen".to_string(),
                1,
                1,
                "Im Anfang schuf Gott die Himmel und die Erde."
            ),
            ("Gen".to_string(), 1, 2, "Die Erde aber war wüst und leer."),
            ("Gen".to_string(), 1, 3, "Und Gott sprach: Es werde Licht!"),
            ("Gen".to_string(), 2, 1, "So wurden vollendet."),
            ("Gen".to_string(), 2, 2, "Und Gott ruhte."),
            ("Gen".to_string(), 2, 3, "Vers 3."),
        ]
    );
    assert_eq!(
        osis.verses.last().map(|v| (v.book, v.chapter, v.verse)),
        Some((exod, 1, 1))
    );

    // Section headings attach to the verse they precede.
    let headings: Vec<(u16, u16, &str)> = osis
        .headings
        .iter()
        .map(|h| (h.chapter, h.verse, h.text.as_str()))
        .collect();
    assert_eq!(
        headings,
        vec![(1, 1, "Die Urzeit"), (1, 2, "Der erste Tag")]
    );

    // The marked note anchors at its word; the located one at its verse's end.
    let notes: Vec<(u16, u16, u32, &str)> = osis
        .notes
        .iter()
        .map(|n| (n.chapter, n.verse, n.offset, n.text.as_str()))
        .collect();
    assert_eq!(
        notes,
        vec![
            (1, 2, "Die Erde aber war wüst".len() as u32, "od. öde."),
            (
                2,
                1,
                "So wurden vollendet.".len() as u32,
                "Das Werk war vollendet."
            ),
        ]
    );
    assert!(osis.notes.iter().all(|n| n.book == genesis));
}

#[test]
fn a_commentary_anchors_sections_and_resolves_references() {
    let doc = Document {
        title: "Kommentar zum Römerbrief".into(),
        blocks: vec![
            h(1, "Einleitung"),
            p(vec![Inline::text(
                "Der Brief wurde in Korinth geschrieben (vgl. Apg 20,2-3).",
            )]),
            h(2, "Gottes Gerechtigkeit (1,18-32)"),
            p(vec![
                Inline::text("Paulus sagt, dass Gottes Zorn über allen steht (V. 18)."),
                Inline::NoteRef(0),
            ]),
            Block::Paragraph {
                style: ParagraphStyle::Scripture,
                inlines: vec![Inline::text(
                    "18 Denn es offenbart sich Gottes Zorn vom Himmel her.",
                )],
            },
            p(vec![Inline::text(
                "»Denn« begründet das Vorige; siehe auch Kapitel 2 und Gal 2,17-21.",
            )]),
            Block::Paragraph {
                style: ParagraphStyle::Scripture,
                inlines: vec![Inline::text("21 weil sie Gott kannten.")],
            },
            p(vec![Inline::text("Die Erkenntnis ohne Ehre (V. 21-23).")]),
            h(2, "Anmerkungen zu Kapitel 4"),
            p(vec![Inline::text(
                "Abraham wurde ohne Werke gerechtfertigt (4,3).",
            )]),
        ],
        notes: vec![note("Siehe M. Luther, Vorrede.")],
        ..Document::default()
    };
    let detection = detect(&doc);
    assert_eq!(detection.kind, DocumentKind::Commentary, "{detection:?}");
    assert_eq!(detection.subject_book.as_deref(), Some("Rom"));

    let commentary = to_commentary(&doc, None).unwrap();
    let anchors: Vec<(u16, u16, u16, Option<&str>)> = commentary
        .entries
        .iter()
        .map(|e| (e.chapter, e.verse_start, e.verse_end, e.heading.as_deref()))
        .collect();
    assert_eq!(
        anchors,
        vec![
            (1, 0, 0, Some("Einleitung")),
            (1, 18, 32, Some("Gottes Gerechtigkeit (1,18-32)")),
            (1, 18, 20, None),
            (1, 21, 21, None),
            (4, 0, 0, Some("Anmerkungen zu Kapitel 4")),
        ],
        "{anchors:?}"
    );
    let refs: Vec<(String, String)> = commentary
        .entries
        .iter()
        .flat_map(|e| {
            e.refs.iter().map(move |r| {
                (
                    e.text[r.start as usize..r.end as usize].to_string(),
                    r.osis.clone(),
                )
            })
        })
        .collect();
    assert_eq!(
        refs,
        vec![
            ("Apg 20,2-3".to_string(), "Acts.20.2-Acts.20.3".to_string()),
            ("V. 18".to_string(), "Rom.1.18".to_string()),
            ("Kapitel 2".to_string(), "Rom.2".to_string()),
            ("Gal 2,17-21".to_string(), "Gal.2.17-Gal.2.21".to_string()),
            ("V. 21-23".to_string(), "Rom.1.21-Rom.1.23".to_string()),
            ("4,3".to_string(), "Rom.4.3".to_string()),
        ]
    );
    // The note travels with its entry, renumbered locally.
    let with_note = &commentary.contents[1];
    assert_eq!(with_note.notes.len(), 1);
    assert!(with_note.blocks.iter().any(
        |b| matches!(b, Block::Paragraph { inlines, .. } if inlines.contains(&Inline::NoteRef(0)))
    ));
    assert!(commentary.entries[1].text.contains("[1] Siehe M. Luther"));
}

#[test]
fn a_book_sections_at_headings() {
    let doc = Document {
        title: "Information".into(),
        blocks: vec![
            p(vec![Inline::text("Vorwort ohne Überschrift.")]),
            h(1, "1 Einführung"),
            p(vec![Inline::text("Text der Einführung, siehe Joh 1,1.")]),
            h(2, "1.1 Begriffe"),
            Block::List {
                ordered: true,
                items: vec![
                    vec![p(vec![Inline::text("Erstens")])],
                    vec![p(vec![Inline::text("Zweitens")])],
                ],
            },
        ],
        ..Document::default()
    };
    assert_eq!(detect(&doc).kind, DocumentKind::Book);
    let book = to_book(&doc).unwrap();
    let names: Vec<(u32, u8, &str)> = book
        .sections
        .iter()
        .map(|s| (s.ordinal, s.level, s.name.as_str()))
        .collect();
    assert_eq!(
        names,
        vec![
            (1, 1, "Information"),
            (2, 1, "1 Einführung"),
            (3, 2, "1.1 Begriffe")
        ]
    );
    assert_eq!(book.sections[2].text, "Erstens\n\nZweitens");
    assert!(book.contents[1].blocks.iter().any(|b| matches!(b, Block::Paragraph { inlines, .. } if inlines.iter().any(|i| matches!(i, Inline::Reference { osis, .. } if osis == "John.1.1")))));
}

#[test]
fn publisher_book_headings_resolve() {
    use gramma_core::document::interpret::book_in_heading;
    let cases = [
        ("Das erste Buch Mose (Genesis)", "Gen"),
        ("Das vierte Buch Mose (Numeri)", "Num"),
        ("Das fünfte Buch Mose (Deuteronomium)", "Deut"),
        ("Das Buch der Richter", "Judg"),
        ("Das erste Buch der Chronik", "1Chr"),
        ("Das Buch des Propheten Hesekiel (Ezechiel)", "Ezek"),
        ("Das Buch des Propheten Zephanja", "Zeph"),
        ("Die Psalmen", "Ps"),
        ("Die Sprüche", "Prov"),
        ("Der Prediger", "Eccl"),
        ("Das Hohelied", "Song"),
        ("Die Klagelieder Jeremias", "Lam"),
        ("Das Evangelium nach Johannes", "John"),
        ("Die Apostelgeschichte", "Acts"),
        ("Der Brief des Apostels Paulus an die Römer", "Rom"),
        (
            "Der erste Brief des Apostels Paulus an die Korinther",
            "1Cor",
        ),
        ("Der zweite Brief des Apostels Paulus an Timotheus", "2Tim"),
        ("Der Brief des Judas", "Jude"),
        ("Der dritte Brief des Apostels Johannes", "3John"),
        ("Die Offenbarung Jesu Christi durch Johannes", "Rev"),
    ];
    for (heading, osis) in cases {
        assert_eq!(
            book_in_heading(heading).map(|b| b.info().osis),
            Some(osis),
            "{heading}"
        );
    }
    assert_eq!(
        book_in_heading("Die Urzeit: von der Schöpfung bis Abraham"),
        None
    );
    assert_eq!(book_in_heading("Der siebte Tag"), None);
}
