use gramma_core::typeset::paragraph::{Paragraph, TextMeasure, build_paragraph};
use gramma_core::typeset::{BreakResult, Item, Params, Scaled, break_lines};
use hyphenation::{Language, Load, Standard};

const U: Scaled = 1000;

/// Every character one unit wide — printer's-fist typography for tests.
struct CharMeasure;

impl TextMeasure for CharMeasure {
    fn text_width(&self, text: &str) -> Scaled {
        text.chars().count() as Scaled * U
    }
    fn space(&self) -> (Scaled, Scaled, Scaled) {
        (U, U / 2, U / 3)
    }
    fn hyphen_width(&self) -> Scaled {
        U
    }
}

fn german() -> Standard {
    Standard::from_embedded(Language::German1996).unwrap()
}

fn box_texts<'a>(text: &'a str, para: &Paragraph) -> Vec<&'a str> {
    para.sources
        .iter()
        .flatten()
        .map(|r| &text[r.clone()])
        .collect()
}

fn render_lines(text: &str, para: &Paragraph, result: &BreakResult) -> Vec<String> {
    result
        .lines
        .iter()
        .map(|line| {
            let mut s = String::new();
            for i in line.start..line.end {
                match para.items[i] {
                    Item::Box { .. } => {
                        s.push_str(&text[para.sources[i].clone().unwrap()]);
                    }
                    Item::Glue { .. } => s.push(' '),
                    Item::Penalty { .. } => {}
                }
            }
            if let Item::Penalty { flagged: true, .. } = para.items[line.end] {
                s.push('-');
            }
            s.trim().to_string()
        })
        .collect()
}

#[test]
fn words_become_boxes_separated_by_glue() {
    let text = "am Anfang";
    let para = build_paragraph(text, &CharMeasure, None);
    assert!(matches!(
        para.items[..3],
        [Item::Box { .. }, Item::Glue { .. }, Item::Box { .. }]
    ));
    assert_eq!(box_texts(text, &para), ["am", "Anfang"]);
    assert_eq!(para.items.len(), 3 + 3, "three finishing items expected");
}

#[test]
fn german_compound_is_hyphenated_at_pattern_points() {
    let text = "Silbentrennung";
    let para = build_paragraph(text, &CharMeasure, Some(&german()));
    let fragments = box_texts(text, &para);
    assert_eq!(fragments.concat(), text, "fragments must cover the word");
    assert_eq!(fragments, ["Sil", "ben", "tren", "nung"]);
}

#[test]
fn hyphenation_points_are_flagged_penalties_with_hyphen_width() {
    let text = "Silbentrennung";
    let para = build_paragraph(text, &CharMeasure, Some(&german()));
    let penalties: Vec<_> = para
        .items
        .iter()
        .filter(|i| matches!(i, Item::Penalty { flagged: true, .. }))
        .collect();
    assert_eq!(penalties.len(), 3);
    for p in penalties {
        assert_eq!(
            *p,
            Item::Penalty {
                width: U,
                penalty: 50,
                flagged: true
            }
        );
    }
}

#[test]
fn umlauts_survive_hyphenation() {
    let text = "Zeilenumbrüche";
    let para = build_paragraph(text, &CharMeasure, Some(&german()));
    let fragments = box_texts(text, &para);
    assert!(fragments.len() > 1, "expected hyphenation points");
    assert_eq!(fragments.concat(), text);
}

#[test]
fn german_sentence_breaks_with_hyphenation_at_narrow_measure() {
    let text = "Die Silbentrennung verbessert die Zeilenumbrüche im schmalen Satzspiegel erheblich";
    let para = build_paragraph(text, &CharMeasure, Some(&german()));
    let result = break_lines(&para.items, &Params::new(16 * U)).unwrap();
    let lines = render_lines(text, &para, &result);
    assert!(
        lines.iter().any(|l| l.ends_with('-')),
        "expected at least one hyphenated line: {lines:?}"
    );
    for line in &lines {
        assert!(
            line.chars().count() <= 17,
            "line exceeds the measure: {line:?}"
        );
    }
    assert_eq!(
        lines.concat().replace(['-', ' '], ""),
        text.replace(' ', "")
    );
}

#[test]
fn golden_german_paragraph_layout() {
    let text = "Am Anfang schuf Gott Himmel und Erde und die Erde war wüst und leer";
    let para = build_paragraph(text, &CharMeasure, Some(&german()));
    let result = break_lines(&para.items, &Params::new(20 * U)).unwrap();
    let lines = render_lines(text, &para, &result);
    assert_eq!(
        lines,
        [
            "Am Anfang schuf Gott",
            "Himmel und Erde und",
            "die Erde war wüst und",
            "leer",
        ]
    );
}
