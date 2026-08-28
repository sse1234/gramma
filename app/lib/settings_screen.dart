import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

import 'dropbox_sync.dart';
import 'l10n.dart';
import 'icloud.dart';
import 'reader_pane.dart' show StrongsBadge;
import 'settings.dart';
import 'sync_transport.dart';
import 'src/rust/api/library.dart';
import 'src/rust/api/typeset.dart';
import 'src/rust/api/user.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.inDialog = false});

  /// Rendered inside a floating dialog (wide screens) instead of its own
  /// route: a header row with a close button replaces the app bar.
  final bool inDialog;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

/// Full-screen route on narrow screens; a floating dialog sized to its
/// content on desktops and tablets.
Future<void> showSettings(BuildContext context) {
  if (MediaQuery.of(context).size.width < 700) {
    return Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
  }
  return showDialog<void>(
    context: context,
    builder: (_) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 760),
        child: const SettingsScreen(inDialog: true),
      ),
    ),
  );
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
      // The default text is a Bible text; commentaries (ADR 0017) are not
      // reading-view candidates.
      _modules = [
        for (final m in modules())
          if (m.kind == 'bible') m
      ];
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
    final l10n = context.l10n;
    try {
      configureSync(dir: path);
      final changed = path == null ? const <String>[] : await pullSync();
      if (!mounted) return;
      setState(() => _syncDir = path);
      messenger.showSnackBar(SnackBar(
        content: Text(path == null
            ? l10n.syncDisabled
            : l10n.syncEnabledPulled(changed.length)),
      ));
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text(l10n.folderNotUsable('$e'))));
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
            ? context.l10n.icloudUnavailable
            : context.l10n.icloudNoContainer),
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
        title: Text(context.l10n.syncPathTitle),
        content: TextField(
          key: const Key('sync-path-field'),
          controller: controller,
          autofocus: true,
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.l10n.cancel),
          ),
          TextButton(
            key: const Key('sync-path-confirm'),
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(context.l10n.useFolder),
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
    final l10n = context.l10n;
    final changed = await pullSync();
    messenger.showSnackBar(SnackBar(
      content: Text(changed.isEmpty
          ? l10n.alreadyUpToDate
          : l10n.changesPulled(changed.length)),
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
      if (!mounted) return;
      messenger.showSnackBar(
          SnackBar(content: Text(context.l10n.dropboxConnectionFailed('$e'))));
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
          title: Text(context.l10n.typefaceDialogTitle),
          content: RadioGroup<String>(
            groupValue: selection,
            onChanged: (v) => setDialogState(() => selection = v!),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(context.l10n.typefaceDialogBody),
                const SizedBox(height: 8),
                RadioListTile<String>(
                  key: const Key('font-GentiumBookPlus'),
                  title: const Text('Gentium Book Plus'),
                  subtitle: Text(context.l10n.fontBookSubtitle),
                  value: 'GentiumBookPlus',
                ),
                RadioListTile<String>(
                  key: const Key('font-GentiumPlus'),
                  title: const Text('Gentium Plus'),
                  subtitle: Text(context.l10n.fontPlusSubtitle),
                  value: 'GentiumPlus',
                ),
                RadioListTile<String>(
                  key: const Key('font-Literata'),
                  title: const Text('Literata'),
                  subtitle: Text(context.l10n.fontLiterataSubtitle),
                  value: 'Literata',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(context.l10n.cancel),
            ),
            FilledButton(
              key: const Key('font-confirm'),
              onPressed: () => Navigator.of(context).pop(selection),
              child: Text(context.l10n.apply),
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
      if (!mounted) return;
      messenger.showSnackBar(
          SnackBar(content: Text(context.l10n.typefaceChangeFailed('$e'))));
    }
  }

  Future<void> _confirmMeasureChange() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.measureDialogTitle),
        content: Text(context.l10n.measureDialogBody),
        actions: [
          TextButton(
            key: const Key('measure-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.keepCurrent),
          ),
          FilledButton(
            key: const Key('measure-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.understandChange),
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
    final list = ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(context.l10n.sectionReading,
                  style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(context.l10n.textSize),
                subtitle: Slider(
                  key: const Key('zoom-slider'),
                  min: 320,
                  max: 520,
                  divisions: 20,
                  value: settings.columnWidth,
                  label: context.l10n
                      .pxColumnLabel(settings.columnWidth.round()),
                  onChanged: settings.setColumnWidth,
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(context.l10n.footnoteTextSize),
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
                title: Text(context.l10n.previewTextSize),
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
                title: Text(context.l10n.commentaryTextSize),
                subtitle: Slider(
                  key: const Key('commentary-scale'),
                  min: 0.8,
                  max: 1.6,
                  divisions: 8,
                  value: settings.commentaryScale,
                  label: '${(settings.commentaryScale * 100).round()} %',
                  onChanged: settings.setCommentaryScale,
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(context.l10n.lineSpacing),
                subtitle: Slider(
                  key: const Key('spacing-slider'),
                  min: 1.2,
                  max: 2.6,
                  divisions: 14,
                  value: settings.lineSpacing,
                  label: context.l10n.lineSpacingLabel(
                      settings.lineSpacing.toStringAsFixed(1)),
                  onChanged: settings.setLineSpacing,
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(context.l10n.columnTurnEffort),
                subtitle: Slider(
                  key: const Key('advance-slider'),
                  // Left = a light swipe already turns the column,
                  // right = a firm one is needed.
                  min: SettingsController.minColumnAdvance,
                  max: SettingsController.maxColumnAdvance,
                  divisions: 9,
                  value: settings.columnAdvance,
                  label: context.l10n.columnAdvanceLabel(
                      (settings.columnAdvance * 100).round()),
                  onChanged: settings.setColumnAdvance,
                ),
              ),
              if (_modules.isNotEmpty)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(context.l10n.defaultText),
                  subtitle: Text(context.l10n.defaultTextSubtitle),
                  trailing: DropdownButton<String>(
                    key: const Key('default-module'),
                    value: _modules.any(
                            (m) => m.code == settings.defaultModule)
                        ? settings.defaultModule
                        : null,
                    hint: Text(context.l10n.firstModule),
                    items: [
                      for (final m in _modules)
                        DropdownMenuItem(
                          value: m.code,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(m.code),
                              if (m.strongs) ...[
                                const SizedBox(width: 4),
                                const StrongsBadge(),
                              ],
                            ],
                          ),
                        ),
                    ],
                    onChanged: settings.setDefaultModule,
                  ),
                ),
              const SizedBox(height: 16),
              Text(context.l10n.sectionAppearance,
                  style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(context.l10n.language),
                trailing: DropdownButton<String>(
                  key: const Key('language-select'),
                  value: settings.localeCode ?? 'system',
                  underline: const SizedBox.shrink(),
                  items: [
                    DropdownMenuItem(
                        value: 'system',
                        child: Text(context.l10n.themeSystem)),
                    const DropdownMenuItem(
                        value: 'en', child: Text('English')),
                    const DropdownMenuItem(
                        value: 'de', child: Text('Deutsch')),
                  ],
                  onChanged: (v) => settings
                      .setLocaleCode(v == 'system' ? null : v),
                ),
              ),
              SegmentedButton<ThemeMode>(
                key: const Key('theme-select'),
                segments: [
                  ButtonSegment(
                    value: ThemeMode.system,
                    label: Text(context.l10n.themeSystem),
                    icon: const Icon(Icons.brightness_auto_outlined),
                  ),
                  ButtonSegment(
                    value: ThemeMode.light,
                    label: Text(context.l10n.themeLight),
                    icon: const Icon(Icons.light_mode_outlined),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    label: Text(context.l10n.themeDark),
                    icon: const Icon(Icons.dark_mode_outlined),
                  ),
                ],
                selected: {settings.themeMode},
                onSelectionChanged: (modes) =>
                    settings.setThemeMode(modes.first),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(context.l10n.tone),
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
                title: Text(context.l10n.fontWeightLightMode),
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
                title: Text(context.l10n.fontWeightDarkMode),
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
                title: Text(context.l10n.trueBlack),
                subtitle: Text(context.l10n.trueBlackSubtitle),
                value: settings.trueBlackDark,
                onChanged: settings.setTrueBlackDark,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(context.l10n.contrast),
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
              Text(context.l10n.sectionTypesetting,
                  style: theme.textTheme.titleMedium),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(context.l10n.typeface),
                subtitle: Text(
                  SettingsController.fontDisplayNames[settings.fontFamily] ??
                      settings.fontFamily,
                ),
                trailing: OutlinedButton(
                  key: const Key('change-font'),
                  onPressed: _changeTypeface,
                  child: Text(context.l10n.changeEllipsis),
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(context.l10n.lineWidth),
                subtitle: Text(context.l10n.lineWidthSubtitle(
                    settings.measureEms,
                    (settings.measureEms * 2.1).round())),
                trailing: _measureUnlocked
                    ? null
                    : OutlinedButton(
                        key: const Key('change-measure'),
                        onPressed: _confirmMeasureChange,
                        child: Text(context.l10n.changeEllipsis),
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
              Text(context.l10n.sectionSync,
                  style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(context.l10n.syncedFolder),
                subtitle: Text(
                  settings.dropboxRefreshToken != null
                      ? context.l10n.syncDropboxSubtitle
                      : _syncDir ?? context.l10n.syncOffSubtitle,
                ),
              ),
              Wrap(
                spacing: 8,
                children: [
                  if (settings.dropboxRefreshToken == null)
                    FilledButton.tonal(
                      key: const Key('sync-dropbox'),
                      onPressed: _connectDropbox,
                      child: Text(context.l10n.connectDropbox),
                    ),
                  if (icloudTransportEnabled &&
                      (Platform.isIOS || Platform.isMacOS))
                    FilledButton.tonal(
                      key: const Key('sync-icloud'),
                      onPressed: _useICloud,
                      child: Text(context.l10n.useICloud),
                    ),
                  if (Platform.isMacOS ||
                      Platform.isLinux ||
                      Platform.isWindows)
                    FilledButton.tonal(
                      key: const Key('sync-choose'),
                      onPressed: _chooseSyncFolder,
                      child: Text(context.l10n.chooseFolder),
                    ),
                  OutlinedButton(
                    key: const Key('sync-enter'),
                    onPressed: _enterSyncFolder,
                    child: Text(context.l10n.enterPath),
                  ),
                  if (_syncDir != null) ...[
                    OutlinedButton(
                      key: const Key('sync-now'),
                      onPressed: _syncNowPressed,
                      child: Text(context.l10n.syncNow),
                    ),
                    TextButton(
                      key: const Key('sync-disable'),
                      onPressed: () {
                        _clearDropbox(settings);
                        _applySyncFolder(null);
                      },
                      child: Text(context.l10n.disable),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 24),
            ],
    );
    if (widget.inDialog) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(context.l10n.settingsTitle,
                      style: theme.textTheme.titleLarge),
                ),
                IconButton(
                  key: const Key('settings-close'),
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          Expanded(child: list),
        ],
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.settingsTitle)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: list,
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
      title: Text(context.l10n.dropboxConnectTitle),
      content: SizedBox(
        width: 440,
        child: ListView(
          shrinkWrap: true,
          children: [
            Text(
              context.l10n.dropboxIntro,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('dropbox-key'),
              controller: _appKey,
              decoration:
                  InputDecoration(labelText: context.l10n.appKey),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            if (key.isNotEmpty) ...[
              Text(context.l10n.dropboxStep1,
                  style: theme.textTheme.bodySmall),
              SelectableText(
                _auth.authorizeUrl(key).toString(),
                key: const Key('dropbox-url'),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.primary),
              ),
              const SizedBox(height: 8),
              Text(context.l10n.dropboxStep2,
                  style: theme.textTheme.bodySmall),
              TextField(
                key: const Key('dropbox-code'),
                controller: _code,
                decoration:
                    InputDecoration(labelText: context.l10n.accessCode),
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
          child:
              Text(_busy ? context.l10n.connecting : context.l10n.connect),
        ),
      ],
    );
  }
}
