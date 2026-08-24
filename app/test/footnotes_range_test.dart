import 'package:flutter_test/flutter_test.dart';
import 'package:gramma/footnotes_pane.dart';
import 'package:gramma/src/rust/api/library.dart';

ChapterRefView _c(String book, int chapter) => ChapterRefView(
      bookOsis: book,
      chapter: chapter,
      heading: '$book $chapter',
      textLength: 100,
      maxVerse: 30,
      bookAbbrev: book,
      bookCategory: 0,
    );

void main() {
  final spine = [_c('Gen', 1), _c('Gen', 2), _c('Gen', 3), _c('Exod', 1)];

  test('single chapter when no end anchor', () {
    expect(visibleChapterIndexes(spine, 'Gen.2.5', null), [1]);
  });

  test('range spans chapters and books', () {
    expect(visibleChapterIndexes(spine, 'Gen.2.5', 'Exod.1.3'), [1, 2, 3]);
  });

  test('inverted or unknown ends collapse to the anchor', () {
    expect(visibleChapterIndexes(spine, 'Gen.3.1', 'Gen.1.9'), [2]);
    expect(visibleChapterIndexes(spine, 'Gen.3.1', 'Nope.1.1'), [2]);
    expect(visibleChapterIndexes(spine, 'Nope.1.1', null), isEmpty);
  });
}
