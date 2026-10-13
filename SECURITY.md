# Security policy

## Supported versions

Only the latest published version receives fixes.

## Reporting a vulnerability

Please do not open a public issue for security problems. Use GitHub's
private vulnerability reporting ("Report a vulnerability" on the Security tab
of https://github.com/YOUR_GITHUB_USERNAME/ble_keeper) or email
SECURITY_CONTACT_EMAIL.

Include the plugin version, platform and OS version, and steps to reproduce.
You will get an acknowledgement within 7 days. Fixes are released as a patch
version and noted in the CHANGELOG.

## Scope notes

- The plugin does no networking.
- It stores device identifiers and characteristic UUIDs on the device
  (Android `noBackupFilesDir`, iOS Application Support excluded from backup)
  and a rotating event log that the app can export. In release builds device
  identifiers in the log are pseudonymised and payload bytes are never
  logged.
- BLE link security (pairing, bonding, encryption) is the responsibility of
  the peripheral firmware and the app.
