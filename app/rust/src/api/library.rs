use std::fs::File;
use std::io::BufReader;
use std::path::Path;
use std::sync::Mutex;

use anyhow::{anyhow, Context};
use gramma_core::library::Library;
use gramma_core::reference::Reference;

static LIBRARY: Mutex<Option<Library>> = Mutex::new(None);

pub struct ModuleView {
    pub code: String,
    pub title: String,
    pub language: String,
    pub verses: u32,
}

pub struct VerseView {
    pub verse: u16,
    pub text: String,
}

pub struct ChapterView {
    pub osis: String,
    pub verses: Vec<VerseView>,
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
