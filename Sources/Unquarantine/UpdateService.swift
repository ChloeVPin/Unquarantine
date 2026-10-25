import AppKit
import CryptoKit
import Foundation
import Observation

struct AvailableUpdate: Equatable {
  let version: String
  let downloadURL: URL
  let sha256: String
  let size: Int
}

enum UpdateState: Equatable {
  case idle
  case checking
  case current
  case available
  case downloading
  case verifying
  case preparing
  case waitingForApproval
  case installing
  case checkFailed(String)
  case failed(String)
}

@MainActor
@Observable
final class UpdateService {
  private static let releaseURL =
    URL(string: "https://api.github.com/repos/ChloeVPin/Unquarantine/releases/latest")!
  private static let checkInterval: TimeInterval = 60 * 60 * 24

  var automaticallyChecksForUpdates: Bool {
    didSet {
      UserDefaults.standard.set(automaticallyChecksForUpdates, forKey: "automaticallyChecksForUpdates")
      if automaticallyChecksForUpdates {
        startAutomaticChecks()
      } else {
        automaticCheckTask?.cancel()
        automaticCheckTask = nil
      }
    }
  }

  var state: UpdateState = .idle
  var availableUpdate: AvailableUpdate?
  @ObservationIgnored private var automaticCheckTask: Task<Void, Never>?

  init() {
    automaticallyChecksForUpdates =
      UserDefaults.standard.object(forKey: "automaticallyChecksForUpdates") as? Bool ?? true
  }

  var isBusy: Bool {
    switch state {
    case .checking, .downloading, .verifying, .preparing, .waitingForApproval, .installing:
      return true
    case .idle, .current, .available, .checkFailed, .failed:
      return false
    }
  }

  var statusDescription: String {
    switch state {
    case .idle:
      return "Updates are checked once a day."
    case .checking:
      return "Checking for updates…"
    case .current:
      return "You’re up to date."
    case .available:
      return "Version \(availableUpdate?.version ?? "") is available."
    case .downloading:
      return "Downloading the update…"
    case .verifying:
      return "Verifying the download…"
    case .preparing:
      return "Preparing the update…"
    case .waitingForApproval:
      return "Approve the update in macOS to continue."
    case .installing:
      return "Unquarantine will reopen when the update is ready."
    case .checkFailed(let message):
      return message
    case .failed(let message):
      return message
    }
  }

  var showsUpdateBanner: Bool {
    guard availableUpdate != nil else { return false }
    switch state {
    case .available, .failed:
      return true
    case .downloading, .verifying, .preparing, .waitingForApproval, .installing:
      return true
    case .idle, .checking, .current, .checkFailed:
      return false
    }
  }

  func checkAutomaticallyIfNeeded() async {
    guard automaticallyChecksForUpdates else { return }
    let lastCheck = UserDefaults.standard.object(forKey: "lastUpdateCheck") as? Date ?? .distantPast
    guard Date().timeIntervalSince(lastCheck) >= Self.checkInterval else { return }
    await checkNow()
  }

  func startAutomaticChecks() {
    guard automaticallyChecksForUpdates else { return }
    automaticCheckTask?.cancel()
    automaticCheckTask = Task { @MainActor [weak self] in
      guard let self else { return }
      while !Task.isCancelled {
        await checkAutomaticallyIfNeeded()
        try? await Task.sleep(nanoseconds: 6 * 60 * 60 * 1_000_000_000)
      }
    }
  }

  func checkNow() async {
    guard !isBusy else { return }
    state = .checking

    do {
      let release = try await latestRelease()
      UserDefaults.standard.set(Date(), forKey: "lastUpdateCheck")
      availableUpdate = release
      state = release == nil ? .current : .available
    } catch let error as UpdateError {
      state = .checkFailed(error.localizedDescription)
    } catch {
      state = .checkFailed("Couldn’t check for updates. Try again when you’re online.")
    }
  }

  func installAvailableUpdate() async {
    guard let update = availableUpdate, !isBusy else { return }
    state = .downloading

    let workDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("UnquarantineUpdate-\(UUID().uuidString)", isDirectory: true)
    var installerStarted = false

    do {
      try FileManager.default.createDirectory(
        at: workDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
      )

      var request = URLRequest(url: update.downloadURL)
      request.timeoutInterval = 60
      let (temporaryDownload, response) = try await URLSession.shared.download(for: request)
      guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
        throw UpdateError.downloadFailed
      }

      let downloadedSize =
        (try FileManager.default.attributesOfItem(atPath: temporaryDownload.path)[.size] as? NSNumber)?
        .intValue ?? 0
      guard downloadedSize == update.size else { throw UpdateError.checksumMismatch }

      let digest = SHA256.hash(data: try Data(contentsOf: temporaryDownload, options: .mappedIfSafe))
        .map { String(format: "%02x", $0) }
        .joined()
      guard digest == update.sha256 else { throw UpdateError.checksumMismatch }

      let diskImage = workDirectory.appendingPathComponent("update.dmg")
      try FileManager.default.copyItem(at: temporaryDownload, to: diskImage)

      state = .preparing
      let replacement = try await extractAndVerifyApp(
        from: diskImage, update: update, workDirectory: workDirectory
      )
      let target = Bundle.main.bundleURL.standardizedFileURL
      try await beginReplacement(of: target, with: replacement, in: workDirectory)
      installerStarted = true
    } catch let error as UpdateError {
      state = .failed(error.localizedDescription)
    } catch {
      state = .failed("The update couldn’t be prepared. Your current copy is unchanged.")
    }

    if !installerStarted {
      try? FileManager.default.removeItem(at: workDirectory)
    }
  }

  private func latestRelease() async throws -> AvailableUpdate? {
    var request = URLRequest(url: Self.releaseURL)
    request.timeoutInterval = 15
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.setValue("Unquarantine/\(currentVersion)", forHTTPHeaderField: "User-Agent")
    request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

    let (data, response): (Data, URLResponse)
    do {
      (data, response) = try await URLSession.shared.data(for: request)
    } catch {
      throw UpdateError.couldNotCheck
    }
    guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
      throw UpdateError.couldNotCheck
    }

    let release: GitHubRelease
    do {
      release = try JSONDecoder().decode(GitHubRelease.self, from: data)
    } catch {
      throw UpdateError.invalidRelease
    }
    guard !release.draft, !release.prerelease,
      let version = SemanticVersion(release.tagName),
      let installedVersion = SemanticVersion(currentVersion),
      version > installedVersion
    else { return nil }

    let assetName = "Unquarantine-\(version.string)-\(architectureName).dmg"
    guard let asset = release.assets.first(where: { $0.name == assetName }),
      asset.size > 0, asset.size <= 100 * 1024 * 1024,
      let digest = asset.digest, digest.hasPrefix("sha256:"),
      let url = URL(string: asset.downloadURL), url.scheme == "https", url.host == "github.com"
    else { throw UpdateError.installerUnavailable }

    let checksum = String(digest.dropFirst("sha256:".count)).lowercased()
    guard checksum.count == 64, checksum.allSatisfy(\.isHexDigit) else {
      throw UpdateError.installerUnavailable
    }

    return AvailableUpdate(version: version.string, downloadURL: url, sha256: checksum, size: asset.size)
  }

  private func extractAndVerifyApp(
    from diskImage: URL,
    update: AvailableUpdate,
    workDirectory: URL
  ) async throws -> URL {
    state = .verifying
    let replacement = workDirectory.appendingPathComponent("Replacement.app", isDirectory: true)
    let mountedApp: MountedDiskImageApp

    do {
      mountedApp = try DiskImageService.mountApp(from: diskImage)
    } catch {
      throw UpdateError.invalidInstaller
    }
    defer { DiskImageService.eject(mountedApp) }

    guard mountedApp.appURL.lastPathComponent == "Unquarantine.app" else {
      throw UpdateError.invalidInstaller
    }
    _ = try await CommandRunner.run(
      "/usr/bin/ditto", arguments: [mountedApp.appURL.path, replacement.path]
    )

    guard let bundle = Bundle(url: replacement),
      bundle.bundleIdentifier == Bundle.main.bundleIdentifier,
      bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == update.version,
      let minimumVersion = bundle.object(forInfoDictionaryKey: "LSMinimumSystemVersion") as? String,
      let requiredOS = OperatingSystemVersion(string: minimumVersion),
      ProcessInfo.processInfo.isOperatingSystemAtLeast(requiredOS)
    else { throw UpdateError.invalidInstaller }

    try QuarantineService.removeQuarantine(on: replacement)
    do {
      _ = try await CommandRunner.run(
        "/usr/bin/codesign",
        arguments: ["--verify", "--deep", "--strict", replacement.path]
      )
    } catch {
      throw UpdateError.invalidInstaller
    }

    return replacement
  }

  private func beginReplacement(of target: URL, with replacement: URL, in workDirectory: URL) async throws {
    let volume = try? target.resourceValues(forKeys: [.volumeIsReadOnlyKey])
    guard volume?.volumeIsReadOnly != true,
      !target.path.hasPrefix("/System/")
    else { throw UpdateError.moveToApplications }

    let needsAdministrator = !FileManager.default.isWritableFile(
      atPath: target.deletingLastPathComponent().path
    )
    let marker = workDirectory.appendingPathComponent("ready-to-replace")
    let backup = target.deletingLastPathComponent().appendingPathComponent(
      "\(target.lastPathComponent).update-backup-\(UUID().uuidString)"
    )
    let command = Self.replacementCommand(
      processID: ProcessInfo.processInfo.processIdentifier,
      target: target,
      backup: backup,
      replacement: replacement,
      workDirectory: workDirectory,
      marker: marker
    )

    let process = Process()
    if needsAdministrator {
      process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
      process.arguments = [
        "-e",
        "do shell script \(Self.appleScriptQuoted(command)) with administrator privileges with prompt \(Self.appleScriptQuoted("Unquarantine needs permission to replace itself in this location."))",
      ]
      state = .waitingForApproval
    } else {
      process.executableURL = URL(fileURLWithPath: "/bin/sh")
      process.arguments = ["-c", command]
      state = .installing
    }
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice

    do {
      try process.run()
    } catch {
      throw UpdateError.installFailed
    }
    while process.isRunning {
      if FileManager.default.fileExists(atPath: marker.path) {
        state = .installing
        NSApplication.shared.terminate(nil)
        return
      }
      try await Task.sleep(nanoseconds: 150_000_000)
    }

    if FileManager.default.fileExists(atPath: marker.path) {
      state = .installing
      NSApplication.shared.terminate(nil)
      return
    }
    throw UpdateError.approvalCanceled
  }

  private var currentVersion: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
  }

  private var architectureName: String {
    #if arch(arm64)
      return "AppleSilicon"
    #else
      return "Intel"
    #endif
  }

  private static func replacementCommand(
    processID: Int32,
    target: URL,
    backup: URL,
    replacement: URL,
    workDirectory: URL,
    marker: URL
  ) -> String {
    let targetPath = shellQuoted(target.path)
    let backupPath = shellQuoted(backup.path)
    let replacementPath = shellQuoted(replacement.path)
    let workPath = shellQuoted(workDirectory.path)

    return """
    /usr/bin/touch \(shellQuoted(marker.path))
    while /bin/kill -0 \(processID) 2>/dev/null; do /bin/sleep 0.2; done
    if [ -e \(targetPath) ]; then
      /bin/mv \(targetPath) \(backupPath) || {
        /usr/bin/open \(targetPath) >/dev/null 2>&1 || true
        /bin/rm -rf \(workPath) 2>/dev/null || true
        exit 1
      }
    fi
    if /usr/bin/ditto --rsrc --extattr \(replacementPath) \(targetPath); then
      /bin/rm -rf \(backupPath) 2>/dev/null || true
      /usr/bin/open \(targetPath) >/dev/null 2>&1 || true
      /bin/rm -rf \(workPath) 2>/dev/null || true
    else
      /bin/rm -rf \(targetPath) 2>/dev/null || true
      /bin/mv \(backupPath) \(targetPath) 2>/dev/null || true
      /usr/bin/open \(targetPath) >/dev/null 2>&1 || true
      /bin/rm -rf \(workPath) 2>/dev/null || true
      exit 1
    fi
    """
  }

  private static func shellQuoted(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
  }

  private static func appleScriptQuoted(_ value: String) -> String {
    "\""
      + value
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"") + "\""
  }
}

private enum UpdateError: Error, LocalizedError {
  case couldNotCheck
  case invalidRelease
  case installerUnavailable
  case downloadFailed
  case checksumMismatch
  case invalidInstaller
  case moveToApplications
  case installFailed
  case approvalCanceled

  var errorDescription: String? {
    switch self {
    case .couldNotCheck:
      return "Couldn’t check for updates. Try again when you’re online."
    case .invalidRelease, .installerUnavailable:
      return "A compatible update isn’t available for this Mac."
    case .downloadFailed:
      return "The update couldn’t be downloaded. Try again in a moment."
    case .checksumMismatch:
      return "The download didn’t match its published checksum. Nothing was installed."
    case .invalidInstaller:
      return "The update couldn’t be verified. Your current copy is unchanged."
    case .moveToApplications:
      return "Move Unquarantine to Applications before updating."
    case .installFailed:
      return "The update couldn’t be started. Your current copy is unchanged."
    case .approvalCanceled:
      return "The update was canceled. Your current copy is unchanged."
    }
  }
}

private struct GitHubRelease: Decodable {
  let tagName: String
  let draft: Bool
  let prerelease: Bool
  let assets: [Asset]

  enum CodingKeys: String, CodingKey {
    case tagName = "tag_name"
    case draft
    case prerelease
    case assets
  }

  struct Asset: Decodable {
    let name: String
    let downloadURL: String
    let digest: String?
    let size: Int

    enum CodingKeys: String, CodingKey {
      case name
      case downloadURL = "browser_download_url"
      case digest
      case size
    }
  }
}

private struct SemanticVersion: Comparable {
  let components: [Int]

  var string: String { components.map(String.init).joined(separator: ".") }

  init?(_ value: String) {
    let trimmed = value.hasPrefix("v") ? String(value.dropFirst()) : value
    let parts = trimmed.split(separator: ".")
    guard parts.count == 3 else { return nil }
    let numbers = parts.compactMap { Int($0) }
    guard numbers.count == 3 else { return nil }
    components = numbers
  }

  static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
    lhs.components.lexicographicallyPrecedes(rhs.components)
  }
}

private enum CommandRunner {
  static func run(_ executable: String, arguments: [String]) async throws -> String {
    try await Task.detached(priority: .utility) {
      let process = Process()
      let output = Pipe()
      process.executableURL = URL(fileURLWithPath: executable)
      process.arguments = arguments
      process.standardOutput = output
      process.standardError = output
      do {
        try process.run()
      } catch {
        throw UpdateError.invalidInstaller
      }
      process.waitUntilExit()
      let data = output.fileHandleForReading.readDataToEndOfFile()
      guard process.terminationStatus == 0 else { throw UpdateError.invalidInstaller }
      return String(data: data, encoding: .utf8) ?? ""
    }.value
  }
}

private extension OperatingSystemVersion {
  init?(string: String) {
    let parts = string.split(separator: ".").compactMap { Int($0) }
    guard !parts.isEmpty else { return nil }
    self.init(
      majorVersion: parts[0],
      minorVersion: parts.count > 1 ? parts[1] : 0,
      patchVersion: parts.count > 2 ? parts[2] : 0
    )
  }
}
