import 'package:flutter_test/flutter_test.dart';
import 'package:gramma/annotations.dart';
import 'package:gramma/src/rust/api/typeset.dart';

RunView _run(int verse, int offset, String text) => RunView(
      text: text,
      x: 0,
      width: 10,
      verseNumber: false,
      noteMarker: false,
      headingLevel: 0,
      verse: verse,
      offset: offset,
    );

void main() {
  final mark = NoteMark(
    id: 'n1',
    module: 'FixDe',
    bookOsis: 'Gen',
    chapter: 1,
    verseStart: 1,
    verseEnd: 2,
    startOffset: 10,
    endOffset: 8,
    colorIndex: 3,
    text: 'Randnotiz',
    created: '2026-08-28T00:00:00Z',
  );

  test('mark encodes and decodes losslessly', () {
    final back = NoteMark.fromJson(
        '{"v":1,"id":"n1","module":"FixDe","book":"Gen","chapter":1,'
        '"verseStart":1,"verseEnd":2,"startOffset":10,"endOffset":8,'
        '"color":3,"text":"Randnotiz","created":"2026-08-28T00:00:00Z"}')!;
    expect(back.osis, 'Gen.1.1-Gen.1.2');
    expect(back.colorIndex, 3);
    expect(NoteMark.fromJson('garbage'), isNull);
  });

  test('origin module covers word-precisely', () {
    // Start verse: words before startOffset are out, at/after are in.
    expect(markCoversRun(mark, _run(1, 0, 'Anfang'), 'FixDe'), isFalse);
    expect(markCoversRun(mark, _run(1, 10, 'schuf'), 'FixDe'), isTrue);
    expect(markCoversRun(mark, _run(1, 30, 'Erde'), 'FixDe'), isTrue);
    // End verse: words past endOffset are out.
    expect(markCoversRun(mark, _run(2, 0, 'Und'), 'FixDe'), isTrue);
    expect(markCoversRun(mark, _run(2, 8, 'wüst'), 'FixDe'), isFalse);
    // Outside the verse range.
    expect(markCoversRun(mark, _run(3, 0, 'Licht'), 'FixDe'), isFalse);
  });

  test('foreign modules cover whole verses', () {
    expect(markCoversRun(mark, _run(1, 0, 'In'), 'KjvTest'), isTrue);
    expect(markCoversRun(mark, _run(2, 99, 'void'), 'KjvTest'), isTrue);
    expect(markCoversRun(mark, _run(3, 0, 'light'), 'KjvTest'), isFalse);
  });

  test('a hyphen-split fragment at the selection edge still covers', () {
    // Run 'Him-' at offset 20 with the real word ending at 26.
    final edge = NoteMark(
      id: 'n2',
      module: 'FixDe',
      bookOsis: 'Gen',
      chapter: 1,
      verseStart: 1,
      verseEnd: 1,
      startOffset: 20,
      endOffset: 26,
      colorIndex: 0,
      text: '',
      created: '',
    );
    expect(markCoversRun(edge, _run(1, 20, 'Him-'), 'FixDe'), isTrue);
    expect(markCoversRun(edge, _run(1, 23, 'mel'), 'FixDe'), isTrue);
    expect(markCoversRun(edge, _run(1, 26, 'und'), 'FixDe'), isFalse);
  });

  test('selections normalize direction and detect the single word', () {
    final a = _run(2, 5, 'Wort,');
    final b = _run(1, 12, 'Anfang');
    final sel = VerseSelection.between(a, b);
    expect((sel.verseStart, sel.verseEnd), (1, 2));
    expect(sel.startOffset, 12);
    expect(sel.endOffset, 5 + 5, reason: 'trailing punctuation counts bytes');
    expect(sel.word, isNull);

    final single = VerseSelection.ofRun(_run(1, 12, 'Anfang,'));
    expect(single.word, 'Anfang');
    expect(VerseSelection.between(a, a).word, 'Wort');

    expect(sel.coversRun(_run(1, 20, 'x')), isTrue);
    expect(sel.coversRun(_run(1, 5, 'davor')), isFalse);
    expect(sel.coversRun(_run(2, 10, 'danach')), isFalse);
  });
}
