//! The user store: personal data, kept strictly separate from the content
//! library (ADR 0003). A key/value store holding desks and their layout
//! objects (ADR 0008, 0014); notes and highlights grow here. Values
//! written through [`UserStore::set_synced`] flow to other installations
//! through the folder op-log of ADR 0014.

use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use rusqlite::{Connection, OptionalExtension};

use crate::sync::{self, Op, Stamp};

#[derive(Debug, thiserror::Error)]
pub enum UserStoreError {
    #[error("database error: {0}")]
    Db(#[from] rusqlite::Error),
    #[error("sync folder error: {0}")]
    Sync(#[from] std::io::Error),
}

const SCHEMA: &str = "
CREATE TABLE IF NOT EXISTS kv(
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
) WITHOUT ROWID;
CREATE TABLE IF NOT EXISTS meta(
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
) WITHOUT ROWID;
CREATE TABLE IF NOT EXISTS sync_state(
  key TEXT PRIMARY KEY,
  millis INTEGER NOT NULL,
  counter INTEGER NOT NULL,
  device TEXT NOT NULL
) WITHOUT ROWID;
";

/// Own-log line count beyond which [`UserStore::sync_now`] compacts.
const COMPACT_THRESHOLD: usize = 200;

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

    fn meta_get(&self, key: &str) -> Result<Option<String>, UserStoreError> {
        Ok(self
            .conn
            .query_row("SELECT value FROM meta WHERE key = ?1", [key], |row| {
                row.get(0)
            })
            .optional()?)
    }

    fn meta_set(&self, key: &str, value: &str) -> Result<(), UserStoreError> {
        self.conn.execute(
            "INSERT INTO meta(key, value) VALUES (?1, ?2)
             ON CONFLICT(key) DO UPDATE SET value = excluded.value",
            (key, value),
        )?;
        Ok(())
    }

    /// This installation's stable random id; generated on first use.
    pub fn device_id(&self) -> Result<String, UserStoreError> {
        if let Some(id) = self.meta_get("device")? {
            return Ok(id);
        }
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_nanos();
        let mixed = nanos ^ ((std::process::id() as u128) << 64);
        let id = format!("{:016x}", (mixed as u64) ^ ((mixed >> 64) as u64));
        self.meta_set("device", &id)?;
        Ok(id)
    }

    /// The configured sync folder, if any.
    pub fn sync_dir(&self) -> Result<Option<String>, UserStoreError> {
        self.meta_get("sync_dir")
    }

    /// Points the store at a synced folder (None disables). Validates by
    /// creating the op-log structure with a first probe of the own log.
    pub fn configure_sync(&self, dir: Option<&str>) -> Result<(), UserStoreError> {
        match dir {
            None => {
                self.conn
                    .execute("DELETE FROM meta WHERE key = 'sync_dir'", [])?;
                Ok(())
            }
            Some(dir) => {
                let device = self.device_id()?;
                std::fs::create_dir_all(Path::new(dir).join("gramma-sync").join("oplog"))?;
                // Touch the own log so the folder is proven writable.
                let probe = Path::new(dir)
                    .join("gramma-sync")
                    .join("oplog")
                    .join(format!("{device}.jsonl"));
                std::fs::OpenOptions::new()
                    .create(true)
                    .append(true)
                    .open(probe)?;
                self.meta_set("sync_dir", dir)
            }
        }
    }

    fn hlc_tick(&self) -> Result<(i64, u32), UserStoreError> {
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_millis() as i64;
        let last_millis: i64 = self
            .meta_get("hlc_millis")?
            .and_then(|v| v.parse().ok())
            .unwrap_or(0);
        let last_counter: u32 = self
            .meta_get("hlc_counter")?
            .and_then(|v| v.parse().ok())
            .unwrap_or(0);
        let (millis, counter) = if now > last_millis {
            (now, 0)
        } else {
            (last_millis, last_counter + 1)
        };
        self.meta_set("hlc_millis", &millis.to_string())?;
        self.meta_set("hlc_counter", &counter.to_string())?;
        Ok((millis, counter))
    }

    /// HLC receive rule: the local clock never falls behind a seen stamp.
    fn hlc_receive(&self, millis: i64, counter: u32) -> Result<(), UserStoreError> {
        let last_millis: i64 = self
            .meta_get("hlc_millis")?
            .and_then(|v| v.parse().ok())
            .unwrap_or(0);
        let last_counter: u32 = self
            .meta_get("hlc_counter")?
            .and_then(|v| v.parse().ok())
            .unwrap_or(0);
        if (millis, counter) > (last_millis, last_counter) {
            self.meta_set("hlc_millis", &millis.to_string())?;
            self.meta_set("hlc_counter", &counter.to_string())?;
        }
        Ok(())
    }

    fn stamp_of(&self, key: &str) -> Result<Option<Stamp>, UserStoreError> {
        Ok(self
            .conn
            .query_row(
                "SELECT millis, counter, device FROM sync_state WHERE key = ?1",
                [key],
                |row| {
                    Ok(Stamp {
                        millis: row.get(0)?,
                        counter: row.get(1)?,
                        device: row.get(2)?,
                    })
                },
            )
            .optional()?)
    }

    fn record_stamp(&self, key: &str, stamp: &Stamp) -> Result<(), UserStoreError> {
        self.conn.execute(
            "INSERT INTO sync_state(key, millis, counter, device)
             VALUES (?1, ?2, ?3, ?4)
             ON CONFLICT(key) DO UPDATE SET millis = excluded.millis,
               counter = excluded.counter, device = excluded.device",
            (key, stamp.millis, stamp.counter, &stamp.device),
        )?;
        Ok(())
    }

    /// Sets a value that participates in sync: stored locally, stamped,
    /// and appended to the own op-log. A folder that is unreachable right
    /// now does not fail the write — [`UserStore::sync_now`] self-heals.
    pub fn set_synced(&self, key: &str, value: &str) -> Result<(), UserStoreError> {
        self.set(key, value)?;
        let (millis, counter) = self.hlc_tick()?;
        let stamp = Stamp {
            millis,
            counter,
            device: self.device_id()?,
        };
        self.record_stamp(key, &stamp)?;
        if let Some(dir) = self.sync_dir()? {
            let op = Op {
                key: key.to_string(),
                value: value.to_string(),
                stamp,
            };
            let _ = sync::append_op(Path::new(&dir), &op);
        }
        Ok(())
    }

    /// Pulls foreign changes from the sync folder: applies every op newer
    /// than the locally applied stamp, self-heals the own log, compacts
    /// it past the threshold, and returns the changed keys.
    pub fn sync_now(&self) -> Result<Vec<String>, UserStoreError> {
        let Some(dir) = self.sync_dir()? else {
            return Ok(Vec::new());
        };
        let root = PathBuf::from(dir);
        let device = self.device_id()?;

        // Self-heal: every self-stamped key whose stamp is missing from
        // the own log (offline save, crash) is re-appended.
        let own = sync::merged(sync::read_device_ops(&root, &device));
        let mut rows = self
            .conn
            .prepare("SELECT key, millis, counter FROM sync_state WHERE device = ?1")?;
        let self_keys: Vec<(String, i64, u32)> = rows
            .query_map([&device], |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)))?
            .collect::<Result<_, _>>()?;
        for (key, millis, counter) in self_keys {
            let logged = own.get(&key).map(|op| (op.stamp.millis, op.stamp.counter));
            if logged.is_none_or(|l| l < (millis, counter))
                && let Some(value) = self.get(&key)?
            {
                let _ = sync::append_op(
                    &root,
                    &Op {
                        key,
                        value,
                        stamp: Stamp {
                            millis,
                            counter,
                            device: device.clone(),
                        },
                    },
                );
            }
        }

        // Pull: apply foreign ops newer than what was already applied.
        let mut changed = Vec::new();
        let mut max_seen: Option<Stamp> = None;
        let mut state: Vec<Op> = sync::merged(sync::read_all_ops(&root))
            .into_values()
            .collect();
        state.sort_by(|a, b| a.key.cmp(&b.key));
        for op in state {
            if max_seen.as_ref().is_none_or(|m| op.stamp > *m) {
                max_seen = Some(op.stamp.clone());
            }
            let newer = match self.stamp_of(&op.key)? {
                Some(local) => op.stamp > local,
                None => true,
            };
            if newer {
                self.set(&op.key, &op.value)?;
                self.record_stamp(&op.key, &op.stamp)?;
                changed.push(op.key);
            }
        }
        if let Some(stamp) = max_seen {
            self.hlc_receive(stamp.millis, stamp.counter)?;
        }

        if sync::own_log_lines(&root, &device) > COMPACT_THRESHOLD {
            let _ = sync::compact(&root, &device);
        }
        Ok(changed)
    }
}
