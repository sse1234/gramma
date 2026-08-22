//! gramma-core: the headless domain core of gramma.
//!
//! All logic in this crate is UI-independent and deterministic; the Flutter
//! shell consumes it through a narrow bridge layer.

pub mod library;
pub mod osis;
pub mod reference;
pub mod typeset;
