//! PDF reader (ADR 0029): the text layer as positioned fragments per
//! page, images as placed assets, then block inference over the lines.
//! Pure Rust (`pdf` crate); no structure tree is assumed — publisher
//! exports rarely carry one — so structure comes from layout.

use std::collections::HashMap;
use std::sync::Arc;

use pdf::content::{Op, TextDrawAdjusted};
use pdf::file::FileOptions;
use pdf::font::{Font, FontData, ToUnicodeMap};
use pdf::object::{Resolve, XObject};

use super::infer::{self, InferOptions};
use super::{Document, DocumentError, ImageAsset};

/// One run of text drawn at a position, in page points (origin bottom
/// left, as PDF has it).
#[derive(Debug, Clone, PartialEq)]
pub struct Fragment {
    pub x: f32,
    pub y: f32,
    /// Effective font size in points.
    pub size: f32,
    pub font: FontRole,
    pub text: String,
    /// Approximate advance width in points (glyph metrics when the
    /// font carries them, else an estimate).
    pub width: f32,
    /// Text rise above the baseline (superscripts).
    pub rise: f32,
}

/// What a font says about its role, from its name and descriptor.
#[derive(Debug, Clone, PartialEq, Eq, Hash, Default)]
pub struct FontRole {
    pub name: String,
    pub bold: bool,
    pub italic: bool,
    pub monospace: bool,
}

/// An image drawn on a page, with its placement in page points.
#[derive(Debug, Clone, PartialEq)]
pub struct PlacedImage {
    pub x: f32,
    pub y: f32,
    pub width: f32,
    pub height: f32,
    pub asset: Option<ImageAsset>,
}

#[derive(Debug, Clone, Default, PartialEq)]
pub struct PageText {
    pub width: f32,
    pub height: f32,
    pub fragments: Vec<Fragment>,
    pub images: Vec<PlacedImage>,
}

/// Read the whole file into a document.
pub fn read(data: Vec<u8>) -> Result<Document, DocumentError> {
    let (pages, title) = read_pages(data)?;
    let mut doc = infer::document_from_pages(&pages, &InferOptions::default());
    if doc.title.is_empty() {
        doc.title = title;
    }
    Ok(doc)
}

/// The text layer and images of every page, plus the document title.
pub fn read_pages(data: Vec<u8>) -> Result<(Vec<PageText>, String), DocumentError> {
    let file = FileOptions::cached().load(data).map_err(|e| match e {
        pdf::PdfError::InvalidPassword => DocumentError::Protected(
            "this PDF is encrypted; gramma opens only files you can open without a password".into(),
        ),
        other => DocumentError::Pdf(other.to_string()),
    })?;
    let resolver = file.resolver();
    let title = file
        .trailer
        .info_dict
        .as_ref()
        .and_then(|info| info.title.as_ref())
        .map(|t| t.to_string_lossy())
        .unwrap_or_default();
    let mut pages = Vec::new();
    let mut font_cache: HashMap<String, Arc<LoadedFont>> = HashMap::new();
    for page in file.pages() {
        let page = page.map_err(|e| DocumentError::Pdf(e.to_string()))?;
        let media = page
            .media_box()
            .map_err(|e| DocumentError::Pdf(e.to_string()))?;
        let mut out = PageText {
            width: media.right - media.left,
            height: media.top - media.bottom,
            ..PageText::default()
        };
        let Some(content) = page.contents.as_ref() else {
            pages.push(out);
            continue;
        };
        let ops = match content.operations(&resolver) {
            Ok(ops) => ops,
            Err(_) => {
                pages.push(out);
                continue;
            }
        };
        let resources = page
            .resources()
            .map_err(|e| DocumentError::Pdf(e.to_string()))?;
        let mut fonts: HashMap<String, Arc<LoadedFont>> = HashMap::new();
        for (name, font_ref) in resources.fonts.iter() {
            let key = format!("{font_ref:?}");
            let loaded = match font_cache.get(&key) {
                Some(f) => f.clone(),
                None => {
                    let Ok(font) = font_ref.load(&resolver) else {
                        continue;
                    };
                    let loaded = Arc::new(LoadedFont::new(&font, &resolver));
                    font_cache.insert(key, loaded.clone());
                    loaded
                }
            };
            fonts.insert(name.as_str().to_string(), loaded);
        }
        let mut state = TextState::default();
        let mut ctm = IDENTITY;
        let mut stack: Vec<[f32; 6]> = Vec::new();
        for op in ops {
            match op {
                Op::Save => stack.push(ctm),
                Op::Restore => {
                    if let Some(m) = stack.pop() {
                        ctm = m;
                    }
                }
                Op::Transform { matrix } => {
                    ctm = mul(
                        &[matrix.a, matrix.b, matrix.c, matrix.d, matrix.e, matrix.f],
                        &ctm,
                    );
                }
                Op::BeginText => {
                    state.tm = IDENTITY;
                    state.tlm = IDENTITY;
                }
                Op::TextFont { name, size } => {
                    state.font = fonts.get(name.as_str()).cloned();
                    state.size = size;
                }
                Op::Leading { leading } => state.leading = leading,
                Op::TextRise { rise } => state.rise = rise,
                Op::CharSpacing { char_space } => state.char_space = char_space,
                Op::WordSpacing { word_space } => state.word_space = word_space,
                Op::TextScaling { horiz_scale } => state.hscale = horiz_scale / 100.0,
                Op::SetTextMatrix { matrix } => {
                    state.tlm = [matrix.a, matrix.b, matrix.c, matrix.d, matrix.e, matrix.f];
                    state.tm = state.tlm;
                }
                Op::MoveTextPosition { translation } => {
                    state.tlm = mul(
                        &[1.0, 0.0, 0.0, 1.0, translation.x, translation.y],
                        &state.tlm,
                    );
                    state.tm = state.tlm;
                }
                Op::TextNewline => {
                    state.tlm = mul(&[1.0, 0.0, 0.0, 1.0, 0.0, -state.leading], &state.tlm);
                    state.tm = state.tlm;
                }
                Op::TextDraw { text } => {
                    state.draw(&text.data, &ctm, &mut out.fragments);
                }
                Op::TextDrawAdjusted { array } => {
                    for item in array {
                        match item {
                            TextDrawAdjusted::Text(t) => {
                                state.draw(&t.data, &ctm, &mut out.fragments)
                            }
                            TextDrawAdjusted::Spacing(adjust) => {
                                // Thousandths of text space; a large negative
                                // adjustment is a gap the producer used as a
                                // space.
                                let tx = -adjust / 1000.0 * state.size * state.hscale;
                                if adjust < -180.0 {
                                    state.pending_space = true;
                                }
                                state.tm = mul(&[1.0, 0.0, 0.0, 1.0, tx, 0.0], &state.tm);
                            }
                        }
                    }
                }
                Op::XObject { name } => {
                    if let Some(xref) = resources.xobjects.get(name.as_str())
                        && let Ok(xobject) = resolver.get(*xref)
                        && let XObject::Image(image) = &*xobject
                    {
                        // The unit square maps through the CTM.
                        let (x, y) = (ctm[4], ctm[5]);
                        let width = (ctm[0] * ctm[0] + ctm[1] * ctm[1]).sqrt();
                        let height = (ctm[2] * ctm[2] + ctm[3] * ctm[3]).sqrt();
                        let asset = image_asset(image, &resolver);
                        out.images.push(PlacedImage {
                            x,
                            y,
                            width,
                            height,
                            asset,
                        });
                    }
                }
                Op::InlineImage { image } => {
                    let (x, y) = (ctm[4], ctm[5]);
                    let width = (ctm[0] * ctm[0] + ctm[1] * ctm[1]).sqrt();
                    let height = (ctm[2] * ctm[2] + ctm[3] * ctm[3]).sqrt();
                    out.images.push(PlacedImage {
                        x,
                        y,
                        width,
                        height,
                        asset: image_asset(&image, &resolver),
                    });
                }
                _ => {}
            }
        }
        pages.push(out);
    }
    Ok((pages, title))
}

const IDENTITY: [f32; 6] = [1.0, 0.0, 0.0, 1.0, 0.0, 0.0];

fn mul(a: &[f32; 6], b: &[f32; 6]) -> [f32; 6] {
    [
        a[0] * b[0] + a[1] * b[2],
        a[0] * b[1] + a[1] * b[3],
        a[2] * b[0] + a[3] * b[2],
        a[2] * b[1] + a[3] * b[3],
        a[4] * b[0] + a[5] * b[2] + b[4],
        a[4] * b[1] + a[5] * b[3] + b[5],
    ]
}

/// A font with what decoding needs.
struct LoadedFont {
    role: FontRole,
    to_unicode: Option<ToUnicodeMap>,
    two_byte: bool,
    widths: Option<pdf::font::Widths>,
    differences: HashMap<u32, String>,
}

impl LoadedFont {
    fn new(font: &Font, resolver: &impl Resolve) -> Self {
        let name = font
            .name
            .as_ref()
            .map(|n| n.to_string())
            .unwrap_or_default();
        let base = name.split('+').next_back().unwrap_or(&name).to_string();
        let lower = base.to_ascii_lowercase();
        let flags = font_flags(font);
        let role = FontRole {
            bold: lower.contains("bold")
                || lower.contains("semibold")
                || lower.contains("black")
                || lower.contains("heavy")
                || (flags & (1 << 18)) != 0,
            italic: lower.contains("italic")
                || lower.contains("oblique")
                || lower.ends_with("-it")
                || lower.contains("-it,")
                || lower.contains("ital")
                || (flags & (1 << 6)) != 0,
            monospace: lower.contains("mono") || lower.contains("courier") || (flags & 1) != 0,
            name: base,
        };
        let to_unicode = font.to_unicode(resolver).and_then(|r| r.ok());
        let differences = font
            .encoding()
            .map(|e| {
                e.differences
                    .iter()
                    .map(|(code, glyph)| (*code, glyph_to_char(glyph)))
                    .collect()
            })
            .unwrap_or_default();
        LoadedFont {
            role,
            to_unicode,
            two_byte: font.is_cid(),
            widths: font.widths(resolver).ok().flatten(),
            differences,
        }
    }

    /// Decode a string's bytes into text and an advance in text-space
    /// units per 1000.
    fn decode(&self, data: &[u8]) -> (String, f32) {
        let mut out = String::new();
        let mut advance = 0.0;
        let mut i = 0;
        while i < data.len() {
            let (code, len) = if self.two_byte && i + 1 < data.len() {
                (u16::from_be_bytes([data[i], data[i + 1]]) as u32, 2)
            } else {
                (data[i] as u32, 1)
            };
            let mut text: Option<String> = None;
            if let Some(map) = &self.to_unicode
                && let Some(s) = map.get(code as u16)
            {
                text = Some(s.to_string());
            } else if !self.two_byte
                && let Some(map) = &self.to_unicode
                && len == 1
                && i + 1 < data.len()
                && let Some(s) = map.get(u16::from_be_bytes([data[i], data[i + 1]]))
            {
                // Some producers write 2-byte codes for simple fonts.
                out.push_str(s);
                advance += self.width_of(u16::from_be_bytes([data[i], data[i + 1]]) as u32);
                i += 2;
                continue;
            }
            let text = text
                .or_else(|| self.differences.get(&code).cloned())
                .unwrap_or_else(|| {
                    if self.two_byte {
                        String::new()
                    } else {
                        cp1252(code as u8).to_string()
                    }
                });
            out.push_str(&text);
            advance += self.width_of(code);
            i += len;
        }
        (out, advance)
    }

    fn width_of(&self, code: u32) -> f32 {
        match &self.widths {
            Some(w) => {
                let width = w.get(code as usize);
                if width > 0.0 { width } else { 500.0 }
            }
            None => 500.0,
        }
    }
}

fn font_flags(font: &Font) -> u32 {
    match &font.data {
        FontData::Type1(t) | FontData::TrueType(t) => {
            t.font_descriptor.as_ref().map(|d| d.flags).unwrap_or(0)
        }
        FontData::CIDFontType0(c) | FontData::CIDFontType2(c) => c.font_descriptor.flags,
        _ => 0,
    }
}

fn glyph_to_char(glyph: &str) -> String {
    match glyph {
        "space" => " ",
        "quoteright" => "’",
        "quoteleft" => "‘",
        "quotedblleft" => "“",
        "quotedblright" => "”",
        "quotedblbase" => "„",
        "guillemotleft" => "«",
        "guillemotright" => "»",
        "endash" => "–",
        "emdash" => "—",
        "germandbls" => "ß",
        "adieresis" => "ä",
        "odieresis" => "ö",
        "udieresis" => "ü",
        "Adieresis" => "Ä",
        "Odieresis" => "Ö",
        "Udieresis" => "Ü",
        "hyphen" => "-",
        "period" => ".",
        "comma" => ",",
        "colon" => ":",
        "semicolon" => ";",
        "fi" => "ﬁ",
        "fl" => "ﬂ",
        "bullet" => "•",
        "ellipsis" => "…",
        other if other.chars().count() == 1 => other,
        other => {
            if let Some(hex) = other.strip_prefix("uni")
                && let Ok(cp) = u32::from_str_radix(hex, 16)
                && let Some(c) = char::from_u32(cp)
            {
                return c.to_string();
            }
            ""
        }
    }
    .to_string()
}

/// Windows-1252, the base of most simple-font encodings in practice.
fn cp1252(code: u8) -> char {
    const HIGH: [char; 32] = [
        '€', '\u{81}', '‚', 'ƒ', '„', '…', '†', '‡', 'ˆ', '‰', 'Š', '‹', 'Œ', '\u{8d}', 'Ž',
        '\u{8f}', '\u{90}', '‘', '’', '“', '”', '•', '–', '—', '˜', '™', 'š', '›', 'œ', '\u{9d}',
        'ž', 'Ÿ',
    ];
    match code {
        0x80..=0x9f => HIGH[(code - 0x80) as usize],
        _ => code as char,
    }
}

#[derive(Default)]
struct TextState {
    font: Option<Arc<LoadedFont>>,
    size: f32,
    leading: f32,
    rise: f32,
    char_space: f32,
    word_space: f32,
    hscale: f32,
    tm: [f32; 6],
    tlm: [f32; 6],
    pending_space: bool,
}

impl TextState {
    fn draw(&mut self, data: &[u8], ctm: &[f32; 6], out: &mut Vec<Fragment>) {
        let hscale = if self.hscale == 0.0 { 1.0 } else { self.hscale };
        let Some(font) = self.font.clone() else {
            return;
        };
        let (mut text, advance) = font.decode(data);
        if text.is_empty() {
            return;
        }
        if self.pending_space && !text.starts_with(' ') {
            text.insert(0, ' ');
        }
        self.pending_space = false;
        let e = mul(&self.tm, ctm);
        let scale = (e[1] * e[1] + e[3] * e[3]).sqrt();
        let size = self.size * scale;
        let spaces = data.iter().filter(|&&b| b == 32).count() as f32;
        let tx = (advance / 1000.0 * self.size
            + self.char_space * data.len() as f32
            + self.word_space * spaces)
            * hscale;
        let width = tx * scale;
        out.push(Fragment {
            x: e[4],
            y: e[5],
            size,
            font: font.role.clone(),
            text,
            width,
            rise: self.rise * scale,
        });
        self.tm = mul(&[1.0, 0.0, 0.0, 1.0, tx, 0.0], &self.tm);
    }
}

/// JPEG images pass through; raw 8-bit gray/RGB samples become PNG.
fn image_asset(image: &pdf::object::ImageXObject, resolver: &impl Resolve) -> Option<ImageAsset> {
    let (data, filter) = image.raw_image_data(resolver).ok()?;
    let width = image.width;
    let height = image.height;
    match filter {
        Some(pdf::enc::StreamFilter::DCTDecode(_)) => Some(ImageAsset {
            media_type: "image/jpeg".into(),
            data: data.to_vec(),
            width,
            height,
        }),
        None => {
            let bpc = image.bits_per_component.unwrap_or(8);
            let channels = match image.color_space.as_ref() {
                Some(pdf::object::ColorSpace::DeviceRGB) => 3,
                Some(pdf::object::ColorSpace::DeviceGray) | None => 1,
                Some(pdf::object::ColorSpace::Icc(_)) => {
                    let per_row = data.len() / height.max(1) as usize;
                    if per_row == width as usize * 3 {
                        3
                    } else if per_row == width as usize {
                        1
                    } else {
                        return None;
                    }
                }
                _ => return None,
            };
            if bpc != 8 || data.len() < (width * height) as usize * channels {
                return None;
            }
            Some(ImageAsset {
                media_type: "image/png".into(),
                data: encode_png(&data, width, height, channels as u8),
                width,
                height,
            })
        }
        _ => None,
    }
}

/// Minimal PNG encoder for 8-bit gray or RGB samples.
pub fn encode_png(samples: &[u8], width: u32, height: u32, channels: u8) -> Vec<u8> {
    use flate2::Compression;
    use flate2::write::ZlibEncoder;
    use std::io::Write;
    let row = width as usize * channels as usize;
    let mut raw = Vec::with_capacity((row + 1) * height as usize);
    for y in 0..height as usize {
        raw.push(0);
        raw.extend_from_slice(&samples[y * row..(y + 1) * row]);
    }
    let mut encoder = ZlibEncoder::new(Vec::new(), Compression::default());
    encoder.write_all(&raw).expect("in-memory write");
    let compressed = encoder.finish().expect("in-memory finish");
    let mut png = Vec::new();
    png.extend_from_slice(b"\x89PNG\r\n\x1a\n");
    let mut ihdr = Vec::new();
    ihdr.extend_from_slice(&width.to_be_bytes());
    ihdr.extend_from_slice(&height.to_be_bytes());
    ihdr.extend_from_slice(&[8, if channels == 3 { 2 } else { 0 }, 0, 0, 0]);
    chunk(&mut png, b"IHDR", &ihdr);
    chunk(&mut png, b"IDAT", &compressed);
    chunk(&mut png, b"IEND", &[]);
    png
}

fn chunk(out: &mut Vec<u8>, kind: &[u8; 4], data: &[u8]) {
    out.extend_from_slice(&(data.len() as u32).to_be_bytes());
    let start = out.len();
    out.extend_from_slice(kind);
    out.extend_from_slice(data);
    let crc = crc32(&out[start..]);
    out.extend_from_slice(&crc.to_be_bytes());
}

fn crc32(data: &[u8]) -> u32 {
    let mut crc = 0xffff_ffffu32;
    for &b in data {
        crc ^= b as u32;
        for _ in 0..8 {
            crc = if crc & 1 != 0 {
                0xedb8_8320 ^ (crc >> 1)
            } else {
                crc >> 1
            };
        }
    }
    !crc
}
