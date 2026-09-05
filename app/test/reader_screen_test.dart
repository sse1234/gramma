import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart'
    show PointerDeviceKind, TapGestureRecognizer;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gramma/footnotes_pane.dart';
import 'package:gramma/annotations.dart';
import 'package:gramma/reader_pane.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gramma/desks.dart';
import 'package:gramma/typeset_chapter.dart';
import 'package:gramma/typeset_column.dart';
import 'package:gramma/typeset_prose.dart';
import 'package:gramma/l10n.dart';
import 'package:gramma/notes_pane.dart';
import 'package:gramma/main.dart';
import 'package:gramma/pane_model.dart';
import 'package:gramma/search_tool.dart';
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
  // The annotations cache outlives the swapped store.
  Annotations.invalidate();
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
    await importSwordFile(path: 'test/fixtures/book.sword.zip');
    await importSwordFile(path: 'test/fixtures/devotional.sword.zip');
    _freshUserStore();
  });

  tearDownAll(() async {
    try {
      await tempDir.delete(recursive: true);
    } on FileSystemException {
      // Windows refuses to delete the library while the Rust side still
      // holds the connection; the OS temp dir is reaped anyway.
    }
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
      // The letter alone — or chapter,verse joined when a second visible
      // chapter's letter collides (ADR 0028).
      find.textContaining(RegExp(r'^(a|1,1a)\s+Anmerkung Alpha')),
      findsOneWidget,
      reason: 'the running letter labels a note in the list',
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
      'G2 · 1 · KjvTest',
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
    expect(find.byKey(const Key('selection-bar')), findsOneWidget,
        reason: 'a steady long press enters selection mode');
    await tester.tap(find.byKey(const Key('selection-dictionary')));
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

    expect(find.byKey(const Key('strongs-badge')), findsNothing,
        reason: 'the untagged text carries no badge');
    await tester.tap(find.byKey(const Key('module-select')).first);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.tag), findsWidgets,
        reason: 'the chooser marks Strong-tagged texts');
    await tester.tap(find.text('Testbibel mit Strongs').last);
    await _settleLayouts(tester);
    expect(find.byIcon(Icons.tag), findsWidgets,
        reason: 'the wide chrome shows the tag via the selected chooser row');
    expect(find.byKey(const Key('strongs-badge')), findsNothing,
        reason: 'no redundant standalone badge next to the chooser');

    // Compact chrome hides the chooser; the badge is the only hint.
    tester.view.physicalSize = const Size(440, 800);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('strongs-badge')), findsOneWidget,
        reason: 'compact chrome carries the tagged badge');
    tester.view.physicalSize = const Size(700, 800);
    await tester.pumpAndSettle();

    await tester
        .longPressAt(await wordPoint(tester, 1, 'heaven', module: 'KjvTest'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('selection-dictionary')));
    await _settle(
        tester, () => _found(find.byKey(const Key('dict-entry-3'))));
    expect(find.bySemanticsLabel(RegExp('οὐρανός')), findsOneWidget,
        reason: 'the tagged word opened its lexicon entry directly');
    semantics.dispose();
  });

  testWidgets('book view: sections, contents, and references',
      (tester) async {
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
    await tester.tap(find.byKey(const Key('add-book')));
    await tester.pumpAndSettle();
    await _settle(
        tester, () => _found(find.byKey(const Key('book-section-1'))));
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel(RegExp('Einleitung des Teils')),
        findsOneWidget);

    await tester.tap(find.byKey(const Key('book-next')));
    await _settle(
        tester, () => _found(find.byKey(const Key('book-section-2'))));
    expect(find.bySemanticsLabel(RegExp('Erster Absatz der Predigt')),
        findsOneWidget);

    // The table of contents jumps anywhere, indented by level.
    await tester.tap(find.byKey(const Key('book-toc-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('toc-3')));
    await _settle(
        tester, () => _found(find.byKey(const Key('book-section-3'))));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp('zweiten Predigt')), findsOneWidget);

    // A reference in section 2 previews its passage.
    await tester.tap(find.byKey(const Key('book-prev')));
    await _settle(
        tester, () => _found(find.byKey(const Key('book-section-2'))));
    final paneWidth =
        tester.getSize(find.byKey(const Key('book-section-2'))).width;
    final fontSize = (paneWidth < 400.0 ? paneWidth : 400.0) / 26.0;
    late BookLayoutView? section;
    await tester.runAsync(() async {
      section = await layoutBookSection(
        moduleCode: 'BuchTest',
        ordinal: 2,
        measureEms: paneWidth / fontSize,
      );
    });
    RunView? linkRun;
    var lineIndex = 0;
    for (var i = 0; i < section!.lines.length && linkRun == null; i++) {
      for (final run in section!.lines[i].runs) {
        if (run.link != null) {
          linkRun = run;
          lineIndex = i;
          break;
        }
      }
    }
    expect(linkRun, isNotNull);
    final runScale = fontSize / section!.unitsPerEm;
    final lineHeight = fontSize * 1.5;
    final origin = tester.getTopLeft(find.descendant(
      of: find.byKey(const Key('book-section-2')),
      matching: find.byType(CustomPaint),
    ));
    await tester.tapAt(origin +
        Offset((linkRun!.x + linkRun.width / 2) * runScale,
            lineIndex * lineHeight + lineHeight * 0.4));
    await tester.pumpAndSettle();
    expect(find.textContaining('Und die Erde war wüst'), findsWidgets);
    semantics.dispose();
  });

  testWidgets('devotional view: today, day walking', (tester) async {
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
    await tester.tap(find.byKey(const Key('add-devotional')));
    await tester.pumpAndSettle();

    String dayKey(DateTime d) =>
        '${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';
    final today = DateTime.now();
    await _settle(tester,
        () => _found(find.bySemanticsLabel(RegExp('Andacht ${dayKey(today)}'))));

    // Walk one day back, then return to today.
    final yesterday = DateTime(2024, today.month, today.day)
        .subtract(const Duration(days: 1));
    await tester.tap(find.byKey(const Key('devo-prev')));
    await _settle(
        tester,
        () =>
            _found(find.bySemanticsLabel(RegExp('Andacht ${dayKey(yesterday)}'))));
    await tester.tap(find.byKey(const Key('devo-today')));
    await _settle(tester,
        () => _found(find.bySemanticsLabel(RegExp('Andacht ${dayKey(today)}'))));
    semantics.dispose();
  });

  testWidgets('exporting without labels explains itself', (tester) async {
    _freshUserStore();
    _phoneViewport(tester);
    await tester.pumpWidget(GrammaApp(settings: SettingsController(prefs)));
    await _settleLayouts(tester);
    await tester.tap(find.byKey(const Key('tools-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tool-export-labels')));
    await tester.pumpAndSettle();
    expect(find.text('No training labels collected yet'), findsOneWidget);
  });

  testWidgets('search tool: hits, jump, and training labels',
      (tester) async {
    _freshUserStore();
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(GrammaApp(settings: SettingsController(prefs)));
    await _settleLayouts(tester);

    await tester.tap(find.byKey(const Key('tools-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tool-search')));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('search-query')), 'Schlange listiger');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await _settle(
        tester, () => _found(find.byKey(const Key('search-results'))));
    expect(find.textContaining('Und die Schlange war listiger'),
        findsOneWidget);

    // The thumb records a positive training label into the synced store.
    await tester.tap(find.byKey(const Key('search-good-0')));
    await tester.pump();
    var labels = userKeys(prefix: 'label/');
    expect(labels.length, 1);
    final positive = userGet(key: labels.first)!;
    expect(positive, contains('"query":"Schlange listiger"'));
    expect(positive, contains('"label":"good_hit"'));
    expect(positive, contains('"osis":"Gen.3.1"'));

    // The red row records a negative for the query.
    await tester.tap(find.byKey(const Key('search-no-good-hit')));
    await tester.pump();
    labels = userKeys(prefix: 'label/');
    expect(labels.length, 2);
    expect(
      labels.map((k) => userGet(key: k)!).where(
          (v) => v.contains('"label":"no_good_hit"')),
      hasLength(1),
    );

    // The export payload is bibelsuche-compatible JSONL, in order.
    final jsonl = labelExportJsonl();
    final lines =
        jsonl.trim().split('\n').map((l) => jsonDecode(l)).toList();
    expect(lines, hasLength(2));
    expect(lines[0]['label'], 'good_hit');
    expect(lines[0]['corpus'], 'FixDe');
    expect(lines[1]['label'], 'no_good_hit');

    // Tapping the hit jumps the reading view.
    await tester.tap(find.byKey(const Key('search-hit-0')));
    await tester.pumpAndSettle();
    await _settleLayouts(tester);
    await tester.pumpAndSettle();
    final position = tester.widget<Text>(
      find.byKey(const Key('current-position')).first,
    );
    expect(position.data, '1. Mose 3');
  });

  testWidgets('annotations: mark, note, edit, and cross-module verses',
      (tester) async {
    _freshUserStore();
    tester.view.physicalSize = const Size(700, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(GrammaApp(settings: SettingsController(prefs)));
    await _settleLayouts(tester);

    // Hold-and-release on a word: selection mode with the word selected.
    await tester.longPressAt(await wordPoint(tester, 1, 'Himmel'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('selection-bar')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('selection-label'))).data,
      '1Mo 1,1',
    );

    // Mark it with color 3 and a note.
    await tester.tap(find.byKey(const Key('selection-mark')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('mark-color-3')));
    await tester.enterText(
        find.byKey(const Key('mark-text')), 'Meine Notiz');
    await tester.tap(find.byKey(const Key('mark-save')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('selection-bar')), findsNothing,
        reason: 'saving exits selection mode');
    expect(userKeys(prefix: 'note/'), hasLength(1));

    // Tapping the marked word opens the note for editing.
    await tester.tapAt(await wordPoint(tester, 1, 'Himmel'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('mark-text')))
          .controller!
          .text,
      'Meine Notiz',
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // Hold-and-swipe: a passage selection across verses.
    final start = await wordPoint(tester, 1, 'Anfang');
    final end = await wordPoint(tester, 1, 'wüst');
    final gesture = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 700));
    await gesture.moveTo(end);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const Key('selection-label'))).data,
      '1Mo 1,1–2',
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('selection-dictionary')))
          .onPressed,
      isNull,
      reason: 'the dictionary needs a single word',
    );
    await tester.tap(find.byKey(const Key('selection-mark')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('mark-save')));
    await tester.pumpAndSettle();
    expect(userKeys(prefix: 'note/'), hasLength(2));

    // In another translation the mark covers whole verses: any word of
    // verse 1 opens the note popup.
    await tester.tap(find.byKey(const Key('module-select')).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Testbibel mit Strongs').last);
    await _settleLayouts(tester);
    await tester
        .tapAt(await wordPoint(tester, 1, 'beginning', module: 'KjvTest'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('mark-text')), findsOneWidget,
        reason: 'verse-level coverage in a foreign module');
    await tester.tap(find.byKey(const Key('mark-delete')));
    await tester.pumpAndSettle();
    final remaining = [
      for (final k in userKeys(prefix: 'note/')) userGet(key: k)!
    ].where((v) => v.isNotEmpty);
    expect(remaining, hasLength(1), reason: 'delete tombstones the mark');
  });

  testWidgets('notes overview: canonical list, jump, edit, and delete',
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
    await tester.tap(find.byKey(const Key('add-notes')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('note-row-0')), findsNothing,
        reason: 'a fresh store shows the empty state');

    // Two marks, saved out of canonical order — the open pane hears the
    // change through the store's revision notifier.
    NoteMark mark(String id, int chapter, String text) => NoteMark(
          id: id,
          module: 'FixDe',
          bookOsis: 'Gen',
          chapter: chapter,
          verseStart: 1,
          verseEnd: 1,
          startOffset: 0,
          endOffset: 1 << 30,
          colorIndex: 2,
          text: text,
          created: '2026-08-29T0$chapter:00:00Z',
        );
    Annotations.save(mark('n-later', 2, 'Später'));
    Annotations.save(mark('n-first', 1, ''));
    await tester.pumpAndSettle();

    // Canonical order: Gen 1 before Gen 2; a pure color mark is labeled.
    expect(
      find.descendant(
          of: find.byKey(const Key('note-row-0')),
          matching: find.text('1Mo 1,1')),
      findsOneWidget,
    );
    expect(
      find.descendant(
          of: find.byKey(const Key('note-row-1')),
          matching: find.text('Später')),
      findsOneWidget,
    );

    // Tapping a row jumps the text view and enters the desk history.
    await _settle(tester, () => _found(find.textContaining('1Mo 1')));
    await tester.tap(find.byKey(const Key('note-row-1')));
    await tester.pumpAndSettle();
    final back =
        tester.widget<IconButton>(find.byKey(const Key('nav-back')).first);
    expect(back.onPressed, isNotNull,
        reason: 'the note jump entered the desk history');

    // Edit through the popup: the row shows the new text.
    await tester.tap(find.byKey(const Key('note-edit-0')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('mark-text')), 'Jetzt mit Text');
    await tester.tap(find.byKey(const Key('mark-save')));
    await tester.pumpAndSettle();
    expect(find.text('Jetzt mit Text'), findsOneWidget);

    // Delete removes the row.
    await tester.tap(find.byKey(const Key('note-edit-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('mark-delete')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('note-row-1')), findsNothing);
    expect(find.text('Später'), findsNothing);
  });

  testWidgets('notes overview in a narrow pane: reference stays, long-press edits',
      (tester) async {
    // A phone-width column beside a text pane leaves the notes pane
    // around 200 logical px: the module chip and edit button give way.
    _freshUserStore();
    Annotations.save(NoteMark(
      id: 'n-phone',
      module: 'FixDe',
      bookOsis: 'Gen',
      chapter: 1,
      verseStart: 1,
      verseEnd: 1,
      startOffset: 0,
      endOffset: 1 << 30,
      colorIndex: 1,
      text: 'Handynotiz',
      created: '2026-08-29T09:00:00Z',
    ));
    var opened = '';
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 220,
            height: 600,
            child: NotesPane(
              readingMode: false,
              onToggleMode: () {},
              badge: null,
              onOpenReference: (osis) => opened = osis,
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
          of: find.byKey(const Key('note-row-0')),
          matching: find.text('1Mo 1,1')),
      findsOneWidget,
      reason: 'the reference owns the compact row',
    );
    expect(find.byKey(const Key('note-edit-0')), findsNothing);
    await tester.tap(find.byKey(const Key('note-row-0')));
    await tester.pumpAndSettle();
    expect(opened, 'Gen.1.1');
    await tester.longPress(find.byKey(const Key('note-row-0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('mark-text')), findsOneWidget,
        reason: 'long-press opens the note popup');
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

  testWidgets('toggling chrome never re-chunks the columns', (tester) async {
    // ADR 0028: the app bar and pane header float over the text, so the
    // column geometry — lines per column, rows placed — is identical
    // with and without chrome; the reading position cannot jump.
    _freshUserStore();
    tester.view.physicalSize = const Size(1200, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final settings = SettingsController(prefs);
    addTearDown(() => settings.setReadingMode(false));
    await tester.pumpWidget(GrammaApp(settings: settings));
    await _settle(
      tester,
      () => _found(find.byKey(const ValueKey('columns-active'))),
    );
    expect(find.byType(AppBar), findsOneWidget);
    final before = tester.widget<TypesetColumn>(find.byType(TypesetColumn).first);

    settings.setReadingMode(true);
    await tester.pumpAndSettle();
    expect(find.byType(AppBar), findsNothing, reason: 'reading mode hides chrome');
    final after = tester.widget<TypesetColumn>(find.byType(TypesetColumn).first);
    expect(after.rowCount, before.rowCount,
        reason: 'lines per column are mode-independent');
    expect(after.rows.length, before.rows.length);
    expect(after.rows.first.row, before.rows.first.row);

    settings.setReadingMode(false);
    await tester.pumpAndSettle();
    final back = tester.widget<TypesetColumn>(find.byType(TypesetColumn).first);
    expect(back.rowCount, before.rowCount);
    expect(back.rows.length, before.rows.length);
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

  testWidgets('reading plans import as JSON and land in the tools menu',
      (tester) async {
    _freshUserStore();
    _phoneViewport(tester);
    await tester.pumpWidget(GrammaApp(settings: SettingsController(prefs)));
    await _settleLayouts(tester);
    // With no plan imported, the tools menu offers none.
    await tester.tap(find.byKey(const Key('tools-menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tool-search')), findsOneWidget);
    expect(find.byKey(const Key('tool-plan-0')), findsNothing);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    // Import a plan (ADR 0025) and start the app fresh — plan
    // discovery is part of startup, synchronous from the library.
    final planFile = File('${Directory.systemTemp.path}/gramma-test-plan.json');
    planFile.writeAsStringSync(jsonEncode({
      'name': 'Testplan',
      'source': 'zwei Tage',
      'days': [
        [
          {'label': 'Erster Tag', 'osis': 'Gen.1'},
        ],
        [
          {'label': 'Zweiter Tag', 'osis': 'Gen.1'},
        ],
      ],
    }));
    addTearDown(() => planFile.deleteSync());
    // The bridge call is real async — run it outside the test's
    // fake-async zone, like the setUpAll imports.
    final imported = await tester
        .runAsync(() => importPlanFile(path: planFile.path));
    expect((imported!.name, imported.days.toInt()), ('Testplan', 2));

    // Tear the tree down so the reader starts fresh — plan discovery
    // is part of startup.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(GrammaApp(settings: SettingsController(prefs)));
    await _settleLayouts(tester);
    await tester.tap(find.byKey(const Key('tools-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tool-plan-0')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const Key('plan-title'))).data,
      startsWith('Testplan — Day'),
    );
    await tester.tap(find.byKey(const Key('plan-ref-0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('plan-title')), findsNothing,
        reason: 'opening a reading closes the popup');
    final back =
        tester.widget<IconButton>(find.byKey(const Key('nav-back')).first);
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
    expect(tester.widget<Text>(find.byKey(const Key('note-title'))).data,
        'Footnotes',
        reason: 'the popup lists the visible footnotes (ADR 0028)');
    expect(
      find.descendant(
          of: find.byKey(const Key('note-body')),
          matching: find.textContaining('Anmerkung Alpha'),
          matchRoot: true),
      findsOneWidget,
      reason: 'the tapped note is the selected entry',
    );
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
