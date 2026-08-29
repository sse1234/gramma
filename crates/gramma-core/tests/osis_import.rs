use gramma_core::library::Library;
use gramma_core::reference::book_by_osis;

const CONTAINER: &str = include_str!("fixtures/container.xml");
const MILESTONE: &str = include_str!("fixtures/milestone.xml");

fn library_with(fixture: &str) -> Library {
    let mut library = Library::open_in_memory().unwrap();
    library.import_osis(fixture.as_bytes()).unwrap();
    library
}

#[test]
fn import_reports_module_metadata_and_verse_count() {
    let mut library = Library::open_in_memory().unwrap();
    let summary = library.import_osis(CONTAINER.as_bytes()).unwrap();
    assert_eq!(summary.code, "FixDe");
    assert_eq!(summary.title, "Fixtur Deutsch");
    assert_eq!(summary.language, "de");
    assert_eq!(summary.verses, 3);
}

#[test]
fn imported_module_is_listed() {
    let library = library_with(CONTAINER);
    let modules = library.modules().unwrap();
    assert_eq!(modules.len(), 1);
    assert_eq!(modules[0].code, "FixDe");
    assert_eq!(modules[0].title, "Fixtur Deutsch");
}

#[test]
fn container_verses_roundtrip_through_chapter_query() {
    let library = library_with(CONTAINER);
    let genesis = book_by_osis("Gen").unwrap();
    let verses = library.chapter("FixDe", genesis, 1).unwrap();
    assert_eq!(verses.len(), 2);
    assert_eq!(verses[0].verse, 1);
    assert_eq!(verses[0].text, "Am Anfang schuf Gott Himmel und Erde.");
}

#[test]
fn verse_text_whitespace_is_normalized() {
    let library = library_with(CONTAINER);
    let genesis = book_by_osis("Gen").unwrap();
    let verses = library.chapter("FixDe", genesis, 1).unwrap();
    assert_eq!(
        verses[1].text,
        "Und die Erde war wüst und leer, und es war finster auf der Tiefe."
    );
}

#[test]
fn non_canonical_books_are_skipped() {
    let library = library_with(CONTAINER);
    let summary = &library.modules().unwrap()[0];
    assert_eq!(summary.verses, 3);
}

#[test]
fn milestone_verses_are_imported() {
    let library = library_with(MILESTONE);
    let john = book_by_osis("John").unwrap();
    let verses = library.chapter("FixEn", john, 3).unwrap();
    assert_eq!(verses.len(), 2);
    assert_eq!(verses[1].verse, 17);
    assert_eq!(
        verses[1].text,
        "For God did not send his Son to condemn the world."
    );
}

#[test]
fn markup_is_unwrapped_and_notes_and_titles_are_excluded() {
    let library = library_with(MILESTONE);
    let john = book_by_osis("John").unwrap();
    let verses = library.chapter("FixEn", john, 3).unwrap();
    assert_eq!(
        verses[0].text,
        "For God so loved the world, that he gave his only Son."
    );
}

#[test]
fn reimporting_a_module_replaces_it() {
    let mut library = library_with(CONTAINER);
    library.import_osis(CONTAINER.as_bytes()).unwrap();
    let modules = library.modules().unwrap();
    assert_eq!(modules.len(), 1);
    assert_eq!(modules[0].verses, 3);
}

#[test]
fn chapter_query_for_unknown_module_fails() {
    let library = library_with(CONTAINER);
    let genesis = book_by_osis("Gen").unwrap();
    assert!(library.chapter("Nope", genesis, 1).is_err());
}

#[test]
fn empty_chapter_yields_empty_list() {
    let library = library_with(CONTAINER);
    let genesis = book_by_osis("Gen").unwrap();
    let verses = library.chapter("FixDe", genesis, 40).unwrap();
    assert!(verses.is_empty());
}

#[test]
fn library_persists_across_reopen() {
    let dir = std::env::temp_dir().join(format!("gramma-test-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let db = dir.join("library.db");
    {
        let mut library = Library::open(&db).unwrap();
        library.import_osis(CONTAINER.as_bytes()).unwrap();
    }
    let library = Library::open(&db).unwrap();
    assert_eq!(library.modules().unwrap().len(), 1);
    // Windows refuses to delete an open database — close it first.
    drop(library);
    std::fs::remove_dir_all(&dir).unwrap();
}

#[test]
fn contents_lists_chapters_in_canonical_order() {
    let library = library_with(CONTAINER);
    let contents = library.contents("FixDe").unwrap();
    let osis: Vec<String> = contents
        .iter()
        .map(|c| format!("{}.{}", c.book.info().osis, c.chapter))
        .collect();
    assert_eq!(osis, ["Gen.1", "Gen.2"]);
    assert!(contents.iter().all(|c| c.text_length > 0));
    assert_eq!(contents[0].max_verse, 2);
    assert_eq!(contents[1].max_verse, 1);
}

#[test]
fn contents_for_unknown_module_fails() {
    let library = library_with(CONTAINER);
    assert!(library.contents("Nope").is_err());
}

#[test]
fn notes_are_extracted_per_verse_in_order() {
    let library = library_with(CONTAINER);
    let genesis = book_by_osis("Gen").unwrap();
    let notes = library.notes("FixDe", genesis, 1).unwrap();
    assert_eq!(notes.len(), 2);
    assert_eq!(notes[0].verse, 1);
    assert_eq!(notes[0].seq, 1);
    assert_eq!(notes[0].text, "Hebr. bereschit");
    // The first note anchors right after "Am Anfang".
    assert_eq!(notes[0].offset, "Am Anfang".len() as u32);
    assert_eq!(notes[1].seq, 2);
    assert_eq!(notes[1].text, "Im Hebr. steht »Himmel« in der Mehrzahl");
    assert_eq!(
        notes[1].offset,
        "Am Anfang schuf Gott Himmel und Erde.".len() as u32
    );
}

#[test]
fn notes_keep_out_of_verse_text() {
    let library = library_with(CONTAINER);
    let genesis = book_by_osis("Gen").unwrap();
    let verses = library.chapter("FixDe", genesis, 1).unwrap();
    assert_eq!(verses[0].text, "Am Anfang schuf Gott Himmel und Erde.");
}

#[test]
fn milestone_note_with_markup_is_flattened() {
    let library = library_with(MILESTONE);
    let john = book_by_osis("John").unwrap();
    let notes = library.notes("FixEn", john, 3).unwrap();
    assert_eq!(notes.len(), 1);
    assert_eq!(notes[0].verse, 16);
    assert_eq!(notes[0].text, "Or: loved in this way");
}

#[test]
fn module_info_reports_note_count() {
    let library = library_with(CONTAINER);
    assert_eq!(library.modules().unwrap()[0].notes, 2);
}

#[test]
fn chapters_without_notes_yield_empty_list() {
    let library = library_with(CONTAINER);
    let genesis = book_by_osis("Gen").unwrap();
    assert!(library.notes("FixDe", genesis, 2).unwrap().is_empty());
}

#[test]
fn untyped_titles_become_section_headings_for_the_following_verse() {
    let library = library_with(CONTAINER);
    let genesis = book_by_osis("Gen").unwrap();
    let headings = library.headings("FixDe", genesis, 1).unwrap();
    assert_eq!(headings.len(), 1);
    assert_eq!(headings[0].verse, 1);
    assert_eq!(headings[0].level, 1);
    assert_eq!(headings[0].text, "Die Schöpfung");
}

#[test]
fn typed_titles_are_not_section_headings() {
    // The book's type="main" title must not appear as a heading.
    let library = library_with(CONTAINER);
    let genesis = book_by_osis("Gen").unwrap();
    let all: Vec<_> = library.headings("FixDe", genesis, 1).unwrap();
    assert!(all.iter().all(|h| h.text != "Das erste Buch Mose"));
}

#[test]
fn section_and_subsection_levels_are_captured_in_order() {
    let source = r#"<?xml version="1.0" encoding="UTF-8"?>
<osis xmlns="http://www.bibletechnologies.net/2003/OSIS/namespace">
  <osisText osisIDWork="FixH" xml:lang="de">
    <header><work osisWork="FixH"><title>Fixtur H</title></work></header>
    <div type="book" osisID="Gen">
      <chapter osisID="Gen.1">
        <verse osisID="Gen.1.1"><div sID="s1" type="section"/> <title>Die Schöpfung</title> <div sID="s2" type="subSection"/> <title>Der Anfang</title> Am Anfang schuf Gott.</verse>
        <verse osisID="Gen.1.2">Und die Erde war wüst.</verse>
      </chapter>
    </div>
  </osisText>
</osis>"#;
    let mut library = Library::open_in_memory().unwrap();
    library.import_osis(source.as_bytes()).unwrap();
    let genesis = book_by_osis("Gen").unwrap();
    let headings = library.headings("FixH", genesis, 1).unwrap();
    assert_eq!(headings.len(), 2);
    assert_eq!(
        (
            headings[0].verse,
            headings[0].level,
            headings[0].text.as_str()
        ),
        (1, 1, "Die Schöpfung")
    );
    assert_eq!(
        (
            headings[1].verse,
            headings[1].level,
            headings[1].text.as_str()
        ),
        (1, 2, "Der Anfang")
    );
    let verses = library.chapter("FixH", genesis, 1).unwrap();
    assert_eq!(verses[0].text, "Am Anfang schuf Gott.");
}
