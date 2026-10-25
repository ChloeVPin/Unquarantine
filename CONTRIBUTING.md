# Contributing

Thanks for taking an interest in Unquarantine. Keep changes focused and keep
the app native: its interface is written in SwiftUI and uses standard macOS
controls and services.

## Before opening a pull request

- Describe the user-facing change and why it helps.
- For a visual change, include a short screen capture when it adds useful
  context.
- Keep new dependencies and background work to a minimum.
- Build with `./scripts/build-app.sh` using Xcode with the macOS 27 SDK. The
  resulting universal app supports macOS 26 and later on Apple silicon, and
  macOS 26 on Intel.

Please do not include app bundles, disk images, private data, or local build
products in a change. For a security issue, follow [SECURITY.md](SECURITY.md)
instead of opening a public issue.
