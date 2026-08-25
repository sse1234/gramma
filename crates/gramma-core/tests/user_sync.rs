//! Sync engine behavior (ADR 0014): two installations converging through
//! a plain folder, with nothing but per-device append-only op-logs.

use std::fs;
use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};

use gramma_core::user::UserStore;

/// A unique temp folder per test standing in for the user's synced
/// folder (iCloud Drive, Dropbox, Syncthing — all just directories).
fn sync_folder(name: &str) -> PathBuf {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let dir = std::env::temp_dir().join(format!("gramma-sync-{name}-{nanos}"));
    fs::create_dir_all(&dir).unwrap();
    dir
}

fn store_with_sync(dir: &std::path::Path) -> UserStore {
    let store = UserStore::open_in_memory().unwrap();
    store.configure_sync(Some(dir.to_str().unwrap())).unwrap();
    store
}

#[test]
fn a_change_flows_to_the_other_device() {
    let folder = sync_folder("flow");
    let a = store_with_sync(&folder);
    let b = store_with_sync(&folder);

    a.set_synced("desk/1", "two panes side by side").unwrap();
    let changed = b.sync_now().unwrap();
    assert_eq!(changed, vec!["desk/1".to_string()]);
    assert_eq!(
        b.get("desk/1").unwrap().as_deref(),
        Some("two panes side by side")
    );
    assert_eq!(b.sync_now().unwrap(), Vec::<String>::new(), "idempotent");
}

#[test]
fn concurrent_writes_converge_to_one_winner() {
    let folder = sync_folder("lww");
    let a = store_with_sync(&folder);
    let b = store_with_sync(&folder);

    a.set_synced("desk/1", "from a").unwrap();
    std::thread::sleep(std::time::Duration::from_millis(5));
    b.set_synced("desk/1", "from b").unwrap();

    a.sync_now().unwrap();
    b.sync_now().unwrap();
    assert_eq!(a.get("desk/1").unwrap(), b.get("desk/1").unwrap());
    assert_eq!(
        a.get("desk/1").unwrap().as_deref(),
        Some("from b"),
        "the later write wins on both devices"
    );
}

#[test]
fn the_devices_own_echo_never_reports_as_change() {
    let folder = sync_folder("echo");
    let a = store_with_sync(&folder);
    a.set_synced("desks", "registry").unwrap();
    assert_eq!(
        a.sync_now().unwrap(),
        Vec::<String>::new(),
        "a device's own ops read back are not changes"
    );
}

#[test]
fn writes_before_sync_was_configured_self_heal_into_the_log() {
    let folder = sync_folder("heal");
    let a = UserStore::open_in_memory().unwrap();
    // Saved while no folder was configured (or the drive was away):
    a.set_synced("desk/1", "written offline").unwrap();
    a.configure_sync(Some(folder.to_str().unwrap())).unwrap();
    a.sync_now().unwrap();

    let b = store_with_sync(&folder);
    b.sync_now().unwrap();
    assert_eq!(b.get("desk/1").unwrap().as_deref(), Some("written offline"));
}

#[test]
fn compaction_bounds_the_log_and_preserves_state() {
    let folder = sync_folder("compact");
    let a = store_with_sync(&folder);
    for i in 0..250 {
        a.set_synced("desk/1", &format!("arrangement {i}")).unwrap();
    }
    a.set_synced("desks", "registry").unwrap();
    a.sync_now().unwrap(); // triggers compaction past the threshold

    let device = a.device_id().unwrap();
    let log = folder
        .join("gramma-sync")
        .join("oplog")
        .join(format!("{device}.jsonl"));
    let lines = fs::read_to_string(log).unwrap().lines().count();
    assert!(lines <= 2, "one line per key after compaction, was {lines}");

    let b = store_with_sync(&folder);
    b.sync_now().unwrap();
    assert_eq!(b.get("desk/1").unwrap().as_deref(), Some("arrangement 249"));
    assert_eq!(b.get("desks").unwrap().as_deref(), Some("registry"));
}

#[test]
fn malformed_foreign_lines_are_ignored() {
    let folder = sync_folder("garbage");
    let a = store_with_sync(&folder);
    a.set_synced("desk/1", "good value").unwrap();

    let foreign = folder.join("gramma-sync").join("oplog").join("cafe.jsonl");
    fs::write(
        &foreign,
        "not json at all\n{\"half\": true\n{\"k\":\"desk/2\",\"v\":\"valid\",\"t\":[1,0],\"d\":\"cafe\"}\n",
    )
    .unwrap();

    let b = store_with_sync(&folder);
    let mut changed = b.sync_now().unwrap();
    changed.sort();
    assert_eq!(changed, vec!["desk/1".to_string(), "desk/2".to_string()]);
    assert_eq!(b.get("desk/2").unwrap().as_deref(), Some("valid"));
}

#[test]
fn device_id_is_stable_across_reopen() {
    let dir = sync_folder("device-id");
    let path = dir.join("user.db");
    let first = UserStore::open(&path).unwrap().device_id().unwrap();
    let second = UserStore::open(&path).unwrap().device_id().unwrap();
    assert_eq!(first, second);
    assert_eq!(first.len(), 16);
}

#[test]
fn unsynced_stores_sync_nothing() {
    let a = UserStore::open_in_memory().unwrap();
    a.set("private", "stays here").unwrap();
    assert_eq!(a.sync_now().unwrap(), Vec::<String>::new());
    assert_eq!(a.sync_dir().unwrap(), None);
}
