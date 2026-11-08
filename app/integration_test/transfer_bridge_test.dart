import 'package:aureon/src/transfers/aureon_storage_api.g.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android FlutterEngine is connected to the Room transfer queue', (tester) async {
    final transfers = await AureonStorageHostApi().listTransfers();
    expect(transfers, isA<List<TransferSnapshot>>());
  });
}
