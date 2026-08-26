import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'src/rust/api/library.dart';

/// Prose with verse references as spans with the references tappable —
/// shared by the footnotes pane, the inline note popup (ADR 0016), and
/// the commentary pane (ADR 0017). Reference offsets are byte positions
/// in UTF-8, so slicing goes through utf8. Created recognizers are added
/// to [recognizers]; the caller owns their disposal.
List<TextSpan> noteSpans(
  String text,
  List<NoteRefView> refs,
  TextStyle? textStyle,
  TextStyle? refStyle,
  ValueChanged<String> onRef,
  List<TapGestureRecognizer> recognizers,
) {
  if (refs.isEmpty) {
    return [TextSpan(text: text, style: textStyle)];
  }
  final bytes = utf8.encode(text);
  final spans = <TextSpan>[];
  var cursor = 0;
  for (final ref in refs) {
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
