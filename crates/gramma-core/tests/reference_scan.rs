use gramma_core::reference::{book_by_osis, scan_references};

fn scan<'a>(text: &'a str, context: &str) -> Vec<(&'a str, String)> {
    scan_references(text, book_by_osis(context))
        .into_iter()
        .map(|s| {
            (
                &text[s.start as usize..s.end as usize],
                s.reference.to_string(),
            )
        })
        .collect()
}

#[test]
fn finds_full_references_in_prose() {
    let found = scan("vgl. 1. Mose 49,25 und Joh 3,16-18.", "Gen");
    assert_eq!(
        found,
        [
            ("1. Mose 49,25", "Gen.49.25".to_string()),
            ("Joh 3,16-18", "John.3.16-John.3.18".to_string()),
        ]
    );
}

#[test]
fn kap_references_resolve_against_the_context_book() {
    let found = scan("so auch [Kap. 7,11]; vgl. Kap. 19", "Gen");
    assert_eq!(
        found,
        [
            ("Kap. 7,11", "Gen.7.11".to_string()),
            ("Kap. 19", "Gen.19".to_string()),
        ]
    );
}

#[test]
fn bare_chapter_verse_pairs_chain_from_the_last_book() {
    let found = scan(
        "so auch [Kap. 7,11]; [8,2]; [1. Mose 49,25]; [50,3-5]",
        "Exod",
    );
    assert_eq!(
        found,
        [
            ("Kap. 7,11", "Exod.7.11".to_string()),
            ("8,2", "Exod.8.2".to_string()),
            ("1. Mose 49,25", "Gen.49.25".to_string()),
            ("50,3-5", "Gen.50.3-Gen.50.5".to_string()),
        ]
    );
}

#[test]
fn concise_abbreviations_resolve() {
    let found = scan("vgl. Rö 8,1 und Off 21,4", "Gen");
    assert_eq!(
        found,
        [
            ("Rö 8,1", "Rom.8.1".to_string()),
            ("Off 21,4", "Rev.21.4".to_string()),
        ]
    );
}

#[test]
fn ordinary_prose_yields_no_false_positives() {
    assert!(scan("Am Anfang schuf Gott Himmel und Erde.", "Gen").is_empty());
    assert!(scan("Im Jahr 70 wurde der Tempel zerstört.", "Gen").is_empty());
    assert!(scan("Eig. eine rauschende, tiefe Wassermenge", "Gen").is_empty());
}

#[test]
fn without_context_kap_and_bare_pairs_are_ignored() {
    let found = scan_references("Kap. 7,11 und 8,2", None);
    assert!(found.is_empty());
}

#[test]
fn references_inside_words_are_not_matched() {
    assert!(scan("Der Psalter1,2 ist", "Gen").is_empty());
}

/// Dictionary prose (ADR 0019) writes references colon-style:
/// "Mt 24:12", chains "Apg 2:46 20:11", verse lists "Hld 2:4,5,7".
#[test]
fn colon_style_references_scan() {
    let found = scan_references("vgl. Mt 24:12 und Apg 2:46 20:11", None);
    let refs: Vec<String> = found.iter().map(|r| r.reference.to_string()).collect();
    assert_eq!(refs, ["Matt.24.12", "Acts.2.46", "Acts.20.11"]);
}

#[test]
fn colon_verse_lists_do_not_mischain() {
    // "5,7" hangs on the comma of a verse list: it is verses 5 and 7 of
    // the same chapter, never chapter 5 verse 7.
    let found = scan_references("LXX: auch Hld 2:4,5,7 und danach 4,2", None);
    let refs: Vec<String> = found.iter().map(|r| r.reference.to_string()).collect();
    assert_eq!(refs, ["Song.2.4", "Song.4.2"]);
}

#[test]
fn colon_ranges_scan() {
    let found = scan_references("siehe Röm 5:8-10; 1Kor 4:21", None);
    let refs: Vec<String> = found.iter().map(|r| r.reference.to_string()).collect();
    assert_eq!(refs, ["Rom.5.8-Rom.5.10", "1Cor.4.21"]);
}
