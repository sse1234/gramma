//! Tier-0 lexical search (ADR 0022): tokenizer and BM25 index, a parity
//! port of bibelsuche's Python implementation (itself mirrored in its
//! Swift port). Folding: NFKD → ASCII → lowercase → `[a-z0-9]` tokens;
//! then the shared alias table, falling back to a guarded suffix strip.
//! Scoring: Okapi BM25 with k1 = 1.5, b = 0.75 and the same IDF.

use std::collections::HashMap;

use unicode_normalization::UnicodeNormalization;

/// The alias table (verbatim from bibelsuche; keys are post-fold forms).
const TOKEN_ALIASES: &[(&str, &str)] = &[
    ("beladen", "belastet"),
    ("beschwert", "belastet"),
    ("erholt", "ruhe"),
    ("erholen", "ruhe"),
    ("erquicklich", "ruhe"),
    ("erquicken", "ruhe"),
    ("fehlt", "mangel"),
    ("fehlen", "mangel"),
    ("friedfertig", "frieden"),
    ("friedfertige", "frieden"),
    ("friedfertigen", "frieden"),
    ("geplagt", "belastet"),
    ("geduld", "langmutig"),
    ("geduldig", "langmutig"),
    ("geliebt", "lieb"),
    ("gezeigt", "lieb"),
    ("glucklich", "selig"),
    ("guetig", "freundlich"),
    ("hirte", "hirt"),
    ("jahwe", "herr"),
    ("lasten", "last"),
    ("liebe", "lieb"),
    ("liebt", "lieb"),
    ("mangelt", "mangel"),
    ("muehselig", "belastet"),
    ("sorge", "sorg"),
    ("sorgen", "sorg"),
    ("sorget", "sorg"),
    ("sorgt", "sorg"),
    ("zuversichtlich", "zuversich"),
];

const SUFFIXES: &[&str] = &["ern", "em", "en", "er", "es", "e", "n", "t"];

fn alias(token: &str) -> Option<&'static str> {
    TOKEN_ALIASES
        .iter()
        .find(|(from, _)| *from == token)
        .map(|(_, to)| *to)
}

fn strip_common_suffixes(token: &str) -> &str {
    for suffix in SUFFIXES {
        if token.len() <= suffix.len() + 3 {
            continue;
        }
        if let Some(stripped) = token.strip_suffix(suffix) {
            return stripped;
        }
    }
    token
}

fn canonicalize(token: &str) -> String {
    if let Some(target) = alias(token) {
        return target.to_string();
    }
    let stripped = strip_common_suffixes(token);
    if let Some(target) = alias(stripped) {
        return target.to_string();
    }
    stripped.to_string()
}

/// Tokenize prose exactly as the reference: NFKD-fold to ASCII,
/// lowercase, split on anything outside `[a-z0-9]`, canonicalize.
pub fn tokenize(text: &str) -> Vec<String> {
    let folded: String = text
        .nfkd()
        .filter(|c| c.is_ascii())
        .collect::<String>()
        .to_lowercase();
    folded
        .split(|c: char| !c.is_ascii_lowercase() && !c.is_ascii_digit())
        .filter(|t| !t.is_empty())
        .map(canonicalize)
        .collect()
}

/// Okapi BM25 over a fixed document list, matching the reference
/// parameters and IDF formula.
pub struct Bm25Index {
    term_frequencies: Vec<HashMap<String, u32>>,
    document_lengths: Vec<u32>,
    average_document_length: f64,
    document_frequencies: HashMap<String, u32>,
}

const K1: f64 = 1.5;
const B: f64 = 0.75;

impl Bm25Index {
    pub fn new(documents: impl Iterator<Item = String>) -> Self {
        let mut term_frequencies: Vec<HashMap<String, u32>> = Vec::new();
        for document in documents {
            let mut counts: HashMap<String, u32> = HashMap::new();
            for token in tokenize(&document) {
                *counts.entry(token).or_insert(0) += 1;
            }
            term_frequencies.push(counts);
        }
        let document_lengths: Vec<u32> = term_frequencies
            .iter()
            .map(|counts| counts.values().sum())
            .collect();
        let average_document_length = if document_lengths.is_empty() {
            0.0
        } else {
            document_lengths.iter().sum::<u32>() as f64 / document_lengths.len() as f64
        };
        let mut document_frequencies: HashMap<String, u32> = HashMap::new();
        for counts in &term_frequencies {
            for term in counts.keys() {
                *document_frequencies.entry(term.clone()).or_insert(0) += 1;
            }
        }
        Bm25Index {
            term_frequencies,
            document_lengths,
            average_document_length,
            document_frequencies,
        }
    }

    pub fn len(&self) -> usize {
        self.term_frequencies.len()
    }

    pub fn is_empty(&self) -> bool {
        self.term_frequencies.is_empty()
    }

    pub fn score(&self, query: &str) -> Vec<f64> {
        let corpus_size = self.term_frequencies.len();
        let mut scores = vec![0.0; corpus_size];
        for term in tokenize(query) {
            let Some(&document_frequency) = self.document_frequencies.get(&term) else {
                continue;
            };
            let idf = (1.0
                + (corpus_size as f64 - document_frequency as f64 + 0.5)
                    / (document_frequency as f64 + 0.5))
                .ln();
            for (index, counts) in self.term_frequencies.iter().enumerate() {
                let term_frequency = *counts.get(&term).unwrap_or(&0) as f64;
                if term_frequency == 0.0 {
                    continue;
                }
                let document_length = self.document_lengths[index] as f64;
                let average = if self.average_document_length == 0.0 {
                    1.0
                } else {
                    self.average_document_length
                };
                let denominator = term_frequency + K1 * (1.0 - B + B * document_length / average);
                scores[index] += idf * term_frequency * (K1 + 1.0) / denominator;
            }
        }
        scores
    }

    /// The highest-scoring documents (score > 0), best first, at most
    /// `limit` — as (document index, score).
    pub fn top_hits(&self, query: &str, limit: usize) -> Vec<(usize, f64)> {
        let mut hits: Vec<(usize, f64)> = self
            .score(query)
            .into_iter()
            .enumerate()
            .filter(|&(_, s)| s > 0.0)
            .collect();
        hits.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal));
        hits.truncate(limit);
        hits
    }
}
