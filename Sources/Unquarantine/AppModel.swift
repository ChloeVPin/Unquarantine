import AppKit
import Foundation
import Observation

enum AppPhase: Equatable {
  case idle
  case working(String)
  case confirming([Candidate])
  case installing([Candidate])
  case batchComplete(BatchSummary)
  case failed(ErrorMessage)
}

struct ErrorMessage: Equatable {
  let title: String
  let detail: String
}

struct BatchSummary: Equatable {
  var installed: [String] = []
  var skipped: [String] = []
  var failed: [String] = []

  var allGood: Bool { skipped.isEmpty && failed.isEmpty }
  var line: String {
    if allGood { return "Everything completed successfully." }
    let count = skipped.count + failed.count
    if !failed.isEmpty && !skipped.isEmpty {
      return "\(count) apps were skipped or couldn’t be prepared."
    }
    if !failed.isEmpty {
      return count == 1 ? "The app couldn’t be prepared." : "\(count) apps couldn’t be prepared."
    }
    return count == 1 ? "The app was skipped." : "\(count) apps were skipped."
  }
}

@MainActor
@Observable
final class AppModel {
  var autoWatch: Bool {
    didSet { UserDefaults.standard.set(autoWatch, forKey: "autoWatch") }
  }
  var openWhenFinished: Bool {
    didSet { UserDefaults.standard.set(openWhenFinished, forKey: "openWhenFinished") }
  }
  var quitAfterCompletion: Bool {
    didSet { UserDefaults.standard.set(quitAfterCompletion, forKey: "quitAfterCompletion") }
  }
  var wantsSelfInstall: Bool {
    didSet { UserDefaults.standard.set(wantsSelfInstall, forKey: "wantsSelfInstall") }
  }
  var liquidGlassPanes: Bool {
    didSet { UserDefaults.standard.set(liquidGlassPanes, forKey: "liquidGlassPanes") }
  }

  var phase: AppPhase = .idle
  var isDropTargeted: Bool = false
  var updater = UpdateService()
  var monitor = ApplicationsDirectoryMonitor()
  private var prepared: [Candidate: URL] = [:]
  // Disk image app URLs only stay valid while their image remains mounted.
  private var mountedImages: [UUID: MountedDiskImageApp] = [:]
  private var lastConfirmed: [Candidate]?

  var canRetryPreparation: Bool {
    lastConfirmed?.isEmpty == false
  }

  init() {
    autoWatch = UserDefaults.standard.bool(forKey: "autoWatch")
    openWhenFinished = UserDefaults.standard.bool(forKey: "openWhenFinished")
    quitAfterCompletion = UserDefaults.standard.bool(forKey: "quitAfterCompletion")
    wantsSelfInstall = UserDefaults.standard.bool(forKey: "wantsSelfInstall")
    liquidGlassPanes = UserDefaults.standard.object(forKey: "liquidGlassPanes") as? Bool ?? true
    ApplicationsDirectoryMonitor.registerDefaults()

    Task { @MainActor [weak self] in
      let drained = ApplicationsDirectoryMonitor.drainHandoff()
      let scanned = ApplicationsDirectoryMonitor.scanForFreshCandidates()
      let combined = drained + scanned.map(\.url)
      let fresh =
        combined
        .compactMap { try? QuarantineService.inspect($0) }
        .filter(\.isQuarantined)
      if !fresh.isEmpty, let model = self {
        model.phase = .confirming(fresh)
      }
      self?.updater.startAutomaticChecks()
    }
    // Refresh the installed helper so it stays in sync with app updates.
    if autoWatch {
      installWatcher()
      startMonitorIfNeeded()
    }
  }

  isolated deinit {
    for mountedApp in mountedImages.values {
      DiskImageService.eject(mountedApp)
    }
  }

  func startMonitorIfNeeded() {
    guard autoWatch else { return }
    monitor.onCandidateChange = { [weak self] in self?.pollFresh() }
    monitor.start()
  }

  func stopMonitor() {
    monitor.stop()
    monitor.onCandidateChange = nil
  }

  func setAutoWatch(_ enabled: Bool) {
    guard autoWatch != enabled else { return }
    autoWatch = enabled
    if enabled {
      installWatcher()
      startMonitorIfNeeded()
    } else {
      uninstallWatcher()
      stopMonitor()
    }
  }

  // MARK: - Intake

  func intakeURLs(_ urls: [URL]) {
    lastConfirmed = nil
    guard urls.count == 1 else {
      phase = .failed(
        ErrorMessage(
          title: "Choose one app at a time",
          detail: "Open or drop a single app or disk image to continue."
        ))
      return
    }

    var candidates: [Candidate] = []
    for url in urls {
      if url.pathExtension == "app" {
        if let candidate = try? QuarantineService.inspect(url) {
          candidates.append(candidate)
        }
      } else {
        phase = .working("Opening disk image…")
        do {
          let mountedApp = try DiskImageService.mountApp(from: url)
          phase = .working("Finding the app…")
          do {
            let candidate = try QuarantineService.inspect(mountedApp.appURL)
            candidates.append(candidate)
            mountedImages[candidate.id] = mountedApp
          } catch {
            DiskImageService.eject(mountedApp)
            throw error
          }
        } catch {
          phase = .failed(
            ErrorMessage(
              title: "Unsupported file type",
              detail: (error as? LocalizedError)?.errorDescription ?? "That couldn’t be opened."
            ))
          return
        }
      }
    }
    guard !candidates.isEmpty else {
      phase = .failed(
        ErrorMessage(
          title: "Unsupported file type",
          detail: "That file isn’t a supported app or disk image."
        ))
      return
    }
    phase = .confirming(candidates)
  }

  func pollFresh() {
    guard phase == .idle else { return }
    let handoff = ApplicationsDirectoryMonitor.drainHandoff()
    let scanned = ApplicationsDirectoryMonitor.scanForFreshCandidates()
    let urls = handoff + scanned.map(\.url)
    let fresh = urls.compactMap { try? QuarantineService.inspect($0) }
      .filter(\.isQuarantined)
    guard !fresh.isEmpty else { return }
    ApplicationsDirectoryMonitor.markKnown(urls)
    phase = .confirming(fresh)
  }

  // MARK: - Prepare apps

  func prepare(_ candidates: [Candidate]) {
    lastConfirmed = candidates
    Task { @MainActor in
      var installed: [String] = []
      let skipped: [String] = []
      var failed: [String] = []

      for candidate in candidates {
        do {
          let target = try installAndClear(candidate)
          installed.append(candidate.name)
          prepared[candidate] = target
          ejectMountedImage(for: candidate)
        } catch {
          failed.append(candidate.name)
          if candidates.count == 1 {
            let detail = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            phase = .failed(
              ErrorMessage(title: "Couldn’t prepare \(candidate.name)", detail: detail)
            )
            return
          }
        }
      }
      phase = .batchComplete(
        BatchSummary(
          installed: installed, skipped: skipped, failed: failed
        ))
      if openWhenFinished { openInstalled(installed) }
    }
  }

  func skip(_ candidates: [Candidate]) {
    for candidate in candidates {
      ejectMountedImage(for: candidate)
    }
    lastConfirmed = nil
    phase = .batchComplete(BatchSummary(skipped: candidates.map(\.name)))
  }

  func finishCurrentFlow() {
    for mountedApp in mountedImages.values {
      DiskImageService.eject(mountedApp)
    }
    mountedImages.removeAll()
    prepared.removeAll()
    lastConfirmed = nil
    phase = .idle
    if quitAfterCompletion {
      NSApplication.shared.terminate(nil)
    }
  }

  private func ejectMountedImage(for candidate: Candidate) {
    guard let mountedApp = mountedImages.removeValue(forKey: candidate.id) else { return }
    DiskImageService.eject(mountedApp)
  }

  private func installAndClear(_ candidate: Candidate) throws -> URL {
    // Apps already in Applications only need the quarantine flag removed.
    var working = candidate.url
    if candidate.url.deletingLastPathComponent().standardizedFileURL
      != InstallService.applicationsURL.standardizedFileURL
    {
      working = try InstallService.install(app: candidate.url)
    }
    try QuarantineService.removeQuarantine(on: working)
    if wantsSelfInstall && working.lastPathComponent == "Unquarantine.app" {
      try? InstallService.approveSelfInstall()
    }
    return working
  }

  private func openInstalled(_ names: [String]) {
    for name in names {
      let app = InstallService.applicationsURL.appendingPathComponent(name + ".app")
      NSWorkspace.shared.openApplication(
        at: app, configuration: NSWorkspace.OpenConfiguration()
      )
    }
  }

  func openPreparedApp(named name: String) {
    guard let target = prepared.first(where: { $0.key.name == name })?.value else { return }
    NSWorkspace.shared.openApplication(
      at: target, configuration: NSWorkspace.OpenConfiguration()
    )
    finishCurrentFlow()
  }

  func retryPreparation() {
    if let candidates = lastConfirmed, !candidates.isEmpty {
      phase = .confirming(candidates)
    } else {
      finishCurrentFlow()
    }
  }

  // MARK: - Watcher agent

  func installWatcher() {
    Task { @MainActor in
      let watcherBinary = watcherBundleURL()
      do {
        try LaunchAgentService.install(watcherBinary: watcherBinary)
      } catch {
        autoWatch = false
        stopMonitor()
        LaunchAgentService.uninstall()
        phase = .failed(
          ErrorMessage(
            title: "Couldn’t start the background watcher.",
            detail: (error as? LocalizedError)?.errorDescription ?? ""
          ))
      }
    }
  }

  func uninstallWatcher() {
    LaunchAgentService.uninstall()
  }

  private func watcherBundleURL() -> URL {
    // The build script places the helper in the app's Resources directory.
    Bundle.main.resourceURL?.appendingPathComponent("UnquarantineWatcher")
      ?? URL(fileURLWithPath: "/nonexistent/UnquarantineWatcher")
  }
}
