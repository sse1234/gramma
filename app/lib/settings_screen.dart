import 'package:flutter/material.dart';

import 'settings.dart';
import 'src/rust/api/library.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _measureUnlocked = false;
  double? _measurePreview;
  List<ModuleView> _modules = const [];

  @override
  void initState() {
    super.initState();
    try {
      _modules = modules();
    } catch (_) {
      _modules = const [];
    }
  }

  Future<void> _confirmMeasureChange() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change line width?'),
        content: const Text(
          'The line width determines where every line of text breaks. '
          'Changing it re-typesets everything — the familiar visual shape '
          'of pages you have read will change. This setting is meant to be '
          'chosen once and kept.',
        ),
        actions: [
          TextButton(
            key: const Key('measure-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep current'),
          ),
          FilledButton(
            key: const Key('measure-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('I understand, change it'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      setState(() => _measureUnlocked = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = SettingsScope.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text('Reading', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Text size'),
                subtitle: Slider(
                  key: const Key('zoom-slider'),
                  min: 320,
                  max: 520,
                  divisions: 20,
                  value: settings.columnWidth,
                  label: '${settings.columnWidth.round()} px column',
                  onChanged: settings.setColumnWidth,
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Footnote text size'),
                subtitle: Slider(
                  key: const Key('footnote-scale'),
                  min: 0.8,
                  max: 1.6,
                  divisions: 8,
                  value: settings.footnoteScale,
                  label: '${(settings.footnoteScale * 100).round()} %',
                  onChanged: settings.setFootnoteScale,
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Preview text size'),
                subtitle: Slider(
                  key: const Key('preview-scale'),
                  min: 0.8,
                  max: 1.6,
                  divisions: 8,
                  value: settings.previewScale,
                  label: '${(settings.previewScale * 100).round()} %',
                  onChanged: settings.setPreviewScale,
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Line spacing'),
                subtitle: Slider(
                  key: const Key('spacing-slider'),
                  min: 1.2,
                  max: 2.6,
                  divisions: 14,
                  value: settings.lineSpacing,
                  label: '${settings.lineSpacing.toStringAsFixed(1)} × font size',
                  onChanged: settings.setLineSpacing,
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Column turn effort'),
                subtitle: Slider(
                  key: const Key('advance-slider'),
                  // Left = a light swipe already turns the column,
                  // right = a firm one is needed.
                  min: SettingsController.minColumnAdvance,
                  max: SettingsController.maxColumnAdvance,
                  divisions: 9,
                  value: settings.columnAdvance,
                  label:
                      '${(settings.columnAdvance * 100).round()}% of a column',
                  onChanged: settings.setColumnAdvance,
                ),
              ),
              if (_modules.isNotEmpty)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Default text'),
                  subtitle: const Text(
                    'Used to resolve references in previews.',
                  ),
                  trailing: DropdownButton<String>(
                    key: const Key('default-module'),
                    value: _modules.any(
                            (m) => m.code == settings.defaultModule)
                        ? settings.defaultModule
                        : null,
                    hint: const Text('First module'),
                    items: [
                      for (final m in _modules)
                        DropdownMenuItem(
                            value: m.code, child: Text(m.code)),
                    ],
                    onChanged: settings.setDefaultModule,
                  ),
                ),
              const SizedBox(height: 16),
              Text('Appearance', style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              SegmentedButton<ThemeMode>(
                key: const Key('theme-select'),
                segments: const [
                  ButtonSegment(
                    value: ThemeMode.system,
                    label: Text('System'),
                    icon: Icon(Icons.brightness_auto_outlined),
                  ),
                  ButtonSegment(
                    value: ThemeMode.light,
                    label: Text('Light'),
                    icon: Icon(Icons.light_mode_outlined),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    label: Text('Dark'),
                    icon: Icon(Icons.dark_mode_outlined),
                  ),
                ],
                selected: {settings.themeMode},
                onSelectionChanged: (modes) =>
                    settings.setThemeMode(modes.first),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Tone'),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      for (final tone in ToneTheme.values)
                        Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: Tooltip(
                            message: tone.name,
                            child: InkWell(
                              key: Key('tone-${tone.name}'),
                              borderRadius: BorderRadius.circular(18),
                              onTap: () => settings.setTone(tone),
                              child: Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: toneBackground(
                                      tone, theme.brightness),
                                  border: Border.all(
                                    color: settings.tone == tone
                                        ? theme.colorScheme.primary
                                        : theme.colorScheme.outlineVariant,
                                    width: settings.tone == tone ? 2.5 : 1,
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    'Aa',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontFamily: 'GentiumBookPlus',
                                      color: toneInk(
                                          tone, theme.brightness),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              SwitchListTile(
                key: const Key('true-black'),
                contentPadding: EdgeInsets.zero,
                title: const Text('True black in dark mode'),
                subtitle: const Text(
                  'Keep the background fully black; contrast dims only '
                  'the text.',
                ),
                value: settings.trueBlackDark,
                onChanged: settings.setTrueBlackDark,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Contrast'),
                subtitle: Slider(
                  key: const Key('contrast-slider'),
                  min: SettingsController.minContrast,
                  max: 1.0,
                  divisions: 14,
                  value: settings.contrast,
                  label: '${(settings.contrast * 100).round()} %',
                  onChanged: settings.setContrast,
                ),
              ),
              const Divider(height: 32),
              Text('Typesetting', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Line width'),
                subtitle: Text(
                  '${settings.measureEms} em — about '
                  '${(settings.measureEms * 2.1).round()} characters per '
                  'line. Fixed so the visual shape of the text stays '
                  'familiar on every page and device.',
                ),
                trailing: _measureUnlocked
                    ? null
                    : OutlinedButton(
                        key: const Key('change-measure'),
                        onPressed: _confirmMeasureChange,
                        child: const Text('Change…'),
                      ),
              ),
              if (_measureUnlocked)
                Slider(
                  key: const Key('measure-slider'),
                  min: 18,
                  max: 36,
                  divisions: 18,
                  value: _measurePreview ?? settings.measureEms.toDouble(),
                  label: '${(_measurePreview ?? settings.measureEms.toDouble()).round()} em',
                  onChanged: (v) => setState(() => _measurePreview = v),
                  // Committing only at drag end avoids re-typesetting the
                  // whole module on every tick.
                  onChangeEnd: (v) {
                    settings.setMeasureEms(v.round(), confirmed: true);
                    setState(() => _measurePreview = null);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}
