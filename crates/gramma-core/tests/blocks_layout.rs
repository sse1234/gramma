//! Block layout (ADR 0029): styled runs keep their bits and scale, note
//! markers ride superscript, references link in reading order, list
//! items hang their markers, tables set cells by column, figures reserve
//! lines, quotes indent, and notes close the entry at a smaller size.

use gramma_core::document::{Block, Inline, Note, ParagraphStyle, Style};
use gramma_core::typeset::blocks::layout_blocks;
use gramma_core::typeset::layout::{
    LineOut, ProseSetting, RunOut, STYLE_BOLD, STYLE_ITALIC, STYLE_SUPERSCRIPT,
};
use gramma_core::typeset::shape::FontMeasure;

const FONT: &[u8] = include_bytes!(concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/../../app/fonts/GentiumPlus-Regular.ttf"
));

fn measure() -> FontMeasure<'static> {
    FontMeasure::new(FONT).expect("font parses")
}

fn runs(lines: &[LineOut]) -> Vec<&RunOut> {
    lines.iter().flat_map(|l| l.runs.iter()).collect()
}

fn text_of(lines: &[LineOut]) -> Vec<String> {
    lines
        .iter()
        .map(|l| {
            l.runs
                .iter()
                .map(|r| r.text.as_str())
                .collect::<Vec<_>>()
                .join("|")
        })
        .collect()
}

fn setting(measure: &FontMeasure, ems: i64) -> ProseSetting {
    ProseSetting {
        justify: true,
        line_width: ems * measure.units_per_em() as i64,
    }
}

#[test]
fn styled_runs_markers_and_links() {
    let m = measure();
    let blocks = vec![
        Block::Heading {
            level: 1,
            inlines: vec![Inline::text("Der Gruß")],
        },
        Block::Paragraph {
            style: ParagraphStyle::Body,
            inlines: vec![
                Inline::text("Paulus sagt "),
                Inline::styled(
                    "ich aber",
                    Style {
                        italic: true,
                        ..Style::PLAIN
                    },
                ),
                Inline::NoteRef(0),
                Inline::text(" wie in "),
                Inline::Reference {
                    text: "Gal 2,17".into(),
                    osis: "Gal.2.17".into(),
                },
                Inline::text("."),
            ],
        },
    ];
    let notes = vec![Note {
        label: "3".into(),
        blocks: vec![Block::Paragraph {
            style: ParagraphStyle::Body,
            inlines: vec![Inline::text("Eine Anmerkung.")],
        }],
    }];
    let lines = layout_blocks(
        Some("7"),
        &blocks,
        &notes,
        &[],
        7,
        &m,
        None,
        setting(&m, 30),
    );
    let all = runs(&lines);
    // The label rides the heading, the heading is level 1.
    assert!(all[0].verse_number && all[0].text == "7");
    assert!(all[1].heading_level == 1 && all[1].text == "Der");
    let italic: Vec<&str> = all
        .iter()
        .filter(|r| r.style & STYLE_ITALIC != 0)
        .map(|r| r.text.as_str())
        .collect();
    assert_eq!(italic, vec!["ich", "aber"]);
    let marker = all.iter().find(|r| r.note_marker).expect("note marker");
    assert_eq!(marker.text, "3");
    assert!(marker.style & STYLE_SUPERSCRIPT != 0);
    assert!(marker.scale < 0.7 && marker.scale > 0.6);
    // The marker hugs the word before it.
    let aber = all.iter().position(|r| r.text == "aber").unwrap();
    assert_eq!(all[aber + 1].text, "3");
    assert!((all[aber].x + all[aber].width - all[aber + 1].x).abs() < 1.0);
    let linked: Vec<(&str, Option<u32>)> = all
        .iter()
        .filter(|r| r.link.is_some())
        .map(|r| (r.text.as_str(), r.link))
        .collect();
    assert_eq!(linked, vec![("Gal", Some(0)), ("2,17", Some(0))]);
    // The period glues to the reference.
    let period = all.iter().position(|r| r.text == ".").unwrap();
    assert!((all[period - 1].x + all[period - 1].width - all[period].x).abs() < 1.0);
    // Notes come last, smaller, labelled.
    let last = lines.last().unwrap();
    assert_eq!(last.runs[0].text, "3");
    assert!(last.runs[0].verse_number);
    assert!(last.runs[1].scale < 0.9 && last.runs[1].text == "Eine");
    assert!(
        lines.iter().any(|l| l.runs.is_empty()),
        "a blank line separates blocks"
    );
}

#[test]
fn lists_tables_figures_and_quotes() {
    let m = measure();
    let em = m.units_per_em() as f64;
    let blocks = vec![
        Block::List {
            ordered: true,
            items: vec![
                vec![Block::Paragraph {
                    style: ParagraphStyle::Body,
                    inlines: vec![Inline::text(
                        "Erstens ein Punkt, der lang genug ist, um über die Zeile zu laufen und weiter zu gehen, bis er umbricht.",
                    )],
                }],
                vec![Block::Paragraph {
                    style: ParagraphStyle::Body,
                    inlines: vec![Inline::text("Zweitens.")],
                }],
            ],
        },
        Block::Table {
            header_rows: 1,
            rows: vec![
                vec![vec![Inline::text("Größe")], vec![Inline::text("Einheit")]],
                vec![vec![Inline::text("Länge")], vec![Inline::text("Meter")]],
            ],
        },
        Block::Figure {
            image: 0,
            caption: vec![Inline::text("Abb. 1")],
        },
        Block::Paragraph {
            style: ParagraphStyle::Quote,
            inlines: vec![Inline::text("Ein Zitat.")],
        },
        Block::Paragraph {
            style: ParagraphStyle::Scripture,
            inlines: vec![Inline::text("14 Denn wir wissen.")],
        },
    ];
    let lines = layout_blocks(
        None,
        &blocks,
        &[],
        &[(400, 200)],
        1,
        &m,
        None,
        setting(&m, 24),
    );
    let text = text_of(&lines);
    // Marker in the margin, item text indented and hanging.
    assert_eq!(lines[0].runs[0].text, "1.");
    assert_eq!(lines[0].runs[0].x, 0.0);
    assert!(
        lines[0].runs[1].x >= 2.0 * em - 1.0,
        "{:?}",
        lines[0].runs[1]
    );
    assert!(
        lines[1].runs[0].x >= 2.0 * em - 1.0,
        "hanging: {:?}",
        lines[1].runs[0]
    );
    let second = lines
        .iter()
        .position(|l| l.runs.first().is_some_and(|r| r.text == "2."))
        .unwrap();
    assert_eq!(text[second], "2.|Zweitens.");
    // Table rows: header bold, cells at column offsets.
    let header = lines
        .iter()
        .position(|l| {
            l.runs
                .first()
                .is_some_and(|r| r.text == "GRÖSSE" || r.text == "Größe")
        })
        .unwrap();
    assert!(lines[header].runs.iter().all(|r| r.style & STYLE_BOLD != 0));
    assert_eq!(lines[header].runs.len(), 2);
    assert!(lines[header].runs[1].x > lines[header].runs[0].x + 5.0 * em);
    assert_eq!(text[header + 1], "Länge|Meter");
    assert!(
        lines[header + 1]
            .runs
            .iter()
            .all(|r| r.style & STYLE_BOLD == 0)
    );
    // Figure: a 2:1 image at a 24 em measure reserves 12 em / 1.4 em ≈ 9 lines.
    let figure = lines.iter().position(|l| l.image == Some(0)).unwrap();
    assert_eq!(lines[figure].image_lines, 9);
    assert!(
        lines[figure + 1..figure + 9]
            .iter()
            .all(|l| l.runs.is_empty() && l.image.is_none())
    );
    assert_eq!(text[figure + 9], "Abb.|1");
    // Quote indents 1.5 em; scripture is bold.
    let quote = lines
        .iter()
        .position(|l| l.runs.first().is_some_and(|r| r.text == "Ein"))
        .unwrap();
    assert!((lines[quote].runs[0].x - 1.5 * em).abs() < 1.0);
    let scripture = lines
        .iter()
        .position(|l| l.runs.first().is_some_and(|r| r.text == "14"))
        .unwrap();
    assert!(
        lines[scripture]
            .runs
            .iter()
            .all(|r| r.style & STYLE_BOLD != 0)
    );
}

#[test]
fn heading_references_become_links() {
    use gramma_core::reference::book_by_osis;
    use gramma_core::typeset::layout::{layout_verses, link_heading_references};
    let m = measure();
    let verses = [
        (1u16, "Im Anfang schuf Gott die Himmel und die Erde."),
        (2, "Die Erde aber war wüst."),
    ];
    let headings = [
        (1u16, 1u8, "Der erste Tag"),
        (1, 2, "Ps 104,2; Jes 45,7; 2Kor 4,6"),
    ];
    let mut lines = layout_verses(
        &verses,
        &[],
        &headings,
        &m,
        None,
        30 * m.units_per_em() as i64,
    );
    let refs = link_heading_references(&mut lines, book_by_osis("Gen"));
    assert_eq!(refs, vec!["Ps.104.2", "Isa.45.7", "2Cor.4.6"]);
    let linked: Vec<(String, u32)> = lines
        .iter()
        .flat_map(|l| l.runs.iter())
        .filter_map(|r| r.link.map(|i| (r.text.clone(), i)))
        .collect();
    assert_eq!(
        linked,
        vec![
            ("Ps".to_string(), 0),
            ("104,2;".to_string(), 0),
            ("Jes".to_string(), 1),
            ("45,7;".to_string(), 1),
            ("2Kor".to_string(), 2),
            ("4,6".to_string(), 2)
        ]
    );
    // The title heading and the verse words carry no link.
    assert!(
        lines
            .iter()
            .flat_map(|l| l.runs.iter())
            .filter(|r| r.heading_level == 1)
            .all(|r| r.link.is_none())
    );
}
