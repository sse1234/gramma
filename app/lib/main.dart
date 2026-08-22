import 'package:flutter/material.dart';

import 'src/rust/frb_generated.dart';
import 'reference_screen.dart';

Future<void> main() async {
  await RustLib.init();
  runApp(const GrammaApp());
}

class GrammaApp extends StatelessWidget {
  const GrammaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'gramma',
      theme: ThemeData(colorSchemeSeed: const Color(0xFF7A5C3E)),
      home: const ReferenceScreen(),
    );
  }
}
