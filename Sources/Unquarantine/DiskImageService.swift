import Foundation

enum DiskImageError: Error, LocalizedError {
  case couldNotOpen
  case pathUnresolvable
  case ambiguous([String])
  case noApp

  var errorDescription: String? {
    switch self {
    case .couldNotOpen:
      return "The disk image couldn’t be opened."
    case .pathUnresolvable:
      return "The app path in the disk image couldn’t be resolved."
    case .ambiguous(let names):
      return "This image contains more than one app: " + names.joined(separator: ", ")
    case .noApp:
      return "No app was found in that disk image."
    }
  }
}

struct MountedDiskImageApp {
  let appURL: URL
  fileprivate let mountPoint: URL
}

enum DiskImageService {
  static func mountApp(from image: URL) throws -> MountedDiskImageApp {
    let mountPoint = try attach(image)

    do {
      let contents = try FileManager.default.contentsOfDirectory(
        at: mountPoint,
        includingPropertiesForKeys: [.isApplicationKey],
        options: [.skipsHiddenFiles]
      )
      let apps = findApps(in: contents, depth: 0)

      if apps.count > 1 {
        throw DiskImageError.ambiguous(apps.map(\.lastPathComponent))
      }
      guard let appURL = apps.first else { throw DiskImageError.noApp }
      return MountedDiskImageApp(appURL: appURL, mountPoint: mountPoint)
    } catch {
      eject(mountPoint)
      throw error
    }
  }

  static func eject(_ mountedApp: MountedDiskImageApp) {
    eject(mountedApp.mountPoint)
  }

  private static func findApps(in urls: [URL], depth: Int) -> [URL] {
    guard depth < 4 else { return [] }

    var apps: [URL] = []
    let fileManager = FileManager.default

    for url in urls {
      if url.pathExtension == "app" {
        apps.append(url)
        continue
      }

      guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true,
        let children = try? fileManager.contentsOfDirectory(
          at: url,
          includingPropertiesForKeys: [.isApplicationKey, .isDirectoryKey],
          options: [.skipsHiddenFiles]
        )
      else { continue }

      apps.append(contentsOf: findApps(in: children, depth: depth + 1))
    }

    return apps
  }

  private static func attach(_ image: URL) throws -> URL {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
    process.arguments = ["attach", image.path, "-nobrowse", "-readonly", "-plist"]

    let output = Pipe()
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice

    do {
      try process.run()
    } catch {
      throw DiskImageError.couldNotOpen
    }
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw DiskImageError.couldNotOpen }

    let data = output.fileHandleForReading.readDataToEndOfFile()
    guard let mountPoint = parseMountPoint(from: data) else {
      throw DiskImageError.pathUnresolvable
    }
    return mountPoint
  }

  private static func parseMountPoint(from data: Data) -> URL? {
    guard
      let entries = try? PropertyListSerialization.propertyList(
        from: data,
        options: [],
        format: nil
      ) as? [String: Any],
      let entities = entries["system-entities"] as? [[String: Any]]
    else { return nil }

    guard let path = entities.compactMap({ $0["mount-point"] as? String }).first else {
      return nil
    }
    return URL(fileURLWithPath: path)
  }

  private static func eject(_ mountPoint: URL) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
    process.arguments = ["detach", mountPoint.path, "-force"]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice

    guard (try? process.run()) != nil else { return }
    process.waitUntilExit()
  }
}
