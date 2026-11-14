//! Managing what the library holds (ADR 0039): a module is deleted with
//! everything it brought, a module is renamed without losing its
//! identity, and a title the reader chose survives a re-import.

use gramma_library::{Library, LibraryError};
use gramma_reference::book_by_osis;

const CONTAINER: &str = include_str!("fixtures/container.xml");
const MILESTONE: &str = include_str!("fixtures/milestone.xml");
const PLAN: &str = r#"{"name":"Jahresplan","days":[[{"label":"1. Mose 1","osis":"Gen.1"}]]}"#;

#[test]
fn deleting_a_module_removes_it_and_its_content() {
    let mut library = Library::open_in_memory().unwrap();
    let first = library.import_osis(CONTAINER.as_bytes()).unwrap().code;
    let second = library.import_osis(MILESTONE.as_bytes()).unwrap().code;
    assert_ne!(first, second);
    let genesis = book_by_osis("Gen").unwrap();
    assert!(!library.chapter(&first, genesis, 1).unwrap().is_empty());

    library.delete_module(&first).unwrap();
    let codes: Vec<String> = library
        .modules()
        .unwrap()
        .into_iter()
        .map(|m| m.code)
        .collect();
    assert_eq!(
        codes.as_slice(),
        std::slice::from_ref(&second),
        "the other module stays"
    );
    assert!(matches!(
        library.chapter(&first, genesis, 1),
        Err(LibraryError::UnknownModule(_))
    ));
    assert_eq!(
        library.orphaned_rows().unwrap(),
        0,
        "no content left behind"
    );

    // Deleting what is not there is an error, not a silent success.
    assert!(matches!(
        library.delete_module(&first),
        Err(LibraryError::UnknownModule(_))
    ));

    // The text can come back: a fresh import of the same file.
    library.import_osis(CONTAINER.as_bytes()).unwrap();
    assert!(!library.chapter(&first, genesis, 1).unwrap().is_empty());
}

#[test]
fn a_rename_changes_the_title_and_survives_a_reimport() {
    let mut library = Library::open_in_memory().unwrap();
    let code = library.import_osis(CONTAINER.as_bytes()).unwrap().code;
    let listed = |library: &Library| {
        let m = library.modules().unwrap().remove(0);
        (m.code, m.title, m.source_title)
    };
    assert_eq!(
        listed(&library),
        (
            code.clone(),
            "Fixtur Deutsch".to_string(),
            "Fixtur Deutsch".to_string()
        )
    );

    library.rename_module(&code, "  Meine Fixtur ").unwrap();
    assert_eq!(
        listed(&library),
        (
            code.clone(),
            "Meine Fixtur".to_string(),
            "Fixtur Deutsch".to_string()
        ),
        "the code is the identity; the source's title is kept beside the reader's"
    );

    // The re-import after a parser change: the reader's name stays.
    library.import_osis(CONTAINER.as_bytes()).unwrap();
    assert_eq!(listed(&library).1, "Meine Fixtur");

    // An empty name gives the source's title back.
    library.rename_module(&code, "   ").unwrap();
    assert_eq!(listed(&library).1, "Fixtur Deutsch");

    assert!(matches!(
        library.rename_module("Nope", "x"),
        Err(LibraryError::UnknownModule(_))
    ));

    // A deleted module takes its chosen name with it: the same file
    // imported later starts under its own title again.
    library.rename_module(&code, "Meine Fixtur").unwrap();
    library.delete_module(&code).unwrap();
    library.import_osis(CONTAINER.as_bytes()).unwrap();
    assert_eq!(listed(&library).1, "Fixtur Deutsch");
}

#[test]
fn a_reading_plan_is_deleted_by_name() {
    let mut library = Library::open_in_memory().unwrap();
    library.import_plan(PLAN).unwrap();
    assert!(library.delete_plan("Jahresplan").unwrap());
    assert!(library.plans().unwrap().is_empty());
    assert!(
        !library.delete_plan("Jahresplan").unwrap(),
        "nothing to delete"
    );
}
