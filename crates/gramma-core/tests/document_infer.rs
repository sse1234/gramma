//! Structure inference over positioned text (ADR 0029) with synthetic
//! pages: running heads and page numbers vanish, footnotes bind to their
//! raised numbers, hyphenated lines join, indents and gaps open
//! paragraphs, numbered lines form lists, aligned cells form tables,
//! heading levels follow size, and two-column pages read column-wise.

use gramma_core::document::infer::{InferOptions, document_from_pages};
use gramma_core::document::pdf::{FontRole, Fragment, PageText};
use gramma_core::document::{Block, Inline, ParagraphStyle, plain_text};

const W: f32 = 400.0;
const H: f32 = 600.0;

fn frag(x: f32, y: f32, size: f32, text: &str) -> Fragment {
    Fragment {
        x,
        y,
        size,
        font: FontRole {
            name: "Body".into(),
            ..FontRole::default()
        },
        text: text.into(),
        width: text.chars().count() as f32 * size * 0.5,
        rise: 0.0,
    }
}

fn bold(mut f: Fragment) -> Fragment {
    f.font.bold = true;
    f
}

fn italic(mut f: Fragment) -> Fragment {
    f.font.italic = true;
    f
}

/// A body page: running head and page number at the margins, lines at a
/// 13 pt pitch from `top` down. `lines` are (indent, text).
fn page(number: usize, lines: &[(f32, &str)]) -> PageText {
    let mut fragments = vec![
        frag(50.0, H - 30.0, 9.0, "Running head"),
        frag(200.0, 25.0, 9.0, &number.to_string()),
    ];
    let mut y = H - 70.0;
    for (indent, text) in lines {
        fragments.push(frag(50.0 + indent, y, 10.0, text));
        y -= 13.0;
    }
    PageText {
        width: W,
        height: H,
        fragments,
        images: Vec::new(),
    }
}

fn paragraphs(doc: &gramma_core::document::Document) -> Vec<String> {
    doc.blocks
        .iter()
        .filter_map(|b| match b {
            Block::Paragraph { inlines, .. } => Some(plain_text(inlines)),
            _ => None,
        })
        .collect()
}

const FULL: &str =
    "Dies ist eine volle Zeile, die bis an den rechten Rand des Satzspiegels reicht und";

#[test]
fn furniture_goes_and_lines_join_into_paragraphs() {
    let pages = vec![
        page(
            1,
            &[
                (0.0, FULL),
                (
                    0.0,
                    "so weiter geht, bis der Absatz mit einem kurzen Rest endet.",
                ),
                (
                    12.0,
                    "Ein neuer Absatz beginnt eingerückt und läuft über die Zeile bis an den Rand,",
                ),
                (0.0, "wo er umbricht und weiter-"),
                (0.0, "geht bis zum Ende."),
            ],
        ),
        page(2, &[(0.0, "Zweite Seite, ein eigener Absatz.")]),
        page(3, &[(0.0, "Dritte Seite.")]),
    ];
    let doc = document_from_pages(&pages, &InferOptions::default());
    let text = paragraphs(&doc);
    assert_eq!(
        text,
        vec![
            format!("{FULL} so weiter geht, bis der Absatz mit einem kurzen Rest endet."),
            "Ein neuer Absatz beginnt eingerückt und läuft über die Zeile bis an den Rand, wo er umbricht und weitergeht bis zum Ende."
                .to_string(),
            "Zweite Seite, ein eigener Absatz.".to_string(),
            "Dritte Seite.".to_string(),
        ],
        "{:#?}",
        doc.blocks
    );
    assert!(
        !doc.blocks
            .iter()
            .any(|b| matches!(b, Block::Heading { .. })),
        "running heads are not headings"
    );
}

#[test]
fn footnotes_bind_to_raised_numbers() {
    let mut p = page(
        1,
        &[
            (0.0, "Ein Satz mit einer Anmerkung"),
            (0.0, "und einer zweiten Zeile."),
        ],
    );
    // Raised small "1" after "Anmerkung" (no Ts operator: smaller size on
    // a higher baseline).
    let anchor_x = 50.0 + "Ein Satz mit einer Anmerkung".chars().count() as f32 * 5.0;
    p.fragments.push(frag(anchor_x, H - 70.0 + 3.0, 6.5, "1"));
    // The note at the page foot, smaller, wrapping over two lines.
    p.fragments.push(frag(
        50.0,
        80.0,
        7.5,
        "1 Die Anmerkung erklärt etwas, das über",
    ));
    p.fragments
        .push(frag(50.0, 70.0, 7.5, "zwei Zeilen läuft."));
    // A second note on the same page.
    p.fragments
        .push(frag(50.0, 60.0, 7.5, "2 Eine weitere Anmerkung."));
    p.fragments.push(frag(150.0, H - 83.0 + 3.0, 6.5, "2"));
    let doc = document_from_pages(&[p], &InferOptions::default());
    let Block::Paragraph { inlines, .. } = &doc.blocks[0] else {
        panic!("{:#?}", doc.blocks)
    };
    assert_eq!(
        inlines,
        &vec![
            Inline::text("Ein Satz mit einer Anmerkung"),
            Inline::NoteRef(0),
            Inline::text(" und einer zweiten Zeile."),
            Inline::NoteRef(1),
        ],
        "{:#?}",
        doc.blocks
    );
    assert_eq!(doc.notes.len(), 2);
    assert_eq!(doc.notes[0].label, "1");
    assert!(
        matches!(&doc.notes[0].blocks[0], Block::Paragraph { inlines, .. } if plain_text(inlines) == "Die Anmerkung erklärt etwas, das über zwei Zeilen läuft."),
        "{:?}",
        doc.notes[0]
    );
}

#[test]
fn headings_rank_by_size_and_lists_and_tables_form() {
    let mut p = page(
        1,
        &[
            (
                0.0,
                "1. Erstens ist dies ein Punkt, der über die Zeile hinausreicht und",
            ),
            (14.0, "in der nächsten Zeile hängend fortgesetzt wird."),
            (0.0, "2. Zweitens ein kurzer Punkt."),
            (0.0, "Danach folgt gewöhnlicher Text."),
        ],
    );
    // A large chapter title and a smaller bold section heading above.
    p.fragments.push(frag(50.0, H - 45.0, 16.0, "Kapitel Eins"));
    p.fragments
        .push(bold(frag(50.0, H - 58.0, 11.0, "Ein Abschnitt")));
    // A three-row, two-column table below the text.
    let y0 = H - 70.0 - 13.0 * 5.0;
    for (i, (a, b)) in [
        ("Länge", "Meter"),
        ("Masse", "Kilogramm"),
        ("Zeit", "Sekunde"),
    ]
    .iter()
    .enumerate()
    {
        let y = y0 - 13.0 * i as f32;
        p.fragments.push(frag(60.0, y, 10.0, a));
        p.fragments.push(frag(180.0, y, 10.0, b));
    }
    let doc = document_from_pages(&[p], &InferOptions::default());
    let kinds: Vec<String> = doc
        .blocks
        .iter()
        .map(|b| match b {
            Block::Heading { level, inlines } => format!("h{level}:{}", plain_text(inlines)),
            Block::Paragraph { .. } => "p".into(),
            Block::List { ordered, items } => format!(
                "list{}:{}",
                if *ordered { "-ordered" } else { "" },
                items.len()
            ),
            Block::Table { rows, .. } => format!("table:{}x{}", rows.len(), rows[0].len()),
            other => format!("{other:?}"),
        })
        .collect();
    assert_eq!(
        kinds,
        vec![
            "h1:Kapitel Eins",
            "h2:Ein Abschnitt",
            "list-ordered:2",
            "p",
            "table:3x2"
        ],
        "{:#?}",
        doc.blocks
    );
    let Block::List { items, .. } = &doc.blocks[2] else {
        panic!()
    };
    assert!(
        matches!(&items[0][0], Block::Paragraph { inlines, .. } if plain_text(inlines) == "Erstens ist dies ein Punkt, der über die Zeile hinausreicht und in der nächsten Zeile hängend fortgesetzt wird."),
        "marker stripped, hanging line joined: {:?}",
        items[0]
    );
    let Block::Table { rows, .. } = &doc.blocks[4] else {
        panic!()
    };
    assert_eq!(plain_text(&rows[1][1]), "Kilogramm");
}

#[test]
fn bold_scripture_blocks_and_styled_runs() {
    let mut p = page(1, &[(0.0, "Kommentar zu dem Vers, der hier folgt.")]);
    let y = H - 83.0;
    p.fragments.push(bold(frag(
        60.0,
        y,
        10.0,
        "14 Denn wir wissen, dass das Gesetz geistlich ist.",
    )));
    p.fragments.push(frag(50.0, y - 13.0, 10.0, "Paulus sagt "));
    p.fragments
        .push(italic(frag(50.0 + 12.0 * 5.0, y - 13.0, 10.0, "ich aber")));
    p.fragments.push(frag(
        50.0 + 20.0 * 5.0,
        y - 13.0,
        10.0,
        " in der ersten Person.",
    ));
    let doc = document_from_pages(&[p], &InferOptions::default());
    assert!(
        matches!(
            &doc.blocks[1],
            Block::Paragraph {
                style: ParagraphStyle::Scripture,
                ..
            }
        ),
        "{:#?}",
        doc.blocks
    );
    let Block::Paragraph { inlines, .. } = &doc.blocks[2] else {
        panic!()
    };
    assert!(
        inlines.iter().any(
            |i| matches!(i, Inline::Text { text, style } if text == "ich aber" && style.italic)
        ),
        "{inlines:?}"
    );
    assert_eq!(
        plain_text(inlines),
        "Paulus sagt ich aber in der ersten Person."
    );
}

#[test]
fn two_column_pages_read_column_by_column() {
    let mut p = PageText {
        width: W,
        height: H,
        fragments: Vec::new(),
        images: Vec::new(),
    };
    // Left column lines at x=40..190, right column at x=210..360, 20 lines each.
    for i in 0..20 {
        let y = H - 60.0 - 13.0 * i as f32;
        p.fragments.push(frag(
            40.0,
            y,
            9.0,
            &format!("links {i} zeile mit wörtern und mehr"),
        ));
        p.fragments.push(frag(
            210.0,
            y,
            9.0,
            &format!("rechts {i} zeile mit wörtern und mehr"),
        ));
    }
    let doc = document_from_pages(&[p], &InferOptions::default());
    let text = paragraphs(&doc).join(" | ");
    let left_end = text.find("links 19").expect("left column present");
    let right_start = text.find("rechts 0").expect("right column present");
    assert!(
        left_end < right_start,
        "left column reads before the right: {text}"
    );
    assert!(
        !doc.blocks.iter().any(|b| matches!(b, Block::Table { .. })),
        "columns are not a table"
    );
}
