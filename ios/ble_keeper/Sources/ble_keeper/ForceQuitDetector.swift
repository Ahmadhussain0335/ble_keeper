import Foundation

/// Best-effort classification of how the previous launch ended.
///
/// iOS does not tell an app that the user force-quit it. Per Apple TN3115,
/// Core Bluetooth state restoration relaunches an app after the system
/// terminated it, after a crash and after a reboot (once the phone is
/// unlocked), but never after the user swiped it away in the app switcher.
/// So when connections were being kept, the plugin was not relaunched by
/// restoration, and the user is now opening the app, a force-quit is the
/// most likely cause.
///
/// Both outcomes that report a force-quit are guesses. Known false positives
/// (documented in the README):
/// - `applicationWillTerminate` also runs when the system terminates an app
///   that is running in the background (not suspended), for example under
///   memory pressure, so `.forceQuit` is only "likely".
/// - Bluetooth turned off in Settings while the app was suspended.
/// - A reboot after which the peripheral never came in range before the user
///   opened the app.
/// - A system termination with no Bluetooth event before the user opened
///   the app.
enum ForceQuitDetector {
  enum Outcome: Equatable {
    /// Nothing was being kept; nothing to report.
    case none
    /// Relaunched by Core Bluetooth state restoration.
    case restored
    /// `applicationWillTerminate` ran: the app was terminated while running
    /// (not suspended). Usually a swipe-away, but a system termination of a
    /// background-running app looks the same. Likely, not certain.
    case forceQuit
    /// Not restored, no other explanation. Weak signal.
    case probableForceQuit
    /// The app was updated; iOS terminates it and does not restore it.
    case appUpdated
  }

  static func classify(
    hadSessions: Bool,
    restored: Bool,
    willTerminateSeen: Bool,
    previousAppVersion: String?,
    currentAppVersion: String
  ) -> Outcome {
    guard hadSessions else { return .none }
    if restored { return .restored }
    if willTerminateSeen { return .forceQuit }
    if let previous = previousAppVersion, previous != currentAppVersion { return .appUpdated }
    return .probableForceQuit
  }
}
