import 'package:flutter/material.dart';

import 'reader_pane.dart';
import 'src/rust/api/library.dart';

/// Receiver-only view (ADR 0008): shows the footnotes of the followed text
/// view's current chapter. Never emits a reading position.
class FootnotesPane extends StatelessWidget {
  const FootnotesPane({
    super.key,
    required this.followedAnchor,
    required this.sourceModule,
    required this.followValue,
    required this.followOptions,
    required this.readingMode,
    required this.onToggleMode,
    required this.badge,
    required this.onFollow,
    this.dragHandle,
    this.onClose,
  });

  /// Reading mode hides the pane's chrome; tapping the content toggles it.
  final bool readingMode;
  final VoidCallback onToggleMode;
  final Widget? badge;
  final Widget? dragHandle;

  /// Canonical "Book.Chapter" of the followed pane.
  final String? followedAnchor;

  /// Module code of the followed pane, whose notes are shown.
  final String? sourceModule;

  final String? followValue;
  final List<FollowOption> followOptions;
  final ValueChanged<String?> onFollow;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!readingMode)
          PaneHeader(
            title: 'Footnotes',
            badge: badge,
            dragHandle: dragHandle,
            followValue: followValue,
            followOptions: followOptions,
            onFollow: onFollow,
            onClose: onClose,
          ),
        const SizedBox(height: 8),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: onToggleMode,
            child: _body(theme),
          ),
        ),
      ],
    );
  }

  Widget _body(ThemeData theme) {
    final anchor = followedAnchor;
    final module = sourceModule;
    if (anchor == null || module == null) {
      return Center(
        child: Text(
          'Link this view to a text view to see its footnotes',
          style: theme.textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
      );
    }
    final parts = anchor.split('.');
    final chapter = parts.length >= 2 ? int.tryParse(parts[1]) : null;
    if (chapter == null) {
      return const SizedBox.shrink();
    }
    final notes = chapterNotes(
      moduleCode: module,
      bookOsis: parts[0],
      chapter: chapter,
    );
    if (notes.isEmpty) {
      return Center(
        child: Text(
          'No footnotes in this chapter',
          key: const Key('no-footnotes'),
          style: theme.textTheme.bodyMedium,
        ),
      );
    }
    final numberStyle = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.primary,
      fontFamily: 'GentiumBookPlus',
    );
    final textStyle = theme.textTheme.bodyMedium?.copyWith(
      fontFamily: 'GentiumBookPlus',
      height: 1.5,
      color: theme.colorScheme.onSurface,
    );
    return ListView.builder(
      key: const Key('footnotes-list'),
      itemCount: notes.length,
      itemBuilder: (context, index) {
        final note = notes[index];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text.rich(
            TextSpan(children: [
              TextSpan(
                text: '${note.verse}${note.label}  ',
                style: numberStyle,
              ),
              TextSpan(text: note.text, style: textStyle),
            ]),
          ),
        );
      },
    );
  }
}
