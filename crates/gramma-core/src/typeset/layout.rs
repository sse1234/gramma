//! Chapter layout: verses flow into one Knuth–Plass-broken paragraph whose
//! lines carry positioned text runs, ready to paint.
//!
//! Every run knows the verse it belongs to, giving the reader verse-level
//! position granularity. Footnote anchors become inline markers: small
//! lettered boxes bound unbreakably to the word they follow.
//!
//! Glue setting happens here: after the breaker chooses breakpoints, each
//! justified line's leftover slack is distributed over its spaces in
//! proportion to their stretch (or shrink), so painted lines end flush with
//! the measure using the same shaped widths the painter will use.

use hyphenation::Standard;

use super::paragraph::{HYPHEN_PENALTY, TextMeasure, hyphen_offsets};
use super::{INFINITE_PENALTY, Item, Params, Scaled, break_lines, finish_paragraph};

/// Verse numbers and note markers are set at this percentage of the text
/// size; widths here and the painter's font size must agree.
pub const VERSE_NUMBER_SCALE_PERCENT: i64 = 65;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum RunKind {
    Word,
    VerseNumber,
    NoteMarker,
    Heading,
}

#[derive(Debug, Clone, PartialEq)]
pub struct RunOut {
    pub text: String,
    /// Left edge in font units from the line start.
    pub x: f64,
    /// Shaped width of `text` in font units (already scaled for numbers).
    pub width: f64,
    pub verse_number: bool,
    /// An inline footnote marker (lettered, matching the note's sequence).
    pub note_marker: bool,
    /// Section heading level (0 = body text, 1 = section, 2 = subsection).
    pub heading_level: u8,
    /// The verse this run belongs to.
    pub verse: u16,
    /// Index of the reference this run is part of (prose layout, ADR
    /// 0018): tapping the run resolves the entry's reference at this
    /// index. None for plain text.
    pub link: Option<u32>,
    /// Byte offset of this run's first fragment within its verse's
    /// normalized text (ADR 0023: word-precise annotation anchors).
    /// Zero for non-word runs and prose layouts.
    pub offset: u32,
}

#[derive(Debug, Clone, PartialEq)]
pub struct LineOut {
    pub runs: Vec<RunOut>,
}

#[derive(Debug, Clone)]
struct BoxMeta {
    text: String,
    kind: RunKind,
    verse: u16,
    heading_level: u8,
    link: Option<u32>,
    offset: u32,
}

/// Lay out verses as justified paragraphs at `line_width` font units,
/// segmented by section headings. `notes` are (verse, byte offset) pairs;
/// each produces an inline lettered marker bound to the word containing its
/// anchor. `headings` are (verse, level, text) rows standing before their
/// verse; each heading group is preceded by one empty spacing line (except
/// at the very top) and rendered as its own ragged line(s).
pub fn layout_verses(
    verses: &[(u16, &str)],
    notes: &[(u16, u32)],
    headings: &[(u16, u8, &str)],
    measure: &impl TextMeasure,
    hyphenator: Option<&Standard>,
    line_width: Scaled,
) -> Vec<LineOut> {
    let mut lines: Vec<LineOut> = Vec::new();
    let mut segment: Vec<(u16, &str)> = Vec::new();
    for &(number, text) in verses {
        let verse_headings: Vec<_> = headings.iter().filter(|(v, _, _)| *v == number).collect();
        if !verse_headings.is_empty() {
            flush_segment(&mut lines, &segment, notes, measure, hyphenator, line_width);
            segment.clear();
            if !lines.is_empty() {
                lines.push(LineOut { runs: Vec::new() });
            }
            for &&(verse, level, text) in &verse_headings {
                lines.extend(layout_heading(
                    None, text, level, verse, measure, line_width,
                ));
            }
        }
        segment.push((number, text));
    }
    flush_segment(&mut lines, &segment, notes, measure, hyphenator, line_width);
    lines
}

fn flush_segment(
    lines: &mut Vec<LineOut>,
    segment: &[(u16, &str)],
    notes: &[(u16, u32)],
    measure: &impl TextMeasure,
    hyphenator: Option<&Standard>,
    line_width: Scaled,
) {
    if segment.is_empty() {
        return;
    }
    lines.extend(layout_paragraph(
        segment, notes, measure, hyphenator, line_width,
    ));
}

/// A heading as its own small paragraph: justified breaking would look odd,
/// and a single line comes out ragged naturally (the paragraph-final glue).
fn layout_heading(
    label: Option<&str>,
    text: &str,
    level: u8,
    verse: u16,
    measure: &impl TextMeasure,
    line_width: Scaled,
) -> Vec<LineOut> {
    let mut items: Vec<Item> = Vec::new();
    let mut meta: Vec<Option<BoxMeta>> = Vec::new();
    let (space_width, stretch, shrink) = measure.space();
    if let Some(label) = label {
        push_label(&mut items, &mut meta, measure, label, verse);
        items.push(Item::Glue {
            width: space_width,
            stretch,
            shrink,
        });
        meta.push(None);
    }
    let mut first = true;
    for word in text.split_whitespace() {
        if !first {
            items.push(Item::Glue {
                width: space_width,
                stretch,
                shrink,
            });
            meta.push(None);
        }
        first = false;
        items.push(Item::Box {
            width: measure.text_width(word),
        });
        meta.push(Some(BoxMeta {
            text: word.to_string(),
            kind: RunKind::Heading,
            verse,
            heading_level: level,
            link: None,
            offset: 0,
        }));
    }
    finish_paragraph(&mut items);
    meta.resize(items.len(), None);
    let params = Params::new(line_width);
    let Ok(broken) = break_lines(&items, &params) else {
        return Vec::new();
    };
    broken
        .lines
        .iter()
        .map(|line| {
            set_line(
                &items, &meta, measure, line.start, line.end, line_width, true,
            )
        })
        .collect()
}

fn layout_paragraph(
    verses: &[(u16, &str)],
    notes: &[(u16, u32)],
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

    fn push(
        items: &mut Vec<Item>,
        meta: &mut Vec<Option<BoxMeta>>,
        item: Item,
        m: Option<BoxMeta>,
    ) {
        items.push(item);
        meta.push(m);
    }

    for (number, text) in verses {
        let mut verse_notes: Vec<usize> = notes
            .iter()
            .filter(|(v, _)| v == number)
            .map(|&(_, offset)| offset as usize)
            .collect();
        verse_notes.sort_unstable();
        let mut note_idx = 0usize;
        let mut marker_letter = b'a';

        if !items.is_empty() {
            push(&mut items, &mut meta, space, None);
        }
        let number_text = number.to_string();
        push(
            &mut items,
            &mut meta,
            Item::Box {
                width: measure.text_width(&number_text) * VERSE_NUMBER_SCALE_PERCENT / 100,
            },
            Some(BoxMeta {
                text: number_text,
                kind: RunKind::VerseNumber,
                verse: *number,
                heading_level: 0,
                link: None,
                offset: 0,
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
        for (word, word_start) in words_with_offsets(text) {
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
                        kind: RunKind::Word,
                        verse: *number,
                        heading_level: 0,
                        link: None,
                        offset: (word_start + fragment_start) as u32,
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
            let word_end = word_start + word.len();
            while note_idx < verse_notes.len() && verse_notes[note_idx] <= word_end {
                note_idx += 1;
                push_marker(&mut items, &mut meta, measure, &mut marker_letter, *number);
            }
        }
        // Notes anchored past the last word still get their marker.
        while note_idx < verse_notes.len() {
            note_idx += 1;
            push_marker(&mut items, &mut meta, measure, &mut marker_letter, *number);
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

/// Bind an inline lettered marker to the preceding word: an infinite
/// penalty forbids a break between them.
fn push_marker(
    items: &mut Vec<Item>,
    meta: &mut Vec<Option<BoxMeta>>,
    measure: &impl TextMeasure,
    marker_letter: &mut u8,
    verse: u16,
) {
    let label = (*marker_letter as char).to_string();
    *marker_letter = marker_letter.saturating_add(1);
    items.push(Item::Penalty {
        width: 0,
        penalty: INFINITE_PENALTY,
        flagged: false,
    });
    meta.push(None);
    items.push(Item::Box {
        width: measure.text_width(&label) * VERSE_NUMBER_SCALE_PERCENT / 100,
    });
    meta.push(Some(BoxMeta {
        text: label,
        kind: RunKind::NoteMarker,
        verse,
        heading_level: 0,
        link: None,
        offset: 0,
    }));
}

fn words_with_offsets(text: &str) -> impl Iterator<Item = (&str, usize)> {
    text.split_whitespace()
        .map(move |word| (word, word.as_ptr() as usize - text.as_ptr() as usize))
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
            kind: RunKind,
            verse: u16,
            heading_level: u8,
            link: Option<u32>,
            offset: u32,
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
                    Some(Piece::Run {
                        text, kind, link, ..
                    }) if *kind == RunKind::Word && m.kind == RunKind::Word && *link == m.link => {
                        text.push_str(&m.text);
                    }
                    _ => pieces.push(Piece::Run {
                        text: m.text.clone(),
                        kind: m.kind,
                        verse: m.verse,
                        heading_level: m.heading_level,
                        link: m.link,
                        offset: m.offset,
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
            Piece::Run { text, kind, .. } => {
                let w = measure.text_width(text);
                if *kind == RunKind::Word || *kind == RunKind::Heading {
                    w as f64
                } else {
                    (w * VERSE_NUMBER_SCALE_PERCENT / 100) as f64
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
            Piece::Run {
                text,
                kind,
                verse,
                heading_level,
                link,
                offset,
            } => {
                runs.push(RunOut {
                    text: text.clone(),
                    x,
                    width: *width,
                    verse_number: *kind == RunKind::VerseNumber,
                    note_marker: *kind == RunKind::NoteMarker,
                    heading_level: *heading_level,
                    verse: *verse,
                    link: *link,
                    offset: *offset,
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

/// A prose paragraph (ADR 0018): text with byte ranges marking tappable
/// references, each carrying the index the painted runs report back.
pub struct ProseParagraph<'a> {
    pub text: &'a str,
    /// (start, end, link index) byte ranges within `text`.
    pub links: Vec<(usize, usize, u32)>,
}

/// Lay out one prose entry — a commentary section — with the same
/// engine and voice as the Bible text: an optional label set like a
/// verse number and bound to what follows, an optional level-1 heading
/// directly above its body, and hyphenated paragraphs separated by one
/// blank line. All runs carry `verse` for position granularity and
/// reference words carry their link index. With `justify` off, lines
/// break at the same measure but every space keeps its natural width —
/// side-aligned setting for narrow, character-dense content like
/// dictionary entries (ADR 0026).
pub fn layout_prose(
    label: Option<&str>,
    heading: Option<&str>,
    paragraphs: &[ProseParagraph],
    verse: u16,
    measure: &impl TextMeasure,
    hyphenator: Option<&Standard>,
    justify: bool,
    line_width: Scaled,
) -> Vec<LineOut> {
    let mut lines: Vec<LineOut> = Vec::new();
    let mut label = label;
    if let Some(heading) = heading {
        lines.extend(layout_heading(
            label.take(),
            heading,
            1,
            verse,
            measure,
            line_width,
        ));
    }
    for (i, paragraph) in paragraphs.iter().enumerate() {
        if i > 0 {
            lines.push(LineOut { runs: Vec::new() });
        }
        lines.extend(prose_paragraph(
            label.take(),
            paragraph,
            verse,
            measure,
            hyphenator,
            justify,
            line_width,
        ));
    }
    lines
}

/// The label box, set at verse-number scale and bound unbreakably to
/// whatever follows.
fn push_label(
    items: &mut Vec<Item>,
    meta: &mut Vec<Option<BoxMeta>>,
    measure: &impl TextMeasure,
    label: &str,
    verse: u16,
) {
    items.push(Item::Box {
        width: measure.text_width(label) * VERSE_NUMBER_SCALE_PERCENT / 100,
    });
    meta.push(Some(BoxMeta {
        text: label.to_string(),
        kind: RunKind::VerseNumber,
        verse,
        heading_level: 0,
        link: None,
        offset: 0,
    }));
    items.push(Item::Penalty {
        width: 0,
        penalty: INFINITE_PENALTY,
        flagged: false,
    });
    meta.push(None);
}

fn prose_paragraph(
    label: Option<&str>,
    paragraph: &ProseParagraph,
    verse: u16,
    measure: &impl TextMeasure,
    hyphenator: Option<&Standard>,
    justify: bool,
    line_width: Scaled,
) -> Vec<LineOut> {
    let mut items: Vec<Item> = Vec::new();
    let mut meta: Vec<Option<BoxMeta>> = Vec::new();
    let (space_width, stretch, shrink) = measure.space();
    // Ragged setting: spaces may stretch freely for the breaker (the
    // slack lands in the right margin, as with TeX's \raggedright),
    // and set_line later keeps them at natural width.
    let space = if justify {
        Item::Glue {
            width: space_width,
            stretch,
            shrink,
        }
    } else {
        Item::Glue {
            width: space_width,
            stretch: line_width,
            shrink: 0,
        }
    };
    if let Some(label) = label {
        push_label(&mut items, &mut meta, measure, label, verse);
        items.push(space);
        meta.push(None);
    }
    let link_at = |start: usize, end: usize| {
        paragraph
            .links
            .iter()
            .find(|&&(s, e, _)| s < end && e > start)
            .map(|&(_, _, index)| index)
    };
    let mut first_word = true;
    for (word, word_start) in words_with_offsets(paragraph.text) {
        if !first_word {
            items.push(space);
            meta.push(None);
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
            items.push(Item::Box {
                width: measure.text_width(fragment),
            });
            meta.push(Some(BoxMeta {
                text: fragment.to_string(),
                kind: RunKind::Word,
                verse,
                heading_level: 0,
                link: link_at(word_start + fragment_start, word_start + offset),
                offset: 0,
            }));
            if offset < word.len() {
                items.push(Item::Penalty {
                    width: measure.hyphen_width(),
                    penalty: HYPHEN_PENALTY,
                    flagged: true,
                });
                meta.push(None);
            }
            fragment_start = offset;
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
                !justify || line_no == last_index,
            )
        })
        .collect()
}
