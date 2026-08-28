import 'dart:convert';

import 'run_hit.dart' show lookupWordText;
import 'src/rust/api/typeset.dart';
import 'src/rust/api/user.dart';

/// A user annotation (ADR 0023): a color mark, optionally with note
/// text, on a verse or passage. Canonically it references verses of one
/// chapter; word precision (byte offsets into the start and end verse)
/// is meaningful only in the module it was created in — every other
/// translation shows the whole verses.
class NoteMark {
  const NoteMark({
    required this.id,
    required this.module,
    required this.bookOsis,
    required this.chapter,
    required this.verseStart,
    required this.verseEnd,
    required this.startOffset,
    required this.endOffset,
    required this.colorIndex,
    required this.text,
    required this.created,
  });

  final String id;

  /// The module the mark was made in — word offsets belong to its text.
  final String module;
  final String bookOsis;
  final int chapter;
  final int verseStart;
  final int verseEnd;

  /// Byte offset of the first marked word in the start verse.
  final int startOffset;

  /// Byte offset just past the last marked word in the end verse.
  final int endOffset;

  /// Index into the HCL mark palette.
  final int colorIndex;

  /// The note text; empty for a pure color mark.
  final String text;
  final String created;

  /// Canonical reference ("Gen.1.1" or "Gen.1.1-Gen.1.3").
  String get osis => verseStart == verseEnd
      ? '$bookOsis.$chapter.$verseStart'
      : '$bookOsis.$chapter.$verseStart-$bookOsis.$chapter.$verseEnd';

  Map<String, dynamic> toJson() => {
        'v': 1,
        'id': id,
        'module': module,
        'book': bookOsis,
        'chapter': chapter,
        'verseStart': verseStart,
        'verseEnd': verseEnd,
        'startOffset': startOffset,
        'endOffset': endOffset,
        'color': colorIndex,
        'text': text,
        'created': created,
      };

  static NoteMark? fromJson(String raw) {
    try {
      final m = jsonDecode(raw);
      if (m is! Map<String, dynamic>) return null;
      return NoteMark(
        id: m['id'] as String,
        module: m['module'] as String,
        bookOsis: m['book'] as String,
        chapter: m['chapter'] as int,
        verseStart: m['verseStart'] as int,
        verseEnd: m['verseEnd'] as int,
        startOffset: m['startOffset'] as int? ?? 0,
        endOffset: m['endOffset'] as int? ?? 1 << 30,
        colorIndex: m['color'] as int? ?? 0,
        text: m['text'] as String? ?? '',
        created: m['created'] as String? ?? '',
      );
    } catch (_) {
      return null;
    }
  }
}

/// Whether [mark] covers [run] of a verse in [paneModule]'s text.
/// Word-precise in the origin module, whole verses elsewhere.
bool markCoversRun(NoteMark mark, RunView run, String? paneModule) {
  if (run.verseNumber || run.noteMarker) return false;
  if (run.verse < mark.verseStart || run.verse > mark.verseEnd) return false;
  if (mark.module != paneModule) return true;
  final runStart = run.offset;
  final runEnd = run.offset +
      utf8.encode(run.text.endsWith('-')
              ? run.text.substring(0, run.text.length - 1)
              : run.text)
          .length;
  if (run.verse == mark.verseStart && runEnd <= mark.startOffset) return false;
  if (run.verse == mark.verseEnd && runStart >= mark.endOffset) return false;
  return true;
}

/// The annotations store: `note/<id>` keys in the synced user store
/// (ADR 0014 op-log), cached in memory; a tombstone is an empty value.
class Annotations {
  static List<NoteMark>? _cache;

  static List<NoteMark> all() {
    final cached = _cache;
    if (cached != null) return cached;
    final marks = <NoteMark>[];
    try {
      for (final key in userKeys(prefix: 'note/')) {
        final value = userGet(key: key);
        if (value == null || value.isEmpty) continue;
        final mark = NoteMark.fromJson(value);
        if (mark != null) marks.add(mark);
      }
    } catch (_) {}
    _cache = marks;
    return marks;
  }

  /// Marks touching one chapter, in any module (rendering decides the
  /// precision per pane).
  static List<NoteMark> forChapter(String bookOsis, int chapter) => [
        for (final m in all())
          if (m.bookOsis == bookOsis && m.chapter == chapter) m
      ];

  static void save(NoteMark mark) {
    userSet(key: 'note/${mark.id}', value: jsonEncode(mark.toJson()));
    _cache = null;
  }

  static void delete(String id) {
    userSet(key: 'note/$id', value: '');
    _cache = null;
  }

  /// Drop the cache after external changes (a sync pull).
  static void invalidate() => _cache = null;

  static String newId() =>
      'n${DateTime.now().toUtc().microsecondsSinceEpoch}-${deviceId()}';
}

/// A live selection in a text view (ADR 0023): verses and byte offsets
/// within one chapter, always normalized so start <= end.
class VerseSelection {
  const VerseSelection({
    required this.verseStart,
    required this.verseEnd,
    required this.startOffset,
    required this.endOffset,
    this.word,
  });

  final int verseStart;
  final int verseEnd;
  final int startOffset;
  final int endOffset;

  /// The selected word when the selection is exactly one run — the
  /// dictionary action is offered only then.
  final String? word;

  static int _endOf(RunView r) =>
      r.offset +
      utf8
          .encode(r.text.endsWith('-')
              ? r.text.substring(0, r.text.length - 1)
              : r.text)
          .length;

  /// The single-word selection of the long-press anchor.
  factory VerseSelection.ofRun(RunView run) => VerseSelection(
        verseStart: run.verse,
        verseEnd: run.verse,
        startOffset: run.offset,
        endOffset: _endOf(run),
        word: lookupWordText(run.text),
      );

  /// A selection spanning from one run to another (either order).
  factory VerseSelection.between(RunView a, RunView b) {
    if (a.verse == b.verse && a.offset == b.offset) {
      return VerseSelection.ofRun(a);
    }
    final aFirst =
        a.verse < b.verse || (a.verse == b.verse && a.offset <= b.offset);
    final first = aFirst ? a : b;
    final last = aFirst ? b : a;
    return VerseSelection(
      verseStart: first.verse,
      verseEnd: last.verse,
      startOffset: first.offset,
      endOffset: _endOf(last),
    );
  }

  bool coversRun(RunView run) {
    if (run.verseNumber || run.noteMarker) return false;
    if (run.verse < verseStart || run.verse > verseEnd) return false;
    final runEnd = run.offset + utf8.encode(run.text).length;
    if (run.verse == verseStart && runEnd <= startOffset) return false;
    if (run.verse == verseEnd && run.offset >= endOffset) return false;
    return true;
  }
}

/// Consecutive covered runs of one line merged into x-spans (font
/// units) — closing only on an uncovered run bridges the spaces.
List<(double, double)> coveredSpans(
  LineView line,
  bool Function(RunView) covers,
) {
  final spans = <(double, double)>[];
  double? start;
  double end = 0;
  for (final run in line.runs) {
    if (covers(run)) {
      start ??= run.x;
      end = run.x + run.width;
    } else if (start != null) {
      spans.add((start, end));
      start = null;
    }
  }
  if (start != null) spans.add((start, end));
  return spans;
}
