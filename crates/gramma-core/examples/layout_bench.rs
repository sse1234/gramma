//! Lay out every chapter of a module and report timing.
//!
//! Usage: cargo run --release --example layout_bench -- <library.db> <module>

use std::path::Path;

use gramma_core::library::Library;
use gramma_core::typeset::layout::layout_verses;
use gramma_core::typeset::shape::FontMeasure;
use hyphenation::{Language, Load, Standard};

const FONT: &[u8] = include_bytes!("../../../app/fonts/GentiumBookPlus-Regular.ttf");

fn main() {
    let mut args = std::env::args().skip(1);
    let (Some(db), Some(module)) = (args.next(), args.next()) else {
        eprintln!("usage: layout_bench <library.db> <module-code>");
        std::process::exit(2);
    };
    let library = Library::open(Path::new(&db)).expect("open library");
    let measure = FontMeasure::new(FONT).expect("font");
    let german = Standard::from_embedded(Language::German1996).unwrap();
    let line_width = 26 * measure.units_per_em() as i64;

    let contents = library.contents(&module).expect("contents");
    let start = std::time::Instant::now();
    let mut lines = 0usize;
    let mut worst = (std::time::Duration::ZERO, String::new());
    for c in &contents {
        let verses = library.chapter(&module, c.book, c.chapter).unwrap();
        let refs: Vec<(u16, &str)> = verses.iter().map(|v| (v.verse, v.text.as_str())).collect();
        let t = std::time::Instant::now();
        let laid = layout_verses(&refs, &[], &[], &measure, Some(&german), line_width);
        let dt = t.elapsed();
        if dt > worst.0 {
            worst = (dt, format!("{} {}", c.book.info().osis, c.chapter));
        }
        lines += laid.len();
    }
    let total = start.elapsed();
    println!(
        "{} chapters, {} lines in {:.2?} ({:.2?}/chapter avg, worst {:.2?} at {})",
        contents.len(),
        lines,
        total,
        total / contents.len() as u32,
        worst.0,
        worst.1,
    );
}
