// Runs on a device: `flutter test integration_test` from example/.
import 'package:ble_keeper/ble_keeper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native side answers activeDeviceIds', (tester) async {
    final ids = await BleKeeper.instance.activeDeviceIds();
    expect(ids, isA<List<String>>());
  });

  testWidgets('invalid device id is rejected by the platform', (tester) async {
    await expectLater(
      BleKeeper.instance.keepConnected(
        deviceId: 'not-an-id',
        subscribe: [
          CharacteristicRef(serviceUuid: '180d', characteristicUuid: '2a37'),
        ],
      ),
      throwsA(isA<BleKeeperException>()),
    );
  });
}
