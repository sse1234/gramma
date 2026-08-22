import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'src/rust/api/library.dart';
import 'src/rust/api/typeset.dart';
import 'src/rust/api/user.dart';
import 'src/rust/frb_generated.dart';
import 'reader_screen.dart';
import 'settings.dart';
import 'window_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  final support = await getApplicationSupportDirectory();
  await Directory(support.path).create(recursive: true);
  openLibrary(path: '${support.path}/library.db');
  openUserStore(path: '${support.path}/user.db');
  final font = await rootBundle.load('fonts/GentiumBookPlus-Regular.ttf');
  initTypesetting(fontData: font.buffer.asUint8List());
  final prefs = await SharedPreferences.getInstance();
  final settings = SettingsController(prefs);
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
        theme: grammaTheme(Brightness.light, settings.contrast),
        darkTheme: grammaTheme(Brightness.dark, settings.contrast,
            trueBlack: settings.trueBlackDark),
        builder: (context, child) =>
            SettingsScope(controller: settings, child: child!),
        home: const ReaderScreen(),
      ),
    );
  }
}
