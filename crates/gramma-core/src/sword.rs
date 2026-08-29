//! SWORD zCom commentary reading (ADR 0017): a clean-room implementation
//! of the publicly documented CrossWire container format.
//!
//! A zCom module keeps, per testament, three files: `*.bzs` (block index:
//! offset, compressed size, uncompressed size — 12 bytes little-endian),
//! `*.bzv` (verse index: block number, offset in the uncompressed block,
//! entry size — 10 bytes little-endian), and `*.bzz` (the zlib-compressed
//! blocks). Verse slots follow the module's versification; a pericope
//! entry is *linked* by pointing several consecutive slots at the same
//! bytes. We walk the verse index in order and de-duplicate, so no canon
//! table is needed — each fragment names its own verse range in its
//! `annotateRef`. Fragments without one (book/chapter milestones, importer
//! notes) are structural and skipped, as are non-canonical books (ADR
//! 0010).

use std::collections::HashMap;
use std::io::Read;
use std::path::Path;

use flate2::read::ZlibDecoder;
use quick_xml::Reader;
use quick_xml::events::{BytesStart, Event};

use crate::reference::{BookId, book_by_osis};

#[derive(Debug, thiserror::Error)]
pub enum SwordError {
    #[error("io error: {0}")]
    Io(#[from] std::io::Error),
    #[error("zip error: {0}")]
    Zip(#[from] zip::result::ZipError),
    #[error("XML error: {0}")]
    Xml(#[from] quick_xml::Error),
    #[error("no module configuration (mods.d/*.conf) in package")]
    NoConf,
    #[error("unsupported module: {0}")]
    Unsupported(String),
    #[error("module data is not valid UTF-8")]
    Encoding,
    #[error("corrupt module data: {0}")]
    Corrupt(String),
    #[error("module contains no commentary entries")]
    Empty,
}

/// One testament's raw data files.
pub struct Testament {
    pub bzs: Vec<u8>,
    pub bzv: Vec<u8>,
    pub bzz: Vec<u8>,
}

pub struct SwordCommentary {
    pub code: String,
    pub title: String,
    pub language: String,
    pub entries: Vec<CommentaryEntry>,
}

/// A SWORD package's content, by module driver.
pub enum SwordModule {
    Commentary(SwordCommentary),
    Dictionary(SwordDictionary),
    Bible(SwordBible),
    Book(SwordBook),
}

/// A lexicon/dictionary (zLD, ADR 0019): keyed entries in sort order.
/// With `Feature=DailyDevotion` (ADR 0021) the entries are the sections
/// of daily readings, sorted by `(month·100+day)·10 + section`.
pub struct SwordDictionary {
    pub code: String,
    pub title: String,
    pub language: String,
    pub devotional: bool,
    pub entries: Vec<DictEntry>,
}

pub struct DictEntry {
    /// Numeric ordering key (the Strong's number for Strong's lexica).
    pub sort: u32,
    /// The module's own key string ("00026").
    pub key: String,
    /// The headword (the Greek word for Strong's).
    pub headword: String,
    /// Transliteration / pronunciation.
    pub pron: String,
    /// Normalized body; paragraphs are separated by "\n\n".
    pub text: String,
}

/// One commentary section, covering a verse range within one chapter.
pub struct CommentaryEntry {
    pub book: BookId,
    pub chapter: u16,
    pub verse_start: u16,
    pub verse_end: u16,
    /// The section's leading title, when it has one.
    pub heading: Option<String>,
    /// Normalized text; paragraphs are separated by "\n\n".
    pub text: String,
    pub refs: Vec<CommentRef>,
}

/// A verse reference inside entry text, as a byte range plus its OSIS id.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CommentRef {
    pub start: u32,
    pub end: u32,
    pub osis: String,
}

struct Conf {
    code: String,
    title: String,
    language: String,
    data_path: String,
    mod_drv: String,
    compress: String,
    source: String,
    encoding: String,
    features: Vec<String>,
}

fn parse_conf(conf: &str) -> Result<Conf, SwordError> {
    let mut code = None;
    let mut features: Vec<String> = Vec::new();
    let mut values: HashMap<&str, &str> = HashMap::new();
    for line in conf.lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        if let Some(name) = line.strip_prefix('[').and_then(|l| l.strip_suffix(']')) {
            code.get_or_insert(name.to_string());
        } else if let Some((key, value)) = line.split_once('=') {
            if key.trim() == "Feature" {
                features.push(value.trim().to_string());
            }
            values.entry(key.trim()).or_insert(value.trim());
        }
    }
    let code = code.ok_or(SwordError::NoConf)?;
    let get = |key: &str| values.get(key).copied().unwrap_or("").to_string();
    Ok(Conf {
        mod_drv: get("ModDrv"),
        compress: get("CompressType"),
        source: get("SourceType"),
        encoding: get("Encoding"),
        title: values
            .get("Description")
            .map(|s| s.to_string())
            .unwrap_or_else(|| code.clone()),
        language: values.get("Lang").unwrap_or(&"en").to_string(),
        data_path: values
            .get("DataPath")
            .map(|s| s.trim_start_matches("./").trim_end_matches('/'))
            .unwrap_or("")
            .to_string(),
        features,
        code,
    })
}

/// Only ZIP-compressed, UTF-8 modules with the expected markup are
/// accepted; anything else fails clearly instead of importing wrongly.
fn ensure(conf: &Conf, mod_drv: &str, source: &str) -> Result<(), SwordError> {
    for (name, got, want) in [
        ("ModDrv", &conf.mod_drv, mod_drv),
        ("CompressType", &conf.compress, "ZIP"),
        ("SourceType", &conf.source, source),
        ("Encoding", &conf.encoding, "UTF-8"),
    ] {
        if !got.eq_ignore_ascii_case(want) {
            return Err(SwordError::Unsupported(format!("{name}={got}")));
        }
    }
    Ok(())
}

/// Read a SWORD distribution package (the CrossWire raw zip form).
pub fn read_sword_zip(path: &Path) -> Result<SwordModule, SwordError> {
    let file = std::fs::File::open(path)?;
    let mut zip = zip::ZipArchive::new(file)?;
    let conf_name = (0..zip.len())
        .filter_map(|i| zip.by_index(i).ok().map(|f| f.name().to_string()))
        .find(|n| n.starts_with("mods.d/") && n.ends_with(".conf"))
        .ok_or(SwordError::NoConf)?;
    let mut conf_text = String::new();
    zip.by_name(&conf_name)?.read_to_string(&mut conf_text)?;
    let conf = parse_conf(&conf_text)?;

    let mut read = |name: String| -> Result<Option<Vec<u8>>, SwordError> {
        match zip.by_name(&name) {
            Ok(mut f) => {
                let mut data = Vec::new();
                f.read_to_end(&mut data)?;
                Ok(Some(data))
            }
            Err(zip::result::ZipError::FileNotFound) => Ok(None),
            Err(e) => Err(e.into()),
        }
    };
    if conf.mod_drv.eq_ignore_ascii_case("RawGenBook") {
        // Raw (uncompressed) driver: no CompressType to check.
        for (name, got, want) in [
            ("SourceType", &conf.source, "OSIS"),
            ("Encoding", &conf.encoding, "UTF-8"),
        ] {
            if !got.eq_ignore_ascii_case(want) {
                return Err(SwordError::Unsupported(format!("{name}={got}")));
            }
        }
        let mut file = |ext: &str| -> Result<Vec<u8>, SwordError> {
            read(format!("{}.{ext}", conf.data_path))?
                .ok_or_else(|| SwordError::Corrupt(format!("missing {ext} file")))
        };
        let (idx, dat, bdt) = (file("idx")?, file("dat")?, file("bdt")?);
        return Ok(SwordModule::Book(parse_genbook_parsed(
            conf, &idx, &dat, &bdt,
        )?));
    }
    if conf.mod_drv.eq_ignore_ascii_case("zLD") {
        ensure_zld(&conf)?;
        let mut file = |ext: &str| -> Result<Vec<u8>, SwordError> {
            read(format!("{}.{ext}", conf.data_path))?
                .ok_or_else(|| SwordError::Corrupt(format!("missing {ext} file")))
        };
        let (idx, dat, zdx, zdt) = (file("idx")?, file("dat")?, file("zdx")?, file("zdt")?);
        return Ok(SwordModule::Dictionary(parse_zld_parsed(
            conf, &idx, &dat, &zdx, &zdt,
        )?));
    }
    let is_text = conf.mod_drv.eq_ignore_ascii_case("zText");
    ensure(&conf, if is_text { "zText" } else { "zCom" }, "OSIS")?;
    let mut testaments = Vec::new();
    for t in ["ot", "nt"] {
        let base = format!("{}/{t}", conf.data_path);
        let (Some(bzs), Some(bzv), Some(bzz)) = (
            read(format!("{base}.bzs"))?,
            read(format!("{base}.bzv"))?,
            read(format!("{base}.bzz"))?,
        ) else {
            continue;
        };
        testaments.push(Testament { bzs, bzv, bzz });
    }
    if is_text {
        return Ok(SwordModule::Bible(parse_ztext_parsed(conf, &testaments)?));
    }
    Ok(SwordModule::Commentary(parse_zcom_parsed(
        conf,
        &testaments,
    )?))
}

pub fn read_zcom_zip(path: &Path) -> Result<SwordCommentary, SwordError> {
    match read_sword_zip(path)? {
        SwordModule::Commentary(c) => Ok(c),
        _ => Err(SwordError::Unsupported("expected a commentary".into())),
    }
}

/// Parse a zCom commentary from its configuration and data files.
pub fn parse_zcom(conf: &str, testaments: &[Testament]) -> Result<SwordCommentary, SwordError> {
    let conf = parse_conf(conf)?;
    ensure(&conf, "zCom", "OSIS")?;
    parse_zcom_parsed(conf, testaments)
}

fn parse_zcom_parsed(conf: Conf, testaments: &[Testament]) -> Result<SwordCommentary, SwordError> {
    let mut entries = Vec::new();
    for t in testaments {
        walk_testament(t, &mut entries)?;
    }
    if entries.is_empty() {
        return Err(SwordError::Empty);
    }
    Ok(SwordCommentary {
        code: conf.code,
        title: conf.title,
        language: conf.language,
        entries,
    })
}

fn walk_testament(t: &Testament, entries: &mut Vec<CommentaryEntry>) -> Result<(), SwordError> {
    let blocks: Vec<(u32, u32)> = t
        .bzs
        .as_chunks::<12>()
        .0
        .iter()
        .map(|c| {
            (
                u32::from_le_bytes(c[0..4].try_into().unwrap()),
                u32::from_le_bytes(c[4..8].try_into().unwrap()),
            )
        })
        .collect();
    let mut cache: HashMap<u32, Vec<u8>> = HashMap::new();
    let mut seen: std::collections::HashSet<(u32, u32, u16)> = Default::default();
    for slot in t.bzv.as_chunks::<10>().0 {
        let block = u32::from_le_bytes(slot[0..4].try_into().unwrap());
        let offset = u32::from_le_bytes(slot[4..8].try_into().unwrap());
        let size = u16::from_le_bytes(slot[8..10].try_into().unwrap());
        if size == 0 || !seen.insert((block, offset, size)) {
            continue;
        }
        let data = match cache.entry(block) {
            std::collections::hash_map::Entry::Occupied(e) => e.into_mut(),
            std::collections::hash_map::Entry::Vacant(e) => {
                let (start, compressed) = *blocks
                    .get(block as usize)
                    .ok_or_else(|| SwordError::Corrupt(format!("block {block}")))?;
                let raw = t
                    .bzz
                    .get(start as usize..(start + compressed) as usize)
                    .ok_or_else(|| SwordError::Corrupt(format!("block {block} bounds")))?;
                let mut out = Vec::new();
                ZlibDecoder::new(raw).read_to_end(&mut out)?;
                e.insert(out)
            }
        };
        let bytes = data
            .get(offset as usize..(offset as usize + size as usize))
            .ok_or_else(|| SwordError::Corrupt(format!("entry bounds in block {block}")))?;
        let fragment = std::str::from_utf8(bytes).map_err(|_| SwordError::Encoding)?;
        if let Some(entry) = parse_fragment(fragment)? {
            entries.push(entry);
        }
    }
    Ok(())
}

/// The verse range of an `annotateRef` like `Gen.1.3-Gen.1.5` or `Gen.1.3`.
/// Ranges never cross a chapter; a malformed end falls back to the start.
fn parse_annotate_ref(value: &str) -> Option<(BookId, u16, u16, u16)> {
    fn part(s: &str) -> Option<(BookId, u16, u16)> {
        let mut p = s.split('.');
        let book = book_by_osis(p.next()?)?;
        Some((book, p.next()?.parse().ok()?, p.next()?.parse().ok()?))
    }
    let (first, second) = match value.split_once('-') {
        Some((a, b)) => (a, Some(b)),
        None => (value, None),
    };
    let (book, chapter, verse) = part(first.trim())?;
    let end = second
        .and_then(part)
        .filter(|&(b, c, _)| b == book && c == chapter)
        .map(|(_, _, v)| v)
        .unwrap_or(verse)
        .max(verse);
    Some((book, chapter, verse, end))
}

fn attr(e: &BytesStart, name: &[u8]) -> Option<String> {
    e.attributes()
        .flatten()
        .find(|a| a.key.as_ref() == name)
        .and_then(|a| a.normalized_value(quick_xml::XmlVersion::Implicit1_0).ok())
        .map(|v| v.into_owned())
}

/// Accumulates whitespace-normalized text, deferring separators until the
/// next word so reference byte ranges never cover surrounding whitespace.
struct TextBuilder {
    out: String,
    space: bool,
    r#break: bool,
}

impl TextBuilder {
    fn new() -> Self {
        TextBuilder {
            out: String::new(),
            space: false,
            r#break: false,
        }
    }

    fn flush_separator(&mut self) {
        if self.out.is_empty() {
            // Leading separators would only indent the entry.
        } else if self.r#break {
            self.out.push_str("\n\n");
        } else if self.space {
            self.out.push(' ');
        }
        self.space = false;
        self.r#break = false;
    }

    fn push_text(&mut self, s: &str) {
        let mut rest = s;
        while !rest.is_empty() {
            let trimmed = rest.trim_start();
            if trimmed.len() < rest.len() {
                self.space = true;
            }
            let Some(end) = trimmed
                .find(char::is_whitespace)
                .or_else(|| (!trimmed.is_empty()).then_some(trimmed.len()))
            else {
                break;
            };
            self.flush_separator();
            self.out.push_str(&trimmed[..end]);
            rest = &trimmed[end..];
        }
    }

    fn paragraph_break(&mut self) {
        self.r#break = true;
    }
}

/// A reader for one container entry: SWORD entries are fragments cut
/// out of a whole-document stream, so element balance stops at entry
/// boundaries — GerMenge's psalm superscriptions, for one, open their
/// `title` in the superscription verse and close it in the next.
/// Mismatched and unmatched end tags must not fail the parse.
fn fragment_reader(fragment: &str) -> Reader<&[u8]> {
    let mut reader = Reader::from_str(fragment);
    let config = reader.config_mut();
    config.check_end_names = false;
    config.allow_unmatched_ends = true;
    reader
}

/// Parse one OSIS fragment into an entry; structural fragments (no
/// `annotateRef`, or a non-canonical book) yield `None`.
fn parse_fragment(fragment: &str) -> Result<Option<CommentaryEntry>, SwordError> {
    let mut reader = fragment_reader(fragment);
    let mut range: Option<(BookId, u16, u16, u16)> = None;
    let mut annotated = false;
    let mut heading: Option<String> = None;
    let mut heading_capture = false;
    let mut heading_text = String::new();
    let mut text = TextBuilder::new();
    let mut refs: Vec<CommentRef> = Vec::new();
    let mut ref_start: Option<(usize, String)> = None;

    loop {
        let event = reader.read_event()?;
        match &event {
            Event::Start(e) | Event::Empty(e) => match e.local_name().as_ref() {
                b"div" => {
                    if let Some(value) = attr(e, b"annotateRef") {
                        annotated = true;
                        if range.is_none() {
                            range = parse_annotate_ref(&value);
                        }
                    }
                    if attr(e, b"type").as_deref() == Some("x-p") {
                        text.paragraph_break();
                    }
                }
                b"title" => {
                    if heading.is_none() && text.out.is_empty() {
                        heading_capture = true;
                        heading_text.clear();
                    } else {
                        // Later titles become their own paragraph.
                        text.paragraph_break();
                    }
                }
                b"reference" => {
                    if let Some(osis) = attr(e, b"osisRef") {
                        text.flush_separator();
                        // A work prefix ("KJV:Gen.1.1") is not part of the id.
                        let osis = osis.rsplit(':').next().unwrap_or(&osis).to_string();
                        ref_start = Some((text.out.len(), osis));
                    }
                }
                b"lb" => text.push_text(" "),
                _ => {}
            },
            Event::End(e) => match e.local_name().as_ref() {
                b"title" => {
                    if heading_capture {
                        heading_capture = false;
                        let t = heading_text
                            .split_whitespace()
                            .collect::<Vec<_>>()
                            .join(" ");
                        if !t.is_empty() {
                            heading = Some(t);
                        }
                    } else {
                        text.paragraph_break();
                    }
                }
                b"reference" => {
                    if let Some((start, osis)) = ref_start.take()
                        && text.out.len() > start
                    {
                        refs.push(CommentRef {
                            start: start as u32,
                            end: text.out.len() as u32,
                            osis,
                        });
                    }
                }
                _ => {}
            },
            Event::Text(t) => {
                let content = t
                    .xml_content(quick_xml::XmlVersion::Implicit1_0)
                    .map_err(quick_xml::Error::from)?;
                if heading_capture {
                    heading_text.push_str(&content);
                } else {
                    text.push_text(&content);
                }
            }
            Event::Eof => break,
            _ => {}
        }
    }

    if !annotated {
        return Ok(None); // structural: book/chapter milestone, importer note
    }
    let Some((book, chapter, verse_start, verse_end)) = range else {
        return Ok(None); // non-canonical book (ADR 0010) or unparsable range
    };
    if text.out.is_empty() && heading.is_none() {
        return Ok(None);
    }
    Ok(Some(CommentaryEntry {
        book,
        chapter,
        verse_start,
        verse_end,
        heading,
        text: text.out,
        refs,
    }))
}

/// Parse a zLD dictionary from its configuration and four data files
/// (ADR 0019). `idx`/`dat` map keys to a block number and entry index;
/// `zdx`/`zdt` hold the zlib blocks, each prefixed by an entry count and
/// (offset, size) pairs into the decompressed block.
pub fn parse_zld(
    conf: &str,
    idx: &[u8],
    dat: &[u8],
    zdx: &[u8],
    zdt: &[u8],
) -> Result<SwordDictionary, SwordError> {
    let conf = parse_conf(conf)?;
    ensure_zld(&conf)?;
    parse_zld_parsed(conf, idx, dat, zdx, zdt)
}

/// zLD accepts TEI lexica (ADR 0019) and OSIS daily devotionals
/// (ADR 0021).
fn ensure_zld(conf: &Conf) -> Result<(), SwordError> {
    if conf.source.eq_ignore_ascii_case("OSIS") {
        ensure(conf, "zLD", "OSIS")
    } else {
        ensure(conf, "zLD", "TEI")
    }
}

fn parse_zld_parsed(
    conf: Conf,
    idx: &[u8],
    dat: &[u8],
    zdx: &[u8],
    zdt: &[u8],
) -> Result<SwordDictionary, SwordError> {
    let blocks: Vec<(u32, u32)> = zdx
        .as_chunks::<8>()
        .0
        .iter()
        .map(|c| {
            (
                u32::from_le_bytes(c[0..4].try_into().unwrap()),
                u32::from_le_bytes(c[4..8].try_into().unwrap()),
            )
        })
        .collect();
    let devotional = conf
        .features
        .iter()
        .any(|f| f.eq_ignore_ascii_case("DailyDevotion"))
        || conf.source.eq_ignore_ascii_case("OSIS");
    let mut cache: HashMap<u32, Vec<u8>> = HashMap::new();
    let mut entries = Vec::new();
    for (i, record) in idx.as_chunks::<8>().0.iter().enumerate() {
        let off = u32::from_le_bytes(record[0..4].try_into().unwrap()) as usize;
        let size = u32::from_le_bytes(record[4..8].try_into().unwrap()) as usize;
        let slice = dat
            .get(off..off + size)
            .ok_or_else(|| SwordError::Corrupt("key record bounds".into()))?;
        let split = slice
            .iter()
            .position(|&b| b == b'\r' || b == b'\n')
            .ok_or_else(|| SwordError::Corrupt("key record".into()))?;
        let key = std::str::from_utf8(&slice[..split])
            .map_err(|_| SwordError::Encoding)?
            .trim()
            .to_string();
        // Exactly one line break separates key and binary tail — the
        // tail's block/entry numbers may themselves contain 0x0A/0x0D.
        let data_start = if slice[split..].starts_with(b"\r\n") {
            split + 2
        } else {
            split + 1
        };
        let tail = slice
            .get(data_start..data_start + 8)
            .ok_or_else(|| SwordError::Corrupt("key record tail".into()))?;
        let block = u32::from_le_bytes(tail[0..4].try_into().unwrap());
        let entry_no = u32::from_le_bytes(tail[4..8].try_into().unwrap()) as usize;
        let data = match cache.entry(block) {
            std::collections::hash_map::Entry::Occupied(e) => e.into_mut(),
            std::collections::hash_map::Entry::Vacant(e) => {
                let (start, compressed) = *blocks
                    .get(block as usize)
                    .ok_or_else(|| SwordError::Corrupt(format!("block {block}")))?;
                let raw = zdt
                    .get(start as usize..(start + compressed) as usize)
                    .ok_or_else(|| SwordError::Corrupt(format!("block {block} bounds")))?;
                let mut out = Vec::new();
                ZlibDecoder::new(raw).read_to_end(&mut out)?;
                e.insert(out)
            }
        };
        let count = u32::from_le_bytes(
            data.get(0..4)
                .ok_or_else(|| SwordError::Corrupt("block header".into()))?
                .try_into()
                .unwrap(),
        ) as usize;
        if entry_no >= count {
            return Err(SwordError::Corrupt(format!("entry {entry_no} of {count}")));
        }
        let pair = data
            .get(4 + entry_no * 8..12 + entry_no * 8)
            .ok_or_else(|| SwordError::Corrupt("entry pair".into()))?;
        let eoff = u32::from_le_bytes(pair[0..4].try_into().unwrap()) as usize;
        let esize = u32::from_le_bytes(pair[4..8].try_into().unwrap()) as usize;
        let fragment = std::str::from_utf8(
            data.get(eoff..eoff + esize)
                .ok_or_else(|| SwordError::Corrupt("entry bounds".into()))?,
        )
        .map_err(|_| SwordError::Encoding)?;
        if devotional {
            entries.extend(parse_devotional_entry(&key, fragment)?);
        } else {
            let sort = key.parse::<u32>().ok().unwrap_or(i as u32 + 1);
            if let Some(entry) = parse_tei_entry(sort, &key, fragment)? {
                entries.push(entry);
            }
        }
    }
    entries.sort_by_key(|e| e.sort);
    if entries.is_empty() {
        return Err(SwordError::Empty);
    }
    Ok(SwordDictionary {
        code: conf.code,
        title: conf.title,
        language: conf.language,
        devotional,
        entries,
    })
}

/// One TEI `entryFree` fragment: `orth` is the headword, `pron` the
/// transliteration, `def` the body with `<lb/>` as paragraph breaks.
fn parse_tei_entry(sort: u32, key: &str, fragment: &str) -> Result<Option<DictEntry>, SwordError> {
    let mut reader = fragment_reader(fragment);
    let mut headword = String::new();
    let mut pron = String::new();
    let mut in_orth = false;
    let mut in_pron = false;
    let mut text = TextBuilder::new();
    loop {
        let event = reader.read_event()?;
        match &event {
            Event::Start(e) => match e.local_name().as_ref() {
                b"orth" if headword.is_empty() => in_orth = true,
                b"pron" if pron.is_empty() => in_pron = true,
                _ => {}
            },
            Event::Empty(e) if e.local_name().as_ref() == b"lb" => {
                text.paragraph_break();
            }
            Event::End(e) => match e.local_name().as_ref() {
                b"orth" => in_orth = false,
                b"pron" => in_pron = false,
                _ => {}
            },
            Event::Text(t) => {
                let content = t
                    .xml_content(quick_xml::XmlVersion::Implicit1_0)
                    .map_err(quick_xml::Error::from)?;
                if in_orth {
                    headword.push_str(content.trim());
                } else if in_pron {
                    pron.push_str(content.trim());
                } else {
                    text.push_text(&content);
                }
            }
            Event::Eof => break,
            _ => {}
        }
    }
    if headword.is_empty() && text.out.is_empty() {
        return Ok(None);
    }
    Ok(Some(DictEntry {
        sort,
        key: key.to_string(),
        headword,
        pron,
        text: text.out,
    }))
}

// ---- zText Bibles with Strong's word links (ADR 0020) ----

/// A Bible text imported from a zText module: verses with word-level
/// Strong's links — the raw material of the concordance.
pub struct SwordBible {
    pub code: String,
    pub title: String,
    pub language: String,
    pub verses: Vec<BibleVerse>,
    pub notes: Vec<BibleNote>,
}

pub struct BibleVerse {
    pub book: BookId,
    pub chapter: u16,
    pub verse: u16,
    /// Normalized verse text.
    pub text: String,
    pub links: Vec<WordLink>,
}

/// A Strong's link covering a byte range of the verse text ("G2316").
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WordLink {
    pub start: u32,
    pub end: u32,
    pub strong: String,
}

pub struct BibleNote {
    pub book: BookId,
    pub chapter: u16,
    pub verse: u16,
    pub seq: u16,
    pub offset: u32,
    pub text: String,
}

/// Parse a zText Bible from its configuration and testament files.
pub fn parse_ztext(conf: &str, testaments: &[Testament]) -> Result<SwordBible, SwordError> {
    let conf = parse_conf(conf)?;
    ensure(&conf, "zText", "OSIS")?;
    parse_ztext_parsed(conf, testaments)
}

fn parse_ztext_parsed(conf: Conf, testaments: &[Testament]) -> Result<SwordBible, SwordError> {
    let mut verses: Vec<BibleVerse> = Vec::new();
    let mut notes: Vec<BibleNote> = Vec::new();
    for t in testaments {
        let blocks: Vec<(u32, u32)> = t
            .bzs
            .as_chunks::<12>()
            .0
            .iter()
            .map(|c| {
                (
                    u32::from_le_bytes(c[0..4].try_into().unwrap()),
                    u32::from_le_bytes(c[4..8].try_into().unwrap()),
                )
            })
            .collect();
        let mut cache: HashMap<u32, Vec<u8>> = HashMap::new();
        // Verse identity comes from the slot walk: book and chapter
        // milestones occupy their own slots (verified against the KJV
        // module: chapter ends are embedded, never separate slots), and
        // every following slot is the next verse of the chapter.
        let mut book: Option<BookId> = None;
        let mut chapter: u16 = 0;
        let mut verse: u16 = 0;
        for slot in t.bzv.as_chunks::<10>().0 {
            let block = u32::from_le_bytes(slot[0..4].try_into().unwrap());
            let offset = u32::from_le_bytes(slot[4..8].try_into().unwrap());
            let size = u16::from_le_bytes(slot[8..10].try_into().unwrap());
            if size == 0 {
                // An empty slot inside a chapter still occupies its
                // verse position (the leading testament slot does not).
                if book.is_some() && chapter > 0 {
                    verse += 1;
                }
                continue;
            }
            let data = match cache.entry(block) {
                std::collections::hash_map::Entry::Occupied(e) => e.into_mut(),
                std::collections::hash_map::Entry::Vacant(e) => {
                    let (start, compressed) = *blocks
                        .get(block as usize)
                        .ok_or_else(|| SwordError::Corrupt(format!("block {block}")))?;
                    let raw = t
                        .bzz
                        .get(start as usize..(start + compressed) as usize)
                        .ok_or_else(|| SwordError::Corrupt(format!("block {block} bounds")))?;
                    let mut out = Vec::new();
                    ZlibDecoder::new(raw).read_to_end(&mut out)?;
                    e.insert(out)
                }
            };
            let bytes = data
                .get(offset as usize..(offset as usize + size as usize))
                .ok_or_else(|| SwordError::Corrupt("verse slot bounds".into()))?;
            let fragment = std::str::from_utf8(bytes).map_err(|_| SwordError::Encoding)?;
            let parsed = parse_bible_fragment(fragment)?;
            if let Some(marker) = parsed.book_marker {
                // Non-canonical books stay None: their verse slots are
                // skipped entirely (ADR 0010).
                book = marker;
                chapter = 0;
                verse = 0;
                continue;
            }
            if let Some(c) = parsed.chapter_marker {
                chapter = c;
                verse = 0;
                continue;
            }
            let Some(book) = book else { continue };
            if chapter == 0 {
                continue; // importer milestones and other preamble
            }
            verse += 1;
            if parsed.text.is_empty() {
                continue;
            }
            for (index, (note_offset, note_text)) in parsed.notes.into_iter().enumerate() {
                notes.push(BibleNote {
                    book,
                    chapter,
                    verse,
                    seq: index as u16 + 1,
                    offset: note_offset,
                    text: note_text,
                });
            }
            verses.push(BibleVerse {
                book,
                chapter,
                verse,
                text: parsed.text,
                links: parsed.links,
            });
        }
    }
    if verses.is_empty() {
        return Err(SwordError::Empty);
    }
    Ok(SwordBible {
        code: conf.code,
        title: conf.title,
        language: conf.language,
        verses,
        notes,
    })
}

struct BibleFragment {
    /// Some(book) marks a canonical book slot, Some(None) a skipped one.
    book_marker: Option<Option<BookId>>,
    chapter_marker: Option<u16>,
    text: String,
    links: Vec<WordLink>,
    notes: Vec<(u32, String)>,
}

/// One verse (or structural) fragment: `w` elements carry Strong's
/// lemmas, notes and editorial titles are excluded from the text (notes
/// captured), canonical titles (psalm superscriptions) count as verse
/// text, everything else unwraps to its text.
fn parse_bible_fragment(fragment: &str) -> Result<BibleFragment, SwordError> {
    let mut reader = fragment_reader(fragment);
    let mut out = BibleFragment {
        book_marker: None,
        chapter_marker: None,
        text: String::new(),
        links: Vec::new(),
        notes: Vec::new(),
    };
    let mut text = TextBuilder::new();
    let mut skip_depth: u32 = 0;
    let mut note_depth: u32 = 0;
    let mut note_text = TextBuilder::new();
    let mut note_offset: u32 = 0;
    let mut w_depth: u32 = 0;
    let mut w_start: usize = 0;
    let mut w_strongs: Vec<String> = Vec::new();

    fn strongs_of(e: &BytesStart) -> Vec<String> {
        attr(e, b"lemma")
            .map(|lemma| {
                lemma
                    .split_whitespace()
                    .filter_map(|part| part.strip_prefix("strong:"))
                    .map(|s| s.to_string())
                    .collect()
            })
            .unwrap_or_default()
    }

    loop {
        let event = reader.read_event()?;
        match &event {
            Event::Start(e) | Event::Empty(e) => {
                let empty = matches!(event, Event::Empty(_));
                match e.local_name().as_ref() {
                    b"div" => {
                        if attr(e, b"type").as_deref() == Some("book")
                            && attr(e, b"eID").is_none()
                            && let Some(id) = attr(e, b"osisID")
                        {
                            out.book_marker = Some(book_by_osis(&id));
                        }
                    }
                    b"chapter" => {
                        if attr(e, b"eID").is_none()
                            && let Some(id) = attr(e, b"osisID")
                            && let Some(number) = id.rsplit('.').next()
                            && let Ok(number) = number.parse::<u16>()
                        {
                            out.chapter_marker = Some(number);
                        }
                    }
                    b"w" if !empty => {
                        if w_depth == 0 && note_depth == 0 && skip_depth == 0 {
                            text.flush_separator();
                            w_start = text.out.len();
                            w_strongs = strongs_of(e);
                        }
                        w_depth += 1;
                    }
                    b"note" if !empty => {
                        if note_depth == 0 {
                            note_offset = text.out.len() as u32;
                            note_text = TextBuilder::new();
                        }
                        note_depth += 1;
                    }
                    // A canonical title is a psalm superscription —
                    // verse text under Luther versification. Only
                    // editorial titles are excluded.
                    b"title" if !empty && attr(e, b"canonical").as_deref() != Some("true") => {
                        skip_depth += 1;
                    }
                    b"lb" | b"milestone" if empty && note_depth == 0 && skip_depth == 0 => {
                        text.push_text(" ");
                    }
                    _ => {}
                }
            }
            Event::End(e) => match e.local_name().as_ref() {
                b"w" => {
                    w_depth = w_depth.saturating_sub(1);
                    if w_depth == 0 && note_depth == 0 && skip_depth == 0 {
                        let end = text.out.len();
                        if end > w_start {
                            for strong in w_strongs.drain(..) {
                                out.links.push(WordLink {
                                    start: w_start as u32,
                                    end: end as u32,
                                    strong,
                                });
                            }
                        }
                    }
                }
                b"note" => {
                    note_depth = note_depth.saturating_sub(1);
                    if note_depth == 0 && !note_text.out.is_empty() {
                        out.notes
                            .push((note_offset, std::mem::take(&mut note_text.out)));
                    }
                }
                b"title" => skip_depth = skip_depth.saturating_sub(1),
                _ => {}
            },
            Event::Text(t) => {
                let content = t
                    .xml_content(quick_xml::XmlVersion::Implicit1_0)
                    .map_err(quick_xml::Error::from)?;
                if skip_depth > 0 {
                    // structural titles are not verse text
                } else if note_depth > 0 {
                    note_text.push_text(&content);
                } else {
                    text.push_text(&content);
                }
            }
            Event::Eof => break,
            _ => {}
        }
    }
    out.text = text.out;
    Ok(out)
}

// ---- RawGenBook general books (ADR 0021) ----

/// A general book from a RawGenBook module: the TreeKey flattened
/// depth-first into reading order.
pub struct SwordBook {
    pub code: String,
    pub title: String,
    pub language: String,
    pub sections: Vec<BookSection>,
}

pub struct BookSection {
    /// 1-based position in depth-first reading order.
    pub ordinal: u32,
    /// Nesting depth (1 = top level).
    pub level: u8,
    /// The tree key name (table of contents label).
    pub name: String,
    /// The section's own leading title, when its text carries one.
    pub heading: Option<String>,
    /// Normalized text; paragraphs separated by "\n\n".
    pub text: String,
}

/// Parse a RawGenBook from its configuration and three files: `idx`
/// (u32 slot offsets into `dat`), `dat` (tree nodes: parent, next
/// sibling, first child — each an idx offset or 0xFFFFFFFF — then the
/// NUL-terminated name and a sized payload of offset+size into `bdt`),
/// and `bdt` (the OSIS section bodies).
pub fn parse_genbook(
    conf: &str,
    idx: &[u8],
    dat: &[u8],
    bdt: &[u8],
) -> Result<SwordBook, SwordError> {
    let conf = parse_conf(conf)?;
    for (name, got, want) in [
        ("ModDrv", &conf.mod_drv, "RawGenBook"),
        ("SourceType", &conf.source, "OSIS"),
        ("Encoding", &conf.encoding, "UTF-8"),
    ] {
        if !got.eq_ignore_ascii_case(want) {
            return Err(SwordError::Unsupported(format!("{name}={got}")));
        }
    }
    parse_genbook_parsed(conf, idx, dat, bdt)
}

const TREE_NONE: u32 = u32::MAX;

struct TreeNode {
    next: u32,
    child: u32,
    name: String,
    body: Option<(u32, u32)>,
}

fn tree_node(idx: &[u8], dat: &[u8], slot: u32) -> Result<TreeNode, SwordError> {
    let slot = slot as usize;
    let dat_off = u32::from_le_bytes(
        idx.get(slot..slot + 4)
            .ok_or_else(|| SwordError::Corrupt("tree slot".into()))?
            .try_into()
            .unwrap(),
    ) as usize;
    let head = dat
        .get(dat_off..dat_off + 12)
        .ok_or_else(|| SwordError::Corrupt("tree node".into()))?;
    let next = u32::from_le_bytes(head[4..8].try_into().unwrap());
    let child = u32::from_le_bytes(head[8..12].try_into().unwrap());
    let name_start = dat_off + 12;
    let name_end = dat[name_start..]
        .iter()
        .position(|&b| b == 0)
        .map(|p| name_start + p)
        .ok_or_else(|| SwordError::Corrupt("tree name".into()))?;
    let name = std::str::from_utf8(&dat[name_start..name_end])
        .map_err(|_| SwordError::Encoding)?
        .to_string();
    let payload = dat.get(name_end + 1..name_end + 3).and_then(|s| {
        let size = u16::from_le_bytes(s.try_into().unwrap()) as usize;
        (size >= 8)
            .then(|| dat.get(name_end + 3..name_end + 3 + 8))
            .flatten()
            .map(|p| {
                (
                    u32::from_le_bytes(p[0..4].try_into().unwrap()),
                    u32::from_le_bytes(p[4..8].try_into().unwrap()),
                )
            })
    });
    Ok(TreeNode {
        next,
        child,
        name,
        body: payload.filter(|&(_, size)| size > 0),
    })
}

fn parse_genbook_parsed(
    conf: Conf,
    idx: &[u8],
    dat: &[u8],
    bdt: &[u8],
) -> Result<SwordBook, SwordError> {
    let mut sections = Vec::new();
    let max_nodes = idx.len() / 4;
    let mut visited = 0usize;
    // Depth-first from the root's first child, in sibling order.
    let root = tree_node(idx, dat, 0)?;
    let mut stack: Vec<u32> = Vec::new();
    if root.child != TREE_NONE {
        stack.push(root.child);
    }
    let mut levels: Vec<u8> = vec![1];
    while let Some(slot) = stack.pop() {
        visited += 1;
        if visited > max_nodes {
            return Err(SwordError::Corrupt("tree cycle".into()));
        }
        let level = *levels.last().unwrap_or(&1);
        let node = tree_node(idx, dat, slot)?;
        let (heading, text) = match node.body {
            Some((off, size)) => {
                let bytes = bdt
                    .get(off as usize..(off + size) as usize)
                    .ok_or_else(|| SwordError::Corrupt("book body bounds".into()))?;
                let fragment = std::str::from_utf8(bytes).map_err(|_| SwordError::Encoding)?;
                parse_book_fragment(fragment)?
            }
            None => (None, String::new()),
        };
        sections.push(BookSection {
            ordinal: sections.len() as u32 + 1,
            level,
            name: node.name,
            heading,
            text,
        });
        // Push the next sibling first, then descend into children so the
        // child block comes out immediately after its parent.
        if node.next != TREE_NONE {
            stack.push(node.next);
        } else {
            levels.pop();
        }
        if node.child != TREE_NONE {
            levels.push(level + 1);
            stack.push(node.child);
        }
    }
    if sections.is_empty() {
        return Err(SwordError::Empty);
    }
    Ok(SwordBook {
        code: conf.code,
        title: conf.title,
        language: conf.language,
        sections,
    })
}

/// A book section body: the first `title` becomes the heading, `p`
/// elements become paragraphs, references keep their display text.
fn parse_book_fragment(fragment: &str) -> Result<(Option<String>, String), SwordError> {
    let mut reader = fragment_reader(fragment);
    let mut heading: Option<String> = None;
    let mut heading_capture = false;
    let mut heading_text = String::new();
    let mut text = TextBuilder::new();
    loop {
        let event = reader.read_event()?;
        match &event {
            Event::Start(e) | Event::Empty(e) => match e.local_name().as_ref() {
                b"title" => {
                    if heading.is_none() && text.out.is_empty() {
                        heading_capture = true;
                        heading_text.clear();
                    } else {
                        text.paragraph_break();
                    }
                }
                b"p" | b"div" => text.paragraph_break(),
                b"lb" | b"milestone" => text.push_text(" "),
                _ => {}
            },
            Event::End(e) => match e.local_name().as_ref() {
                b"title" => {
                    if heading_capture {
                        heading_capture = false;
                        let t = heading_text
                            .split_whitespace()
                            .collect::<Vec<_>>()
                            .join(" ");
                        if !t.is_empty() {
                            heading = Some(t);
                        }
                    } else {
                        text.paragraph_break();
                    }
                }
                b"p" | b"div" => text.paragraph_break(),
                _ => {}
            },
            Event::Text(t) => {
                let content = t
                    .xml_content(quick_xml::XmlVersion::Implicit1_0)
                    .map_err(quick_xml::Error::from)?;
                if heading_capture {
                    heading_text.push_str(&content);
                } else {
                    text.push_text(&content);
                }
            }
            Event::Eof => break,
            _ => {}
        }
    }
    Ok((heading, text.out))
}

/// A devotional zLD entry (OSIS): each `section` div becomes one entry
/// keyed `(month·100+day)·10 + index`, its title the headword.
fn parse_devotional_entry(key: &str, fragment: &str) -> Result<Vec<DictEntry>, SwordError> {
    let day_sort = {
        let mut parts = key.split('.');
        let month: u32 = parts.next().and_then(|p| p.parse().ok()).unwrap_or(0);
        let day: u32 = parts.next().and_then(|p| p.parse().ok()).unwrap_or(0);
        month * 100 + day
    };
    if day_sort == 0 {
        return Ok(Vec::new());
    }
    let mut reader = fragment_reader(fragment);
    let mut entries: Vec<DictEntry> = Vec::new();
    let mut headword = String::new();
    let mut heading_capture = false;
    let mut text = TextBuilder::new();
    let mut open = false;

    fn flush(
        entries: &mut Vec<DictEntry>,
        key: &str,
        day_sort: u32,
        headword: &mut String,
        text: &mut TextBuilder,
        open: &mut bool,
    ) {
        if *open && (!headword.is_empty() || !text.out.is_empty()) {
            entries.push(DictEntry {
                sort: day_sort * 10 + entries.len() as u32,
                key: key.to_string(),
                headword: std::mem::take(headword),
                pron: String::new(),
                text: std::mem::take(&mut text.out),
            });
        }
        *text = TextBuilder::new();
        *open = false;
    }

    loop {
        let event = reader.read_event()?;
        match &event {
            Event::Start(e) | Event::Empty(e) => match e.local_name().as_ref() {
                b"div" if attr(e, b"type").as_deref() == Some("section") => {
                    flush(
                        &mut entries,
                        key,
                        day_sort,
                        &mut headword,
                        &mut text,
                        &mut open,
                    );
                    open = true;
                }
                b"title" => {
                    if open && headword.is_empty() && text.out.is_empty() {
                        heading_capture = true;
                    } else {
                        text.paragraph_break();
                    }
                }
                b"p" => text.paragraph_break(),
                b"lb" | b"milestone" => text.push_text(" "),
                _ => {}
            },
            Event::End(e) => match e.local_name().as_ref() {
                b"title" => {
                    if heading_capture {
                        heading_capture = false;
                        headword = headword.split_whitespace().collect::<Vec<_>>().join(" ");
                    } else {
                        text.paragraph_break();
                    }
                }
                b"p" => text.paragraph_break(),
                _ => {}
            },
            Event::Text(t) => {
                let content = t
                    .xml_content(quick_xml::XmlVersion::Implicit1_0)
                    .map_err(quick_xml::Error::from)?;
                if heading_capture {
                    headword.push_str(&content);
                } else if open {
                    text.push_text(&content);
                }
            }
            Event::Eof => break,
            _ => {}
        }
    }
    flush(
        &mut entries,
        key,
        day_sort,
        &mut headword,
        &mut text,
        &mut open,
    );
    Ok(entries)
}
