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

  test('badges assign lowest unused characters and persist', () {
    final f = _Fixture();
    f.model.ensureBadges();
    expect(f.a.badge, '1');
    expect(f.b.badge, '2');
    expect(f.c.badge, '3');
    f.model.removePane(f.b.id);
    final d = PaneSpec(kind: PaneKind.text);
    f.model.columns.last.panes.add(d);
    f.model.ensureBadges();
    expect(d.badge, '2', reason: 'freed badge reused');
    expect(f.c.badge, '3', reason: 'existing badges never change');
    final decoded = LayoutModel.decode(f.model.encode())!;
    expect(decoded.allPanes.map((p) => p.badge).toList(), ['1', '3', '2']);
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
