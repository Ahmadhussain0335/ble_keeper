import 'dart:io';

import 'package:ble_keeper/ble_keeper.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'device_controller.dart';
import 'permissions.dart';
import 'scan_sheet.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.controller});

  final DeviceController controller;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const _debugChannel = MethodChannel('ble_keeper_example/debug');
  final _deviceId = TextEditingController();

  DeviceController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    // After a restart the plugin still keeps the device connected; show it.
    _c.adoptActiveDevice().then((id) {
      if (id != null && mounted && _deviceId.text.isEmpty) _deviceId.text = id;
    });
  }

  @override
  void dispose() {
    _deviceId.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    final id = await showScanSheet(context);
    if (id != null) _deviceId.text = id;
  }

  Future<void> _permissions() async {
    final denied = await requestBlePermissions();
    _snack(
      denied.isEmpty ? 'Permissions granted' : 'Denied: ${denied.join(', ')}',
    );
  }

  Future<void> _exportLog() async {
    try {
      final path = await BleKeeper.instance.exportLog();
      await SharePlus.instance.share(
        ShareParams(files: [XFile(path)], subject: 'ble_keeper log'),
      );
    } on Object catch (e) {
      _snack('Export failed: $e');
    }
  }

  Future<void> _clearLog() async {
    await BleKeeper.instance.clearLog();
    _snack('Log cleared');
  }

  /// Debug and profile builds on iOS only: SIGKILL simulates the system
  /// terminating the app. Core Bluetooth state restoration should relaunch it
  /// in the background on the next event from the device. Restoration tests
  /// need a profile build: iOS cannot relaunch a debug Flutter app itself.
  Future<void> _simulateKill() =>
      _debugChannel.invokeMethod('simulateSystemKill');

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ble_keeper test')),
      body: ValueListenableBuilder<DeviceState>(
        valueListenable: _c.state,
        builder: (context, s, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _deviceId,
                    decoration: InputDecoration(
                      labelText: Platform.isIOS
                          ? 'Peripheral UUID'
                          : 'MAC address',
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Scan',
                  onPressed: _scan,
                  icon: const Icon(Icons.bluetooth_searching),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: () => _c.keep(_deviceId.text),
                  child: const Text('Keep connected'),
                ),
                OutlinedButton(onPressed: _c.stop, child: const Text('Stop')),
                if (Platform.isAndroid)
                  OutlinedButton(
                    onPressed: _permissions,
                    child: const Text('Permissions'),
                  ),
                // Debug only, for checklist test 15: press Home within 10 s so
                // keepConnected runs while the app is in the background.
                if (kDebugMode && Platform.isAndroid)
                  OutlinedButton(
                    onPressed: () {
                      final id = _deviceId.text;
                      _snack('keepConnected in 10 s: press Home now');
                      Future<void>.delayed(
                        const Duration(seconds: 10),
                        () => _c.keep(id),
                      );
                    },
                    child: const Text('Keep connected in 10 s (debug)'),
                  ),
              ],
            ),
            const Divider(height: 32),
            _StatusCard(state: s),
            const SizedBox(height: 16),
            Text(
              'Device commands',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final cmd in ['disconnect', 'reboot', 'silent'])
                  OutlinedButton(
                    onPressed: s.link == LinkState.connected
                        ? () => _c.sendCommand(cmd)
                        : null,
                    child: Text(cmd),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: _exportLog,
                  child: const Text('Export log'),
                ),
                OutlinedButton(
                  onPressed: _clearLog,
                  child: const Text('Clear log'),
                ),
                if ((kDebugMode || kProfileMode) && Platform.isIOS)
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                    ),
                    onPressed: _simulateKill,
                    child: const Text('Simulate system kill'),
                  ),
              ],
            ),
            const Divider(height: 32),
            Text('Events', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            for (final line in s.log.reversed.take(200))
              Text(
                line,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.state});

  final DeviceState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'State: ${state.link.name}',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Counter: ${state.counter ?? '-'}',
              style: theme.textTheme.displaySmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Received ${state.received}   Missed ${state.missed}   Resets ${state.resets}',
            ),
            if (state.lastProblem != null) ...[
              const SizedBox(height: 8),
              Text(
                state.lastProblem!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
