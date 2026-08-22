//! OSIS XML parsing: turns an OSIS document into module metadata plus a flat
//! list of verses addressed by canonical book/chapter/verse.
//!
//! Both encoding styles found in CrossWire content are supported: container
//! verses (`<verse osisID="…">text</verse>`) and milestone verses
//! (`<verse sID="…"/>text<verse eID="…"/>`). Formatting markup (`w`, `hi`,
//! `seg`, `divineName`, …) is unwrapped to its text; `title` content is
//! excluded; `note` content is excluded from verse text but captured as a
//! footnote attached to its verse. Books outside the 66-book canon are
//! skipped.

use std::io::BufRead;

use quick_xml::Reader;
use quick_xml::events::{BytesStart, Event};

use crate::reference::{BookId, book_by_osis};

#[derive(Debug, thiserror::Error)]
pub enum OsisError {
    #[error("XML error: {0}")]
    Xml(#[from] quick_xml::Error),
    #[error("XML attribute error: {0}")]
    Attr(#[from] quick_xml::events::attributes::AttrError),
    #[error("osisText element has no osisIDWork attribute")]
    MissingWorkId,
    #[error("document contains no verses")]
    NoVerses,
}

#[derive(Debug)]
pub struct OsisDocument {
    pub code: String,
    pub title: String,
    pub language: String,
    pub verses: Vec<OsisVerse>,
    pub notes: Vec<OsisNote>,
}

#[derive(Debug)]
pub struct OsisVerse {
    pub book: BookId,
    pub chapter: u16,
    pub verse: u16,
    pub text: String,
}

/// A footnote attached to a verse; `seq` numbers multiple notes within one
/// verse starting at 1.
#[derive(Debug)]
pub struct OsisNote {
    pub book: BookId,
    pub chapter: u16,
    pub verse: u16,
    pub seq: u16,
    pub text: String,
}

pub fn parse(source: impl BufRead) -> Result<OsisDocument, OsisError> {
    let mut reader = Reader::from_reader(source);
    let mut buf = Vec::new();

    let mut code: Option<String> = None;
    let mut language = String::new();
    let mut title = String::new();
    let mut in_header = false;
    let mut capture_work_title = false;
    let mut skip_depth: u32 = 0;
    let mut note_depth: u32 = 0;
    let mut note_text = String::new();
    let mut current: Option<(BookId, u16, u16)> = None;
    let mut text = String::new();
    let mut verses: Vec<OsisVerse> = Vec::new();
    let mut notes: Vec<OsisNote> = Vec::new();

    loop {
        match reader.read_event_into(&mut buf)? {
            Event::Start(e) => match e.local_name().as_ref() {
                b"osisText" => {
                    code = attr(&e, b"osisIDWork");
                    if let Some(lang) = attr(&e, b"xml:lang") {
                        language = lang;
                    }
                }
                b"header" => in_header = true,
                b"title" if in_header => capture_work_title = title.is_empty(),
                b"title" => skip_depth += 1,
                b"note" => note_depth += 1,
                b"verse" => {
                    if let Some(id) = attr(&e, b"osisID") {
                        current = parse_osis_id(&id);
                        text.clear();
                    }
                }
                _ => {}
            },
            Event::Empty(e) => match e.local_name().as_ref() {
                b"verse" => {
                    if let Some(id) = attr(&e, b"sID").or_else(|| attr(&e, b"osisID")) {
                        current = parse_osis_id(&id);
                        text.clear();
                    } else if attr(&e, b"eID").is_some() {
                        commit(&mut current, &mut text, &mut verses);
                    }
                }
                b"lb" => text.push(' '),
                _ => {}
            },
            Event::End(e) => match e.local_name().as_ref() {
                b"header" => in_header = false,
                b"title" if in_header => capture_work_title = false,
                b"title" => skip_depth = skip_depth.saturating_sub(1),
                b"note" => {
                    note_depth = note_depth.saturating_sub(1);
                    if note_depth == 0 {
                        commit_note(&current, &mut note_text, &mut notes);
                    }
                }
                b"verse" => commit(&mut current, &mut text, &mut verses),
                _ => {}
            },
            Event::Text(t) => {
                let content = t
                    .xml_content(quick_xml::XmlVersion::Implicit1_0)
                    .map_err(quick_xml::Error::from)?;
                if capture_work_title {
                    title.push_str(&content);
                } else if note_depth > 0 {
                    if skip_depth == 0 && current.is_some() {
                        note_text.push_str(&content);
                    }
                } else if skip_depth == 0 && current.is_some() {
                    text.push_str(&content);
                }
            }
            Event::Eof => break,
            _ => {}
        }
        buf.clear();
    }

    if verses.is_empty() {
        return Err(OsisError::NoVerses);
    }
    Ok(OsisDocument {
        code: code.ok_or(OsisError::MissingWorkId)?,
        title: normalize(&title),
        language,
        verses,
        notes,
    })
}

fn commit_note(
    current: &Option<(BookId, u16, u16)>,
    note_text: &mut String,
    notes: &mut Vec<OsisNote>,
) {
    let text = normalize(note_text);
    note_text.clear();
    let Some((book, chapter, verse)) = *current else {
        return;
    };
    if text.is_empty() {
        return;
    }
    let seq = notes
        .last()
        .filter(|n| (n.book, n.chapter, n.verse) == (book, chapter, verse))
        .map(|n| n.seq + 1)
        .unwrap_or(1);
    notes.push(OsisNote {
        book,
        chapter,
        verse,
        seq,
        text,
    });
}

fn commit(
    current: &mut Option<(BookId, u16, u16)>,
    text: &mut String,
    verses: &mut Vec<OsisVerse>,
) {
    if let Some((book, chapter, verse)) = current.take() {
        let normalized = normalize(text);
        if !normalized.is_empty() {
            verses.push(OsisVerse {
                book,
                chapter,
                verse,
                text: normalized,
            });
        }
    }
    text.clear();
}

/// Resolve an osisID like `John.3.16` (for linked ids such as
/// `Gen.1.29 Gen.1.30` the first is used; subverse suffixes like `!a` are
/// dropped). Returns `None` for non-canonical books, whose verses are skipped.
fn parse_osis_id(id: &str) -> Option<(BookId, u16, u16)> {
    let first = id.split_whitespace().next()?;
    let first = first.split('!').next()?;
    let mut parts = first.split('.');
    let book = book_by_osis(parts.next()?)?;
    let chapter: u16 = parts.next()?.parse().ok()?;
    let verse: u16 = parts.next()?.parse().ok()?;
    Some((book, chapter, verse))
}

fn attr(e: &BytesStart, name: &[u8]) -> Option<String> {
    e.attributes()
        .flatten()
        .find(|a| a.key.as_ref() == name)
        .and_then(|a| a.normalized_value(quick_xml::XmlVersion::Implicit1_0).ok())
        .map(|v| v.into_owned())
}

fn normalize(s: &str) -> String {
    s.split_whitespace().collect::<Vec<_>>().join(" ")
}
