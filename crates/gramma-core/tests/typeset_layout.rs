use gramma_core::typeset::layout::{LineOut, layout_verses};
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

const GEN_1_1: &str = "Am Anfang schuf Gott Himmel und Erde.";
const GEN_1_2: &str = "Und die Erde war wüst und leer, und es war finster auf der Tiefe; und der Geist Gottes schwebte auf dem Wasser.";

fn layout(verses: &[(u16, &str)], ems: i64) -> Vec<LineOut> {
    let m = measure();
    let width = ems * m.units_per_em() as i64;
    layout_verses(verses, &m, Some(&german()), width)
}

fn line_text(line: &LineOut) -> String {
    line.runs
        .iter()
        .map(|r| r.text.as_str())
        .collect::<Vec<_>>()
        .join(" ")
}

#[test]
fn font_measures_real_advances() {
    let m = measure();
    assert!(m.units_per_em() >= 1000);
    let narrow = m.text_width("il");
    let wide = m.text_width("mw");
    assert!(narrow > 0);
    assert!(wide > narrow, "advance widths must differ by glyph");
    let (space, stretch, shrink) = m.space();
    assert!(space > 0 && stretch > 0 && shrink > 0);
    assert!(m.hyphen_width() > 0);
}

#[test]
fn verses_flow_into_justified_lines() {
    let lines = layout(&[(1, GEN_1_1), (2, GEN_1_2)], 22);
    assert!(lines.len() > 2, "expected several lines: {}", lines.len());
    let m = measure();
    let width = (22 * m.units_per_em() as i64) as f64;
    for line in &lines[..lines.len() - 1] {
        let last = line.runs.last().unwrap();
        let right_edge = last.x + last.width;
        assert!(
            (right_edge - width).abs() < 1.0,
            "justified line must be flush right: edge {right_edge} vs measure {width}"
        );
    }
}

#[test]
fn verse_numbers_are_marked_and_scaled() {
    let lines = layout(&[(1, GEN_1_1), (2, GEN_1_2)], 22);
    let m = measure();
    let numbers: Vec<_> = lines
        .iter()
        .flat_map(|l| &l.runs)
        .filter(|r| r.verse_number)
        .collect();
    assert_eq!(numbers.len(), 2);
    assert_eq!(numbers[0].text, "1");
    assert!(numbers[0].width < m.text_width("1") as f64);
}

#[test]
fn verse_number_is_never_stranded_at_line_end() {
    for ems in [14, 18, 22, 26, 30] {
        let lines = layout(&[(1, GEN_1_1), (2, GEN_1_2), (3, GEN_1_1)], ems);
        for line in &lines {
            assert!(
                !line.runs.last().unwrap().verse_number,
                "verse number stranded at line end ({ems}em): {:?}",
                line_text(line)
            );
        }
    }
}

#[test]
fn narrow_measure_produces_hyphenated_lines() {
    let lines = layout(&[(2, GEN_1_2)], 10);
    assert!(
        lines
            .iter()
            .any(|l| l.runs.last().is_some_and(|r| r.text.ends_with('-'))),
        "expected a hyphenated line: {:?}",
        lines.iter().map(line_text).collect::<Vec<_>>()
    );
}

#[test]
fn all_words_survive_layout() {
    let lines = layout(&[(1, GEN_1_1), (2, GEN_1_2)], 18);
    let rebuilt: String = lines
        .iter()
        .flat_map(|l| &l.runs)
        .filter(|r| !r.verse_number)
        .map(|r| r.text.replace('-', ""))
        .collect();
    let expected: String = format!("{GEN_1_1} {GEN_1_2}").split_whitespace().collect();
    assert_eq!(rebuilt.replace('-', ""), expected.replace('-', ""));
}

#[test]
fn runs_advance_monotonically() {
    let lines = layout(&[(1, GEN_1_1), (2, GEN_1_2)], 22);
    for line in &lines {
        let mut x = -1.0;
        for run in &line.runs {
            assert!(run.x > x, "runs must advance: {:?}", line_text(line));
            x = run.x + run.width;
        }
    }
}

#[test]
fn golden_first_lines_are_stable_across_platforms() {
    // Pinned layout of Luther's Genesis 1:1-2 at a 22em measure; identical
    // values on Linux CI prove cross-platform layout determinism with real
    // font shaping.
    let lines = layout(&[(1, GEN_1_1), (2, GEN_1_2)], 22);
    let texts: Vec<String> = lines.iter().map(line_text).collect();
    assert_eq!(
        texts,
        [
            "1 Am Anfang schuf Gott Himmel und Erde. 2 Und die",
            "Erde war wüst und leer, und es war finster auf der Tie-",
            "fe; und der Geist Gottes schwebte auf dem Wasser.",
        ],
        "golden layout changed"
    );
}
