use std::sync::OnceLock;

use anyhow::anyhow;
use gramma_core::reference::book_by_osis;
use gramma_core::typeset::layout::{layout_verses, VERSE_NUMBER_SCALE_PERCENT};
use gramma_core::typeset::shape::FontMeasure;
use hyphenation::{Language, Load, Standard};

use super::library::with_library;

static MEASURE: OnceLock<FontMeasure<'static>> = OnceLock::new();
static GERMAN: OnceLock<Standard> = OnceLock::new();

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
    if MEASURE.get().is_some() {
        return Ok(());
    }
    // The face is parsed once and kept for the process lifetime; leaking the
    // buffer gives it the 'static lifetime it needs.
    let data: &'static [u8] = Box::leak(font_data.into_boxed_slice());
    let measure = FontMeasure::new(data).ok_or_else(|| anyhow!("cannot parse font"))?;
    let _ = MEASURE.set(measure);
    Ok(())
}

/// Async on purpose: runs on a worker thread so scrolling never blocks on
/// shaping and breaking.
pub fn layout_chapter(
    module_code: String,
    book_osis: String,
    chapter: u16,
    measure_ems: u16,
) -> anyhow::Result<ChapterLayoutView> {
    let measure = MEASURE
        .get()
        .ok_or_else(|| anyhow!("typesetting not initialized"))?;
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

/// Text-line count of every chapter in the module's spine order, at the
/// canonical measure. This makes global line numbering possible, which the
/// multi-column reader chunks into viewport-sized columns — layout itself
/// never depends on the viewport.
pub fn module_line_counts(module_code: String, measure_ems: u16) -> anyhow::Result<Vec<u32>> {
    let measure = MEASURE
        .get()
        .ok_or_else(|| anyhow!("typesetting not initialized"))?;
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
