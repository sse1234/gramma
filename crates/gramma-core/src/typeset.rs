//! Optimal paragraph breaking after Knuth & Plass, "Breaking Paragraphs
//! into Lines" (Software—Practice and Experience, 1981) — the algorithm at
//! the heart of TeX, implemented here from the paper (see ADR 0002).
//!
//! Content is modeled as the paper's box/glue/penalty items in integer
//! `Scaled` units; the breaker finds the breakpoint sequence minimizing
//! total demerits via dynamic programming over feasible breakpoints.
//! Widths are integers and cost arithmetic uses only IEEE 754 basic
//! operations, so results are identical on every platform — the foundation
//! of the "same words per line everywhere" requirement.
//!
//! Three passes mirror TeX's behavior: the configured tolerance first, then
//! a permissive tolerance, then a last resort permitting overfull lines, so
//! well-formed paragraphs always break.

pub mod paragraph;

/// Fixed-point width unit; the shaping layer defines its physical meaning.
pub type Scaled = i64;

/// Penalties at or above this value forbid a break.
pub const INFINITE_PENALTY: i32 = 10_000;
/// This penalty value forces a break.
pub const FORCED_BREAK: i32 = -10_000;
/// Effectively infinite glue stretch (paragraph-final fill).
pub const INFINITE_GLUE: Scaled = 1 << 40;

const INF_BAD: f64 = 10_000.0;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Item {
    /// Unbreakable content of fixed width (a word or word fragment).
    Box { width: Scaled },
    /// Stretchable/shrinkable space; a legal breakpoint when it follows a box.
    Glue {
        width: Scaled,
        stretch: Scaled,
        shrink: Scaled,
    },
    /// An explicit break opportunity; `width` is added to the line only when
    /// the break is taken (e.g. a hyphen), `flagged` marks hyphen breaks.
    Penalty {
        width: Scaled,
        penalty: i32,
        flagged: bool,
    },
}

/// Breaking parameters. Defaults follow plain TeX.
#[derive(Debug, Clone, PartialEq)]
pub struct Params {
    pub line_width: Scaled,
    /// Badness threshold for feasible lines (TeX `\tolerance`).
    pub tolerance: f64,
    /// Added to every line's badness before squaring (TeX `\linepenalty`).
    pub line_penalty: f64,
    /// Demerits for adjacent lines of clashing tightness (TeX `\adjdemerits`).
    pub adj_demerits: f64,
    /// Demerits for consecutive hyphenated lines (TeX `\doublehyphendemerits`).
    pub double_hyphen_demerits: f64,
}

impl Params {
    pub fn new(line_width: Scaled) -> Self {
        Params {
            line_width,
            tolerance: 200.0,
            line_penalty: 10.0,
            adj_demerits: 10_000.0,
            double_hyphen_demerits: 10_000.0,
        }
    }
}

/// One line of the solution: items `start..end`, broken at item `end`, to be
/// set with adjustment ratio `ratio` (negative = shrink; below -1 the line
/// is overfull).
#[derive(Debug, Clone, PartialEq)]
pub struct Line {
    pub start: usize,
    pub end: usize,
    pub ratio: f64,
}

#[derive(Debug, Clone, PartialEq)]
pub struct BreakResult {
    pub lines: Vec<Line>,
    pub demerits: f64,
}

#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum BreakError {
    #[error("paragraph must end with a forced break; call finish_paragraph")]
    Unterminated,
    #[error("no feasible line breaking found")]
    NoBreaks,
}

/// Append TeX's paragraph-final sequence: an unbreakable transition into
/// infinitely stretchable fill glue, then a forced break.
pub fn finish_paragraph(items: &mut Vec<Item>) {
    items.push(Item::Penalty {
        width: 0,
        penalty: INFINITE_PENALTY,
        flagged: false,
    });
    items.push(Item::Glue {
        width: 0,
        stretch: INFINITE_GLUE,
        shrink: 0,
    });
    items.push(Item::Penalty {
        width: 0,
        penalty: FORCED_BREAK,
        flagged: false,
    });
}

pub fn break_lines(items: &[Item], params: &Params) -> Result<BreakResult, BreakError> {
    match items.last() {
        Some(Item::Penalty { penalty, .. }) if *penalty == FORCED_BREAK => {}
        _ => return Err(BreakError::Unterminated),
    }
    let passes = [(params.tolerance, false), (INF_BAD, false), (INF_BAD, true)];
    for (tolerance, allow_overfull) in passes {
        if let Some(result) = break_pass(items, params, tolerance, allow_overfull) {
            return Ok(result);
        }
    }
    Err(BreakError::NoBreaks)
}

struct Node {
    /// First item of the line that begins after this breakpoint.
    start: usize,
    /// Item index broken at (`usize::MAX` for the root).
    brk: usize,
    fitness: i32,
    flagged: bool,
    total: f64,
    ratio: f64,
    prev: usize,
}

fn break_pass(
    items: &[Item],
    params: &Params,
    tolerance: f64,
    allow_overfull: bool,
) -> Option<BreakResult> {
    let n = items.len();
    // Prefix sums over items[0..i]: width (boxes and glue), stretch, shrink.
    let mut tw = vec![0i64; n + 1];
    let mut ty = vec![0i64; n + 1];
    let mut tz = vec![0i64; n + 1];
    for (i, item) in items.iter().enumerate() {
        let (w, y, z) = match *item {
            Item::Box { width } => (width, 0, 0),
            Item::Glue {
                width,
                stretch,
                shrink,
            } => (width, stretch, shrink),
            Item::Penalty { .. } => (0, 0, 0),
        };
        tw[i + 1] = tw[i] + w;
        ty[i + 1] = ty[i] + y;
        tz[i + 1] = tz[i] + z;
    }

    let root = Node {
        start: 0,
        brk: usize::MAX,
        fitness: 1,
        flagged: false,
        total: 0.0,
        ratio: 0.0,
        prev: usize::MAX,
    };
    let mut arena = vec![root];
    let mut active: Vec<usize> = vec![0];
    let mut finals: Vec<usize> = Vec::new();

    for b in 0..n {
        if !is_legal_break(items, b) {
            continue;
        }
        let (pen, pen_width, flagged) = match items[b] {
            Item::Penalty {
                width,
                penalty,
                flagged,
            } => (penalty, width, flagged),
            _ => (0, 0, false),
        };
        let forced = pen == FORCED_BREAK;

        // Best candidate per fitness class: (total demerits, prev node, ratio).
        let mut best: [Option<(f64, usize, f64)>; 4] = [None; 4];
        let mut survivors = Vec::with_capacity(active.len());
        for &ai in &active {
            let a = &arena[ai];
            let l = tw[b] - tw[a.start] + pen_width;
            let y = ty[b] - ty[a.start];
            let z = tz[b] - tz[a.start];
            let slack = params.line_width - l;
            let r = if slack > 0 {
                if y > 0 {
                    slack as f64 / y as f64
                } else {
                    f64::INFINITY
                }
            } else if slack < 0 {
                if z > 0 {
                    slack as f64 / z as f64
                } else {
                    f64::NEG_INFINITY
                }
            } else {
                0.0
            };
            let overfull = r < -1.0;
            if !overfull && !forced {
                survivors.push(ai);
            }
            let feasible = !overfull || allow_overfull;
            if !feasible {
                continue;
            }
            let bad = if overfull {
                INF_BAD
            } else {
                (100.0 * r.abs().powi(3)).min(INF_BAD)
            };
            if bad > tolerance && !forced {
                continue;
            }
            let base = (params.line_penalty + bad).powi(2);
            let mut d = if forced {
                base
            } else if pen >= 0 {
                base + (pen as f64).powi(2)
            } else {
                base - (pen as f64).powi(2)
            };
            if flagged && a.flagged {
                d += params.double_hyphen_demerits;
            }
            let f = fitness(r);
            if (f - a.fitness).abs() > 1 {
                d += params.adj_demerits;
            }
            let total = a.total + d;
            let slot = &mut best[f as usize];
            if slot.is_none_or(|(t, _, _)| total < t) {
                *slot = Some((total, ai, r));
            }
        }
        active = survivors;

        let start = line_start_after(items, b);
        for (f, slot) in best.iter().enumerate() {
            if let Some((total, prev, ratio)) = *slot {
                let idx = arena.len();
                arena.push(Node {
                    start,
                    brk: b,
                    fitness: f as i32,
                    flagged,
                    total,
                    ratio,
                    prev,
                });
                if b == n - 1 {
                    finals.push(idx);
                } else {
                    active.push(idx);
                }
            }
        }
        if active.is_empty() && finals.is_empty() {
            return None;
        }
    }

    let best_final = finals
        .into_iter()
        .min_by(|&a, &b| arena[a].total.partial_cmp(&arena[b].total).unwrap())?;
    let mut chain = Vec::new();
    let mut cur = best_final;
    while arena[cur].brk != usize::MAX {
        chain.push(cur);
        cur = arena[cur].prev;
    }
    chain.reverse();
    let mut lines = Vec::with_capacity(chain.len());
    let mut start = 0usize;
    for idx in chain {
        let node = &arena[idx];
        lines.push(Line {
            start,
            end: node.brk,
            ratio: node.ratio,
        });
        start = node.start;
    }
    Some(BreakResult {
        lines,
        demerits: arena[best_final].total,
    })
}

fn is_legal_break(items: &[Item], b: usize) -> bool {
    match items[b] {
        Item::Glue { .. } => b > 0 && matches!(items[b - 1], Item::Box { .. }),
        Item::Penalty { penalty, .. } => penalty < INFINITE_PENALTY,
        Item::Box { .. } => false,
    }
}

/// After a break, glue and non-forced penalties are discarded up to the next
/// box (or a forced break).
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

/// Fitness classes: 0 tight, 1 decent, 2 loose, 3 very loose.
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
