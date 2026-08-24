#[allow(unused_imports)]
use gramma_core::reference::BookCategory;
use gramma_core::reference::{ParseError, Reference, book_by_osis, canon};

fn parse(s: &str) -> Result<Reference, ParseError> {
    s.parse()
}

fn osis(s: &str) -> String {
    parse(s).unwrap().to_string()
}

#[test]
fn parses_german_verse_reference() {
    assert_eq!(osis("Joh 3,16"), "John.3.16");
}

#[test]
fn parses_english_verse_reference() {
    assert_eq!(osis("John 3:16"), "John.3.16");
}

#[test]
fn parses_osis_form() {
    assert_eq!(osis("John.3.16"), "John.3.16");
}

#[test]
fn parses_numbered_book_with_range() {
    assert_eq!(osis("1 Kor 13:4-7"), "1Cor.13.4-1Cor.13.7");
}

#[test]
fn parses_full_german_numbered_book_name() {
    assert_eq!(osis("1. Korinther 13,4-7"), "1Cor.13.4-1Cor.13.7");
}

#[test]
fn parses_chapter_only_reference() {
    assert_eq!(osis("Ps 23"), "Ps.23");
}

#[test]
fn normalizes_umlauts_and_transliteration() {
    assert_eq!(osis("Matthäus 5,3"), "Matt.5.3");
    assert_eq!(osis("Matthaeus 5,3"), "Matt.5.3");
}

#[test]
fn is_case_insensitive() {
    assert_eq!(osis("joh 3,16"), "John.3.16");
    assert_eq!(osis("JOH 3,16"), "John.3.16");
}

#[test]
fn accepts_en_dash_ranges() {
    assert_eq!(osis("Joh 3,16–18"), "John.3.16-John.3.18");
}

#[test]
fn rejects_unknown_book() {
    assert!(matches!(parse("Foo 3,16"), Err(ParseError::UnknownBook(_))));
}

#[test]
fn rejects_empty_input() {
    assert!(matches!(parse(""), Err(ParseError::Empty)));
    assert!(matches!(parse("   "), Err(ParseError::Empty)));
}

#[test]
fn rejects_book_without_chapter() {
    assert!(matches!(parse("Joh"), Err(ParseError::MissingChapter)));
}

#[test]
fn rejects_trailing_garbage() {
    assert!(matches!(parse("Joh 3,16xyz"), Err(ParseError::Trailing(_))));
}

#[test]
fn rejects_descending_range() {
    assert!(matches!(parse("Joh 3,16-9"), Err(ParseError::InvalidRange)));
}

#[test]
fn rejects_zero_chapter_or_verse() {
    assert!(matches!(parse("Joh 0,16"), Err(ParseError::InvalidNumber)));
    assert!(matches!(parse("Joh 3,0"), Err(ParseError::InvalidNumber)));
}

#[test]
fn canon_has_66_books_resolvable_by_osis_english_and_german() {
    let books = canon();
    assert_eq!(books.len(), 66);
    for info in books {
        for name in [info.osis, info.english, info.german] {
            let input = format!("{name} 1");
            let parsed =
                parse(&input).unwrap_or_else(|e| panic!("could not parse {input:?}: {e:?}"));
            let Reference::Chapter { book, chapter } = parsed else {
                panic!("expected chapter reference for {input:?}");
            };
            assert_eq!(canon()[book.index()].osis, info.osis);
            assert_eq!(chapter, 1);
        }
    }
}

#[test]
fn canon_order_is_protestant_66() {
    let books = canon();
    assert_eq!(books[0].osis, "Gen");
    assert_eq!(books[38].osis, "Mal");
    assert_eq!(books[39].osis, "Matt");
    assert_eq!(books[65].osis, "Rev");
}

#[test]
fn book_lookup_by_osis_id() {
    assert!(book_by_osis("John").is_some());
    assert!(book_by_osis("Nope").is_none());
}

#[test]
fn osis_output_roundtrips_through_parser() {
    for input in ["Joh 3,16", "1 Kor 13:4-7", "Ps 23", "Offb 21,1-4"] {
        let once = osis(input);
        let twice = osis(&once);
        assert_eq!(once, twice, "roundtrip failed for {input:?}");
    }
}

#[test]
fn every_book_has_a_unique_concise_abbreviation() {
    let mut seen = std::collections::HashSet::new();
    for info in canon() {
        assert!(!info.abbrev.is_empty(), "missing abbrev for {}", info.osis);
        assert!(
            info.abbrev.chars().count() <= 4,
            "abbrev too long: {}",
            info.abbrev
        );
        assert!(seen.insert(info.abbrev), "duplicate abbrev {}", info.abbrev);
    }
}

#[test]
fn categories_follow_canonical_order() {
    use gramma_core::reference::BookCategory::*;
    for (osis, expected) in [
        ("Gen", Law),
        ("Deut", Law),
        ("Josh", HistoryOt),
        ("Esth", HistoryOt),
        ("Job", Wisdom),
        ("Song", Wisdom),
        ("Isa", MajorProphets),
        ("Dan", MajorProphets),
        ("Hos", MinorProphets),
        ("Mal", MinorProphets),
        ("Matt", Gospels),
        ("John", Gospels),
        ("Acts", HistoryNt),
        ("Rom", Epistles),
        ("Jude", Epistles),
        ("Rev", Apocalyptic),
    ] {
        assert_eq!(
            book_by_osis(osis).unwrap().category(),
            expected,
            "for {osis}"
        );
    }
}

#[test]
fn concise_display_uses_the_abbreviation_scheme() {
    for (input, expected) in [
        ("Gen.3.1", "1Mo 3,1"),
        ("John.3.16-John.3.18", "Joh 3,16-18"),
        ("Ps.23", "Ps 23"),
    ] {
        let reference: Reference = input.parse().unwrap();
        assert_eq!(reference.display_concise(), expected);
    }
}
