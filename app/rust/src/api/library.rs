use std::fs::File;
use std::io::BufReader;
use std::path::Path;
use std::sync::Mutex;

use anyhow::{anyhow, Context};
use gramma_core::library::Library;
use gramma_core::reference::{book_by_osis, Reference};

static LIBRARY: Mutex<Option<Library>> = Mutex::new(None);

/// Run `f` against the opened library (bridge-internal helper).
#[flutter_rust_bridge::frb(ignore)]
pub(crate) fn with_library<T>(
    f: impl FnOnce(&Library) -> Result<T, gramma_core::library::LibraryError>,
) -> anyhow::Result<T> {
    let guard = LIBRARY.lock().unwrap();
    let library = guard
        .as_ref()
        .ok_or_else(|| anyhow!("library not opened"))?;
    Ok(f(library)?)
}

pub struct ModuleView {
    pub code: String,
    pub title: String,
    pub language: String,
    pub verses: u32,
    pub notes: u32,
}

pub struct VerseView {
    pub verse: u16,
    pub text: String,
}

pub struct NoteView {
    pub verse: u16,
    /// Marker letter matching the inline marker in the text ("a", "b", …).
    pub label: String,
    pub text: String,
}

pub struct ChapterView {
    pub osis: String,
    pub verses: Vec<VerseView>,
}

/// One entry of a module's chapter spine, with a heading localized to the
/// module's language (German book names for `de` modules, English otherwise).
pub struct ChapterRefView {
    pub book_osis: String,
    pub chapter: u16,
    pub heading: String,
    /// Chapter text length in bytes, for scroll-height estimation.
    pub text_length: i64,
    /// Highest verse number in the chapter.
    pub max_verse: u16,
    /// Concise display abbreviation of the book.
    pub book_abbrev: String,
    /// Traditional canon grouping (0..8), for the book-grid palette.
    pub book_category: u8,
}

#[flutter_rust_bridge::frb(sync)]
pub fn open_library(path: String) -> anyhow::Result<()> {
    let library = Library::open(Path::new(&path))?;
    *LIBRARY.lock().unwrap() = Some(library);
    Ok(())
}

pub fn import_osis_file(path: String) -> anyhow::Result<ModuleView> {
    let source = BufReader::new(File::open(&path).with_context(|| format!("open {path}"))?);
    let mut guard = LIBRARY.lock().unwrap();
    let library = guard
        .as_mut()
        .ok_or_else(|| anyhow!("library not opened"))?;
    let info = library.import_osis(source)?;
    Ok(ModuleView {
        code: info.code,
        title: info.title,
        language: info.language,
        verses: info.verses,
        notes: info.notes,
    })
}

#[flutter_rust_bridge::frb(sync)]
pub fn modules() -> anyhow::Result<Vec<ModuleView>> {
    let guard = LIBRARY.lock().unwrap();
    let library = guard
        .as_ref()
        .ok_or_else(|| anyhow!("library not opened"))?;
    Ok(library
        .modules()?
        .into_iter()
        .map(|m| ModuleView {
            code: m.code,
            title: m.title,
            language: m.language,
            verses: m.verses,
            notes: m.notes,
        })
        .collect())
}

#[flutter_rust_bridge::frb(sync)]
pub fn contents(module_code: String) -> anyhow::Result<Vec<ChapterRefView>> {
    let guard = LIBRARY.lock().unwrap();
    let library = guard
        .as_ref()
        .ok_or_else(|| anyhow!("library not opened"))?;
    let german = library
        .modules()?
        .iter()
        .find(|m| m.code == module_code)
        .is_some_and(|m| m.language.starts_with("de"));
    Ok(library
        .contents(&module_code)?
        .into_iter()
        .map(|c| {
            let info = c.book.info();
            let name = if german { info.german } else { info.english };
            ChapterRefView {
                book_osis: info.osis.to_string(),
                chapter: c.chapter,
                heading: format!("{name} {}", c.chapter),
                text_length: c.text_length,
                max_verse: c.max_verse,
                book_abbrev: if german {
                    info.abbrev.to_string()
                } else {
                    info.osis.to_string()
                },
                book_category: c.book.category().index(),
            }
        })
        .collect())
}

/// Footnotes of one chapter, ordered by verse and sequence.
#[flutter_rust_bridge::frb(sync)]
pub fn chapter_notes(
    module_code: String,
    book_osis: String,
    chapter: u16,
) -> anyhow::Result<Vec<NoteView>> {
    let book = book_by_osis(&book_osis).ok_or_else(|| anyhow!("unknown book: {book_osis}"))?;
    with_library(|library| library.notes(&module_code, book, chapter)).map(|notes| {
        notes
            .into_iter()
            .map(|n| NoteView {
                verse: n.verse,
                label: ((b'a' + ((n.seq - 1) as u8).min(25)) as char).to_string(),
                text: n.text,
            })
            .collect()
    })
}

#[flutter_rust_bridge::frb(sync)]
pub fn chapter_verses(
    module_code: String,
    book_osis: String,
    chapter: u16,
) -> anyhow::Result<Vec<VerseView>> {
    let book = book_by_osis(&book_osis).ok_or_else(|| anyhow!("unknown book: {book_osis}"))?;
    let guard = LIBRARY.lock().unwrap();
    let library = guard
        .as_ref()
        .ok_or_else(|| anyhow!("library not opened"))?;
    Ok(library
        .chapter(&module_code, book, chapter)?
        .into_iter()
        .map(|v| VerseView {
            verse: v.verse,
            text: v.text,
        })
        .collect())
}

/// Resolve a reference and return the containing chapter of the given module.
#[flutter_rust_bridge::frb(sync)]
pub fn chapter(module_code: String, reference: String) -> anyhow::Result<ChapterView> {
    let parsed: Reference = reference
        .parse()
        .map_err(|e| anyhow!("invalid reference: {e}"))?;
    let (book, chapter_no) = match parsed {
        Reference::Chapter { book, chapter } => (book, chapter),
        Reference::Verse(v) => (v.book, v.chapter),
        Reference::VerseRange { start, .. } => (start.book, start.chapter),
    };
    let guard = LIBRARY.lock().unwrap();
    let library = guard
        .as_ref()
        .ok_or_else(|| anyhow!("library not opened"))?;
    let verses = library
        .chapter(&module_code, book, chapter_no)?
        .into_iter()
        .map(|v| VerseView {
            verse: v.verse,
            text: v.text,
        })
        .collect();
    Ok(ChapterView {
        osis: Reference::Chapter {
            book,
            chapter: chapter_no,
        }
        .to_string(),
        verses,
    })
}
