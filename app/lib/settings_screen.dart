import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

import 'dropbox_sync.dart';
import 'icloud.dart';
import 'settings.dart';
import 'sync_transport.dart';
import 'src/rust/api/library.dart';
import 'src/rust/api/typeset.dart';
import 'src/rust/api/user.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _measureUnlocked = false;
  double? _measurePreview;
  List<ModuleView> _modules = const [];
  String? _syncDir;

  @override
  void initState() {
    super.initState();
    try {
      _modules = modules();
    } catch (_) {
      _modules = const [];
    }
    try {
      _syncDir = syncDir();
    } catch (_) {
      _syncDir = null;
    }
  }

  Future<void> _applySyncFolder(String? path) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      configureSync(dir: path);
      final changed = path == null ? const <String>[] : await pullSync();
      if (!mounted) return;
      setState(() => _syncDir = path);
      messenger.showSnackBar(SnackBar(
        content: Text(path == null
            ? 'Sync disabled'
            : 'Sync enabled — ${changed.length} change(s) pulled'),
      ));
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('Folder not usable: $e')));
    }
  }

  Future<void> _useICloud() async {
    final messenger = ScaffoldMessenger.of(context);
    final path = Platform.isIOS
        ? await icloudContainerPath()
        : macIcloudContainerPath();
    if (!mounted) return;
    if (path == null) {
      messenger.showSnackBar(SnackBar(
        content: Text(Platform.isIOS
            ? 'iCloud is not available — check that iCloud Drive is '
                'enabled for this device'
            : 'No gramma iCloud container yet — open gramma on your '
                'iPhone or iPad once, then try again'),
      ));
      return;
    }
    await _applySyncFolder(path);
  }

  Future<void> _chooseSyncFolder() async {
    final path = await getDirectoryPath();
    if (path == null || !mounted) return;
    _clearDropbox(SettingsScope.of(context));
    _applySyncFolder(path);
  }

  Future<void> _enterSyncFolder() async {
    var suggestion = _syncDir ?? '';
    if (suggestion.isEmpty && Platform.isAndroid) {
      // Reachable by sync agents like Syncthing without extra permissions.
      final external = await getExternalStorageDirectory();
      if (external != null) suggestion = '${external.path}/sync';
    }
    if (!mounted) return;
    final controller = TextEditingController(text: suggestion);
    final path = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Synced folder path'),
        content: TextField(
          key: const Key('sync-path-field'),
          controller: controller,
          autofocus: true,
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('sync-path-confirm'),
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Use folder'),
          ),
        ],
      ),
    );
    if (path == null || path.trim().isEmpty || !mounted) return;
    _clearDropbox(SettingsScope.of(context));
    _applySyncFolder(path.trim());
  }

  Future<void> _syncNowPressed() async {
    final messenger = ScaffoldMessenger.of(context);
    final changed = await pullSync();
    messenger.showSnackBar(SnackBar(
      content: Text(changed.isEmpty
          ? 'Already up to date'
          : '${changed.length} change(s) pulled'),
    ));
  }

  /// Folder transports replace Dropbox and vice versa: connecting one
  /// disconnects the other.
  void _clearDropbox(SettingsController settings) {
    activeDropbox = null;
    settings.setDropbox(appKey: settings.dropboxAppKey, refreshToken: null);
    settings.prefs.remove('dropboxRevs');
    settings.prefs.remove('dropboxOwnHash');
  }

  Future<void> _connectDropbox() async {
    final settings = SettingsScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (context) =>
          DropboxConnectDialog(initialAppKey: settings.dropboxAppKey),
    );
    if (result == null || !mounted) return;
    final (appKey, refreshToken) = result;
    settings.setDropbox(appKey: appKey, refreshToken: refreshToken);
    final support = await getApplicationSupportDirectory();
    final mirror = '${support.path}/dropbox-sync';
    if (!mounted) return;
    try {
      activeDropbox = DropboxSync(
        appKey: appKey,
        refreshToken: refreshToken,
        localRoot: mirror,
        ownLog: '${deviceId()}.jsonl',
        prefs: settings.prefs,
      );
      await _applySyncFolder(mirror);
    } catch (e) {
      activeDropbox = null;
      messenger.showSnackBar(
          SnackBar(content: Text('Dropbox connection failed: $e')));
    }
  }

  Future<void> _changeTypeface() async {
    final settings = SettingsScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    var selection = settings.fontFamily;
    final chosen = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Change typeface?'),
          content: RadioGroup<String>(
            groupValue: selection,
            onChanged: (v) => setDialogState(() => selection = v!),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'The typeface defines where every line of text breaks. '
                  'Changing it re-typesets everything — the familiar visual '
                  'shape of pages you have read will change.',
                ),
                const SizedBox(height: 8),
                const RadioListTile<String>(
                  key: Key('font-GentiumBookPlus'),
                  title: Text('Gentium Book Plus'),
                  subtitle: Text('the heavier cut — the default'),
                  value: 'GentiumBookPlus',
                ),
                const RadioListTile<String>(
                  key: Key('font-GentiumPlus'),
                  title: Text('Gentium Plus'),
                  subtitle: Text('the lighter companion cut'),
                  value: 'GentiumPlus',
                ),
                const RadioListTile<String>(
                  key: Key('font-Literata'),
                  title: Text('Literata'),
                  subtitle:
                      Text('designed for e-reading — larger x-height'),
                  value: 'Literata',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('font-confirm'),
              onPressed: () => Navigator.of(context).pop(selection),
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
    if (chosen == null ||
        !mounted ||
        chosen == settings.fontFamily) {
      return;
    }
    try {
      final font =
          await rootBundle.load(SettingsController.fontAssets[chosen]!);
      setTypesetFont(fontData: font.buffer.asUint8List());
      settings.setFontFamily(chosen, confirmed: true);
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('Typeface change failed: $e')));
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
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Font weight · light mode'),
                subtitle: Slider(
                  key: const Key('weight-light'),
                  min: 0,
                  max: SettingsController.maxFontWeight,
                  divisions: 6,
                  value: settings.fontWeightLight,
                  label: settings.fontWeightLight == 0
                      ? 'natural'
                      : '+${(settings.fontWeightLight * 100).round()}',
                  onChanged: settings.setFontWeightLight,
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Font weight · dark mode'),
                subtitle: Slider(
                  key: const Key('weight-dark'),
                  min: 0,
                  max: SettingsController.maxFontWeight,
                  divisions: 6,
                  value: settings.fontWeightDark,
                  label: settings.fontWeightDark == 0
                      ? 'natural'
                      : '+${(settings.fontWeightDark * 100).round()}',
                  onChanged: settings.setFontWeightDark,
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
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Typeface'),
                subtitle: Text(
                  SettingsController.fontDisplayNames[settings.fontFamily] ??
                      settings.fontFamily,
                ),
                trailing: OutlinedButton(
                  key: const Key('change-font'),
                  onPressed: _changeTypeface,
                  child: const Text('Change…'),
                ),
              ),
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
              const SizedBox(height: 16),
              Text('Sync', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Synced folder'),
                subtitle: Text(
                  settings.dropboxRefreshToken != null
                      ? 'Dropbox — direct connection, no local client. '
                          'Op-logs live under Apps in your Dropbox.'
                      : _syncDir ??
                          'Off — point gramma at a folder your cloud '
                              'provider or sync agent keeps in sync, or '
                              'connect Dropbox directly (ADR 0014). Desks '
                              'and reading positions flow between your '
                              'devices; texts never leave this device.',
                ),
              ),
              Wrap(
                spacing: 8,
                children: [
                  if (settings.dropboxRefreshToken == null)
                    FilledButton.tonal(
                      key: const Key('sync-dropbox'),
                      onPressed: _connectDropbox,
                      child: const Text('Connect Dropbox…'),
                    ),
                  if (icloudTransportEnabled &&
                      (Platform.isIOS || Platform.isMacOS))
                    FilledButton.tonal(
                      key: const Key('sync-icloud'),
                      onPressed: _useICloud,
                      child: const Text('Use iCloud Drive'),
                    ),
                  if (Platform.isMacOS ||
                      Platform.isLinux ||
                      Platform.isWindows)
                    FilledButton.tonal(
                      key: const Key('sync-choose'),
                      onPressed: _chooseSyncFolder,
                      child: const Text('Choose folder…'),
                    ),
                  OutlinedButton(
                    key: const Key('sync-enter'),
                    onPressed: _enterSyncFolder,
                    child: const Text('Enter path…'),
                  ),
                  if (_syncDir != null) ...[
                    OutlinedButton(
                      key: const Key('sync-now'),
                      onPressed: _syncNowPressed,
                      child: const Text('Sync now'),
                    ),
                    TextButton(
                      key: const Key('sync-disable'),
                      onPressed: () {
                        _clearDropbox(settings);
                        _applySyncFolder(null);
                      },
                      child: const Text('Disable'),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

/// The Dropbox PKCE flow, all out-of-band: the user brings their own app
/// key, opens the shown link, and pastes the code Dropbox displays. No
/// client secret, no redirect server, nothing gramma-operated.
class DropboxConnectDialog extends StatefulWidget {
  const DropboxConnectDialog({super.key, this.initialAppKey});

  final String? initialAppKey;

  @override
  State<DropboxConnectDialog> createState() => _DropboxConnectDialogState();
}

class _DropboxConnectDialogState extends State<DropboxConnectDialog> {
  final _auth = DropboxAuth();
  late final TextEditingController _appKey =
      TextEditingController(text: widget.initialAppKey ?? '');
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _appKey.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final refresh =
          await _auth.exchangeCode(_appKey.text.trim(), _code.text);
      if (!mounted) return;
      Navigator.of(context).pop((_appKey.text.trim(), refresh));
    } catch (e) {
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final key = _appKey.text.trim();
    return AlertDialog(
      title: const Text('Connect Dropbox'),
      content: SizedBox(
        width: 440,
        child: ListView(
          shrinkWrap: true,
          children: [
            Text(
              'Create a free "Scoped access" app with "App folder" access '
              'at dropbox.com/developers/apps and paste its app key. '
              'gramma will only ever see its own app folder.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('dropbox-key'),
              controller: _appKey,
              decoration: const InputDecoration(labelText: 'App key'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            if (key.isNotEmpty) ...[
              Text('1. Open this link in a browser and allow access:',
                  style: theme.textTheme.bodySmall),
              SelectableText(
                _auth.authorizeUrl(key).toString(),
                key: const Key('dropbox-url'),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.primary),
              ),
              const SizedBox(height: 8),
              Text('2. Paste the code Dropbox shows:',
                  style: theme.textTheme.bodySmall),
              TextField(
                key: const Key('dropbox-code'),
                controller: _code,
                decoration: const InputDecoration(labelText: 'Access code'),
                onSubmitted: (_) => _connect(),
              ),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!,
                    style: TextStyle(color: theme.colorScheme.error)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed:
              _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('dropbox-connect'),
          onPressed: _busy || key.isEmpty || _code.text.isEmpty
              ? null
              : _connect,
          child: Text(_busy ? 'Connecting…' : 'Connect'),
        ),
      ],
    );
  }
}
