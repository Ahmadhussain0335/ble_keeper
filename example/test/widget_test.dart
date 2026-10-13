import 'package:ble_keeper/ble_keeper.dart';
import 'package:ble_keeper/ble_keeper_platform_interface.dart';
import 'package:ble_keeper_example/main.dart';
import 'package:ble_keeper_example/src/device_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_platform.dart';

void main() {
  testWidgets('shows counter and missed values from events', (tester) async {
    final fake = FakePlatform();
    BleKeeperPlatform.instance = fake;
    final controller = DeviceController(BleKeeper.instance);

    await tester.pumpWidget(ExampleApp(controller: controller));
    expect(find.text('Counter: -'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'AA:BB:CC:DD:EE:FF');
    await tester.tap(find.text('Keep connected'));
    await tester.pump();
    expect(fake.calls, ['keep AA:BB:CC:DD:EE:FF']);

    fake.controller
      ..add(counterData(41))
      ..add(counterData(44));
    await tester.pump();

    expect(find.text('Counter: 44'), findsOneWidget);
    expect(find.textContaining('Missed 2'), findsOneWidget);
    expect(find.text('State: connected'), findsOneWidget);
  });
}
