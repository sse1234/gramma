import 'dart:io';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:gramma/footnotes_pane.dart';
import 'package:gramma/reader_pane.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gramma/main.dart';
import 'package:gramma/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gramma/src/rust/api/library.dart';
import 'package:gramma/src/rust/api/typeset.dart';
import 'package:gramma/src/rust/api/user.dart';
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

/// Async results (line counts, chapter layouts) arrive from the Rust worker
/// thread; pump real async until [done] holds or time out.
Future<void> _settle(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 100; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
    if (done()) return;
  }
  fail('condition did not settle');
}

Future<void> _settleLayouts(WidgetTester tester) => _settle(
      tester,
      () => find.byKey(const Key('chapter-placeholder')).evaluate().isEmpty,
    );

/// Pin a phone-like viewport so the reader stays in vertical mode.
void _phoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(520, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// A desktop-like viewport wide enough for multiple columns.
void _desktopViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 700);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

bool _found(Finder f) => f.evaluate().isNotEmpty;

var _storeCounter = 0;

/// A fresh user store per test isolates persisted layout objects.
void _freshUserStore() {
  final dir = Directory.systemTemp.createTempSync('gramma-user');
  openUserStore(path: '${dir.path}/user-${_storeCounter++}.db');
}

void main() {
  late Directory tempDir;
  late SharedPreferences prefs;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    await RustLib.init(
      externalLibrary: ExternalLibrary.open(_bridgeLibraryPath()),
    );
    tempDir = await Directory.systemTemp.createTemp('gramma-test');
    openLibrary(path: '${tempDir.path}/library.db');
    initTypesetting(
      fontData: File('fonts/GentiumBookPlus-Regular.ttf').readAsBytesSync(),
    );
    await importOsisFile(path: _fixture);
    _freshUserStore();
  });

  tearDownAll(() async {
    await tempDir.delete(recursive: true);
  });

  testWidgets('shows the imported module and its first chapter', (tester) async {
    _freshUserStore();
    _phoneViewport(tester);
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(GrammaApp(settings: SettingsController(prefs)));
    await _settleLayouts(tester);
    expect(find.text('Fixtur Deutsch'), findsOneWidget);
    expect(find.text('1. Mose 1'), findsWidgets);
    expect(
      find.bySemanticsLabel(RegExp('Am Anfang schuf Gott Himmel und Erde')),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('reports the current reading position', (tester) async {
    _freshUserStore();
    _phoneViewport(tester);
    await tester.pumpWidget(GrammaApp(settings: SettingsController(prefs)));
    await tester.pump();
    final position = tester.widget<Text>(
      find.byKey(const Key('current-position')),
    );
    expect(position.data, '1. Mose 1');
  });

  testWidgets('jumps to a resolved reference', (tester) async {
    _freshUserStore();
    _phoneViewport(tester);
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(GrammaApp(settings: SettingsController(prefs)));
    await _settleLayouts(tester);
    await _enter(tester, '1. Mose 2');
    await _settleLayouts(tester);
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
    _freshUserStore();
    _phoneViewport(tester);
    await tester.pumpWidget(GrammaApp(settings: SettingsController(prefs)));
    await tester.pump();
    await _enter(tester, '1. Mose 2,1');
    expect(find.text('Gen.2.1'), findsOneWidget);
  });

  testWidgets('reports a reference outside the module', (tester) async {
    _freshUserStore();
    _phoneViewport(tester);
    await tester.pumpWidget(GrammaApp(settings: SettingsController(prefs)));
    await tester.pump();
    await _enter(tester, 'Joh 3,16');
    expect(find.byKey(const Key('jump-miss')), findsOneWidget);
  });

  testWidgets('shows an error for an unknown book', (tester) async {
    _freshUserStore();
    _phoneViewport(tester);
    await tester.pumpWidget(GrammaApp(settings: SettingsController(prefs)));
    await tester.pump();
    await _enter(tester, 'Foo 3,16');
    expect(find.byKey(const Key('parse-error')), findsOneWidget);
    expect(find.byKey(const Key('osis-result')), findsNothing);
  });

  testWidgets('clearing the input clears status but keeps the reader', (tester) async {
    _freshUserStore();
    _phoneViewport(tester);
    await tester.pumpWidget(GrammaApp(settings: SettingsController(prefs)));
    await tester.pump();
    await _enter(tester, '1. Mose 2');
    await _enter(tester, '');
    expect(find.byKey(const Key('osis-result')), findsNothing);
    expect(find.byKey(const Key('parse-error')), findsNothing);
    expect(find.byKey(const Key('jump-miss')), findsNothing);
    expect(find.byKey(const Key('vertical-reader')), findsOneWidget);
  });

  testWidgets('wide viewports switch to horizontal columns', (tester) async {
    _freshUserStore();
    _desktopViewport(tester);
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(GrammaApp(settings: SettingsController(prefs)));
    await _settle(
      tester,
      () => _found(find.byKey(const ValueKey('columns-active'))),
    );
    expect(find.byKey(const Key('vertical-reader')), findsNothing);
    await _settle(
      tester,
      () => _found(
        find.bySemanticsLabel(RegExp('Am Anfang schuf Gott Himmel und Erde')),
      ),
    );
    semantics.dispose();
  });

  testWidgets('jumping in horizontal mode scrolls the target into view',
      (tester) async {
    // Short viewport: few lines per column, so the fixture spans enough
    // columns to leave real scroll distance.
    tester.view.physicalSize = const Size(1200, 420);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(GrammaApp(settings: SettingsController(prefs)));
    await _settle(
      tester,
      () => _found(find.byKey(const ValueKey('columns-active'))),
    );
    String label() => tester
        .widget<Text>(find.byKey(const Key('current-position')))
        .data!;
    expect(label(), '1. Mose 1');
    await _enter(tester, '2. Mose 1');
    // The label follows the leftmost visible column; the jump must move it
    // off the start even if the target lands mid-column.
    await _settle(tester, () => label() != '1. Mose 1');
    expect(
      find.bySemanticsLabel(RegExp('Dies sind die Namen')),
      findsWidgets,
    );
    semantics.dispose();
  });

  testWidgets('narrowing the window falls back to one vertical column',
      (tester) async {
    _desktopViewport(tester);
    await tester.pumpWidget(GrammaApp(settings: SettingsController(prefs)));
    await _settle(
      tester,
      () => _found(find.byKey(const ValueKey('columns-active'))),
    );
    tester.view.physicalSize = const Size(520, 800);
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('vertical-reader')), findsOneWidget);
  });

  testWidgets('footnotes view follows the text view', (tester) async {
    _freshUserStore();
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(GrammaApp(settings: SettingsController(prefs)));
    await _settleLayouts(tester);
    await tester.tap(find.byKey(const Key('add-view')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Footnotes view'));
    await _settle(tester, () => _found(find.textContaining('Anmerkung Alpha')));
    expect(
      find.textContaining('1a'),
      findsWidgets,
      reason: 'notes carry marker letters matching the inline markers',
    );
    await _enter(tester, '1. Mose 3');
    await _settle(tester, () => _found(find.textContaining('Anmerkung Beta')));
    expect(find.textContaining('Anmerkung Alpha'), findsNothing);
  });

  testWidgets('a second text view follows the first', (tester) async {
    _freshUserStore();
    tester.view.physicalSize = const Size(1400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(GrammaApp(settings: SettingsController(prefs)));
    await _settleLayouts(tester);
    await tester.tap(find.byKey(const Key('add-view')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Text view'));
    await _settleLayouts(tester);
    await tester.tap(find.byKey(const Key('link-select')).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('FixDe').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '1. Mose 3');
    await _settle(tester, () {
      final labels = find.byKey(const Key('current-position'));
      if (labels.evaluate().length < 2) return false;
      return tester.widget<Text>(labels.last).data == '1. Mose 3';
    });
  });

  testWidgets('the layout object survives a restart', (tester) async {
    _freshUserStore();
    await tester.pumpWidget(GrammaApp(settings: SettingsController(prefs)));
    await _settleLayouts(tester);
    await tester.tap(find.byKey(const Key('add-view')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Footnotes view'));
    await tester.pumpAndSettle();
    expect(find.text('Footnotes'), findsOneWidget);
    await tester.pumpWidget(GrammaApp(settings: SettingsController(prefs)));
    await tester.pump();
    expect(find.text('Footnotes'), findsOneWidget,
        reason: 'restored from the user store');
  });

  testWidgets('horizontal scrolling settles on a column boundary',
      (tester) async {
    _freshUserStore();
    tester.view.physicalSize = const Size(1200, 420);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(GrammaApp(settings: SettingsController(prefs)));
    await _settle(
      tester,
      () => _found(find.byKey(const ValueKey('columns-active'))),
    );
    await tester.drag(
      find.byKey(const ValueKey('columns-active')),
      const Offset(-537, 0),
    );
    await tester.pumpAndSettle();
    final list = tester.widget<ListView>(find.byType(ListView).first);
    final offset = list.controller!.offset;
    const stride = 448.0; // default 400px column + 48px gutter
    expect(offset, greaterThan(0), reason: 'the drag must scroll');
    expect(
      (offset % stride).abs(),
      lessThan(1.0),
      reason: 'must settle aligned to a column, was $offset',
    );
  });

  testWidgets('a mouse wheel tick pages exactly one column', (tester) async {
    _freshUserStore();
    tester.view.physicalSize = const Size(1200, 420);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(GrammaApp(settings: SettingsController(prefs)));
    await _settle(
      tester,
      () => _found(find.byKey(const ValueKey('columns-active'))),
    );
    final center =
        tester.getCenter(find.byKey(const ValueKey('columns-active')));
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    pointer.hover(center);
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 50)));
    await tester.pumpAndSettle();
    const stride = 448.0;
    final list = tester.widget<ListView>(find.byType(ListView).first);
    expect(list.controller!.offset, moreOrLessEquals(stride, epsilon: 1));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 50)));
    await tester.pumpAndSettle();
    expect(
      list.controller!.offset,
      moreOrLessEquals(2 * stride, epsilon: 1),
    );
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, -50)));
    await tester.pumpAndSettle();
    expect(list.controller!.offset, moreOrLessEquals(stride, epsilon: 1));
    // A single large accelerated delta still steps exactly one column.
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 300)));
    await tester.pumpAndSettle();
    expect(
      list.controller!.offset,
      moreOrLessEquals(2 * stride, epsilon: 1),
    );
  });

  testWidgets('footnotes stack below their text view in the same column',
      (tester) async {
    _freshUserStore();
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(GrammaApp(settings: SettingsController(prefs)));
    await _settleLayouts(tester);
    await tester.tap(find.byKey(const Key('add-view')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Footnotes view'));
    await tester.pumpAndSettle();
    final text = tester.getRect(find.byType(ReaderPane));
    final notes = tester.getRect(find.byType(FootnotesPane));
    expect(notes.top, greaterThan(text.bottom - 1),
        reason: 'footnotes tile below the text view');
    expect(find.byKey(const Key('badge-1')), findsOneWidget);
    expect(find.byKey(const Key('badge-2')), findsNothing,
        reason: 'receive-only panes carry no badge');
    expect((notes.left - text.left).abs(), lessThan(1),
        reason: 'both tiles share the column');
  });

  testWidgets('row divider resizes the stack and the size persists',
      (tester) async {
    _freshUserStore();
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(GrammaApp(settings: SettingsController(prefs)));
    await _settleLayouts(tester);
    await tester.tap(find.byKey(const Key('add-view')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Footnotes view'));
    await tester.pumpAndSettle();
    final before = tester.getSize(find.byType(FootnotesPane)).height;
    final grip = find.byWidgetPredicate(
      (w) => w is MouseRegion && w.cursor == SystemMouseCursors.resizeRow,
    );
    await tester.drag(grip, const Offset(0, 120));
    await tester.pumpAndSettle();
    final after = tester.getSize(find.byType(FootnotesPane)).height;
    expect(after, lessThan(before - 80));
    await tester.pumpWidget(GrammaApp(settings: SettingsController(prefs)));
    await tester.pump();
    await tester.pump();
    final restored = tester.getSize(find.byType(FootnotesPane)).height;
    expect((restored - after).abs(), lessThan(2),
        reason: 'weights persist in the layout object');
  });

  testWidgets('column divider snaps to whole column widths', (tester) async {
    _freshUserStore();
    tester.view.physicalSize = const Size(1400, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(GrammaApp(settings: SettingsController(prefs)));
    await _settleLayouts(tester);
    await tester.tap(find.byKey(const Key('add-view')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Text view'));
    await _settleLayouts(tester);
    final grip = find.byWidgetPredicate(
      (w) => w is MouseRegion && w.cursor == SystemMouseCursors.resizeColumn,
    );
    await tester.drag(grip, const Offset(100, 0));
    await tester.pumpAndSettle();
    final width = tester.getSize(find.byType(ReaderPane).first).width;
    expect(width, moreOrLessEquals(848, epsilon: 2),
        reason: 'left column snaps to two typeset columns');
  });

  testWidgets('tapping content toggles reading mode and persists',
      (tester) async {
    _freshUserStore();
    _phoneViewport(tester);
    await tester.pumpWidget(GrammaApp(settings: SettingsController(prefs)));
    await _settleLayouts(tester);
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.byKey(const Key('module-select')), findsOneWidget);

    await tester.tap(find.byKey(const Key('vertical-reader')));
    await tester.pumpAndSettle();
    expect(find.byType(AppBar), findsNothing, reason: 'reading mode');
    expect(find.byKey(const Key('module-select')), findsNothing);
    expect(find.byType(TextField), findsNothing);

    await tester.pumpWidget(GrammaApp(settings: SettingsController(prefs)));
    await tester.pump();
    expect(find.byType(AppBar), findsNothing,
        reason: 'reading mode persists across restarts');

    await tester.tap(find.byKey(const Key('vertical-reader')));
    await tester.pumpAndSettle();
    expect(find.byType(AppBar), findsOneWidget, reason: 'back to setup');
  });

  testWidgets('a pane can be dragged into another stack', (tester) async {
    _freshUserStore();
    tester.view.physicalSize = const Size(1400, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(GrammaApp(settings: SettingsController(prefs)));
    await _settleLayouts(tester);
    await tester.tap(find.byKey(const Key('add-view')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Text view'));
    await _settleLayouts(tester);
    final first = tester.getRect(find.byType(ReaderPane).first);
    expect(tester.getRect(find.byType(ReaderPane).last).left,
        greaterThan(first.right), reason: 'starts side by side');

    final handle = tester.getCenter(find.byIcon(Icons.drag_indicator).last);
    final gesture = await tester.startGesture(handle);
    await gesture.moveBy(const Offset(0, 30));
    await tester.pump();
    // Bottom stack boundary of the first column.
    await gesture.moveTo(Offset(first.center.dx, first.bottom - 20));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    final panes = find.byType(ReaderPane);
    final a = tester.getRect(panes.first);
    final b = tester.getRect(panes.last);
    expect(b.top, greaterThan(a.bottom - 1), reason: 'now stacked');
    expect((b.left - a.left).abs(), lessThan(1));
  });

  testWidgets('a stacked pane can be dragged out into its own column',
      (tester) async {
    _freshUserStore();
    tester.view.physicalSize = const Size(1400, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(GrammaApp(settings: SettingsController(prefs)));
    await _settleLayouts(tester);
    await tester.tap(find.byKey(const Key('add-view')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Footnotes view'));
    await tester.pumpAndSettle();
    final text = tester.getRect(find.byType(ReaderPane));
    final notesBefore = tester.getRect(find.byType(FootnotesPane));
    expect(notesBefore.top, greaterThan(text.bottom - 1));

    final handle = tester.getCenter(find.byIcon(Icons.drag_indicator).last);
    final gesture = await tester.startGesture(handle);
    await gesture.moveBy(const Offset(0, 30));
    await tester.pump();
    // Far right edge: become a new column.
    await gesture.moveTo(Offset(1400 - 30, 350));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    final textAfter = tester.getRect(find.byType(ReaderPane));
    final notesAfter = tester.getRect(find.byType(FootnotesPane));
    expect(notesAfter.left, greaterThan(textAfter.right - 1),
        reason: 'footnotes moved into their own column');
  });

  testWidgets('panes show identity badges and the selector navigates',
      (tester) async {
    _freshUserStore();
    _phoneViewport(tester);
    await tester.pumpWidget(GrammaApp(settings: SettingsController(prefs)));
    await _settleLayouts(tester);
    expect(find.byKey(const Key('badge-1')), findsOneWidget,
        reason: 'first pane carries badge 1');

    await tester.tap(find.byKey(const Key('open-selector')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sel-book-Gen')), findsOneWidget);
    expect(find.byKey(const Key('sel-book-Exod')), findsOneWidget);

    await tester.tap(find.byKey(const Key('sel-book-Exod')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sel-ch-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sel-v-3')));
    await _settleLayouts(tester);
    final position = tester.widget<Text>(
      find.byKey(const Key('current-position')),
    );
    expect(position.data, '2. Mose 2');
  });
}
