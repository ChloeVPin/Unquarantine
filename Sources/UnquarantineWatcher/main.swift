import Darwin
import Dispatch
import Foundation

final class ApplicationsWatcher {
  private let applications = URL(fileURLWithPath: "/Applications")
  private let pendingDirectory: URL
  private let queue = DispatchQueue(label: "tools.unquarantine.watcher")
  private var known: Set<String> = []
  private let knownDefaultsKey = "watcherKnownQuarantinedApps"
  private var debounce: DispatchWorkItem?
  private var source: DispatchSourceFileSystemObject?
  private let debounceInterval: TimeInterval = 0.75

  init() {
    let fm = FileManager.default
    let appSupport = fm.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support/Unquarantine")
    pendingDirectory = appSupport.appendingPathComponent("pending-app")
    try? fm.createDirectory(at: pendingDirectory, withIntermediateDirectories: true)
    known = loadKnown()
  }

  func startWatching() -> Bool {
    let path = applications.path
    let fd = Darwin.open(path, O_EVTONLY)
    guard fd >= 0 else { return false }

    let events: DispatchSource.FileSystemEvent = [.write, .rename, .delete, .extend, .attrib]
    let source = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: fd,
      eventMask: events,
      queue: queue
    )
    let watcher = self
    source.setEventHandler(qos: .unspecified) {
      watcher.scheduleRescan()
    }
    source.setCancelHandler(qos: .unspecified) {
      close(fd)
    }
    self.source = source
    source.resume()

    // Find apps that were already present when the watcher started.
    queue.async { [watcher] in
      watcher.performRescan()
    }
    return true
  }

  func stop() {
    source?.cancel()
    source = nil
  }

  // MARK: - Rescan

  private func scheduleRescan() {
    debounce?.cancel()
    let rescan = DispatchWorkItem { [watcher = self] in
      watcher.performRescan()
    }
    debounce = rescan
    queue.asyncAfter(deadline: .now() + debounceInterval, execute: rescan)
  }

  private func performRescan() {
    let fm = FileManager.default
    guard
      let contents = try? fm.contentsOfDirectory(
        at: applications,
        includingPropertiesForKeys: [.quarantinePropertiesKey, .isApplicationKey],
        options: [.skipsHiddenFiles]
      )
    else { return }

    var discovered: [URL] = []
    let current = Set(
      contents.compactMap { url -> String? in
        guard url.pathExtension == "app",
          let values = try? url.resourceValues(forKeys: [
            .isApplicationKey, .quarantinePropertiesKey,
          ]),
          values.isApplication == true
        else { return nil }
        if values.quarantineProperties != nil { discovered.append(url) }
        return url.path
      }
    )
    known.formIntersection(current)
    saveKnown()

    guard !discovered.isEmpty else { return }
    let fresh = discovered.filter { !known.contains($0.path) }
    guard !fresh.isEmpty else { return }

    for url in fresh {
      known.insert(url.path)
      stageForHandoff(url)
    }
    saveKnown()
    openMainApp()
  }

  // MARK: - Handoff + lifecycle

  private func stageForHandoff(_ url: URL) {
    let handoff =
      pendingDirectory
      .appendingPathComponent("\(UUID().uuidString).txt")
    try? Data(url.path.utf8).write(to: handoff, options: .atomic)
  }

  private func openMainApp() {
    let bundle = URL(fileURLWithPath: "/Applications/Unquarantine.app")
    guard FileManager.default.fileExists(atPath: bundle.path) else { return }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = ["-g", bundle.path]
    try? process.run()
    process.waitUntilExit()
  }

  private func loadKnown() -> Set<String> {
    Set(UserDefaults.standard.stringArray(forKey: knownDefaultsKey) ?? [])
  }

  private func saveKnown() {
    UserDefaults.standard.set(Array(known), forKey: knownDefaultsKey)
  }
}

let watcher = ApplicationsWatcher()
if watcher.startWatching() {
  dispatchMain()
}
exit(1)
