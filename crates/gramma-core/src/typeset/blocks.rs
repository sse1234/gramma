//! Block layout (ADR 0029): an entry's block tree — headings, styled
//! paragraphs, lists, tables, figures, notes — set with the same breaker
//! and voice as verse and prose text. Lists hang their markers, quotes
//! and poetry indent, tables set each cell as a ragged paragraph in its
//! column, figures reserve whole lines, notes close the entry at a
//! smaller size.

use hyphenation::Standard;

use super::layout::{
    BoxMeta, LineOut, ProseSetting, RunKind, RunOut, STYLE_BOLD, STYLE_ITALIC, STYLE_MONOSPACE,
    STYLE_SMALL_CAPS, STYLE_SUPERSCRIPT, VERSE_NUMBER_SCALE_PERCENT, layout_heading, push_label,
    set_line,
};
use super::paragraph::{HYPHEN_PENALTY, TextMeasure, hyphen_offsets};
use super::{INFINITE_PENALTY, Item, Params, Scaled, break_lines, finish_paragraph};
use crate::document::{Block, Inline, Note, ParagraphStyle, Style};

/// Natural pixel size of each image the entry may show, by index.
pub type ImageSizes<'a> = &'a [(u32, u32)];

/// Small-caps runs are set in capitals at this percent of the size.
const SMALL_CAPS_PERCENT: i64 = 80;
/// Superscript note markers and raised text.
const SUPERSCRIPT_PERCENT: i64 = 65;
/// Captions and notes.
const SMALL_PERCENT: i64 = 85;
/// Vertical pitch assumed when reserving lines for a figure, in ems.
const FIGURE_LINE_PITCH_EM: f64 = 1.4;

/// Set an entry's blocks. `label` is set like a verse number before the
/// first heading or paragraph; `notes` follow the blocks; references in
/// the blocks get link indices in reading order (heading and paragraph
/// text, list items, table rows, captions, then notes), matching the
/// order the plain-text `refs` were stored in.
#[allow(clippy::too_many_arguments)]
pub fn layout_blocks(
    label: Option<&str>,
    blocks: &[Block],
    notes: &[Note],
    images: ImageSizes,
    verse: u16,
    measure: &impl TextMeasure,
    hyphenator: Option<&Standard>,
    setting: ProseSetting,
) -> Vec<LineOut> {
    let mut ctx = Ctx {
        measure,
        hyphenator,
        justify: setting.justify,
        line_width: setting.line_width,
        em: measure.em(),
        verse,
        label: label.map(str::to_string),
        link: 0,
        lines: Vec::new(),
        notes,
        images,
    };
    for (i, block) in blocks.iter().enumerate() {
        if i > 0 {
            ctx.blank();
        }
        ctx.block(block, 0, 0);
    }
    if !notes.is_empty() {
        ctx.blank();
        for (i, note) in notes.iter().enumerate() {
            let label = if note.label.is_empty() {
                (i + 1).to_string()
            } else {
                note.label.clone()
            };
            let mut first = true;
            for b in &note.blocks {
                if let Block::Paragraph { inlines, .. } = b {
                    let label = first.then_some(label.as_str());
                    first = false;
                    ctx.paragraph(label, inlines, SMALL_PERCENT, 0, ctx.em / 2, 0, false, 0);
                }
            }
            if first {
                // A note without paragraphs still shows its label.
                ctx.paragraph(Some(&label), &[], SMALL_PERCENT, 0, 0, 0, false, 0);
            }
        }
    }
    ctx.lines
}

struct Ctx<'a, M: TextMeasure> {
    measure: &'a M,
    hyphenator: Option<&'a Standard>,
    justify: bool,
    line_width: Scaled,
    em: Scaled,
    verse: u16,
    /// Consumed by the first heading or paragraph.
    label: Option<String>,
    /// Next reference link index.
    link: u32,
    lines: Vec<LineOut>,
    notes: &'a [Note],
    images: ImageSizes<'a>,
}

impl<M: TextMeasure> Ctx<'_, M> {
    fn blank(&mut self) {
        self.lines.push(LineOut::text(Vec::new()));
    }

    /// `indent` shifts the block right; `hang` additionally indents every
    /// line after the first (list items).
    fn block(&mut self, block: &Block, indent: Scaled, hang: Scaled) {
        match block {
            Block::Heading { level, inlines } => {
                let text = crate::document::plain_text(inlines);
                let label = self.label.take();
                let level = (*level).clamp(1, 3);
                let mut lines = layout_heading(
                    label.as_deref(),
                    &text,
                    level,
                    self.verse,
                    self.measure,
                    self.line_width - indent,
                );
                self.count_links(inlines);
                shift(&mut lines, indent as f64);
                self.lines.extend(lines);
            }
            Block::Paragraph { style, inlines } => {
                let label = self.label.take();
                match style {
                    ParagraphStyle::Body => self.paragraph(
                        label.as_deref(),
                        inlines,
                        100,
                        0,
                        indent,
                        hang,
                        self.justify,
                        0,
                    ),
                    ParagraphStyle::Quote => {
                        let em = self.em;
                        self.paragraph(
                            label.as_deref(),
                            inlines,
                            100,
                            0,
                            indent + em * 3 / 2,
                            hang,
                            self.justify,
                            em * 3 / 2,
                        )
                    }
                    ParagraphStyle::Scripture => self.paragraph(
                        label.as_deref(),
                        inlines,
                        100,
                        STYLE_BOLD,
                        indent,
                        hang,
                        self.justify,
                        0,
                    ),
                    ParagraphStyle::Poetry { indent: level } => {
                        let em = self.em;
                        let left = indent + em * (*level as i64);
                        self.paragraph(label.as_deref(), inlines, 100, 0, left, em, false, 0)
                    }
                    ParagraphStyle::Caption => self.paragraph(
                        label.as_deref(),
                        inlines,
                        SMALL_PERCENT,
                        0,
                        indent,
                        hang,
                        false,
                        0,
                    ),
                }
            }
            Block::List { ordered, items } => {
                let em = self.em;
                let hang_width = em * 2;
                for (i, item) in items.iter().enumerate() {
                    if i > 0 {
                        self.blank();
                    }
                    let marker = if *ordered {
                        format!("{}.", i + 1)
                    } else {
                        "•".to_string()
                    };
                    let start = self.lines.len();
                    for (j, b) in item.iter().enumerate() {
                        if j > 0 {
                            self.blank();
                        }
                        self.block(b, indent + hang_width, 0);
                    }
                    // The marker sits in the hanging margin of the item's
                    // first line.
                    if let Some(first) = self.lines.get_mut(start) {
                        let width = self.measure.text_width(&marker) as f64;
                        first.runs.insert(
                            0,
                            RunOut {
                                text: marker,
                                x: indent as f64,
                                width,
                                verse_number: false,
                                note_marker: false,
                                heading_level: 0,
                                verse: self.verse,
                                link: None,
                                offset: 0,
                                style: 0,
                                scale: 1.0,
                            },
                        );
                    }
                }
            }
            Block::Table { header_rows, rows } => {
                let columns = rows.iter().map(|r| r.len()).max().unwrap_or(0);
                if columns == 0 {
                    return;
                }
                let gutter = self.em;
                let width = self.line_width - indent;
                let col_width =
                    ((width - gutter * (columns as i64 - 1)) / columns as i64).max(self.em * 3);
                for (r, row) in rows.iter().enumerate() {
                    let style = if r < *header_rows as usize {
                        STYLE_BOLD
                    } else {
                        0
                    };
                    let mut cell_lines: Vec<Vec<LineOut>> = Vec::new();
                    for cell in row {
                        let lines = self.set_inlines(None, cell, 100, style, col_width, 0, false);
                        cell_lines.push(lines);
                    }
                    let height = cell_lines.iter().map(|l| l.len()).max().unwrap_or(0);
                    for line_no in 0..height {
                        let mut runs = Vec::new();
                        for (c, lines) in cell_lines.iter().enumerate() {
                            let x0 = indent + (col_width + gutter) * c as i64;
                            if let Some(line) = lines.get(line_no) {
                                for run in &line.runs {
                                    let mut run = run.clone();
                                    run.x += x0 as f64;
                                    runs.push(run);
                                }
                            }
                        }
                        self.lines.push(LineOut::text(runs));
                    }
                }
            }
            Block::Figure { image, caption } => {
                let (w, h) = self.images.get(*image).copied().unwrap_or((4, 3));
                let width = (self.line_width - indent) as f64;
                let height = width * h.max(1) as f64 / w.max(1) as f64;
                let pitch = self.em as f64 * FIGURE_LINE_PITCH_EM;
                let lines = (height / pitch).ceil().max(1.0) as u16;
                self.lines.push(LineOut {
                    runs: Vec::new(),
                    image: Some(*image as u32),
                    image_lines: lines,
                });
                for _ in 1..lines {
                    self.lines.push(LineOut::text(Vec::new()));
                }
                if !caption.is_empty() {
                    self.paragraph(None, caption, SMALL_PERCENT, 0, indent, 0, false, 0);
                }
            }
            Block::Rule | Block::Milestone { .. } => {}
        }
    }

    fn count_links(&mut self, inlines: &[Inline]) {
        self.link += inlines
            .iter()
            .filter(|i| matches!(i, Inline::Reference { .. }))
            .count() as u32;
    }

    /// One paragraph: `percent` scales the text, `style` adds character
    /// style bits, `left` indents all lines, `hang` indents lines after
    /// the first, `right` narrows the measure from the right.
    #[allow(clippy::too_many_arguments)]
    fn paragraph(
        &mut self,
        label: Option<&str>,
        inlines: &[Inline],
        percent: i64,
        style: u8,
        left: Scaled,
        hang: Scaled,
        justify: bool,
        right: Scaled,
    ) {
        let width = (self.line_width - left - right).max(self.em * 4);
        let mut lines = self.set_inlines(label, inlines, percent, style, width, hang, justify);
        shift(&mut lines, left as f64);
        self.lines.extend(lines);
    }

    /// Build and break one paragraph's items at `width`; lines after the
    /// first are set `hang` narrower and shifted by it.
    #[allow(clippy::too_many_arguments)]
    fn set_inlines(
        &mut self,
        label: Option<&str>,
        inlines: &[Inline],
        percent: i64,
        base_style: u8,
        width: Scaled,
        hang: Scaled,
        justify: bool,
    ) -> Vec<LineOut> {
        let measure = self.measure;
        let mut items: Vec<Item> = Vec::new();
        let mut meta: Vec<Option<BoxMeta>> = Vec::new();
        let (space_width, stretch, shrink) = measure.space();
        let space_width = space_width * percent / 100;
        let space = if justify {
            Item::Glue {
                width: space_width,
                stretch: stretch * percent / 100,
                shrink: shrink * percent / 100,
            }
        } else {
            Item::Glue {
                width: space_width,
                stretch: width,
                shrink: 0,
            }
        };
        let mut pending_space = false;
        let mut any = false;
        if let Some(label) = label {
            push_label(&mut items, &mut meta, measure, label, self.verse);
            pending_space = true;
            any = true;
        }
        for inline in inlines {
            match inline {
                Inline::Text { text, style: s } => {
                    let bits = base_style | style_bits(s);
                    let scale = if s.superscript || s.subscript {
                        SUPERSCRIPT_PERCENT
                    } else if s.small_caps {
                        SMALL_CAPS_PERCENT
                    } else {
                        100
                    } * percent
                        / 100;
                    let shown: String = if s.small_caps {
                        text.to_uppercase()
                    } else {
                        text.clone()
                    };
                    let leading_space = shown.starts_with(char::is_whitespace);
                    let trailing_space = shown.ends_with(char::is_whitespace);
                    let mut first = true;
                    for word in shown.split_whitespace() {
                        if (first && (pending_space || leading_space) && any) || !first {
                            items.push(space);
                            meta.push(None);
                        } else if first && any && !pending_space && !leading_space {
                            // Glued to the previous run: no break here.
                            items.push(Item::Penalty {
                                width: 0,
                                penalty: INFINITE_PENALTY,
                                flagged: false,
                            });
                            meta.push(None);
                        }
                        first = false;
                        any = true;
                        self.push_word(&mut items, &mut meta, word, bits, scale, None, s.monospace);
                    }
                    if !shown.trim().is_empty() {
                        pending_space = trailing_space;
                    } else if !shown.is_empty() {
                        pending_space = true;
                    }
                }
                Inline::Reference { text, .. } => {
                    let link = Some(self.link);
                    self.link += 1;
                    let leading_space = text.starts_with(char::is_whitespace);
                    let mut first = true;
                    for word in text.split_whitespace() {
                        if (first && (pending_space || leading_space) && any) || !first {
                            items.push(space);
                            meta.push(None);
                        }
                        first = false;
                        any = true;
                        self.push_word(
                            &mut items, &mut meta, word, base_style, percent, link, false,
                        );
                    }
                    pending_space = text.ends_with(char::is_whitespace);
                }
                Inline::VerseNumber(n) => {
                    if any {
                        items.push(space);
                        meta.push(None);
                    }
                    push_label(&mut items, &mut meta, measure, &n.to_string(), self.verse);
                    pending_space = true;
                    any = true;
                }
                Inline::NoteRef(index) => {
                    let label = self
                        .notes
                        .get(*index)
                        .map(|n| {
                            if n.label.is_empty() {
                                (index + 1).to_string()
                            } else {
                                n.label.clone()
                            }
                        })
                        .unwrap_or_else(|| (index + 1).to_string());
                    items.push(Item::Penalty {
                        width: 0,
                        penalty: INFINITE_PENALTY,
                        flagged: false,
                    });
                    meta.push(None);
                    items.push(Item::Box {
                        width: measure.text_width(&label) * SUPERSCRIPT_PERCENT * percent / 10_000,
                    });
                    meta.push(Some(BoxMeta {
                        text: label,
                        kind: RunKind::NoteMarker,
                        verse: self.verse,
                        heading_level: 0,
                        link: None,
                        offset: 0,
                        style: STYLE_SUPERSCRIPT,
                        scale_percent: SUPERSCRIPT_PERCENT * percent / 100,
                    }));
                    any = true;
                    pending_space = true;
                }
                Inline::LineBreak => {
                    // Force a break: a penalty of -infinity after glue.
                    items.push(Item::Glue {
                        width: 0,
                        stretch: width,
                        shrink: 0,
                    });
                    meta.push(None);
                    items.push(Item::Penalty {
                        width: 0,
                        penalty: -INFINITE_PENALTY,
                        flagged: false,
                    });
                    meta.push(None);
                    pending_space = false;
                }
            }
        }
        if !any {
            return Vec::new();
        }
        finish_paragraph(&mut items);
        meta.resize(items.len(), None);
        // Hanging lines: break at the narrower width when the first line
        // differs (the breaker takes one width; approximate by breaking
        // at the hanging width and letting the first line run to it too).
        let break_width = if hang > 0 { width - hang } else { width };
        let params = Params::new(break_width);
        let Ok(broken) = break_lines(&items, &params) else {
            return Vec::new();
        };
        let last_index = broken.lines.len().saturating_sub(1);
        broken
            .lines
            .iter()
            .enumerate()
            .map(|(line_no, line)| {
                let mut out = set_line(
                    &items,
                    &meta,
                    measure,
                    line.start,
                    line.end,
                    break_width,
                    !justify || line_no == last_index,
                );
                if hang > 0 && line_no > 0 {
                    shift(std::slice::from_mut(&mut out), hang as f64);
                }
                out
            })
            .collect()
    }

    #[allow(clippy::too_many_arguments)]
    fn push_word(
        &self,
        items: &mut Vec<Item>,
        meta: &mut Vec<Option<BoxMeta>>,
        word: &str,
        style: u8,
        scale_percent: i64,
        link: Option<u32>,
        no_hyphen: bool,
    ) {
        let breaks = if no_hyphen || link.is_some() {
            Vec::new()
        } else {
            self.hyphenator
                .map(|h| hyphen_offsets(word, h))
                .unwrap_or_default()
        };
        let mut fragment_start = 0usize;
        for offset in breaks.iter().copied().chain([word.len()]) {
            if offset == fragment_start {
                continue;
            }
            let fragment = &word[fragment_start..offset];
            items.push(Item::Box {
                width: self.measure.text_width(fragment) * scale_percent / 100,
            });
            meta.push(Some(BoxMeta {
                text: fragment.to_string(),
                kind: RunKind::Word,
                verse: self.verse,
                heading_level: 0,
                link,
                offset: 0,
                style,
                scale_percent,
            }));
            if offset < word.len() {
                items.push(Item::Penalty {
                    width: self.measure.hyphen_width() * scale_percent / 100,
                    penalty: HYPHEN_PENALTY,
                    flagged: true,
                });
                meta.push(None);
            }
            fragment_start = offset;
        }
    }
}

fn style_bits(s: &Style) -> u8 {
    let mut bits = 0;
    if s.italic {
        bits |= STYLE_ITALIC;
    }
    if s.bold {
        bits |= STYLE_BOLD;
    }
    if s.small_caps {
        bits |= STYLE_SMALL_CAPS;
    }
    if s.superscript || s.subscript {
        bits |= STYLE_SUPERSCRIPT;
    }
    if s.monospace {
        bits |= STYLE_MONOSPACE;
    }
    bits
}

fn shift(lines: &mut [LineOut], dx: f64) {
    if dx == 0.0 {
        return;
    }
    for line in lines {
        for run in &mut line.runs {
            run.x += dx;
        }
    }
}

/// The percent labels are set at, re-exported for callers sizing markers.
pub const LABEL_PERCENT: i64 = VERSE_NUMBER_SCALE_PERCENT;

/// OSIS targets of every reference in the order `layout_blocks` assigns
/// link indices: block text in reading order, list items, table cells,
/// captions, then notes.
pub fn reference_targets(blocks: &[Block], notes: &[Note]) -> Vec<String> {
    fn inlines(out: &mut Vec<String>, inlines: &[Inline]) {
        for i in inlines {
            if let Inline::Reference { osis, .. } = i {
                out.push(osis.clone());
            }
        }
    }
    fn walk(out: &mut Vec<String>, blocks: &[Block]) {
        for b in blocks {
            match b {
                Block::Heading { inlines: i, .. } | Block::Paragraph { inlines: i, .. } => {
                    inlines(out, i)
                }
                Block::List { items, .. } => {
                    for item in items {
                        walk(out, item);
                    }
                }
                Block::Table { rows, .. } => {
                    for row in rows {
                        for cell in row {
                            inlines(out, cell);
                        }
                    }
                }
                Block::Figure { caption, .. } => inlines(out, caption),
                Block::Rule | Block::Milestone { .. } => {}
            }
        }
    }
    let mut out = Vec::new();
    walk(&mut out, blocks);
    for note in notes {
        for b in &note.blocks {
            if let Block::Paragraph { inlines: i, .. } = b {
                inlines(&mut out, i);
            }
        }
    }
    out
}
