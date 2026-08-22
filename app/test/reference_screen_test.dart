import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gramma/main.dart';

import 'package:gramma/src/rust/api/library.dart';
import 'package:gramma/src/rust/frb_generated.dart';

/// Host tests load the bridge library from the Cargo workspace target dir;
/// build it first with `cargo build -p rust_lib_gramma`.
String _bridgeLibraryPath() {
  const base = '../target/debug/';
  if (Platform.isMacOS) return '${base}librust_lib_gramma.dylib';
  if (Platform.isWindows) return '${base}rust_lib_gramma.dll';
  return '${base}librust_lib_gramma.so';
}

const _fixture = '../crates/gramma-core/tests/fixtures/container.xml';

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
    await importOsisFile(path: _fixture);
  });

  tearDownAll(() async {
    await tempDir.delete(recursive: true);
  });

  testWidgets('resolves a German reference to its OSIS form', (tester) async {
    await tester.pumpWidget(const GrammaApp());
    await _enter(tester, 'Joh 3,16');
    expect(find.text('John.3.16'), findsOneWidget);
  });

  testWidgets('resolves a numbered book with a verse range', (tester) async {
    await tester.pumpWidget(const GrammaApp());
    await _enter(tester, '1 Kor 13:4-7');
    expect(find.text('1Cor.13.4-1Cor.13.7'), findsOneWidget);
  });

  testWidgets('shows an error for an unknown book', (tester) async {
    await tester.pumpWidget(const GrammaApp());
    await _enter(tester, 'Foo 3,16');
    expect(find.byKey(const Key('parse-error')), findsOneWidget);
    expect(find.byKey(const Key('osis-result')), findsNothing);
  });

  testWidgets('clearing the input clears the result', (tester) async {
    await tester.pumpWidget(const GrammaApp());
    await _enter(tester, 'Ps 23');
    expect(find.text('Ps.23'), findsOneWidget);
    await _enter(tester, '');
    expect(find.byKey(const Key('osis-result')), findsNothing);
    expect(find.byKey(const Key('parse-error')), findsNothing);
  });

  testWidgets('shows the imported module as the active source', (tester) async {
    await tester.pumpWidget(const GrammaApp());
    expect(find.text('Fixtur Deutsch'), findsOneWidget);
  });

  testWidgets('displays the chapter for a resolved reference', (tester) async {
    await tester.pumpWidget(const GrammaApp());
    await _enter(tester, '1. Mose 1');
    expect(find.text('Gen.1'), findsOneWidget);
    expect(find.byKey(const Key('chapter-list')), findsOneWidget);
    expect(
      find.textContaining('Am Anfang schuf Gott Himmel und Erde.'),
      findsOneWidget,
    );
  });

  testWidgets('no chapter list for a book the module lacks', (tester) async {
    await tester.pumpWidget(const GrammaApp());
    await _enter(tester, 'Joh 3,16');
    expect(find.byKey(const Key('chapter-list')), findsNothing);
  });
}
