import 'package:flutter_test/flutter_test.dart';
import 'package:gramma/desks.dart';

void main() {
  test('registry roundtrips through its encoding', () {
    final registry = DeskRegistry([
      DeskInfo(id: 'a1', name: 'Desk 1'),
      DeskInfo(id: 'b2', name: 'Study'),
    ]);
    final decoded = DeskRegistry.decode(registry.encode())!;
    expect(decoded.desks.length, 2);
    expect(decoded.byId('b2')!.name, 'Study');
    expect(decoded.desks.first.id, 'a1', reason: 'order preserved');
  });

  test('garbage decodes to null, never a crash', () {
    expect(DeskRegistry.decode(''), isNull);
    expect(DeskRegistry.decode('{"desks": []}'), isNull,
        reason: 'an empty desk list is unusable');
    expect(DeskRegistry.decode('{"desks": [{"id": 1}]}'), isNull);
    expect(DeskRegistry.decode('[1,2]'), isNull);
  });

  test('new desk names avoid collisions', () {
    final registry = DeskRegistry([
      DeskInfo(id: 'a', name: 'Desk 1'),
      DeskInfo(id: 'b', name: 'Desk 3'),
    ]);
    expect(registry.nextName('Desk'), 'Desk 4',
        reason: 'skips past any existing Desk n');
  });

  test('desk ids are unique', () {
    expect(newDeskId(), isNot(newDeskId()));
  });
}
