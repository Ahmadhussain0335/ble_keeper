import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

/// Requests the Android runtime permissions the example needs.
///
/// The plugin itself never requests permissions; it reports
/// `Blocked(PermissionMissing(...))` instead. On iOS, Core Bluetooth shows
/// its own prompt the first time Bluetooth is used, so nothing is requested
/// here.
///
/// Returns the permissions that are still denied.
Future<List<String>> requestBlePermissions() async {
  if (!Platform.isAndroid) return const [];
  final permissions = [
    Permission.bluetoothConnect, // connect (API 31+)
    Permission.bluetoothScan, // the example's scanner (API 31+)
    Permission.notification, // foreground-service notification (API 33+)
    // Scanning on Android 11 and lower needs location. The manifest limits
    // it to maxSdkVersion 30, so on newer versions it is denied and ignored.
    Permission.locationWhenInUse,
  ];
  final results = await permissions.request();
  return [
    for (final entry in results.entries)
      if (entry.key != Permission.locationWhenInUse &&
          !entry.value.isGranted &&
          !entry.value.isLimited)
        entry.key.toString(),
  ];
}
