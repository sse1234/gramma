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
    let mut text_out: Option<String> = None;
    let mut find: Option<String> = None;
    let mut fragments_page: Option<usize> = None;
    let mut lines_page: Option<usize> = None;
    let mut page_chars = false;
    let mut i = 2;
    while i < args.len() {
        match args[i].as_str() {
            "--lines" => {
                lines_page = Some(args[i + 1].parse().unwrap());
                i += 2;
            }
            "--fragments" => {
                fragments_page = Some(args[i + 1].parse().unwrap());
                i += 2;
            }
            "--pagechars" => {
                page_chars = true;
                i += 1;
            }
            "--find" => {
                find = Some(args[i + 1].clone());
                i += 2;
            }
            "--text" => {
                text_out = Some(args[i + 1].clone());
                i += 2;
            }
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
    if let Some(n) = lines_page {
        let mut data = Vec::new();
        File::open(path)
            .expect("open")
            .read_to_end(&mut data)
            .expect("read");
        let (pages, _) = pdf::read_pages(data).expect("read pages");
        let options = gramma_core::document::infer::InferOptions::default();
        println!(
            "gutter: {:?}",
            gramma_core::document::infer::column_gutter(&pages[n])
        );
        for l in gramma_core::document::infer::lines_of_page(&pages[n], n, &options) {
            println!(
                "  top={:6.1} left={:6.1} right={:6.1} size={:4.1} cells={} {}",
                l.top,
                l.left,
                l.right,
                l.size,
                l.cells.len(),
                trunc(&l.text().replace('\t', " ⇥ "), 90)
            );
        }
        return;
    }
    if fragments_page.is_some() || page_chars {
        let mut data = Vec::new();
        File::open(path)
            .expect("open")
            .read_to_end(&mut data)
            .expect("read");
        let (pages, _) = pdf::read_pages(data).expect("read pages");
        if let Some(n) = fragments_page {
            let page = &pages[n];
            println!(
                "page {n}: {}x{} fragments={}",
                page.width,
                page.height,
                page.fragments.len()
            );
            for f in &page.fragments {
                println!(
                    "  y={:6.1} x={:6.1} w={:5.1} size={:4.1} {}{}{} {:?}",
                    f.y,
                    f.x,
                    f.width,
                    f.size,
                    if f.font.bold { "B" } else { "-" },
                    if f.font.italic { "I" } else { "-" },
                    if f.rise != 0.0 { "^" } else { " " },
                    f.text
                );
            }
        }
        if page_chars {
            for (i, page) in pages.iter().enumerate() {
                let chars: usize = page.fragments.iter().map(|f| f.text.chars().count()).sum();
                println!("{i} {chars}");
            }
        }
        return;
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
    if let Some(path) = text_out {
        // Plain text of every block, one paragraph per line, for the
        // extraction comparison tool.
        fn dump(blocks: &[Block], out: &mut String) {
            for b in blocks {
                match b {
                    Block::Heading { inlines, .. } | Block::Paragraph { inlines, .. } => {
                        out.push_str(&plain_text(inlines));
                        out.push('\n');
                    }
                    Block::List { items, .. } => {
                        for item in items {
                            dump(item, out);
                        }
                    }
                    Block::Table { rows, .. } => {
                        for row in rows {
                            for cell in row {
                                out.push_str(&plain_text(cell));
                                out.push('\n');
                            }
                        }
                    }
                    Block::Figure { caption, .. } => {
                        out.push_str(&plain_text(caption));
                        out.push('\n');
                    }
                    _ => {}
                }
            }
        }
        let mut out = String::new();
        dump(&doc.blocks, &mut out);
        for note in &doc.notes {
            dump(&note.blocks, &mut out);
        }
        std::fs::write(&path, out).expect("write text dump");
        println!("text written to {path}");
    }
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
    if let Some(needle) = &find {
        for (i, b) in doc.blocks.iter().enumerate() {
            let d = describe(b);
            let full = match b {
                Block::Paragraph { inlines, .. } | Block::Heading { inlines, .. } => {
                    plain_text(inlines)
                }
                Block::List { items, .. } => items
                    .iter()
                    .flat_map(|it| it.iter())
                    .map(|b| match b {
                        Block::Paragraph { inlines, .. } => plain_text(inlines),
                        _ => String::new(),
                    })
                    .collect::<Vec<_>>()
                    .join(" / "),
                Block::Table { rows, .. } => rows
                    .iter()
                    .flat_map(|r| r.iter())
                    .map(|c| plain_text(c))
                    .collect::<Vec<_>>()
                    .join(" | "),
                _ => String::new(),
            };
            if full.contains(needle.as_str()) || d.contains(needle.as_str()) {
                println!("FOUND {i}: {}", trunc(&d, 160));
                let k = full.find(needle.as_str()).unwrap_or(0);
                let start = full[..k]
                    .char_indices()
                    .rev()
                    .nth(60)
                    .map(|(i, _)| i)
                    .unwrap_or(0);
                let end = full[k..]
                    .char_indices()
                    .nth(40)
                    .map(|(i, _)| k + i)
                    .unwrap_or(full.len());
                println!("   context: {:?}", &full[start..end]);
            }
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
