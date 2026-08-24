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

    pub fn from_index(index: usize) -> Option<BookId> {
        (index < CANON.len()).then_some(BookId(index as u8))
    }

    pub fn info(self) -> &'static BookInfo {
        &CANON[self.index()]
    }

    pub fn category(self) -> BookCategory {
        match self.index() {
            0..=4 => BookCategory::Law,
            5..=16 => BookCategory::HistoryOt,
            17..=21 => BookCategory::Wisdom,
            22..=26 => BookCategory::MajorProphets,
            27..=38 => BookCategory::MinorProphets,
            39..=42 => BookCategory::Gospels,
            43 => BookCategory::HistoryNt,
            44..=64 => BookCategory::Epistles,
            _ => BookCategory::Apocalyptic,
        }
    }
}

/// Traditional grouping of the canon, derived from canonical order (the
/// canon is closed per ADR 0010, so position determines category).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BookCategory {
    Law,
    HistoryOt,
    Wisdom,
    MajorProphets,
    MinorProphets,
    Gospels,
    HistoryNt,
    Epistles,
    Apocalyptic,
}

impl BookCategory {
    pub fn index(self) -> u8 {
        self as u8
    }
}

/// Static metadata for one book of the canon.
#[derive(Debug)]
pub struct BookInfo {
    /// OSIS book identifier, e.g. `John`.
    pub osis: &'static str,
    pub english: &'static str,
    pub german: &'static str,
    /// Most concise display abbreviation (German reference scheme).
    pub abbrev: &'static str,
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

/// A reference found inside prose text (byte range half-open).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ScannedReference {
    pub start: u32,
    pub end: u32,
    pub reference: Reference,
}

fn book_of(reference: Reference) -> BookId {
    match reference {
        Reference::Chapter { book, .. } => book,
        Reference::Verse(v) => v.book,
        Reference::VerseRange { start, .. } => start.book,
    }
}

fn build_ref(book: BookId, chapter: u16, verse: Option<u16>, end: Option<u16>) -> Reference {
    match (verse, end) {
        (Some(verse), Some(end_verse)) => Reference::VerseRange {
            start: VerseRef {
                book,
                chapter,
                verse,
            },
            end_verse,
        },
        (Some(verse), None) => Reference::Verse(VerseRef {
            book,
            chapter,
            verse,
        }),
        _ => Reference::Chapter { book, chapter },
    }
}

/// Parse `chapter[,verse[-end]]` at the start of `s`; returns the parts and
/// the exact byte length of the match, which must end at a word boundary.
fn parse_chapter_verse(s: &str) -> Option<(u16, Option<u16>, Option<u16>, usize)> {
    fn digits(s: &str) -> Option<(u16, usize)> {
        let len = s.chars().take_while(|c| c.is_ascii_digit()).count();
        if len == 0 {
            return None;
        }
        let n: u16 = s[..len].parse().ok()?;
        (n > 0).then_some((n, len))
    }
    let (chapter, mut len) = digits(s)?;
    let mut verse = None;
    let mut end = None;
    if s[len..].starts_with(',')
        && let Some((v, vlen)) = digits(&s[len + 1..])
    {
        verse = Some(v);
        len += 1 + vlen;
        let rest = &s[len..];
        let dash = rest.starts_with('-') || rest.starts_with('–');
        if dash {
            let dash_len = rest.chars().next().unwrap().len_utf8();
            if let Some((e, elen)) = digits(&rest[dash_len..])
                && e >= v
            {
                end = Some(e);
                len += dash_len + elen;
            }
        }
    }
    if s[len..].chars().next().is_some_and(|c| c.is_alphanumeric()) {
        return None;
    }
    Some((chapter, verse, end, len))
}

/// Parse a reference at the start of `input`, allowing trailing content.
/// Returns the reference and the bytes consumed; the match must end at a
/// word boundary. In prose only `,` and `:` introduce a verse, so sentence
/// periods are never swallowed.
pub fn parse_reference_prefix(input: &str) -> Option<(Reference, usize)> {
    let total = input.len();
    let mut parser = Parser { rest: input };
    let book = parser.parse_book().ok()?;
    parser.skip_separator();
    let chapter = match parser.parse_number() {
        Ok(Some(n)) => n,
        _ => return None,
    };
    let mut result = Reference::Chapter { book, chapter };
    let mut consumed = total - parser.rest.len();
    if matches!(parser.rest.chars().next(), Some(',' | ':')) {
        parser.rest = parser.rest[1..].trim_start();
        if let Ok(Some(verse)) = parser.parse_number() {
            let start = VerseRef {
                book,
                chapter,
                verse,
            };
            result = Reference::Verse(start);
            let save_range = parser.rest;
            let dash = parser.rest.chars().next();
            if matches!(dash, Some('-' | '–')) {
                parser.rest = parser.rest[dash.unwrap().len_utf8()..].trim_start();
                match parser.parse_number() {
                    Ok(Some(end)) if end >= verse => {
                        result = Reference::VerseRange {
                            start,
                            end_verse: end,
                        };
                    }
                    _ => parser.rest = save_range,
                }
            }
            consumed = total - parser.rest.len();
        }
    }
    while consumed > 0 && input.as_bytes()[consumed - 1].is_ascii_whitespace() {
        consumed -= 1;
    }
    if consumed == 0 {
        return None;
    }
    if input[consumed..]
        .chars()
        .next()
        .is_some_and(|c| c.is_alphanumeric())
    {
        return None;
    }
    Some((result, consumed))
}

/// Find verse references inside prose (footnotes, commentary text):
/// full references ("1. Mose 49,25", "Joh 3,16-18"), context references
/// ("Kap. 7,11" against the context book), and bare chapter,verse pairs
/// chained from the most recently mentioned book.
pub fn scan_references(text: &str, context: Option<BookId>) -> Vec<ScannedReference> {
    let mut out = Vec::new();
    let mut last_book = context;
    let mut prev_alnum = false;
    let mut iter = text.char_indices().peekable();
    while let Some((i, ch)) = iter.next() {
        let boundary = !prev_alnum;
        prev_alnum = ch.is_alphanumeric();
        if !boundary {
            continue;
        }
        let slice = &text[i..];
        let mut matched_end: Option<(usize, Reference)> = None;
        if let Some(book) = last_book
            && (slice.starts_with("Kap.") || slice.starts_with("Kap "))
        {
            let after = &slice[4..];
            let pad = 4 + (after.len() - after.trim_start().len());
            if let Some((c, v, e, len)) = parse_chapter_verse(&slice[pad..]) {
                matched_end = Some((i + pad + len, build_ref(book, c, v, e)));
            }
        }
        if matched_end.is_none()
            && ch.is_alphanumeric()
            && let Some((reference, consumed)) = parse_reference_prefix(slice)
        {
            matched_end = Some((i + consumed, reference));
        }
        if matched_end.is_none()
            && ch.is_ascii_digit()
            && let Some(book) = last_book
            && let Some((c, Some(v), e, len)) = parse_chapter_verse(slice)
        {
            matched_end = Some((i + len, build_ref(book, c, Some(v), e)));
        }
        if let Some((end, reference)) = matched_end {
            last_book = Some(book_of(reference));
            out.push(ScannedReference {
                start: i as u32,
                end: end as u32,
                reference,
            });
            while let Some(&(j, _)) = iter.peek() {
                if j < end {
                    iter.next();
                } else {
                    break;
                }
            }
            prev_alnum = true;
        }
    }
    out
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
            for name in [info.osis, info.english, info.german, info.abbrev] {
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
    ($(($osis:literal, $english:literal, $german:literal, $abbrev:literal, [$($alias:literal),*])),* $(,)?) => {
        [$(BookInfo {
            osis: $osis,
            english: $english,
            german: $german,
            abbrev: $abbrev,
            aliases: &[$($alias),*],
        }),*]
    };
}

static CANON: [BookInfo; 66] = canon_table![
    ("Gen", "Genesis", "1. Mose", "1Mo", ["1mo", "1mos"]),
    ("Exod", "Exodus", "2. Mose", "2Mo", ["2mo", "2mos", "ex"]),
    ("Lev", "Leviticus", "3. Mose", "3Mo", ["3mo", "3mos"]),
    ("Num", "Numbers", "4. Mose", "4Mo", ["4mo", "4mos"]),
    (
        "Deut",
        "Deuteronomy",
        "5. Mose",
        "5Mo",
        ["5mo", "5mos", "dtn", "dt"]
    ),
    ("Josh", "Joshua", "Josua", "Jos", ["jos"]),
    ("Judg", "Judges", "Richter", "Ri", ["ri"]),
    ("Ruth", "Ruth", "Rut", "Rut", []),
    ("1Sam", "1 Samuel", "1. Samuel", "1Sa", ["1sa", "1sm"]),
    ("2Sam", "2 Samuel", "2. Samuel", "2Sa", ["2sa", "2sm"]),
    (
        "1Kgs",
        "1 Kings",
        "1. Könige",
        "1Kö",
        ["1koen", "1kg", "1ki"]
    ),
    (
        "2Kgs",
        "2 Kings",
        "2. Könige",
        "2Kö",
        ["2koen", "2kg", "2ki"]
    ),
    ("1Chr", "1 Chronicles", "1. Chronik", "1Ch", ["1ch"]),
    ("2Chr", "2 Chronicles", "2. Chronik", "2Ch", ["2ch"]),
    ("Ezra", "Ezra", "Esra", "Esr", ["esr"]),
    ("Neh", "Nehemiah", "Nehemia", "Neh", []),
    ("Esth", "Esther", "Ester", "Est", ["est"]),
    ("Job", "Job", "Hiob", "Hi", ["hi"]),
    ("Ps", "Psalms", "Psalmen", "Ps", ["psalm", "pss"]),
    ("Prov", "Proverbs", "Sprüche", "Spr", ["spr", "prv"]),
    (
        "Eccl",
        "Ecclesiastes",
        "Prediger",
        "Pred",
        ["pred", "koh", "kohelet", "ecc", "qoh"]
    ),
    (
        "Song",
        "Song of Solomon",
        "Hoheslied",
        "Hld",
        ["hld", "hohelied", "sos"]
    ),
    ("Isa", "Isaiah", "Jesaja", "Jes", ["jes"]),
    ("Jer", "Jeremiah", "Jeremia", "Jer", []),
    (
        "Lam",
        "Lamentations",
        "Klagelieder",
        "Klgl",
        ["klgl", "kla"]
    ),
    (
        "Ezek",
        "Ezekiel",
        "Hesekiel",
        "Hes",
        ["hes", "ez", "ezechiel"]
    ),
    ("Dan", "Daniel", "Daniel", "Dan", ["dn"]),
    ("Hos", "Hosea", "Hosea", "Hos", []),
    ("Joel", "Joel", "Joel", "Joel", ["jl"]),
    ("Amos", "Amos", "Amos", "Am", ["am"]),
    ("Obad", "Obadiah", "Obadja", "Ob", ["obd", "ob"]),
    ("Jonah", "Jonah", "Jona", "Jona", ["jon"]),
    ("Mic", "Micah", "Micha", "Mi", ["mi"]),
    ("Nah", "Nahum", "Nahum", "Nah", ["nam"]),
    ("Hab", "Habakkuk", "Habakuk", "Hab", []),
    ("Zeph", "Zephaniah", "Zefanja", "Zef", ["zef", "zep"]),
    ("Hag", "Haggai", "Haggai", "Hag", ["hgg"]),
    ("Zech", "Zechariah", "Sacharja", "Sach", ["sach", "zec"]),
    ("Mal", "Malachi", "Maleachi", "Mal", []),
    ("Matt", "Matthew", "Matthäus", "Mt", ["mt", "mat"]),
    ("Mark", "Mark", "Markus", "Mk", ["mk", "mrk"]),
    ("Luke", "Luke", "Lukas", "Lk", ["lk", "luk"]),
    ("John", "John", "Johannes", "Joh", ["joh", "jn"]),
    ("Acts", "Acts", "Apostelgeschichte", "Apg", ["apg", "act"]),
    ("Rom", "Romans", "Römer", "Rö", ["rm"]),
    (
        "1Cor",
        "1 Corinthians",
        "1. Korinther",
        "1Ko",
        ["1kor", "1co"]
    ),
    (
        "2Cor",
        "2 Corinthians",
        "2. Korinther",
        "2Ko",
        ["2kor", "2co"]
    ),
    ("Gal", "Galatians", "Galater", "Gal", []),
    ("Eph", "Ephesians", "Epheser", "Eph", []),
    ("Phil", "Philippians", "Philipper", "Phil", ["php"]),
    ("Col", "Colossians", "Kolosser", "Kol", ["kol"]),
    (
        "1Thess",
        "1 Thessalonians",
        "1. Thessalonicher",
        "1Th",
        ["1thes", "1th"]
    ),
    (
        "2Thess",
        "2 Thessalonians",
        "2. Thessalonicher",
        "2Th",
        ["2thes", "2th"]
    ),
    ("1Tim", "1 Timothy", "1. Timotheus", "1Ti", ["1ti"]),
    ("2Tim", "2 Timothy", "2. Timotheus", "2Ti", ["2ti"]),
    ("Titus", "Titus", "Titus", "Tit", ["tit"]),
    ("Phlm", "Philemon", "Philemon", "Phm", ["phm"]),
    ("Heb", "Hebrews", "Hebräer", "Heb", ["hebr"]),
    ("Jas", "James", "Jakobus", "Jak", ["jak", "jam"]),
    (
        "1Pet",
        "1 Peter",
        "1. Petrus",
        "1Pe",
        ["1petr", "1pt", "1pe"]
    ),
    (
        "2Pet",
        "2 Peter",
        "2. Petrus",
        "2Pe",
        ["2petr", "2pt", "2pe"]
    ),
    ("1John", "1 John", "1. Johannes", "1Jo", ["1joh", "1jn"]),
    ("2John", "2 John", "2. Johannes", "2Jo", ["2joh", "2jn"]),
    ("3John", "3 John", "3. Johannes", "3Jo", ["3joh", "3jn"]),
    ("Jude", "Jude", "Judas", "Jud", ["jud"]),
    (
        "Rev",
        "Revelation",
        "Offenbarung",
        "Off",
        ["offb", "apk", "rv"]
    ),
];
