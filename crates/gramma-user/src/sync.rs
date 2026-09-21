//! Op-log sync primitives (ADR 0014): eventual sync of the user store
//! between the user's own installations through any synced folder.
//!
//! Each device appends only to its own `oplog/<device>.jsonl`; no file
//! ever has two writers, so provider-level conflicts cannot occur. State
//! is the last-writer-wins fold of all logs, ordered by hybrid logical
//! clock and device id — deterministic on every device.

use std::collections::HashMap;
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

/// Hybrid-logical-clock stamp plus writing device; totally ordered.
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord)]
pub struct Stamp {
    pub millis: i64,
    pub counter: u32,
    pub device: String,
}

/// One operation: a key set to a value at a stamp.
#[derive(Debug, Clone)]
pub struct Op {
    pub key: String,
    pub value: String,
    pub stamp: Stamp,
}

/// The wire format of one log line.
#[derive(Serialize, Deserialize)]
struct Line {
    k: String,
    v: String,
    t: (i64, u32),
    d: String,
}

impl Op {
    fn to_line(&self) -> Line {
        Line {
            k: self.key.clone(),
            v: self.value.clone(),
            t: (self.stamp.millis, self.stamp.counter),
            d: self.stamp.device.clone(),
        }
    }

    fn from_line(line: Line) -> Op {
        Op {
            key: line.k,
            value: line.v,
            stamp: Stamp {
                millis: line.t.0,
                counter: line.t.1,
                device: line.d,
            },
        }
    }
}

fn oplog_dir(root: &Path) -> PathBuf {
    root.join("gramma-sync").join("oplog")
}

fn log_path(root: &Path, device: &str) -> PathBuf {
    oplog_dir(root).join(format!("{device}.jsonl"))
}

/// Appends one op to the device's own log, creating directories as
/// needed.
pub fn append_op(root: &Path, op: &Op) -> std::io::Result<()> {
    let dir = oplog_dir(root);
    fs::create_dir_all(&dir)?;
    let mut file = fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(log_path(root, &op.stamp.device))?;
    let mut line = serde_json::to_string(&op.to_line())?;
    line.push('\n');
    file.write_all(line.as_bytes())
}

/// All ops of one device's log; malformed lines are skipped, a missing
/// file is empty.
pub fn read_device_ops(root: &Path, device: &str) -> Vec<Op> {
    read_file_ops(&log_path(root, device))
}

fn read_file_ops(path: &Path) -> Vec<Op> {
    let Ok(content) = fs::read_to_string(path) else {
        return Vec::new();
    };
    content
        .lines()
        .filter_map(|l| serde_json::from_str::<Line>(l).ok())
        .map(Op::from_line)
        .collect()
}

/// All ops from every log in the folder; unreadable files and malformed
/// lines are skipped — a foreign device's problems must never be fatal
/// here.
pub fn read_all_ops(root: &Path) -> Vec<Op> {
    let Ok(entries) = fs::read_dir(oplog_dir(root)) else {
        return Vec::new();
    };
    let mut ops = Vec::new();
    for entry in entries.flatten() {
        let path = entry.path();
        if path.extension().is_some_and(|e| e == "jsonl") {
            ops.extend(read_file_ops(&path));
        }
    }
    ops
}

/// Last-writer-wins fold: for each key, the op with the greatest stamp.
pub fn merged(ops: impl IntoIterator<Item = Op>) -> HashMap<String, Op> {
    let mut state: HashMap<String, Op> = HashMap::new();
    for op in ops {
        match state.get(&op.key) {
            Some(existing) if existing.stamp >= op.stamp => {}
            _ => {
                state.insert(op.key.clone(), op);
            }
        }
    }
    state
}

/// Rewrites the device's own log keeping only the latest op per key.
/// Only one's own file may ever be compacted (one writer per file).
pub fn compact(root: &Path, device: &str) -> std::io::Result<()> {
    let ops = read_device_ops(root, device);
    let mut latest = merged(ops).into_values().collect::<Vec<_>>();
    latest.sort_by(|a, b| a.stamp.cmp(&b.stamp));
    let mut content = String::new();
    for op in &latest {
        content.push_str(&serde_json::to_string(&op.to_line())?);
        content.push('\n');
    }
    // The tmp name carries no .jsonl extension, so readers never see it.
    let tmp = oplog_dir(root).join(format!("{device}.tmp"));
    fs::write(&tmp, content)?;
    fs::rename(tmp, log_path(root, device))
}

/// Lines currently in the device's own log (compaction trigger).
pub fn own_log_lines(root: &Path, device: &str) -> usize {
    fs::read_to_string(log_path(root, device))
        .map(|c| c.lines().count())
        .unwrap_or(0)
}
