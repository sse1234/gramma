import 'package:flutter/material.dart';

import 'settings.dart';
import 'src/rust/api/library.dart';

/// Floating preview of a referenced passage: the target verse(s) with their
/// chapter context, resolved against the default text. `onOpen` navigates
/// the linked text view to the reference.
Future<void> showPassagePreview(
  BuildContext context, {
  required String osis,
  required String moduleCode,
  VoidCallback? onOpen,
}) {
  final parts = osis.split('-').first.split('.');
  final book = parts[0];
  final chapter = parts.length >= 2 ? int.tryParse(parts[1]) ?? 1 : 1;
  final verse = parts.length >= 3 ? int.tryParse(parts[2]) : null;
  var endVerse = verse;
  final endParts = osis.split('-');
  if (endParts.length == 2) {
    final tail = endParts[1].split('.');
    if (tail.length >= 3) endVerse = int.tryParse(tail[2]) ?? verse;
  }
  List<VerseView> verses;
  try {
    verses = chapterVerses(
      moduleCode: moduleCode,
      bookOsis: book,
      chapter: chapter,
    );
  } catch (_) {
    verses = const [];
  }
  // Context: begin one verse before the target so the passage reads
  // naturally; the popup scrolls for however much fits.
  final startIndex = verse == null
      ? 0
      : verses.indexWhere((v) => v.verse >= verse - 1).clamp(0, verses.length);
  final visible = verses.isEmpty ? const <VerseView>[] : verses.sublist(startIndex);
  return showDialog<void>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      final settings = SettingsScope.of(context);
      final scale = settings.previewScale;
      final family = settings.fontFamily;
      final numberStyle = theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.primary,
        fontFamily: family,
        fontSize: (theme.textTheme.labelSmall?.fontSize ?? 11) * scale,
      );
      final textStyle = theme.textTheme.bodyMedium?.copyWith(
        fontFamily: family,
        height: 1.3,
        color: theme.colorScheme.onSurface,
        fontSize: (theme.textTheme.bodyMedium?.fontSize ?? 14) * scale,
      );
      bool highlighted(int v) =>
          verse != null && v >= verse && v <= (endVerse ?? verse);
      return Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420, maxHeight: 460),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '$book $chapter'
                        '${verse != null ? ',$verse' : ''}'
                        '${endVerse != null && endVerse != verse ? '-$endVerse' : ''}'
                        ' · $moduleCode',
                        style: theme.textTheme.titleSmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (onOpen != null)
                      TextButton.icon(
                        key: const Key('preview-open'),
                        onPressed: () {
                          Navigator.of(context).pop();
                          onOpen();
                        },
                        icon: const Icon(Icons.open_in_new, size: 16),
                        label: const Text('Open'),
                      ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: visible.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            'Passage not available in $moduleCode',
                            style: textStyle,
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: visible.length,
                          itemBuilder: (context, index) {
                            final v = visible[index];
                            final strong = highlighted(v.verse);
                            return Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 3),
                              child: Text.rich(
                                TextSpan(children: [
                                  TextSpan(
                                    text: '${v.verse}  ',
                                    style: numberStyle?.copyWith(
                                      fontWeight: strong
                                          ? FontWeight.w800
                                          : FontWeight.w400,
                                    ),
                                  ),
                                  TextSpan(
                                    text: v.text,
                                    style: strong
                                        ? textStyle?.copyWith(
                                            fontWeight: FontWeight.w600)
                                        : textStyle,
                                  ),
                                ]),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
