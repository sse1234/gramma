import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'src/rust/api/library.dart';

/// A note's text as spans with its scanned references tappable — shared
/// by the footnotes pane and the inline note popup (ADR 0016).
/// Reference offsets are byte positions in UTF-8, so slicing goes
/// through utf8. Created recognizers are added to [recognizers]; the
/// caller owns their disposal.
List<TextSpan> noteSpans(
  NoteView note,
  TextStyle? textStyle,
  TextStyle? refStyle,
  ValueChanged<String> onRef,
  List<TapGestureRecognizer> recognizers,
) {
  if (note.refs.isEmpty) {
    return [TextSpan(text: note.text, style: textStyle)];
  }
  final bytes = utf8.encode(note.text);
  final spans = <TextSpan>[];
  var cursor = 0;
  for (final ref in note.refs) {
    if (ref.start > cursor) {
      spans.add(TextSpan(
        text: utf8.decode(bytes.sublist(cursor, ref.start)),
        style: textStyle,
      ));
    }
    final recognizer = TapGestureRecognizer()..onTap = () => onRef(ref.osis);
    recognizers.add(recognizer);
    spans.add(TextSpan(
      text: utf8.decode(bytes.sublist(ref.start, ref.end)),
      style: refStyle,
      recognizer: recognizer,
    ));
    cursor = ref.end;
  }
  if (cursor < bytes.length) {
    spans.add(TextSpan(
      text: utf8.decode(bytes.sublist(cursor)),
      style: textStyle,
    ));
  }
  return spans;
}

/// The link style for references inside note text.
TextStyle? refStyleFor(ThemeData theme, TextStyle? base) =>
    base?.copyWith(
      color: theme.colorScheme.primary,
      decoration: TextDecoration.underline,
      decorationColor: theme.colorScheme.primary.withValues(alpha: 0.5),
    );
