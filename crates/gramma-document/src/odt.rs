//! OpenDocument Text reader (ADR 0029): a word processor's own file,
//! read as it was written. Headings come with their outline level,
//! paragraphs with their inline styles, footnotes with their bodies. A
//! character style named like a verse number ("Verszahl") marks verse
//! numbers; a paragraph style named like a book title ("Buchtitel")
//! marks a book heading. Nothing is inferred from geometry — there is
//! none.

use std::collections::HashMap;
use std::io::{Read, Seek};

use quick_xml::Reader;
use quick_xml::events::{BytesStart, Event};

use super::{
    Block, Document, DocumentError, Inline, Note, ParagraphStyle, Style, normalize_whitespace,
    push_text,
};

const XML: quick_xml::XmlVersion = quick_xml::XmlVersion::Implicit1_0;

/// Read an ODT from any seekable source.
pub fn read(source: impl Read + Seek) -> Result<Document, DocumentError> {
    let mut zip = zip::ZipArchive::new(source)?;
    let mut styles = Styles::default();
    if let Ok(xml) = read_entry(&mut zip, "styles.xml") {
        styles.absorb(&xml)?;
    }
    let content = read_entry(&mut zip, "content.xml")?;
    styles.absorb(&content)?;
    let mut doc = Document {
        language: styles.language.clone(),
        ..Document::default()
    };
    if let Ok(meta) = read_entry(&mut zip, "meta.xml") {
        doc.title = meta_title(&meta).unwrap_or_default();
    }
    let mut walker = Walker {
        styles: &styles,
        doc: &mut doc,
        span_stack: Vec::new(),
        block: None,
        note: None,
        in_citation: false,
        verse_digits: None,
        in_body: false,
    };
    walker.walk(&content)?;
    Ok(doc)
}

fn read_entry<R: Read + Seek>(
    zip: &mut zip::ZipArchive<R>,
    name: &str,
) -> Result<String, DocumentError> {
    let mut entry = zip.by_name(name)?;
    let mut text = String::new();
    entry.read_to_string(&mut text)?;
    Ok(text)
}

fn attr(e: &BytesStart, name: &[u8]) -> Option<String> {
    e.attributes()
        .flatten()
        .find(|a| a.key.local_name().as_ref() == name)
        .and_then(|a| a.normalized_value(XML).ok().map(|v| v.to_string()))
}

/// A qualified attribute, matched on prefix and local name ("fo",
/// "font-weight"), since ODT uses several namespaces with clashing
/// local names (`fo:font-size`, `style:font-size-asian`).
fn qattr(e: &BytesStart, prefix: &[u8], name: &[u8]) -> Option<String> {
    e.attributes().flatten().find_map(|a| {
        let key = a.key;
        let matches =
            key.local_name().as_ref() == name && key.prefix().is_some_and(|p| p.as_ref() == prefix);
        matches.then(|| a.normalized_value(XML).ok().map(|v| v.to_string()))?
    })
}

#[derive(Debug, Clone, Default)]
struct RawStyle {
    parent: Option<String>,
    /// The paragraph style's display name, when it differs.
    display: Option<String>,
    bold: bool,
    italic: bool,
    superscript: bool,
    small_caps: bool,
}

#[derive(Default)]
struct Styles {
    by_name: HashMap<String, RawStyle>,
    language: String,
}

impl Styles {
    /// Collects `style:style` elements from a styles.xml or content.xml.
    fn absorb(&mut self, xml: &str) -> Result<(), DocumentError> {
        let mut reader = Reader::from_str(xml);
        let mut current: Option<(String, RawStyle)> = None;
        loop {
            let event = reader.read_event()?;
            match event {
                Event::Start(ref e) | Event::Empty(ref e)
                    if e.local_name().as_ref() == b"style" =>
                {
                    if let Some(name) = attr(e, b"name") {
                        let raw = RawStyle {
                            parent: attr(e, b"parent-style-name"),
                            display: attr(e, b"display-name"),
                            ..RawStyle::default()
                        };
                        // A style without properties is an empty element:
                        // no end event follows, it is complete here.
                        if matches!(event, Event::Empty(_)) {
                            self.by_name.insert(name, raw);
                        } else {
                            current = Some((name, raw));
                        }
                    }
                }
                Event::Start(ref e) | Event::Empty(ref e)
                    if e.local_name().as_ref() == b"text-properties" =>
                {
                    if let Some(lang) = qattr(e, b"fo", b"language")
                        && self.language.is_empty()
                        && !lang.is_empty()
                        && lang != "none"
                        && lang != "zxx"
                    {
                        self.language = lang;
                    }
                    if let Some((_, raw)) = current.as_mut() {
                        if qattr(e, b"fo", b"font-weight").is_some_and(|w| w == "bold") {
                            raw.bold = true;
                        }
                        if qattr(e, b"fo", b"font-style").is_some_and(|w| w == "italic") {
                            raw.italic = true;
                        }
                        if qattr(e, b"style", b"text-position")
                            .is_some_and(|p| p.starts_with("super"))
                        {
                            raw.superscript = true;
                        }
                        if qattr(e, b"fo", b"font-variant").is_some_and(|v| v == "small-caps") {
                            raw.small_caps = true;
                        }
                    }
                }
                Event::End(ref e) if e.local_name().as_ref() == b"style" => {
                    if let Some((name, raw)) = current.take() {
                        self.by_name.insert(name, raw);
                    }
                }
                Event::Eof => break,
                _ => {}
            }
        }
        Ok(())
    }

    /// The style's ancestry, itself first: automatic styles derive from
    /// named ones, which derive from each other.
    fn chain<'s>(&'s self, name: &'s str) -> Vec<&'s str> {
        let mut out = Vec::new();
        let mut cursor: Option<&'s str> = Some(name);
        while let Some(n) = cursor
            && out.len() < 8
        {
            out.push(n);
            cursor = self.by_name.get(n).and_then(|r| r.parent.as_deref());
        }
        out
    }

    fn resolve(&self, name: &str) -> Style {
        let mut style = Style::PLAIN;
        for n in self.chain(name) {
            if let Some(raw) = self.by_name.get(n) {
                style.bold |= raw.bold;
                style.italic |= raw.italic;
                style.superscript |= raw.superscript;
                style.small_caps |= raw.small_caps;
            }
        }
        style
    }

    /// Whether the style or one of its ancestors is named (or displayed)
    /// like `role`, case-insensitively: "Verszahl", "Buchtitel".
    fn named(&self, name: &str, role: &str) -> bool {
        self.chain(name).iter().any(|n| {
            let display = self
                .by_name
                .get(*n)
                .and_then(|r| r.display.as_deref())
                .unwrap_or(n);
            n.eq_ignore_ascii_case(role) || display.eq_ignore_ascii_case(role)
        })
    }
}

fn meta_title(xml: &str) -> Option<String> {
    let mut reader = Reader::from_str(xml);
    let mut capture = false;
    let mut title = String::new();
    loop {
        match reader.read_event().ok()? {
            Event::Start(e) if e.local_name().as_ref() == b"title" => capture = true,
            Event::End(e) if e.local_name().as_ref() == b"title" => break,
            Event::Text(t) if capture => title.push_str(&t.xml_content(XML).ok()?),
            Event::Eof => break,
            _ => {}
        }
    }
    let title = title.trim().to_string();
    (!title.is_empty()).then_some(title)
}

struct Walker<'a> {
    styles: &'a Styles,
    doc: &'a mut Document,
    /// Inline styles of the open spans, innermost last.
    span_stack: Vec<Style>,
    /// The block under construction: a heading with its level, or a
    /// paragraph with its style.
    block: Option<(Option<u8>, ParagraphStyle, Vec<Inline>)>,
    /// A footnote under construction: its label (the citation) and body.
    note: Option<(String, Vec<Inline>)>,
    /// Inside the note's citation, whose text is the label.
    in_citation: bool,
    /// Digits of a verse number span under construction.
    verse_digits: Option<String>,
    in_body: bool,
}

impl Walker<'_> {
    fn walk(&mut self, xml: &str) -> Result<(), DocumentError> {
        let mut reader = Reader::from_str(xml);
        loop {
            match reader.read_event()? {
                Event::Start(e) => self.start(&e),
                Event::Empty(e) => self.empty(&e),
                Event::End(e) => self.end(e.local_name().as_ref()),
                Event::Text(t) => {
                    let text = t.xml_content(XML).map_err(quick_xml::Error::from)?;
                    self.text(&text);
                }
                Event::Eof => break,
                _ => {}
            }
        }
        Ok(())
    }

    fn current_style(&self) -> Style {
        self.span_stack.last().copied().unwrap_or(Style::PLAIN)
    }

    fn inlines(&mut self) -> Option<&mut Vec<Inline>> {
        if let Some((_, inlines)) = self.note.as_mut() {
            return Some(inlines);
        }
        self.block.as_mut().map(|(_, _, inlines)| inlines)
    }

    fn text(&mut self, text: &str) {
        if !self.in_body {
            return;
        }
        if let Some(digits) = self.verse_digits.as_mut() {
            digits.push_str(text);
            return;
        }
        if self.in_citation {
            if let Some((label, _)) = self.note.as_mut() {
                label.push_str(text.trim());
            }
            return;
        }
        let style = self.current_style();
        if let Some(inlines) = self.inlines() {
            push_text(inlines, text, style);
        }
    }

    fn start(&mut self, e: &BytesStart) {
        match e.local_name().as_ref() {
            b"body" => self.in_body = true,
            b"h" if self.in_body => {
                self.flush();
                let level = attr(e, b"outline-level")
                    .and_then(|l| l.parse::<u8>().ok())
                    .unwrap_or(1);
                self.block = Some((Some(level), ParagraphStyle::Body, Vec::new()));
            }
            b"p" if self.in_body => {
                if self.note.is_some() {
                    // A note body's paragraphs run on inside the note.
                    if let Some((_, inlines)) = self.note.as_mut()
                        && !inlines.is_empty()
                    {
                        inlines.push(Inline::LineBreak);
                    }
                    return;
                }
                self.flush();
                let name = attr(e, b"style-name").unwrap_or_default();
                let heading = self.styles.named(&name, "Buchtitel").then_some(2);
                self.block = Some((heading, ParagraphStyle::Body, Vec::new()));
            }
            b"span" if self.in_body => {
                let name = attr(e, b"style-name").unwrap_or_default();
                let mut style = self.current_style();
                let own = self.styles.resolve(&name);
                style.bold |= own.bold;
                style.italic |= own.italic;
                style.superscript |= own.superscript;
                style.small_caps |= own.small_caps;
                self.span_stack.push(style);
                if self.styles.named(&name, "Verszahl") && self.note.is_none() {
                    self.verse_digits = Some(String::new());
                }
            }
            b"note" if self.in_body => self.note = Some((String::new(), Vec::new())),
            b"note-citation" => self.in_citation = true,
            _ => {}
        }
    }

    fn empty(&mut self, e: &BytesStart) {
        if !self.in_body {
            return;
        }
        match e.local_name().as_ref() {
            b"s" => {
                let n = attr(e, b"c")
                    .and_then(|c| c.parse::<usize>().ok())
                    .unwrap_or(1);
                let spaces = " ".repeat(n);
                self.text(&spaces);
            }
            b"tab" => self.text(" "),
            b"line-break" => {
                if let Some(inlines) = self.inlines() {
                    inlines.push(Inline::LineBreak);
                }
            }
            _ => {}
        }
    }

    fn end(&mut self, name: &[u8]) {
        match name {
            b"body" => {
                self.flush();
                self.in_body = false;
            }
            b"h" if self.in_body => self.flush(),
            b"p" if self.in_body && self.note.is_none() => self.flush(),
            b"span" if self.in_body => {
                self.span_stack.pop();
                if let Some(digits) = self.verse_digits.take() {
                    let number: String = digits.chars().filter(|c| c.is_ascii_digit()).collect();
                    match number.parse::<u16>() {
                        Ok(n) if n > 0 => {
                            if let Some(inlines) = self.inlines() {
                                inlines.push(Inline::VerseNumber(n));
                            }
                        }
                        _ => {
                            let style = self.current_style();
                            if let Some(inlines) = self.inlines() {
                                push_text(inlines, &digits, style);
                            }
                        }
                    }
                }
            }
            b"note-citation" => self.in_citation = false,
            b"note" if self.in_body => {
                if let Some((label, mut inlines)) = self.note.take() {
                    normalize_whitespace(&mut inlines);
                    let index = self.doc.notes.len();
                    self.doc.notes.push(Note {
                        label,
                        blocks: vec![Block::Paragraph {
                            style: ParagraphStyle::Body,
                            inlines,
                        }],
                    });
                    if let Some(inlines) = self.inlines() {
                        inlines.push(Inline::NoteRef(index));
                    }
                }
            }
            _ => {}
        }
    }

    /// Closes the block under construction.
    fn flush(&mut self) {
        let Some((heading, style, mut inlines)) = self.block.take() else {
            return;
        };
        normalize_whitespace(&mut inlines);
        if inlines.is_empty() {
            return;
        }
        let block = match heading {
            Some(level) => Block::Heading { level, inlines },
            None => Block::Paragraph { style, inlines },
        };
        self.doc.blocks.push(block);
    }
}
