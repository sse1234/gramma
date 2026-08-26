import 'package:flutter/material.dart';

import 'l10n.dart';
import 'settings.dart';
import 'src/rust/api/library.dart';

/// The parsed shape of a preview target: "Book.Ch[.V][-…[.V2]]".
({String book, int chapter, int? verse, int? endVerse}) parsePreviewOsis(
    String osis) {
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
  return (book: book, chapter: chapter, verse: verse, endVerse: endVerse);
}

/// Display label of a preview target ("Gen 17,9-14 · GerNeUe").
String previewTitle(String osis, String moduleCode) {
  final t = parsePreviewOsis(osis);
  return '${t.book} ${t.chapter}'
      '${t.verse != null ? ',${t.verse}' : ''}'
      '${t.endVerse != null && t.endVerse != t.verse ? '-${t.endVerse}' : ''}'
      ' · $moduleCode';
}

/// The verses of a referenced passage with the target range highlighted,
/// beginning one verse before the target so the passage reads naturally.
/// Shared by the floating preview and the note popup (ADR 0016).
class PassageList extends StatelessWidget {
  const PassageList({super.key, required this.osis, required this.moduleCode});

  final String osis;
  final String moduleCode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scale = SettingsScope.of(context).previewScale;
    final family = SettingsScope.of(context).fontFamily;
    final target = parsePreviewOsis(osis);
    List<VerseView> verses;
    try {
      verses = chapterVerses(
        moduleCode: moduleCode,
        bookOsis: target.book,
        chapter: target.chapter,
      );
    } catch (_) {
      verses = const [];
    }
    final startIndex = target.verse == null
        ? 0
        : verses
            .indexWhere((v) => v.verse >= target.verse! - 1)
            .clamp(0, verses.length);
    final visible =
        verses.isEmpty ? const <VerseView>[] : verses.sublist(startIndex);
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
        target.verse != null &&
        v >= target.verse! &&
        v <= (target.endVerse ?? target.verse!);
    if (visible.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          context.l10n.passageNotAvailable(moduleCode),
          style: textStyle,
        ),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      itemCount: visible.length,
      itemBuilder: (context, index) {
        final v = visible[index];
        final strong = highlighted(v.verse);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Text.rich(
            TextSpan(children: [
              TextSpan(
                text: '${v.verse}  ',
                style: numberStyle?.copyWith(
                  fontWeight: strong ? FontWeight.w800 : FontWeight.w400,
                ),
              ),
              TextSpan(
                text: v.text,
                style: strong
                    ? textStyle?.copyWith(fontWeight: FontWeight.w600)
                    : textStyle,
              ),
            ]),
          ),
        );
      },
    );
  }
}

/// Floating preview of a referenced passage, resolved against the
/// default text. `onOpen` navigates the linked text view.
Future<void> showPassagePreview(
  BuildContext context, {
  required String osis,
  required String moduleCode,
  VoidCallback? onOpen,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
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
                        previewTitle(osis, moduleCode),
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
                        label: Text(context.l10n.open),
                      ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Flexible(child: PassageList(osis: osis, moduleCode: moduleCode)),
              ],
            ),
          ),
        ),
      );
    },
  );
}
