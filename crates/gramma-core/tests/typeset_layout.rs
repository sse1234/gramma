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
    layout_with_notes(verses, &[], ems)
}

fn layout_with_notes(verses: &[(u16, &str)], notes: &[(u16, u32)], ems: i64) -> Vec<LineOut> {
    let m = measure();
    let width = ems * m.units_per_em() as i64;
    layout_verses(verses, notes, &[], &m, Some(&german()), width)
}

fn layout_with_headings(
    verses: &[(u16, &str)],
    headings: &[(u16, u8, &str)],
    ems: i64,
) -> Vec<LineOut> {
    let m = measure();
    let width = ems * m.units_per_em() as i64;
    layout_verses(verses, &[], headings, &m, Some(&german()), width)
}

fn line_text(line: &LineOut) -> String {
    line.runs
        .iter()
        .map(|r| r.text.as_str())
        .collect::<Vec<_>>()
        .join(" ")
}

#[test]
fn every_bundled_face_parses_and_literata_really_differs() {
    let book: &[u8] = FONT;
    let plus: &[u8] = include_bytes!(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../../app/fonts/GentiumPlus-Regular.ttf"
    ));
    let literata: &[u8] = include_bytes!(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../../app/fonts/Literata-Regular.ttf"
    ));
    let faces = [book, plus, literata].map(|data| {
        let m = FontMeasure::new(data).expect("bundled face parses");
        assert!(m.text_width("Wort") > 0);
        m
    });
    let width = |m: &FontMeasure, s: &str| m.text_width(s) as f64 / m.units_per_em() as f64;
    let sample = "Am Anfang schuf Gott Himmel und Erde";
    assert!(
        (width(&faces[0], sample) - width(&faces[2], sample)).abs() > 0.3,
        "Literata's metrics must differ visibly from Gentium's"
    );
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

#[test]
fn runs_carry_their_verse() {
    let lines = layout(&[(1, GEN_1_1), (2, GEN_1_2)], 22);
    let verses: Vec<u16> = lines
        .iter()
        .flat_map(|l| &l.runs)
        .map(|r| r.verse)
        .collect();
    assert!(verses.contains(&1) && verses.contains(&2));
    let mut last = 0u16;
    for v in verses {
        assert!(v >= last, "verse tags must be monotonic");
        last = v;
    }
}

#[test]
fn note_anchors_become_inline_lettered_markers() {
    // Two notes in verse 1: after "Anfang" (offset 9) and at the verse end.
    let notes = [(1u16, 9u32), (1, GEN_1_1.len() as u32)];
    let lines = layout_with_notes(&[(1, GEN_1_1)], &notes, 22);
    let markers: Vec<_> = lines
        .iter()
        .flat_map(|l| &l.runs)
        .filter(|r| r.note_marker)
        .collect();
    assert_eq!(markers.len(), 2);
    assert_eq!(markers[0].text, "a");
    assert_eq!(markers[1].text, "b");
    assert!(markers.iter().all(|m| m.verse == 1));
    // The first marker follows immediately after the word "Anfang".
    let runs: Vec<_> = lines.iter().flat_map(|l| &l.runs).collect();
    let marker_pos = runs.iter().position(|r| r.note_marker).unwrap();
    assert_eq!(runs[marker_pos - 1].text, "Anfang");
    let word = &runs[marker_pos - 1];
    assert!(
        (word.x + word.width - runs[marker_pos].x).abs() < 1e-6,
        "marker must sit flush after its word"
    );
}

#[test]
fn markers_never_start_a_line() {
    // Force narrow measures; the infinite penalty must keep each marker on
    // its word's line.
    let notes = [(1u16, 9u32), (2, 20u32)];
    for ems in [10, 12, 14, 16] {
        let lines = layout_with_notes(&[(1, GEN_1_1), (2, GEN_1_2)], &notes, ems);
        for line in &lines {
            if let Some(first) = line.runs.first() {
                assert!(!first.note_marker, "marker stranded at line start");
            }
        }
    }
}

#[test]
fn headings_become_their_own_lines_with_spacing() {
    let headings = [(2u16, 1u8, "Der siebte Tag")];
    let lines = layout_with_headings(&[(1, GEN_1_1), (2, GEN_1_2)], &headings, 22);
    let spacer = lines
        .iter()
        .position(|l| l.runs.is_empty())
        .expect("a spacing line before the heading group");
    let heading_line = &lines[spacer + 1];
    assert!(heading_line.runs.iter().all(|r| r.heading_level == 1));
    let text: Vec<_> = heading_line.runs.iter().map(|r| r.text.as_str()).collect();
    assert_eq!(text.join(" "), "Der siebte Tag");
    assert!(
        heading_line.runs.iter().all(|r| r.verse == 2),
        "heading lines anchor to the following verse"
    );
    // Verse 2's paragraph starts after the heading.
    let after = &lines[spacer + 2];
    assert!(after.runs.iter().any(|r| r.verse_number && r.text == "2"));
}

#[test]
fn heading_at_the_top_gets_no_leading_spacer() {
    let headings = [(1u16, 1u8, "Die Schöpfung"), (1, 2, "Der Anfang")];
    let lines = layout_with_headings(&[(1, GEN_1_1)], &headings, 22);
    assert!(!lines[0].runs.is_empty(), "no spacer at the very top");
    assert_eq!(lines[0].runs[0].heading_level, 1);
    assert_eq!(lines[1].runs[0].heading_level, 2);
    assert!(lines[2].runs.iter().any(|r| r.verse_number));
}

#[test]
fn body_runs_carry_no_heading_level() {
    let lines = layout(&[(1, GEN_1_1)], 22);
    assert!(
        lines
            .iter()
            .flat_map(|l| &l.runs)
            .all(|r| r.heading_level == 0)
    );
}

#[test]
fn no_grotesque_lines_across_fonts_and_measures() {
    // Hebrews 10, Elberfelder 1905 (public domain): the chapter whose
    // whole-paragraph breaking once produced a first line of two words
    // stretched across the full measure ("1 Denn da") and orphaned
    // hyphen fragments, whenever the tolerance passes escalated. Every
    // interior line must stay typographically sane at every measure, in
    // every bundled face.
    let fixture = include_str!("fixtures/heb10_elb1905.txt");
    let verses: Vec<(u16, &str)> = fixture
        .lines()
        .map(|l| {
            let (n, t) = l.split_once('|').unwrap();
            (n.parse().unwrap(), t)
        })
        .collect();
    let literata: &[u8] = include_bytes!(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../../app/fonts/Literata-Regular.ttf"
    ));
    let hyph = german();
    for (name, data) in [("Gentium", FONT), ("Literata", literata)] {
        let m = FontMeasure::new(data).unwrap();
        let (space, _, _) = m.space();
        for ems in 14..=30i64 {
            let width = ems * m.units_per_em() as i64;
            let lines = layout_verses(&verses, &[], &[], &m, Some(&hyph), width);
            for (i, line) in lines.iter().enumerate() {
                if line.runs.is_empty() || i + 1 == lines.len() {
                    continue;
                }
                let max_gap = line
                    .runs
                    .windows(2)
                    .map(|w| w[1].x - (w[0].x + w[0].width))
                    .fold(0.0f64, f64::max);
                // Narrow measures with long German compounds run
                // legitimately loose (a single space can carry ~2em); the
                // degenerate lines this guards against gapped at 5em+.
                assert!(
                    max_gap <= 2.2 * m.units_per_em() as f64,
                    "{name} {ems}em line {i}: word gap {max_gap:.0} vs \
                     space {space}: {:?}",
                    line.runs.iter().map(|r| &r.text).collect::<Vec<_>>()
                );
                let edge = line.runs.last().map(|r| r.x + r.width).unwrap();
                assert!(
                    line.runs.len() > 1 || edge >= 0.5 * width as f64,
                    "{name} {ems}em line {i}: orphaned fragment {:?}",
                    line.runs.iter().map(|r| &r.text).collect::<Vec<_>>()
                );
            }
        }
    }
}

/// Word runs carry their byte offset within the verse (ADR 0023), and a
/// hyphenation split's second fragment keeps its own mid-word offset —
/// so annotation ranges resolve exactly even across line breaks.
#[test]
fn word_runs_carry_verse_offsets() {
    let verses = [(1u16, GEN_1_2)];
    let lines = layout(&verses, 14);
    let mut seen = Vec::new();
    for line in &lines {
        for run in &line.runs {
            if !run.verse_number && !run.note_marker {
                seen.push((run.offset as usize, run.text.clone()));
            }
        }
    }
    // Every unhyphenated run's text appears at its offset in the verse.
    for (offset, text) in &seen {
        let clean = text.trim_end_matches('-');
        assert!(
            GEN_1_2[*offset..].starts_with(clean)
                || GEN_1_2[*offset..].starts_with(&clean.replace('-', "")),
            "run {text:?} not at offset {offset}"
        );
    }
    // Offsets are strictly increasing within the verse.
    assert!(seen.windows(2).all(|w| w[0].0 < w[1].0), "{seen:?}");
}
