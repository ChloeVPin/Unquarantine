import Darwin
import Dispatch
import Foundation

@MainActor
final class ApplicationsDirectoryMonitor {
  static let knownDefaultsKey = "knownQuarantinedApps"
  static let handoffDirectory = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/Unquarantine")
  static let pendingDirectory = handoffDirectory.appendingPathComponent("pending-app")

  private let applications = URL(fileURLWithPath: "/Applications")
  private let debounceInterval: Duration = .milliseconds(500)
  private var source: DispatchSourceFileSystemObject?
  private var rescanTask: Task<Void, Never>?

  var onCandidateChange: (() -> Void)?

  static func registerDefaults() {
    UserDefaults.standard.register(defaults: [knownDefaultsKey: [:]])
  }

  func start() {
    guard source == nil else { return }

    let fd = Darwin.open(applications.path, O_EVTONLY)
    guard fd >= 0 else { return }

    let source = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: fd,
      eventMask: [.write, .rename, .delete, .extend, .attrib],
      queue: .main
    )
    source.setEventHandler { [weak self] in
      Task { @MainActor in self?.scheduleRescan() }
    }
    source.setCancelHandler { close(fd) }

    self.source = source
    source.resume()
    scheduleRescan()
  }

  func stop() {
    rescanTask?.cancel()
    rescanTask = nil
    source?.cancel()
    source = nil
  }

  private func scheduleRescan() {
    rescanTask?.cancel()
    rescanTask = Task { @MainActor [weak self] in
      guard let self else { return }
      do {
        try await Task.sleep(for: debounceInterval)
      } catch {
        return
      }
      onCandidateChange?()
    }
  }

  static func scanForFreshCandidates() -> [QuarantineCandidate] {
    let contents =
      (try? FileManager.default.contentsOfDirectory(
        at: URL(fileURLWithPath: "/Applications"),
        includingPropertiesForKeys: [.quarantinePropertiesKey, .isApplicationKey],
        options: [.skipsHiddenFiles]
      )) ?? []

    let quarantinedApps = contents.filter {
      $0.pathExtension == "app" && QuarantineService.isQuarantined($0)
    }

    var known =
      UserDefaults.standard.dictionary(forKey: knownDefaultsKey) as? [String: String] ?? [:]
    let freshApps = quarantinedApps.filter { known[$0.path] == nil }
    for app in quarantinedApps {
      known[app.path] = app.lastPathComponent
    }
    UserDefaults.standard.set(known, forKey: knownDefaultsKey)

    return freshApps.map { QuarantineCandidate(url: $0, isQuarantined: true) }
  }

  static func drainHandoff() -> [URL] {
    let fileManager = FileManager.default
    let entries =
      (try? fileManager.contentsOfDirectory(at: pendingDirectory, includingPropertiesForKeys: nil))
      ?? []

    return entries.compactMap { entry in
      guard entry.pathExtension == "txt",
        let data = try? Data(contentsOf: entry),
        let path = String(data: data, encoding: .utf8)
      else { return nil }

      try? fileManager.removeItem(at: entry)
      let appURL = URL(fileURLWithPath: path.trimmingCharacters(in: .whitespacesAndNewlines))
      return appURL.pathExtension == "app" ? appURL : nil
    }
  }

  static func markKnown(_ urls: [URL]) {
    var known =
      UserDefaults.standard.dictionary(forKey: knownDefaultsKey) as? [String: String] ?? [:]
    for url in urls {
      known[url.path] = url.lastPathComponent
    }
    UserDefaults.standard.set(known, forKey: knownDefaultsKey)
  }
}
