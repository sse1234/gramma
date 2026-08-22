//! Import an OSIS file into a library database and print a short summary.
//!
//! Usage: cargo run --example import_osis -- <library.db> <file.osis.xml>

use std::io::BufReader;
use std::path::Path;

use gramma_core::library::Library;
use gramma_core::reference::{Reference, book_by_osis};

fn main() {
    let mut args = std::env::args().skip(1);
    let (Some(db), Some(file)) = (args.next(), args.next()) else {
        eprintln!("usage: import_osis <library.db> <file.osis.xml>");
        std::process::exit(2);
    };
    let mut library = Library::open(Path::new(&db)).expect("open library");
    let source = BufReader::new(std::fs::File::open(&file).expect("open OSIS file"));
    let start = std::time::Instant::now();
    let summary = library.import_osis(source).expect("import");
    println!(
        "imported {} ({}, lang {}): {} verses in {:.2?}",
        summary.code,
        summary.title,
        summary.language,
        summary.verses,
        start.elapsed()
    );
    let john = book_by_osis("John").unwrap();
    for verse in library.chapter(&summary.code, john, 3).expect("query") {
        if verse.verse == 16 {
            let reference: Reference = "Joh 3,16".parse().unwrap();
            println!("{reference}  {}", verse.text);
        }
    }
}
