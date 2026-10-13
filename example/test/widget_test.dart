import 'dart:async';
import 'dart:typed_data';

import 'package:ble_keeper/ble_keeper.dart';
import 'package:ble_keeper/ble_keeper_platform_interface.dart';
import 'package:ble_keeper_example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakePlatform extends BleKeeperPlatform {
  final controller = StreamController<KeeperEvent>.broadcast();

  @override
  Stream<KeeperEvent> get events => controller.stream;
}

void main() {
  testWidgets('shows the counter from Data events', (tester) async {
    final fake = FakePlatform();
    BleKeeperPlatform.instance = fake;

    await tester.pumpWidget(const MaterialApp(home: CounterPage()));
    expect(find.text('Counter: -'), findsOneWidget);

    fake.controller.add(
      Data(
        deviceId: 'AA:BB:CC:DD:EE:FF',
        characteristic: counterChar,
        bytes: Uint8List.fromList([42, 0, 0, 0]),
        timestamp: DateTime(2026),
      ),
    );
    await tester.pump();

    expect(find.text('Counter: 42'), findsOneWidget);
  });
}
