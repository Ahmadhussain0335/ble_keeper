import Foundation

/// Checks the app's Info.plist before any CBCentralManager is created,
/// because both problems below terminate the app:
/// - Without `NSBluetoothAlwaysUsageDescription`, creating a manager crashes
///   (privacy-sensitive data access without a usage description).
/// - A restore identifier without `UIBackgroundModes` = `bluetooth-central`
///   raises an exception: state restoration is only allowed for apps with
///   that background mode.
struct ConfigurationChecker {
  let info: [String: Any]

  init(info: [String: Any] = Bundle.main.infoDictionary ?? [:]) {
    self.info = info
  }

  var hasUsageDescription: Bool {
    guard let text = info["NSBluetoothAlwaysUsageDescription"] as? String else { return false }
    return !text.trimmingCharacters(in: .whitespaces).isEmpty
  }

  var hasBackgroundMode: Bool {
    (info["UIBackgroundModes"] as? [String])?.contains("bluetooth-central") ?? false
  }

  var appVersion: String {
    let short = info["CFBundleShortVersionString"] as? String ?? "?"
    let build = info["CFBundleVersion"] as? String ?? "?"
    return "\(short)+\(build)"
  }

  /// Problems to report as `Blocked(misconfigured)`.
  var problems: [String] {
    var result: [String] = []
    if !hasUsageDescription {
      result.append("Info.plist is missing NSBluetoothAlwaysUsageDescription; Bluetooth is disabled")
    }
    if !hasBackgroundMode {
      result.append(
        "Info.plist UIBackgroundModes is missing bluetooth-central; connections stop when the app is suspended and state restoration is disabled"
      )
    }
    return result
  }
}
