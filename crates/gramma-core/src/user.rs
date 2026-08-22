//! The user store: personal data, kept strictly separate from the content
//! library (ADR 0003). Starts as a key/value store holding the layout
//! object (ADR 0008); notes, highlights, and the sync op-log (ADR 0004)
//! grow here.

use std::path::Path;

use rusqlite::{Connection, OptionalExtension};

#[derive(Debug, thiserror::Error)]
pub enum UserStoreError {
    #[error("database error: {0}")]
    Db(#[from] rusqlite::Error),
}

const SCHEMA: &str = "
CREATE TABLE IF NOT EXISTS kv(
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
) WITHOUT ROWID;
";

pub struct UserStore {
    conn: Connection,
}

impl UserStore {
    pub fn open(path: &Path) -> Result<Self, UserStoreError> {
        Self::init(Connection::open(path)?)
    }

    pub fn open_in_memory() -> Result<Self, UserStoreError> {
        Self::init(Connection::open_in_memory()?)
    }

    fn init(conn: Connection) -> Result<Self, UserStoreError> {
        conn.execute_batch(SCHEMA)?;
        Ok(UserStore { conn })
    }

    pub fn set(&self, key: &str, value: &str) -> Result<(), UserStoreError> {
        self.conn.execute(
            "INSERT INTO kv(key, value) VALUES (?1, ?2)
             ON CONFLICT(key) DO UPDATE SET value = excluded.value",
            (key, value),
        )?;
        Ok(())
    }

    pub fn get(&self, key: &str) -> Result<Option<String>, UserStoreError> {
        Ok(self
            .conn
            .query_row("SELECT value FROM kv WHERE key = ?1", [key], |row| {
                row.get(0)
            })
            .optional()?)
    }
}
