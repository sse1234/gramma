//! Text shaping via rustybuzz (a HarfBuzz port): real glyph advances from a
//! bundled font, in integer font units, feeding the breaker deterministically
//! on every platform.

use rustybuzz::{Face, UnicodeBuffer};

use super::Scaled;
use super::paragraph::TextMeasure;

pub struct FontMeasure<'a> {
    face: Face<'a>,
    space_width: Scaled,
    hyphen_width: Scaled,
}

impl<'a> FontMeasure<'a> {
    pub fn new(font_data: &'a [u8]) -> Option<Self> {
        let face = Face::from_slice(font_data, 0)?;
        let mut measure = FontMeasure {
            face,
            space_width: 0,
            hyphen_width: 0,
        };
        measure.space_width = measure.shape_width(" ");
        measure.hyphen_width = measure.shape_width("-");
        Some(measure)
    }

    pub fn units_per_em(&self) -> u16 {
        self.face.units_per_em() as u16
    }

    fn shape_width(&self, text: &str) -> Scaled {
        let mut buffer = UnicodeBuffer::new();
        buffer.push_str(text);
        let glyphs = rustybuzz::shape(&self.face, &[], buffer);
        glyphs
            .glyph_positions()
            .iter()
            .map(|p| p.x_advance as Scaled)
            .sum()
    }
}

impl TextMeasure for FontMeasure<'_> {
    fn text_width(&self, text: &str) -> Scaled {
        self.shape_width(text)
    }

    /// TeX's interword glue proportions: stretch w/2, shrink w/3.
    fn space(&self) -> (Scaled, Scaled, Scaled) {
        (self.space_width, self.space_width / 2, self.space_width / 3)
    }

    fn hyphen_width(&self) -> Scaled {
        self.hyphen_width
    }
}
