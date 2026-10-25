import AppKit
import SwiftUI
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    true
  }
}

@main
struct UnquarantineApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @Environment(\.openWindow) private var openWindow
  @State private var model = AppModel()

  var body: some Scene {
    WindowGroup("Unquarantine") {
      ContentView()
        .environment(model)
    }
    .windowResizability(.contentSize)
    .windowStyle(.hiddenTitleBar)
    .defaultSize(width: 640, height: 400)
    .commands {
      CommandGroup(replacing: .appInfo) {
        Button("About Unquarantine") {
          openWindow(id: "about")
        }
      }

      CommandGroup(replacing: .newItem) {
        Button("Choose Files…") {
          chooseFiles(model: model)
        }
        .keyboardShortcut("o")
      }
    }

    Window("About Unquarantine", id: "about") {
      AboutView()
    }
    .windowResizability(.contentSize)
    .defaultSize(width: 280, height: 226)
    .windowStyle(.hiddenTitleBar)

    Settings {
      SettingsView()
        .environment(model)
    }
    .windowResizability(.contentSize)
    .defaultSize(width: 540, height: 496)
  }
}

@MainActor
func chooseFiles(model: AppModel) {
  let panel = NSOpenPanel()
  panel.canChooseFiles = true
  panel.canChooseDirectories = false
  panel.allowsMultipleSelection = false
  panel.allowedContentTypes = [
    UTType.bundle,
    UTType.diskImage,
    UTType(filenameExtension: "iso") ?? .data,
  ]
  panel.prompt = "Choose an app or disk image"
  panel.message = "Choose a .app, .dmg, or .iso file."
  guard panel.runModal() == .OK else { return }
  model.intakeURLs(Array(panel.urls))
}

private struct AboutView: View {
  @AppStorage("liquidGlassPanes") private var liquidGlassPanes = true

  var body: some View {
    VStack(spacing: 7) {
      Image(nsImage: NSApplication.shared.applicationIconImage)
        .resizable()
        .scaledToFit()
        .frame(width: 64, height: 64)
        .padding(.bottom, 2)

      Text("Unquarantine")
        .font(.system(size: 14, weight: .semibold))

      Text("Version 1.0")
        .font(.system(size: 11))
        .foregroundStyle(.secondary)

      donationButton
        .padding(.top, 5)
    }
    .frame(width: 280, height: 226)
    .containerBackground(for: .window) {
      if liquidGlassPanes {
        Rectangle().fill(.regularMaterial)
      } else {
        Color(nsColor: .windowBackgroundColor)
      }
    }
  }

  private var coffeeGold: Color {
    Color(red: 1, green: 0.867, blue: 0)
  }

  private var donationLabel: some View {
    HStack(spacing: 8) {
      Image(systemName: "cup.and.saucer.fill")
        .foregroundStyle(.black)

      Text("Buy me a coffee")
        .font(.system(size: 13, weight: .semibold, design: .rounded))
        .foregroundStyle(.black)
    }
    .padding(.horizontal, 15)
    .padding(.vertical, 8)
    .contentShape(Capsule())
  }

  @ViewBuilder
  private var donationButton: some View {
    let destination = URL(string: "https://www.buymeacoffee.com/chloevalesquez")!

    if liquidGlassPanes {
      Link(destination: destination) {
        donationLabel
          .glassEffect(
            .regular.tint(coffeeGold).interactive(),
            in: Capsule()
          )
      }
      .buttonStyle(.plain)
    } else {
      Link(destination: destination) {
        donationLabel
          .background(Capsule().fill(coffeeGold))
      }
      .buttonStyle(.plain)
    }
  }
}
