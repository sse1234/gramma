//! gramma-core: the headless domain core of gramma, one facade over the
//! layered crates (ADR 0030). The layers, bottom up: references, module
//! readers (OSIS, SWORD), the document model, typesetting, the library;
//! the user store stands beside them. A crate may depend only on layers
//! beneath it — Cargo enforces the direction.
//!
//! All logic is UI-independent and deterministic; the Flutter shell
//! consumes it through a narrow bridge layer.

pub use gramma_document as document;
pub use gramma_library as library;
pub use gramma_library::search;
pub use gramma_osis::osis;
pub use gramma_osis::sword;
pub use gramma_reference as reference;
pub use gramma_typeset as typeset;
pub use gramma_user as user;
pub use gramma_user::sync;
