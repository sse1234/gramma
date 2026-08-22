//! Tests for the Knuth–Plass line breaker.
//!
//! The `spec` module below is an independent, direct transcription of the
//! cost model from Knuth & Plass, "Breaking Paragraphs into Lines" (1981),
//! evaluated by brute force over all feasible breakpoint sequences. The
//! production algorithm must always find the same optimum.

use gramma_core::typeset::{
    BreakResult, FORCED_BREAK, INFINITE_PENALTY, Item, Params, Scaled, break_lines,
    finish_paragraph,
};

const U: Scaled = 1000;

fn word(w: Scaled) -> Item {
    Item::Box { width: w * U }
}

fn space() -> Item {
    Item::Glue {
        width: 4 * U,
        stretch: 2 * U,
        shrink: U,
    }
}

fn words(widths: &[Scaled]) -> Vec<Item> {
    let mut items = Vec::new();
    for (i, &w) in widths.iter().enumerate() {
        if i > 0 {
            items.push(space());
        }
        items.push(word(w));
    }
    finish_paragraph(&mut items);
    items
}

fn params(line_width: Scaled) -> Params {
    Params::new(line_width * U)
}

fn break_indices(result: &BreakResult) -> Vec<usize> {
    result.lines.iter().map(|l| l.end).collect()
}

#[test]
fn short_paragraph_is_a_single_line() {
    let items = words(&[10, 10, 10]);
    let result = break_lines(&items, &params(60)).unwrap();
    assert_eq!(result.lines.len(), 1);
    assert_eq!(result.lines[0].start, 0);
    assert_eq!(result.lines[0].end, items.len() - 1);
}

#[test]
fn equal_words_break_at_the_exact_fit() {
    // Three words of 10 plus two spaces of 4 measure exactly 38.
    let items = words(&[10, 10, 10, 10, 10, 10]);
    let result = break_lines(&items, &params(38)).unwrap();
    assert_eq!(result.lines.len(), 2);
    // items: B0 G1 B2 G3 B4 G5 B6 G7 B8 G9 B10 …finish
    assert_eq!(break_indices(&result)[0], 5);
    assert!(result.lines[0].ratio.abs() < 1e-9);
    assert_eq!(result.lines[1].start, 6);
}

#[test]
fn glue_after_penalty_is_not_a_legal_break() {
    // An INFINITE_PENALTY before a space forbids breaking at that space
    // (a glue is a legal break only when preceded by a box).
    let mut items = vec![
        word(10),
        space(),
        word(10),
        Item::Penalty {
            width: 0,
            penalty: INFINITE_PENALTY,
            flagged: false,
        },
        space(),
        word(10),
    ];
    finish_paragraph(&mut items);
    let result = break_lines(&items, &params(24)).unwrap();
    assert!(
        !break_indices(&result).contains(&4),
        "must not break at the protected space: {result:?}"
    );
}

#[test]
fn forced_break_ends_a_line_exactly_there() {
    let mut items = vec![
        word(10),
        Item::Penalty {
            width: 0,
            penalty: FORCED_BREAK,
            flagged: false,
        },
        word(10),
        space(),
        word(10),
    ];
    finish_paragraph(&mut items);
    let result = break_lines(&items, &params(30)).unwrap();
    assert_eq!(break_indices(&result)[0], 1);
}

#[test]
fn hyphenation_point_is_used_when_it_fits() {
    // "1010-10 10" with measure 26: breaking at the flagged penalty of
    // width 2 gives 10+4+10+2 = 26 exactly; any other first line is
    // terrible.
    let mut items = vec![
        word(10),
        space(),
        word(10),
        Item::Penalty {
            width: 2 * U,
            penalty: 50,
            flagged: true,
        },
        word(10),
        space(),
        word(10),
    ];
    finish_paragraph(&mut items);
    let result = break_lines(&items, &params(26)).unwrap();
    assert_eq!(break_indices(&result)[0], 3);
    assert!(result.lines[0].ratio.abs() < 1e-9);
    // The next line starts at the box after the hyphen.
    assert_eq!(result.lines[1].start, 4);
}

#[test]
fn reported_lines_are_contiguous_and_end_at_the_final_forced_break() {
    let items = words(&[8, 12, 6, 9, 11, 7, 10, 5, 9]);
    let result = break_lines(&items, &params(30)).unwrap();
    assert_eq!(result.lines.first().unwrap().start, 0);
    for pair in result.lines.windows(2) {
        assert!(pair[0].end < pair[1].start);
        assert!(pair[1].start <= pair[1].end);
    }
    assert_eq!(result.lines.last().unwrap().end, items.len() - 1);
}

#[test]
fn unterminated_paragraph_is_rejected() {
    let items = vec![word(10), space(), word(10)];
    assert!(break_lines(&items, &params(30)).is_err());
}

#[test]
fn oversized_box_still_breaks_with_overfull_line() {
    let items = words(&[50, 10, 10]);
    let result = break_lines(&items, &params(30)).unwrap();
    assert!(!result.lines.is_empty());
    assert!(
        result.lines.iter().any(|l| l.ratio < -1.0),
        "expected an overfull line: {result:?}"
    );
}

#[test]
fn golden_break_positions_are_stable_across_platforms() {
    // Fixed pseudo-paragraph; the expected indices double as the
    // cross-platform determinism check because CI runs them on Linux.
    let widths = [7, 11, 5, 9, 13, 6, 8, 10, 4, 12, 9, 7, 11, 5, 8];
    let items = words(&widths);
    let p = params(34);
    let result = break_lines(&items, &p).unwrap();
    let optimum = spec::brute_force_optimum(&items, &p, p.tolerance)
        .or_else(|| spec::brute_force_optimum(&items, &p, 10_000.0))
        .unwrap();
    assert!((result.demerits - optimum).abs() < 1e-6);
    assert_eq!(break_indices(&result), vec![5, 11, 17, 23, 31]);
}

// ---------------------------------------------------------------------------
// Executable specification: brute force over the 1981 paper's cost model.
// ---------------------------------------------------------------------------

mod spec {
    use super::*;

    const INF_BAD: f64 = 10_000.0;

    fn is_legal_break(items: &[Item], b: usize) -> bool {
        match items[b] {
            Item::Glue { .. } => b > 0 && matches!(items[b - 1], Item::Box { .. }),
            Item::Penalty { penalty, .. } => penalty < INFINITE_PENALTY,
            Item::Box { .. } => false,
        }
    }

    fn line_start_after(items: &[Item], b: usize) -> usize {
        let mut j = b + 1;
        while j < items.len() {
            match items[j] {
                Item::Box { .. } => break,
                Item::Penalty { penalty, .. } if penalty == FORCED_BREAK => break,
                _ => j += 1,
            }
        }
        j
    }

    fn ratio(items: &[Item], line_width: Scaled, start: usize, b: usize) -> f64 {
        let (mut l, mut y, mut z) = (0i64, 0i64, 0i64);
        for item in &items[start..b] {
            match *item {
                Item::Box { width } => l += width,
                Item::Glue {
                    width,
                    stretch,
                    shrink,
                } => {
                    l += width;
                    y += stretch;
                    z += shrink;
                }
                Item::Penalty { .. } => {}
            }
        }
        if let Item::Penalty { width, .. } = items[b] {
            l += width;
        }
        let slack = (line_width - l) as f64;
        if slack > 0.0 {
            if y > 0 {
                slack / y as f64
            } else {
                f64::INFINITY
            }
        } else if slack < 0.0 {
            if z > 0 {
                slack / z as f64
            } else {
                f64::NEG_INFINITY
            }
        } else {
            0.0
        }
    }

    fn badness(r: f64) -> f64 {
        if r < -1.0 {
            INF_BAD
        } else {
            (100.0 * r.abs().powi(3)).min(INF_BAD)
        }
    }

    fn fitness(r: f64) -> i32 {
        if r < -0.5 {
            0
        } else if r <= 0.5 {
            1
        } else if r <= 1.0 {
            2
        } else {
            3
        }
    }

    /// Total demerits of one breakpoint sequence, or None if infeasible.
    fn total_demerits(
        items: &[Item],
        params: &Params,
        tolerance: f64,
        breaks: &[usize],
    ) -> Option<f64> {
        let mut total = 0.0;
        let mut start = 0usize;
        let mut prev_flagged = false;
        let mut prev_fitness = 1;
        for &b in breaks {
            let (penalty, flagged) = match items[b] {
                Item::Penalty {
                    penalty, flagged, ..
                } => (penalty, flagged),
                _ => (0, false),
            };
            let forced = penalty == FORCED_BREAK;
            let r = ratio(items, params.line_width, start, b);
            if r < -1.0 {
                return None;
            }
            let bad = badness(r);
            if bad > tolerance && !forced {
                return None;
            }
            let base = (params.line_penalty + bad).powi(2);
            let mut d = if forced {
                base
            } else if penalty >= 0 {
                base + (penalty as f64).powi(2)
            } else {
                base - (penalty as f64).powi(2)
            };
            if flagged && prev_flagged {
                d += params.double_hyphen_demerits;
            }
            let f = fitness(r);
            if (f - prev_fitness).abs() > 1 {
                d += params.adj_demerits;
            }
            total += d;
            prev_flagged = flagged;
            prev_fitness = f;
            start = line_start_after(items, b);
        }
        Some(total)
    }

    /// Minimum total demerits over all feasible breakpoint sequences.
    pub fn brute_force_optimum(items: &[Item], params: &Params, tolerance: f64) -> Option<f64> {
        let last = items.len() - 1;
        let candidates: Vec<usize> = (0..last).filter(|&b| is_legal_break(items, b)).collect();
        let mut best: Option<f64> = None;
        for mask in 0u32..(1 << candidates.len()) {
            let mut breaks: Vec<usize> = candidates
                .iter()
                .enumerate()
                .filter(|(i, _)| mask & (1 << i) != 0)
                .map(|(_, &b)| b)
                .collect();
            breaks.push(last);
            if let Some(d) = total_demerits(items, params, tolerance, &breaks)
                && best.is_none_or(|b| d < b)
            {
                best = Some(d);
            }
        }
        best
    }
}

#[test]
fn matches_brute_force_on_a_ragged_paragraph() {
    let items = words(&[9, 5, 12, 7, 10, 6, 11, 8, 5, 9, 12, 6]);
    let mut p = params(32);
    p.tolerance = 10_000.0;
    let result = break_lines(&items, &p).unwrap();
    let optimum = spec::brute_force_optimum(&items, &p, p.tolerance).unwrap();
    assert!((result.demerits - optimum).abs() < 1e-6);
}

proptest::proptest! {
    #![proptest_config(proptest::prelude::ProptestConfig::with_cases(96))]

    #[test]
    fn always_matches_the_brute_force_optimum(
        widths in proptest::collection::vec(3i64..14, 2..7),
        hyphen_after in proptest::collection::vec(proptest::bool::ANY, 2..7),
        line_width in 18i64..40,
    ) {
        let mut items = Vec::new();
        for (i, &w) in widths.iter().enumerate() {
            if i > 0 {
                items.push(space());
            }
            items.push(word(w));
            if *hyphen_after.get(i).unwrap_or(&false) && i + 1 < widths.len() {
                items.push(Item::Penalty { width: U, penalty: 50, flagged: true });
            }
        }
        finish_paragraph(&mut items);
        let mut p = params(line_width);
        p.tolerance = 10_000.0;
        p.adj_demerits = 10_000.0;
        p.double_hyphen_demerits = 10_000.0;
        let result = break_lines(&items, &p).unwrap();
        let optimum = spec::brute_force_optimum(&items, &p, p.tolerance);
        proptest::prop_assert!(optimum.is_some(), "spec found no feasible breaking");
        proptest::prop_assert!(
            (result.demerits - optimum.unwrap()).abs() < 1e-6,
            "algorithm: {} vs brute force: {}", result.demerits, optimum.unwrap()
        );
    }
}
