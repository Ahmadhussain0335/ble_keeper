import 'package:ble_keeper/ble_keeper.dart';
import 'package:flutter/material.dart';

import 'src/device_controller.dart';
import 'src/home_page.dart';

/// Runs in a background isolate when the OS restarted the app without UI.
/// Keep it short; on iOS the app has only a few seconds per Bluetooth event.
@pragma('vm:entry-point')
void backgroundHandler(KeeperEvent event) {
  debugPrint('ble_keeper background: $event');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Register on every start: callback handles change when the app is updated.
  await BleKeeper.instance.registerBackgroundHandler(backgroundHandler);
  runApp(ExampleApp(controller: DeviceController(BleKeeper.instance)));
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key, required this.controller});

  final DeviceController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ble_keeper example',
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.light,
      ),
      home: HomePage(controller: controller),
    );
  }
}
