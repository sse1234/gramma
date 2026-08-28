import 'dart:io';

import 'package:flutter/gestures.dart'
    show PointerDeviceKind, TapGestureRecognizer;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gramma/footnotes_pane.dart';
import 'package:gramma/reader_pane.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gramma/desks.dart';
import 'package:gramma/typeset_chapter.dart';
import 'package:gramma/typeset_prose.dart';
import 'package:gramma/main.dart';
import 'package:gramma/pane_model.dart';
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

/// Navigate a pane through the book/chapter/verse selector popup.
Future<void> _selectRef(
  WidgetTester tester, {
  required String book,
  required int chapter,
  int verse = 1,
  Finder? trigger,
}) async {
  await tester.tap(trigger ?? find.byKey(const Key('open-selector')).first);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key('sel-book-$book')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key('sel-ch-$chapter')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key('sel-v-$verse')));
  await tester.pumpAndSettle();
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
    await importSwordFile(path: 'test/fixtures/commentary.sword.zip');
    await importSwordFile(path: 'test/fixtures/dictionary.sword.zip');
    await importSwordFile(path: 'test/fixtures/bible.sword.zip');
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
    await _selectRef(tester, book: 'Exod', chapter: 1);
    // The label follows the leftmost visible column; the jump must move it
    // off the start even if the target lands mid-column.
    await _settle(tester, () => label() != '1. Mose 1');
    await _settle(
      tester,
      () => _found(find.bySemanticsLabel(RegExp('Dies sind die Namen'))),
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
    await _selectRef(tester, book: 'Gen', chapter: 3);
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
    await _selectRef(tester, book: 'Gen', chapter: 3);
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

  testWidgets('window resize keeps text columns on the grid', (tester) async {
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
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(ReaderPane).first).width,
        moreOrLessEquals(848, epsilon: 2),
        reason: 'the fresh split snapped on creation');

    tester.view.physicalSize = const Size(1200, 700);
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(ReaderPane).first).width,
        moreOrLessEquals(848, epsilon: 2),
        reason: 'a window resize re-snaps to whole column widths '
            '(proportional weights alone would give ~721)');
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

    // The fresh 50 % tiling snapped to the column grid immediately —
    // without any divider drag (two typeset columns at 1400 wide).
    await tester.pumpAndSettle();
    expect(textAfter.width, moreOrLessEquals(848, epsilon: 2),
        reason: 'a new tiling lands on whole column widths at once');
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

    // Categories separate: same row and tint within a category, a new row
    // and a different tint when the category changes (Josh = OT history).
    final gen = tester.getRect(find.byKey(const Key('sel-book-Gen')));
    final exod = tester.getRect(find.byKey(const Key('sel-book-Exod')));
    final josh = tester.getRect(find.byKey(const Key('sel-book-Josh')));
    expect(exod.top, gen.top, reason: 'same category shares the row');
    expect(josh.top, greaterThan(gen.top),
        reason: 'next category starts a new row');
    expect(josh.left, greaterThan(gen.left + 20),
        reason: 'alternate categories carry the half-tile offset');
    final genColor =
        tester.widget<Material>(find.byKey(const Key('sel-book-Gen'))).color;
    final joshColor =
        tester.widget<Material>(find.byKey(const Key('sel-book-Josh'))).color;
    expect(joshColor, isNot(genColor));

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

  testWidgets('footnote references preview and open the passage',
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
    await _selectRef(tester, book: 'Gen', chapter: 3);
    await _settle(tester, () => _found(find.textContaining('Anmerkung Beta')));

    TapGestureRecognizer? recognizer;
    for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
      rich.text.visitChildren((span) {
        if (span is TextSpan &&
            span.text == 'Kap. 1,1' &&
            span.recognizer is TapGestureRecognizer) {
          recognizer = span.recognizer as TapGestureRecognizer;
          return false;
        }
        return true;
      });
      if (recognizer != null) break;
    }
    expect(recognizer, isNotNull,
        reason: 'the scanned reference must be tappable');
    recognizer!.onTap!();
    await tester.pumpAndSettle();
    expect(find.textContaining('Am Anfang schuf Gott'), findsWidgets,
        reason: 'preview shows the referenced passage');

    await tester.tap(find.byKey(const Key('preview-open')));
    await tester.pumpAndSettle();
    await _settleLayouts(tester);
    await tester.pumpAndSettle();
    final position = tester.widget<Text>(
      find.byKey(const Key('current-position')).first,
    );
    expect(position.data, '1. Mose 1',
        reason: 'Open navigates the linked text view');
  });

  testWidgets('commentary view: entries, references, and module separation',
      (tester) async {
    _freshUserStore();
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(GrammaApp(settings: SettingsController(prefs)));
    await _settleLayouts(tester);

    // Commentaries never appear among the reading texts (ADR 0017).
    final readerModules =
        tester.widget<ReaderPane>(find.byType(ReaderPane)).modules;
    expect(readerModules.any((m) => m.kind == 'commentary'), isFalse);

    await tester.tap(find.byKey(const Key('add-view')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-commentary')));
    await tester.pumpAndSettle();

    // The pane linked itself to the text view; once that view reports its
    // position, the typeset sections covering the visible verses appear
    // (painted text, so asserted through the entries' semantics).
    final semantics = tester.ensureSemantics();
    await _selectRef(tester, book: 'Gen', chapter: 1);
    await _settle(
        tester, () => _found(find.byKey(const Key('comment-Gen.1.1'))));
    expect(find.byKey(const Key('commentary-list')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Der Anfang')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Zweiter Absatz der Auslegung')),
        findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Licht wird')), findsOneWidget);

    // Tap the typeset reference run at its computed position: the layout
    // is deterministic, so recomputing it with the widget's parameters
    // names the exact pixel (ADR 0018).
    final paneWidth =
        tester.getSize(find.byKey(const Key('commentary-list'))).width;
    // The reader's own em size (min(pane width, column width) / measure):
    // commentary matches the Bible text exactly at scale 1.0.
    final fontSize = (paneWidth < 400.0 ? paneWidth : 400.0) / 26.0;
    final prose = tester.widget<TypesetProse>(find.byType(TypesetProse).first);
    expect(prose.fontSize, moreOrLessEquals(fontSize, epsilon: 0.01),
        reason: 'commentary glyphs are set at the Bible text size');
    expect(prose.lineHeightEm, 1.5,
        reason: 'commentary uses the reader line spacing setting');
    late List<CommentLayoutView> layouts;
    await tester.runAsync(() async {
      layouts = await layoutComments(
        moduleCode: 'KomTest',
        bookOsis: 'Gen',
        chapter: 1,
        measureEms: paneWidth / fontSize,
      );
    });
    final entry = layouts.firstWhere((c) => c.verseStart == 1);
    RunView? linkRun;
    var lineIndex = 0;
    for (var i = 0; i < entry.lines.length && linkRun == null; i++) {
      for (final run in entry.lines[i].runs) {
        if (run.link != null) {
          linkRun = run;
          lineIndex = i;
          break;
        }
      }
    }
    expect(linkRun, isNotNull,
        reason: 'the reference must be a tappable run');
    final runScale = fontSize / entry.unitsPerEm;
    final lineHeight = fontSize * 1.5;
    final origin = tester.getTopLeft(find.descendant(
      of: find.byKey(const Key('comment-Gen.1.1')),
      matching: find.byType(CustomPaint),
    ));
    await tester.tapAt(origin +
        Offset((linkRun!.x + linkRun.width / 2) * runScale,
            lineIndex * lineHeight + lineHeight * 0.4));
    await tester.pumpAndSettle();
    expect(find.textContaining('Und die Schlange war listiger'), findsWidgets,
        reason: 'preview shows the referenced passage');

    await tester.tap(find.byKey(const Key('preview-open')));
    await tester.pumpAndSettle();
    await _settleLayouts(tester);
    await _settle(
        tester, () => _found(find.byKey(const Key('no-commentary'))));
    final position = tester.widget<Text>(
      find.byKey(const Key('current-position')).first,
    );
    expect(position.data, '1. Mose 3',
        reason: 'Open navigates the linked text view');
    semantics.dispose();
  });

  /// Center of the first run whose text contains [word] in the painted
  /// vertical chapter — recomputed from the deterministic layout.
  Future<Offset> wordPoint(WidgetTester tester, int chapter, String word,
      {String module = 'FixDe'}) async {
    final layout = await tester.runAsync(() => layoutChapter(
        moduleCode: module,
        bookOsis: 'Gen',
        chapter: chapter,
        measureEms: 26));
    for (var i = 0; i < layout!.lines.length; i++) {
      for (final run in layout.lines[i].runs) {
        if (!run.noteMarker && !run.verseNumber && run.text.contains(word)) {
          for (final element in find.byType(TypesetChapter).evaluate()) {
            final widget = element.widget as TypesetChapter;
            if (widget.layout.lines.length != layout.lines.length) continue;
            final rect =
                tester.getRect(find.byWidget(widget, skipOffstage: false));
            final scale = rect.width / layout.measureUnits;
            final lineHeight = scale * layout.unitsPerEm * 1.5;
            return rect.topLeft +
                Offset((run.x + run.width / 2) * scale,
                    (i + 0.3) * lineHeight);
          }
        }
      }
    }
    fail('word $word not painted in chapter $chapter');
  }

  testWidgets('dictionary view: search, entry, and browsing', (tester) async {
    _freshUserStore();
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(GrammaApp(settings: SettingsController(prefs)));
    await _settleLayouts(tester);

    await tester.tap(find.byKey(const Key('add-view')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-dictionary')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dict-search')), findsOneWidget);

    // Search a German gloss, open the hit.
    await tester.enterText(find.byKey(const Key('dict-search')), 'Liebe');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dict-results')), findsOneWidget);
    await tester.tap(find.byKey(const Key('dict-hit-2')));
    await _settle(
        tester, () => _found(find.byKey(const Key('dict-entry-2'))));
    expect(find.bySemanticsLabel(RegExp('ἀγάπη')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('höchste Form')), findsOneWidget);

    // Tapping the Strong label (halo mechanics, ADR 0020) opens the
    // concordance of that number in the tagged Bible fixture.
    final entryWidth =
        tester.getSize(find.byKey(const Key('dict-entry-2'))).width;
    final entryFontSize = (entryWidth < 400.0 ? entryWidth : 400.0) / 26.0;
    late DictLayoutView? entry2;
    await tester.runAsync(() async {
      entry2 = await layoutDictEntry(
        moduleCode: 'WbTest',
        sort: 2,
        measureEms: entryWidth / entryFontSize,
      );
    });
    final label = entry2!.lines.first.runs
        .firstWhere((run) => run.verseNumber);
    final labelScale = entryFontSize / entry2!.unitsPerEm;
    final entryOrigin = tester.getTopLeft(find.descendant(
      of: find.byKey(const Key('dict-entry-2')),
      matching: find.byType(CustomPaint),
    ));
    await tester.tapAt(entryOrigin +
        Offset((label.x + label.width / 2) * labelScale,
            entryFontSize * entry2!.numberScale * 0.5));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('concordance-list')), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(const Key('concordance-count')))
          .data,
      'G2 · 1',
    );
    expect(find.textContaining('Love'), findsWidgets,
        reason: 'the occurrence shows its verse with the word bold');

    // The header arrows walk the pane's lookup history.
    await tester.tap(find.byKey(const Key('dict-prev')));
    await _settle(
        tester, () => _found(find.byKey(const Key('dict-entry-2'))));
    await tester.tap(find.byKey(const Key('dict-prev')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dict-results')), findsOneWidget,
        reason: 'history returns to the search results');
    await tester.tap(find.byKey(const Key('dict-next')));
    await _settle(
        tester, () => _found(find.byKey(const Key('dict-entry-2'))));

    // A Strong's number in the search field goes straight to its entry.
    await tester.enterText(find.byKey(const Key('dict-search')), 'G1');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await _settle(
        tester, () => _found(find.byKey(const Key('dict-entry-1'))));

    // The scanned reference in the entry previews and opens the passage.
    final paneWidth =
        tester.getSize(find.byKey(const Key('dict-entry-1'))).width;
    final fontSize = (paneWidth < 400.0 ? paneWidth : 400.0) / 26.0;
    late DictLayoutView? entry;
    await tester.runAsync(() async {
      entry = await layoutDictEntry(
        moduleCode: 'WbTest',
        sort: 1,
        measureEms: paneWidth / fontSize,
      );
    });
    RunView? linkRun;
    var lineIndex = 0;
    for (var i = 0; i < entry!.lines.length && linkRun == null; i++) {
      for (final run in entry!.lines[i].runs) {
        if (run.link != null) {
          linkRun = run;
          lineIndex = i;
          break;
        }
      }
    }
    expect(linkRun, isNotNull);
    final runScale = fontSize / entry!.unitsPerEm;
    final lineHeight = fontSize * 1.5;
    final origin = tester.getTopLeft(find.descendant(
      of: find.byKey(const Key('dict-entry-1')),
      matching: find.byType(CustomPaint),
    ));
    await tester.tapAt(origin +
        Offset((linkRun!.x + linkRun.width / 2) * runScale,
            lineIndex * lineHeight + lineHeight * 0.4));
    await tester.pumpAndSettle();
    expect(find.textContaining('Und die Erde war wüst'), findsWidgets,
        reason: 'preview shows the referenced passage');
    semantics.dispose();
  });

  testWidgets('long-pressing a word opens the dictionary and searches it',
      (tester) async {
    _freshUserStore();
    // Wide enough for the full pane chrome, narrow enough to stay in the
    // vertical reader.
    tester.view.physicalSize = const Size(700, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(GrammaApp(settings: SettingsController(prefs)));
    await _settleLayouts(tester);
    expect(find.byKey(const Key('dict-search')), findsNothing);

    await tester.longPressAt(await wordPoint(tester, 1, 'Himmel'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dict-search')), findsOneWidget,
        reason: 'a dictionary view was created for the lookup');
    expect(find.byKey(const Key('dict-results')), findsOneWidget);
    expect(find.byKey(const Key('dict-hit-3')), findsOneWidget,
        reason: 'the Himmel gloss entry matches');
    final field =
        tester.widget<TextField>(find.byKey(const Key('dict-search')));
    expect(field.controller!.text, 'Himmel');
  });

  testWidgets('in a tagged text a long-pressed word resolves its Strong',
      (tester) async {
    _freshUserStore();
    tester.view.physicalSize = const Size(700, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(GrammaApp(settings: SettingsController(prefs)));
    await _settleLayouts(tester);

    await tester.tap(find.byKey(const Key('module-select')).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Testbibel mit Strongs').last);
    await _settleLayouts(tester);

    await tester
        .longPressAt(await wordPoint(tester, 1, 'heaven', module: 'KjvTest'));
    await _settle(
        tester, () => _found(find.byKey(const Key('dict-entry-3'))));
    expect(find.bySemanticsLabel(RegExp('οὐρανός')), findsOneWidget,
        reason: 'the tagged word opened its lexicon entry directly');
    semantics.dispose();
  });

  testWidgets('desk history: back, forward, and the dropdown', (tester) async {
    _freshUserStore();
    _phoneViewport(tester);
    await tester.pumpWidget(GrammaApp(settings: SettingsController(prefs)));
    await _settleLayouts(tester);

    String label() => tester
        .widget<Text>(find.byKey(const Key('current-position')))
        .data!;
    Future<void> settleJump() async {
      for (var i = 0; i < 3; i++) {
        await tester.pumpAndSettle();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
      }
      await _settleLayouts(tester);
      await tester.pumpAndSettle();
    }

    expect(
      tester.widget<IconButton>(find.byKey(const Key('nav-back'))).onPressed,
      isNull,
      reason: 'nothing to go back to yet',
    );

    await _selectRef(tester, book: 'Gen', chapter: 3);
    await _selectRef(tester, book: 'Exod', chapter: 1);
    await settleJump();
    expect(label(), '2. Mose 1');

    await tester.tap(find.byKey(const Key('nav-back')));
    await settleJump();
    expect(label(), '1. Mose 3');

    await tester.tap(find.byKey(const Key('nav-back')));
    await settleJump();
    expect(label(), '1. Mose 1');
    expect(
      tester.widget<IconButton>(find.byKey(const Key('nav-back'))).onPressed,
      isNull,
      reason: 'at the oldest entry',
    );

    await tester.tap(find.byKey(const Key('nav-forward')));
    await settleJump();
    expect(label(), '1. Mose 3');

    await tester.tap(find.byKey(const Key('nav-history')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2Mo 1,1').last);
    await settleJump();
    expect(label(), '2. Mose 1');
  });

  /// An iPhone-like viewport: too narrow for the wide pane chrome, with
  /// status-bar/notch and home-indicator insets.
  void notchedPhoneViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    tester.view.padding = const FakeViewPadding(
        left: 0, top: 59, right: 0, bottom: 34);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
  }

  testWidgets('phone-width panes collapse chrome into the overflow menu',
      (tester) async {
    _freshUserStore();
    notchedPhoneViewport(tester);
    await tester.pumpWidget(GrammaApp(settings: SettingsController(prefs)));
    await _settleLayouts(tester);
    // No overflow errors were thrown (pumpWidget rethrows them), and the
    // wide-chrome widgets gave way to the compact form.
    expect(find.byKey(const Key('pane-menu')), findsOneWidget);
    expect(find.byKey(const Key('module-select')), findsNothing);
    expect(find.byKey(const Key('link-select')), findsNothing);
    expect(find.byKey(const Key('current-position')), findsOneWidget);
    await tester.tap(find.byKey(const Key('pane-menu')));
    await tester.pumpAndSettle();
    expect(find.text('Fixtur Deutsch'), findsOneWidget,
        reason: 'module switching lives in the menu');
    expect(find.byKey(const Key('menu-unlinked')), findsOneWidget);
  });

  testWidgets('reading mode stays clear of the status bar inset',
      (tester) async {
    _freshUserStore();
    notchedPhoneViewport(tester);
    await prefs.setBool('readingMode', true);
    addTearDown(() => prefs.setBool('readingMode', false));
    await tester.pumpWidget(GrammaApp(settings: SettingsController(prefs)));
    await _settleLayouts(tester);
    final top = tester.getTopLeft(find.byKey(const Key('vertical-reader'))).dy;
    expect(top, greaterThanOrEqualTo(59),
        reason: 'without chrome the text must not slide under the notch');
  });

  testWidgets('arrow keys page the columns one at a time', (tester) async {
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
    const stride = 448.0;
    final list = tester.widget<ListView>(find.byType(ListView).first);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(list.controller!.offset, moreOrLessEquals(stride, epsilon: 1));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(list.controller!.offset, moreOrLessEquals(2 * stride, epsilon: 1));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(list.controller!.offset, moreOrLessEquals(stride, epsilon: 1));
  });

  testWidgets('drop targets omit the dragged pane\'s own position',
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
    await tester.tap(find.text('Text view'));
    await _settleLayouts(tester);

    // Drag the second (rightmost) pane: dropping it at the boundary on
    // either side of itself would recreate the current layout.
    final handle = tester.getCenter(find.byIcon(Icons.drag_indicator).last);
    final gesture = await tester.startGesture(handle);
    await gesture.moveBy(const Offset(0, 30));
    await tester.pump();
    expect(find.byKey(const Key('drop-column-1')), findsNothing,
        reason: 'the middle boundary is a no-op for the dragged pane');
    expect(find.byKey(const Key('drop-column-2')), findsNothing,
        reason: 'so is the boundary right of it');
    expect(find.byKey(const Key('drop-column-0')), findsOneWidget,
        reason: 'moving to the far left changes the order');
    expect(find.byKey(const Key('drop-stack-1-0')), findsNothing,
        reason: 'its own stack position is a no-op');
    expect(find.byKey(const Key('drop-stack-0-0')), findsOneWidget);
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('desks: create, switch, rename, and delete', (tester) async {
    _freshUserStore();
    _phoneViewport(tester);
    await tester.pumpWidget(GrammaApp(settings: SettingsController(prefs)));
    await _settleLayouts(tester);
    String label() => tester
        .widget<Text>(find.byKey(const Key('current-position')))
        .data!;

    // A second desk starts fresh; give it its own position.
    await tester.tap(find.byKey(const Key('desk-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('desk-new')));
    await tester.pumpAndSettle();
    await _settleLayouts(tester);
    await _selectRef(tester, book: 'Exod', chapter: 2);
    await _settle(tester, () => label() == '2. Mose 2');

    // Switching desks restores each desk's own position.
    await tester.tap(find.byKey(const Key('desk-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('desk-item-Desk 1')));
    await tester.pumpAndSettle();
    await _settle(tester, () => label() == '1. Mose 1');
    await tester.tap(find.byKey(const Key('desk-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('desk-item-Desk 2')));
    await tester.pumpAndSettle();
    await _settle(tester, () => label() == '2. Mose 2');

    // Rename the current desk.
    await tester.tap(find.byKey(const Key('desk-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('desk-rename')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('desk-name-field')), 'Study');
    await tester.tap(find.byKey(const Key('desk-rename-confirm')));
    await tester.pumpAndSettle();

    // Delete it: back on Desk 1, Study is gone.
    await tester.tap(find.byKey(const Key('desk-menu')));
    await tester.pumpAndSettle();
    expect(find.text('Study'), findsOneWidget);
    await tester.tap(find.byKey(const Key('desk-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('desk-delete-confirm')));
    await tester.pumpAndSettle();
    await _settle(tester, () => label() == '1. Mose 1');
    await tester.tap(find.byKey(const Key('desk-menu')));
    await tester.pumpAndSettle();
    expect(find.text('Study'), findsNothing);
  });

  testWidgets('the legacy single layout migrates into Desk 1',
      (tester) async {
    _freshUserStore();
    _phoneViewport(tester);
    final legacy = LayoutModel([
      PaneColumn(panes: [
        PaneSpec(kind: PaneKind.text, module: 'FixDe', anchor: 'Exod.2.1'),
      ]),
    ])
      ..ensureBadges();
    userSet(key: 'layout', value: legacy.encode());
    await tester.pumpWidget(GrammaApp(settings: SettingsController(prefs)));
    await _settleLayouts(tester);
    await _settle(
      tester,
      () =>
          tester
              .widget<Text>(find.byKey(const Key('current-position')))
              .data ==
          '2. Mose 2',
    );
    expect(DeskRegistry.decode(userGet(key: 'desks')!), isNotNull,
        reason: 'the registry now exists with the migrated desk');
  });

  testWidgets('a desk arranged on one device appears on the second',
      (tester) async {
    _phoneViewport(tester);
    final folder = Directory.systemTemp.createTempSync('gramma-syncdir');

    // Device A: sync into the folder, read at 2. Mose 1. (Not the last
    // fixture chapter: that cannot sit at the viewport top, so its label
    // would never stabilize.)
    _freshUserStore();
    configureSync(dir: folder.path);
    await tester.pumpWidget(GrammaApp(settings: SettingsController(prefs)));
    await _settleLayouts(tester);
    await _selectRef(tester, book: 'Exod', chapter: 1);
    await _settle(
      tester,
      () =>
          tester
              .widget<Text>(find.byKey(const Key('current-position')))
              .data ==
          '2. Mose 1',
    );

    // Device B: a fresh store pointed at the same folder.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    _freshUserStore();
    configureSync(dir: folder.path);
    await tester.pumpWidget(GrammaApp(settings: SettingsController(prefs)));
    await _settleLayouts(tester);
    await _settle(
      tester,
      () =>
          tester
              .widget<Text>(find.byKey(const Key('current-position')))
              .data ==
          '2. Mose 1',
    );
  });

  testWidgets('the tools menu opens the reading plan and records the jump',
      (tester) async {
    _freshUserStore();
    _phoneViewport(tester);
    await tester.pumpWidget(GrammaApp(settings: SettingsController(prefs)));
    await _settleLayouts(tester);
    await tester.tap(find.byKey(const Key('tools-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tool-plan')));
    // The bundled plan loads asynchronously before the dialog appears.
    await _settle(
        tester, () => _found(find.byKey(const Key('plan-title'))));
    expect(
      tester.widget<Text>(find.byKey(const Key('plan-title'))).data,
      startsWith('Bibelliga — Day'),
    );
    await tester.tap(find.byKey(const Key('plan-ref-0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('plan-title')), findsNothing);
    final back = tester
        .widget<IconButton>(find.byKey(const Key('nav-back')).first);
    expect(back.onPressed, isNotNull,
        reason: 'the plan jump entered the desk history');
  });

  testWidgets('switching the typeface re-typesets the reader',
      (tester) async {
    _freshUserStore();
    _phoneViewport(tester);
    final settings = SettingsController(prefs);
    addTearDown(
        () => settings.setFontFamily('GentiumBookPlus', confirmed: true));
    await tester.pumpWidget(GrammaApp(settings: settings));
    await _settleLayouts(tester);
    await tester.tap(find.byKey(const Key('open-settings')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.byKey(const Key('change-font')), 300);
    await tester.tap(find.byKey(const Key('change-font')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('font-GentiumPlus')));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('font-confirm')));
      // The apply loads the font asset asynchronously.
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(settings.fontFamily, 'GentiumPlus');
    await tester.pageBack();
    await tester.pumpAndSettle();
    // The reader re-measures with the new metrics and keeps reading.
    await _settleLayouts(tester);
    expect(find.text('1. Mose 1'), findsWidgets);
  });

  /// Global tap point of the [nth] note marker of [chapter] inside the
  /// matching visible TypesetChapter, from the deterministic layout.
  Future<Offset> markerPoint(WidgetTester tester, int chapter,
      {int nth = 0}) async {
    final layout = await tester.runAsync(() => layoutChapter(
        moduleCode: 'FixDe',
        bookOsis: 'Gen',
        chapter: chapter,
        measureEms: 26));
    final markers = <(int, RunView)>[];
    for (var i = 0; i < layout!.lines.length; i++) {
      for (final run in layout.lines[i].runs) {
        if (run.noteMarker) markers.add((i, run));
      }
    }
    final (lineIndex, run) = markers[nth];
    // Pick the painted chapter whose height matches this layout.
    for (final element in find.byType(TypesetChapter).evaluate()) {
      final widget = element.widget as TypesetChapter;
      if (widget.layout.lines.length != layout.lines.length) continue;
      final rect = tester.getRect(
          find.byWidget(widget, skipOffstage: false));
      final scale = rect.width / layout.measureUnits;
      final lineHeight = scale * layout.unitsPerEm * 1.5;
      return rect.topLeft +
          Offset((run.x + run.width / 2) * scale,
              (lineIndex + 0.5) * lineHeight);
    }
    fail('chapter $chapter not painted');
  }

  testWidgets('note markers are active: popup, in-popup navigation, jump',
      (tester) async {
    _freshUserStore();
    _phoneViewport(tester);
    final settings = SettingsController(prefs);
    await tester.pumpWidget(GrammaApp(settings: settings));
    await _settleLayouts(tester);

    // Tapping the marker opens the note; reading mode must not toggle.
    await tester.tapAt(await markerPoint(tester, 1));
    await tester.pumpAndSettle();
    expect(find.textContaining('Anmerkung Alpha'), findsOneWidget);
    expect(settings.readingMode, isFalse);
    await tester.tap(find.byKey(const Key('note-close')));
    await tester.pumpAndSettle();

    // The Beta note carries a reference: navigate it inside the popup.
    await _selectRef(tester, book: 'Gen', chapter: 3);
    await _settleLayouts(tester);
    await tester.tapAt(await markerPoint(tester, 3));
    await tester.pumpAndSettle();
    expect(find.textContaining('Anmerkung Beta'), findsOneWidget);

    TapGestureRecognizer? recognizer;
    for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
      rich.text.visitChildren((span) {
        if (span is TextSpan &&
            span.text == 'Kap. 1,1' &&
            span.recognizer is TapGestureRecognizer) {
          recognizer = span.recognizer as TapGestureRecognizer;
          return false;
        }
        return true;
      });
      if (recognizer != null) break;
    }
    recognizer!.onTap!();
    await tester.pumpAndSettle();
    expect(find.textContaining('Am Anfang schuf Gott'), findsOneWidget,
        reason: 'the passage page shows inside the same popup');
    await tester.tap(find.byKey(const Key('note-back')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Anmerkung Beta'), findsOneWidget,
        reason: 'back returns to the note page');

    // Open from the passage page jumps the reading view.
    recognizer!.onTap!();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('note-open')));
    await _settle(
      tester,
      () =>
          tester
              .widget<Text>(find.byKey(const Key('current-position')))
              .data ==
          '1. Mose 1',
    );

    // A plain word tap still toggles reading mode.
    await tester.tapAt(await markerPoint(tester, 1) + const Offset(-40, 0));
    await tester.pumpAndSettle();
    expect(settings.readingMode, isTrue);
    settings.setReadingMode(false);
  });

  testWidgets('wide screens get settings as a floating dialog',
      (tester) async {
    _freshUserStore();
    _desktopViewport(tester);
    await tester.pumpWidget(GrammaApp(settings: SettingsController(prefs)));
    await _settleLayouts(tester);
    await tester.tap(find.byKey(const Key('open-settings')));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget,
        reason: 'no full-screen route on a desktop viewport');
    await tester.tap(find.byKey(const Key('settings-close')));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('corrupted pane weights restore to a usable desk',
      (tester) async {
    _freshUserStore();
    final broken = LayoutModel([
      PaneColumn(
          panes: [PaneSpec(kind: PaneKind.text, module: 'FixDe')],
          weight: -0.4),
      PaneColumn(
          panes: [PaneSpec(kind: PaneKind.text, module: 'FixDe')]),
    ]);
    final desk = DeskInfo(id: 'dtest', name: 'Desk 1');
    userSet(key: 'desks', value: DeskRegistry([desk]).encode());
    userSet(key: 'desk/dtest', value: broken.encode());
    _desktopViewport(tester);
    await tester.pumpWidget(GrammaApp(settings: SettingsController(prefs)));
    await _settleLayouts(tester);
    expect(find.byType(ReaderPane), findsNWidgets(2));
    for (final pane in find.byType(ReaderPane).evaluate()) {
      expect(pane.size!.width, greaterThan(100),
          reason: 'no pane may be squeezed off the desk on restore');
    }
  });
}
