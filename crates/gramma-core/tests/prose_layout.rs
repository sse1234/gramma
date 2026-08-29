//! Prose typesetting (ADR 0018): commentary entries go through the same
//! Knuth–Plass engine as the Bible text — label set like a verse number,
//! heading line, justified paragraphs, and reference words carrying a
//! link index so the painted text stays tappable (ADR 0016).

use gramma_core::typeset::layout::{LineOut, ProseParagraph, ProseSetting, RunOut, layout_prose};
use gramma_core::typeset::paragraph::TextMeasure;
use gramma_core::typeset::shape::FontMeasure;
use hyphenation::{Language, Load, Standard};

const FONT: &[u8] = include_bytes!(concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/../../app/fonts/GentiumBookPlus-Regular.ttf"
));

fn measure() -> FontMeasure<'static> {
    FontMeasure::new(FONT).expect("font loads")
}

fn german() -> Standard {
    Standard::from_embedded(Language::German1996).unwrap()
}

fn runs(lines: &[LineOut]) -> Vec<&RunOut> {
    lines.iter().flat_map(|l| l.runs.iter()).collect()
}

#[test]
fn entry_with_heading_label_links_and_paragraphs() {
    let p1 = "Alles beginnt mit dem Wort, vgl. Joh 1,1. Danach geht die \
              Auslegung ausführlich weiter und braucht mehrere Zeilen im Satz.";
    let start = p1.find("Joh").unwrap();
    let links = vec![(start, start + "Joh 1,1".len(), 0u32)];
    let paragraphs = [
        ProseParagraph { text: p1, links },
        ProseParagraph {
            text: "Zweiter Absatz der Auslegung.",
            links: Vec::new(),
        },
    ];
    let m = measure();
    let width = 22 * m.units_per_em() as i64;
    let lines = layout_prose(
        Some("19-21"),
        Some("Gott nahen"),
        &paragraphs,
        19,
        &m,
        Some(&german()),
        ProseSetting {
            justify: true,
            line_width: width,
        },
    );

    // The heading line: label first, set like a verse number, then the
    // heading words at level 1.
    let first = &lines[0];
    assert!(first.runs[0].verse_number);
    assert_eq!(first.runs[0].text, "19-21");
    assert_eq!(first.runs[1].heading_level, 1);
    assert_eq!(first.runs[1].text, "Gott");
    assert!(runs(&lines).iter().all(|r| r.verse == 19));

    // The reference words carry the link index; ordinary words do not.
    let linked: Vec<_> = runs(&lines)
        .into_iter()
        .filter(|r| r.link == Some(0))
        .collect();
    let joined = linked
        .iter()
        .map(|r| r.text.as_str())
        .collect::<Vec<_>>()
        .join(" ");
    assert!(joined.contains("Joh"), "link words: {joined}");
    assert!(
        runs(&lines)
            .iter()
            .any(|r| r.link.is_none() && r.text.contains("Alles")),
        "plain words carry no link"
    );

    // Exactly one blank line: between the two paragraphs (the heading sits
    // directly above its body, as in chapters).
    let blanks = lines.iter().filter(|l| l.runs.is_empty()).count();
    assert_eq!(blanks, 1);
    assert!(
        !lines[1].runs.is_empty(),
        "body follows the heading directly"
    );

    // Justified: no line paints past the measure.
    for line in &lines {
        if let Some(last) = line.runs.last() {
            assert!(last.x + last.width <= width as f64 + 1.0);
        }
    }
}

#[test]
fn ragged_prose_keeps_natural_spaces_on_every_line() {
    // Dictionary entries (ADR 0026): narrow columns and dense special
    // characters read better side-aligned — every space stays at its
    // natural width, and no line paints past the measure.
    let text = "Zorn Gnade Treue Wahrheit Erbarmen Segen Friede \
                Hoffnung Geduld Demut Milde Langmut";
    let paragraphs = [ProseParagraph {
        text,
        links: Vec::new(),
    }];
    let m = measure();
    let width = 10 * m.units_per_em() as i64;
    let (space, _, _) = m.space();

    let ragged = layout_prose(
        None,
        None,
        &paragraphs,
        0,
        &m,
        None,
        ProseSetting {
            justify: false,
            line_width: width,
        },
    );
    assert!(ragged.len() > 1, "the narrow measure breaks into lines");
    for line in &ragged {
        for pair in line.runs.windows(2) {
            let gap = pair[1].x - (pair[0].x + pair[0].width);
            assert!(
                (gap - space as f64).abs() < 0.5,
                "ragged gap stays natural, got {gap} vs {space}"
            );
        }
        if let Some(last) = line.runs.last() {
            assert!(last.x + last.width <= width as f64 + 1.0);
        }
    }

    // The justified engine, for contrast, stretches gaps to the measure.
    let justified = layout_prose(
        None,
        None,
        &paragraphs,
        0,
        &m,
        None,
        ProseSetting {
            justify: true,
            line_width: width,
        },
    );
    let stretched = justified.iter().take(justified.len() - 1).any(|line| {
        line.runs
            .windows(2)
            .any(|p| p[1].x - (p[0].x + p[0].width) > space as f64 + 0.5)
    });
    assert!(stretched, "justification stretches at least one gap");
}

#[test]
fn label_without_heading_binds_to_the_first_word() {
    let paragraphs = [ProseParagraph {
        text: "Licht wird.",
        links: Vec::new(),
    }];
    let m = measure();
    let width = 22 * m.units_per_em() as i64;
    let lines = layout_prose(
        Some("3"),
        None,
        &paragraphs,
        3,
        &m,
        None,
        ProseSetting {
            justify: true,
            line_width: width,
        },
    );
    let first = &lines[0];
    assert!(first.runs[0].verse_number);
    assert_eq!(first.runs[0].text, "3");
    assert_eq!(first.runs[1].text, "Licht");
    assert_eq!(first.runs[1].heading_level, 0);
}
