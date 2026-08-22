import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'src/rust/api/library.dart';
import 'src/rust/frb_generated.dart';
import 'reader_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  final support = await getApplicationSupportDirectory();
  await Directory(support.path).create(recursive: true);
  openLibrary(path: '${support.path}/library.db');
  runApp(const GrammaApp());
}

class GrammaApp extends StatelessWidget {
  const GrammaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'gramma',
      theme: ThemeData(colorSchemeSeed: const Color(0xFF7A5C3E)),
      home: const ReaderScreen(),
    );
  }
}
