//! Interpretation (ADR 0029): what kind of document this is, and its
//! conversion into what the library stores — a Bible text into verses,
//! headings, and notes; a commentary into passage-anchored entries; a
//! general book into sections — with scripture references resolved
//! against the document's own context.

use std::collections::HashMap;

use serde::{Deserialize, Serialize};

use super::{Block, Document, Inline, Note, ParagraphStyle, plain_text};
use crate::osis::{OsisDocument, OsisHeading, OsisNote, OsisVerse};
use crate::reference::{
    BookId, Reference, ReferenceContext, VerseRef, book_by_alias, parse_reference_prefix,
    scan_references_in,
};
use crate::sword::{BookSection, CommentRef, CommentaryEntry};

/// The three shapes a document can take in the library.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum DocumentKind {
    Bible,
    Commentary,
    Book,
}

/// What detection saw, for the import dialog.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Detection {
    pub kind: DocumentKind,
    /// Verse-number markers found.
    pub verse_numbers: usize,
    /// Chapters recognized (milestones or chapter headings).
    pub chapters: usize,
    /// Scripture references recognized in the text.
    pub references: usize,
    /// The book a commentary is about, as OSIS id.
    pub subject_book: Option<String>,
    pub headings: usize,
    pub notes: usize,
    pub images: usize,
}

/// Decide the document's kind from its own evidence.
pub fn detect(doc: &Document) -> Detection {
    let mut verse_numbers = 0;
    let mut paragraphs = 0;
    let mut headings = 0;
    let mut scripture = 0;
    for block in walk(&doc.blocks) {
        match block {
            Block::Paragraph { inlines, style } => {
                paragraphs += 1;
                if *style == ParagraphStyle::Scripture {
                    scripture += 1;
                }
                verse_numbers += inlines
                    .iter()
                    .filter(|i| matches!(i, Inline::VerseNumber(_)))
                    .count();
            }
            Block::Heading { .. } => headings += 1,
            _ => {}
        }
    }
    let chapters = chapter_starts(doc).len();
    let subject = subject_book(doc);
    let (sample_refs, sampled) = sample_reference_count(doc, subject);
    // Bible: verse markers through chapters. Commentary: a subject book
    // with quoted verses or a reference density a treatise never has.
    let dense = sample_refs * 100 >= sampled.max(1) * 15 && sample_refs >= 3;
    let kind = if verse_numbers >= 50 && chapters >= 2 && verse_numbers * 2 >= paragraphs {
        DocumentKind::Bible
    } else if subject.is_some()
        && (scripture >= 10 || dense || (scripture >= 2 && sample_refs >= 3))
    {
        DocumentKind::Commentary
    } else {
        DocumentKind::Book
    };
    Detection {
        kind,
        verse_numbers,
        chapters,
        references: sample_refs,
        subject_book: subject.map(|b| b.info().osis.to_string()),
        headings,
        notes: doc.notes.len(),
        images: doc.images.len(),
    }
}

/// Every block, depth first.
fn walk(blocks: &[Block]) -> Vec<&Block> {
    let mut out = Vec::new();
    for b in blocks {
        out.push(b);
        if let Block::List { items, .. } = b {
            for item in items {
                out.extend(walk(item));
            }
        }
    }
    out
}

/// References in the first ~200 paragraphs, resolved against the
/// subject: (references found, paragraphs sampled).
fn sample_reference_count(doc: &Document, subject: Option<BookId>) -> (usize, usize) {
    let ctx = ReferenceContext {
        book: subject,
        chapter: None,
    };
    let mut refs = 0;
    let mut sampled = 0;
    for text in walk(&doc.blocks)
        .into_iter()
        .filter_map(|b| match b {
            Block::Paragraph { inlines, .. } => Some(plain_text(inlines)),
            _ => None,
        })
        .take(200)
    {
        sampled += 1;
        refs += scan_references_in(&text, ctx).len();
    }
    (refs, sampled)
}

/// The book a commentary treats: from its title ("Kommentar zum
/// Römerbrief"), else the book its text references far more than any
/// other (explicit references only: the title book of a commentary is
/// named on nearly every page).
pub fn subject_book(doc: &Document) -> Option<BookId> {
    if let Some(book) = book_in_title(&doc.title) {
        return Some(book);
    }
    let mut counts: HashMap<BookId, usize> = HashMap::new();
    for block in walk(&doc.blocks) {
        let text = match block {
            Block::Heading { inlines, .. } | Block::Paragraph { inlines, .. } => {
                plain_text(inlines)
            }
            _ => continue,
        };
        for r in scan_references_in(&text, ReferenceContext::default()) {
            *counts.entry(book_of(r.reference)).or_default() += 1;
        }
    }
    let mut ranked: Vec<(BookId, usize)> = counts.into_iter().collect();
    ranked.sort_by_key(|(_, n)| std::cmp::Reverse(*n));
    match ranked.as_slice() {
        [(book, top), rest @ ..]
            if *top >= 20 && rest.first().is_none_or(|(_, second)| *top >= second * 2) =>
        {
            Some(*book)
        }
        _ => None,
    }
}

/// A book name inside free text: whole words and words minus a "brief"
/// suffix ("Römerbrief" → Römer), with ordinals ("1. Korinther").
pub fn book_in_title(title: &str) -> Option<BookId> {
    let words: Vec<&str> = title
        .split(|c: char| !c.is_alphanumeric() && c != '.')
        .filter(|w| !w.is_empty())
        .collect();
    for i in 0..words.len() {
        for len in (1..=3).rev() {
            if i + len > words.len() {
                continue;
            }
            let candidate = words[i..i + len].join(" ");
            for variant in name_variants(&candidate) {
                if let Some(book) = book_by_alias(&variant) {
                    return Some(book);
                }
            }
        }
    }
    None
}

fn name_variants(candidate: &str) -> Vec<String> {
    let mut out = vec![candidate.to_string()];
    for suffix in ["brief", "briefes", "-Brief", "evangelium", "buch"] {
        if let Some(stem) = candidate.strip_suffix(suffix) {
            out.push(stem.trim_end_matches('-').to_string());
        }
    }
    out
}

fn book_of(reference: Reference) -> BookId {
    match reference {
        Reference::Chapter { book, .. } => book,
        Reference::Verse(v) => v.book,
        Reference::VerseRange { start, .. } => start.book,
    }
}

/// A display title set on two lines — "Psalm" above a large "1" — arrives
/// as two headings; read them as one for structure ("Psalm 1").
pub fn joined_heading_text(blocks: &[Block], i: usize) -> Option<String> {
    let Block::Heading { inlines, .. } = &blocks[i] else {
        return None;
    };
    let text = plain_text(inlines);
    let numeric = |t: &str| !t.is_empty() && t.trim().chars().all(|c| c.is_ascii_digit());
    if numeric(&text) {
        // Consumed by the heading before it.
        if i > 0
            && let Block::Heading { inlines: prev, .. } = &blocks[i - 1]
            && !numeric(&plain_text(prev))
            && plain_text(prev).split_whitespace().count() <= 3
        {
            return Some(String::new());
        }
        return Some(text);
    }
    if text.split_whitespace().count() <= 3
        && let Some(Block::Heading { inlines: next, .. }) = blocks.get(i + 1)
        && numeric(&plain_text(next))
    {
        return Some(format!("{} {}", text.trim(), plain_text(next).trim()));
    }
    Some(text)
}

/// Chapter starts in a Bible-shaped document: (block index, book, chapter).
fn chapter_starts(doc: &Document) -> Vec<(usize, BookId, u16)> {
    let mut out = Vec::new();
    let mut current_book: Option<BookId> = None;
    // Book titles sit at one heading level; deeper headings are section
    // titles even when they mention a book ("Hiob antwortet").
    let mut book_level: Option<u8> = None;
    for (i, block) in doc.blocks.iter().enumerate() {
        match block {
            Block::Milestone { osis } => {
                if let Some((book, chapter)) = parse_milestone(osis) {
                    current_book = Some(book);
                    out.push((i, book, chapter));
                }
            }
            Block::Heading { level, .. } => {
                let text = joined_heading_text(&doc.blocks, i).unwrap_or_default();
                if text.is_empty() {
                    continue;
                }
                let mut meaning = heading_meaning(&text, current_book);
                if let HeadingMeaning::Book(_) = meaning
                    && book_level.is_some_and(|l| *level > l)
                {
                    meaning = HeadingMeaning::Title;
                }
                if let HeadingMeaning::Book(_) = meaning
                    && book_level.is_none()
                {
                    book_level = Some(*level);
                }
                match meaning {
                    HeadingMeaning::Book(book) => {
                        current_book = Some(book);
                        // A book opens at chapter 1 unless a chapter
                        // heading says otherwise (producers often leave
                        // the first chapter number implicit).
                        out.push((i, book, 1));
                    }
                    HeadingMeaning::Chapter(book, chapter) => {
                        current_book = Some(book);
                        // A milestone or book heading may have announced
                        // this chapter already.
                        if out
                            .last()
                            .is_none_or(|(_, b, c)| (*b, *c) != (book, chapter))
                        {
                            out.push((i, book, chapter));
                        }
                    }
                    HeadingMeaning::Title => {}
                }
            }
            _ => {}
        }
    }
    out
}

fn parse_milestone(osis: &str) -> Option<(BookId, u16)> {
    let mut parts = osis.split('.');
    let book = crate::reference::book_by_osis(parts.next()?)?;
    let chapter: u16 = parts.next()?.parse().ok()?;
    Some((book, chapter))
}

#[derive(Debug, Clone, Copy, PartialEq)]
enum HeadingMeaning {
    /// A book title ("Das erste Buch Mose (Genesis)").
    Book(BookId),
    /// A chapter start ("Esther 4", "Kapitel 3", "3").
    Chapter(BookId, u16),
    /// Any other heading.
    Title,
}

fn heading_meaning(text: &str, current_book: Option<BookId>) -> HeadingMeaning {
    let t = text.trim();
    // "3" or "Kapitel 3" / "Psalm 23" inside the current book.
    let digits_only = !t.is_empty() && t.chars().all(|c| c.is_ascii_digit());
    if digits_only && let (Some(book), Ok(n)) = (current_book, t.parse::<u16>()) {
        return HeadingMeaning::Chapter(book, n);
    }
    for prefix in ["Kapitel ", "Kap. ", "Chapter ", "Psalm "] {
        if let Some(rest) = t.strip_prefix(prefix)
            && let Ok(n) = rest.trim().parse::<u16>()
            && let Some(book) = current_book
        {
            return HeadingMeaning::Chapter(book, n);
        }
    }
    // "Esther 4": a reference of chapter form with nothing after it.
    if let Some((Reference::Chapter { book, chapter }, consumed)) = parse_reference_prefix(t)
        && t[consumed..].trim().is_empty()
    {
        return HeadingMeaning::Chapter(book, chapter);
    }
    // "Das erste Buch Mose (Genesis)", "Die Psalmen", "Der Brief des
    // Apostels Paulus an die Römer": a book name on a heading without
    // digits.
    if !t.chars().any(|c| c.is_ascii_digit()) || t.starts_with(|c: char| c.is_ascii_digit()) {
        if let Some(book) = book_by_alias(t) {
            return HeadingMeaning::Book(book);
        }
        if let Some(book) = book_in_heading(t) {
            return HeadingMeaning::Book(book);
        }
    }
    HeadingMeaning::Title
}

/// The book named by a title-style heading: a parenthesized alias
/// ("(Numeri)"), else the first word that is a book name, with the
/// heading's ordinal ("Der erste Brief … an die Korinther" → 1. Korinther)
/// tried before the bare word. Function words never count.
pub fn book_in_heading(t: &str) -> Option<BookId> {
    let words: Vec<&str> = t
        .split(|c: char| !c.is_alphabetic() && c != '.')
        .filter(|w| !w.is_empty())
        .collect();
    if words.len() > 12 {
        return None;
    }
    if let Some(start) = t.find('(')
        && let Some(end) = t[start..].find(')')
        && let Some(book) = book_by_alias(t[start + 1..start + end].trim())
    {
        return Some(book);
    }
    let ordinal = words.iter().find_map(|w| {
        let l = w.to_lowercase();
        let l = l.trim_end_matches('.');
        match l {
            "erste" | "erstes" | "erster" | "first" | "1" | "i" => Some("1."),
            "zweite" | "zweites" | "zweiter" | "second" | "2" | "ii" => Some("2."),
            "dritte" | "drittes" | "dritter" | "third" | "3" | "iii" => Some("3."),
            "vierte" | "viertes" | "fourth" | "4" => Some("4."),
            "fünfte" | "fünftes" | "fifth" | "5" => Some("5."),
            _ => None,
        }
    });
    const STOP: &[&str] = &[
        "das",
        "der",
        "die",
        "des",
        "dem",
        "den",
        "ein",
        "eine",
        "buch",
        "bücher",
        "brief",
        "briefe",
        "evangelium",
        "nach",
        "an",
        "und",
        "von",
        "durch",
        "propheten",
        "prophet",
        "apostels",
        "apostel",
        "paulus",
        "jesu",
        "christi",
        "the",
        "of",
        "book",
        "epistle",
        "gospel",
        "according",
        "to",
        "letter",
        "first",
        "second",
        "third",
        "erste",
        "zweite",
        "dritte",
        "vierte",
        "fünfte",
    ];
    for word in &words {
        let lower = word.to_lowercase();
        if STOP.contains(&lower.trim_end_matches('.')) {
            continue;
        }
        if let Some(n) = ordinal
            && let Some(book) = book_by_alias(&format!("{n} {word}"))
        {
            return Some(book);
        }
        if ordinal.is_none()
            && let Some(book) = book_by_alias(word)
        {
            return Some(book);
        }
    }
    // With an ordinal but no ordinal match, a plain name still counts
    // ("Das erste Buch der Chronik" fails only on the alias side).
    if ordinal.is_some() {
        for word in &words {
            let lower = word.to_lowercase();
            if STOP.contains(&lower.trim_end_matches('.')) {
                continue;
            }
            if let Some(book) = book_by_alias(word) {
                return Some(book);
            }
        }
    }
    None
}

/// A Bible text for the library: verses split at their numbers, section
/// headings attached to the verse they precede, notes anchored by marker
/// or by their "(chapter,verse)" locator.
pub fn to_bible(doc: &Document, code: &str) -> Result<OsisDocument, InterpretError> {
    let mut out = OsisDocument {
        code: code.to_string(),
        title: doc.title.clone(),
        language: doc.language.clone(),
        verses: Vec::new(),
        notes: Vec::new(),
        headings: Vec::new(),
    };
    let starts = chapter_starts(doc);
    if starts.is_empty() {
        return Err(InterpretError::NoChapters);
    }
    let mut start_at: HashMap<usize, (BookId, u16)> =
        starts.iter().map(|(i, b, c)| (*i, (*b, *c))).collect();
    let mut book: Option<BookId> = None;
    let mut chapter: u16 = 0;
    let mut verse: u16 = 0;
    // Section headings rank below the book title's level: the next level
    // down is a section (1), anything deeper a subsection (2).
    let book_level: u8 = doc
        .blocks
        .iter()
        .enumerate()
        .find_map(|(i, b)| match b {
            Block::Heading { level, .. } => {
                let text = joined_heading_text(&doc.blocks, i).unwrap_or_default();
                matches!(heading_meaning(&text, None), HeadingMeaning::Book(_)).then_some(*level)
            }
            _ => None,
        })
        .unwrap_or(1);
    let mut pending_headings: Vec<(u8, String)> = Vec::new();
    let mut note_seq: HashMap<(BookId, u16, u16), u16> = HashMap::new();
    // Unreferenced notes with a "(c,v)" locator, bound after the text.
    let mut located_notes: Vec<(BookId, u16, u16, String)> = Vec::new();
    let mut used_notes = vec![false; doc.notes.len()];
    for (i, block) in doc.blocks.iter().enumerate() {
        if let Some((b, c)) = start_at.remove(&i) {
            book = Some(b);
            chapter = c;
            verse = 0;
            pending_headings.clear();
        }
        let Some(current_book) = book else {
            continue;
        };
        match block {
            Block::Heading { level, .. } => {
                let text = joined_heading_text(&doc.blocks, i).unwrap_or_default();
                if text.is_empty() {
                    continue;
                }
                if matches!(heading_meaning(&text, book), HeadingMeaning::Title) && chapter > 0 {
                    let relative = level.saturating_sub(book_level).clamp(1, 2);
                    pending_headings.push((relative, text));
                }
            }
            Block::Paragraph { inlines, .. }
                if chapter > 0
                    && !inlines.iter().any(|i| matches!(i, Inline::VerseNumber(_)))
                    && let Some((level, text)) = heading_like(inlines) =>
            {
                // A section title set apart (short, italic or bold) or a
                // line of parallel passages: headings before the next
                // verse, never verse text.
                pending_headings.push((level, text));
            }
            Block::Paragraph { inlines, .. } if chapter > 0 => {
                // Split at verse numbers; text before the first number
                // continues the previous verse (or opens verse 1 when it
                // starts with "1 ").
                let mut segments: Vec<(Option<u16>, Vec<Inline>)> = vec![(None, Vec::new())];
                for inline in inlines {
                    match inline {
                        Inline::VerseNumber(n) => segments.push((Some(*n), Vec::new())),
                        other => segments.last_mut().expect("segment").1.push(other.clone()),
                    }
                }
                for (number, seg) in segments {
                    let mut text = plain_text(&seg).trim().to_string();
                    let number = number.or_else(|| {
                        // A leading "1 " on a chapter's first paragraph.
                        let digits = text.chars().take_while(|c| c.is_ascii_digit()).count();
                        if verse == 0
                            && digits > 0
                            && digits <= 3
                            && text[digits..].starts_with(' ')
                        {
                            let n: u16 = text[..digits].parse().ok()?;
                            text = text[digits..].trim_start().to_string();
                            // A drop-cap chapter number opens verse 1.
                            Some(if n == chapter { 1 } else { n })
                        } else {
                            None
                        }
                    });
                    if let Some(n) = number {
                        verse = n;
                        let seq_base = out
                            .headings
                            .iter()
                            .filter(|h| {
                                h.book == current_book && h.chapter == chapter && h.verse == n
                            })
                            .count() as u16;
                        for (k, (level, heading)) in pending_headings.drain(..).enumerate() {
                            out.headings.push(OsisHeading {
                                book: current_book,
                                chapter,
                                verse: n,
                                seq: seq_base + k as u16 + 1,
                                level,
                                text: heading,
                            });
                        }
                        out.verses.push(OsisVerse {
                            book: current_book,
                            chapter,
                            verse: n,
                            text: String::new(),
                        });
                    }
                    if verse == 0 {
                        // Prose before any verse (front matter, book intro).
                        continue;
                    }
                    let Some(last) = out.verses.last_mut() else {
                        continue;
                    };
                    // Note markers anchor at their offset in the verse text.
                    let mut offset_text = String::new();
                    for inline in &seg {
                        match inline {
                            Inline::Text { text, .. } | Inline::Reference { text, .. } => {
                                offset_text.push_str(text)
                            }
                            Inline::LineBreak => offset_text.push(' '),
                            Inline::NoteRef(index) => {
                                if let Some(note) = doc.notes.get(*index) {
                                    used_notes[*index] = true;
                                    let key = (current_book, chapter, verse);
                                    let seq = note_seq.entry(key).or_default();
                                    *seq += 1;
                                    let prefix_len = normalized_len(&last.text, &offset_text);
                                    out.notes.push(OsisNote {
                                        book: current_book,
                                        chapter,
                                        verse,
                                        seq: *seq,
                                        offset: prefix_len as u32,
                                        text: note_text(note),
                                    });
                                }
                            }
                            Inline::VerseNumber(_) => {}
                        }
                    }
                    if !text.is_empty() {
                        if !last.text.is_empty() {
                            last.text.push(' ');
                        }
                        last.text.push_str(&collapse(&text));
                    }
                }
            }
            _ => {}
        }
    }
    // Notes nobody marked: "(c,v)" locators bind them to a verse.
    for (index, note) in doc.notes.iter().enumerate() {
        if used_notes[index] {
            continue;
        }
        let text = note_text(note);
        if let Some((c, v, rest)) = locator(&text) {
            // The locator's book is the book the note follows in the
            // source; approximate with the book of the last verse whose
            // chapter matches, searching backwards from the end.
            if let Some(verse_row) = out
                .verses
                .iter()
                .rev()
                .find(|vr| vr.chapter == c && vr.verse == v)
            {
                located_notes.push((verse_row.book, c, v, rest));
            }
        }
    }
    for (book, chapter, verse, text) in located_notes {
        let seq = note_seq.entry((book, chapter, verse)).or_default();
        *seq += 1;
        let offset = out
            .verses
            .iter()
            .find(|v| v.book == book && v.chapter == chapter && v.verse == verse)
            .map(|v| v.text.len() as u32)
            .unwrap_or(0);
        out.notes.push(OsisNote {
            book,
            chapter,
            verse,
            seq: *seq,
            offset,
            text,
        });
    }
    if out.verses.is_empty() {
        return Err(InterpretError::NoVerses);
    }
    Ok(out)
}

/// A paragraph without verse numbers that reads as a heading: short and
/// wholly italic or bold (a section title, level 1), or made of
/// scripture references only (a parallel-passage line, level 2).
fn heading_like(inlines: &[Inline]) -> Option<(u8, String)> {
    let text = collapse(&plain_text(inlines));
    if text.is_empty() || text.chars().count() > 120 {
        return None;
    }
    let styled = inlines.iter().all(|i| match i {
        Inline::Text { text, style } => {
            text.trim().is_empty() || style.italic || style.bold || style.small_caps
        }
        Inline::LineBreak => true,
        _ => false,
    });
    if styled && !text.ends_with('.') {
        return Some((1, text));
    }
    let refs = scan_references_in(&text, ReferenceContext::default());
    if refs.is_empty() {
        return None;
    }
    let covered: usize = refs.iter().map(|r| (r.end - r.start) as usize).sum();
    let letters = text
        .chars()
        .filter(|c| !c.is_whitespace() && *c != ';' && *c != ',')
        .count();
    (covered * 10 >= text.len() * 8 && letters > 0).then_some((2, text))
}

/// Length of `verse_text` plus the not-yet-appended `pending` text, as
/// the offset a note marker will have once the segment is appended.
fn normalized_len(verse_text: &str, pending: &str) -> usize {
    let pending = collapse(pending.trim_start());
    if verse_text.is_empty() {
        pending.len()
    } else if pending.is_empty() {
        verse_text.len()
    } else {
        verse_text.len() + 1 + pending.len()
    }
}

fn collapse(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    let mut space = false;
    for c in text.chars() {
        if c.is_whitespace() {
            space = true;
        } else {
            if space && !out.is_empty() {
                out.push(' ');
            }
            space = false;
            out.push(c);
        }
    }
    out
}

/// "(2,7) text" → (2, 7, "text").
fn locator(text: &str) -> Option<(u16, u16, String)> {
    let t = text.trim_start();
    let inner = t.strip_prefix('(')?;
    let end = inner.find(')')?;
    let (c, v) = inner[..end].split_once(',')?;
    let c: u16 = c.trim().parse().ok()?;
    let v: u16 = v.trim().parse().ok()?;
    Some((c, v, inner[end + 1..].trim().to_string()))
}

fn note_text(note: &Note) -> String {
    note.blocks
        .iter()
        .filter_map(|b| match b {
            Block::Paragraph { inlines, .. } | Block::Heading { inlines, .. } => {
                Some(collapse(&plain_text(inlines)))
            }
            _ => None,
        })
        .collect::<Vec<_>>()
        .join("\n\n")
}

/// Rich content of one library entry: its blocks with the notes they
/// reference (indices local to this entry) and image indices into the
/// module's image table.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct EntryContent {
    pub blocks: Vec<Block>,
    pub notes: Vec<Note>,
}

/// A commentary for the library: sections anchored to the passages their
/// headings and quoted scripture name; each entry carries plain text for
/// the existing views and its block tree for rich rendering.
pub struct CommentaryDocument {
    pub book: BookId,
    pub entries: Vec<CommentaryEntry>,
    pub contents: Vec<EntryContent>,
}

pub fn to_commentary(
    doc: &Document,
    subject: Option<BookId>,
) -> Result<CommentaryDocument, InterpretError> {
    let book = subject
        .or_else(|| subject_book(doc))
        .ok_or(InterpretError::NoSubject)?;
    let mut entries: Vec<CommentaryEntry> = Vec::new();
    let mut contents: Vec<EntryContent> = Vec::new();
    // The section under construction.
    let mut chapter: u16 = 0;
    let mut verse_start: u16 = 0;
    let mut verse_end: u16 = 0;
    let mut heading: Option<String> = None;
    let mut blocks: Vec<Block> = Vec::new();
    let mut notes: Vec<Note> = Vec::new();
    let mut note_index: HashMap<usize, usize> = HashMap::new();
    let mut open = false;

    macro_rules! close_entry {
        () => {
            if open && !blocks.is_empty() {
                let ctx = ReferenceContext {
                    book: Some(book),
                    chapter: (chapter > 0).then_some(chapter),
                };
                let resolved: Vec<Block> =
                    blocks.drain(..).map(|b| resolve_block(b, ctx)).collect();
                let (text, refs) = entry_text(&resolved, &notes);
                // Verse 0 is the chapter's introduction (the SWORD
                // convention); chapter 0 is the document's front matter,
                // filed under chapter 1.
                entries.push(CommentaryEntry {
                    book,
                    chapter: chapter.max(1),
                    verse_start,
                    verse_end: verse_end.max(verse_start),
                    heading: heading.take(),
                    text,
                    refs,
                });
                contents.push(EntryContent {
                    blocks: resolved,
                    notes: std::mem::take(&mut notes),
                });
                note_index.clear();
            } else {
                blocks.clear();
            }
            #[allow(unused_assignments)]
            {
                open = false;
            }
        };
    }

    for (i, block) in doc.blocks.iter().enumerate() {
        match block {
            Block::Heading { .. } => {
                let text = joined_heading_text(&doc.blocks, i).unwrap_or_default();
                if text.is_empty() {
                    continue;
                }
                close_entry!();
                // The heading's own references set the passage.
                let ctx = ReferenceContext {
                    book: Some(book),
                    chapter: (chapter > 0).then_some(chapter),
                };
                let refs = scan_references_in(&text, ctx);
                if let Some(r) = refs
                    .iter()
                    .map(|r| r.reference)
                    .find(|r| book_of(*r) == book)
                {
                    match r {
                        Reference::Chapter { chapter: c, .. } => {
                            chapter = c;
                            verse_start = 0;
                            verse_end = 0;
                        }
                        Reference::Verse(v) => {
                            chapter = v.chapter;
                            verse_start = v.verse;
                            verse_end = v.verse;
                        }
                        Reference::VerseRange { start, end_verse } => {
                            chapter = start.chapter;
                            verse_start = start.verse;
                            verse_end = end_verse;
                        }
                    }
                }
                heading = Some(text);
                open = true;
            }
            Block::Paragraph {
                style: ParagraphStyle::Scripture,
                inlines,
            } => {
                // A quoted verse opens an entry for that verse.
                let text = plain_text(inlines);
                if let Some(n) = leading_number(&text) {
                    close_entry!();
                    verse_start = n;
                    verse_end = n;
                    // Extend the previous entry's range up to this verse.
                    if let Some(prev) = entries.last_mut()
                        && prev.chapter == chapter.max(1)
                        && prev.verse_end < n
                        && prev.verse_start > 0
                    {
                        prev.verse_end = n - 1;
                    }
                    open = true;
                }
                blocks.push(relocate_notes(
                    block.clone(),
                    doc,
                    &mut notes,
                    &mut note_index,
                ));
            }
            Block::List {
                ordered: true,
                items,
            } if chapter > 0 && verse_numbered_list(items) => {
                for (k, item) in items.iter().enumerate() {
                    // The item's own number when its text keeps it
                    // ("2. Und nun …"), else its position.
                    let n = item
                        .first()
                        .and_then(|b| match b {
                            Block::Paragraph { inlines, .. } => {
                                leading_number_dot(&plain_text(inlines))
                            }
                            _ => None,
                        })
                        .unwrap_or(k as u16 + 1);
                    close_entry!();
                    verse_start = n;
                    verse_end = n;
                    open = true;
                    for b in item {
                        blocks.push(relocate_notes(b.clone(), doc, &mut notes, &mut note_index));
                    }
                }
            }
            Block::Paragraph { inlines, .. }
                if chapter > 0
                    && (verse_lead(&plain_text(inlines)).is_some()
                        || bold_number_lead(inlines).is_some()) =>
            {
                // "V. 6. …" or a bold "6." opening the paragraph:
                // verse-by-verse exposition opens an entry per verse, the
                // way a quoted verse does.
                let n = verse_lead(&plain_text(inlines))
                    .or_else(|| bold_number_lead(inlines))
                    .expect("checked");
                close_entry!();
                verse_start = n;
                verse_end = n;
                open = true;
                blocks.push(relocate_notes(
                    block.clone(),
                    doc,
                    &mut notes,
                    &mut note_index,
                ));
            }
            other => {
                if !open {
                    open = true;
                }
                blocks.push(relocate_notes(
                    other.clone(),
                    doc,
                    &mut notes,
                    &mut note_index,
                ));
            }
        }
    }
    close_entry!();
    let _ = open;
    if entries.is_empty() {
        return Err(InterpretError::NoSections);
    }
    Ok(CommentaryDocument {
        book,
        entries,
        contents,
    })
}

/// An ordered list standing for verses: items of some length (a quoted
/// verse with its exposition), not a short enumeration.
fn verse_numbered_list(items: &[Vec<Block>]) -> bool {
    if items.is_empty() {
        return false;
    }
    // Items keeping their own numbers ("2. Und nun …") are verses the
    // way expositions number them; unnumbered items count only when
    // they are long expositions, so a quoted psalm stays a list.
    let numbered = items.iter().all(|item| {
        matches!(item.first(), Some(Block::Paragraph { inlines, .. }) if leading_number_dot(&plain_text(inlines)).is_some())
    });
    if numbered {
        return true;
    }
    let chars: usize = items
        .iter()
        .flat_map(|item| item.iter())
        .map(|b| match b {
            Block::Paragraph { inlines, .. } => plain_text(inlines).chars().count(),
            _ => 0,
        })
        .sum();
    chars / items.len() >= 200
}

/// "2. Und nun" → 2: a number with its dot opening the text.
fn leading_number_dot(text: &str) -> Option<u16> {
    let t = text.trim_start();
    let digits = t.chars().take_while(|c| c.is_ascii_digit()).count();
    if digits == 0 || digits > 3 || !t[digits..].starts_with('.') {
        return None;
    }
    t[..digits].parse().ok()
}

/// A paragraph opening with a bold verse number ("**1.** Wohl dem …"),
/// the way expositions number their verses; the number must be small
/// enough to be a verse and the bold run must be just the number.
fn bold_number_lead(inlines: &[Inline]) -> Option<u16> {
    let Some(Inline::Text { text, style }) = inlines.first() else {
        return None;
    };
    if !style.bold {
        return None;
    }
    let t = text.trim();
    let digits = t.chars().take_while(|c| c.is_ascii_digit()).count();
    if digits == 0 || digits > 3 {
        return None;
    }
    let rest = t[digits..].trim_end_matches('.').trim();
    if !rest.is_empty() {
        return None;
    }
    let n: u16 = t[..digits].parse().ok()?;
    (n > 0 && n <= 176).then_some(n)
}

/// "V. 6.", "V.6", "Vers 6" opening a paragraph: the verse it treats.
fn verse_lead(text: &str) -> Option<u16> {
    let t = text.trim_start();
    let rest = ["V. ", "V.", "Vers ", "Verse "]
        .iter()
        .find_map(|p| t.strip_prefix(p))?;
    let rest = rest.trim_start();
    let digits = rest.chars().take_while(|c| c.is_ascii_digit()).count();
    if digits == 0 || digits > 3 {
        return None;
    }
    let after = &rest[digits..];
    if after
        .chars()
        .next()
        .is_some_and(|c| c.is_alphanumeric() && c != 'a' && c != 'b')
    {
        return None;
    }
    rest[..digits].parse().ok()
}

fn leading_number(text: &str) -> Option<u16> {
    let t = text.trim_start();
    let digits = t.chars().take_while(|c| c.is_ascii_digit()).count();
    if digits == 0 || digits > 3 || !t[digits..].starts_with(' ') {
        return None;
    }
    t[..digits].parse().ok()
}

/// Copy a block, renumbering its note references into the entry's own
/// note list.
fn relocate_notes(
    block: Block,
    doc: &Document,
    notes: &mut Vec<Note>,
    index: &mut HashMap<usize, usize>,
) -> Block {
    fn inlines_of(
        inlines: Vec<Inline>,
        doc: &Document,
        notes: &mut Vec<Note>,
        index: &mut HashMap<usize, usize>,
    ) -> Vec<Inline> {
        inlines
            .into_iter()
            .map(|i| match i {
                Inline::NoteRef(global) => {
                    let local = *index.entry(global).or_insert_with(|| {
                        notes.push(doc.notes.get(global).cloned().unwrap_or_default());
                        notes.len() - 1
                    });
                    Inline::NoteRef(local)
                }
                other => other,
            })
            .collect()
    }
    match block {
        Block::Heading { level, inlines } => Block::Heading {
            level,
            inlines: inlines_of(inlines, doc, notes, index),
        },
        Block::Paragraph { style, inlines } => Block::Paragraph {
            style,
            inlines: inlines_of(inlines, doc, notes, index),
        },
        Block::List { ordered, items } => Block::List {
            ordered,
            items: items
                .into_iter()
                .map(|item| {
                    item.into_iter()
                        .map(|b| relocate_notes(b, doc, notes, index))
                        .collect()
                })
                .collect(),
        },
        Block::Table { header_rows, rows } => Block::Table {
            header_rows,
            rows: rows
                .into_iter()
                .map(|row| {
                    row.into_iter()
                        .map(|cell| inlines_of(cell, doc, notes, index))
                        .collect()
                })
                .collect(),
        },
        other => other,
    }
}

/// Mark scripture references in a block's text as `Inline::Reference`.
pub fn resolve_block(block: Block, ctx: ReferenceContext) -> Block {
    match block {
        Block::Heading { level, inlines } => Block::Heading {
            level,
            inlines: resolve_inlines(inlines, ctx),
        },
        Block::Paragraph { style, inlines } => Block::Paragraph {
            style,
            inlines: resolve_inlines(inlines, ctx),
        },
        Block::List { ordered, items } => Block::List {
            ordered,
            items: items
                .into_iter()
                .map(|item| item.into_iter().map(|b| resolve_block(b, ctx)).collect())
                .collect(),
        },
        Block::Table { header_rows, rows } => Block::Table {
            header_rows,
            rows: rows
                .into_iter()
                .map(|row| {
                    row.into_iter()
                        .map(|cell| resolve_inlines(cell, ctx))
                        .collect()
                })
                .collect(),
        },
        other => other,
    }
}

pub fn resolve_inlines(inlines: Vec<Inline>, ctx: ReferenceContext) -> Vec<Inline> {
    let mut out = Vec::with_capacity(inlines.len());
    for inline in inlines {
        match inline {
            Inline::Text { text, style } => {
                let found = scan_references_in(&text, ctx);
                if found.is_empty() {
                    out.push(Inline::Text { text, style });
                    continue;
                }
                let mut cursor = 0usize;
                for r in found {
                    let (start, end) = (r.start as usize, r.end as usize);
                    if start > cursor {
                        out.push(Inline::Text {
                            text: text[cursor..start].to_string(),
                            style,
                        });
                    }
                    out.push(Inline::Reference {
                        text: text[start..end].to_string(),
                        osis: osis_of(r.reference),
                    });
                    cursor = end;
                }
                if cursor < text.len() {
                    out.push(Inline::Text {
                        text: text[cursor..].to_string(),
                        style,
                    });
                }
            }
            other => out.push(other),
        }
    }
    out
}

/// OSIS id of a reference: "Rom.8", "Rom.8.23", "Rom.8.23-Rom.8.25".
pub fn osis_of(reference: Reference) -> String {
    match reference {
        Reference::Chapter { book, chapter } => format!("{}.{}", book.info().osis, chapter),
        Reference::Verse(v) => format!("{}.{}.{}", v.book.info().osis, v.chapter, v.verse),
        Reference::VerseRange { start, end_verse } => format!(
            "{}.{}.{}-{}.{}.{}",
            start.book.info().osis,
            start.chapter,
            start.verse,
            start.book.info().osis,
            start.chapter,
            end_verse
        ),
    }
}

/// Plain text of an entry (paragraphs joined by blank lines, notes
/// appended) with the byte ranges of its references.
fn entry_text(blocks: &[Block], notes: &[Note]) -> (String, Vec<CommentRef>) {
    let mut text = String::new();
    let mut refs = Vec::new();
    fn emit(inlines: &[Inline], text: &mut String, refs: &mut Vec<CommentRef>) {
        for inline in inlines {
            match inline {
                Inline::Text { text: t, .. } => text.push_str(t),
                Inline::Reference { text: t, osis } => {
                    let start = text.len() as u32;
                    text.push_str(t);
                    refs.push(CommentRef {
                        start,
                        end: text.len() as u32,
                        osis: osis.clone(),
                    });
                }
                Inline::LineBreak => text.push(' '),
                Inline::VerseNumber(n) => {
                    text.push_str(&n.to_string());
                    text.push(' ');
                }
                Inline::NoteRef(_) => {}
            }
        }
    }
    fn block_text(block: &Block, text: &mut String, refs: &mut Vec<CommentRef>) {
        match block {
            Block::Heading { inlines, .. } | Block::Paragraph { inlines, .. } => {
                if !text.is_empty() {
                    text.push_str("\n\n");
                }
                emit(inlines, text, refs);
            }
            Block::List { items, .. } => {
                for item in items {
                    for b in item {
                        block_text(b, text, refs);
                    }
                }
            }
            Block::Table { rows, .. } => {
                for row in rows {
                    if !text.is_empty() {
                        text.push_str("\n\n");
                    }
                    for (i, cell) in row.iter().enumerate() {
                        if i > 0 {
                            text.push_str(" · ");
                        }
                        emit(cell, text, refs);
                    }
                }
            }
            Block::Figure { caption, .. } if !caption.is_empty() => {
                if !text.is_empty() {
                    text.push_str("\n\n");
                }
                emit(caption, text, refs);
            }
            _ => {}
        }
    }
    for block in blocks {
        block_text(block, &mut text, &mut refs);
    }
    for (i, note) in notes.iter().enumerate() {
        if !text.is_empty() {
            text.push_str("\n\n");
        }
        text.push_str(&format!(
            "[{}] ",
            if note.label.is_empty() {
                (i + 1).to_string()
            } else {
                note.label.clone()
            }
        ));
        for b in &note.blocks {
            if let Block::Paragraph { inlines, .. } = b {
                emit(inlines, &mut text, &mut refs);
            }
        }
    }
    (text, refs)
}

/// A general book for the library: sections at every heading, nested by
/// level, each with plain text and its block tree.
pub struct BookDocument {
    pub sections: Vec<BookSection>,
    pub contents: Vec<EntryContent>,
}

pub fn to_book(doc: &Document) -> Result<BookDocument, InterpretError> {
    let mut sections: Vec<BookSection> = Vec::new();
    let mut contents: Vec<EntryContent> = Vec::new();
    let mut current: Option<(u8, String)> = None;
    let mut blocks: Vec<Block> = Vec::new();
    let mut notes: Vec<Note> = Vec::new();
    let mut note_index: HashMap<usize, usize> = HashMap::new();
    let ctx = ReferenceContext::default();
    let close = |current: &mut Option<(u8, String)>,
                 blocks: &mut Vec<Block>,
                 notes: &mut Vec<Note>,
                 sections: &mut Vec<BookSection>,
                 contents: &mut Vec<EntryContent>| {
        let (level, name) = current.take().unwrap_or((1, String::new()));
        if blocks.is_empty() && name.is_empty() {
            return;
        }
        let resolved: Vec<Block> = blocks.drain(..).map(|b| resolve_block(b, ctx)).collect();
        let (text, _) = entry_text(&resolved, notes);
        let ordinal = sections.len() as u32 + 1;
        sections.push(BookSection {
            ordinal,
            level,
            name: if name.is_empty() {
                doc.title.clone()
            } else {
                name.clone()
            },
            heading: (!name.is_empty()).then_some(name),
            text,
        });
        contents.push(EntryContent {
            blocks: resolved,
            notes: std::mem::take(notes),
        });
    };
    for block in &doc.blocks {
        match block {
            Block::Heading { level, inlines } => {
                close(
                    &mut current,
                    &mut blocks,
                    &mut notes,
                    &mut sections,
                    &mut contents,
                );
                note_index.clear();
                current = Some((*level, plain_text(inlines)));
            }
            Block::Milestone { .. } => {}
            other => blocks.push(relocate_notes(
                other.clone(),
                doc,
                &mut notes,
                &mut note_index,
            )),
        }
    }
    close(
        &mut current,
        &mut blocks,
        &mut notes,
        &mut sections,
        &mut contents,
    );
    if sections.is_empty() {
        return Err(InterpretError::NoSections);
    }
    Ok(BookDocument { sections, contents })
}

#[derive(Debug, thiserror::Error)]
pub enum InterpretError {
    #[error("no chapters recognized: the text has no book or chapter headings")]
    NoChapters,
    #[error("no verses recognized")]
    NoVerses,
    #[error("no subject book: the title and headings name no book of the Bible")]
    NoSubject,
    #[error("no sections recognized")]
    NoSections,
}

/// Convenience for tests and tools: a verse reference as OSIS.
pub fn verse_osis(v: VerseRef) -> String {
    format!("{}.{}.{}", v.book.info().osis, v.chapter, v.verse)
}
