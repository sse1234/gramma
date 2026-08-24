import 'package:flutter_test/flutter_test.dart';
import 'package:gramma/pane_model.dart';

void main() {
  test('v2 layout roundtrips with columns, weights, and id links', () {
    final text = PaneSpec(kind: PaneKind.text, module: 'luth1912', weight: 1);
    final notes = PaneSpec(
      kind: PaneKind.footnotes,
      follow: text.id,
      weight: 0.5,
    );
    final model = LayoutModel([
      PaneColumn(panes: [text, notes], weight: 2),
      PaneColumn(panes: [PaneSpec(kind: PaneKind.text, module: 'GerNeUe')]),
    ]);
    final decoded = LayoutModel.decode(model.encode())!;
    expect(decoded.columns.length, 2);
    expect(decoded.columns[0].weight, 2);
    expect(decoded.columns[0].panes.length, 2);
    expect(decoded.columns[0].panes[1].kind, PaneKind.footnotes);
    expect(decoded.columns[0].panes[1].weight, 0.5);
    expect(
      decoded.columns[0].panes[1].follow,
      decoded.columns[0].panes[0].id,
    );
    expect(decoded.columns[1].panes[0].module, 'GerNeUe');
  });

  test('v1 layouts migrate: one column per pane, index links become ids', () {
    const v1 = '{"v":1,"panes":['
        '{"kind":"text","module":"luth1912","follow":null,"anchor":"Gen.1"},'
        '{"kind":"footnotes","module":null,"follow":0,"anchor":null}]}';
    final model = LayoutModel.decode(v1)!;
    expect(model.columns.length, 2);
    expect(model.columns[0].panes.single.module, 'luth1912');
    expect(model.columns[0].panes.single.anchor, 'Gen.1');
    expect(
      model.columns[1].panes.single.follow,
      model.columns[0].panes.single.id,
    );
  });

  test('unreadable layouts decode to null', () {
    expect(LayoutModel.decode('nonsense'), isNull);
    expect(LayoutModel.decode('{"v":99}'), isNull);
    expect(LayoutModel.decode('{"v":2,"columns":[]}'), isNull);
  });

  test('removing a pane clears dangling links and empty columns', () {
    final a = PaneSpec(kind: PaneKind.text, module: 'a');
    final b = PaneSpec(kind: PaneKind.footnotes, follow: a.id);
    final c = PaneSpec(kind: PaneKind.text, module: 'c', follow: a.id);
    final model = LayoutModel([
      PaneColumn(panes: [a]),
      PaneColumn(panes: [b, c]),
    ]);
    model.removePane(a.id);
    expect(model.columns.length, 1, reason: 'empty column dropped');
    expect(model.byId(b.id)!.follow, isNull);
    expect(model.byId(c.id)!.follow, isNull);
  });

  test('panes enumerate in column-major order', () {
    final a = PaneSpec(kind: PaneKind.text);
    final b = PaneSpec(kind: PaneKind.footnotes);
    final c = PaneSpec(kind: PaneKind.text);
    final model = LayoutModel([
      PaneColumn(panes: [a, b]),
      PaneColumn(panes: [c]),
    ]);
    expect(model.allPanes.map((p) => p.id).toList(), [a.id, b.id, c.id]);
  });

  test('column widths snap to integer column multiples', () {
    const colW = 400.0;
    const gutter = 48.0;
    expect(snapToColumns(430, colW, gutter, 2000), 400);
    expect(snapToColumns(700, colW, gutter, 2000), 848);
    expect(snapToColumns(900, colW, gutter, 2000), 848);
    expect(snapToColumns(100, colW, gutter, 2000), 400,
        reason: 'never below one column');
    expect(snapToColumns(1900, colW, gutter, 1000), 848,
        reason: 'never beyond the available space');
  });
  _moveTests();
  _historyTests();

  test('badges go to sender-capable panes only and persist', () {
    final f = _Fixture();
    f.model.ensureBadges();
    expect(f.a.badge, '1');
    expect(f.b.badge, isNull, reason: 'receive-only panes carry no badge');
    expect(f.c.badge, '2');
    f.model.removePane(f.a.id);
    final d = PaneSpec(kind: PaneKind.text);
    f.model.columns.last.panes.add(d);
    f.model.ensureBadges();
    expect(d.badge, '1', reason: 'freed badge reused');
    expect(f.c.badge, '2', reason: 'existing badges never change');
    final decoded = LayoutModel.decode(f.model.encode())!;
    expect(decoded.allPanes.map((p) => p.badge).toList(), [null, '2', '1']);
  });

  test('stray badges on receive-only panes are stripped on load', () {
    final f = _Fixture();
    f.b.badge = '9';
    f.model.ensureBadges();
    expect(f.b.badge, isNull);
  });

  test('badge index maps into the badge alphabet', () {
    final p = PaneSpec(kind: PaneKind.text, badge: 'a');
    expect(p.badgeIndex, 9);
  });
}

// Rearrangement operations (drag-to-rearrange).
class _Fixture {
  _Fixture() {
    a = PaneSpec(kind: PaneKind.text, module: 'a');
    b = PaneSpec(kind: PaneKind.footnotes, follow: a.id);
    c = PaneSpec(kind: PaneKind.text, module: 'c');
    model = LayoutModel([
      PaneColumn(panes: [a, b]),
      PaneColumn(panes: [c]),
    ]);
  }
  late PaneSpec a, b, c;
  late LayoutModel model;
}

void _moveTests() {
  test('a pane can move into another stack at a position', () {
    final f = _Fixture();
    f.model.moveIntoStack(f.c.id, f.model.columns[0], 1);
    expect(f.model.columns.length, 1, reason: 'emptied column removed');
    expect(f.model.columns[0].panes.map((p) => p.id).toList(),
        [f.a.id, f.c.id, f.b.id]);
    expect(f.model.byId(f.b.id)!.follow, f.a.id,
        reason: 'links survive rearrangement');
  });

  test('a pane can leave a stack to become a new column', () {
    final f = _Fixture();
    f.model.moveToNewColumn(f.b.id, after: f.model.columns[1]);
    expect(f.model.columns.length, 3);
    expect(f.model.columns[0].panes.single.id, f.a.id);
    expect(f.model.columns[2].panes.single.id, f.b.id);
  });

  test('moving to a new leftmost column', () {
    final f = _Fixture();
    f.model.moveToNewColumn(f.c.id, after: null);
    expect(f.model.columns.first.panes.single.id, f.c.id);
    expect(f.model.columns.length, 2, reason: 'old singleton column removed');
  });

  test('reordering within the same stack adjusts for removal', () {
    final f = _Fixture();
    f.model.moveIntoStack(f.a.id, f.model.columns[0], 2);
    expect(f.model.columns[0].panes.map((p) => p.id).toList(),
        [f.b.id, f.a.id]);
  });

  test('moving a sole pane to a new column beside itself is harmless', () {
    final f = _Fixture();
    f.model.moveToNewColumn(f.c.id, after: f.model.columns[1]);
    expect(f.model.columns.length, 2);
    expect(f.model.columns[1].panes.single.id, f.c.id);
  });
}

void _historyTests() {
  test('deliberate jumps push the departure and the target', () {
    final f = _Fixture();
    f.a.anchor = 'Gen.1.1';
    f.model.recordNavigation(f.a.id, 'Gen.3.1');
    expect(f.model.history.map((e) => e.osis).toList(),
        ['Gen.1.1', 'Gen.3.1']);
    expect(f.model.historyCursor, 1);
    expect(f.model.canGoBack, isTrue);
    expect(f.model.canGoForward, isFalse);
  });

  test('back and forward move the cursor and return entries', () {
    final f = _Fixture();
    f.a.anchor = 'Gen.1.1';
    f.model.recordNavigation(f.a.id, 'Gen.3.1');
    f.a.anchor = 'Gen.3.1';
    f.model.recordNavigation(f.a.id, 'Exod.1.1');
    final back = f.model.goBack()!;
    expect(back.osis, 'Gen.3.1');
    final back2 = f.model.goBack()!;
    expect(back2.osis, 'Gen.1.1');
    expect(f.model.canGoBack, isFalse);
    final forward = f.model.goForward()!;
    expect(forward.osis, 'Gen.3.1');
    expect(f.model.canGoForward, isTrue);
  });

  test('navigating after going back truncates the forward tail', () {
    final f = _Fixture();
    f.a.anchor = 'Gen.1.1';
    f.model.recordNavigation(f.a.id, 'Gen.3.1');
    f.a.anchor = 'Gen.3.1';
    f.model.goBack();
    f.a.anchor = 'Gen.1.1';
    f.model.recordNavigation(f.a.id, 'Exod.1.1');
    expect(f.model.history.map((e) => e.osis).toList(),
        ['Gen.1.1', 'Exod.1.1']);
    expect(f.model.canGoForward, isFalse);
  });

  test('history survives encoding and prunes removed panes', () {
    final f = _Fixture();
    f.a.anchor = 'Gen.1.1';
    f.model.recordNavigation(f.a.id, 'Gen.3.1');
    f.c.anchor = 'Exod.1.1';
    f.model.recordNavigation(f.c.id, 'Exod.2.1');
    final decoded = LayoutModel.decode(f.model.encode())!;
    expect(decoded.history.length, 4);
    expect(decoded.historyCursor, 3);
    decoded.removePane(decoded.byId(f.c.id)!.id);
    expect(decoded.history.length, 2,
        reason: 'entries of removed panes are pruned');
    expect(decoded.historyCursor, 1);
  });

  test('duplicate departures are not pushed twice', () {
    final f = _Fixture();
    f.a.anchor = 'Gen.1.1';
    f.model.recordNavigation(f.a.id, 'Gen.3.1');
    f.a.anchor = 'Gen.3.1';
    f.model.recordNavigation(f.a.id, 'Gen.5.1');
    expect(f.model.history.map((e) => e.osis).toList(),
        ['Gen.1.1', 'Gen.3.1', 'Gen.5.1']);
  });

  test('jumping into history places the cursor there', () {
    final f = _Fixture();
    f.a.anchor = 'Gen.1.1';
    f.model.recordNavigation(f.a.id, 'Gen.3.1');
    f.a.anchor = 'Gen.3.1';
    f.model.recordNavigation(f.a.id, 'Exod.1.1');
    final entry = f.model.jumpToHistory(0)!;
    expect(entry.osis, 'Gen.1.1');
    expect(f.model.historyCursor, 0);
    expect(f.model.canGoForward, isTrue);
  });

  test('column snapping never exceeds the available width', () {
    // 400px columns, 48px gutter, generous space: snaps to whole columns.
    expect(snapToColumns(430, 400, 48, 1200), 400);
    expect(snapToColumns(700, 400, 48, 1200), 848);
    // The snapped width always fits what is available.
    expect(snapToColumns(700, 400, 48, 800), 400);
  });

  test('column snapping leaves the width alone on narrow screens', () {
    // A portrait phone: not even one whole 400px column fits in the space
    // left of the divider — the user's drag position must survive, never a
    // forced overflow past the screen edge.
    expect(snapToColumns(180, 400, 48, 220), 180);
    expect(snapToColumns(140, 400, 48, 100), 140);
  });

  test('decode sanitizes corrupted weights', () {
    final model = LayoutModel([
      PaneColumn(panes: [PaneSpec(kind: PaneKind.text)], weight: -0.4),
      PaneColumn(
          panes: [PaneSpec(kind: PaneKind.text, weight: 0.0)], weight: 2),
    ]);
    final decoded = LayoutModel.decode(model.encode())!;
    expect(decoded.columns[0].weight, 1.0,
        reason: 'negative column weights reset so the pane stays reachable');
    expect(decoded.columns[0].panes[0].weight, 1.0);
    expect(decoded.columns[1].weight, 2.0, reason: 'valid weights survive');
    expect(decoded.columns[1].panes[0].weight, 1.0,
        reason: 'zero pane weights reset');
  });
}
