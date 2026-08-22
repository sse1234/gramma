import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:gramma/src/rust/api/references.dart';
import 'package:gramma/src/rust/frb_generated.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => await RustLib.init());
  test('bridge round trip parses a reference on device', () {
    final outcome = parseReference(input: 'Joh 3,16');
    expect(outcome.osis, 'John.3.16');
    expect(outcome.error, isNull);
  });
}
