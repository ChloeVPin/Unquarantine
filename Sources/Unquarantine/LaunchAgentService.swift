import Darwin
import Foundation

enum LaunchAgentError: Error, LocalizedError {
  case couldNotStart
  case watcherNotFound

  var errorDescription: String? {
    switch self {
    case .couldNotStart: return "launchd couldn’t start the background watcher."
    case .watcherNotFound: return "The background watcher isn’t installed."
    }
  }
}

enum LaunchAgentService {
  static let label = "tools.unquarantine.watcher"
  static let plistName = "tools.unquarantine.watcher.plist"

  static var launchAgentsDir: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
  }
  static var plistURL: URL { launchAgentsDir.appendingPathComponent(plistName) }

  static var supportDir: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support/Unquarantine", isDirectory: true)
  }
  static var watcherCopy: URL { supportDir.appendingPathComponent("UnquarantineWatcher") }

  static func isInstalled() -> Bool {
    FileManager.default.fileExists(atPath: plistURL.path)
  }

  static func install(watcherBinary: URL) throws {
    let fm = FileManager.default
    guard fm.fileExists(atPath: watcherBinary.path) else {
      throw LaunchAgentError.watcherNotFound
    }

    try fm.createDirectory(at: launchAgentsDir, withIntermediateDirectories: true)
    try fm.createDirectory(at: supportDir, withIntermediateDirectories: true)

    // Stop an older copy before replacing the helper it points to.
    bootoutIfNeeded()
    try? fm.removeItem(at: watcherCopy)
    try fm.copyItem(at: watcherBinary, to: watcherCopy)

    let programPath = watcherCopy.path
    let plist: [String: Any] = [
      "Label": label,
      "ProgramArguments": [programPath],
      "RunAtLoad": true,
      "AssociatedBundleIdentifiers": ["tools.unquarantine.app"],
    ]
    let data = try PropertyListSerialization.data(
      fromPropertyList: plist, format: .xml, options: 0
    )
    try data.write(to: plistURL)

    // Enable for the user's login session and start it immediately.
    _ = runLaunchctl(["enable", "gui/\(uid)/\(label)"])
    guard runLaunchctl(["bootstrap", "gui/\(uid)", plistURL.path]) == 0 else {
      try? fm.removeItem(at: plistURL)
      try? fm.removeItem(at: watcherCopy)
      throw LaunchAgentError.couldNotStart
    }
  }

  static func uninstall() {
    bootoutIfNeeded()
    try? FileManager.default.removeItem(at: plistURL)
    try? FileManager.default.removeItem(at: watcherCopy)
  }

  static func bootoutIfNeeded() {
    _ = runLaunchctl(["bootout", "gui/\(uid)/\(label)"])
  }

  static var uid: String {
    String(getuid())
  }

  @discardableResult
  static func runLaunchctl(_ args: [String]) -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    process.arguments = args
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    do {
      try process.run()
      process.waitUntilExit()
      return process.terminationStatus
    } catch {
      return -1
    }
  }
}
