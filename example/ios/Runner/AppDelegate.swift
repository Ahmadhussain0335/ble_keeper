import Flutter
import UIKit
import ble_keeper

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Must run before super: when iOS relaunches the app in the background
    // for Core Bluetooth, no scene (and no UI engine) is created, so the
    // plugin's normal registration never happens.
    BleKeeperPlugin.bootstrap(launchOptions: launchOptions) { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    #if DEBUG
      // Debug builds only: lets the example simulate the system terminating
      // the app (state restoration should relaunch it on the next BLE event).
      let channel = FlutterMethodChannel(
        name: "ble_keeper_example/debug",
        binaryMessenger: engineBridge.applicationRegistrar.messenger())
      channel.setMethodCallHandler { call, result in
        if call.method == "simulateSystemKill" {
          kill(getpid(), SIGKILL)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    #endif
  }
}
