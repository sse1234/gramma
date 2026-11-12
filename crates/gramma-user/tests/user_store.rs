use gramma_user::UserStore;

#[test]
fn values_roundtrip_and_overwrite() {
    let store = UserStore::open_in_memory().unwrap();
    assert_eq!(store.get("layout").unwrap(), None);
    store.set("layout", "{\"v\":1}").unwrap();
    assert_eq!(store.get("layout").unwrap().as_deref(), Some("{\"v\":1}"));
    store.set("layout", "{\"v\":2}").unwrap();
    assert_eq!(store.get("layout").unwrap().as_deref(), Some("{\"v\":2}"));
}

#[test]
fn keys_are_independent() {
    let store = UserStore::open_in_memory().unwrap();
    store.set("a", "1").unwrap();
    store.set("b", "2").unwrap();
    assert_eq!(store.get("a").unwrap().as_deref(), Some("1"));
    assert_eq!(store.get("b").unwrap().as_deref(), Some("2"));
}

#[test]
fn store_persists_across_reopen() {
    let dir = std::env::temp_dir().join(format!("gramma-user-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let db = dir.join("user.db");
    {
        let store = UserStore::open(&db).unwrap();
        store.set("layout", "persisted").unwrap();
    }
    let store = UserStore::open(&db).unwrap();
    assert_eq!(store.get("layout").unwrap().as_deref(), Some("persisted"));
    // Windows refuses to delete an open database — close it first.
    drop(store);
    std::fs::remove_dir_all(&dir).unwrap();
}

/// ADR 0037: the store runs in write-ahead mode with NORMAL
/// synchronization, and what was committed is there for the next open
/// even when the process never closed the database — the app killed in
/// the background, with the log not yet folded into the main file.
#[test]
fn committed_writes_survive_an_unclosed_store() {
    let dir = std::env::temp_dir().join(format!("gramma-user-wal-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let db = dir.join("user.db");
    let store = UserStore::open(&db).unwrap();
    assert_eq!(store.durability().unwrap(), ("wal".to_string(), 1));
    store.set_synced("desk/1", "position").unwrap();
    store.set("plain", "value").unwrap();
    // Never closed: no checkpoint runs.
    std::mem::forget(store);
    let reopened = UserStore::open(&db).unwrap();
    assert_eq!(reopened.get("desk/1").unwrap().as_deref(), Some("position"));
    assert_eq!(reopened.get("plain").unwrap().as_deref(), Some("value"));
    drop(reopened);
    // The forgotten handle keeps the files open on Windows.
    let _ = std::fs::remove_dir_all(&dir);
}
