//! Turning text into box/glue/penalty items for the breaker.
//!
//! Width measurement is behind [`TextMeasure`] so the shaping layer
//! (rustybuzz) can plug in without touching this logic; hyphenation uses
//! Knuth–Liang patterns via the `hyphenation` crate, inserting flagged
//! penalties at every legal division point.

use std::ops::Range;

use hyphenation::{Hyphenator, Standard};

use super::{Item, Scaled, finish_paragraph};

/// Provides widths for text runs and the paragraph's spacing parameters, in
/// `Scaled` units. Implemented later by the shaping layer; tests use simple
/// fixed-width measures.
pub trait TextMeasure {
    fn text_width(&self, text: &str) -> Scaled;
    /// Inter-word space: (width, stretch, shrink).
    fn space(&self) -> (Scaled, Scaled, Scaled);
    fn hyphen_width(&self) -> Scaled;
}

/// Items plus, for every box item, the source-text range it covers.
#[derive(Debug, Clone, PartialEq)]
pub struct Paragraph {
    pub items: Vec<Item>,
    pub sources: Vec<Option<Range<usize>>>,
}

/// Penalty charged for breaking at a hyphenation point (TeX
/// `\hyphenpenalty`).
pub const HYPHEN_PENALTY: i32 = 50;

pub fn build_paragraph(
    text: &str,
    measure: &impl TextMeasure,
    hyphenator: Option<&Standard>,
) -> Paragraph {
    let mut items = Vec::new();
    let mut sources = Vec::new();
    let (space_width, stretch, shrink) = measure.space();
    let mut first = true;
    for (word, word_start) in words_with_offsets(text) {
        if !first {
            items.push(Item::Glue {
                width: space_width,
                stretch,
                shrink,
            });
            sources.push(None);
        }
        first = false;
        let breaks = hyphenator
            .map(|h| h.hyphenate(word).breaks)
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
            sources.push(Some(word_start + fragment_start..word_start + offset));
            if offset < word.len() {
                items.push(Item::Penalty {
                    width: measure.hyphen_width(),
                    penalty: HYPHEN_PENALTY,
                    flagged: true,
                });
                sources.push(None);
            }
            fragment_start = offset;
        }
    }
    finish_paragraph(&mut items);
    sources.resize(items.len(), None);
    Paragraph { items, sources }
}

fn words_with_offsets(text: &str) -> impl Iterator<Item = (&str, usize)> {
    text.split_whitespace()
        .map(move |word| (word, word.as_ptr() as usize - text.as_ptr() as usize))
}
