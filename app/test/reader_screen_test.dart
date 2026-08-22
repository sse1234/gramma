import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gramma/main.dart';

import 'package:gramma/src/rust/api/library.dart';
import 'package:gramma/src/rust/api/typeset.dart';
import 'package:gramma/src/rust/frb_generated.dart';

/// Host tests load the bridge library from the Cargo workspace target dir;
/// build it first with `cargo build -p rust_lib_gramma`.
String _bridgeLibraryPath() {
  const base = '../target/debug/';
  if (Platform.isMacOS) return '${base}librust_lib_gramma.dylib';
  if (Platform.isWindows) return '${base}rust_lib_gramma.dll';
  return '${base}librust_lib_gramma.so';
}

const _fixture = 'test/fixtures/reader.osis.xml';

Future<void> _enter(WidgetTester tester, String input) async {
  await tester.enterText(find.byType(TextField), input);
  await tester.pump();
}

void main() {
  late Directory tempDir;

  setUpAll(() async {
    await RustLib.init(
      externalLibrary: ExternalLibrary.open(_bridgeLibraryPath()),
    );
    tempDir = await Directory.systemTemp.createTemp('gramma-test');
    openLibrary(path: '${tempDir.path}/library.db');
    initTypesetting(
      fontData: File('fonts/GentiumBookPlus-Regular.ttf').readAsBytesSync(),
    );
    await importOsisFile(path: _fixture);
  });

  tearDownAll(() async {
    await tempDir.delete(recursive: true);
  });

  testWidgets('shows the imported module and its first chapter', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(const GrammaApp());
    await tester.pump();
    expect(find.text('Fixtur Deutsch'), findsOneWidget);
    expect(find.text('1. Mose 1'), findsWidgets);
    expect(
      find.bySemanticsLabel(RegExp('Am Anfang schuf Gott Himmel und Erde')),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('reports the current reading position', (tester) async {
    await tester.pumpWidget(const GrammaApp());
    await tester.pump();
    final position = tester.widget<Text>(
      find.byKey(const Key('current-position')),
    );
    expect(position.data, '1. Mose 1');
  });

  testWidgets('jumps to a resolved reference', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(const GrammaApp());
    await tester.pump();
    await _enter(tester, '1. Mose 2');
    await tester.pump();
    expect(
      find.bySemanticsLabel(RegExp('Also ward vollendet Himmel und Erde')),
      findsOneWidget,
    );
    final position = tester.widget<Text>(
      find.byKey(const Key('current-position')),
    );
    expect(position.data, '1. Mose 2');
    semantics.dispose();
  });

  testWidgets('echoes the OSIS form of the entered reference', (tester) async {
    await tester.pumpWidget(const GrammaApp());
    await tester.pump();
    await _enter(tester, '1. Mose 2,1');
    expect(find.text('Gen.2.1'), findsOneWidget);
  });

  testWidgets('reports a reference outside the module', (tester) async {
    await tester.pumpWidget(const GrammaApp());
    await tester.pump();
    await _enter(tester, 'Joh 3,16');
    expect(find.byKey(const Key('jump-miss')), findsOneWidget);
  });

  testWidgets('shows an error for an unknown book', (tester) async {
    await tester.pumpWidget(const GrammaApp());
    await tester.pump();
    await _enter(tester, 'Foo 3,16');
    expect(find.byKey(const Key('parse-error')), findsOneWidget);
    expect(find.byKey(const Key('osis-result')), findsNothing);
  });

  testWidgets('clearing the input clears status but keeps the reader', (tester) async {
    await tester.pumpWidget(const GrammaApp());
    await tester.pump();
    await _enter(tester, '1. Mose 2');
    await _enter(tester, '');
    expect(find.byKey(const Key('osis-result')), findsNothing);
    expect(find.byKey(const Key('parse-error')), findsNothing);
    expect(find.byKey(const Key('jump-miss')), findsNothing);
    expect(find.byKey(const Key('reader')), findsOneWidget);
  });
}
