use std::sync::OnceLock;

use anyhow::anyhow;
use gramma_core::reference::book_by_osis;
use gramma_core::typeset::layout::{layout_verses, VERSE_NUMBER_SCALE_PERCENT};
use gramma_core::typeset::shape::FontMeasure;
use hyphenation::{Language, Load, Standard};

use super::library::with_library;

/// The canonical measure: line width in ems, identical on every device.
/// Column pixel width divided by this gives the rendering font size.
pub const MEASURE_EMS: i64 = 26;

static MEASURE: OnceLock<FontMeasure<'static>> = OnceLock::new();
static GERMAN: OnceLock<Standard> = OnceLock::new();

pub struct RunView {
    pub text: String,
    /// Left edge in font units.
    pub x: f64,
    /// Shaped width in font units.
    pub width: f64,
    pub verse_number: bool,
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
) -> anyhow::Result<ChapterLayoutView> {
    let measure = MEASURE
        .get()
        .ok_or_else(|| anyhow!("typesetting not initialized"))?;
    let book = book_by_osis(&book_osis).ok_or_else(|| anyhow!("unknown book: {book_osis}"))?;
    let (verses, german) = with_library(|library| {
        let verses = library.chapter(&module_code, book, chapter)?;
        let german = library
            .modules()?
            .iter()
            .any(|m| m.code == module_code && m.language.starts_with("de"));
        Ok((verses, german))
    })?;
    let hyphenator = german.then(|| {
        GERMAN.get_or_init(|| {
            Standard::from_embedded(Language::German1996).expect("embedded patterns")
        })
    });
    let verse_refs: Vec<(u16, &str)> = verses.iter().map(|v| (v.verse, v.text.as_str())).collect();
    let measure_units = MEASURE_EMS * measure.units_per_em() as i64;
    let lines = layout_verses(&verse_refs, measure, hyphenator, measure_units);
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
