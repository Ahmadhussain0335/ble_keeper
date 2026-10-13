import 'dart:async';
import 'dart:typed_data';

import 'package:ble_keeper/ble_keeper.dart';
import 'package:flutter/material.dart';

final counterChar = CharacteristicRef(
  serviceUuid: '12345678-1234-1234-1234-1234567890ab',
  characteristicUuid: '12345678-1234-1234-1234-1234567890ac',
);

void main() => runApp(const MaterialApp(home: CounterPage()));

class CounterPage extends StatefulWidget {
  const CounterPage({super.key});

  @override
  State<CounterPage> createState() => _CounterPageState();
}

class _CounterPageState extends State<CounterPage> {
  final _deviceId = TextEditingController();
  StreamSubscription<KeeperEvent>? _sub;
  String _status = 'idle';
  int? _counter;

  @override
  void initState() {
    super.initState();
    _sub = BleKeeper.instance.events.listen(_onEvent);
  }

  void _onEvent(KeeperEvent e) {
    setState(() {
      if (e is Data && e.bytes.length >= 4) {
        _counter = ByteData.sublistView(e.bytes).getUint32(0, Endian.little);
      } else if (e is! Data) {
        _status = e.toString();
      }
    });
  }

  Future<void> _keep() async {
    try {
      await BleKeeper.instance.keepConnected(
        deviceId: _deviceId.text,
        subscribe: [counterChar],
      );
    } on Object catch (e) {
      setState(() => _status = 'error: $e');
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _deviceId.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ble_keeper')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _deviceId,
              decoration: const InputDecoration(labelText: 'Device ID'),
            ),
            const SizedBox(height: 8),
            FilledButton(onPressed: _keep, child: const Text('Keep connected')),
            const SizedBox(height: 24),
            Text(
              'Counter: ${_counter ?? '-'}',
              style: const TextStyle(fontSize: 32),
            ),
            Text(_status),
          ],
        ),
      ),
    );
  }
}
