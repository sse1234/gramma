//! Canonical Bible references: the 66-book canon, alias resolution, and
//! parsing of human-entered references (German and English conventions) into
//! typed values that format as OSIS references.
//!
//! Versification-aware validation (chapter/verse bounds, scheme mapping) is
//! layered on top of this module later; here a reference is syntactically
//! well-formed if book resolves and all numbers are >= 1.

use std::collections::HashMap;
use std::fmt;
use std::str::FromStr;
use std::sync::OnceLock;

/// Index into the canon table; the canonical identity of a book.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct BookId(u8);

impl BookId {
    pub fn index(self) -> usize {
        self.0 as usize
    }

    pub fn info(self) -> &'static BookInfo {
        &CANON[self.index()]
    }
}

/// Static metadata for one book of the canon.
#[derive(Debug)]
pub struct BookInfo {
    /// OSIS book identifier, e.g. `John`.
    pub osis: &'static str,
    pub english: &'static str,
    pub german: &'static str,
    /// Additional accepted abbreviations, pre-normalized (lowercase, no
    /// dots/spaces, umlauts transliterated).
    pub aliases: &'static [&'static str],
}

/// The Protestant 66-book canon in canonical order.
pub fn canon() -> &'static [BookInfo; 66] {
    &CANON
}

/// Resolve a book by its exact OSIS identifier.
pub fn book_by_osis(osis: &str) -> Option<BookId> {
    CANON
        .iter()
        .position(|b| b.osis == osis)
        .map(|i| BookId(i as u8))
}

/// Resolve a book from any accepted name or abbreviation.
pub fn book_by_alias(name: &str) -> Option<BookId> {
    alias_map().get(normalize(name).as_str()).copied()
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct VerseRef {
    pub book: BookId,
    pub chapter: u16,
    pub verse: u16,
}

/// A parsed reference: a whole chapter, a single verse, or a verse range
/// within one chapter.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Reference {
    Chapter { book: BookId, chapter: u16 },
    Verse(VerseRef),
    VerseRange { start: VerseRef, end_verse: u16 },
}

impl fmt::Display for Reference {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match *self {
            Reference::Chapter { book, chapter } => {
                write!(f, "{}.{}", book.info().osis, chapter)
            }
            Reference::Verse(v) => {
                write!(f, "{}.{}.{}", v.book.info().osis, v.chapter, v.verse)
            }
            Reference::VerseRange { start, end_verse } => {
                let osis = start.book.info().osis;
                write!(
                    f,
                    "{}.{}.{}-{}.{}.{}",
                    osis, start.chapter, start.verse, osis, start.chapter, end_verse
                )
            }
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ParseError {
    Empty,
    UnknownBook(String),
    MissingChapter,
    InvalidNumber,
    InvalidRange,
    Trailing(String),
}

impl fmt::Display for ParseError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            ParseError::Empty => write!(f, "empty reference"),
            ParseError::UnknownBook(name) => write!(f, "unknown book: {name:?}"),
            ParseError::MissingChapter => write!(f, "missing chapter number"),
            ParseError::InvalidNumber => write!(f, "chapter/verse numbers must be >= 1"),
            ParseError::InvalidRange => write!(f, "range end must not precede its start"),
            ParseError::Trailing(rest) => write!(f, "unexpected trailing input: {rest:?}"),
        }
    }
}

impl std::error::Error for ParseError {}

impl FromStr for Reference {
    type Err = ParseError;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        Parser::new(s).parse()
    }
}

struct Parser<'a> {
    rest: &'a str,
}

impl<'a> Parser<'a> {
    fn new(input: &'a str) -> Self {
        Parser { rest: input.trim() }
    }

    fn parse(mut self) -> Result<Reference, ParseError> {
        if self.rest.is_empty() {
            return Err(ParseError::Empty);
        }
        let book = self.parse_book()?;
        self.skip_separator();
        let chapter = self.parse_number()?.ok_or(ParseError::MissingChapter)?;
        self.skip_separator();
        let verse = self.parse_number()?;
        let reference = match verse {
            None => Reference::Chapter { book, chapter },
            Some(verse) => {
                let start = VerseRef {
                    book,
                    chapter,
                    verse,
                };
                match self.parse_range_end(start)? {
                    None => Reference::Verse(start),
                    Some(end_verse) if end_verse >= verse => {
                        Reference::VerseRange { start, end_verse }
                    }
                    Some(_) => return Err(ParseError::InvalidRange),
                }
            }
        };
        if !self.rest.is_empty() {
            return Err(ParseError::Trailing(self.rest.to_string()));
        }
        Ok(reference)
    }

    /// Book = optional leading ordinal ("1", "2", "3", with optional dot)
    /// followed by one or more alphabetic words, e.g. "1. Korinther", "2Tim",
    /// "Joh", "Song of Solomon". The longest word sequence that resolves to a
    /// book wins; `self.rest` is left untouched on failure.
    fn parse_book(&mut self) -> Result<BookId, ParseError> {
        let mut ordinal = String::new();
        let mut chars = self.rest.char_indices().peekable();
        if let Some(&(_, c)) = chars.peek()
            && c.is_ascii_digit()
        {
            ordinal.push(c);
            chars.next();
            while let Some(&(_, c)) = chars.peek() {
                if c == '.' || c == ' ' {
                    chars.next();
                } else {
                    break;
                }
            }
        }
        // Collect candidate words with the input offset each one ends at.
        let mut words: Vec<(String, usize)> = Vec::new();
        let mut end = self.rest.len();
        loop {
            let mut word = String::new();
            while let Some(&(i, c)) = chars.peek() {
                if c.is_alphabetic() {
                    word.push(c);
                    end = i + c.len_utf8();
                    chars.next();
                } else {
                    break;
                }
            }
            if word.is_empty() {
                break;
            }
            words.push((word, end));
            if words.len() == 4 {
                break;
            }
            while let Some(&(_, ' ')) = chars.peek() {
                chars.next();
            }
            if !matches!(chars.peek(), Some(&(_, c)) if c.is_alphabetic()) {
                break;
            }
        }
        if words.is_empty() {
            return Err(ParseError::UnknownBook(self.rest.to_string()));
        }
        for k in (1..=words.len()).rev() {
            let mut key = ordinal.clone();
            for (word, _) in &words[..k] {
                key.push_str(word);
            }
            if let Some(book) = book_by_alias(&key) {
                self.rest = self.rest[words[k - 1].1..].trim_start();
                return Ok(book);
            }
        }
        let name_end = words.last().map(|&(_, e)| e).unwrap_or(self.rest.len());
        Err(ParseError::UnknownBook(
            self.rest[..name_end].trim().to_string(),
        ))
    }

    fn skip_separator(&mut self) {
        let mut chars = self.rest.chars();
        if matches!(chars.next(), Some(',' | ':' | '.')) {
            self.rest = chars.as_str().trim_start();
        }
    }

    fn parse_number(&mut self) -> Result<Option<u16>, ParseError> {
        let digits: String = self
            .rest
            .chars()
            .take_while(|c| c.is_ascii_digit())
            .collect();
        if digits.is_empty() {
            return Ok(None);
        }
        self.rest = self.rest[digits.len()..].trim_start();
        let n: u16 = digits.parse().map_err(|_| ParseError::InvalidNumber)?;
        if n == 0 {
            return Err(ParseError::InvalidNumber);
        }
        Ok(Some(n))
    }

    /// Range end is either a bare verse number ("16-18") or, as in OSIS osisRef
    /// ranges, a full reference ("John.3.16-John.3.18") whose book and chapter
    /// must match the start; cross-chapter ranges are not supported yet.
    fn parse_range_end(&mut self, start: VerseRef) -> Result<Option<u16>, ParseError> {
        let mut chars = self.rest.chars();
        if !matches!(chars.next(), Some('-' | '–')) {
            return Ok(None);
        }
        self.rest = chars.as_str().trim_start();
        if let Ok(book) = self.parse_book() {
            self.skip_separator();
            let chapter = self.parse_number()?.ok_or(ParseError::InvalidNumber)?;
            self.skip_separator();
            let verse = self.parse_number()?.ok_or(ParseError::InvalidNumber)?;
            if book != start.book || chapter != start.chapter {
                return Err(ParseError::InvalidRange);
            }
            return Ok(Some(verse));
        }
        self.parse_number()?
            .ok_or(ParseError::InvalidNumber)
            .map(Some)
    }
}

/// Normalize a book name for lookup: lowercase, strip dots and whitespace,
/// transliterate German umlauts.
fn normalize(name: &str) -> String {
    let mut out = String::with_capacity(name.len());
    for c in name.chars() {
        match c {
            '.' | ' ' | '\t' => {}
            'ä' | 'Ä' => out.push_str("ae"),
            'ö' | 'Ö' => out.push_str("oe"),
            'ü' | 'Ü' => out.push_str("ue"),
            'ß' => out.push_str("ss"),
            _ => out.extend(c.to_lowercase()),
        }
    }
    out
}

fn alias_map() -> &'static HashMap<String, BookId> {
    static MAP: OnceLock<HashMap<String, BookId>> = OnceLock::new();
    MAP.get_or_init(|| {
        let mut map = HashMap::new();
        for (i, info) in CANON.iter().enumerate() {
            let id = BookId(i as u8);
            for name in [info.osis, info.english, info.german] {
                map.insert(normalize(name), id);
            }
            for alias in info.aliases {
                map.insert((*alias).to_string(), id);
            }
        }
        map
    })
}

macro_rules! canon_table {
    ($(($osis:literal, $english:literal, $german:literal, [$($alias:literal),*])),* $(,)?) => {
        [$(BookInfo {
            osis: $osis,
            english: $english,
            german: $german,
            aliases: &[$($alias),*],
        }),*]
    };
}

static CANON: [BookInfo; 66] = canon_table![
    ("Gen", "Genesis", "1. Mose", ["1mo", "1mos"]),
    ("Exod", "Exodus", "2. Mose", ["2mo", "2mos", "ex"]),
    ("Lev", "Leviticus", "3. Mose", ["3mo", "3mos"]),
    ("Num", "Numbers", "4. Mose", ["4mo", "4mos"]),
    (
        "Deut",
        "Deuteronomy",
        "5. Mose",
        ["5mo", "5mos", "dtn", "dt"]
    ),
    ("Josh", "Joshua", "Josua", ["jos"]),
    ("Judg", "Judges", "Richter", ["ri"]),
    ("Ruth", "Ruth", "Rut", []),
    ("1Sam", "1 Samuel", "1. Samuel", ["1sa", "1sm"]),
    ("2Sam", "2 Samuel", "2. Samuel", ["2sa", "2sm"]),
    ("1Kgs", "1 Kings", "1. Könige", ["1koen", "1kg", "1ki"]),
    ("2Kgs", "2 Kings", "2. Könige", ["2koen", "2kg", "2ki"]),
    ("1Chr", "1 Chronicles", "1. Chronik", ["1ch"]),
    ("2Chr", "2 Chronicles", "2. Chronik", ["2ch"]),
    ("Ezra", "Ezra", "Esra", ["esr"]),
    ("Neh", "Nehemiah", "Nehemia", []),
    ("Esth", "Esther", "Ester", ["est"]),
    ("Job", "Job", "Hiob", ["hi"]),
    ("Ps", "Psalms", "Psalmen", ["psalm", "pss"]),
    ("Prov", "Proverbs", "Sprüche", ["spr", "prv"]),
    (
        "Eccl",
        "Ecclesiastes",
        "Prediger",
        ["pred", "koh", "kohelet", "ecc", "qoh"]
    ),
    (
        "Song",
        "Song of Solomon",
        "Hoheslied",
        ["hld", "hohelied", "sos"]
    ),
    ("Isa", "Isaiah", "Jesaja", ["jes"]),
    ("Jer", "Jeremiah", "Jeremia", []),
    ("Lam", "Lamentations", "Klagelieder", ["klgl", "kla"]),
    ("Ezek", "Ezekiel", "Hesekiel", ["hes", "ez", "ezechiel"]),
    ("Dan", "Daniel", "Daniel", ["dn"]),
    ("Hos", "Hosea", "Hosea", []),
    ("Joel", "Joel", "Joel", ["jl"]),
    ("Amos", "Amos", "Amos", ["am"]),
    ("Obad", "Obadiah", "Obadja", ["obd", "ob"]),
    ("Jonah", "Jonah", "Jona", ["jon"]),
    ("Mic", "Micah", "Micha", ["mi"]),
    ("Nah", "Nahum", "Nahum", ["nam"]),
    ("Hab", "Habakkuk", "Habakuk", []),
    ("Zeph", "Zephaniah", "Zefanja", ["zef", "zep"]),
    ("Hag", "Haggai", "Haggai", ["hgg"]),
    ("Zech", "Zechariah", "Sacharja", ["sach", "zec"]),
    ("Mal", "Malachi", "Maleachi", []),
    ("Matt", "Matthew", "Matthäus", ["mt", "mat"]),
    ("Mark", "Mark", "Markus", ["mk", "mrk"]),
    ("Luke", "Luke", "Lukas", ["lk", "luk"]),
    ("John", "John", "Johannes", ["joh", "jn"]),
    ("Acts", "Acts", "Apostelgeschichte", ["apg", "act"]),
    ("Rom", "Romans", "Römer", ["rm"]),
    ("1Cor", "1 Corinthians", "1. Korinther", ["1kor", "1co"]),
    ("2Cor", "2 Corinthians", "2. Korinther", ["2kor", "2co"]),
    ("Gal", "Galatians", "Galater", []),
    ("Eph", "Ephesians", "Epheser", []),
    ("Phil", "Philippians", "Philipper", ["php"]),
    ("Col", "Colossians", "Kolosser", ["kol"]),
    (
        "1Thess",
        "1 Thessalonians",
        "1. Thessalonicher",
        ["1thes", "1th"]
    ),
    (
        "2Thess",
        "2 Thessalonians",
        "2. Thessalonicher",
        ["2thes", "2th"]
    ),
    ("1Tim", "1 Timothy", "1. Timotheus", ["1ti"]),
    ("2Tim", "2 Timothy", "2. Timotheus", ["2ti"]),
    ("Titus", "Titus", "Titus", ["tit"]),
    ("Phlm", "Philemon", "Philemon", ["phm"]),
    ("Heb", "Hebrews", "Hebräer", ["hebr"]),
    ("Jas", "James", "Jakobus", ["jak", "jam"]),
    ("1Pet", "1 Peter", "1. Petrus", ["1petr", "1pt", "1pe"]),
    ("2Pet", "2 Peter", "2. Petrus", ["2petr", "2pt", "2pe"]),
    ("1John", "1 John", "1. Johannes", ["1joh", "1jn"]),
    ("2John", "2 John", "2. Johannes", ["2joh", "2jn"]),
    ("3John", "3 John", "3. Johannes", ["3joh", "3jn"]),
    ("Jude", "Jude", "Judas", ["jud"]),
    ("Rev", "Revelation", "Offenbarung", ["offb", "apk", "rv"]),
];
