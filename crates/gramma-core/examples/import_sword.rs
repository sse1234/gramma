//! Import a SWORD package (a CrossWire zip) into a library database
//! from the command line — the same dispatch the app uses.
//!
//! Usage: cargo run --example import_sword -- <library.db> <Module.zip>

use std::path::Path;

use gramma_core::library::Library;
use gramma_core::sword::{SwordModule, read_sword_zip};

fn main() {
    let mut args = std::env::args().skip(1);
    let (Some(db), Some(file)) = (args.next(), args.next()) else {
        eprintln!("usage: import_sword <library.db> <Module.zip>");
        std::process::exit(2);
    };
    let mut library = Library::open(Path::new(&db)).expect("open library");
    let module = read_sword_zip(Path::new(&file)).expect("read package");
    let info = match module {
        SwordModule::Commentary(doc) => library.import_commentary(&doc),
        SwordModule::Dictionary(doc) => library.import_dictionary(&doc),
        SwordModule::Bible(doc) => library.import_bible(&doc),
        SwordModule::Book(doc) => library.import_book(&doc),
    }
    .expect("import");
    println!("{}: {} {} units", info.code, info.kind, info.verses);
}
