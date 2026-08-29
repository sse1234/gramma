use gramma_core::user::UserStore;

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
