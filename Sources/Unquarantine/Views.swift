import AppKit
import SwiftUI

// MARK: - Shared card chrome

private let contentWidth: CGFloat = 640

/// A shared background for the app's cards.
private struct AdaptivePaneBackground: View {
  @Environment(AppModel.self) private var model

  let cornerRadius: CGFloat
  let fallbackFill: Color
  var borderColor: Color = .primary
  var borderOpacity: Double = 0.06

  private var shape: RoundedRectangle {
    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
  }

  var body: some View {
    if model.liquidGlassPanes {
      shape.fill(.clear)
        .glassEffect(.regular, in: shape)
    } else {
      shape
        .fill(fallbackFill)
        .overlay {
          shape.strokeBorder(borderColor.opacity(borderOpacity), lineWidth: 1)
        }
    }
  }
}

// MARK: - Content

struct ContentView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    VStack(spacing: 0) {
      Group {
        switch model.phase {
        case .idle:
          DropZoneScreen()
        case .working(let status):
          WorkingView(status: status)
        case .confirming(let candidates):
          ConfirmCardView(candidates: candidates)
        case .installing(let candidates):
          InstallerCardView(candidates: candidates)
        case .batchComplete(let summary):
          BatchCompleteView(summary: summary)
        case .failed(let message):
          FailureView(message: message)
        }
      }
      .padding(model.phase == .idle ? 0 : 28)
    }
    .frame(width: contentWidth)
    .animation(.snappy(duration: 0.25), value: model.phase)
    .animation(.snappy(duration: 0.15), value: model.isDropTargeted)
    .animation(.snappy(duration: 0.2), value: model.updater.state)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .containerBackground(for: .window) {
      if model.liquidGlassPanes {
        Rectangle().fill(.regularMaterial)
      } else {
        Color(nsColor: .windowBackgroundColor)
      }
    }
    .overlay(alignment: .topTrailing) {
      if model.phase == .idle, model.updater.showsUpdateBanner,
        let update = model.updater.availableUpdate
      {
        UpdatePill(update: update)
          .padding(.top, 5)
          .padding(.trailing, 14)
          .transition(.move(edge: .top).combined(with: .opacity))
      }
    }
    .ignoresSafeArea()
  }
}

private struct UpdatePill: View {
  @Environment(AppModel.self) private var model

  let update: AvailableUpdate

  var body: some View {
    Group {
      switch model.updater.state {
      case .available:
        actionPill(title: "Update", symbol: "arrow.down.app")
          .help("Install version \(update.version) and relaunch")
          .accessibilityLabel("Install update version \(update.version) and relaunch")
      case .failed:
        actionPill(title: "Retry", symbol: "arrow.clockwise")
          .help(model.updater.statusDescription)
          .accessibilityLabel("Try the update again")
      case .waitingForApproval:
        statusPill(title: "Approve", symbol: nil)
          .help(model.updater.statusDescription)
          .accessibilityLabel(model.updater.statusDescription)
      case .installing:
        statusPill(title: "Restarting", symbol: nil)
          .help(model.updater.statusDescription)
          .accessibilityLabel(model.updater.statusDescription)
      case .downloading, .verifying, .preparing:
        statusPill(title: "Updating", symbol: nil, showsProgress: true)
          .help(model.updater.statusDescription)
          .accessibilityLabel(model.updater.statusDescription)
      case .idle, .checking, .current, .checkFailed:
        EmptyView()
      }
    }
  }

  private func actionPill(title: String, symbol: String) -> some View {
    Button {
      Task { await model.updater.installAvailableUpdate() }
    } label: {
      pillLabel(title: title, symbol: symbol)
    }
    .buttonStyle(.plain)
    .modifier(UpdatePillSurface(usesLiquidGlass: model.liquidGlassPanes))
  }

  private func statusPill(title: String, symbol: String?, showsProgress: Bool = false) -> some View {
    pillLabel(title: title, symbol: symbol, showsProgress: showsProgress)
      .modifier(UpdatePillSurface(usesLiquidGlass: model.liquidGlassPanes))
  }

  private func pillLabel(title: String, symbol: String?, showsProgress: Bool = false) -> some View {
    HStack(spacing: 5) {
      if showsProgress {
        ProgressView().controlSize(.mini)
      } else if let symbol {
        Image(systemName: symbol)
          .font(.system(size: 11, weight: .semibold))
      }
      Text(title)
        .font(.system(size: 11, weight: .semibold))
    }
    .padding(.horizontal, 9)
    .padding(.vertical, 4)
    .fixedSize()
  }
}

private struct UpdatePillSurface: ViewModifier {
  let usesLiquidGlass: Bool

  func body(content: Content) -> some View {
    if usesLiquidGlass {
      content.glassEffect(.regular.interactive(), in: Capsule())
    } else {
      content
        .background {
          Capsule().fill(Color(nsColor: .controlBackgroundColor))
        }
        .overlay {
          Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }
  }
}

// MARK: - Idle: drop zone

private struct DropZoneScreen: View {
  @Environment(AppModel.self) private var model
  @State private var isHovered = false

  var body: some View {
    ZStack {
      @Bindable var model = model
      DropZone(
        onDrop: { urls in
          model.isDropTargeted = false
          model.intakeURLs(urls)
        },
        onClick: { chooseFiles(model: model) },
        isTargeted: $model.isDropTargeted,
        isHovered: $isHovered
      )

      VStack(spacing: 20) {
        Image(systemName: model.isDropTargeted ? "arrow.down.app.fill" : "arrow.down.app")
          .font(.system(size: 36, weight: .medium, design: .rounded))
          .foregroundStyle(Color.accentColor)
          .frame(width: 78, height: 78)
          .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
              .fill(
                Color.accentColor.opacity(
                  model.isDropTargeted ? 0.18 : (isHovered ? 0.14 : 0.10)
                ))
          )
          .symbolEffect(.bounce, value: model.isDropTargeted)
          .animation(.spring(duration: 0.25), value: model.isDropTargeted)
          .scaleEffect(isHovered && !model.isDropTargeted ? 1.04 : 1)
          .animation(.snappy(duration: 0.18), value: isHovered)
          .offset(y: 9)

        Text(model.isDropTargeted ? "Drop it here" : "Drop or click to browse")
          .font(.title2.bold())
          .offset(y: 8)

        Text("App or disk image · .app, .dmg, .iso")
          .font(.callout)
          .foregroundStyle(.secondary)
          .offset(y: -7)
      }
      .padding(24)
      .allowsHitTesting(false)
    }
    .frame(maxWidth: .infinity)
    .frame(maxHeight: .infinity)
    .animation(.snappy(duration: 0.18), value: isHovered)
    .background {
      if model.liquidGlassPanes {
        Color.clear.glassEffect(.regular, in: ConcentricRectangle())
      } else {
        Color.primary.opacity(isHovered ? 0.035 : 0)
      }
    }
    .overlay {
      if model.liquidGlassPanes {
        if model.isDropTargeted {
          ConcentricRectangle()
            .stroke(Color.accentColor.opacity(0.72), lineWidth: 1.5)
            .padding(1)
            .allowsHitTesting(false)
        } else if isHovered {
          ConcentricRectangle()
            .fill(Color.primary.opacity(0.035))
            .allowsHitTesting(false)
        }
      } else {
        ConcentricRectangle()
          .stroke(
            model.isDropTargeted
              ? Color.accentColor.opacity(0.72)
              : Color.primary.opacity(isHovered ? 0.32 : 0.24),
            style: StrokeStyle(lineWidth: 1, dash: [5, 5])
          )
          .padding(1)
          .allowsHitTesting(false)
      }
    }
  }
}

// MARK: - Working

struct WorkingView: View {
  let status: String

  var body: some View {
    VStack(spacing: 16) {
      ProgressView().controlSize(.large)
      Text(status)
        .font(.callout)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, minHeight: 300)
  }
}

// MARK: - Confirm card

struct ConfirmCardView: View {
  @Environment(AppModel.self) private var model
  let candidates: [Candidate]

  private var candidate: Candidate? { candidates.first }

  private var title: String {
    if candidates.count > 1 {
      return "Prepare these apps?"
    }
    if let candidate {
      return candidate.isQuarantined
        ? "Trust \(candidate.name) and prepare it?"
        : "Prepare \(candidate.name)?"
    }
    return "Prepare this app?"
  }

  private var warningText: String {
    if candidates.count > 1 {
      return "Only continue if you trust where these apps came from. This removes macOS’s downloaded-file warning for each one; it doesn’t verify that they’re safe."
    }
    guard let candidate else { return "Review each app before continuing." }
    if candidate.isQuarantined {
      return "Only continue if you trust where this app came from. This removes macOS’s downloaded-file warning; it doesn’t verify that the app is safe."
    }
    return "This app isn’t marked as quarantined. Unquarantine will copy it to Applications without changing its security settings."
  }

  private var actionTitle: String {
    if candidates.count > 1 { return "Trust & Prepare" }
    return candidate?.isQuarantined == true ? "Trust & Prepare" : "Prepare"
  }

  var body: some View {
    VStack(spacing: 0) {
      if candidates.count == 1, let candidate {
        Image(nsImage: NSWorkspace.shared.icon(forFile: candidate.url.path))
          .resizable()
          .scaledToFit()
          .frame(width: 56, height: 56)
          .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
          .padding(.bottom, 24)
      } else if candidates.count > 1 {
        Image(systemName: "square.stack.3d.up.fill")
          .font(.system(size: 32, weight: .medium))
          .foregroundStyle(.tint)
          .frame(height: 56)
          .padding(.bottom, 24)
      }

      Text(title)
        .font(.title2.bold())
        .padding(.bottom, 10)

      Text(warningText)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: 420)
        .padding(.bottom, 22)

      HStack(spacing: 12) {
        Button {
          model.skip(candidates)
        } label: {
          Text("Skip")
        }
        .keyboardShortcut(.cancelAction)
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)

        Button {
          model.phase = .installing(candidates)
        } label: {
          Text(actionTitle)
        }
        .keyboardShortcut(.defaultAction)
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
      }
      .controlSize(.regular)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .controlSize(.regular)
  }
}

// MARK: - Installer card

struct InstallerCardView: View {
  @Environment(AppModel.self) private var model
  let candidates: [Candidate]

  var body: some View {
    VStack(spacing: 16) {
      ProgressView().controlSize(.large)
      VStack(spacing: 6) {
        Text("Waiting for administrator approval…")
          .font(.title3.weight(.medium))
        Text("Approve the macOS dialog to continue.")
          .foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity, minHeight: 220)
    .task {
      model.prepare(candidates)
    }
  }
}

// MARK: - Batch completion

struct BatchCompleteView: View {
  @Environment(AppModel.self) private var model
  let summary: BatchSummary

  private var singleOutcomeName: String? {
    let names = summary.installed + summary.failed + summary.skipped
    return names.count == 1 ? names.first : nil
  }

  var body: some View {
    VStack(spacing: 18) {
      if let name = singleOutcomeName {
        singleOutcome(name)
      } else {
        batchOutcome
      }

      if let name = singleOutcomeName, summary.installed.contains(name) {
        HStack(spacing: 10) {
          Button("Open App") { model.openPreparedApp(named: name) }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .keyboardShortcut(.defaultAction)

          Button("Done") { model.finishCurrentFlow() }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .keyboardShortcut(.cancelAction)
        }
        .controlSize(.regular)
      } else {
        Button("Done") { model.finishCurrentFlow() }
          .keyboardShortcut(.defaultAction)
          .buttonStyle(.borderedProminent)
          .buttonBorderShape(.capsule)
          .controlSize(.regular)
      }
    }
    .padding(.horizontal, 28)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  @ViewBuilder
  private func singleOutcome(_ name: String) -> some View {
    if summary.installed.contains(name) {
      let appURL = InstallService.applicationsURL.appendingPathComponent(name + ".app")
      VStack(spacing: 8) {
        Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path))
          .resizable()
          .scaledToFit()
          .frame(width: 58, height: 58)

        Text("App prepared")
          .font(.title3.weight(.semibold))

        Text(name)
          .font(.callout)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)

        Text("Ready to open in Applications.")
          .font(.callout)
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity)
    } else {
      let skipped = summary.skipped.contains(name)
      VStack(spacing: 10) {
        Image(systemName: skipped ? "forward.circle.fill" : "xmark.circle.fill")
          .font(.system(size: 34, weight: .regular))
          .foregroundStyle(skipped ? Color.orange : Color.red)

        Text(skipped ? "App skipped" : "Couldn’t prepare app")
          .font(.title3.weight(.semibold))

        Text(name)
          .font(.callout)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)

        Text(skipped ? "You chose to skip this app." : "The app couldn’t be prepared.")
          .font(.callout)
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity)
    }
  }

  private var batchOutcome: some View {
    VStack(spacing: 8) {
      VStack(spacing: 6) {
        if summary.installed.isEmpty {
          Text("No apps were prepared")
            .font(.title3.weight(.semibold))
          Text(summary.line)
            .font(.callout)
            .foregroundStyle(.secondary)
        } else {
          Image(
            systemName: summary.allGood
              ? "checkmark.circle.fill"
              : "checkmark.circle.badge.exclamationmark.fill"
          )
          .foregroundStyle(summary.allGood ? Color.green : Color.orange)
          .font(.system(size: 32, design: .rounded))
          Text(summary.line)
            .font(.headline)
          Text("\(summary.installed.count) prepared")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      .frame(maxWidth: .infinity)
      .padding(.bottom, 14)

      VStack(spacing: 8) {
        ForEach(summary.installed, id: \.self) { name in
          outcomeRow(symbol: "forward.circle.fill", tint: .accentColor, name: name)
        }
        ForEach(summary.failed, id: \.self) { name in
          outcomeRow(symbol: "xmark.circle.fill", tint: .red, name: name)
        }
        ForEach(summary.skipped, id: \.self) { name in
          outcomeRow(
            symbol: "forward.circle.fill",
            tint: .orange,
            name: name,
            detail: "Skipped by user"
          )
        }
      }
      .frame(maxWidth: 460)
    }
  }

  private func outcomeRow(
    symbol: String,
    tint: Color,
    name: String,
    detail: String? = nil
  ) -> some View {
    HStack(spacing: 8) {
      Image(systemName: symbol).foregroundStyle(tint)
      VStack(alignment: .leading, spacing: 2) {
        Text(name)
          .font(.callout.weight(.semibold))
          .lineLimit(1)
          .truncationMode(.middle)
        if let detail {
          Text(detail)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      Spacer()
    }
    .font(.callout)
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      AdaptivePaneBackground(
        cornerRadius: 12,
        fallbackFill: Color.primary.opacity(0.045),
        borderOpacity: 0.04
      )
    )
  }
}

// MARK: - Failure

struct FailureView: View {
  @Environment(AppModel.self) private var model
  let message: ErrorMessage

  var body: some View {
    VStack(spacing: 14) {
      Image(systemName: "exclamationmark.triangle.fill")
        .font(.system(size: 36, design: .rounded))
        .foregroundStyle(.orange)
      VStack(spacing: 4) {
        Text(message.title)
          .font(.headline)
        if !message.detail.isEmpty {
          Text(message.detail)
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
      }
      HStack(spacing: 10) {
        if model.canRetryPreparation {
          Button("Try Again") { model.retryPreparation() }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
        }

        Button("Done") { model.finishCurrentFlow() }
          .keyboardShortcut(.defaultAction)
          .buttonStyle(.borderedProminent)
          .buttonBorderShape(.capsule)
      }
      .controlSize(.regular)
    }
    .frame(maxWidth: .infinity, minHeight: 240)
  }
}
