import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dropbox_sync.dart';
import 'l10n.dart';
import 'mac_bookmarks.dart';
import 'src/rust/api/library.dart';
import 'src/rust/api/typeset.dart';
import 'src/rust/api/user.dart';
import 'src/rust/frb_generated.dart';
import 'reader_screen.dart';
import 'settings.dart';
import 'window_state.dart';

/// One-time migration out of the macOS App Sandbox container (ADR 0014):
/// the app ran sandboxed before sync; its databases and preferences move
/// to the unsandboxed locations on first launch after the change.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  final support = await getApplicationSupportDirectory();
  await Directory(support.path).create(recursive: true);
  openLibrary(path: '${support.path}/library.db');
  openUserStore(path: '${support.path}/user.db');
  final prefs = await SharedPreferences.getInstance();
  final settings = SettingsController(prefs);
  final font = await rootBundle
      .load(SettingsController.fontAssets[settings.fontFamily]!);
  initTypesetting(fontData: font.buffer.asUint8List());
  // Re-grant the sandboxed sync-folder access (ADR 0027) before anything
  // reads the sync configuration.
  await restoreMacSyncAccess(settings);
  // Reconnect the direct Dropbox transport when configured (ADR 0014).
  final dropboxKey = settings.dropboxAppKey;
  final dropboxToken = settings.dropboxRefreshToken;
  final dir = syncDir();
  if (dropboxKey != null && dropboxToken != null && dir != null) {
    activeDropbox = DropboxSync(
      appKey: dropboxKey,
      refreshToken: dropboxToken,
      localRoot: dir,
      ownLog: '${deviceId()}.jsonl',
      prefs: prefs,
    );
  }
  if (WindowStatePersistence.supported) {
    await WindowStatePersistence(prefs).restoreAndTrack();
  }
  runApp(GrammaApp(settings: settings));
}

class GrammaApp extends StatelessWidget {
  const GrammaApp({super.key, required this.settings});

  final SettingsController settings;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => MaterialApp(
        title: 'gramma',
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: settings.localeOverride,
        themeMode: settings.themeMode,
        theme: grammaTheme(Brightness.light, settings.contrast,
            tone: settings.tone),
        darkTheme: grammaTheme(Brightness.dark, settings.contrast,
            trueBlack: settings.trueBlackDark, tone: settings.tone),
        builder: (context, child) => SettingsScope(
          controller: settings,
          // Any pointer-down outside the focused text field dismisses
          // the keyboard — scrolling and menu taps included. Pointer
          // events bypass the gesture arena, so this never steals taps
          // from buttons or the readers.
          child: Listener(
            behavior: HitTestBehavior.deferToChild,
            onPointerDown: (event) {
              final focus = FocusManager.instance.primaryFocus;
              final focusContext = focus?.context;
              if (focus == null || focusContext == null) return;
              final box = focusContext.findRenderObject();
              if (box is RenderBox && box.attached) {
                final local = box.globalToLocal(event.position);
                if ((Offset.zero & box.size).contains(local)) return;
              }
              focus.unfocus();
            },
            child: child!,
          ),
        ),
        home: const ReaderScreen(),
      ),
    );
  }
}
