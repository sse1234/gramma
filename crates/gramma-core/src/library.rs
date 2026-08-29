//! The library database: imported modules and their verse-addressed content,
//! stored offline-first in SQLite (see ADR 0003).

use std::path::Path;

use rusqlite::{Connection, OptionalExtension};

use crate::osis::{self, OsisError};
use crate::reference::BookId;

#[derive(Debug, thiserror::Error)]
pub enum LibraryError {
    #[error("database error: {0}")]
    Db(#[from] rusqlite::Error),
    #[error("OSIS import failed: {0}")]
    Osis(#[from] OsisError),
    #[error("unknown module: {0}")]
    UnknownModule(String),
    #[error("not a reading plan: {0}")]
    Plan(String),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ModuleInfo {
    pub code: String,
    pub title: String,
    pub language: String,
    /// Content units: verses of a Bible text, entries of a commentary.
    pub verses: u32,
    pub notes: u32,
    /// "bible" or "commentary".
    pub kind: String,
    /// Whether the module carries Strong's word links (ADR 0020).
    pub strongs: bool,
}

/// One commentary section (ADR 0017), covering verses
/// `verse_start..=verse_end` of one chapter.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Comment {
    pub verse_start: u16,
    pub verse_end: u16,
    pub heading: Option<String>,
    /// Paragraphs separated by "\n\n".
    pub text: String,
    pub refs: Vec<crate::sword::CommentRef>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Verse {
    pub verse: u16,
    pub text: String,
}

/// A footnote of a verse; `seq` numbers notes within one verse from 1.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Note {
    pub verse: u16,
    pub seq: u16,
    /// Byte offset into the verse's normalized text where the note anchors.
    pub offset: u32,
    pub text: String,
}

/// A section heading standing before a verse.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Heading {
    pub verse: u16,
    pub seq: u16,
    pub level: u8,
    pub text: String,
}

/// One chapter in a module's table of contents.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ChapterRef {
    pub book: BookId,
    pub chapter: u16,
    /// Total text length in bytes, for layout-size estimation.
    pub text_length: i64,
    /// Highest verse number in the chapter.
    pub max_verse: u16,
}

const SCHEMA: &str = "
CREATE TABLE IF NOT EXISTS module(
  id INTEGER PRIMARY KEY,
  code TEXT NOT NULL UNIQUE,
  title TEXT NOT NULL,
  language TEXT NOT NULL,
  kind TEXT NOT NULL DEFAULT 'bible'
);
CREATE TABLE IF NOT EXISTS verse(
  module_id INTEGER NOT NULL REFERENCES module(id) ON DELETE CASCADE,
  book INTEGER NOT NULL,
  chapter INTEGER NOT NULL,
  verse INTEGER NOT NULL,
  text TEXT NOT NULL,
  PRIMARY KEY(module_id, book, chapter, verse)
) WITHOUT ROWID;
CREATE TABLE IF NOT EXISTS heading(
  module_id INTEGER NOT NULL REFERENCES module(id) ON DELETE CASCADE,
  book INTEGER NOT NULL,
  chapter INTEGER NOT NULL,
  verse INTEGER NOT NULL,
  seq INTEGER NOT NULL,
  level INTEGER NOT NULL,
  text TEXT NOT NULL,
  PRIMARY KEY(module_id, book, chapter, verse, seq)
) WITHOUT ROWID;
CREATE TABLE IF NOT EXISTS note(
  module_id INTEGER NOT NULL REFERENCES module(id) ON DELETE CASCADE,
  book INTEGER NOT NULL,
  chapter INTEGER NOT NULL,
  verse INTEGER NOT NULL,
  seq INTEGER NOT NULL,
  offset INTEGER NOT NULL DEFAULT 0,
  text TEXT NOT NULL,
  PRIMARY KEY(module_id, book, chapter, verse, seq)
) WITHOUT ROWID;
CREATE TABLE IF NOT EXISTS comment(
  module_id INTEGER NOT NULL REFERENCES module(id) ON DELETE CASCADE,
  book INTEGER NOT NULL,
  chapter INTEGER NOT NULL,
  verse_start INTEGER NOT NULL,
  verse_end INTEGER NOT NULL,
  heading TEXT,
  text TEXT NOT NULL,
  PRIMARY KEY(module_id, book, chapter, verse_start)
) WITHOUT ROWID;
CREATE TABLE IF NOT EXISTS dict_entry(
  module_id INTEGER NOT NULL REFERENCES module(id) ON DELETE CASCADE,
  sort INTEGER NOT NULL,
  key TEXT NOT NULL,
  headword TEXT NOT NULL,
  pron TEXT NOT NULL,
  text TEXT NOT NULL,
  PRIMARY KEY(module_id, sort)
) WITHOUT ROWID;
CREATE TABLE IF NOT EXISTS word_link(
  module_id INTEGER NOT NULL REFERENCES module(id) ON DELETE CASCADE,
  book INTEGER NOT NULL,
  chapter INTEGER NOT NULL,
  verse INTEGER NOT NULL,
  seq INTEGER NOT NULL,
  start INTEGER NOT NULL,
  ref_end INTEGER NOT NULL,
  strong TEXT NOT NULL,
  PRIMARY KEY(module_id, book, chapter, verse, seq)
) WITHOUT ROWID;
CREATE INDEX IF NOT EXISTS word_link_strong
  ON word_link(module_id, strong);
CREATE TABLE IF NOT EXISTS book_section(
  module_id INTEGER NOT NULL REFERENCES module(id) ON DELETE CASCADE,
  ordinal INTEGER NOT NULL,
  level INTEGER NOT NULL,
  name TEXT NOT NULL,
  heading TEXT,
  text TEXT NOT NULL,
  PRIMARY KEY(module_id, ordinal)
) WITHOUT ROWID;
CREATE TABLE IF NOT EXISTS plan(
  name TEXT PRIMARY KEY,
  source TEXT NOT NULL,
  json TEXT NOT NULL
) WITHOUT ROWID;
CREATE TABLE IF NOT EXISTS comment_ref(
  module_id INTEGER NOT NULL REFERENCES module(id) ON DELETE CASCADE,
  book INTEGER NOT NULL,
  chapter INTEGER NOT NULL,
  verse_start INTEGER NOT NULL,
  seq INTEGER NOT NULL,
  ref_start INTEGER NOT NULL,
  ref_end INTEGER NOT NULL,
  osis TEXT NOT NULL,
  PRIMARY KEY(module_id, book, chapter, verse_start, seq)
) WITHOUT ROWID;
";

/// One dictionary entry (ADR 0019).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DictEntryRow {
    pub sort: u32,
    pub key: String,
    pub headword: String,
    pub pron: String,
    /// Paragraphs separated by "\n\n".
    pub text: String,
}

/// One concordance hit (ADR 0020): a Strong's occurrence with its
/// verse text and the covered byte range.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Occurrence {
    pub book: BookId,
    pub chapter: u16,
    pub verse: u16,
    pub start: u32,
    pub end: u32,
    pub text: String,
}

/// One table-of-contents row of a general book (ADR 0021).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BookTocRow {
    pub ordinal: u32,
    pub level: u8,
    pub name: String,
}

/// One section of a general book.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BookSectionRow {
    pub ordinal: u32,
    pub level: u8,
    pub name: String,
    pub heading: Option<String>,
    /// Paragraphs separated by "\n\n".
    pub text: String,
}

/// A dictionary search hit: enough to render a result row.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DictHit {
    pub sort: u32,
    pub key: String,
    pub headword: String,
    pub pron: String,
}

pub struct Library {
    conn: Connection,
}

impl Library {
    pub fn open(path: &Path) -> Result<Self, LibraryError> {
        Self::init(Connection::open(path)?)
    }

    pub fn open_in_memory() -> Result<Self, LibraryError> {
        Self::init(Connection::open_in_memory()?)
    }

    fn init(conn: Connection) -> Result<Self, LibraryError> {
        conn.pragma_update(None, "foreign_keys", true)?;
        conn.execute_batch(SCHEMA)?;
        // Migration: earlier note tables lack the offset column, earlier
        // module tables the kind column.
        let _ = conn.execute(
            "ALTER TABLE note ADD COLUMN offset INTEGER NOT NULL DEFAULT 0",
            [],
        );
        let _ = conn.execute(
            "ALTER TABLE module ADD COLUMN kind TEXT NOT NULL DEFAULT 'bible'",
            [],
        );
        Ok(Library { conn })
    }

    /// Import an OSIS document, replacing any existing module with the same
    /// work code.
    pub fn import_osis(
        &mut self,
        source: impl std::io::BufRead,
    ) -> Result<ModuleInfo, LibraryError> {
        let doc = osis::parse(source)?;
        let tx = self.conn.transaction()?;
        tx.execute("DELETE FROM module WHERE code = ?1", [&doc.code])?;
        tx.execute(
            "INSERT INTO module(code, title, language) VALUES (?1, ?2, ?3)",
            (&doc.code, &doc.title, &doc.language),
        )?;
        let module_id = tx.last_insert_rowid();
        {
            // Subverse parts sharing one id (e.g. `Gen.1.1!a` + `!b`) merge
            // into a single verse row.
            let mut insert = tx.prepare(
                "INSERT INTO verse(module_id, book, chapter, verse, text)
                 VALUES (?1, ?2, ?3, ?4, ?5)
                 ON CONFLICT(module_id, book, chapter, verse)
                 DO UPDATE SET text = text || ' ' || excluded.text",
            )?;
            for v in &doc.verses {
                insert.execute((
                    module_id,
                    v.book.index() as i64,
                    v.chapter,
                    v.verse,
                    &v.text,
                ))?;
            }
        }
        {
            let mut insert = tx.prepare(
                "INSERT OR REPLACE INTO note(module_id, book, chapter, verse, seq, offset, text)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
            )?;
            for n in &doc.notes {
                insert.execute((
                    module_id,
                    n.book.index() as i64,
                    n.chapter,
                    n.verse,
                    n.seq,
                    n.offset,
                    &n.text,
                ))?;
            }
        }
        {
            let mut insert = tx.prepare(
                "INSERT OR REPLACE INTO heading(module_id, book, chapter, verse, seq, level, text)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
            )?;
            for h in &doc.headings {
                insert.execute((
                    module_id,
                    h.book.index() as i64,
                    h.chapter,
                    h.verse,
                    h.seq,
                    h.level,
                    &h.text,
                ))?;
            }
        }
        tx.commit()?;
        let verses = self.verse_count(module_id)?;
        Ok(ModuleInfo {
            code: doc.code,
            title: doc.title,
            language: doc.language,
            verses,
            notes: doc.notes.len() as u32,
            kind: "bible".to_string(),
            strongs: false,
        })
    }

    /// Import a SWORD commentary (ADR 0017), replacing any existing module
    /// with the same code.
    pub fn import_commentary(
        &mut self,
        doc: &crate::sword::SwordCommentary,
    ) -> Result<ModuleInfo, LibraryError> {
        let tx = self.conn.transaction()?;
        tx.execute("DELETE FROM module WHERE code = ?1", [&doc.code])?;
        tx.execute(
            "INSERT INTO module(code, title, language, kind)
             VALUES (?1, ?2, ?3, 'commentary')",
            (&doc.code, &doc.title, &doc.language),
        )?;
        let module_id = tx.last_insert_rowid();
        {
            let mut insert = tx.prepare(
                "INSERT OR REPLACE INTO comment
                   (module_id, book, chapter, verse_start, verse_end, heading, text)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
            )?;
            let mut insert_ref = tx.prepare(
                "INSERT OR REPLACE INTO comment_ref
                   (module_id, book, chapter, verse_start, seq, ref_start, ref_end, osis)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
            )?;
            for e in &doc.entries {
                insert.execute((
                    module_id,
                    e.book.index() as i64,
                    e.chapter,
                    e.verse_start,
                    e.verse_end,
                    &e.heading,
                    &e.text,
                ))?;
                for (seq, r) in e.refs.iter().enumerate() {
                    insert_ref.execute((
                        module_id,
                        e.book.index() as i64,
                        e.chapter,
                        e.verse_start,
                        seq as i64 + 1,
                        r.start,
                        r.end,
                        &r.osis,
                    ))?;
                }
            }
        }
        tx.commit()?;
        let entries: u32 = self.conn.query_row(
            "SELECT COUNT(*) FROM comment WHERE module_id = ?1",
            [module_id],
            |row| row.get(0),
        )?;
        Ok(ModuleInfo {
            code: doc.code.clone(),
            title: doc.title.clone(),
            language: doc.language.clone(),
            verses: entries,
            notes: 0,
            kind: "commentary".to_string(),
            strongs: false,
        })
    }

    /// Import a SWORD Bible text (zText, ADR 0020) with its word-level
    /// Strong's links, replacing any module with the same code.
    pub fn import_bible(
        &mut self,
        doc: &crate::sword::SwordBible,
    ) -> Result<ModuleInfo, LibraryError> {
        let tx = self.conn.transaction()?;
        tx.execute("DELETE FROM module WHERE code = ?1", [&doc.code])?;
        tx.execute(
            "INSERT INTO module(code, title, language, kind)
             VALUES (?1, ?2, ?3, 'bible')",
            (&doc.code, &doc.title, &doc.language),
        )?;
        let module_id = tx.last_insert_rowid();
        {
            let mut insert_verse = tx.prepare(
                "INSERT OR REPLACE INTO verse(module_id, book, chapter, verse, text)
                 VALUES (?1, ?2, ?3, ?4, ?5)",
            )?;
            let mut insert_link = tx.prepare(
                "INSERT OR REPLACE INTO word_link
                   (module_id, book, chapter, verse, seq, start, ref_end, strong)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
            )?;
            for v in &doc.verses {
                insert_verse.execute((
                    module_id,
                    v.book.index() as i64,
                    v.chapter,
                    v.verse,
                    &v.text,
                ))?;
                for (seq, link) in v.links.iter().enumerate() {
                    insert_link.execute((
                        module_id,
                        v.book.index() as i64,
                        v.chapter,
                        v.verse,
                        seq as i64 + 1,
                        link.start,
                        link.end,
                        &link.strong,
                    ))?;
                }
            }
            let mut insert_note = tx.prepare(
                "INSERT OR REPLACE INTO note(module_id, book, chapter, verse, seq, offset, text)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
            )?;
            for n in &doc.notes {
                insert_note.execute((
                    module_id,
                    n.book.index() as i64,
                    n.chapter,
                    n.verse,
                    n.seq,
                    n.offset,
                    &n.text,
                ))?;
            }
        }
        tx.commit()?;
        let verses = self.verse_count(module_id)?;
        Ok(ModuleInfo {
            code: doc.code.clone(),
            title: doc.title.clone(),
            language: doc.language.clone(),
            verses,
            notes: doc.notes.len() as u32,
            kind: "bible".to_string(),
            strongs: doc.verses.iter().any(|v| !v.links.is_empty()),
        })
    }

    /// Every occurrence of a Strong number in a module, in canon order —
    /// the concordance (ADR 0020).
    pub fn concordance(
        &self,
        module_code: &str,
        strong: &str,
        limit: usize,
    ) -> Result<Vec<Occurrence>, LibraryError> {
        let module_id = self.module_id(module_code)?;
        let mut stmt = self.conn.prepare(
            "SELECT w.book, w.chapter, w.verse, w.start, w.ref_end, v.text
             FROM word_link w
             JOIN verse v ON v.module_id = w.module_id AND v.book = w.book
               AND v.chapter = w.chapter AND v.verse = w.verse
             WHERE w.module_id = ?1 AND w.strong = ?2
             ORDER BY w.book, w.chapter, w.verse, w.seq
             LIMIT ?3",
        )?;
        let hits = stmt
            .query_map((module_id, strong, limit as i64), |row| {
                Ok((
                    row.get::<_, i64>(0)?,
                    row.get::<_, u16>(1)?,
                    row.get::<_, u16>(2)?,
                    row.get::<_, u32>(3)?,
                    row.get::<_, u32>(4)?,
                    row.get::<_, String>(5)?,
                ))
            })?
            .filter_map(|row| {
                row.map(|(book, chapter, verse, start, end, text)| {
                    BookId::from_index(book as usize).map(|book| Occurrence {
                        book,
                        chapter,
                        verse,
                        start,
                        end,
                        text,
                    })
                })
                .transpose()
            })
            .collect::<Result<Vec<_>, _>>()?;
        Ok(hits)
    }

    /// The Strong number(s) of a word in a verse: links whose covered
    /// text contains the word (Unicode case-insensitive, whole-word).
    pub fn strongs_for_word(
        &self,
        module_code: &str,
        book: BookId,
        chapter: u16,
        verse: u16,
        word: &str,
    ) -> Result<Vec<String>, LibraryError> {
        let module_id = self.module_id(module_code)?;
        let text: Option<String> = self
            .conn
            .query_row(
                "SELECT text FROM verse
                 WHERE module_id = ?1 AND book = ?2 AND chapter = ?3 AND verse = ?4",
                (module_id, book.index() as i64, chapter, verse),
                |row| row.get(0),
            )
            .optional()?;
        let Some(text) = text else {
            return Ok(Vec::new());
        };
        let needle = word.to_lowercase();
        let mut stmt = self.conn.prepare(
            "SELECT start, ref_end, strong FROM word_link
             WHERE module_id = ?1 AND book = ?2 AND chapter = ?3 AND verse = ?4
             ORDER BY seq",
        )?;
        let mut out = Vec::new();
        let rows = stmt.query_map((module_id, book.index() as i64, chapter, verse), |row| {
            Ok((
                row.get::<_, u32>(0)?,
                row.get::<_, u32>(1)?,
                row.get::<_, String>(2)?,
            ))
        })?;
        for row in rows {
            let (start, end, strong) = row?;
            let Some(slice) = text.get(start as usize..end as usize) else {
                continue;
            };
            let matches = slice
                .split(|c: char| !c.is_alphanumeric())
                .any(|w| !w.is_empty() && w.to_lowercase() == needle);
            if matches && !out.contains(&strong) {
                out.push(strong);
            }
        }
        Ok(out)
    }

    /// The first module carrying Strong's word links, if any — the
    /// concordance source.
    pub fn strongs_module(&self) -> Result<Option<String>, LibraryError> {
        Ok(self
            .conn
            .query_row(
                "SELECT m.code FROM module m
                 WHERE EXISTS (SELECT 1 FROM word_link w WHERE w.module_id = m.id)
                 ORDER BY m.code LIMIT 1",
                [],
                |row| row.get(0),
            )
            .optional()?)
    }

    /// Import a SWORD dictionary (ADR 0019), replacing any module with
    /// the same code.
    pub fn import_dictionary(
        &mut self,
        doc: &crate::sword::SwordDictionary,
    ) -> Result<ModuleInfo, LibraryError> {
        let kind = if doc.devotional {
            "devotional"
        } else {
            "dictionary"
        };
        let tx = self.conn.transaction()?;
        tx.execute("DELETE FROM module WHERE code = ?1", [&doc.code])?;
        tx.execute(
            "INSERT INTO module(code, title, language, kind)
             VALUES (?1, ?2, ?3, ?4)",
            (&doc.code, &doc.title, &doc.language, kind),
        )?;
        let module_id = tx.last_insert_rowid();
        {
            let mut insert = tx.prepare(
                "INSERT OR REPLACE INTO dict_entry
                   (module_id, sort, key, headword, pron, text)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
            )?;
            for e in &doc.entries {
                insert.execute((module_id, e.sort, &e.key, &e.headword, &e.pron, &e.text))?;
            }
        }
        tx.commit()?;
        let entries: u32 = self.conn.query_row(
            "SELECT COUNT(*) FROM dict_entry WHERE module_id = ?1",
            [module_id],
            |row| row.get(0),
        )?;
        Ok(ModuleInfo {
            code: doc.code.clone(),
            title: doc.title.clone(),
            language: doc.language.clone(),
            verses: entries,
            notes: 0,
            kind: kind.to_string(),
            strongs: false,
        })
    }

    /// Import a general book (RawGenBook, ADR 0021), replacing any
    /// module with the same code.
    pub fn import_book(
        &mut self,
        doc: &crate::sword::SwordBook,
    ) -> Result<ModuleInfo, LibraryError> {
        let tx = self.conn.transaction()?;
        tx.execute("DELETE FROM module WHERE code = ?1", [&doc.code])?;
        tx.execute(
            "INSERT INTO module(code, title, language, kind)
             VALUES (?1, ?2, ?3, 'book')",
            (&doc.code, &doc.title, &doc.language),
        )?;
        let module_id = tx.last_insert_rowid();
        {
            let mut insert = tx.prepare(
                "INSERT OR REPLACE INTO book_section
                   (module_id, ordinal, level, name, heading, text)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
            )?;
            for section in &doc.sections {
                insert.execute((
                    module_id,
                    section.ordinal,
                    section.level,
                    &section.name,
                    &section.heading,
                    &section.text,
                ))?;
            }
        }
        tx.commit()?;
        let sections: u32 = self.conn.query_row(
            "SELECT COUNT(*) FROM book_section WHERE module_id = ?1",
            [module_id],
            |row| row.get(0),
        )?;
        Ok(ModuleInfo {
            code: doc.code.clone(),
            title: doc.title.clone(),
            language: doc.language.clone(),
            verses: sections,
            notes: 0,
            kind: "book".to_string(),
            strongs: false,
        })
    }

    /// The table of contents of a general book, in reading order.
    pub fn book_toc(&self, module_code: &str) -> Result<Vec<BookTocRow>, LibraryError> {
        let module_id = self.module_id(module_code)?;
        let mut stmt = self.conn.prepare(
            "SELECT ordinal, level, name FROM book_section
             WHERE module_id = ?1 ORDER BY ordinal",
        )?;
        let rows = stmt
            .query_map([module_id], |row| {
                Ok(BookTocRow {
                    ordinal: row.get(0)?,
                    level: row.get(1)?,
                    name: row.get(2)?,
                })
            })?
            .collect::<Result<Vec<_>, _>>()?;
        Ok(rows)
    }

    /// One book section with its reading-order neighbors.
    #[allow(clippy::type_complexity)]
    pub fn book_section(
        &self,
        module_code: &str,
        ordinal: u32,
    ) -> Result<Option<(BookSectionRow, Option<u32>, Option<u32>)>, LibraryError> {
        let module_id = self.module_id(module_code)?;
        let section = self
            .conn
            .query_row(
                "SELECT ordinal, level, name, heading, text FROM book_section
                 WHERE module_id = ?1 AND ordinal = ?2",
                (module_id, ordinal),
                |row| {
                    Ok(BookSectionRow {
                        ordinal: row.get(0)?,
                        level: row.get(1)?,
                        name: row.get(2)?,
                        heading: row.get(3)?,
                        text: row.get(4)?,
                    })
                },
            )
            .optional()?;
        let Some(section) = section else {
            return Ok(None);
        };
        let prev: Option<u32> = self.conn.query_row(
            "SELECT MAX(ordinal) FROM book_section
             WHERE module_id = ?1 AND ordinal < ?2",
            (module_id, ordinal),
            |row| row.get(0),
        )?;
        let next: Option<u32> = self.conn.query_row(
            "SELECT MIN(ordinal) FROM book_section
             WHERE module_id = ?1 AND ordinal > ?2",
            (module_id, ordinal),
            |row| row.get(0),
        )?;
        Ok(Some((section, prev, next)))
    }

    /// Dictionary entries whose sort lies in [lo, hi] — a devotional
    /// day's readings (ADR 0021).
    pub fn dict_entries_between(
        &self,
        module_code: &str,
        lo: u32,
        hi: u32,
    ) -> Result<Vec<DictEntryRow>, LibraryError> {
        let module_id = self.module_id(module_code)?;
        let mut stmt = self.conn.prepare(
            "SELECT sort, key, headword, pron, text FROM dict_entry
             WHERE module_id = ?1 AND sort BETWEEN ?2 AND ?3 ORDER BY sort",
        )?;
        let rows = stmt
            .query_map((module_id, lo, hi), |row| {
                Ok(DictEntryRow {
                    sort: row.get(0)?,
                    key: row.get(1)?,
                    headword: row.get(2)?,
                    pron: row.get(3)?,
                    text: row.get(4)?,
                })
            })?
            .collect::<Result<Vec<_>, _>>()?;
        Ok(rows)
    }

    /// One dictionary entry by sort key, with its neighbors for
    /// prev/next browsing.
    #[allow(clippy::type_complexity)]
    pub fn dictionary_entry(
        &self,
        module_code: &str,
        sort: u32,
    ) -> Result<Option<(DictEntryRow, Option<u32>, Option<u32>)>, LibraryError> {
        let module_id = self.module_id(module_code)?;
        let entry = self
            .conn
            .query_row(
                "SELECT sort, key, headword, pron, text FROM dict_entry
                 WHERE module_id = ?1 AND sort = ?2",
                (module_id, sort),
                |row| {
                    Ok(DictEntryRow {
                        sort: row.get(0)?,
                        key: row.get(1)?,
                        headword: row.get(2)?,
                        pron: row.get(3)?,
                        text: row.get(4)?,
                    })
                },
            )
            .optional()?;
        let Some(entry) = entry else {
            return Ok(None);
        };
        let prev: Option<u32> = self.conn.query_row(
            "SELECT MAX(sort) FROM dict_entry WHERE module_id = ?1 AND sort < ?2",
            (module_id, sort),
            |row| row.get(0),
        )?;
        let next: Option<u32> = self.conn.query_row(
            "SELECT MIN(sort) FROM dict_entry WHERE module_id = ?1 AND sort > ?2",
            (module_id, sort),
            |row| row.get(0),
        )?;
        Ok(Some((entry, prev, next)))
    }

    /// Search a dictionary: headword, transliteration, and key hits rank
    /// before body-text hits. Bodies match by canonical search tokens
    /// (the bibelsuche tokenizer, ADR 0022) — "Zeltes" finds "Zelt",
    /// but "Einzelteile" does not — ordered by match density so the
    /// entry actually about the word beats one mentioning it in
    /// passing (the GerSch "Zelt"→G40 lesson).
    pub fn dictionary_search(
        &self,
        module_code: &str,
        query: &str,
        limit: usize,
    ) -> Result<Vec<DictHit>, LibraryError> {
        let module_id = self.module_id(module_code)?;
        let needle = query.to_lowercase();
        if needle.is_empty() {
            return Ok(Vec::new());
        }
        let query_tokens = crate::search::tokenize(query);
        let mut stmt = self.conn.prepare(
            "SELECT sort, key, headword, pron, text FROM dict_entry
             WHERE module_id = ?1 ORDER BY sort",
        )?;
        // (rank, negative match density, sort) orders the results.
        let mut ranked: Vec<(u8, i64, DictHit)> = Vec::new();
        let rows = stmt.query_map([module_id], |row| {
            Ok((
                DictHit {
                    sort: row.get(0)?,
                    key: row.get(1)?,
                    headword: row.get(2)?,
                    pron: row.get(3)?,
                },
                row.get::<_, String>(4)?,
            ))
        })?;
        for row in rows {
            let (hit, text) = row?;
            if hit.headword.to_lowercase().contains(&needle)
                || hit.pron.to_lowercase().contains(&needle)
                || hit.key.trim_start_matches('0') == needle.trim_start_matches('0')
            {
                ranked.push((0, 0, hit));
                continue;
            }
            if query_tokens.is_empty() {
                continue;
            }
            let body_tokens = crate::search::tokenize(&text);
            let matches = body_tokens
                .iter()
                .filter(|t| query_tokens.contains(t))
                .count();
            let all_present = query_tokens
                .iter()
                .all(|q| body_tokens.iter().any(|t| t == q));
            if all_present && matches > 0 {
                ranked.push((1, -(matches as i64), hit));
            }
        }
        ranked.sort_by_key(|(rank, density, hit)| (*rank, *density, hit.sort));
        Ok(ranked
            .into_iter()
            .map(|(_, _, hit)| hit)
            .take(limit)
            .collect())
    }

    /// Commentary entries of one chapter, ordered by starting verse.
    pub fn comments(
        &self,
        module_code: &str,
        book: BookId,
        chapter: u16,
    ) -> Result<Vec<Comment>, LibraryError> {
        let module_id = self.module_id(module_code)?;
        let mut stmt = self.conn.prepare(
            "SELECT verse_start, verse_end, heading, text FROM comment
             WHERE module_id = ?1 AND book = ?2 AND chapter = ?3
             ORDER BY verse_start",
        )?;
        let mut comments = stmt
            .query_map((module_id, book.index() as i64, chapter), |row| {
                Ok(Comment {
                    verse_start: row.get(0)?,
                    verse_end: row.get(1)?,
                    heading: row.get(2)?,
                    text: row.get(3)?,
                    refs: Vec::new(),
                })
            })?
            .collect::<Result<Vec<_>, _>>()?;
        let mut refs = self.conn.prepare(
            "SELECT ref_start, ref_end, osis FROM comment_ref
             WHERE module_id = ?1 AND book = ?2 AND chapter = ?3
               AND verse_start = ?4
             ORDER BY seq",
        )?;
        for comment in &mut comments {
            comment.refs = refs
                .query_map(
                    (module_id, book.index() as i64, chapter, comment.verse_start),
                    |row| {
                        Ok(crate::sword::CommentRef {
                            start: row.get(0)?,
                            end: row.get(1)?,
                            osis: row.get(2)?,
                        })
                    },
                )?
                .collect::<Result<Vec<_>, _>>()?;
        }
        Ok(comments)
    }

    pub fn modules(&self) -> Result<Vec<ModuleInfo>, LibraryError> {
        let mut stmt = self.conn.prepare(
            "SELECT code, title, language,
                    (SELECT COUNT(*) FROM verse v WHERE v.module_id = m.id)
                    + (SELECT COUNT(*) FROM comment c WHERE c.module_id = m.id)
                    + (SELECT COUNT(*) FROM dict_entry d WHERE d.module_id = m.id)
                    + (SELECT COUNT(*) FROM book_section b WHERE b.module_id = m.id),
                    (SELECT COUNT(*) FROM note n WHERE n.module_id = m.id),
                    kind,
                    EXISTS (SELECT 1 FROM word_link w WHERE w.module_id = m.id)
             FROM module m ORDER BY code",
        )?;
        let modules = stmt
            .query_map([], |row| {
                Ok(ModuleInfo {
                    code: row.get(0)?,
                    title: row.get(1)?,
                    language: row.get(2)?,
                    verses: row.get(3)?,
                    notes: row.get(4)?,
                    kind: row.get(5)?,
                    strongs: row.get(6)?,
                })
            })?
            .collect::<Result<Vec<_>, _>>()?;
        Ok(modules)
    }

    pub fn chapter(
        &self,
        module_code: &str,
        book: BookId,
        chapter: u16,
    ) -> Result<Vec<Verse>, LibraryError> {
        let module_id = self.module_id(module_code)?;
        let mut stmt = self.conn.prepare(
            "SELECT verse, text FROM verse
             WHERE module_id = ?1 AND book = ?2 AND chapter = ?3
             ORDER BY verse",
        )?;
        let verses = stmt
            .query_map((module_id, book.index() as i64, chapter), |row| {
                Ok(Verse {
                    verse: row.get(0)?,
                    text: row.get(1)?,
                })
            })?
            .collect::<Result<Vec<_>, _>>()?;
        Ok(verses)
    }

    /// Section headings of one chapter, ordered by verse and sequence.
    pub fn headings(
        &self,
        module_code: &str,
        book: BookId,
        chapter: u16,
    ) -> Result<Vec<Heading>, LibraryError> {
        let module_id = self.module_id(module_code)?;
        let mut stmt = self.conn.prepare(
            "SELECT verse, seq, level, text FROM heading
             WHERE module_id = ?1 AND book = ?2 AND chapter = ?3
             ORDER BY verse, seq",
        )?;
        let headings = stmt
            .query_map((module_id, book.index() as i64, chapter), |row| {
                Ok(Heading {
                    verse: row.get(0)?,
                    seq: row.get(1)?,
                    level: row.get(2)?,
                    text: row.get(3)?,
                })
            })?
            .collect::<Result<Vec<_>, _>>()?;
        Ok(headings)
    }

    /// Footnotes of one chapter, ordered by verse and sequence.
    pub fn notes(
        &self,
        module_code: &str,
        book: BookId,
        chapter: u16,
    ) -> Result<Vec<Note>, LibraryError> {
        let module_id = self.module_id(module_code)?;
        let mut stmt = self.conn.prepare(
            "SELECT verse, seq, offset, text FROM note
             WHERE module_id = ?1 AND book = ?2 AND chapter = ?3
             ORDER BY verse, seq",
        )?;
        let notes = stmt
            .query_map((module_id, book.index() as i64, chapter), |row| {
                Ok(Note {
                    verse: row.get(0)?,
                    seq: row.get(1)?,
                    offset: row.get(2)?,
                    text: row.get(3)?,
                })
            })?
            .collect::<Result<Vec<_>, _>>()?;
        Ok(notes)
    }

    /// Every verse of a module in canon order, for search indexing
    /// (ADR 0022).
    pub fn all_verses(
        &self,
        module_code: &str,
    ) -> Result<Vec<(BookId, u16, u16, String)>, LibraryError> {
        let module_id = self.module_id(module_code)?;
        let mut stmt = self.conn.prepare(
            "SELECT book, chapter, verse, text FROM verse
             WHERE module_id = ?1 ORDER BY book, chapter, verse",
        )?;
        let rows = stmt
            .query_map([module_id], |row| {
                Ok((
                    row.get::<_, i64>(0)?,
                    row.get::<_, u16>(1)?,
                    row.get::<_, u16>(2)?,
                    row.get::<_, String>(3)?,
                ))
            })?
            .filter_map(|row| {
                row.map(|(book, chapter, verse, text)| {
                    BookId::from_index(book as usize).map(|b| (b, chapter, verse, text))
                })
                .transpose()
            })
            .collect::<Result<Vec<_>, _>>()?;
        Ok(rows)
    }

    /// The ordered chapter spine of a module: every chapter that has content,
    /// in canonical order. This is the backbone of the endless-scrolling
    /// reader.
    pub fn contents(&self, module_code: &str) -> Result<Vec<ChapterRef>, LibraryError> {
        let module_id = self.module_id(module_code)?;
        let mut stmt = self.conn.prepare(
            "SELECT book, chapter, SUM(LENGTH(text)), MAX(verse) FROM verse
             WHERE module_id = ?1 GROUP BY book, chapter ORDER BY book, chapter",
        )?;
        let contents = stmt
            .query_map([module_id], |row| {
                Ok((
                    row.get::<_, i64>(0)?,
                    row.get::<_, u16>(1)?,
                    row.get::<_, i64>(2)?,
                    row.get::<_, u16>(3)?,
                ))
            })?
            .filter_map(|row| {
                row.map(|(book, chapter, text_length, max_verse)| {
                    BookId::from_index(book as usize).map(|book| ChapterRef {
                        book,
                        chapter,
                        text_length,
                        max_verse,
                    })
                })
                .transpose()
            })
            .collect::<Result<Vec<_>, _>>()?;
        Ok(contents)
    }

    fn module_id(&self, code: &str) -> Result<i64, LibraryError> {
        self.conn
            .query_row("SELECT id FROM module WHERE code = ?1", [code], |row| {
                row.get(0)
            })
            .optional()?
            .ok_or_else(|| LibraryError::UnknownModule(code.to_string()))
    }

    fn verse_count(&self, module_id: i64) -> Result<u32, LibraryError> {
        Ok(self.conn.query_row(
            "SELECT COUNT(*) FROM verse WHERE module_id = ?1",
            [module_id],
            |row| row.get(0),
        )?)
    }

    /// Import a reading plan from its JSON (the `assets/plans` schema):
    /// validated here, stored verbatim, keyed by name — a re-import
    /// replaces the plan.
    pub fn import_plan(&mut self, json: &str) -> Result<PlanInfo, LibraryError> {
        let bad = |what: &str| LibraryError::Plan(what.to_string());
        let value: serde_json::Value =
            serde_json::from_str(json).map_err(|e| bad(&format!("invalid JSON: {e}")))?;
        let name = value
            .get("name")
            .and_then(|v| v.as_str())
            .filter(|s| !s.is_empty())
            .ok_or_else(|| bad("missing plan name"))?;
        let source = value.get("source").and_then(|v| v.as_str()).unwrap_or("");
        let days = value
            .get("days")
            .and_then(|v| v.as_array())
            .filter(|d| !d.is_empty())
            .ok_or_else(|| bad("missing days"))?;
        for day in days {
            let refs = day.as_array().ok_or_else(|| bad("day is not a list"))?;
            for r in refs {
                for field in ["label", "osis"] {
                    r.get(field)
                        .and_then(|v| v.as_str())
                        .ok_or_else(|| bad(&format!("reading without {field}")))?;
                }
            }
        }
        self.conn.execute(
            "INSERT OR REPLACE INTO plan(name, source, json) VALUES (?1, ?2, ?3)",
            rusqlite::params![name, source, json],
        )?;
        Ok(PlanInfo {
            name: name.to_string(),
            source: source.to_string(),
            days: days.len() as u32,
        })
    }

    /// All imported reading plans, ordered by name.
    pub fn plans(&self) -> Result<Vec<PlanRecord>, LibraryError> {
        let mut stmt = self
            .conn
            .prepare("SELECT name, source, json FROM plan ORDER BY name")?;
        let rows = stmt.query_map([], |row| {
            Ok(PlanRecord {
                name: row.get(0)?,
                source: row.get(1)?,
                json: row.get(2)?,
            })
        })?;
        Ok(rows.collect::<Result<_, _>>()?)
    }
}

/// The outcome of a plan import, for the confirmation message.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PlanInfo {
    pub name: String,
    pub source: String,
    pub days: u32,
}

/// One stored reading plan; the app decodes `json` itself.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PlanRecord {
    pub name: String,
    pub source: String,
    pub json: String,
}
