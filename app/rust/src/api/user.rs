use std::path::Path;
use std::sync::Mutex;

use anyhow::anyhow;
use gramma_core::user::UserStore;

static USER: Mutex<Option<UserStore>> = Mutex::new(None);

fn with_store<T>(f: impl FnOnce(&UserStore) -> anyhow::Result<T>) -> anyhow::Result<T> {
    let guard = USER.lock().unwrap();
    let store = guard
        .as_ref()
        .ok_or_else(|| anyhow!("user store not opened"))?;
    f(store)
}

#[flutter_rust_bridge::frb(sync)]
pub fn open_user_store(path: String) -> anyhow::Result<()> {
    let store = UserStore::open(Path::new(&path))?;
    *USER.lock().unwrap() = Some(store);
    Ok(())
}

/// Persist one synced user value (desks, layout objects, later notes);
/// the write is stamped and appended to the sync op-log (ADR 0014).
#[flutter_rust_bridge::frb(sync)]
pub fn user_set(key: String, value: String) -> anyhow::Result<()> {
    with_store(|store| Ok(store.set_synced(&key, &value)?))
}

#[flutter_rust_bridge::frb(sync)]
pub fn user_get(key: String) -> anyhow::Result<Option<String>> {
    with_store(|store| Ok(store.get(&key)?))
}

/// Point the store at a synced folder (None disables sync). Fails when
/// the folder cannot be written.
#[flutter_rust_bridge::frb(sync)]
pub fn configure_sync(dir: Option<String>) -> anyhow::Result<()> {
    with_store(|store| Ok(store.configure_sync(dir.as_deref())?))
}

#[flutter_rust_bridge::frb(sync)]
pub fn sync_dir() -> anyhow::Result<Option<String>> {
    with_store(|store| Ok(store.sync_dir()?))
}

/// This installation's stable device id — the name of its own op-log.
#[flutter_rust_bridge::frb(sync)]
pub fn device_id() -> anyhow::Result<String> {
    with_store(|store| Ok(store.device_id()?))
}

/// Pull changes other installations wrote into the sync folder; returns
/// the changed keys so the UI can react.
#[flutter_rust_bridge::frb(sync)]
pub fn sync_now() -> anyhow::Result<Vec<String>> {
    with_store(|store| Ok(store.sync_now()?))
}
