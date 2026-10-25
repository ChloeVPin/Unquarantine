import Foundation

enum InstallError: Error, LocalizedError {
  case canceled
  case denied
  case nameConflict

  var errorDescription: String? {
    switch self {
    case .canceled: return "Administrator approval was canceled."
    case .denied: return "macOS wouldn’t allow approval."
    case .nameConflict: return "An app with that name already exists in Applications."
    }
  }
}

enum InstallService {
  static let applicationsURL = URL(fileURLWithPath: "/Applications")

  static func destinationName(for app: URL) -> String { app.lastPathComponent }

  static func install(app: URL) throws -> URL {
    let target = applicationsURL.appendingPathComponent(destinationName(for: app))
    guard !FileManager.default.fileExists(atPath: target.path) else {
      throw InstallError.nameConflict
    }

    let quotedTarget = shellQuoted(target.path)
    let quotedAttribute = shellQuoted(QuarantineService.quarantineAttribute)
    let copy = "cp -R \(shellQuoted(app.path)) \(quotedTarget)"
    let clearQuarantine =
      "if /usr/bin/xattr -p \(quotedAttribute) \(quotedTarget) >/dev/null 2>&1; then "
      + "/usr/bin/xattr -d \(quotedAttribute) \(quotedTarget); else :; fi"
    try runAsAdministrator(copy + " && " + clearQuarantine)
    return target
  }

  static func approveSelfInstall() throws {
    let selfBundle = applicationsURL.appendingPathComponent("Unquarantine.app")
    try selfInstallApprove(path: selfBundle.path)
  }

  static func selfInstallApprove(path: String) throws {
    let command =
      "xattr -d \(shellQuoted(QuarantineService.quarantineAttribute)) \(shellQuoted(path))"
    try runAsAdministrator(command)
  }

  private static func shellQuoted(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
  }

  private static func appleScriptString(_ value: String) -> String {
    "\""
      + value
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"") + "\""
  }

  private static func runAsAdministrator(_ command: String) throws {
    let script = "do shell script \(appleScriptString(command)) with administrator privileges"
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = ["-e", script]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    do {
      try process.run()
    } catch {
      throw InstallError.denied
    }
    process.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8)?.lowercased() ?? ""
    if output.contains("user canceled") { throw InstallError.canceled }
    guard process.terminationStatus == 0 else { throw InstallError.denied }
  }
}
