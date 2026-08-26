//! SWORD zCom commentary import (ADR 0017): a synthetic module exercises
//! the container walk (linked entries, structural fragments, empty slots)
//! and the OSIS fragment parsing (paragraphs, headings, references).

use std::io::Write;

use flate2::write::ZlibEncoder;
use flate2::Compression;
use gramma_core::library::Library;
use gramma_core::reference::BookId;
use gramma_core::sword::{parse_zcom, read_zcom_zip, Testament};

const CONF: &str = "\
[GerTest]
Description=Testkommentar zur Bibel
DataPath=./modules/comments/zcom/gertest/
ModDrv=zCom
SourceType=OSIS
Encoding=UTF-8
CompressType=ZIP
Versification=KJV
Lang=de
";

const FRAG_BOOK: &str = r#"<div osisID="Gen" sID="g1" type="book"/>"#;
const FRAG_CHAPTER: &str = r#"<chapter osisID="Gen.1" sID="g2"/> "#;
const FRAG_A: &str = concat!(
    r#"<div annotateRef="Gen.1.1-Gen.1.2" annotateType="commentary" sID="g3" type="section"/>"#,
    r#"<div sID="g4" type="x-p"/><title>Der Anfang</title><div eID="g4" type="x-p"/> "#,
    r#"<div sID="g5" type="x-p"/>Am Anfang steht das <hi type="italic">Wort</hi>, "#,
    r#"vgl. <reference osisRef="John.1.1">Joh 1,1</reference>.<div eID="g5" type="x-p"/>"#,
    r#"<div sID="g6" type="x-p"/>Zweiter   Absatz.<div eID="g6" type="x-p"/>"#,
    r#"<div annotateRef="Gen.1.1-Gen.1.2" annotateType="commentary" eID="g3" type="section"/>"#,
);
const FRAG_B: &str = concat!(
    r#"<div annotateRef="Gen.1.3" annotateType="commentary" sID="g7" type="section"/>"#,
    r#"<div sID="g8" type="x-p"/>Licht wird.<div eID="g8" type="x-p"/>"#,
);

/// Build the testament files for one block holding the four fragments,
/// with verse slots as SWORD writes them: an empty leading slot, the
/// structural book/chapter entries, and verses 1-2 linked to fragment A.
fn testament() -> Testament {
    let block: String = [FRAG_BOOK, FRAG_CHAPTER, FRAG_A, FRAG_B].concat();
    let mut z = ZlibEncoder::new(Vec::new(), Compression::default());
    z.write_all(block.as_bytes()).unwrap();
    let compressed = z.finish().unwrap();

    let mut bzs = Vec::new();
    bzs.extend_from_slice(&0u32.to_le_bytes());
    bzs.extend_from_slice(&(compressed.len() as u32).to_le_bytes());
    bzs.extend_from_slice(&(block.len() as u32).to_le_bytes());

    let offset = |frag: &str| block.find(frag).unwrap() as u32;
    let mut bzv = Vec::new();
    let mut slot = |block_no: u32, off: u32, size: u16| {
        bzv.extend_from_slice(&block_no.to_le_bytes());
        bzv.extend_from_slice(&off.to_le_bytes());
        bzv.extend_from_slice(&size.to_le_bytes());
    };
    slot(0, 0, 0); // testament intro, empty
    slot(u32::MAX, u32::MAX, 0); // garbage offsets with size 0 (seen in the wild)
    slot(0, offset(FRAG_BOOK), FRAG_BOOK.len() as u16);
    slot(0, offset(FRAG_CHAPTER), FRAG_CHAPTER.len() as u16);
    slot(0, offset(FRAG_A), FRAG_A.len() as u16); // Gen 1:1
    slot(0, offset(FRAG_A), FRAG_A.len() as u16); // Gen 1:2, linked
    slot(0, offset(FRAG_B), FRAG_B.len() as u16); // Gen 1:3

    Testament {
        bzs,
        bzv,
        bzz: compressed,
    }
}

#[test]
fn parses_a_synthetic_zcom_module() {
    let doc = parse_zcom(CONF, &[testament()]).unwrap();
    assert_eq!(doc.code, "GerTest");
    assert_eq!(doc.title, "Testkommentar zur Bibel");
    assert_eq!(doc.language, "de");
    assert_eq!(doc.entries.len(), 2, "structural fragments are not entries");

    let a = &doc.entries[0];
    assert_eq!(
        (a.book, a.chapter, a.verse_start, a.verse_end),
        (BookId::from_index(0).unwrap(), 1, 1, 2)
    );
    assert_eq!(a.heading.as_deref(), Some("Der Anfang"));
    assert_eq!(
        a.text,
        "Am Anfang steht das Wort, vgl. Joh 1,1.\n\nZweiter Absatz."
    );
    assert_eq!(a.refs.len(), 1);
    let r = &a.refs[0];
    assert_eq!(r.osis, "John.1.1");
    assert_eq!(
        &a.text.as_bytes()[r.start as usize..r.end as usize],
        "Joh 1,1".as_bytes()
    );

    let b = &doc.entries[1];
    assert_eq!((b.verse_start, b.verse_end), (3, 3));
    assert_eq!(b.heading, None);
    assert_eq!(b.text, "Licht wird.");
    assert!(b.refs.is_empty());
}

#[test]
fn reads_the_zip_package_form() {
    let dir = std::env::temp_dir().join(format!("gramma-sword-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let path = dir.join("gertest.zip");
    let t = testament();
    {
        let file = std::fs::File::create(&path).unwrap();
        let mut zip = zip::ZipWriter::new(file);
        let opts = zip::write::SimpleFileOptions::default();
        zip.start_file("mods.d/gertest.conf", opts).unwrap();
        zip.write_all(CONF.as_bytes()).unwrap();
        for (name, data) in [("ot.bzs", &t.bzs), ("ot.bzv", &t.bzv), ("ot.bzz", &t.bzz)] {
            zip.start_file(
                format!("modules/comments/zcom/gertest/{name}"),
                opts,
            )
            .unwrap();
            zip.write_all(data).unwrap();
        }
        zip.finish().unwrap();
    }
    let doc = read_zcom_zip(&path).unwrap();
    assert_eq!(doc.code, "GerTest");
    assert_eq!(doc.entries.len(), 2);
    std::fs::remove_dir_all(&dir).ok();
}

#[test]
fn commentary_imports_into_the_library_and_queries_by_chapter() {
    let doc = parse_zcom(CONF, &[testament()]).unwrap();
    let mut library = Library::open_in_memory().unwrap();
    let info = library.import_commentary(&doc).unwrap();
    assert_eq!(info.code, "GerTest");
    assert_eq!(info.kind, "commentary");
    assert_eq!(info.verses, 2, "content units of a commentary are entries");

    let modules = library.modules().unwrap();
    let m = modules.iter().find(|m| m.code == "GerTest").unwrap();
    assert_eq!(m.kind, "commentary");

    let genesis = BookId::from_index(0).unwrap();
    let comments = library.comments("GerTest", genesis, 1).unwrap();
    assert_eq!(comments.len(), 2);
    assert_eq!(comments[0].verse_start, 1);
    assert_eq!(comments[0].verse_end, 2);
    assert_eq!(comments[0].heading.as_deref(), Some("Der Anfang"));
    assert_eq!(comments[0].refs.len(), 1);
    assert_eq!(comments[0].refs[0].osis, "John.1.1");
    assert!(library.comments("GerTest", genesis, 2).unwrap().is_empty());

    // Re-import replaces, never duplicates.
    library.import_commentary(&doc).unwrap();
    assert_eq!(library.comments("GerTest", genesis, 1).unwrap().len(), 2);
}

/// Opt-in validation against a real CrossWire package:
/// `GRAMMA_SWORD_ZIP=/path/to/Module.zip cargo test -p gramma-core -- --ignored`
#[test]
#[ignore = "needs a real SWORD package via GRAMMA_SWORD_ZIP"]
fn reads_a_real_package_when_provided() {
    let path = std::env::var("GRAMMA_SWORD_ZIP").expect("set GRAMMA_SWORD_ZIP");
    let doc = read_zcom_zip(std::path::Path::new(&path)).unwrap();
    assert!(!doc.code.is_empty());
    assert!(doc.entries.len() > 100, "only {} entries", doc.entries.len());
    for e in &doc.entries {
        assert!(!e.text.is_empty() || e.heading.is_some());
        assert!(e.verse_start <= e.verse_end);
        for r in &e.refs {
            assert!(e.text.is_char_boundary(r.start as usize));
            assert!(e.text.is_char_boundary(r.end as usize));
            assert!(r.start < r.end && (r.end as usize) <= e.text.len());
        }
    }
    let with_heading = doc.entries.iter().filter(|e| e.heading.is_some()).count();
    println!(
        "{}: {} entries, {} with heading, {} refs",
        doc.code,
        doc.entries.len(),
        with_heading,
        doc.entries.iter().map(|e| e.refs.len()).sum::<usize>()
    );
}
