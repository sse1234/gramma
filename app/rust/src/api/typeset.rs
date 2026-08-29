use std::collections::hash_map::DefaultHasher;
use std::collections::HashMap;
use std::hash::{Hash, Hasher};
use std::sync::{Mutex, OnceLock, RwLock};

use anyhow::anyhow;
use gramma_core::reference::{book_by_osis, scan_references};
use gramma_core::typeset::layout::{
    layout_prose, layout_verses, ProseParagraph, VERSE_NUMBER_SCALE_PERCENT,
};
use gramma_core::typeset::shape::FontMeasure;
use hyphenation::{Language, Load, Standard};

use super::library::with_library;

/// The active face. Every parsed face is kept for the process lifetime
/// (a handful at most — the user's typeface choices), so switching back
/// and forth re-uses the parsed face and its word-width cache.
static MEASURE: RwLock<Option<&'static FontMeasure<'static>>> = RwLock::new(None);
static FACES: Mutex<Option<HashMap<u64, &'static FontMeasure<'static>>>> = Mutex::new(None);
static GERMAN: OnceLock<Standard> = OnceLock::new();

fn activate_font(font_data: Vec<u8>) -> anyhow::Result<()> {
    let mut hasher = DefaultHasher::new();
    font_data.hash(&mut hasher);
    let key = hasher.finish();
    let mut guard = FACES.lock().unwrap();
    let faces = guard.get_or_insert_with(HashMap::new);
    let measure = match faces.get(&key) {
        Some(measure) => *measure,
        None => {
            let data: &'static [u8] = Box::leak(font_data.into_boxed_slice());
            let measure: &'static FontMeasure<'static> = Box::leak(Box::new(
                FontMeasure::new(data).ok_or_else(|| anyhow!("cannot parse font"))?,
            ));
            faces.insert(key, measure);
            measure
        }
    };
    *MEASURE.write().unwrap() = Some(measure);
    Ok(())
}

fn active_measure() -> anyhow::Result<&'static FontMeasure<'static>> {
    MEASURE
        .read()
        .unwrap()
        .ok_or_else(|| anyhow!("typesetting not initialized"))
}

pub struct RunView {
    pub text: String,
    /// Left edge in font units.
    pub x: f64,
    /// Shaped width in font units.
    pub width: f64,
    pub verse_number: bool,
    /// An inline lettered footnote marker.
    pub note_marker: bool,
    /// Section heading level (0 = body, 1 = section, 2 = subsection).
    pub heading_level: u8,
    /// The verse this run belongs to.
    pub verse: u16,
    /// Reference index in the owning layout's refs (prose, ADR 0018);
    /// tapping the run opens that reference. None for plain text.
    pub link: Option<u32>,
    /// Byte offset of the run within its verse's text (ADR 0023);
    /// zero for non-word runs and prose layouts.
    pub offset: u32,
}

pub struct LineView {
    pub runs: Vec<RunView>,
}

pub struct ChapterLayoutView {
    pub lines: Vec<LineView>,
    pub units_per_em: u16,
    /// Line width in font units (MEASURE_EMS ems).
    pub measure_units: i64,
    /// Verse numbers render at this fraction of the text size.
    pub number_scale: f64,
    /// Flowing text of the chapter, for accessibility semantics.
    pub plain_text: String,
}

#[flutter_rust_bridge::frb(sync)]
pub fn init_typesetting(font_data: Vec<u8>) -> anyhow::Result<()> {
    if MEASURE.read().unwrap().is_some() {
        return Ok(());
    }
    activate_font(font_data)
}

/// Switch the typesetting face (the user's typeface setting): every
/// later layout uses the new metrics, so callers re-measure and re-lay
/// their modules just as after a measure change.
#[flutter_rust_bridge::frb(sync)]
pub fn set_typeset_font(font_data: Vec<u8>) -> anyhow::Result<()> {
    activate_font(font_data)
}

/// Async on purpose: runs on a worker thread so scrolling never blocks on
/// shaping and breaking.
pub fn layout_chapter(
    module_code: String,
    book_osis: String,
    chapter: u16,
    measure_ems: u16,
) -> anyhow::Result<ChapterLayoutView> {
    let measure = active_measure()?;
    let book = book_by_osis(&book_osis).ok_or_else(|| anyhow!("unknown book: {book_osis}"))?;
    let (verses, notes, headings, german) = with_library(|library| {
        let verses = library.chapter(&module_code, book, chapter)?;
        let notes = library.notes(&module_code, book, chapter)?;
        let headings = library.headings(&module_code, book, chapter)?;
        let german = library
            .modules()?
            .iter()
            .any(|m| m.code == module_code && m.language.starts_with("de"));
        Ok((verses, notes, headings, german))
    })?;
    let hyphenator = german.then(|| {
        GERMAN.get_or_init(|| {
            Standard::from_embedded(Language::German1996).expect("embedded patterns")
        })
    });
    let verse_refs: Vec<(u16, &str)> = verses.iter().map(|v| (v.verse, v.text.as_str())).collect();
    let note_refs: Vec<(u16, u32)> = notes.iter().map(|n| (n.verse, n.offset)).collect();
    let heading_refs: Vec<(u16, u8, &str)> = headings
        .iter()
        .map(|h| (h.verse, h.level, h.text.as_str()))
        .collect();
    let measure_units = measure_ems as i64 * measure.units_per_em() as i64;
    let lines = layout_verses(
        &verse_refs,
        &note_refs,
        &heading_refs,
        measure,
        hyphenator,
        measure_units,
    );
    let plain_text = verses
        .iter()
        .map(|v| format!("{} {}", v.verse, v.text))
        .collect::<Vec<_>>()
        .join(" ");
    Ok(ChapterLayoutView {
        lines: lines
            .into_iter()
            .map(|l| LineView {
                runs: l
                    .runs
                    .into_iter()
                    .map(|r| RunView {
                        text: r.text,
                        x: r.x,
                        width: r.width,
                        verse_number: r.verse_number,
                        note_marker: r.note_marker,
                        heading_level: r.heading_level,
                        verse: r.verse,
                        link: r.link,
                        offset: r.offset,
                    })
                    .collect(),
            })
            .collect(),
        units_per_em: measure.units_per_em(),
        measure_units,
        number_scale: VERSE_NUMBER_SCALE_PERCENT as f64 / 100.0,
        plain_text,
    })
}

/// One commentary section, typeset (ADR 0018): the same engine as the
/// Bible text, at the pane's own measure. Runs with a `link` index are
/// tappable references resolving through `refs`.
pub struct CommentLayoutView {
    pub verse_start: u16,
    pub verse_end: u16,
    pub lines: Vec<LineView>,
    /// OSIS targets by `RunView.link` index.
    pub refs: Vec<String>,
    pub units_per_em: u16,
    /// Line width in font units for this layout.
    pub measure_units: i64,
    /// The label renders at this fraction of the text size.
    pub number_scale: f64,
    /// Flowing text of the entry, for accessibility semantics.
    pub plain_text: String,
}

/// Typeset the commentary sections of one chapter at `measure_ems` ems —
/// the pane's width in ems of its text size; commentary reflows freely,
/// without the reader's protected measure. Async: shaping and breaking
/// run on a worker thread.
pub fn layout_comments(
    module_code: String,
    book_osis: String,
    chapter: u16,
    measure_ems: f64,
) -> anyhow::Result<Vec<CommentLayoutView>> {
    let measure = active_measure()?;
    let book = book_by_osis(&book_osis).ok_or_else(|| anyhow!("unknown book: {book_osis}"))?;
    let (comments, german) = with_library(|library| {
        let comments = library.comments(&module_code, book, chapter)?;
        let german = library
            .modules()?
            .iter()
            .any(|m| m.code == module_code && m.language.starts_with("de"));
        Ok((comments, german))
    })?;
    let hyphenator = german.then(|| {
        GERMAN.get_or_init(|| {
            Standard::from_embedded(Language::German1996).expect("embedded patterns")
        })
    });
    let measure_units = (measure_ems * measure.units_per_em() as f64) as i64;
    Ok(comments
        .into_iter()
        .map(|c| {
            let label = if c.verse_start == c.verse_end {
                c.verse_start.to_string()
            } else {
                format!("{}-{}", c.verse_start, c.verse_end)
            };
            let spans: Vec<(u32, u32)> = c.refs.iter().map(|r| (r.start, r.end)).collect();
            let paragraphs = prose_paragraphs(&c.text, &spans);
            let lines = layout_prose(
                Some(&label),
                c.heading.as_deref(),
                &paragraphs,
                c.verse_start,
                measure,
                hyphenator,
                true,
                measure_units,
            );
            let plain_text = match &c.heading {
                Some(h) => format!("{label} {h}. {}", c.text.replace("\n\n", " ")),
                None => format!("{label} {}", c.text.replace("\n\n", " ")),
            };
            CommentLayoutView {
                verse_start: c.verse_start,
                verse_end: c.verse_end,
                lines: lines
                    .into_iter()
                    .map(|l| LineView {
                        runs: l
                            .runs
                            .into_iter()
                            .map(|r| RunView {
                                text: r.text,
                                x: r.x,
                                width: r.width,
                                verse_number: r.verse_number,
                                note_marker: r.note_marker,
                                heading_level: r.heading_level,
                                verse: r.verse,
                                link: r.link,
                                offset: r.offset,
                            })
                            .collect(),
                    })
                    .collect(),
                refs: c.refs.into_iter().map(|r| r.osis).collect(),
                units_per_em: measure.units_per_em(),
                measure_units,
                number_scale: VERSE_NUMBER_SCALE_PERCENT as f64 / 100.0,
                plain_text,
            }
        })
        .collect())
}

/// Split prose into paragraphs at "\n\n", re-basing reference byte
/// spans (indexed in order) onto each paragraph.
fn prose_paragraphs<'a>(text: &'a str, spans: &[(u32, u32)]) -> Vec<ProseParagraph<'a>> {
    let mut paragraphs = Vec::new();
    let mut cursor = 0usize;
    for part in text.split("\n\n") {
        let start = cursor;
        let end = start + part.len();
        let links = spans
            .iter()
            .enumerate()
            .filter(|(_, r)| (r.0 as usize) < end && (r.1 as usize) > start)
            .map(|(i, r)| {
                (
                    (r.0 as usize).saturating_sub(start),
                    (r.1 as usize).min(end) - start,
                    i as u32,
                )
            })
            .collect();
        paragraphs.push(ProseParagraph { text: part, links });
        cursor = end + 2;
    }
    paragraphs
}

/// One dictionary entry, typeset (ADR 0019): key label, headword line,
/// and the body through the same engine as everything else. Verse
/// references found in the prose are tappable link runs.
pub struct DictLayoutView {
    pub sort: u32,
    pub display_key: String,
    pub headword: String,
    pub pron: String,
    pub lines: Vec<LineView>,
    /// OSIS targets by `RunView.link` index.
    pub refs: Vec<String>,
    pub prev_sort: Option<u32>,
    pub next_sort: Option<u32>,
    pub units_per_em: u16,
    pub measure_units: i64,
    pub number_scale: f64,
    pub plain_text: String,
}

fn view_lines(lines: Vec<gramma_core::typeset::layout::LineOut>) -> Vec<LineView> {
    lines
        .into_iter()
        .map(|l| LineView {
            runs: l
                .runs
                .into_iter()
                .map(|r| RunView {
                    text: r.text,
                    x: r.x,
                    width: r.width,
                    verse_number: r.verse_number,
                    note_marker: r.note_marker,
                    heading_level: r.heading_level,
                    verse: r.verse,
                    link: r.link,
                    offset: r.offset,
                })
                .collect(),
        })
        .collect()
}

/// One stored entry as a typeset prose layout — the shared tail of the
/// dictionary and devotional paths.
fn entry_layout(
    measure: &FontMeasure<'_>,
    entry: gramma_core::library::DictEntryRow,
    prev_sort: Option<u32>,
    next_sort: Option<u32>,
    label: Option<&str>,
    justify: bool,
    measure_units: i64,
) -> DictLayoutView {
    let scanned = scan_references(&entry.text, None);
    let spans: Vec<(u32, u32)> = scanned.iter().map(|r| (r.start, r.end)).collect();
    let refs: Vec<String> = scanned.iter().map(|r| r.reference.to_string()).collect();
    let paragraphs = prose_paragraphs(&entry.text, &spans);
    let display = super::library::display_key(&entry.key, entry.sort);
    let heading = if entry.pron.is_empty() {
        entry.headword.clone()
    } else {
        format!("{} · {}", entry.headword, entry.pron)
    };
    let lines = layout_prose(
        label,
        (!heading.is_empty()).then_some(heading.as_str()),
        &paragraphs,
        0,
        measure,
        None,
        justify,
        measure_units,
    );
    let plain_text = format!("{display} {heading}. {}", entry.text.replace("\n\n", " "));
    DictLayoutView {
        sort: entry.sort,
        display_key: display,
        headword: entry.headword,
        pron: entry.pron,
        lines: view_lines(lines),
        refs,
        prev_sort,
        next_sort,
        units_per_em: measure.units_per_em(),
        measure_units,
        number_scale: VERSE_NUMBER_SCALE_PERCENT as f64 / 100.0,
        plain_text,
    }
}

/// Typeset one dictionary entry at `measure_ems` ems of its text size.
/// Async: shaping and breaking run on a worker thread.
pub fn layout_dict_entry(
    module_code: String,
    sort: u32,
    measure_ems: f64,
) -> anyhow::Result<Option<DictLayoutView>> {
    let measure = active_measure()?;
    let found = with_library(|library| library.dictionary_entry(&module_code, sort))?;
    let Some((entry, prev_sort, next_sort)) = found else {
        return Ok(None);
    };
    let measure_units = (measure_ems * measure.units_per_em() as f64) as i64;
    let display = super::library::display_key(&entry.key, entry.sort);
    // Dictionary entries set ragged (ADR 0026): the column is narrow
    // and the text dense with special characters — justification has
    // nothing to offer here.
    Ok(Some(entry_layout(
        measure,
        entry,
        prev_sort,
        next_sort,
        Some(&display),
        false,
        measure_units,
    )))
}

/// Typeset a devotional day's readings (ADR 0021): every section whose
/// sort lies in the day's range, in order. Async.
pub fn layout_devotional_day(
    module_code: String,
    month: u16,
    day: u16,
    measure_ems: f64,
) -> anyhow::Result<Vec<DictLayoutView>> {
    let measure = active_measure()?;
    let lo = (month as u32 * 100 + day as u32) * 10;
    let entries = with_library(|library| library.dict_entries_between(&module_code, lo, lo + 9))?;
    let measure_units = (measure_ems * measure.units_per_em() as f64) as i64;
    Ok(entries
        .into_iter()
        .map(|entry| entry_layout(measure, entry, None, None, None, true, measure_units))
        .collect())
}

/// One book section, typeset (ADR 0021).
pub struct BookLayoutView {
    pub ordinal: u32,
    pub level: u8,
    pub name: String,
    pub lines: Vec<LineView>,
    /// OSIS targets by `RunView.link` index.
    pub refs: Vec<String>,
    pub prev_ordinal: Option<u32>,
    pub next_ordinal: Option<u32>,
    pub units_per_em: u16,
    pub measure_units: i64,
    pub number_scale: f64,
    pub plain_text: String,
}

/// Typeset one section of a general book at `measure_ems` ems. Async.
pub fn layout_book_section(
    module_code: String,
    ordinal: u32,
    measure_ems: f64,
) -> anyhow::Result<Option<BookLayoutView>> {
    let measure = active_measure()?;
    let found = with_library(|library| library.book_section(&module_code, ordinal))?;
    let Some((section, prev_ordinal, next_ordinal)) = found else {
        return Ok(None);
    };
    let scanned = scan_references(&section.text, None);
    let spans: Vec<(u32, u32)> = scanned.iter().map(|r| (r.start, r.end)).collect();
    let refs: Vec<String> = scanned.iter().map(|r| r.reference.to_string()).collect();
    let paragraphs = prose_paragraphs(&section.text, &spans);
    let heading = section
        .heading
        .clone()
        .unwrap_or_else(|| section.name.clone());
    let measure_units = (measure_ems * measure.units_per_em() as f64) as i64;
    let lines = layout_prose(
        None,
        (!heading.is_empty()).then_some(heading.as_str()),
        &paragraphs,
        0,
        measure,
        None,
        true,
        measure_units,
    );
    let plain_text = format!("{heading}. {}", section.text.replace("\n\n", " "));
    Ok(Some(BookLayoutView {
        ordinal: section.ordinal,
        level: section.level,
        name: section.name,
        lines: view_lines(lines),
        refs,
        prev_ordinal,
        next_ordinal,
        units_per_em: measure.units_per_em(),
        measure_units,
        number_scale: VERSE_NUMBER_SCALE_PERCENT as f64 / 100.0,
        plain_text,
    }))
}

/// Text-line count of every chapter in the module's spine order, at the
/// canonical measure. This makes global line numbering possible, which the
/// multi-column reader chunks into viewport-sized columns — layout itself
/// never depends on the viewport.
pub fn module_line_counts(module_code: String, measure_ems: u16) -> anyhow::Result<Vec<u32>> {
    let measure = active_measure()?;
    let (contents, german) = with_library(|library| {
        let contents = library.contents(&module_code)?;
        let german = library
            .modules()?
            .iter()
            .any(|m| m.code == module_code && m.language.starts_with("de"));
        Ok((contents, german))
    })?;
    let hyphenator = german.then(|| {
        GERMAN.get_or_init(|| {
            Standard::from_embedded(Language::German1996).expect("embedded patterns")
        })
    });
    let measure_units = measure_ems as i64 * measure.units_per_em() as i64;
    let mut counts = Vec::with_capacity(contents.len());
    for c in &contents {
        let (verses, notes, headings) = with_library(|library| {
            Ok((
                library.chapter(&module_code, c.book, c.chapter)?,
                library.notes(&module_code, c.book, c.chapter)?,
                library.headings(&module_code, c.book, c.chapter)?,
            ))
        })?;
        let refs: Vec<(u16, &str)> = verses.iter().map(|v| (v.verse, v.text.as_str())).collect();
        let note_refs: Vec<(u16, u32)> = notes.iter().map(|n| (n.verse, n.offset)).collect();
        let heading_refs: Vec<(u16, u8, &str)> = headings
            .iter()
            .map(|h| (h.verse, h.level, h.text.as_str()))
            .collect();
        counts.push(
            layout_verses(
                &refs,
                &note_refs,
                &heading_refs,
                measure,
                hyphenator,
                measure_units,
            )
            .len() as u32,
        );
    }
    Ok(counts)
}
