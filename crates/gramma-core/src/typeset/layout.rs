//! Chapter layout: verses flow into one Knuth–Plass-broken paragraph whose
//! lines carry positioned text runs, ready to paint.
//!
//! Glue setting happens here: after the breaker chooses breakpoints, each
//! justified line's leftover slack is distributed over its spaces in
//! proportion to their stretch (or shrink), so painted lines end flush with
//! the measure using the same shaped widths the painter will use.

use hyphenation::Standard;

use super::paragraph::{HYPHEN_PENALTY, TextMeasure, hyphen_offsets};
use super::{INFINITE_PENALTY, Item, Params, Scaled, break_lines, finish_paragraph};

/// Verse numbers are set at this percentage of the text size; widths here
/// and the painter's font size must agree.
pub const VERSE_NUMBER_SCALE_PERCENT: i64 = 65;

#[derive(Debug, Clone, PartialEq)]
pub struct RunOut {
    pub text: String,
    /// Left edge in font units from the line start.
    pub x: f64,
    /// Shaped width of `text` in font units (already scaled for numbers).
    pub width: f64,
    pub verse_number: bool,
}

#[derive(Debug, Clone, PartialEq)]
pub struct LineOut {
    pub runs: Vec<RunOut>,
}

#[derive(Debug, Clone)]
struct BoxMeta {
    text: String,
    verse_number: bool,
}

/// Lay out verses as one flowing justified paragraph at `line_width` font
/// units.
pub fn layout_verses(
    verses: &[(u16, &str)],
    measure: &impl TextMeasure,
    hyphenator: Option<&Standard>,
    line_width: Scaled,
) -> Vec<LineOut> {
    let mut items: Vec<Item> = Vec::new();
    let mut meta: Vec<Option<BoxMeta>> = Vec::new();
    let (space_width, stretch, shrink) = measure.space();
    let space = Item::Glue {
        width: space_width,
        stretch,
        shrink,
    };
    let push = |items: &mut Vec<Item>, meta: &mut Vec<Option<BoxMeta>>, item, m| {
        items.push(item);
        meta.push(m);
    };

    for (number, text) in verses {
        if !items.is_empty() {
            push(&mut items, &mut meta, space, None);
        }
        let number = number.to_string();
        let number_width = measure.text_width(&number) * VERSE_NUMBER_SCALE_PERCENT / 100;
        push(
            &mut items,
            &mut meta,
            Item::Box {
                width: number_width,
            },
            Some(BoxMeta {
                text: number,
                verse_number: true,
            }),
        );
        // Never break between a verse number and its first word: an infinite
        // penalty makes the following glue an illegal breakpoint.
        push(
            &mut items,
            &mut meta,
            Item::Penalty {
                width: 0,
                penalty: INFINITE_PENALTY,
                flagged: false,
            },
            None,
        );
        push(&mut items, &mut meta, space, None);
        let mut first_word = true;
        for word in text.split_whitespace() {
            if !first_word {
                push(&mut items, &mut meta, space, None);
            }
            first_word = false;
            let breaks = hyphenator
                .map(|h| hyphen_offsets(word, h))
                .unwrap_or_default();
            let mut fragment_start = 0usize;
            for offset in breaks.iter().copied().chain([word.len()]) {
                if offset == fragment_start {
                    continue;
                }
                let fragment = &word[fragment_start..offset];
                push(
                    &mut items,
                    &mut meta,
                    Item::Box {
                        width: measure.text_width(fragment),
                    },
                    Some(BoxMeta {
                        text: fragment.to_string(),
                        verse_number: false,
                    }),
                );
                if offset < word.len() {
                    push(
                        &mut items,
                        &mut meta,
                        Item::Penalty {
                            width: measure.hyphen_width(),
                            penalty: HYPHEN_PENALTY,
                            flagged: true,
                        },
                        None,
                    );
                }
                fragment_start = offset;
            }
        }
    }
    finish_paragraph(&mut items);
    meta.resize(items.len(), None);

    let params = Params::new(line_width);
    let Ok(broken) = break_lines(&items, &params) else {
        return Vec::new();
    };

    let last_index = broken.lines.len() - 1;
    broken
        .lines
        .iter()
        .enumerate()
        .map(|(line_no, line)| {
            set_line(
                &items,
                &meta,
                measure,
                line.start,
                line.end,
                line_width,
                line_no == last_index,
            )
        })
        .collect()
}

/// Assemble a line's runs (merging word fragments not broken apart) and
/// distribute slack over its glue.
fn set_line(
    items: &[Item],
    meta: &[Option<BoxMeta>],
    measure: &impl TextMeasure,
    start: usize,
    end: usize,
    line_width: Scaled,
    is_last: bool,
) -> LineOut {
    enum Piece {
        Run {
            text: String,
            verse_number: bool,
        },
        Space {
            stretch: Scaled,
            shrink: Scaled,
            width: Scaled,
        },
    }
    let mut pieces: Vec<Piece> = Vec::new();
    for i in start..end {
        match items[i] {
            Item::Box { .. } => {
                let m = meta[i].as_ref().expect("box has meta");
                match pieces.last_mut() {
                    Some(Piece::Run { text, verse_number }) if !*verse_number => {
                        text.push_str(&m.text);
                    }
                    _ => pieces.push(Piece::Run {
                        text: m.text.clone(),
                        verse_number: m.verse_number,
                    }),
                }
            }
            Item::Glue {
                width,
                stretch,
                shrink,
            } => {
                if !pieces.is_empty() {
                    pieces.push(Piece::Space {
                        width,
                        stretch,
                        shrink,
                    });
                }
            }
            Item::Penalty { .. } => {}
        }
    }
    if let Item::Penalty { flagged: true, .. } = items[end]
        && let Some(Piece::Run { text, .. }) = pieces.last_mut()
    {
        text.push('-');
    }
    while matches!(pieces.last(), Some(Piece::Space { .. })) {
        pieces.pop();
    }

    let widths: Vec<f64> = pieces
        .iter()
        .map(|p| match p {
            Piece::Run { text, verse_number } => {
                let w = measure.text_width(text);
                if *verse_number {
                    (w * VERSE_NUMBER_SCALE_PERCENT / 100) as f64
                } else {
                    w as f64
                }
            }
            Piece::Space { width, .. } => *width as f64,
        })
        .collect();
    let natural: f64 = widths.iter().sum();
    let slack = line_width as f64 - natural;
    let total_stretch: f64 = pieces
        .iter()
        .filter_map(|p| match p {
            Piece::Space { stretch, .. } => Some(*stretch as f64),
            _ => None,
        })
        .sum();
    let total_shrink: f64 = pieces
        .iter()
        .filter_map(|p| match p {
            Piece::Space { shrink, .. } => Some(*shrink as f64),
            _ => None,
        })
        .sum();

    let mut runs = Vec::new();
    let mut x = 0.0f64;
    for (piece, width) in pieces.iter().zip(&widths) {
        match piece {
            Piece::Run { text, verse_number } => {
                runs.push(RunOut {
                    text: text.clone(),
                    x,
                    width: *width,
                    verse_number: *verse_number,
                });
                x += width;
            }
            Piece::Space {
                stretch, shrink, ..
            } => {
                let mut set = *width;
                if !is_last && slack > 0.0 && total_stretch > 0.0 {
                    set += slack * (*stretch as f64) / total_stretch;
                } else if slack < 0.0 && total_shrink > 0.0 {
                    // Shrink no further than the glue allows (overfull lines
                    // keep maximum shrink).
                    let factor = (-slack / total_shrink).min(1.0);
                    set -= factor * (*shrink as f64);
                }
                x += set;
            }
        }
    }
    LineOut { runs }
}
