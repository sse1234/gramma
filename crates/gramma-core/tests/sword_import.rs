//! SWORD zCom commentary import (ADR 0017): a synthetic module exercises
//! the container walk (linked entries, structural fragments, empty slots)
//! and the OSIS fragment parsing (paragraphs, headings, references).

use std::io::Write;

use flate2::Compression;
use flate2::write::ZlibEncoder;
use gramma_core::library::Library;
use gramma_core::reference::BookId;
use gramma_core::sword::{
    SwordModule, Testament, parse_zcom, parse_zld, parse_ztext, read_sword_zip, read_zcom_zip,
};

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
            zip.start_file(format!("modules/comments/zcom/gertest/{name}"), opts)
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
    match read_sword_zip(std::path::Path::new(&path)).unwrap() {
        SwordModule::Commentary(doc) => {
            assert!(!doc.code.is_empty());
            assert!(
                doc.entries.len() > 100,
                "only {} entries",
                doc.entries.len()
            );
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
                "{}: {} commentary entries, {} with heading, {} refs",
                doc.code,
                doc.entries.len(),
                with_heading,
                doc.entries.iter().map(|e| e.refs.len()).sum::<usize>()
            );
        }
        SwordModule::Dictionary(doc) => {
            assert!(!doc.code.is_empty());
            assert!(
                doc.entries.len() > 100,
                "only {} entries",
                doc.entries.len()
            );
            let mut sorts = std::collections::HashSet::new();
            for e in &doc.entries {
                assert!(!e.headword.is_empty() || !e.text.is_empty());
                assert!(sorts.insert(e.sort), "duplicate sort {}", e.sort);
            }
            let with_pron = doc.entries.iter().filter(|e| !e.pron.is_empty()).count();
            println!(
                "{}: {} dictionary entries, {} with transliteration",
                doc.code,
                doc.entries.len(),
                with_pron
            );
        }
        SwordModule::Bible(doc) => {
            assert!(doc.verses.len() > 20000, "only {} verses", doc.verses.len());
            let links: usize = doc.verses.iter().map(|v| v.links.len()).sum();
            assert!(links > 100000, "only {links} word links");
            for v in &doc.verses {
                for l in &v.links {
                    assert!(v.text.is_char_boundary(l.start as usize));
                    assert!(v.text.is_char_boundary(l.end as usize));
                    assert!(l.start < l.end && (l.end as usize) <= v.text.len());
                }
            }
            let john316 = doc
                .verses
                .iter()
                .find(|v| {
                    v.book == gramma_core::reference::book_by_osis("John").unwrap()
                        && v.chapter == 3
                        && v.verse == 16
                })
                .expect("John 3:16 present — the slot walk stayed aligned");
            assert!(
                john316.text.contains("only begotten Son")
                    || john316.text.contains("eingeborenen Sohn"),
                "John 3:16 reads: {}",
                john316.text
            );
            assert!(
                john316.links.iter().any(|l| l.strong == "G3439"),
                "monogenes is linked in John 3:16"
            );
            println!(
                "{}: {} verses, {} word links, {} notes",
                doc.code,
                doc.verses.len(),
                links,
                doc.notes.len()
            );
        }
    }
}

// ---- zLD dictionaries (ADR 0019) ----

const DICT_CONF: &str = "\
[GerTestDict]
Description=Testlexikon Griechisch-Deutsch
DataPath=./modules/lexdict/zld/gertestdict/dict
ModDrv=zLD
SourceType=TEI
Encoding=UTF-8
CompressType=ZIP
Lang=de
";

const ENTRY_1: &str = concat!(
    r#"<entryFree n="00001"><orth>ἀγαθός</orth>"#,
    r#"<pron rend="italic">ag-ath-os'</pron><lb/>"#,
    "<def>gut, brauchbar;\nvgl. Mt 24:12 und danach 25:14</def></entryFree>",
);
const ENTRY_2: &str = concat!(
    r#"<entryFree n="00002"><orth>ἀγάπη</orth>"#,
    r#"<pron rend="italic">ag-ah'-pay</pron><lb/>"#,
    "<def>I) d. Liebe<lb/>1) d. höchste   Form d. Liebe.</def></entryFree>",
);
const ENTRY_3: &str = concat!(
    r#"<entryFree n="00003"><orth>ἄγγελος</orth>"#,
    r#"<pron rend="italic">ang'-el-os</pron><lb/>"#,
    "<def>d. Bote, d. Engel</def></entryFree>",
);

/// Build the four zLD files: two zlib blocks (entries 1+2, entry 3),
/// each with the block-local count and (offset, size) pair header.
fn zld_files() -> (Vec<u8>, Vec<u8>, Vec<u8>, Vec<u8>) {
    fn block(entries: &[&str]) -> Vec<u8> {
        let mut header = Vec::new();
        header.extend_from_slice(&(entries.len() as u32).to_le_bytes());
        let mut body = Vec::new();
        let base = 4 + entries.len() * 8;
        for e in entries {
            header.extend_from_slice(&((base + body.len()) as u32).to_le_bytes());
            header.extend_from_slice(&(e.len() as u32).to_le_bytes());
            body.extend_from_slice(e.as_bytes());
        }
        header.extend_from_slice(&body);
        header
    }
    let blocks = [block(&[ENTRY_1, ENTRY_2]), block(&[ENTRY_3])];
    let mut zdx = Vec::new();
    let mut zdt = Vec::new();
    for b in &blocks {
        let mut z = ZlibEncoder::new(Vec::new(), Compression::default());
        z.write_all(b).unwrap();
        let compressed = z.finish().unwrap();
        zdx.extend_from_slice(&(zdt.len() as u32).to_le_bytes());
        zdx.extend_from_slice(&(compressed.len() as u32).to_le_bytes());
        zdt.extend_from_slice(&compressed);
    }
    let mut idx = Vec::new();
    let mut dat = Vec::new();
    for (key, block_no, entry_no) in [("00001", 0u32, 0u32), ("00002", 0, 1), ("00003", 1, 0)] {
        idx.extend_from_slice(&(dat.len() as u32).to_le_bytes());
        idx.extend_from_slice(&15u32.to_le_bytes());
        dat.extend_from_slice(key.as_bytes());
        dat.extend_from_slice(b"\r\n");
        dat.extend_from_slice(&block_no.to_le_bytes());
        dat.extend_from_slice(&entry_no.to_le_bytes());
    }
    (idx, dat, zdx, zdt)
}

#[test]
fn parses_a_synthetic_zld_dictionary() {
    let (idx, dat, zdx, zdt) = zld_files();
    let dict = parse_zld(DICT_CONF, &idx, &dat, &zdx, &zdt).unwrap();
    assert_eq!(dict.code, "GerTestDict");
    assert_eq!(dict.language, "de");
    assert_eq!(dict.entries.len(), 3);
    let a = &dict.entries[0];
    assert_eq!((a.sort, a.key.as_str()), (1, "00001"));
    assert_eq!(a.headword, "ἀγαθός");
    assert_eq!(a.pron, "ag-ath-os'");
    assert_eq!(a.text, "gut, brauchbar; vgl. Mt 24:12 und danach 25:14");
    let b = &dict.entries[1];
    assert_eq!(
        b.text, "I) d. Liebe\n\n1) d. höchste Form d. Liebe.",
        "lb becomes a paragraph break, whitespace normalizes"
    );
    assert_eq!(dict.entries[2].headword, "ἄγγελος");
}

#[test]
fn the_zip_package_dispatches_by_driver() {
    let dir = std::env::temp_dir().join(format!("gramma-zld-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let path = dir.join("gertestdict.zip");
    let (idx, dat, zdx, zdt) = zld_files();
    {
        let file = std::fs::File::create(&path).unwrap();
        let mut zip = zip::ZipWriter::new(file);
        let opts = zip::write::SimpleFileOptions::default();
        zip.start_file("mods.d/gertestdict.conf", opts).unwrap();
        zip.write_all(DICT_CONF.as_bytes()).unwrap();
        for (name, data) in [
            ("dict.idx", &idx),
            ("dict.dat", &dat),
            ("dict.zdx", &zdx),
            ("dict.zdt", &zdt),
        ] {
            zip.start_file(format!("modules/lexdict/zld/gertestdict/{name}"), opts)
                .unwrap();
            zip.write_all(data).unwrap();
        }
        zip.finish().unwrap();
    }
    match read_sword_zip(&path).unwrap() {
        SwordModule::Dictionary(d) => assert_eq!(d.entries.len(), 3),
        _ => panic!("dispatched wrongly"),
    }
    std::fs::remove_dir_all(&dir).ok();
}

#[test]
fn dictionary_imports_looks_up_and_searches() {
    let (idx, dat, zdx, zdt) = zld_files();
    let dict = parse_zld(DICT_CONF, &idx, &dat, &zdx, &zdt).unwrap();
    let mut library = Library::open_in_memory().unwrap();
    let info = library.import_dictionary(&dict).unwrap();
    assert_eq!((info.kind.as_str(), info.verses), ("dictionary", 3));

    let (entry, prev, next) = library.dictionary_entry("GerTestDict", 2).unwrap().unwrap();
    assert_eq!(entry.headword, "ἀγάπη");
    assert_eq!((prev, next), (Some(1), Some(3)));
    let (_, prev, next) = library.dictionary_entry("GerTestDict", 1).unwrap().unwrap();
    assert_eq!((prev, next), (None, Some(2)));
    assert!(
        library
            .dictionary_entry("GerTestDict", 9)
            .unwrap()
            .is_none()
    );

    // Search: headword and transliteration hits rank before body hits;
    // matching is Unicode case-insensitive.
    let hits = library
        .dictionary_search("GerTestDict", "liebe", 10)
        .unwrap();
    assert_eq!(hits.len(), 1);
    assert_eq!(hits[0].sort, 2);
    // Exact codepoints for now: ἀγάπη has an accented ά, so only
    // ἀγαθός matches (diacritic folding is future work).
    let hits = library.dictionary_search("GerTestDict", "ἀγα", 10).unwrap();
    assert_eq!(hits.len(), 1);
    assert_eq!(hits[0].headword, "ἀγαθός");
    let hits = library
        .dictionary_search("GerTestDict", "Engel", 10)
        .unwrap();
    assert_eq!(hits[0].headword, "ἄγγελος");

    // Re-import replaces.
    library.import_dictionary(&dict).unwrap();
    assert_eq!(
        library
            .dictionary_search("GerTestDict", "Liebe", 10)
            .unwrap()
            .len(),
        1
    );
}

// ---- zText Bibles with Strong's links (ADR 0020) ----

const BIBLE_CONF: &str = "\
[KjvTest]
Description=Testbibel mit Strongs
DataPath=./modules/texts/ztext/kjvtest/
ModDrv=zText
SourceType=OSIS
Encoding=UTF-8
CompressType=ZIP
Versification=KJV
Lang=en
";

const SLOT_IMPORTER: &str = r#"<milestone type="x-importer" subType="x-osis2mod" n="test"/>"#;
const SLOT_BOOK: &str = concat!(
    r#"<div canonical="true" sID="b1" subType="x-OT" type="bookGroup"/> "#,
    r#"<div canonical="true" osisID="Gen" sID="b2" type="book"/> "#,
    r#"<title type="main">GENESIS</title> "#,
);
const SLOT_CHAPTER: &str = concat!(
    r#"<chapter chapterTitle="CHAPTER 1." osisID="Gen.1" sID="c1"/> "#,
    r#"<title type="chapter">CHAPTER 1.</title> "#,
);
const SLOT_V1: &str = concat!(
    r#"<w lemma="strong:G746 lemma.TR:αρχη">In the beginning</w> "#,
    r#"<w lemma="strong:G2316">God</w> "#,
    r#"<transChange type="added">created</transChange> "#,
    r#"<w lemma="strong:G3772 strong:G1093" morph="x">heaven and earth</w>."#,
    r#"<note type="study">a marginal <catchWord>note</catchWord></note>"#,
);
const SLOT_V2: &str = concat!(
    r#"<w lemma="strong:G3772">And heaven</w> "#,
    r#"<w lemma="lemma.TR:untagged">was</w> void."#,
);

fn bible_testament() -> Testament {
    let slots = [SLOT_IMPORTER, SLOT_BOOK, SLOT_CHAPTER, SLOT_V1, SLOT_V2];
    let block: String = slots.concat();
    let mut z = ZlibEncoder::new(Vec::new(), Compression::default());
    z.write_all(block.as_bytes()).unwrap();
    let compressed = z.finish().unwrap();
    let mut bzs = Vec::new();
    bzs.extend_from_slice(&0u32.to_le_bytes());
    bzs.extend_from_slice(&(compressed.len() as u32).to_le_bytes());
    bzs.extend_from_slice(&(block.len() as u32).to_le_bytes());
    let mut bzv = Vec::new();
    let mut slot = |off: u32, size: u16| {
        bzv.extend_from_slice(&0u32.to_le_bytes());
        bzv.extend_from_slice(&off.to_le_bytes());
        bzv.extend_from_slice(&size.to_le_bytes());
    };
    slot(0, 0); // testament intro, empty
    let mut off = 0u32;
    for s in slots {
        slot(off, s.len() as u16);
        off += s.len() as u32;
    }
    Testament {
        bzs,
        bzv,
        bzz: compressed,
    }
}

#[test]
fn parses_a_synthetic_ztext_bible() {
    let doc = parse_ztext(BIBLE_CONF, &[bible_testament()]).unwrap();
    assert_eq!(doc.code, "KjvTest");
    assert_eq!(doc.verses.len(), 2);
    let v1 = &doc.verses[0];
    assert_eq!(
        (v1.book, v1.chapter, v1.verse),
        (BookId::from_index(0).unwrap(), 1, 1)
    );
    assert_eq!(v1.text, "In the beginning God created heaven and earth.");
    let strongs: Vec<(&str, &str)> = v1
        .links
        .iter()
        .map(|l| {
            (
                l.strong.as_str(),
                &v1.text[l.start as usize..l.end as usize],
            )
        })
        .collect();
    assert_eq!(
        strongs,
        [
            ("G746", "In the beginning"),
            ("G2316", "God"),
            ("G3772", "heaven and earth"),
            ("G1093", "heaven and earth"),
        ],
        "words carry their Strong links; transChange text has none"
    );
    assert_eq!(doc.notes.len(), 1);
    assert_eq!(doc.notes[0].text, "a marginal note");
    let v2 = &doc.verses[1];
    assert_eq!(v2.verse, 2);
    assert_eq!(v2.text, "And heaven was void.");
    assert_eq!(v2.links.len(), 1, "lemma without strong: yields no link");
}

#[test]
fn bible_imports_with_concordance_and_word_resolution() {
    let doc = parse_ztext(BIBLE_CONF, &[bible_testament()]).unwrap();
    let mut library = Library::open_in_memory().unwrap();
    let info = library.import_bible(&doc).unwrap();
    assert_eq!(
        (info.kind.as_str(), info.verses, info.notes),
        ("bible", 2, 1)
    );

    // The concordance: every occurrence of a Strong number, in order.
    let hits = library.concordance("KjvTest", "G3772", 100).unwrap();
    assert_eq!(hits.len(), 2);
    assert_eq!((hits[0].chapter, hits[0].verse), (1, 1));
    assert_eq!(
        &hits[0].text[hits[0].start as usize..hits[0].end as usize],
        "heaven and earth"
    );
    assert_eq!((hits[1].chapter, hits[1].verse), (1, 2));
    assert!(
        library
            .concordance("KjvTest", "G9999", 100)
            .unwrap()
            .is_empty()
    );

    // A long-pressed word resolves to its Strong number(s).
    let genesis = BookId::from_index(0).unwrap();
    let strongs = library
        .strongs_for_word("KjvTest", genesis, 1, 1, "god")
        .unwrap();
    assert_eq!(strongs, ["G2316"], "case-insensitive containment");
    let strongs = library
        .strongs_for_word("KjvTest", genesis, 1, 1, "beginning")
        .unwrap();
    assert_eq!(strongs, ["G746"], "a word inside a multi-word link matches");
    assert!(
        library
            .strongs_for_word("KjvTest", genesis, 1, 1, "created")
            .unwrap()
            .is_empty()
    );

    // The module with Strong links is discoverable.
    assert_eq!(
        library.strongs_module().unwrap().as_deref(),
        Some("KjvTest")
    );
}
