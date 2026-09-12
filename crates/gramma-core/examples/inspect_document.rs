//! Import a PDF or EPUB through the document model and print what was
//! found: counts per block kind, notes, images, and the first blocks.
//!
//! Usage: cargo run --example inspect_document -- <file> [--blocks N] [--from I]
//!        [--import <library.db> <code> [bible|commentary|book]]

use std::collections::BTreeMap;
use std::fs::File;
use std::io::Read;

use gramma_core::document::interpret::{DocumentKind, detect};
use gramma_core::document::{Block, Inline, ParagraphStyle, plain_text};
use gramma_core::document::{epub, pdf};
use gramma_core::library::Library;

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let path = args.get(1).expect("file path");
    let mut show = 40usize;
    let mut from = 0usize;
    let mut import: Option<(String, String, Option<String>)> = None;
    let mut entries_chapter: Option<u16> = None;
    let mut i = 2;
    while i < args.len() {
        match args[i].as_str() {
            "--entries" => {
                entries_chapter = Some(args[i + 1].parse().unwrap());
                i += 2;
            }
            "--import" => {
                let kind = args.get(i + 3).filter(|k| !k.starts_with("--")).cloned();
                import = Some((args[i + 1].clone(), args[i + 2].clone(), kind.clone()));
                i += if kind.is_some() { 4 } else { 3 };
            }
            "--blocks" => {
                show = args[i + 1].parse().unwrap();
                i += 2;
            }
            "--from" => {
                from = args[i + 1].parse().unwrap();
                i += 2;
            }
            _ => i += 1,
        }
    }
    let started = std::time::Instant::now();
    let doc = if path.to_ascii_lowercase().ends_with(".epub") {
        epub::read(File::open(path).expect("open")).expect("read epub")
    } else {
        let mut data = Vec::new();
        File::open(path)
            .expect("open")
            .read_to_end(&mut data)
            .expect("read");
        pdf::read(data).expect("read pdf")
    };
    let elapsed = started.elapsed();
    let mut doc = doc;
    if doc.title.trim().is_empty() {
        doc.title = gramma_core::document::title_from_filename(path);
    }
    println!(
        "title: {:?}  language: {:?}  authors: {:?}",
        doc.title, doc.language, doc.authors
    );
    let mut kinds: BTreeMap<String, usize> = BTreeMap::new();
    let mut verse_numbers = 0usize;
    let mut note_refs = 0usize;
    let mut chars = 0usize;
    fn count(
        blocks: &[Block],
        kinds: &mut BTreeMap<String, usize>,
        verses: &mut usize,
        refs: &mut usize,
        chars: &mut usize,
    ) {
        for b in blocks {
            let (kind, inlines): (String, Vec<&Vec<Inline>>) = match b {
                Block::Heading { level, inlines } => (format!("heading{level}"), vec![inlines]),
                Block::Paragraph { style, inlines } => (
                    match style {
                        ParagraphStyle::Body => "paragraph".into(),
                        ParagraphStyle::Quote => "quote".into(),
                        ParagraphStyle::Scripture => "scripture".into(),
                        ParagraphStyle::Poetry { .. } => "poetry".into(),
                        ParagraphStyle::Caption => "caption".into(),
                    },
                    vec![inlines],
                ),
                Block::List { items, .. } => {
                    for item in items {
                        count(item, kinds, verses, refs, chars);
                    }
                    ("list".into(), vec![])
                }
                Block::Table { rows, .. } => ("table".into(), rows.iter().flatten().collect()),
                Block::Figure { .. } => ("figure".into(), vec![]),
                Block::Rule => ("rule".into(), vec![]),
                Block::Milestone { .. } => ("milestone".into(), vec![]),
            };
            *kinds.entry(kind).or_default() += 1;
            for inlines in inlines {
                for inline in inlines.iter() {
                    match inline {
                        Inline::VerseNumber(_) => *verses += 1,
                        Inline::NoteRef(_) => *refs += 1,
                        Inline::Text { text, .. } => *chars += text.chars().count(),
                        _ => {}
                    }
                }
            }
        }
    }
    count(
        &doc.blocks,
        &mut kinds,
        &mut verse_numbers,
        &mut note_refs,
        &mut chars,
    );
    println!(
        "blocks: {}  chars: {}  verse numbers: {}  note refs: {}  notes: {}  images: {} ({} KB)  in {:.1?}",
        doc.blocks.len(),
        chars,
        verse_numbers,
        note_refs,
        doc.notes.len(),
        doc.images.len(),
        doc.images.iter().map(|i| i.data.len()).sum::<usize>() / 1024,
        elapsed
    );
    for (k, n) in &kinds {
        println!("  {k:12} {n}");
    }
    let detection = detect(&doc);
    println!("detected: {detection:?}");
    if let Some(chapter) = entries_chapter {
        match gramma_core::document::interpret::to_commentary(&doc, None) {
            Ok(c) => {
                for e in c.entries.iter().filter(|e| e.chapter == chapter) {
                    println!(
                        "  entry {}:{}-{} heading={:?} {}",
                        e.chapter,
                        e.verse_start,
                        e.verse_end,
                        e.heading.as_deref().map(|h| trunc(h, 24)),
                        trunc(&e.text, 60)
                    );
                }
            }
            Err(e) => println!("to_commentary failed: {e}"),
        }
    }
    if let Some((db, code, kind)) = import {
        let kind = match kind.as_deref() {
            Some("bible") => DocumentKind::Bible,
            Some("commentary") => DocumentKind::Commentary,
            Some("book") => DocumentKind::Book,
            _ => detection.kind,
        };
        let started = std::time::Instant::now();
        let mut library = Library::open(std::path::Path::new(&db)).expect("open library");
        match library.import_document(&doc, kind, &code, None) {
            Ok(info) => println!(
                "imported as {kind:?}: {info:?} in {:.1?}",
                started.elapsed()
            ),
            Err(e) => println!("import failed: {e}"),
        }
    }
    println!("--- blocks {from}..{}", from + show);
    let show_inlines = std::env::var("INLINES").is_ok();
    for (i, b) in doc.blocks.iter().enumerate().skip(from).take(show) {
        println!("{i:5} {}", describe(b));
        if show_inlines {
            let inlines: Option<&Vec<Inline>> = match b {
                Block::Paragraph { inlines, .. } | Block::Heading { inlines, .. } => Some(inlines),
                Block::List { items, .. } => {
                    items
                        .first()
                        .and_then(|it| it.first())
                        .and_then(|b| match b {
                            Block::Paragraph { inlines, .. } => Some(inlines),
                            _ => None,
                        })
                }
                _ => None,
            };
            if let Some(inlines) = inlines {
                for inline in inlines.iter().take(4) {
                    println!(
                        "         {:?}",
                        match inline {
                            Inline::Text { text, style } =>
                                format!("{:?} {:?}", trunc(text, 40), style),
                            other => format!("{other:?}"),
                        }
                    );
                }
            }
        }
    }
    if !doc.notes.is_empty() {
        println!("--- first notes");
        for (i, n) in doc.notes.iter().take(5).enumerate() {
            let text: String = n
                .blocks
                .iter()
                .map(describe)
                .collect::<Vec<_>>()
                .join(" | ");
            println!("  [{i}] label={:?} {}", n.label, trunc(&text, 160));
        }
    }
}

fn describe(b: &Block) -> String {
    match b {
        Block::Heading { level, inlines } => {
            format!("H{level}  {}", trunc(&plain_text(inlines), 100))
        }
        Block::Paragraph { style, inlines } => {
            let styled: usize = inlines
                .iter()
                .filter(|i| matches!(i, Inline::Text { style, .. } if !style.is_plain()))
                .count();
            let marks: String = inlines
                .iter()
                .filter_map(|i| match i {
                    Inline::VerseNumber(v) => Some(format!("v{v}")),
                    Inline::NoteRef(n) => Some(format!("n{n}")),
                    _ => None,
                })
                .take(6)
                .collect::<Vec<_>>()
                .join(",");
            format!(
                "P{:?} [{marks}] styled={styled}  {}",
                style,
                trunc(&plain_text(inlines), 110)
            )
        }
        Block::List { ordered, items } => format!(
            "LIST ordered={ordered} items={} first={}",
            items.len(),
            items
                .first()
                .map(|i| i.iter().map(describe).collect::<Vec<_>>().join(" / "))
                .unwrap_or_default()
        ),
        Block::Table { header_rows, rows } => format!(
            "TABLE {}x{} header={header_rows} first row={:?}",
            rows.len(),
            rows.first().map(|r| r.len()).unwrap_or(0),
            rows.first()
                .map(|r| r
                    .iter()
                    .map(|c| trunc(&plain_text(c), 30))
                    .collect::<Vec<_>>())
                .unwrap_or_default()
        ),
        Block::Figure { image, caption } => format!(
            "FIGURE #{image} caption={:?}",
            trunc(&plain_text(caption), 60)
        ),
        Block::Rule => "RULE".into(),
        Block::Milestone { osis } => format!("MILESTONE {osis}"),
    }
}

fn trunc(s: &str, n: usize) -> String {
    let s = s.replace('\n', "⏎");
    if s.chars().count() <= n {
        s
    } else {
        format!("{}…", s.chars().take(n).collect::<String>())
    }
}
