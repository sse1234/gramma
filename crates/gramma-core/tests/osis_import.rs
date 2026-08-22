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
}

#[test]
fn contents_for_unknown_module_fails() {
    let library = library_with(CONTAINER);
    assert!(library.contents("Nope").is_err());
}
