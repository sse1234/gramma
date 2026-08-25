import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dropbox_sync.dart';
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
Future<void> _migrateFromMacSandbox(Directory support) async {
  if (!Platform.isMacOS) return;
  if (File('${support.path}/library.db').existsSync()) return;
  final home = Platform.environment['HOME'];
  if (home == null) return;
  final container = '$home/Library/Containers/io.sse.gramma/Data/Library';
  final oldSupport = '$container/Application Support/io.sse.gramma';
  for (final name in ['library.db', 'user.db']) {
    final old = File('$oldSupport/$name');
    if (old.existsSync()) {
      await old.copy('${support.path}/$name');
    }
  }
  final oldPrefs = File('$container/Preferences/io.sse.gramma.plist');
  final newPrefs = File('$home/Library/Preferences/io.sse.gramma.plist');
  if (oldPrefs.existsSync() && !newPrefs.existsSync()) {
    try {
      await oldPrefs.copy(newPrefs.path);
    } catch (_) {
      // Settings reset to defaults; the reading data above still moved.
    }
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  final support = await getApplicationSupportDirectory();
  await Directory(support.path).create(recursive: true);
  await _migrateFromMacSandbox(Directory(support.path));
  openLibrary(path: '${support.path}/library.db');
  openUserStore(path: '${support.path}/user.db');
  final font = await rootBundle.load('fonts/GentiumBookPlus-Regular.ttf');
  initTypesetting(fontData: font.buffer.asUint8List());
  final prefs = await SharedPreferences.getInstance();
  final settings = SettingsController(prefs);
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
        themeMode: settings.themeMode,
        theme: grammaTheme(Brightness.light, settings.contrast,
            tone: settings.tone),
        darkTheme: grammaTheme(Brightness.dark, settings.contrast,
            trueBlack: settings.trueBlackDark, tone: settings.tone),
        builder: (context, child) =>
            SettingsScope(controller: settings, child: child!),
        home: const ReaderScreen(),
      ),
    );
  }
}
