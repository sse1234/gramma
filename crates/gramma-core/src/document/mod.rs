//! The document model (ADR 0029): what every importer produces and what
//! interpretation, storage, and typesetting consume. A document is a
//! sequence of blocks over styled inlines, with notes and image assets
//! held beside the tree.

pub mod epub;
pub mod infer;
pub mod interpret;
pub mod pdf;

use serde::{Deserialize, Serialize};

/// A complete imported document.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct Document {
    pub title: String,
    /// BCP 47 tag when the source states one ("de", "en").
    pub language: String,
    pub authors: Vec<String>,
    pub blocks: Vec<Block>,
    /// Footnotes in document order; inlines refer to them by index.
    pub notes: Vec<Note>,
    /// Images in document order; figures refer to them by index.
    pub images: Vec<ImageAsset>,
}

/// One footnote body.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct Note {
    /// The source's own label ("1", "a"); display labels are assigned
    /// at layout time.
    pub label: String,
    pub blocks: Vec<Block>,
}

/// An embedded image, kept at its source resolution.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct ImageAsset {
    /// IANA media type ("image/jpeg", "image/png").
    pub media_type: String,
    #[serde(with = "serde_bytes_vec")]
    pub data: Vec<u8>,
    pub width: u32,
    pub height: u32,
}

mod serde_bytes_vec {
    use serde::{Deserialize, Deserializer, Serializer};
    pub fn serialize<S: Serializer>(v: &[u8], s: S) -> Result<S::Ok, S::Error> {
        s.serialize_bytes(v)
    }
    pub fn deserialize<'de, D: Deserializer<'de>>(d: D) -> Result<Vec<u8>, D::Error> {
        Vec::<u8>::deserialize(d)
    }
}

/// Where a paragraph sits in the page's voice.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
pub enum ParagraphStyle {
    /// Running body text.
    #[default]
    Body,
    /// Block quotation, set indented.
    Quote,
    /// A quoted scripture passage inside a commentary, set apart
    /// (bold in most publishers' style).
    Scripture,
    /// A line of poetry; `indent` levels nest.
    Poetry { indent: u8 },
    /// A figure or table caption.
    Caption,
}

/// A block-level element.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum Block {
    /// Section heading; level 1 is the highest in the document.
    Heading { level: u8, inlines: Vec<Inline> },
    Paragraph {
        style: ParagraphStyle,
        inlines: Vec<Inline>,
    },
    /// Enumerated (`ordered`) or bulleted list; each item holds blocks.
    List {
        ordered: bool,
        items: Vec<Vec<Block>>,
    },
    /// Rows of cells; `header` rows come first.
    Table {
        header_rows: u8,
        rows: Vec<Vec<Vec<Inline>>>,
    },
    /// An image with an optional caption.
    Figure { image: usize, caption: Vec<Inline> },
    /// A horizontal rule or an ornamental break.
    Rule,
    /// Chapter start of a Bible text or a passage-anchored section start:
    /// `osis` is "Book.Chapter" or a verse range "Book.Ch.V-Book.Ch.V".
    Milestone { osis: String },
}

/// Character-level styling, combinable.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
pub struct Style {
    pub italic: bool,
    pub bold: bool,
    pub small_caps: bool,
    pub superscript: bool,
    pub subscript: bool,
    pub monospace: bool,
}

impl Style {
    pub const PLAIN: Style = Style {
        italic: false,
        bold: false,
        small_caps: false,
        superscript: false,
        subscript: false,
        monospace: false,
    };

    pub fn is_plain(&self) -> bool {
        *self == Style::PLAIN
    }
}

/// An inline element within a block.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum Inline {
    Text {
        text: String,
        style: Style,
    },
    /// A verse number of a Bible text.
    VerseNumber(u16),
    /// Marker pointing at `Document::notes[index]`.
    NoteRef(usize),
    /// A recognized scripture reference over `text`, resolved to OSIS
    /// ("Rom.8.23", "Gal.2.17-Gal.2.21", "Ps.23").
    Reference {
        text: String,
        osis: String,
    },
    /// A forced line break inside a paragraph.
    LineBreak,
}

impl Inline {
    pub fn text(text: impl Into<String>) -> Inline {
        Inline::Text {
            text: text.into(),
            style: Style::PLAIN,
        }
    }

    pub fn styled(text: impl Into<String>, style: Style) -> Inline {
        Inline::Text {
            text: text.into(),
            style,
        }
    }
}

/// Concatenated plain text of inlines (verse numbers and note markers
/// omitted), for detection heuristics and tests.
pub fn plain_text(inlines: &[Inline]) -> String {
    let mut out = String::new();
    for inline in inlines {
        match inline {
            Inline::Text { text, .. } | Inline::Reference { text, .. } => out.push_str(text),
            Inline::LineBreak => out.push('\n'),
            Inline::VerseNumber(_) | Inline::NoteRef(_) => {}
        }
    }
    out
}

/// Append `text` with `style`, merging into a preceding run of the same
/// style so inlines stay minimal.
pub fn push_text(inlines: &mut Vec<Inline>, text: &str, style: Style) {
    if text.is_empty() {
        return;
    }
    if let Some(Inline::Text {
        text: last,
        style: last_style,
    }) = inlines.last_mut()
        && *last_style == style
    {
        last.push_str(text);
        return;
    }
    inlines.push(Inline::styled(text, style));
}

/// Collapse runs of whitespace to single spaces inside `inlines` and trim
/// the block's ends, the way XHTML and PDF line joining both need.
pub fn normalize_whitespace(inlines: &mut Vec<Inline>) {
    let mut prev_space = true;
    for inline in inlines.iter_mut() {
        if let Inline::Text { text, .. } = inline {
            let mut out = String::with_capacity(text.len());
            for c in text.chars() {
                if c.is_whitespace() && c != '\u{a0}' {
                    if !prev_space {
                        out.push(' ');
                    }
                    prev_space = true;
                } else {
                    out.push(c);
                    prev_space = false;
                }
            }
            *text = out;
        } else if matches!(inline, Inline::LineBreak | Inline::VerseNumber(_)) {
            // A verse number stands apart from the text that follows.
            prev_space = true;
        } else {
            prev_space = false;
        }
    }
    if let Some(Inline::Text { text, .. }) = inlines.last_mut() {
        let trimmed = text.trim_end().len();
        text.truncate(trimmed);
    }
    inlines.retain(|i| !matches!(i, Inline::Text { text, .. } if text.is_empty()));
}

/// A readable title from a file name when the document states none:
/// "256386_kommentar-zum-roemerbrief_download.pdf" → "Kommentar zum
/// roemerbrief" (shop numbers and download suffixes dropped, separators
/// spaced, first letter raised).
pub fn title_from_filename(name: &str) -> String {
    let stem = name.rsplit('/').next().unwrap_or(name);
    let stem = stem.rsplit_once('.').map(|(s, _)| s).unwrap_or(stem);
    let mut words: Vec<String> = stem
        .split(['_', '-', ' '])
        .filter(|w| !w.is_empty() && !w.chars().all(|c| c.is_ascii_digit()))
        .map(|w| w.to_string())
        .collect();
    words.retain(|w| {
        !matches!(
            w.to_ascii_lowercase().as_str(),
            "download" | "ebook" | "pdf" | "epub" | "final"
        )
    });
    let mut title = words.join(" ");
    if let Some(first) = title.chars().next() {
        let upper: String = first.to_uppercase().collect();
        title.replace_range(..first.len_utf8(), &upper);
    }
    title
}

/// Errors shared by the document readers.
#[derive(Debug, thiserror::Error)]
pub enum DocumentError {
    #[error("I/O error: {0}")]
    Io(#[from] std::io::Error),
    #[error("archive error: {0}")]
    Zip(#[from] zip::result::ZipError),
    #[error("XML error: {0}")]
    Xml(#[from] quick_xml::Error),
    #[error("malformed {0}: {1}")]
    Malformed(&'static str, String),
    #[error("the file is protected: {0}")]
    Protected(String),
    #[error("PDF error: {0}")]
    Pdf(String),
}
