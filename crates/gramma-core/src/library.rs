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
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ModuleInfo {
    pub code: String,
    pub title: String,
    pub language: String,
    pub verses: u32,
    pub notes: u32,
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
    pub text: String,
}

/// One chapter in a module's table of contents.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ChapterRef {
    pub book: BookId,
    pub chapter: u16,
    /// Total text length in bytes, for layout-size estimation.
    pub text_length: i64,
}

const SCHEMA: &str = "
CREATE TABLE IF NOT EXISTS module(
  id INTEGER PRIMARY KEY,
  code TEXT NOT NULL UNIQUE,
  title TEXT NOT NULL,
  language TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS verse(
  module_id INTEGER NOT NULL REFERENCES module(id) ON DELETE CASCADE,
  book INTEGER NOT NULL,
  chapter INTEGER NOT NULL,
  verse INTEGER NOT NULL,
  text TEXT NOT NULL,
  PRIMARY KEY(module_id, book, chapter, verse)
) WITHOUT ROWID;
CREATE TABLE IF NOT EXISTS note(
  module_id INTEGER NOT NULL REFERENCES module(id) ON DELETE CASCADE,
  book INTEGER NOT NULL,
  chapter INTEGER NOT NULL,
  verse INTEGER NOT NULL,
  seq INTEGER NOT NULL,
  text TEXT NOT NULL,
  PRIMARY KEY(module_id, book, chapter, verse, seq)
) WITHOUT ROWID;
";

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
                "INSERT OR REPLACE INTO note(module_id, book, chapter, verse, seq, text)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
            )?;
            for n in &doc.notes {
                insert.execute((
                    module_id,
                    n.book.index() as i64,
                    n.chapter,
                    n.verse,
                    n.seq,
                    &n.text,
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
        })
    }

    pub fn modules(&self) -> Result<Vec<ModuleInfo>, LibraryError> {
        let mut stmt = self.conn.prepare(
            "SELECT code, title, language,
                    (SELECT COUNT(*) FROM verse v WHERE v.module_id = m.id),
                    (SELECT COUNT(*) FROM note n WHERE n.module_id = m.id)
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

    /// Footnotes of one chapter, ordered by verse and sequence.
    pub fn notes(
        &self,
        module_code: &str,
        book: BookId,
        chapter: u16,
    ) -> Result<Vec<Note>, LibraryError> {
        let module_id = self.module_id(module_code)?;
        let mut stmt = self.conn.prepare(
            "SELECT verse, seq, text FROM note
             WHERE module_id = ?1 AND book = ?2 AND chapter = ?3
             ORDER BY verse, seq",
        )?;
        let notes = stmt
            .query_map((module_id, book.index() as i64, chapter), |row| {
                Ok(Note {
                    verse: row.get(0)?,
                    seq: row.get(1)?,
                    text: row.get(2)?,
                })
            })?
            .collect::<Result<Vec<_>, _>>()?;
        Ok(notes)
    }

    /// The ordered chapter spine of a module: every chapter that has content,
    /// in canonical order. This is the backbone of the endless-scrolling
    /// reader.
    pub fn contents(&self, module_code: &str) -> Result<Vec<ChapterRef>, LibraryError> {
        let module_id = self.module_id(module_code)?;
        let mut stmt = self.conn.prepare(
            "SELECT book, chapter, SUM(LENGTH(text)) FROM verse
             WHERE module_id = ?1 GROUP BY book, chapter ORDER BY book, chapter",
        )?;
        let contents = stmt
            .query_map([module_id], |row| {
                Ok((
                    row.get::<_, i64>(0)?,
                    row.get::<_, u16>(1)?,
                    row.get::<_, i64>(2)?,
                ))
            })?
            .filter_map(|row| {
                row.map(|(book, chapter, text_length)| {
                    BookId::from_index(book as usize).map(|book| ChapterRef {
                        book,
                        chapter,
                        text_length,
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
}
