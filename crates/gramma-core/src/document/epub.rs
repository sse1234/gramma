//! EPUB reader (ADR 0029): the package's spine in order, each XHTML file
//! walked into blocks. Styling comes from the tags themselves and from a
//! small reading of the stylesheets' class rules; verse numbers, note
//! references, and note bodies are recognized by the class and
//! `epub:type` conventions Bible producers use.

use std::collections::HashMap;
use std::io::{Read, Seek};

use quick_xml::Reader;
use quick_xml::events::{BytesStart, Event};

use super::{
    Block, Document, DocumentError, ImageAsset, Inline, Note, ParagraphStyle, Style,
    normalize_whitespace, push_text,
};
use crate::reference::book_by_osis;

const XML: quick_xml::XmlVersion = quick_xml::XmlVersion::Implicit1_0;

/// Read an EPUB from any seekable source (a file, a memory buffer).
pub fn read(source: impl Read + Seek) -> Result<Document, DocumentError> {
    let mut zip = zip::ZipArchive::new(source)?;
    refuse_encrypted(&mut zip)?;
    let container = read_entry(&mut zip, "META-INF/container.xml")?;
    let opf_path = rootfile(&container)?;
    let opf_dir = parent_dir(&opf_path);
    let opf = read_entry(&mut zip, &opf_path)?;
    let package = parse_opf(&opf)?;

    let mut classes = ClassStyles::default();
    for item in package.manifest.values() {
        if item.media_type == "text/css"
            && let Ok(css) = read_entry(&mut zip, &join(&opf_dir, &item.href))
        {
            classes.absorb(&css);
        }
    }

    let mut doc = Document {
        title: package.title.clone(),
        language: package.language.clone(),
        authors: package.authors.clone(),
        ..Document::default()
    };
    for idref in &package.spine {
        let Some(item) = package.manifest.get(idref) else {
            continue;
        };
        if !item.media_type.contains("xhtml") && !item.media_type.contains("html") {
            continue;
        }
        let path = join(&opf_dir, &item.href);
        let Ok(xhtml) = read_entry(&mut zip, &path) else {
            continue;
        };
        if let Some(osis) = milestone_from_name(&item.href) {
            doc.blocks.push(Block::Milestone { osis });
        }
        let mut walker = Walker::new(&classes, &mut doc, parent_dir(&path));
        walker.walk(&xhtml)?;
        walker.finish(&mut zip, &package);
    }
    Ok(doc)
}

/// EPUBs may obfuscate embedded fonts; anything else in the encryption
/// manifest is DRM and the file is refused (ADR 0029).
fn refuse_encrypted<R: Read + Seek>(zip: &mut zip::ZipArchive<R>) -> Result<(), DocumentError> {
    let Ok(manifest) = read_entry(zip, "META-INF/encryption.xml") else {
        return Ok(());
    };
    let mut reader = Reader::from_str(&manifest);
    loop {
        match reader.read_event()? {
            Event::Start(e) | Event::Empty(e) if e.local_name().as_ref() == b"EncryptionMethod" => {
                let algorithm = attr(&e, b"Algorithm").unwrap_or_default();
                let font_obfuscation = algorithm.contains("idpf.org/2008/embedding")
                    || algorithm.contains("ns.adobe.com/pdf/enc");
                if !font_obfuscation {
                    return Err(DocumentError::Protected(
                        "this EPUB is encrypted (DRM); gramma opens only unprotected files".into(),
                    ));
                }
            }
            Event::Eof => return Ok(()),
            _ => {}
        }
    }
}

fn read_entry<R: Read + Seek>(
    zip: &mut zip::ZipArchive<R>,
    name: &str,
) -> Result<String, DocumentError> {
    let mut text = String::new();
    zip.by_name(name)?.read_to_string(&mut text)?;
    Ok(text)
}

fn read_bytes<R: Read + Seek>(zip: &mut zip::ZipArchive<R>, name: &str) -> Option<Vec<u8>> {
    let mut data = Vec::new();
    zip.by_name(name).ok()?.read_to_end(&mut data).ok()?;
    Some(data)
}

fn rootfile(container: &str) -> Result<String, DocumentError> {
    let mut reader = Reader::from_str(container);
    loop {
        match reader.read_event()? {
            Event::Start(e) | Event::Empty(e) if e.local_name().as_ref() == b"rootfile" => {
                if let Some(path) = attr(&e, b"full-path") {
                    return Ok(path);
                }
            }
            Event::Eof => {
                return Err(DocumentError::Malformed(
                    "container.xml",
                    "no rootfile".into(),
                ));
            }
            _ => {}
        }
    }
}

#[derive(Debug, Clone)]
struct ManifestItem {
    href: String,
    media_type: String,
}

#[derive(Debug, Default)]
struct Package {
    title: String,
    language: String,
    authors: Vec<String>,
    manifest: HashMap<String, ManifestItem>,
    spine: Vec<String>,
}

fn parse_opf(opf: &str) -> Result<Package, DocumentError> {
    let mut reader = Reader::from_str(opf);
    let mut package = Package::default();
    let mut capture: Option<&'static str> = None;
    let mut text = String::new();
    loop {
        match reader.read_event()? {
            Event::Start(e) => match e.local_name().as_ref() {
                b"title" if package.title.is_empty() => capture = Some("title"),
                b"language" if package.language.is_empty() => capture = Some("language"),
                b"creator" => capture = Some("creator"),
                b"item" => insert_item(&mut package, &e),
                b"itemref" => {
                    if let Some(id) = attr(&e, b"idref") {
                        package.spine.push(id);
                    }
                }
                _ => {}
            },
            Event::Empty(e) => match e.local_name().as_ref() {
                b"item" => insert_item(&mut package, &e),
                b"itemref" => {
                    if let Some(id) = attr(&e, b"idref") {
                        package.spine.push(id);
                    }
                }
                _ => {}
            },
            Event::Text(t) if capture.is_some() => {
                text.push_str(&t.xml_content(XML).map_err(quick_xml::Error::from)?);
            }
            Event::End(_) => {
                if let Some(field) = capture.take() {
                    let value = text.trim().to_string();
                    text.clear();
                    match field {
                        "title" => package.title = value,
                        "language" => package.language = value,
                        _ => {
                            if !value.is_empty() {
                                package.authors.push(value);
                            }
                        }
                    }
                }
            }
            Event::Eof => break,
            _ => {}
        }
    }
    if package.spine.is_empty() {
        return Err(DocumentError::Malformed("package", "empty spine".into()));
    }
    Ok(package)
}

fn insert_item(package: &mut Package, e: &BytesStart) {
    if let (Some(id), Some(href)) = (attr(e, b"id"), attr(e, b"href")) {
        package.manifest.insert(
            id,
            ManifestItem {
                href,
                media_type: attr(e, b"media-type").unwrap_or_default(),
            },
        );
    }
}

fn attr(e: &BytesStart, name: &[u8]) -> Option<String> {
    e.attributes()
        .flatten()
        .find(|a| a.key.local_name().as_ref() == name)
        .and_then(|a| a.normalized_value(XML).ok())
        .map(|v| v.into_owned())
}

fn parent_dir(path: &str) -> String {
    match path.rfind('/') {
        Some(i) => path[..i].to_string(),
        None => String::new(),
    }
}

/// Resolve `href` against `dir`, folding `..` and stripping fragments.
fn join(dir: &str, href: &str) -> String {
    let href = href.split('#').next().unwrap_or("");
    let href = percent_decode(href);
    let mut parts: Vec<&str> = if dir.is_empty() {
        Vec::new()
    } else {
        dir.split('/').collect()
    };
    for part in href.split('/') {
        match part {
            "" | "." => {}
            ".." => {
                parts.pop();
            }
            p => parts.push(p),
        }
    }
    parts.join("/")
}

fn percent_decode(s: &str) -> String {
    if !s.contains('%') {
        return s.to_string();
    }
    let bytes = s.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%'
            && i + 2 < bytes.len()
            && let Ok(v) = u8::from_str_radix(&s[i + 1..i + 3], 16)
        {
            out.push(v);
            i += 3;
        } else {
            out.push(bytes[i]);
            i += 1;
        }
    }
    String::from_utf8_lossy(&out).into_owned()
}

/// "Esth-4.html", "Ps-119.xhtml": a spine file named by OSIS book and
/// chapter marks a chapter start.
fn milestone_from_name(href: &str) -> Option<String> {
    let name = href.rsplit('/').next()?;
    let stem = name.split('.').next()?;
    let (book, chapter) = stem.split_once('-')?;
    let chapter: u16 = chapter.parse().ok()?;
    let id = book_by_osis(book)?;
    Some(format!("{}.{}", id.info().osis, chapter))
}

/// Class → style deltas read from `.class { ... }` rules. Deliberately
/// small: the properties that change the reading voice.
#[derive(Debug, Default)]
struct ClassStyles {
    styles: HashMap<String, Style>,
    /// Classes whose rule hides the element (`display: none`).
    hidden: Vec<String>,
}

impl ClassStyles {
    fn absorb(&mut self, css: &str) {
        let css = strip_comments(css);
        for rule in css.split('}') {
            let Some((selectors, body)) = rule.split_once('{') else {
                continue;
            };
            let mut style = Style::PLAIN;
            let mut hidden = false;
            for decl in body.split(';') {
                let Some((prop, value)) = decl.split_once(':') else {
                    continue;
                };
                let prop = prop.trim().to_ascii_lowercase();
                let value = value.trim().to_ascii_lowercase();
                match prop.as_str() {
                    "font-style" if value.starts_with("italic") || value.starts_with("oblique") => {
                        style.italic = true
                    }
                    "font-weight" => {
                        let weight: u32 = value.parse().unwrap_or(0);
                        if value.starts_with("bold") || weight >= 600 {
                            style.bold = true;
                        }
                    }
                    "font-variant" if value.contains("small-caps") => style.small_caps = true,
                    "vertical-align" if value.contains("super") || value.contains("text-top") => {
                        style.superscript = true
                    }
                    "vertical-align" if value.contains("sub") => style.subscript = true,
                    "font-family" if value.contains("mono") || value.contains("courier") => {
                        style.monospace = true
                    }
                    "display" if value == "none" => hidden = true,
                    _ => {}
                }
            }
            if style.is_plain() && !hidden {
                continue;
            }
            for selector in selectors.split(',') {
                // Only plain class selectors (".x", "span.x"); descendant
                // and pseudo selectors are beyond this reading.
                let selector = selector.trim();
                if selector.contains(' ') || selector.contains(':') || selector.contains('>') {
                    continue;
                }
                let Some((_, class)) = selector.rsplit_once('.') else {
                    continue;
                };
                if hidden {
                    self.hidden.push(class.to_string());
                }
                if !style.is_plain() {
                    let entry = self.styles.entry(class.to_string()).or_default();
                    *entry = merge(*entry, style);
                }
            }
        }
    }

    fn style_of(&self, classes: &str) -> Style {
        let mut style = Style::PLAIN;
        for class in classes.split_whitespace() {
            if let Some(s) = self.styles.get(class) {
                style = merge(style, *s);
            }
        }
        style
    }

    fn is_hidden(&self, classes: &str) -> bool {
        classes
            .split_whitespace()
            .any(|c| self.hidden.iter().any(|h| h == c))
    }
}

fn merge(a: Style, b: Style) -> Style {
    Style {
        italic: a.italic || b.italic,
        bold: a.bold || b.bold,
        small_caps: a.small_caps || b.small_caps,
        superscript: a.superscript || b.superscript,
        subscript: a.subscript || b.subscript,
        monospace: a.monospace || b.monospace,
    }
}

fn strip_comments(css: &str) -> String {
    let mut out = String::with_capacity(css.len());
    let mut rest = css;
    while let Some(start) = rest.find("/*") {
        out.push_str(&rest[..start]);
        match rest[start..].find("*/") {
            Some(end) => rest = &rest[start + end + 2..],
            None => return out,
        }
    }
    out.push_str(rest);
    out
}

/// What an open element contributes while its content is walked.
#[derive(Debug, Clone)]
struct Frame {
    name: String,
    /// Style added by this element, applied to text inside it.
    style: Style,
    /// Text inside this element is skipped (script, style, hidden).
    skip: bool,
    /// The element is a verse-number holder: its digits become a marker.
    verse_number: bool,
    /// The element is a note reference (a superscript link or span).
    note_ref: Option<NoteTarget>,
    /// The element opens a note body collected out of the flow.
    note_body: Option<String>,
    /// The element carries a note body's own label.
    note_label: bool,
    /// Label text seen inside this note body.
    note_label_text: String,
    /// Block context opened by this element.
    block: Option<BlockKind>,
}

#[derive(Debug, Clone, PartialEq)]
enum NoteTarget {
    Id(String),
    /// A marker without a link; matched to note bodies by order.
    Ordinal,
}

#[derive(Debug, Clone, Copy, PartialEq)]
enum BlockKind {
    Heading(u8),
    Paragraph(ParagraphStyle),
    List {
        ordered: bool,
    },
    ListItem,
    Table,
    TableRow {
        header: bool,
    },
    TableCell,
    Figure,
    Note,
    /// A paragraph that turned out to be only navigation links.
    Nav,
}

/// A list under construction.
struct ListBuilder {
    ordered: bool,
    items: Vec<Vec<Block>>,
}

struct TableBuilder {
    header_rows: u8,
    rows: Vec<Vec<Vec<Inline>>>,
    current_row: Option<(bool, Vec<Vec<Inline>>)>,
}

/// Where finished blocks go: the document, the current list item, or a
/// note body.
struct Sink {
    blocks: Vec<Block>,
}

struct Walker<'a> {
    classes: &'a ClassStyles,
    doc: &'a mut Document,
    dir: String,
    frames: Vec<Frame>,
    /// Inline run of the paragraph being built.
    inlines: Vec<Inline>,
    /// Text seen directly in a block without a paragraph wrapper.
    inline_block_open: bool,
    sinks: Vec<Sink>,
    lists: Vec<ListBuilder>,
    tables: Vec<TableBuilder>,
    cell: Option<Vec<Inline>>,
    /// Note bodies found in this file, by id (or ordinal key).
    note_bodies: Vec<(Option<String>, Vec<Block>, String)>,
    /// Note markers placed in this file, in order: index into
    /// `doc.notes` plus the target they named.
    note_refs: Vec<(usize, NoteTarget)>,
    /// Link inside the current paragraph: (text seen inside links, text
    /// seen outside) to recognize navigation-only paragraphs.
    link_chars: usize,
    other_chars: usize,
    in_link: bool,
    pending_images: Vec<(usize, String)>,
}

impl<'a> Walker<'a> {
    fn new(classes: &'a ClassStyles, doc: &'a mut Document, dir: String) -> Self {
        Walker {
            classes,
            doc,
            dir,
            frames: Vec::new(),
            inlines: Vec::new(),
            inline_block_open: false,
            sinks: vec![Sink { blocks: Vec::new() }],
            lists: Vec::new(),
            tables: Vec::new(),
            cell: None,
            note_bodies: Vec::new(),
            note_refs: Vec::new(),
            link_chars: 0,
            other_chars: 0,
            in_link: false,
            pending_images: Vec::new(),
        }
    }

    fn walk(&mut self, xhtml: &str) -> Result<(), DocumentError> {
        let mut reader = Reader::from_str(xhtml);
        reader.config_mut().check_end_names = false;
        let mut in_body = false;
        loop {
            match reader.read_event()? {
                Event::Start(e) => {
                    let name = local(&e);
                    if name == "body" {
                        in_body = true;
                        continue;
                    }
                    if !in_body {
                        continue;
                    }
                    self.open(&name, &e);
                }
                Event::Empty(e) => {
                    let name = local(&e);
                    if !in_body {
                        continue;
                    }
                    self.open(&name, &e);
                    self.close(&name);
                }
                Event::End(e) => {
                    let name = String::from_utf8_lossy(e.local_name().as_ref()).into_owned();
                    if name == "body" {
                        in_body = false;
                        continue;
                    }
                    if in_body {
                        self.close(&name);
                    }
                }
                Event::Text(t) if in_body => {
                    let text = t.xml_content(XML).map_err(quick_xml::Error::from)?;
                    self.text(&text);
                }
                Event::CData(t) if in_body => {
                    let text = String::from_utf8_lossy(&t).into_owned();
                    self.text(&text);
                }
                Event::Eof => break,
                _ => {}
            }
        }
        self.flush_paragraph(ParagraphStyle::Body);
        Ok(())
    }

    fn current_style(&self) -> Style {
        self.frames
            .iter()
            .fold(Style::PLAIN, |acc, f| merge(acc, f.style))
    }

    fn skipping(&self) -> bool {
        self.frames.iter().any(|f| f.skip)
    }

    fn in_verse_number(&self) -> bool {
        self.frames.iter().any(|f| f.verse_number)
    }

    fn in_note_ref(&self) -> bool {
        self.frames.iter().any(|f| f.note_ref.is_some())
    }

    fn in_note_body(&self) -> bool {
        self.frames.iter().any(|f| f.note_body.is_some())
    }

    fn open(&mut self, name: &str, e: &BytesStart) {
        let class = attr(e, b"class").unwrap_or_default();
        let epub_type = attr(e, b"type").unwrap_or_default();
        let id = attr(e, b"id");
        let lower_class = class.to_ascii_lowercase();
        let mut frame = Frame {
            name: name.to_string(),
            style: self.classes.style_of(&class),
            skip: false,
            verse_number: false,
            note_ref: None,
            note_body: None,
            note_label: false,
            note_label_text: String::new(),
            block: None,
        };
        if self.classes.is_hidden(&class) {
            // Hidden chapter numbers (h3.hidden) still carry structure;
            // hide only inline elements.
            if !is_block_tag(name) {
                frame.skip = true;
            }
        }
        match name {
            "script" | "style" | "nav" | "svg" => frame.skip = true,
            "i" | "em" | "cite" | "dfn" => frame.style.italic = true,
            "b" | "strong" => frame.style.bold = true,
            "sup" => frame.style.superscript = true,
            "sub" => frame.style.subscript = true,
            "code" | "tt" | "kbd" | "samp" => frame.style.monospace = true,
            "br" if !self.skipping() => {
                self.inlines.push(Inline::LineBreak);
            }
            "hr" => {
                self.flush_paragraph(ParagraphStyle::Body);
                self.emit(Block::Rule);
            }
            "img" | "image" => {
                if let Some(src) = attr(e, b"src").or_else(|| attr(e, b"href")) {
                    self.flush_paragraph(ParagraphStyle::Body);
                    let index = self.doc.images.len();
                    self.doc.images.push(ImageAsset::default());
                    self.pending_images.push((index, join(&self.dir, &src)));
                    self.emit(Block::Figure {
                        image: index,
                        caption: Vec::new(),
                    });
                }
            }
            "a" => {
                self.in_link = true;
                let href = attr(e, b"href").unwrap_or_default();
                let is_ref = epub_type.contains("noteref")
                    || lower_class.contains("noteref")
                    || lower_class.contains("footnote-anchor")
                    || lower_class.contains("footnotelink")
                    || lower_class.contains("footnoteref")
                    || (href.starts_with('#') && self.frames.iter().any(|f| f.style.superscript));
                let target = match href.strip_prefix('#') {
                    Some(id) if !id.is_empty() => NoteTarget::Id(id.to_string()),
                    _ => NoteTarget::Ordinal,
                };
                let backlink = self.in_note_body()
                    && (href.contains("backlink")
                        || lower_class.contains("anchor")
                        || lower_class.contains("backlink"));
                if backlink {
                    frame.note_label = true;
                } else if let Some(outer) =
                    self.frames.iter_mut().rev().find(|f| f.note_ref.is_some())
                {
                    // A link inside a marker span names the body precisely.
                    if is_ref || href.starts_with('#') {
                        outer.note_ref = Some(target);
                    }
                } else if is_ref && !self.in_note_body() {
                    frame.note_ref = Some(target);
                }
            }
            "span" => {
                if is_verse_class(&lower_class) {
                    frame.verse_number = true;
                } else if lower_class.contains("noteref") || lower_class.contains("footnoteref") {
                    if self.in_note_body() {
                        // The marker repeated at the head of its body is
                        // the note's label, not a reference.
                        frame.note_label = true;
                    } else if !self.in_note_ref() {
                        frame.note_ref = Some(NoteTarget::Ordinal);
                    }
                }
            }
            "h1" | "h2" | "h3" | "h4" | "h5" | "h6" => {
                self.flush_paragraph(ParagraphStyle::Body);
                frame.block = Some(BlockKind::Heading(name.as_bytes()[1] - b'0'));
            }
            "p" => {
                self.flush_paragraph(ParagraphStyle::Body);
                let style = if lower_class.contains("quote") {
                    ParagraphStyle::Quote
                } else if let Some(indent) = poetry_indent(&lower_class) {
                    ParagraphStyle::Poetry { indent }
                } else if lower_class.contains("caption") {
                    ParagraphStyle::Caption
                } else {
                    ParagraphStyle::Body
                };
                frame.block = Some(BlockKind::Paragraph(style));
            }
            "blockquote" => {
                self.flush_paragraph(ParagraphStyle::Body);
                frame.block = Some(BlockKind::Paragraph(ParagraphStyle::Quote));
            }
            "pre" => {
                self.flush_paragraph(ParagraphStyle::Body);
                frame.style.monospace = true;
                frame.block = Some(BlockKind::Paragraph(ParagraphStyle::Body));
            }
            "ol" | "ul" => {
                self.flush_paragraph(ParagraphStyle::Body);
                self.lists.push(ListBuilder {
                    ordered: name == "ol",
                    items: Vec::new(),
                });
                frame.block = Some(BlockKind::List {
                    ordered: name == "ol",
                });
            }
            "li" => {
                self.flush_paragraph(ParagraphStyle::Body);
                self.sinks.push(Sink { blocks: Vec::new() });
                frame.block = Some(BlockKind::ListItem);
            }
            "table" => {
                self.flush_paragraph(ParagraphStyle::Body);
                self.tables.push(TableBuilder {
                    header_rows: 0,
                    rows: Vec::new(),
                    current_row: None,
                });
                frame.block = Some(BlockKind::Table);
            }
            "tr" => {
                if let Some(t) = self.tables.last_mut() {
                    t.current_row = Some((false, Vec::new()));
                }
                frame.block = Some(BlockKind::TableRow { header: false });
            }
            "td" | "th" => {
                if name == "th"
                    && let Some(t) = self.tables.last_mut()
                    && let Some(row) = t.current_row.as_mut()
                {
                    row.0 = true;
                }
                self.cell = Some(Vec::new());
                frame.block = Some(BlockKind::TableCell);
            }
            "figure" => {
                self.flush_paragraph(ParagraphStyle::Body);
                frame.block = Some(BlockKind::Figure);
            }
            "figcaption" => {
                frame.block = Some(BlockKind::Paragraph(ParagraphStyle::Caption));
            }
            "div" | "section" | "aside" | "footer" => {
                let is_note = epub_type.contains("footnote")
                    || epub_type.contains("endnote")
                    || epub_type == "note"
                    || (lower_class.split_whitespace().any(|c| {
                        c == "note" || c == "footnote" || c == "fn" || c.ends_with("-note")
                    }) && !lower_class.contains("container"));
                let inside_note = self.frames.iter().any(|f| f.note_body.is_some());
                if is_note && !inside_note {
                    self.flush_paragraph(ParagraphStyle::Body);
                    self.sinks.push(Sink { blocks: Vec::new() });
                    frame.note_body = Some(id.clone().unwrap_or_default());
                    frame.block = Some(BlockKind::Note);
                } else if lower_class.contains("nav") || lower_class.contains("chapnav") {
                    frame.block = Some(BlockKind::Nav);
                    frame.skip = true;
                }
            }
            _ => {}
        }
        if name == "p"
            && (lower_class
                .split_whitespace()
                .any(|c| c == "note" || c == "footnote" || c == "fn")
                || epub_type.contains("footnote"))
            && !self.frames.iter().any(|f| f.note_body.is_some())
        {
            // A note body given as a paragraph: collect it out of the flow.
            frame.block = Some(BlockKind::Note);
            self.sinks.push(Sink { blocks: Vec::new() });
            frame.note_body = Some(id.unwrap_or_default());
        }
        self.frames.push(frame);
    }

    fn text(&mut self, text: &str) {
        if self.skipping() || text.is_empty() {
            return;
        }
        if self.in_verse_number() {
            let digits: String = text.chars().filter(|c| c.is_ascii_digit()).collect();
            if let Ok(n) = digits.parse::<u16>()
                && n > 0
            {
                self.inlines.push(Inline::VerseNumber(n));
            }
            return;
        }
        if self.in_note_ref() {
            return;
        }
        if self.frames.iter().any(|f| f.note_label) {
            let label = text.trim();
            if !label.is_empty()
                && let Some(body) = self.frames.iter_mut().rev().find(|f| f.note_body.is_some())
                && body.note_label_text.is_empty()
            {
                body.note_label_text = label.to_string();
            }
            return;
        }
        let style = self.current_style();
        if let Some(cell) = self.cell.as_mut() {
            push_text(cell, text, style);
            return;
        }
        if self.in_link {
            self.link_chars += text.trim().chars().count();
        } else {
            self.other_chars += text.trim().chars().count();
        }
        push_text(&mut self.inlines, text, style);
        self.inline_block_open = true;
    }

    fn close(&mut self, name: &str) {
        let Some(pos) = self.frames.iter().rposition(|f| f.name == name) else {
            return;
        };
        let frame = self.frames.remove(pos);
        if let Some(target) = frame.note_ref {
            self.place_note_ref(target);
        }
        if name == "a" {
            self.in_link = false;
        }
        match frame.block {
            Some(BlockKind::Heading(level)) => {
                let mut inlines = std::mem::take(&mut self.inlines);
                normalize_whitespace(&mut inlines);
                self.reset_link_stats();
                if !inlines.is_empty() {
                    self.emit(Block::Heading { level, inlines });
                }
            }
            Some(BlockKind::Paragraph(style)) => self.flush_paragraph(style),
            Some(BlockKind::List { .. }) => {
                self.flush_paragraph(ParagraphStyle::Body);
                if let Some(list) = self.lists.pop() {
                    self.emit(Block::List {
                        ordered: list.ordered,
                        items: list.items,
                    });
                }
            }
            Some(BlockKind::ListItem) => {
                self.flush_paragraph(ParagraphStyle::Body);
                let sink = self.sinks.pop().unwrap_or(Sink { blocks: Vec::new() });
                if let Some(list) = self.lists.last_mut() {
                    list.items.push(sink.blocks);
                }
            }
            Some(BlockKind::Table) => {
                if let Some(table) = self.tables.pop()
                    && !table.rows.is_empty()
                {
                    self.emit(Block::Table {
                        header_rows: table.header_rows,
                        rows: table.rows,
                    });
                }
            }
            Some(BlockKind::TableRow { .. }) => {
                if let Some(table) = self.tables.last_mut()
                    && let Some((header, cells)) = table.current_row.take()
                {
                    if header && table.rows.len() == table.header_rows as usize {
                        table.header_rows += 1;
                    }
                    table.rows.push(cells);
                }
            }
            Some(BlockKind::TableCell) => {
                if let Some(mut cell) = self.cell.take() {
                    normalize_whitespace(&mut cell);
                    if let Some(table) = self.tables.last_mut()
                        && let Some(row) = table.current_row.as_mut()
                    {
                        row.1.push(cell);
                    }
                }
            }
            Some(BlockKind::Figure) => {
                self.flush_paragraph(ParagraphStyle::Body);
            }
            Some(BlockKind::Note) => {
                self.flush_paragraph(ParagraphStyle::Body);
                let sink = self.sinks.pop().unwrap_or(Sink { blocks: Vec::new() });
                let id = frame.note_body.filter(|id| !id.is_empty());
                self.note_bodies
                    .push((id, sink.blocks, frame.note_label_text));
            }
            Some(BlockKind::Nav) | None => {}
        }
    }

    fn place_note_ref(&mut self, target: NoteTarget) {
        if self.skipping() {
            return;
        }
        let index = self.doc.notes.len();
        self.doc.notes.push(Note::default());
        self.note_refs.push((index, target));
        if let Some(cell) = self.cell.as_mut() {
            cell.push(Inline::NoteRef(index));
        } else {
            self.inlines.push(Inline::NoteRef(index));
        }
    }

    fn flush_paragraph(&mut self, style: ParagraphStyle) {
        let mut inlines = std::mem::take(&mut self.inlines);
        normalize_whitespace(&mut inlines);
        let nav_only = self.other_chars == 0 && self.link_chars > 0;
        self.reset_link_stats();
        self.inline_block_open = false;
        if inlines.is_empty() || nav_only {
            return;
        }
        // A caption paragraph right after a figure belongs to it.
        if style == ParagraphStyle::Caption
            && let Some(Block::Figure { caption, .. }) =
                self.sinks.last_mut().and_then(|s| s.blocks.last_mut())
            && caption.is_empty()
        {
            *caption = inlines;
            return;
        }
        self.emit(Block::Paragraph { style, inlines });
    }

    fn reset_link_stats(&mut self) {
        self.link_chars = 0;
        self.other_chars = 0;
    }

    fn emit(&mut self, block: Block) {
        if let Some(sink) = self.sinks.last_mut() {
            sink.blocks.push(block);
        }
    }

    /// After a file: bind note markers to bodies and load image bytes.
    fn finish<R: Read + Seek>(mut self, zip: &mut zip::ZipArchive<R>, package: &Package) {
        let mut bodies = std::mem::take(&mut self.note_bodies);
        let refs = std::mem::take(&mut self.note_refs);
        // By id first, then by order among the unmatched.
        let mut used = vec![false; bodies.len()];
        let mut unmatched_refs = Vec::new();
        for (index, target) in refs {
            match target {
                NoteTarget::Id(id) => {
                    if let Some(pos) = bodies
                        .iter()
                        .position(|(bid, _, _)| bid.as_deref() == Some(id.as_str()))
                    {
                        used[pos] = true;
                        self.doc.notes[index].label = if bodies[pos].2.is_empty() {
                            id
                        } else {
                            bodies[pos].2.clone()
                        };
                        self.doc.notes[index].blocks = std::mem::take(&mut bodies[pos].1);
                    } else {
                        unmatched_refs.push(index);
                    }
                }
                NoteTarget::Ordinal => unmatched_refs.push(index),
            }
        }
        let mut free = (0..bodies.len())
            .filter(|&i| !used[i])
            .collect::<Vec<_>>()
            .into_iter();
        for index in unmatched_refs {
            if let Some(pos) = free.next() {
                used[pos] = true;
                self.doc.notes[index].blocks = std::mem::take(&mut bodies[pos].1);
                self.doc.notes[index].label = if bodies[pos].2.is_empty() {
                    bodies[pos].0.clone().unwrap_or_default()
                } else {
                    bodies[pos].2.clone()
                };
            }
        }
        // Bodies nobody pointed at stay as notes without a marker: a
        // Bible's chapter-end notes locate themselves by "(chapter,verse)"
        // in their text, which interpretation binds later.
        for (pos, (id, blocks, label)) in bodies.into_iter().enumerate() {
            if used[pos] || blocks.is_empty() {
                continue;
            }
            self.doc.notes.push(Note {
                label: if label.is_empty() {
                    id.unwrap_or_default()
                } else {
                    label
                },
                blocks,
            });
        }
        // Strip a leading label ("1 ", "1. ", "[]") from note bodies that
        // repeat their marker.
        for note in self.doc.notes.iter_mut() {
            strip_leading_label(note);
        }
        let file_blocks = std::mem::take(&mut self.sinks[0].blocks);
        self.doc.blocks.extend(file_blocks);
        for (index, path) in std::mem::take(&mut self.pending_images) {
            if let Some(data) = read_bytes(zip, &path) {
                let media_type = package
                    .manifest
                    .values()
                    .find(|item| path.ends_with(&item.href))
                    .map(|item| item.media_type.clone())
                    .filter(|m| m.starts_with("image/"))
                    .unwrap_or_else(|| media_type_of(&path).to_string());
                let (width, height) = image_size(&data, &media_type).unwrap_or((0, 0));
                self.doc.images[index] = ImageAsset {
                    media_type,
                    data,
                    width,
                    height,
                };
            }
        }
    }
}

fn strip_leading_label(note: &mut Note) {
    let Some(Block::Paragraph { inlines, .. }) = note.blocks.first_mut() else {
        return;
    };
    let Some(Inline::Text { text, .. }) = inlines.first_mut() else {
        return;
    };
    // "[label]" or "[]" around a back-link the walker emptied.
    if text.starts_with('[')
        && let Some(close) = text.find(']')
        && close <= 4
    {
        let inner = text[1..close].trim().to_string();
        if note.label.is_empty() && !inner.is_empty() {
            note.label = inner;
        }
        *text = text[close + 1..].trim_start().to_string();
    }
    let digits = text.chars().take_while(|c| c.is_ascii_digit()).count();
    if digits == 0 || digits > 3 {
        return;
    }
    let rest = &text[digits..];
    let after = rest.trim_start_matches(['.', ')', ' ', '\u{a0}']);
    if after.len() == rest.len() {
        return;
    }
    if note.label.is_empty() {
        note.label = text[..digits].to_string();
    }
    *text = after.to_string();
}

fn local(e: &BytesStart) -> String {
    String::from_utf8_lossy(e.local_name().as_ref()).to_ascii_lowercase()
}

fn is_block_tag(name: &str) -> bool {
    matches!(
        name,
        "p" | "div"
            | "h1"
            | "h2"
            | "h3"
            | "h4"
            | "h5"
            | "h6"
            | "ol"
            | "ul"
            | "li"
            | "table"
            | "tr"
            | "td"
            | "th"
            | "blockquote"
            | "section"
            | "aside"
            | "figure"
            | "pre"
    )
}

fn is_verse_class(class: &str) -> bool {
    class.split_whitespace().any(|c| {
        c.starts_with("vers")
            || c == "vn"
            || c == "v"
            || c.contains("verse-num")
            || c.contains("versenum")
    })
}

fn poetry_indent(class: &str) -> Option<u8> {
    for c in class.split_whitespace() {
        if let Some(rest) = c.strip_prefix("poline") {
            return Some(rest.parse().unwrap_or(1));
        }
        if c == "q" || c == "q1" || c == "poetry" {
            return Some(1);
        }
        if c == "q2" {
            return Some(2);
        }
    }
    None
}

fn media_type_of(path: &str) -> &'static str {
    let lower = path.to_ascii_lowercase();
    if lower.ends_with(".png") {
        "image/png"
    } else if lower.ends_with(".jpg") || lower.ends_with(".jpeg") {
        "image/jpeg"
    } else if lower.ends_with(".gif") {
        "image/gif"
    } else if lower.ends_with(".svg") {
        "image/svg+xml"
    } else {
        "application/octet-stream"
    }
}

/// Pixel size from PNG or JPEG headers; None for other formats.
pub fn image_size(data: &[u8], media_type: &str) -> Option<(u32, u32)> {
    if media_type == "image/png" && data.len() >= 24 && &data[..8] == b"\x89PNG\r\n\x1a\n" {
        let w = u32::from_be_bytes([data[16], data[17], data[18], data[19]]);
        let h = u32::from_be_bytes([data[20], data[21], data[22], data[23]]);
        return Some((w, h));
    }
    if media_type == "image/jpeg" && data.len() > 4 && data[0] == 0xFF && data[1] == 0xD8 {
        let mut i = 2;
        while i + 9 < data.len() {
            if data[i] != 0xFF {
                i += 1;
                continue;
            }
            let marker = data[i + 1];
            if marker == 0xD8 || (0xD0..=0xD7).contains(&marker) || marker == 0x01 || marker == 0xFF
            {
                i += 2;
                continue;
            }
            let len = u16::from_be_bytes([data[i + 2], data[i + 3]]) as usize;
            if matches!(marker, 0xC0..=0xC3 | 0xC5..=0xC7 | 0xC9..=0xCB | 0xCD..=0xCF) {
                let h = u16::from_be_bytes([data[i + 5], data[i + 6]]) as u32;
                let w = u16::from_be_bytes([data[i + 7], data[i + 8]]) as u32;
                return Some((w, h));
            }
            i += 2 + len;
        }
    }
    None
}
