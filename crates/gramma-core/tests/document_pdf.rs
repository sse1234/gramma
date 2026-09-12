//! PDF reading (ADR 0029) end to end on a hand-built file: standard
//! fonts without ToUnicode decode through the base encoding, positions
//! follow the text matrix, font roles come from names, and encrypted
//! files are refused.

use gramma_core::document::pdf;
use gramma_core::document::{Block, DocumentError, Inline, plain_text};

/// A one-page PDF with Helvetica (F1) and Helvetica-Bold (F2); `ops` is
/// the page's content stream.
fn build_pdf(ops: &str) -> Vec<u8> {
    let objects = [
        "<< /Type /Catalog /Pages 2 0 R >>".to_string(),
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>".to_string(),
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 400 600] /Contents 4 0 R /Resources << /Font << /F1 5 0 R /F2 6 0 R >> >> >>"
            .to_string(),
        format!("<< /Length {} >>\nstream\n{ops}\nendstream", ops.len()),
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>".to_string(),
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>".to_string(),
    ];
    let mut out = String::from("%PDF-1.4\n");
    let mut offsets = Vec::new();
    for (i, body) in objects.iter().enumerate() {
        offsets.push(out.len());
        out.push_str(&format!("{} 0 obj\n{body}\nendobj\n", i + 1));
    }
    let xref = out.len();
    out.push_str(&format!(
        "xref\n0 {}\n0000000000 65535 f \n",
        objects.len() + 1
    ));
    for off in offsets {
        out.push_str(&format!("{off:010} 00000 n \n"));
    }
    out.push_str(&format!(
        "trailer\n<< /Size {} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n",
        objects.len() + 1
    ));
    out.into_bytes()
}

#[test]
fn reads_text_lines_with_fonts_and_positions() {
    let ops = "BT /F2 14 Tf 1 0 0 1 50 550 Tm (Ein Titel) Tj ET\n\
               BT /F1 10 Tf 1 0 0 1 50 520 Tm (Erste Zeile des Absatzes, die bis zum Rand des Satzspiegels reicht) Tj \
               0 -13 Td (und in der zweiten Zeile endet.) Tj ET\n\
               BT /F1 10 Tf 1 0 0 1 200 30 Tm (7) Tj ET";
    let doc = pdf::read(build_pdf(ops)).unwrap();
    assert_eq!(doc.blocks.len(), 2, "{:#?}", doc.blocks);
    assert!(
        matches!(&doc.blocks[0], Block::Heading { level: 1, inlines } if plain_text(inlines) == "Ein Titel")
    );
    let Block::Paragraph { inlines, .. } = &doc.blocks[1] else {
        panic!()
    };
    assert_eq!(
        plain_text(inlines),
        "Erste Zeile des Absatzes, die bis zum Rand des Satzspiegels reicht und in der zweiten Zeile endet."
    );
    assert!(matches!(&inlines[0], Inline::Text { style, .. } if style.is_plain()));
}

#[test]
fn text_matrix_scaling_and_adjusted_spacing() {
    // Size in the matrix (Tf 1 with Tm scale 10), a TJ array whose large
    // negative adjustment stands for a space, and WinAnsi umlauts.
    let ops = "BT /F1 1 Tf 10 0 0 10 50 500 Tm [(Gr) -20 (\\374\\337e) -300 (dich)] TJ ET";
    let doc = pdf::read(build_pdf(ops)).unwrap();
    let Block::Paragraph { inlines, .. } = &doc.blocks[0] else {
        panic!("{:#?}", doc.blocks)
    };
    assert_eq!(plain_text(inlines), "Grüße dich");
}

#[test]
fn encrypted_files_are_refused() {
    let mut pdf = build_pdf("BT /F1 10 Tf (x) Tj ET");
    // Splice an /Encrypt entry into the trailer: the reader must refuse
    // rather than attempt anything.
    let text = String::from_utf8(pdf.clone()).unwrap();
    let patched = text.replace(
        "/Root 1 0 R",
        "/Root 1 0 R /Encrypt << /Filter /Standard /V 1 /R 2 /O (x) /U (y) /P -1 >>",
    );
    pdf = patched.into_bytes();
    let err = pdf::read(pdf).unwrap_err();
    assert!(
        matches!(err, DocumentError::Protected(_) | DocumentError::Pdf(_)),
        "{err:?}"
    );
}
