import 'package:flutter_test/flutter_test.dart';
import 'package:gramma/run_hit.dart';
import 'package:gramma/src/rust/api/typeset.dart';

RunView _run(double x, double width, {bool marker = false, String? text}) =>
    RunView(
      text: text ?? (marker ? 'a' : 'wort'),
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

  test('words resolve by their exact box only (ADR 0019)', () {
    expect(runInLine(line, 1.0, 50)!.text, 'wort');
    expect(runInLine(line, 1.0, 105), isNull,
        reason: 'the gap between word and marker hits nothing');
    expect(runInLine(line, 1.0, 130), isNull);
    expect(runInLine(line, 1.0, 300), isNull, reason: 'past the line end');
    expect(runInLine(line, 1.0, 115)!.noteMarker, isTrue,
        reason: 'a dead-center tap still hits the marker box');
  });

  test('scale maps logical pixels to font units', () {
    expect(runInLine(line, 0.5, 57)!.noteMarker, isTrue);
    expect(runInLine(line, 0.5, 30)!.text, 'wort');
  });

  test('exact stacking picks the right line', () {
    final lines = [
      LineView(runs: [_run(0, 100)]),
      line,
    ];
    expect(runAtOffset(lines, 1.0, 20, const Offset(115, 30))!.noteMarker,
        isTrue);
    expect(runAtOffset(lines, 1.0, 20, const Offset(50, 10))!.noteMarker,
        isFalse);
    expect(runAtOffset(lines, 1.0, 20, const Offset(115, 10)), isNull);
    expect(runAtOffset(lines, 1.0, 20, const Offset(115, 99)), isNull);
    expect(runAtOffset(lines, 1.0, 20, const Offset(1, -5)), isNull);
    expect(runAtOffset(const [], 1.0, 20, const Offset(1, 1)), isNull);
  });

  test('markers carry a 1.5x halo on every side', () {
    // Marker box: x 110..122 (w 12), glyph height 10, line top 0.
    final stack = [(line: line, top: 0.0)];
    // 1.5 * 12 = 18 horizontal halo: 92..140.
    expect(markerNear(stack, 1.0, 10, const Offset(93, 5)), isNotNull);
    expect(markerNear(stack, 1.0, 10, const Offset(139, 5)), isNotNull);
    expect(markerNear(stack, 1.0, 10, const Offset(90, 5)), isNull);
    // 1.5 * 10 = 15 vertical halo: -15..25.
    expect(markerNear(stack, 1.0, 10, const Offset(115, -14)), isNotNull);
    expect(markerNear(stack, 1.0, 10, const Offset(115, 24)), isNotNull);
    expect(markerNear(stack, 1.0, 10, const Offset(115, 27)), isNull);
  });

  test('the halo reaches across neighboring lines; nearest marker wins', () {
    final upper = LineView(runs: [_run(50, 12, marker: true)]);
    final stack = [(line: upper, top: 0.0), (line: line, top: 20.0)];
    // Between the lines, nearer the lower marker.
    expect(
        markerNear(stack, 1.0, 10, const Offset(110, 18))!.x, 110);
    // Same spot but horizontally at the upper marker.
    expect(markerNear(stack, 1.0, 10, const Offset(52, 14))!.x, 50);
  });

  test('lookupWord strips punctuation and rejects non-words', () {
    expect(lookupWord(_run(0, 10, text: 'Wort,')), 'Wort');
    expect(lookupWord(_run(0, 10, text: '(Gnade)!')), 'Gnade');
    expect(lookupWord(_run(0, 10, text: 'ἀγάπη')), 'ἀγάπη');
    expect(lookupWord(_run(0, 10, text: '—')), isNull);
    expect(lookupWord(_run(0, 10, marker: true)), isNull);
  });
}
