# Architecture

Unquarantine is a native SwiftUI macOS app with no third-party package
dependencies. AppKit is used for standard macOS services such as file selection,
application icons, and launching apps.

## App flow

- `AppModel` owns the current flow and user preferences.
- `Views` and `SettingsView` present the main window, result states, and
  preferences.
- `QuarantineService` inspects apps and removes the quarantine attribute after
  the user approves the action.
- `DiskImageService` mounts `.dmg` and `.iso` files read-only, finds one app,
  and ejects the image at the end of the flow.
- `InstallService` copies an app into `/Applications` when needed. macOS
  performs that privileged copy after the user approves its administrator
  prompt.

## Background monitoring

When enabled, `LaunchAgentService` installs a user-level LaunchAgent and copies
the small `UnquarantineWatcher` executable into the user’s Application Support
folder. The watcher observes `/Applications`, records seen app paths in the
user defaults store, and hands new quarantined app paths back to the main app.
It opens `/Applications/Unquarantine.app` when available. Turning monitoring
off removes the LaunchAgent and copied helper.

## Build

The package targets macOS 26 and builds with the macOS 27 SDK. The build script
compiles both executables for arm64 and x86_64, combines each pair into a
universal binary, compiles the Icon Composer asset, assembles
`dist/Unquarantine.app`, and applies an ad-hoc signature for local use. macOS 27
supports Apple silicon; Intel Macs can run the app on macOS 26.
