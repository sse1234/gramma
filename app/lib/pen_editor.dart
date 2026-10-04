import 'package:flutter/material.dart';

import 'l10n.dart';
import 'pens.dart';

/// The editor of one marking pen (ADR 0035): hue on a spectrum, strength,
/// wash or underline, with the pen shown on a line of text. Every change
/// saves at once, so the text behind the dialog follows.
Future<void> showPenEditor(BuildContext context, int index) {
  return showDialog<void>(
    context: context,
    builder: (context) => _PenDialog(index: index),
  );
}

class _PenDialog extends StatefulWidget {
  const _PenDialog({required this.index});

  final int index;

  @override
  State<_PenDialog> createState() => _PenDialogState();
}

class _PenDialogState extends State<_PenDialog> {
  late Pen _pen = Pens.of(widget.index);

  void _apply(Pen pen) {
    setState(() => _pen = pen);
    Pens.save(widget.index, pen);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final l10n = context.l10n;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.penTitle(widget.index + 1),
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 12),
              Center(
                child: PenSample(pen: _pen, text: l10n.sizeSample),
              ),
              const SizedBox(height: 12),
              Text(l10n.penHue, style: theme.textTheme.labelMedium),
              Stack(
                alignment: Alignment.center,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Container(
                      height: 10,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(5),
                        gradient: LinearGradient(
                          colors: [
                            for (var h = 0; h <= 360; h += 30)
                              Pen(
                                hue: h.toDouble(),
                                strength: 1,
                                style: PenStyle.wash,
                              ).ink(brightness),
                          ],
                        ),
                      ),
                    ),
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: Colors.transparent,
                      inactiveTrackColor: Colors.transparent,
                      thumbColor: _pen.ink(brightness),
                    ),
                    child: Slider(
                      key: const Key('pen-hue'),
                      min: 0,
                      max: 360,
                      value: _pen.hue,
                      onChanged: (v) => _apply(_pen.copyWith(hue: v % 360)),
                    ),
                  ),
                ],
              ),
              Text(l10n.penStrength, style: theme.textTheme.labelMedium),
              Slider(
                key: const Key('pen-strength'),
                min: Pen.minStrength,
                max: Pen.maxStrength,
                divisions: 16,
                value: _pen.strength,
                label: '${(_pen.strength * 100).round()} %',
                onChanged: (v) => _apply(_pen.copyWith(strength: v)),
              ),
              const SizedBox(height: 4),
              SegmentedButton<PenStyle>(
                key: const Key('pen-style'),
                segments: [
                  ButtonSegment(
                    value: PenStyle.wash,
                    label: Text(l10n.penStyleWash),
                    icon: const Icon(Icons.format_color_fill_outlined),
                  ),
                  ButtonSegment(
                    value: PenStyle.underline,
                    label: Text(l10n.penStyleUnderline),
                    icon: const Icon(Icons.format_underlined),
                  ),
                ],
                selected: {_pen.style},
                onSelectionChanged: (s) =>
                    _apply(_pen.copyWith(style: s.first)),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  TextButton(
                    key: const Key('pen-reset'),
                    onPressed: () {
                      Pens.reset(widget.index);
                      setState(() => _pen = Pens.of(widget.index));
                    },
                    child: Text(l10n.penReset),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l10n.close),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A line of text marked with [pen], as the reader will see it.
class PenSample extends StatelessWidget {
  const PenSample({super.key, required this.pen, required this.text});

  final Pen pen;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final decoration = switch (pen.style) {
      PenStyle.wash => BoxDecoration(
        color: pen.wash(brightness),
        borderRadius: BorderRadius.circular(3),
      ),
      PenStyle.underline => BoxDecoration(
        border: Border(
          bottom: BorderSide(color: pen.ink(brightness), width: 2),
        ),
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: decoration,
      child: Text(
        text,
        style: theme.textTheme.bodyLarge,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// A round swatch of a pen: its wash, or its paper with the ink
/// underneath for an underlining pen.
class PenSwatch extends StatelessWidget {
  const PenSwatch({
    super.key,
    required this.pen,
    required this.selected,
    this.size = 26,
  });

  final Pen pen;
  final bool selected;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final border = Border.all(
      color: selected ? theme.colorScheme.onSurface : Colors.transparent,
      width: 2,
    );
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: pen.style == PenStyle.wash
            ? pen.wash(brightness)
            : theme.colorScheme.surfaceContainerHighest,
        shape: BoxShape.circle,
        border: border,
      ),
      child: pen.style == PenStyle.underline
          ? Center(
              child: Container(
                width: size * 0.5,
                height: 3,
                margin: EdgeInsets.only(top: size * 0.3),
                color: pen.ink(brightness),
              ),
            )
          : null,
    );
  }
}
