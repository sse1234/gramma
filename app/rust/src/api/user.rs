use std::path::Path;
use std::sync::Mutex;

use anyhow::anyhow;
use gramma_core::user::UserStore;

static USER: Mutex<Option<UserStore>> = Mutex::new(None);

const LAYOUT_KEY: &str = "layout";

#[flutter_rust_bridge::frb(sync)]
pub fn open_user_store(path: String) -> anyhow::Result<()> {
    let store = UserStore::open(Path::new(&path))?;
    *USER.lock().unwrap() = Some(store);
    Ok(())
}

/// Persist the layout object (ADR 0008): the serialized description of the
/// current view arrangement.
#[flutter_rust_bridge::frb(sync)]
pub fn save_layout(json: String) -> anyhow::Result<()> {
    let guard = USER.lock().unwrap();
    let store = guard
        .as_ref()
        .ok_or_else(|| anyhow!("user store not opened"))?;
    store.set(LAYOUT_KEY, &json)?;
    Ok(())
}

#[flutter_rust_bridge::frb(sync)]
pub fn load_layout() -> anyhow::Result<Option<String>> {
    let guard = USER.lock().unwrap();
    let store = guard
        .as_ref()
        .ok_or_else(|| anyhow!("user store not opened"))?;
    Ok(store.get(LAYOUT_KEY)?)
}
