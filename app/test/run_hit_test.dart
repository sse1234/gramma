import 'package:flutter_test/flutter_test.dart';
import 'package:gramma/run_hit.dart';
import 'package:gramma/src/rust/api/typeset.dart';

RunView _run(double x, double width, {bool marker = false}) => RunView(
      text: marker ? 'a' : 'wort',
      x: x,
      width: width,
      verseNumber: false,
      noteMarker: marker,
      headingLevel: 0,
      verse: 1,
    );

void main() {
  final line = LineView(runs: [
    _run(0, 100),
    _run(110, 12, marker: true),
    _run(140, 100),
  ]);

  test('taps resolve to the run under them', () {
    expect(runInLine(line, 1.0, 50)!.text, 'wort');
    expect(runInLine(line, 1.0, 115)!.noteMarker, isTrue);
    expect(runInLine(line, 1.0, 300), isNull, reason: 'past the line end');
  });

  test('slop widens small targets but the nearest true box wins', () {
    expect(runInLine(line, 1.0, 106, slop: 6)!.noteMarker, isTrue,
        reason: 'the gap left of the marker belongs to the marker');
    expect(runInLine(line, 1.0, 104, slop: 6)!.noteMarker, isFalse,
        reason: 'closer to the word than to the marker');
    expect(runInLine(line, 1.0, 128, slop: 8)!.noteMarker, isTrue);
  });

  test('scale maps logical pixels to font units', () {
    expect(runInLine(line, 0.5, 57)!.noteMarker, isTrue);
  });

  test('line stacking picks the right line', () {
    final lines = [LineView(runs: [_run(0, 100)]), line];
    expect(
        runAtOffset(lines, 1.0, 20, const Offset(115, 30))!.noteMarker, isTrue);
    expect(runAtOffset(lines, 1.0, 20, const Offset(50, 10))!.noteMarker,
        isFalse);
    expect(runAtOffset(lines, 1.0, 20, const Offset(115, 10)), isNull,
        reason: 'past the first line\'s end');
    expect(runAtOffset(lines, 1.0, 20, const Offset(115, 99)), isNull);
    expect(runAtOffset(const [], 1.0, 20, const Offset(1, 1)), isNull);
  });
}
