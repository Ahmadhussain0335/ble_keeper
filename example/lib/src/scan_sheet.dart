import 'dart:async';

import 'package:flutter/material.dart';
import 'package:universal_ble/universal_ble.dart';

import 'device_controller.dart';

/// Finds the test device and returns its ID. Example only: ble_keeper does
/// not scan. On iOS this is the only way to get a peripheral identifier,
/// because iOS assigns it per app install.
Future<String?> showScanSheet(BuildContext context) =>
    showModalBottomSheet<String>(
      context: context,
      builder: (_) => const _ScanSheet(),
    );

class _ScanSheet extends StatefulWidget {
  const _ScanSheet();

  @override
  State<_ScanSheet> createState() => _ScanSheetState();
}

class _ScanSheetState extends State<_ScanSheet> {
  final Map<String, BleDevice> _found = {};
  StreamSubscription<BleDevice>? _sub;
  String? _error;

  @override
  void initState() {
    super.initState();
    _sub = UniversalBle.scanStream.listen(
      (d) => setState(() => _found[d.deviceId] = d),
    );
    // universal_ble ORs the conditions: a device matches by the test service
    // UUID or by name (phone peripherals may put the UUID only in the scan
    // response on some stacks).
    UniversalBle.startScan(
      scanFilter: ScanFilter(
        withServices: [testServiceUuid],
        withNamePrefix: [testDeviceName],
      ),
    ).catchError((Object e) => setState(() => _error = '$e'));
  }

  @override
  void dispose() {
    _sub?.cancel();
    UniversalBle.stopScan().catchError((_) {});
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final devices = _found.values.toList()
      ..sort((a, b) => (b.rssi ?? -999).compareTo(a.rssi ?? -999));
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ListTile(
            title: Text('Scanning for the test service or BLE-Test-Device'),
            trailing: SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final d in devices)
                  ListTile(
                    title: Text(d.name ?? '(no name)'),
                    subtitle: Text(d.deviceId),
                    trailing: Text('${d.rssi ?? '?'} dBm'),
                    onTap: () => Navigator.pop(context, d.deviceId),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
