//! Structure inference over positioned text (ADR 0029): fragments become
//! lines, lines become blocks by layout rules that hold for publisher
//! exports — one body face and size, larger or bolder standalone lines
//! for headings, smaller text at the foot for notes, running heads and
//! page numbers at the margins, indents and gaps for paragraphs.

use std::collections::HashMap;

use super::pdf::{Fragment, PageText, PlacedImage};
use super::{
    Block, Document, Inline, Note, ParagraphStyle, Style, normalize_whitespace, push_text,
};

/// Tunable thresholds; the defaults suit 10–11 pt book pages.
#[derive(Debug, Clone)]
pub struct InferOptions {
    /// Fragments within this many points vertically share a line.
    pub line_tolerance: f32,
    /// Fraction of the page height at top and bottom where running
    /// heads and page numbers live.
    pub margin_band: f32,
    /// A gap between fragments wider than this many spaces separates
    /// table cells.
    pub cell_gap_spaces: f32,
}

impl Default for InferOptions {
    fn default() -> Self {
        InferOptions {
            line_tolerance: 1.5,
            margin_band: 0.09,
            cell_gap_spaces: 2.5,
        }
    }
}

/// A line of text assembled from fragments, in reading order.
#[derive(Debug, Clone, PartialEq)]
pub struct Line {
    pub page: usize,
    /// Baseline, measured from the top of the page (points).
    pub top: f32,
    pub left: f32,
    pub right: f32,
    /// Dominant font size.
    pub size: f32,
    pub bold: bool,
    pub italic: bool,
    pub monospace: bool,
    /// Cells when the fragments sat in columns; one cell otherwise.
    pub cells: Vec<Cell>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Cell {
    pub left: f32,
    pub inlines: Vec<Inline>,
}

impl Line {
    pub fn text(&self) -> String {
        self.cells
            .iter()
            .map(|c| super::plain_text(&c.inlines))
            .collect::<Vec<_>>()
            .join("\t")
    }
}

/// A test picking a size class of fragments.
type FragmentTest = Box<dyn Fn(&Fragment) -> bool>;

/// A vertical gutter with text on both sides on many lines: the page is
/// set in two columns. Returns the gutter's x position.
pub fn column_gutter(page: &PageText) -> Option<f32> {
    let frags: Vec<&Fragment> = page
        .fragments
        .iter()
        .filter(|f| !f.text.trim().is_empty())
        .collect();
    gutter_of(&frags, page.width)
}

/// The gutter of a set of fragments (a whole page or a region of it).
fn gutter_of(frags: &[&Fragment], page_width: f32) -> Option<f32> {
    if frags.len() < 20 {
        return None;
    }
    let lo = page_width * 0.35;
    let hi = page_width * 0.65;
    // Coverage histogram at 2 pt resolution across the middle band.
    let bins = ((hi - lo) / 2.0) as usize + 1;
    let mut covered = vec![0usize; bins];
    for f in frags {
        let (a, b) = (f.x, f.x + f.width);
        if b < lo || a > hi {
            continue;
        }
        let start = (((a.max(lo) - lo) / 2.0) as usize).min(bins - 1);
        let end = (((b.min(hi) - lo) / 2.0) as usize).min(bins - 1);
        for bin in covered.iter_mut().take(end + 1).skip(start) {
            *bin += 1;
        }
    }
    // The widest empty run in the band; a centered heading or a page
    // number crossing it (a handful of fragments) does not fill it.
    let allowed = frags.len() / 100;
    let mut best: Option<(usize, usize)> = None;
    let mut run_start = None;
    for (i, &c) in covered.iter().enumerate() {
        match (c <= allowed, run_start) {
            (true, None) => run_start = Some(i),
            (false, Some(s)) => {
                if best.is_none_or(|(bs, be)| i - s > be - bs) {
                    best = Some((s, i));
                }
                run_start = None;
            }
            _ => {}
        }
    }
    if let Some(s) = run_start
        && best.is_none_or(|(bs, be)| bins - s > be - bs)
    {
        best = Some((s, bins));
    }
    let (s, e) = best?;
    if (e - s) * 2 < 6 {
        return None;
    }
    let gutter = lo + (s + e) as f32;
    // Text on both sides on enough lines, and next to nothing running
    // across the gutter (single-column lines above a two-column
    // apparatus would be torn apart).
    let left = frags.iter().filter(|f| f.x + f.width <= gutter).count();
    let right = frags.iter().filter(|f| f.x >= gutter).count();
    let crossing = frags.len() - left - right;
    (left >= 8 && right >= 8 && crossing * 50 <= frags.len()).then_some(gutter)
}

/// Group a page's fragments into lines; a two-column page reads its
/// left column before its right one. A page whose small-type apparatus
/// (endnotes) is set in two columns under single-column text reads the
/// text first, then the apparatus column by column.
pub fn lines_of_page(page: &PageText, index: usize, options: &InferOptions) -> Vec<Line> {
    if let Some(gutter) = column_gutter(page) {
        let mut left = page.clone();
        let mut right = page.clone();
        left.fragments.retain(|f| f.x + f.width * 0.5 < gutter);
        right.fragments.retain(|f| f.x + f.width * 0.5 >= gutter);
        left.images.clear();
        let mut lines = lines_of_fragments(&left, index, options);
        lines.extend(lines_of_fragments(&right, index, options));
        return lines;
    }
    // A page mixing single-column text with a two-column region (an
    // apparatus in small type, or endnotes in the page's dominant size
    // under a few lines of text): find the size class that forms columns
    // and read everything else first, then that region column by column.
    let mut by_size: HashMap<u32, usize> = HashMap::new();
    for f in &page.fragments {
        *by_size.entry((f.size * 10.0).round() as u32).or_default() += f.text.chars().count();
    }
    let dominant = by_size
        .iter()
        .max_by_key(|(_, n)| **n)
        .map(|(s, _)| *s as f32 / 10.0)
        .unwrap_or(10.0);
    let trace = std::env::var("GRAMMA_INFER_TRACE").is_ok();
    let classes: [FragmentTest; 2] = [
        Box::new(move |f: &Fragment| f.size < dominant * 0.85),
        Box::new(move |f: &Fragment| (f.size - dominant).abs() < dominant * 0.15),
    ];
    for in_region in classes {
        let region: Vec<&Fragment> = page
            .fragments
            .iter()
            .filter(|f| in_region(f) && !f.text.trim().is_empty())
            .collect();
        if region.len() == page.fragments.len() || region.len() < 20 {
            continue;
        }
        let Some(gutter) = gutter_of(&region, page.width) else {
            continue;
        };
        if trace {
            eprintln!(
                "page {index}: region of {} fragments in columns at {gutter}",
                region.len()
            );
        }
        let region_top = region.iter().map(|f| f.y).fold(f32::MIN, f32::max);
        let mut rest = page.clone();
        rest.fragments.retain(|f| !in_region(f) || f.y > region_top);
        let mut left = page.clone();
        left.fragments
            .retain(|f| in_region(f) && f.y <= region_top && f.x + f.width * 0.5 < gutter);
        left.images.clear();
        let mut right = page.clone();
        right
            .fragments
            .retain(|f| in_region(f) && f.y <= region_top && f.x + f.width * 0.5 >= gutter);
        right.images.clear();
        let mut lines = lines_of_fragments(&rest, index, options);
        lines.extend(lines_of_fragments(&left, index, options));
        lines.extend(lines_of_fragments(&right, index, options));
        return lines;
    }
    lines_of_fragments(page, index, options)
}

fn lines_of_fragments(page: &PageText, index: usize, options: &InferOptions) -> Vec<Line> {
    let mut frags: Vec<&Fragment> = page
        .fragments
        .iter()
        .filter(|f| !f.text.trim().is_empty() || f.text.contains(' '))
        .collect();
    // Superscripts are raised: pull them onto their baseline for
    // grouping, remembering the rise.
    frags.sort_by(|a, b| {
        let ya = a.y - a.rise;
        let yb = b.y - b.rise;
        yb.partial_cmp(&ya)
            .unwrap_or(std::cmp::Ordering::Equal)
            .then(a.x.partial_cmp(&b.x).unwrap_or(std::cmp::Ordering::Equal))
    });
    let mut lines: Vec<Vec<&Fragment>> = Vec::new();
    for frag in frags {
        let baseline = frag.y - frag.rise;
        match lines.last_mut() {
            Some(current)
                if (current[0].y - current[0].rise - baseline).abs() <= options.line_tolerance =>
            {
                current.push(frag)
            }
            _ => lines.push(vec![frag]),
        }
    }
    // Superscripts set as smaller text on a raised baseline (no Ts
    // operator) form their own tiny group; fold each into the line just
    // below it, recording the rise.
    let mut owned: Vec<Vec<Fragment>> = lines
        .iter()
        .map(|g| g.iter().map(|f| (*f).clone()).collect())
        .collect();
    let mut i = 0;
    while i < owned.len() {
        let group = &owned[i];
        let raised = group.iter().all(|f| {
            f.text
                .trim()
                .chars()
                .all(|c| c.is_ascii_digit() || c == '*' || c == ')')
                && !f.text.trim().is_empty()
        });
        let size = group.iter().map(|f| f.size).fold(0.0, f32::max);
        if raised && i + 1 < owned.len() {
            let below = &owned[i + 1];
            let below_size = below.iter().map(|f| f.size).fold(0.0, f32::max);
            let dy = group[0].y - group[0].rise - (below[0].y - below[0].rise);
            if size < below_size * 0.8 && dy > 0.0 && dy < below_size * 0.7 {
                let mut moved = owned.remove(i);
                for f in moved.iter_mut() {
                    f.rise += dy;
                }
                owned[i].extend(moved);
                continue;
            }
        }
        i += 1;
    }
    owned
        .into_iter()
        .filter_map(|mut group| {
            group.sort_by(|a, b| a.x.partial_cmp(&b.x).unwrap_or(std::cmp::Ordering::Equal));
            let refs: Vec<&Fragment> = group.iter().collect();
            build_line(&refs, index, page.height, options)
        })
        .collect()
}

fn build_line(
    group: &[&Fragment],
    page: usize,
    page_height: f32,
    options: &InferOptions,
) -> Option<Line> {
    // Dominant style by character count.
    let mut by_size: HashMap<(u32, bool, bool, bool), usize> = HashMap::new();
    for f in group {
        if f.rise.abs() > 0.5 {
            continue;
        }
        *by_size
            .entry((
                (f.size * 10.0).round() as u32,
                f.font.bold,
                f.font.italic,
                f.font.monospace,
            ))
            .or_default() += f.text.chars().count();
    }
    let ((size10, bold, italic, monospace), _) = by_size
        .into_iter()
        .max_by_key(|(k, n)| (*n, k.0))
        .or_else(|| {
            let f = group.first()?;
            Some((
                (
                    (f.size * 10.0).round() as u32,
                    f.font.bold,
                    f.font.italic,
                    f.font.monospace,
                ),
                0,
            ))
        })?;
    let size = size10 as f32 / 10.0;
    let space = size * 0.25;
    let mut cells: Vec<Cell> = vec![Cell {
        left: group[0].x,
        inlines: Vec::new(),
    }];
    let mut cursor = group[0].x;
    let last_index = group.len() - 1;
    for (fi, f) in group.iter().enumerate() {
        let gap = f.x - cursor;
        let cell = cells.last_mut().expect("one cell");
        let after_soft_hyphen = matches!(cell.inlines.last(), Some(Inline::Text { text, .. }) if text.ends_with('\u{ad}'));
        if gap > options.cell_gap_spaces * space
            && !cell.inlines.is_empty()
            && !punctuation_only(&f.text)
        {
            cells.push(Cell {
                left: f.x,
                inlines: Vec::new(),
            });
        } else if gap > space * 0.6
            && !cell.inlines.is_empty()
            && !after_soft_hyphen
            && !punctuation_only(&f.text)
        {
            push_text(&mut cell.inlines, " ", Style::PLAIN);
        }
        // A soft hyphen inside a line is a hyphenation point the
        // producer did not use; only a line-final one means a break.
        let text: String = if fi == last_index {
            let trimmed = f.text.trim_end();
            let inner: String = trimmed.trim_end_matches('\u{ad}').replace('\u{ad}', "");
            if trimmed.ends_with('\u{ad}') {
                inner + "\u{ad}"
            } else {
                inner
            }
        } else {
            f.text.replace('\u{ad}', "")
        };
        let f = &Fragment {
            text,
            ..(*f).clone()
        };
        let cell = cells.last_mut().expect("one cell");
        let superscript =
            f.rise > 0.5 || (f.size < size * 0.8 && f.y > group[0].y - group[0].rise + 0.5);
        let style = Style {
            italic: f.font.italic,
            bold: f.font.bold,
            monospace: f.font.monospace,
            superscript,
            ..Style::PLAIN
        };
        push_text(&mut cell.inlines, &f.text, style);
        cursor = f.x + f.width;
    }
    for cell in cells.iter_mut() {
        normalize_whitespace(&mut cell.inlines);
        // Drop a stray soft hyphen left before an in-line space.
        for inline in cell.inlines.iter_mut() {
            if let Inline::Text { text, .. } = inline
                && text.contains("\u{ad} ")
            {
                *text = text.replace("\u{ad} ", "");
            }
        }
    }
    cells.retain(|c| !c.inlines.is_empty());
    if cells.is_empty() {
        return None;
    }
    Some(Line {
        page,
        top: page_height - (group[0].y - group[0].rise),
        left: group[0].x,
        right: cursor,
        size,
        bold,
        italic,
        monospace,
        cells,
    })
}

/// A fragment holding only punctuation ("-", ",", ")."): it belongs to
/// the word before it whatever the geometry says.
fn punctuation_only(text: &str) -> bool {
    let t = text.trim();
    !t.is_empty()
        && t.chars()
            .all(|c| c.is_ascii_punctuation() || c == '–' || c == '»' || c == '«' || c == '’')
        && !t.starts_with(['(', '»', '„', '['])
}

/// Document-wide measurements the rules are relative to.
#[derive(Debug, Clone)]
pub struct Profile {
    pub body_size: f32,
    /// Typical baseline distance of body lines.
    pub body_pitch: f32,
    /// Left edge of body text (most common line start).
    pub body_left: f32,
    /// Right edge of full body lines.
    pub body_right: f32,
    /// Height of each page (points).
    pub page_heights: Vec<f32>,
}

impl Profile {
    pub fn page_height(&self, page: usize) -> f32 {
        self.page_heights.get(page).copied().unwrap_or(800.0)
    }
}

pub fn profile(lines: &[Line], page_heights: Vec<f32>) -> Profile {
    let mut by_size: HashMap<u32, usize> = HashMap::new();
    for l in lines {
        *by_size.entry((l.size * 10.0).round() as u32).or_default() += l.text().chars().count();
    }
    // The size carrying the most text is the body — unless a smaller
    // size wins only because a note apparatus is long: then the larger
    // size with at least 40% as much text is the body.
    let mut ranked: Vec<(u32, usize)> = by_size.into_iter().collect();
    ranked.sort_by(|a, b| b.1.cmp(&a.1).then(b.0.cmp(&a.0)));
    let mut body_size10 = ranked.first().map(|(s, _)| *s).unwrap_or(100);
    if let Some((top, n)) = ranked.first().copied() {
        for (size, count) in ranked.iter().skip(1) {
            if *size > top && count * 10 >= n * 4 {
                body_size10 = *size;
                break;
            }
        }
    }
    let body_size = body_size10 as f32 / 10.0;
    let body: Vec<&Line> = lines
        .iter()
        .filter(|l| (l.size - body_size).abs() < 0.3)
        .collect();
    let mut lefts: HashMap<i32, usize> = HashMap::new();
    for l in &body {
        *lefts.entry(l.left.round() as i32).or_default() += 1;
    }
    let body_left = lefts
        .iter()
        .max_by_key(|(_, n)| **n)
        .map(|(x, _)| *x as f32)
        .unwrap_or(0.0);
    let mut rights: Vec<f32> = body.iter().map(|l| l.right).collect();
    rights.sort_by(|a, b| a.partial_cmp(b).unwrap());
    let body_right = rights
        .get(rights.len() * 9 / 10)
        .copied()
        .unwrap_or(body_left + 300.0);
    let mut pitches: Vec<f32> = Vec::new();
    for pair in body.windows(2) {
        if pair[0].page == pair[1].page {
            let d = pair[1].top - pair[0].top;
            if d > body_size * 0.8 && d < body_size * 2.0 {
                pitches.push(d);
            }
        }
    }
    pitches.sort_by(|a, b| a.partial_cmp(b).unwrap());
    let body_pitch = pitches
        .get(pitches.len() / 2)
        .copied()
        .unwrap_or(body_size * 1.3);
    Profile {
        body_size,
        body_pitch,
        body_left,
        body_right,
        page_heights,
    }
}

/// Running heads and page numbers: lines in the margin bands that are
/// purely numeric, or whose text (digits removed) recurs on several
/// pages, or that use a size other than the body's.
pub fn strip_furniture(lines: Vec<Line>, profile: &Profile, options: &InferOptions) -> Vec<Line> {
    let band_of = |l: &Line| profile.page_height(l.page) * options.margin_band;
    let in_band = |l: &Line| l.top < band_of(l) || l.top > profile.page_height(l.page) - band_of(l);
    let mut recurring: HashMap<String, usize> = HashMap::new();
    let key = |l: &Line| -> String {
        l.text()
            .chars()
            .filter(|c| !c.is_ascii_digit())
            .collect::<String>()
            .trim()
            .to_string()
    };
    for l in &lines {
        if in_band(l) {
            *recurring.entry(key(l)).or_default() += 1;
        }
    }
    lines
        .into_iter()
        .filter(|l| {
            if !in_band(l) {
                return true;
            }
            let text = l.text();
            let numeric = text
                .trim()
                .chars()
                .all(|c| c.is_ascii_digit() || c.is_whitespace())
                && text.trim().chars().any(|c| c.is_ascii_digit());
            if numeric {
                return false;
            }
            let k = key(l);
            if !k.is_empty() && recurring.get(&k).copied().unwrap_or(0) >= 3 {
                return false;
            }
            // A short line hugging the top edge set in another size is a
            // running head even when its words are unique (chapter
            // titles start lower on the page).
            let top_band = l.top < band_of(l) * 0.6;
            let short = l.right - l.left < (profile.body_right - profile.body_left) * 0.6;
            !(top_band && short && (l.size - profile.body_size).abs() > 0.3)
        })
        .collect()
}

/// Notes found on pages: (page, label, lines).
pub type NoteLines = Vec<(usize, String, Vec<Line>)>;

/// Footnote lines: smaller than the body, in the lower part of the page,
/// starting a note with a number or letter. Returns (body lines, notes
/// keyed by page and label).
pub fn split_footnotes(lines: Vec<Line>, profile: &Profile) -> (Vec<Line>, NoteLines) {
    let mut body = Vec::new();
    let mut notes: NoteLines = Vec::new();
    let mut i = 0;
    let small = |l: &Line| l.size < profile.body_size - 1.5;
    while i < lines.len() {
        let l = &lines[i];
        if small(l) && l.top > profile.page_height(l.page) * 0.5 && !l.bold {
            // Everything small from here to the end of the page is notes.
            let page = l.page;
            let mut j = i;
            while j < lines.len() && lines[j].page == page && small(&lines[j]) {
                j += 1;
            }
            let block: Vec<Line> = lines[i..j].to_vec();
            i = j;
            // Split into notes at lines starting with a label.
            for line in block {
                let text = line.text();
                let label = leading_label(&text);
                match label {
                    Some(label)
                        if !notes
                            .last()
                            .is_some_and(|(p, _, ls)| *p == page && ls.is_empty())
                            || notes.is_empty() =>
                    {
                        notes.push((page, label, vec![line]));
                    }
                    Some(label) => notes.push((page, label, vec![line])),
                    None => match notes.last_mut() {
                        Some((p, _, ls)) if *p == page => ls.push(line),
                        _ => body.push(line),
                    },
                }
            }
            continue;
        }
        body.push(l.clone());
        i += 1;
    }
    (body, notes)
}

/// "12 text", "12. text", "a) text": the label of a note line.
fn leading_label(text: &str) -> Option<String> {
    let digits: String = text.chars().take_while(|c| c.is_ascii_digit()).collect();
    if !digits.is_empty() && digits.len() <= 3 {
        let rest = &text[digits.len()..];
        if rest.starts_with(' ')
            || rest.starts_with('\u{a0}')
            || rest.starts_with(". ")
            || rest.starts_with(".\u{a0}")
        {
            return Some(digits);
        }
    }
    None
}

/// The whole pipeline: pages → lines → furniture removed → notes split →
/// blocks, with images placed as figures where they sit.
pub fn document_from_pages(pages: &[PageText], options: &InferOptions) -> Document {
    let mut all: Vec<Line> = Vec::new();
    for (i, page) in pages.iter().enumerate() {
        all.extend(lines_of_page(page, i, options));
    }
    let chars = |lines: &[Line]| -> usize { lines.iter().map(|l| l.text().chars().count()).sum() };
    let trace = std::env::var("GRAMMA_INFER_TRACE").is_ok();
    if trace {
        eprintln!("stage lines: {}", chars(&all));
    }
    let profile = profile(&all, pages.iter().map(|p| p.height).collect());
    if trace {
        eprintln!("profile: {profile:?}");
    }
    let lines = strip_furniture(all, &profile, options);
    if trace {
        eprintln!("stage after furniture: {}", chars(&lines));
    }
    let (body, note_lines) = split_footnotes(lines, &profile);
    if trace {
        let note_chars: usize = note_lines.iter().map(|(_, _, ls)| chars(ls)).sum();
        eprintln!("stage body: {}  notes: {}", chars(&body), note_chars);
    }
    let mut doc = Document::default();
    let mut images: Vec<(usize, f32, usize)> = Vec::new(); // (page, top, image index)
    for (p, page) in pages.iter().enumerate() {
        for img in &page.images {
            if let Some(asset) = image_asset(img) {
                let index = doc.images.len();
                doc.images.push(asset);
                images.push((p, page.height - (img.y + img.height), index));
            }
        }
    }
    let mut notes_by_page: HashMap<usize, Vec<(String, Vec<Line>)>> = HashMap::new();
    for (page, label, lines) in note_lines {
        notes_by_page.entry(page).or_default().push((label, lines));
    }
    let mut builder = BlockBuilder::new(&profile);
    builder.notes_by_page = notes_by_page;
    builder.images = images;
    for line in body {
        builder.push(line);
    }
    builder.finish(&mut doc);
    doc
}

fn image_asset(img: &PlacedImage) -> Option<super::ImageAsset> {
    let asset = img.asset.as_ref()?;
    // Tiny images are ornaments and rules.
    if asset.width < 16 || asset.height < 16 || img.width < 20.0 || img.height < 20.0 {
        return None;
    }
    Some(asset.clone())
}

/// Turns the stream of body lines into blocks.
struct BlockBuilder<'a> {
    profile: &'a Profile,
    blocks: Vec<Block>,
    /// The paragraph under construction.
    para: Vec<Inline>,
    para_style: ParagraphStyle,
    para_left: f32,
    para_first_left: f32,
    /// Lines of the paragraph so far.
    para_lines: usize,
    /// Ends with a hyphen to be joined.
    hyphen_break: Option<bool>,
    last: Option<Line>,
    /// Pending table rows and the column positions seen so far.
    table_rows: Vec<Vec<Cell>>,
    table_columns: Vec<f32>,
    /// Pending list items (blocks per item) with the list's ordered flag.
    list: Option<(bool, Vec<Vec<Block>>)>,
    notes_by_page: HashMap<usize, Vec<(String, Vec<Line>)>>,
    note_map: HashMap<(usize, String), usize>,
    notes: Vec<Note>,
    images: Vec<(usize, f32, usize)>,
    image_cursor: usize,
    /// Sizes of heading lines seen, to rank levels.
    heading_sizes: Vec<f32>,
    pending_headings: Vec<(usize, f32, bool)>, // (block index, size, bold)
    /// Whether the last pushed line ended well before the measure.
    last_line_short: bool,
    /// Block indices of paragraphs made of one short line.
    single_short: std::collections::HashSet<usize>,
}

impl<'a> BlockBuilder<'a> {
    fn new(profile: &'a Profile) -> Self {
        BlockBuilder {
            profile,
            blocks: Vec::new(),
            para: Vec::new(),
            para_style: ParagraphStyle::Body,
            para_left: 0.0,
            para_first_left: 0.0,
            para_lines: 0,
            hyphen_break: None,
            last: None,
            table_rows: Vec::new(),
            table_columns: Vec::new(),
            list: None,
            notes_by_page: HashMap::new(),
            note_map: HashMap::new(),
            notes: Vec::new(),
            images: Vec::new(),
            image_cursor: 0,
            heading_sizes: Vec::new(),
            pending_headings: Vec::new(),
            last_line_short: false,
            single_short: std::collections::HashSet::new(),
        }
    }

    fn is_heading(&self, line: &Line) -> bool {
        let p = self.profile;
        let short = line.right - line.left < (p.body_right - p.body_left) * 0.85;
        let larger = line.size > p.body_size + 0.4;
        let numbered_only = line.text().trim().chars().all(|c| c.is_ascii_digit());
        (larger && short)
            || (line.bold
                && short
                && !numbered_only
                && self.para.is_empty()
                && line.cells.len() == 1)
            || (larger && numbered_only)
    }

    fn push(&mut self, line: Line) {
        // Leaving a page: note lines of earlier pages nobody referenced
        // return to the flow as paragraphs (an unmarked apparatus).
        if let Some(prev) = &self.last
            && prev.page < line.page
        {
            self.flush_unbound_notes(line.page);
        }
        // Figures above this line on the same page come first.
        self.place_images(line.page, line.top);
        let p = self.profile;
        let gap = match &self.last {
            Some(prev) if prev.page == line.page => line.top - prev.top,
            _ => f32::INFINITY,
        };

        // Tables: rows with two or more cells at shared positions; a row
        // may leave columns empty, and a one-cell line whose left sits on
        // a column continues the table (a wrapped cell).
        if line.cells.len() >= 2
            || (!self.table_rows.is_empty()
                && self.on_table_column(&line)
                && gap < p.body_pitch * 1.45)
        {
            if !self.table_rows.is_empty() && !self.fits_table(&line.cells) {
                self.flush_table();
            }
            if self.table_rows.is_empty() {
                self.flush_list();
                self.table_columns = line.cells.iter().map(|c| c.left).collect();
            } else {
                for c in &line.cells {
                    if !self.table_columns.iter().any(|x| (x - c.left).abs() < 6.0) {
                        self.table_columns.push(c.left);
                    }
                }
                self.table_columns.sort_by(|a, b| a.partial_cmp(b).unwrap());
            }
            self.table_rows.push(line.cells.clone());
            self.last = Some(line);
            return;
        }
        if !self.table_rows.is_empty() {
            self.flush_table();
        }

        if self.is_heading(&line) {
            self.flush_paragraph();
            self.flush_list();
            let mut inlines = line.cells[0].inlines.clone();
            strip_styles(&mut inlines);
            let index = self.blocks.len();
            self.blocks.push(Block::Heading { level: 1, inlines });
            self.pending_headings.push((index, line.size, line.bold));
            self.heading_sizes.push(line.size);
            self.last = Some(line);
            return;
        }

        let text = line.text();
        let indented = line.left > p.body_left + p.body_size * 0.6;
        let big_gap = gap > p.body_pitch * 1.45;
        let measure_all = p.body_right - p.body_left;
        let prev_line_short = self
            .last
            .as_ref()
            .is_some_and(|prev| prev.right < p.body_right - measure_all * 0.25);
        let prev_colon = self
            .last
            .as_ref()
            .is_some_and(|prev| prev.text().trim_end().ends_with(':'));
        // Inside a list, a marker back at the items' margin is the next
        // item even after a full hanging line.
        let back_at_item_margin = self.list.is_some()
            && (line.left - self.para_first_left).abs() < 1.0
            && line.left < self.para_left;
        // The next number of an open ordered list is an item on its own
        // evidence.
        let next_in_list = match (&self.list, list_number(&text)) {
            (Some((true, items)), Some(n)) => n == items.len() as u32 + 1,
            _ => false,
        };
        let starts_list = list_marker(&text).is_some()
            && (self.para.is_empty()
                || big_gap
                || prev_line_short
                || indented
                || prev_colon
                || back_at_item_margin
                || next_in_list);
        // A previous line ending well before the measure closed its
        // paragraph (justified setting makes this reliable).
        let measure = p.body_right - p.body_left;
        let prev_short = self.last.as_ref().is_some_and(|prev| {
            prev.right < p.body_right - measure * 0.25 && self.hyphen_break != Some(true)
        });
        let style_change = self
            .last
            .as_ref()
            .is_some_and(|prev| prev.bold != line.bold && !line.italic);
        // A first-line indent opens a paragraph; a hanging indent inside a
        // list item or a quotation continues one.
        let first_line_indent = indented
            && self.list.is_none()
            && self.para_style != ParagraphStyle::Quote
            && line.left < p.body_left + p.body_size * 3.0
            && line.left > self.para_left + p.body_size * 0.6;
        let dedent =
            line.left < self.para_left - p.body_size * 0.6 && self.para_lines >= 1 && prev_short;
        let hyphen_pending = self.hyphen_break == Some(true);
        let new_para = self.para.is_empty()
            || (!hyphen_pending
                && (big_gap
                    || starts_list
                    || style_change
                    || first_line_indent
                    || prev_short
                    || dedent));

        if !new_para && self.para_lines >= 1 && line.left > self.para_first_left + 0.5 {
            // A hanging continuation: remember its margin.
            self.para_left = line.left;
        }
        if new_para {
            self.flush_paragraph();
            self.para_style = if line.bold && starts_with_verse_number(&text) {
                ParagraphStyle::Scripture
            } else if indented
                && !starts_list
                && self.list.is_none()
                && line.left > p.body_left + p.body_size * 3.0
            {
                ParagraphStyle::Quote
            } else {
                ParagraphStyle::Body
            };
            if starts_list {
                self.list_item_start(&text);
            } else if self.list.is_some() && !indented {
                self.flush_list();
            }
            self.para_left = line.left;
            self.para_first_left = line.left;
            self.para_lines = 0;
        }
        self.append_line(&line);
        self.last_line_short = line.right < p.body_right - measure * 0.25;
        self.last = Some(line);
    }

    fn fits_table(&self, cells: &[Cell]) -> bool {
        // Every cell sits on a known column, or extends the table by at
        // most one new column to the right.
        let mut new = 0;
        for c in cells {
            if !self.table_columns.iter().any(|x| (x - c.left).abs() < 6.0) {
                new += 1;
            }
        }
        new <= 1 && cells.len() <= self.table_columns.len() + 1
    }

    fn on_table_column(&self, line: &Line) -> bool {
        line.cells.len() == 1
            && self
                .table_columns
                .iter()
                .skip(1)
                .any(|x| (x - line.left).abs() < 6.0)
    }

    fn list_item_start(&mut self, text: &str) {
        let t = text.trim_start();
        let digits = t.chars().take_while(|c| c.is_ascii_digit()).count();
        let number: Option<u32> = (digits > 0).then(|| t[..digits].parse().ok()).flatten();
        let ordered = number.is_some();
        // An ordered list continues only with the next number; "1." after
        // "1. 2. 3." opens a new list (a restart, or a different kind of
        // enumeration such as verse-by-verse exposition).
        let continues = match (&self.list, number) {
            (Some((true, items)), Some(n)) => n == items.len() as u32 + 1,
            (Some((false, _)), None) => true,
            _ => false,
        };
        if continues {
            if let Some((_, items)) = &mut self.list {
                items.push(Vec::new());
            }
        } else {
            self.flush_list();
            self.list = Some((ordered, vec![Vec::new()]));
        }
    }

    fn append_line(&mut self, line: &Line) {
        let mut inlines = line.cells[0].inlines.clone();
        if self.para_lines == 0 && self.list.is_some() {
            strip_list_marker(&mut inlines);
        }
        // Resolve raised numbers into note references.
        self.bind_note_refs(&mut inlines, line.page);
        if self.para_lines > 0 {
            match self.hyphen_break {
                Some(true) => {}
                _ => push_text(&mut self.para, " ", Style::PLAIN),
            }
        }
        let joined = join_hyphen(&mut self.para, &mut inlines);
        self.hyphen_break = Some(joined);
        for inline in inlines {
            match inline {
                Inline::Text { text, style } => push_text(&mut self.para, &text, style),
                other => self.para.push(other),
            }
        }
        // A line ending in a soft or hard hyphen joins the next.
        let ends_hyphen = match self.para.last() {
            Some(Inline::Text { text, .. }) => {
                text.ends_with('\u{ad}') || (text.ends_with('-') && text.len() > 1)
            }
            _ => false,
        };
        self.hyphen_break = Some(ends_hyphen);
        self.para_lines += 1;
    }

    /// Emit note lines of pages before `before` that no marker claimed.
    fn flush_unbound_notes(&mut self, before: usize) {
        let mut pages: Vec<usize> = self
            .notes_by_page
            .keys()
            .copied()
            .filter(|p| *p < before)
            .collect();
        pages.sort_unstable();
        for p in pages {
            let Some(notes) = self.notes_by_page.remove(&p) else {
                continue;
            };
            if notes.is_empty() {
                continue;
            }
            self.flush_paragraph();
            for (label, lines) in notes {
                let mut blocks = note_blocks(lines, &label);
                if let Some(Block::Paragraph { inlines, .. }) = blocks.first_mut() {
                    // Keep the label the note carried in print.
                    let mut labelled = vec![Inline::styled(
                        format!("{label} "),
                        Style {
                            bold: true,
                            ..Style::PLAIN
                        },
                    )];
                    labelled.append(inlines);
                    *inlines = labelled;
                }
                self.blocks.extend(blocks);
            }
        }
    }

    fn bind_note_refs(&mut self, inlines: &mut Vec<Inline>, page: usize) {
        let mut out = Vec::with_capacity(inlines.len());
        for inline in inlines.drain(..) {
            match inline {
                Inline::Text { text, style }
                    if style.superscript
                        && text.trim().chars().all(|c| c.is_ascii_digit())
                        && !text.trim().is_empty() =>
                {
                    let label = text.trim().to_string();
                    let key = (page, label.clone());
                    let index = match self.note_map.get(&key) {
                        Some(i) => *i,
                        None => {
                            // The note sits on this page (a footnote) or on
                            // a later one (endnotes after the section).
                            let mut body = None;
                            let mut candidates: Vec<usize> = self
                                .notes_by_page
                                .keys()
                                .copied()
                                .filter(|p| *p >= page)
                                .collect();
                            candidates.sort_unstable();
                            for p in candidates {
                                if let Some(notes) = self.notes_by_page.get_mut(&p)
                                    && let Some(pos) = notes.iter().position(|(l, _)| *l == label)
                                {
                                    body = Some(notes.remove(pos).1);
                                    break;
                                }
                            }
                            let Some(body) = body else {
                                // No note body on this page: keep the number.
                                out.push(Inline::Text { text, style });
                                continue;
                            };
                            let index = self.notes.len();
                            self.notes.push(Note {
                                label: label.clone(),
                                blocks: note_blocks(body, &label),
                            });
                            self.note_map.insert(key, index);
                            index
                        }
                    };
                    out.push(Inline::NoteRef(index));
                }
                other => out.push(other),
            }
        }
        *inlines = out;
    }

    fn flush_paragraph(&mut self) {
        if self.para.is_empty() {
            return;
        }
        let mut inlines = std::mem::take(&mut self.para);
        normalize_whitespace(&mut inlines);
        let style = self.para_style;
        self.para_style = ParagraphStyle::Body;
        let lines_in_para = self.para_lines;
        self.para_lines = 0;
        self.hyphen_break = None;
        if inlines.is_empty() {
            return;
        }
        let block = Block::Paragraph { style, inlines };
        let one_short_line =
            lines_in_para == 1 && self.last_line_short && style == ParagraphStyle::Body;
        match &mut self.list {
            Some((_, items)) => items.last_mut().expect("item").push(block),
            None => {
                if one_short_line {
                    self.single_short.insert(self.blocks.len());
                }
                self.blocks.push(block);
            }
        }
    }

    fn flush_list(&mut self) {
        self.flush_paragraph();
        if let Some((ordered, items)) = self.list.take() {
            let items: Vec<Vec<Block>> = items.into_iter().filter(|i| !i.is_empty()).collect();
            if !items.is_empty() {
                self.blocks.push(Block::List { ordered, items });
            }
        }
    }

    fn flush_table(&mut self) {
        let rows = std::mem::take(&mut self.table_rows);
        let columns = std::mem::take(&mut self.table_columns);
        if rows.is_empty() {
            return;
        }
        if rows.len() == 1 || columns.len() < 2 {
            // A lone two-cell line is a paragraph with a gap, not a table.
            let mut inlines = Vec::new();
            for (i, cell) in rows[0].iter().enumerate() {
                if i > 0 {
                    push_text(&mut inlines, " ", Style::PLAIN);
                }
                inlines.extend(cell.inlines.iter().cloned());
            }
            self.para.extend(inlines);
            self.para_lines += 1;
            return;
        }
        self.flush_paragraph();
        // Long cells wrapping over many rows are two columns of running
        // text (endnotes, a two-column apparatus), not a table: read them
        // column by column, a paragraph per labelled note.
        let cells_total: usize = rows.iter().map(|r| r.len()).sum();
        let chars_total: usize = rows
            .iter()
            .flat_map(|r| r.iter())
            .map(|c| super::plain_text(&c.inlines).chars().count())
            .sum();
        if rows.len() >= 6
            && columns.len() <= 3
            && cells_total > 0
            && chars_total / cells_total >= 25
        {
            for column in &columns {
                let mut para: Vec<Inline> = Vec::new();
                for cells in &rows {
                    let Some(cell) = cells.iter().find(|c| (c.left - column).abs() < 6.0) else {
                        continue;
                    };
                    let text = super::plain_text(&cell.inlines);
                    if leading_label(&text).is_some() && !para.is_empty() {
                        normalize_whitespace(&mut para);
                        self.blocks.push(Block::Paragraph {
                            style: ParagraphStyle::Body,
                            inlines: std::mem::take(&mut para),
                        });
                    }
                    let mut next = cell.inlines.clone();
                    let joined = join_hyphen(&mut para, &mut next);
                    if !joined && !para.is_empty() {
                        push_text(&mut para, " ", Style::PLAIN);
                    }
                    for inline in next {
                        match inline {
                            Inline::Text { text, style } => push_text(&mut para, &text, style),
                            other => para.push(other),
                        }
                    }
                }
                if !para.is_empty() {
                    normalize_whitespace(&mut para);
                    self.blocks.push(Block::Paragraph {
                        style: ParagraphStyle::Body,
                        inlines: para,
                    });
                }
            }
            return;
        }
        // Place cells by column; a wrapped cell (a row that only fills
        // columns the previous row also filled, with no text in the first
        // column) joins the row above.
        let mut grid: Vec<Vec<Vec<Inline>>> = Vec::new();
        for cells in rows {
            let mut row: Vec<Vec<Inline>> = vec![Vec::new(); columns.len()];
            let mut first_filled = false;
            for c in cells {
                let col = columns
                    .iter()
                    .position(|x| (x - c.left).abs() < 6.0)
                    .unwrap_or(columns.len() - 1);
                if col == 0 {
                    first_filled = true;
                }
                if !row[col].is_empty() {
                    push_text(&mut row[col], " ", Style::PLAIN);
                }
                row[col].extend(c.inlines);
            }
            if !first_filled && let Some(prev) = grid.last_mut() {
                for (col, cell) in row.into_iter().enumerate() {
                    if cell.is_empty() {
                        continue;
                    }
                    if !prev[col].is_empty() {
                        push_text(&mut prev[col], " ", Style::PLAIN);
                    }
                    prev[col].extend(cell);
                }
                continue;
            }
            grid.push(row);
        }
        for row in grid.iter_mut() {
            for cell in row.iter_mut() {
                normalize_whitespace(cell);
            }
        }
        self.blocks.push(Block::Table {
            header_rows: 0,
            rows: grid,
        });
    }

    fn place_images(&mut self, page: usize, before_top: f32) {
        while let Some(&(p, top, index)) = self.images.get(self.image_cursor) {
            if p < page || (p == page && top < before_top) {
                self.flush_paragraph();
                self.blocks.push(Block::Figure {
                    image: index,
                    caption: Vec::new(),
                });
                self.image_cursor += 1;
            } else {
                break;
            }
        }
    }

    fn finish(mut self, doc: &mut Document) {
        self.flush_table();
        self.flush_list();
        self.flush_unbound_notes(usize::MAX);
        self.place_images(usize::MAX, 0.0);
        // Heading levels by size rank: the largest size is level 1.
        let mut sizes: Vec<u32> = self
            .heading_sizes
            .iter()
            .map(|s| (s * 10.0).round() as u32)
            .collect();
        sizes.sort_unstable();
        sizes.dedup();
        sizes.reverse();
        for (index, size, _bold) in &self.pending_headings {
            let rank = sizes
                .iter()
                .position(|s| *s == (size * 10.0).round() as u32)
                .unwrap_or(0);
            if let Block::Heading { level, .. } = &mut self.blocks[*index] {
                *level = (rank + 1).min(6) as u8;
            }
        }
        // A title set over several lines arrives as several headings of
        // one size: join them into one.
        let sizes: std::collections::HashMap<usize, u32> = self
            .pending_headings
            .iter()
            .map(|(i, size, _)| (*i, (size * 10.0).round() as u32))
            .collect();
        let mut i = 0;
        let mut removed = 0;
        let mut merged_blocks: Vec<Block> = Vec::with_capacity(self.blocks.len());
        let mut merged_single: std::collections::HashSet<usize> = std::collections::HashSet::new();
        while i < self.blocks.len() {
            let block = self.blocks[i].clone();
            if let Block::Heading { level, inlines } = &block
                && let Some(size) = sizes.get(&i)
            {
                let level = *level;
                let mut inlines = inlines.clone();
                let mut j = i + 1;
                while j < self.blocks.len()
                    && let Block::Heading { inlines: next, .. } = &self.blocks[j]
                    && sizes.get(&j) == Some(size)
                {
                    push_text(&mut inlines, " ", Style::PLAIN);
                    inlines.extend(next.iter().cloned());
                    j += 1;
                }
                removed += j - i - 1;
                merged_blocks.push(Block::Heading { level, inlines });
                i = j;
                continue;
            }
            if self.single_short.contains(&i) {
                merged_single.insert(merged_blocks.len());
            }
            merged_blocks.push(block);
            i += 1;
        }
        let _ = removed;
        self.blocks = merged_blocks;
        self.single_short = merged_single;
        // Runs of single short lines are set as they stand: poetry.
        let single: Vec<usize> = {
            let mut v: Vec<usize> = self.single_short.iter().copied().collect();
            v.sort_unstable();
            v
        };
        let mut run: Vec<usize> = Vec::new();
        let flush_run = |run: &mut Vec<usize>, blocks: &mut Vec<Block>| {
            if run.len() >= 2 {
                for &k in run.iter() {
                    if let Block::Paragraph { style, .. } = &mut blocks[k] {
                        *style = ParagraphStyle::Poetry { indent: 1 };
                    }
                }
            }
            run.clear();
        };
        for k in single {
            if run.last().is_some_and(|&last| last + 1 != k) {
                flush_run(&mut run, &mut self.blocks);
            }
            run.push(k);
        }
        flush_run(&mut run, &mut self.blocks);
        // Captions: a paragraph right after a figure starting "Abb."/"Fig."
        let mut i = 0;
        while i + 1 < self.blocks.len() {
            if let Block::Figure { .. } = &self.blocks[i]
                && let Block::Paragraph { inlines, .. } = &self.blocks[i + 1]
                && is_caption(&super::plain_text(inlines))
            {
                let caption = inlines.clone();
                self.blocks.remove(i + 1);
                if let Block::Figure { caption: slot, .. } = &mut self.blocks[i] {
                    *slot = caption;
                }
            }
            i += 1;
        }
        doc.blocks.extend(self.blocks);
        doc.notes.extend(self.notes);
    }
}

fn note_blocks(lines: Vec<Line>, label: &str) -> Vec<Block> {
    let mut inlines: Vec<Inline> = Vec::new();
    for (i, line) in lines.iter().enumerate() {
        let mut cell = line
            .cells
            .iter()
            .flat_map(|c| c.inlines.iter().cloned())
            .collect::<Vec<_>>();
        strip_styles_superscript(&mut cell);
        if i == 0 {
            // Drop the label that opens the note.
            if let Some(Inline::Text { text, .. }) = cell.first_mut()
                && let Some(rest) = text.strip_prefix(label)
            {
                *text = rest.trim_start_matches(['.', ' ', '\u{a0}']).to_string();
            }
        } else {
            let joined = join_hyphen(&mut inlines, &mut cell);
            if !joined {
                push_text(&mut inlines, " ", Style::PLAIN);
            }
        }
        for inline in cell {
            match inline {
                Inline::Text { text, style } => push_text(&mut inlines, &text, style),
                other => inlines.push(other),
            }
        }
    }
    normalize_whitespace(&mut inlines);
    if inlines.is_empty() {
        Vec::new()
    } else {
        vec![Block::Paragraph {
            style: ParagraphStyle::Body,
            inlines,
        }]
    }
}

/// If `para` ends with a hyphen (soft or hard) and `next` continues in
/// lowercase, remove the hyphen and report the join.
fn join_hyphen(para: &mut [Inline], next: &mut [Inline]) -> bool {
    let Some(Inline::Text { text, .. }) = para.last_mut() else {
        return false;
    };
    let next_lower = matches!(next.first(), Some(Inline::Text { text, .. }) if text.chars().next().is_some_and(|c| c.is_lowercase()));
    if text.ends_with('\u{ad}') {
        text.pop();
        return true;
    }
    if text.ends_with('-') && text.len() > 1 && next_lower {
        text.pop();
        while text.ends_with(' ') {
            text.pop();
        }
        return true;
    }
    false
}

/// "1. ", "12) ", "• ", "– ", "a) " at the start of a paragraph.
pub fn list_marker(text: &str) -> Option<usize> {
    let t = text.trim_start();
    let offset = text.len() - t.len();
    let digits = t.chars().take_while(|c| c.is_ascii_digit()).count();
    if digits > 0 && digits <= 2 {
        let rest = &t[digits..];
        for sep in [". ", ") ", ".\u{a0}", ".\t", ")\u{a0}"] {
            if let Some(after) = rest.strip_prefix(sep)
                && !after.is_empty()
            {
                return Some(offset + digits + sep.len());
            }
        }
    }
    for marker in [
        "• ",
        "– ",
        "- ",
        "· ",
        "▪ ",
        "■ ",
        "◦ ",
        "•\u{a0}",
        "–\u{a0}",
    ] {
        if let Some(rest) = t.strip_prefix(marker)
            && !rest.is_empty()
        {
            return Some(offset + marker.len());
        }
    }
    let mut chars = t.chars();
    if let (Some(c), Some(')' | '.'), Some(' ' | '\u{a0}')) =
        (chars.next(), chars.next(), chars.next())
        && c.is_ascii_lowercase()
    {
        let len: usize = t.chars().take(3).map(|c| c.len_utf8()).sum();
        return Some(offset + len);
    }
    None
}

/// The number of an ordered marker at the start of `text`, if any.
fn list_number(text: &str) -> Option<u32> {
    let t = text.trim_start();
    let digits = t.chars().take_while(|c| c.is_ascii_digit()).count();
    if digits == 0 || digits > 2 || list_marker(text).is_none() {
        return None;
    }
    t[..digits].parse().ok()
}

fn strip_list_marker(inlines: &mut [Inline]) {
    if let Some(Inline::Text { text, .. }) = inlines.first_mut()
        && let Some(len) = list_marker(text)
    {
        *text = text[len..].to_string();
    }
}

fn starts_with_verse_number(text: &str) -> bool {
    let t = text.trim_start();
    let digits = t.chars().take_while(|c| c.is_ascii_digit()).count();
    digits > 0 && digits <= 3 && t[digits..].starts_with(' ')
}

fn strip_styles(inlines: &mut [Inline]) {
    for inline in inlines.iter_mut() {
        if let Inline::Text { style, .. } = inline {
            style.bold = false;
        }
    }
}

fn strip_styles_superscript(inlines: &mut [Inline]) {
    for inline in inlines.iter_mut() {
        if let Inline::Text { style, .. } = inline {
            style.superscript = false;
        }
    }
}

fn is_caption(text: &str) -> bool {
    let t = text.trim_start();
    [
        "Abb.",
        "Abbildung",
        "Fig.",
        "Figure",
        "Bild",
        "Tabelle",
        "Table",
    ]
    .iter()
    .any(|p| t.starts_with(p))
}
