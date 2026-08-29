//! Imported reading plans: JSON stored verbatim in the library after
//! schema validation, listed by name for the tools menu.

use gramma_core::library::Library;

const PLAN: &str = r#"{"name":"Jahresplan","source":"366 Tage durch die Bibel","days":[[{"label":"1. Mose 1-2","osis":"Gen.1"},{"label":"Psalm 1","osis":"Ps.1"}],[{"label":"Matthäus 1","osis":"Matt.1"}]]}"#;

#[test]
fn plans_import_replace_and_list() {
    let mut library = Library::open_in_memory().unwrap();
    let info = library.import_plan(PLAN).unwrap();
    assert_eq!(info.name, "Jahresplan");
    assert_eq!(info.source, "366 Tage durch die Bibel");
    assert_eq!(info.days, 2);

    let plans = library.plans().unwrap();
    assert_eq!(plans.len(), 1);
    assert_eq!(plans[0].name, "Jahresplan");
    assert_eq!(plans[0].json, PLAN, "the JSON is stored verbatim");

    // Re-import replaces, never duplicates.
    library.import_plan(PLAN).unwrap();
    assert_eq!(library.plans().unwrap().len(), 1);

    // A second plan; the listing is ordered by name.
    let other = r#"{"name":"Advent","days":[[{"label":"Joh 1","osis":"John.1"}]]}"#;
    let info = library.import_plan(other).unwrap();
    assert_eq!((info.name.as_str(), info.days), ("Advent", 1));
    let names: Vec<String> = library
        .plans()
        .unwrap()
        .into_iter()
        .map(|p| p.name)
        .collect();
    assert_eq!(names, ["Advent", "Jahresplan"]);
}

#[test]
fn invalid_plans_are_rejected() {
    let mut library = Library::open_in_memory().unwrap();
    for bad in [
        "not json at all",
        r#"{"days":[[{"label":"a","osis":"Gen.1"}]]}"#, // no name
        r#"{"name":"","days":[[{"label":"a","osis":"Gen.1"}]]}"#, // empty name
        r#"{"name":"x"}"#,                              // no days
        r#"{"name":"x","days":[]}"#,                    // empty days
        r#"{"name":"x","days":[[{"label":"a"}]]}"#,     // ref without osis
        r#"{"name":"x","days":[[{"osis":"Gen.1"}]]}"#,  // ref without label
        r#"{"name":"x","days":["flat"]}"#,              // day not a list
    ] {
        assert!(library.import_plan(bad).is_err(), "accepted: {bad}");
    }
    assert!(library.plans().unwrap().is_empty());
}
