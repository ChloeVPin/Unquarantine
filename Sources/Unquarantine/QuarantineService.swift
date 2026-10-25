import Foundation

enum QuarantineError: Error, LocalizedError {
  case couldNotChange
  case notAnApplication
  case pathUnreadable

  var errorDescription: String? {
    switch self {
    case .couldNotChange: return "macOS wouldn’t allow that change."
    case .notAnApplication: return "That file isn’t a supported app or disk image."
    case .pathUnreadable: return "That file couldn’t be read."
    }
  }
}

struct QuarantineCandidate: Identifiable, Hashable {
  let id = UUID()
  let url: URL
  let isQuarantined: Bool

  var name: String { url.deletingPathExtension().lastPathComponent }
}

typealias Candidate = QuarantineCandidate

enum QuarantineService {
  static let quarantineAttribute = "com.apple.quarantine"

  // MARK: - Inspect

  static func isQuarantined(_ url: URL) -> Bool {
    guard let values = try? url.resourceValues(forKeys: [.quarantinePropertiesKey]) else {
      return false
    }
    return values.quarantineProperties != nil
  }

  static func inspect(_ url: URL) throws -> QuarantineCandidate {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
      isDirectory.boolValue
    else {
      throw QuarantineError.notAnApplication
    }
    guard
      let values = try? url.resourceValues(forKeys: [
        .quarantinePropertiesKey,
        .isApplicationKey,
      ])
    else {
      throw QuarantineError.pathUnreadable
    }
    guard values.isApplication == true else {
      throw QuarantineError.notAnApplication
    }
    return QuarantineCandidate(
      url: url,
      isQuarantined: values.quarantineProperties != nil
    )
  }

  // MARK: - Remove quarantine

  static func removeQuarantine(on url: URL) throws {
    guard isQuarantined(url) else { return }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
    process.arguments = ["-d", quarantineAttribute, url.path]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try runTool(process)
    // Confirm that the flag was actually removed.
    if isQuarantined(url) {
      throw QuarantineError.couldNotChange
    }
  }

  private static func runTool(_ process: Process) throws {
    do {
      try process.run()
    } catch {
      throw QuarantineError.couldNotChange
    }
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      throw QuarantineError.couldNotChange
    }
  }
}
