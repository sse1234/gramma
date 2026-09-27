//! Paragraph structure in OSIS (ADR 0033): `<p>`, `<lg>`/`<l>` and
//! `<milestone type="x-p"/>` flag the verse they open; the writer puts
//! every paragraph back as a `<p>` container, titles between them.

use gramma_osis::osis::{parse, write};

const SOURCE: &str = r#"<?xml version="1.0" encoding="UTF-8"?>
<osis xmlns="http://www.bibletechnologies.net/2003/OSIS/namespace">
  <osisText osisIDWork="Fix" xml:lang="de">
    <header><work osisWork="Fix"><title>Fixtur</title></work></header>
    <div type="book" osisID="Gen">
      <chapter osisID="Gen.1">
        <p>
          <verse osisID="Gen.1.1">Im Anfang schuf Gott die Himmel und die Erde.</verse>
          <verse osisID="Gen.1.2">Die Erde aber war wüst und leer.</verse>
        </p>
        <p>
          <verse osisID="Gen.1.3">Und Gott sprach: Es werde Licht!</verse>
          <verse osisID="Gen.1.4">Und Gott sah, <p>dass das Licht gut war.</p></verse>
          <verse osisID="Gen.1.5"><milestone type="x-p"/>Und Gott nannte das Licht Tag.</verse>
        </p>
        <div type="section"><title>Der zweite Tag</title></div>
        <lg>
          <l><verse osisID="Gen.1.6">Und Gott sprach: Es werde eine Ausdehnung!</verse></l>
          <l><verse osisID="Gen.1.7">Und Gott machte die Ausdehnung.</verse></l>
        </lg>
      </chapter>
      <chapter osisID="Gen.2">
        <verse sID="Gen.2.1" osisID="Gen.2.1"/>So wurden vollendet die Himmel und die Erde.<verse eID="Gen.2.1"/>
        <verse sID="Gen.2.2" osisID="Gen.2.2"/><milestone type="x-p" marker="¶"/>Und Gott vollendete am siebten Tag.<verse eID="Gen.2.2"/>
        <verse sID="Gen.2.3" osisID="Gen.2.3"/>Und Gott segnete den siebten Tag.<verse eID="Gen.2.3"/>
        <lg sID="lg1"/><l sID="l1"/><verse sID="Gen.2.4" osisID="Gen.2.4"/>Dies ist die Geschichte.<verse eID="Gen.2.4"/><l eID="l1"/><lg eID="lg1"/>
      </chapter>
    </div>
  </osisText>
</osis>"#;

fn flags(xml: &str) -> Vec<(u16, u16, bool)> {
    let doc = parse(xml.as_bytes()).unwrap();
    doc.verses
        .iter()
        .map(|v| (v.chapter, v.verse, v.paragraph))
        .collect()
}

#[test]
fn containers_and_milestones_flag_the_verse_they_open() {
    assert_eq!(
        flags(SOURCE),
        vec![
            (1, 1, true),
            (1, 2, false),
            (1, 3, true),
            // A paragraph opening inside a verse's text is one the verse
            // model cannot hold: dropped, and it does not spill over.
            (1, 4, false),
            (1, 5, true),
            (1, 6, true),
            (1, 7, true),
            (2, 1, false),
            (2, 2, true),
            (2, 3, false),
            (2, 4, true),
        ]
    );
}

#[test]
fn the_writer_puts_paragraphs_back_and_the_reader_finds_them_again() {
    let doc = parse(SOURCE.as_bytes()).unwrap();
    let xml = write(&doc);
    // Every chapter opens a paragraph; each flagged verse opens another;
    // the section title stands between paragraphs, not inside one.
    assert_eq!(xml.matches("<p>").count(), 8, "{xml}");
    assert_eq!(xml.matches("</p>").count(), 8, "{xml}");
    assert!(
        xml.contains("</p>\n<div type=\"section\"><title>Der zweite Tag</title></div>\n<p>\n"),
        "{xml}"
    );
    assert!(
        xml.contains("<verse osisID=\"Gen.1.4\">Und Gott sah, dass das Licht gut war.</verse>")
    );
    let again = flags(&xml);
    let mut expected = flags(SOURCE);
    // A chapter's first verse opens its paragraph in the written form.
    expected[7].2 = true;
    assert_eq!(again, expected);
}
