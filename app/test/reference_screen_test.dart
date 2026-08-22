import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gramma/main.dart';

import 'package:gramma/src/rust/frb_generated.dart';

/// Host tests load the bridge library from the Cargo workspace target dir;
/// build it first with `cargo build -p rust_lib_gramma`.
String _bridgeLibraryPath() {
  const base = '../target/debug/';
  if (Platform.isMacOS) return '${base}librust_lib_gramma.dylib';
  if (Platform.isWindows) return '${base}rust_lib_gramma.dll';
  return '${base}librust_lib_gramma.so';
}

Future<void> _enter(WidgetTester tester, String input) async {
  await tester.enterText(find.byType(TextField), input);
  await tester.pump();
}

void main() {
  setUpAll(() async {
    await RustLib.init(
      externalLibrary: ExternalLibrary.open(_bridgeLibraryPath()),
    );
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
}
