//! Tier-0 lexical search (ADR 0022): a parity port of bibelsuche's
//! tokenizer and BM25 — same folding, suffix stripping, alias table,
//! and Okapi scoring, pinned against values computed by the Python
//! reference implementation.

use gramma_core::search::{Bm25Index, tokenize};

const DOCS: [&str; 4] = [
    "Und die Schlange war listiger denn alle Tiere auf dem Felde.",
    "Der HERR ist mein Hirte, mir wird nichts mangeln.",
    "Ich bin der gute Hirte und kenne die Meinen.",
    "Am Anfang schuf Gott Himmel und Erde.",
];

#[test]
fn tokenizer_matches_the_reference() {
    assert_eq!(
        tokenize(DOCS[0]),
        [
            "und", "die", "schlang", "war", "listig", "denn", "alle", "tier", "auf", "dem", "feld"
        ]
    );
    assert_eq!(
        tokenize(DOCS[1]),
        [
            "der", "herr", "ist", "mein", "hirt", "mir", "wird", "nichts", "mangel"
        ]
    );
    // Umlaut folding, aliases, and the suffix guard.
    assert_eq!(tokenize("Bäume"), ["baum"]);
    assert_eq!(
        tokenize("Jahwe liebt Geduld"),
        ["herr", "lieb", "langmutig"]
    );
    assert_eq!(tokenize("ist"), ["ist"], "short tokens keep their suffix");
}

#[test]
fn bm25_scores_match_the_reference() {
    let index = Bm25Index::new(DOCS.iter().map(|d| d.to_string()));
    let close = |a: f64, b: f64| (a - b).abs() < 1e-6;
    let scores = index.score("Der Herr ist mein Hirte");
    assert!(close(scores[0], 0.0), "{scores:?}");
    assert!(close(scores[1], 4.487387), "{scores:?}");
    assert!(close(scores[2], 2.079442), "{scores:?}");
    assert!(close(scores[3], 0.0), "{scores:?}");
    let scores = index.score("Schlange");
    assert!(close(scores[0], 1.094521), "{scores:?}");
    assert!(scores[1..].iter().all(|&s| s == 0.0));
    assert!(index.score("Bäume").iter().all(|&s| s == 0.0));
    assert!(index.score("").iter().all(|&s| s == 0.0));
}

#[test]
fn top_hits_rank_and_cut() {
    let index = Bm25Index::new(DOCS.iter().map(|d| d.to_string()));
    let hits = index.top_hits("Der Herr ist mein Hirte", 5);
    assert_eq!(hits.len(), 2, "zero scores are not hits");
    assert_eq!(hits[0].0, 1, "the psalm wording ranks first");
    assert_eq!(hits[1].0, 2);
    assert!(hits[0].1 > hits[1].1);
    assert_eq!(index.top_hits("Hirte", 1).len(), 1);
}
