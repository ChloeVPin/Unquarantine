import AppKit
import SwiftUI

struct SettingsView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    @Bindable var model = model

    VStack(alignment: .leading, spacing: 18) {
      SettingsSection(title: "After preparing apps") {
        SettingsPane(usesLiquidGlass: model.liquidGlassPanes) {
          VStack(spacing: 0) {
            PreferenceRow(
              title: "Open apps when finished",
              detail: "Launch the app automatically after it’s prepared.",
              isOn: $model.openWhenFinished
            )

            sectionDivider

            PreferenceRow(
              title: "Quit on finish",
              detail: "Quit after you open the app or choose Done.",
              isOn: $model.quitAfterCompletion
            )
          }
        }
      }

      SettingsSection(title: "Background monitoring") {
        SettingsPane(usesLiquidGlass: model.liquidGlassPanes) {
          VStack(alignment: .leading, spacing: 10) {
            PreferenceRow(
              title: "Look for new quarantined apps",
              detail:
                "Open Unquarantine when a newly added app in /Applications needs your approval.",
              isOn: Binding(
                get: { model.autoWatch },
                set: { model.setAutoWatch($0) }
              )
            )

            Text(
              "Installs a lightweight login agent that watches only /Applications. Turn this off to remove it."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, 14)
            .padding(.bottom, 12)
          }
        }
      }

      SettingsSection(title: "Appearance") {
        SettingsPane(usesLiquidGlass: model.liquidGlassPanes) {
          PreferenceRow(
            title: "Liquid Glass appearance",
            detail:
              "Use a translucent window background and Liquid Glass for interactive surfaces. macOS adapts them to your transparency and contrast settings.",
            isOn: $model.liquidGlassPanes
          )
        }
      }

      Spacer(minLength: 0)
    }
    .padding(.horizontal, 26)
    .padding(.top, 22)
    .padding(.bottom, 18)
    .frame(width: 540, height: 496, alignment: .topLeading)
    .containerBackground(for: .window) {
      if model.liquidGlassPanes {
        Rectangle().fill(.regularMaterial)
      } else {
        Color(nsColor: .windowBackgroundColor)
      }
    }
  }

  private var sectionDivider: some View {
    Rectangle()
      .fill(Color(nsColor: .separatorColor).opacity(0.45))
      .frame(height: 0.5)
      .padding(.leading, 14)
  }
}

private struct SettingsSection<Content: View>: View {
  let title: String
  @ViewBuilder let content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.headline)
        .padding(.leading, 2)

      content
    }
  }
}

private struct SettingsPane<Content: View>: View {
  let usesLiquidGlass: Bool
  @ViewBuilder let content: Content

  private let shape = ConcentricRectangle()

  private var paddedContent: some View {
    content
      .padding(.horizontal, 14)
      .padding(.vertical, 8)
  }

  var body: some View {
    paddedContent
      .background {
        if usesLiquidGlass {
          shape.fill(.regularMaterial)
        } else {
          shape.fill(Color(nsColor: .controlBackgroundColor))
        }
      }
      .overlay {
        shape.stroke(Color.primary.opacity(usesLiquidGlass ? 0.08 : 0.06), lineWidth: 1)
      }
  }
}

private struct PreferenceRow: View {
  let title: String
  let detail: String
  @Binding var isOn: Bool

  var body: some View {
    HStack(spacing: 16) {
      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.body)
        Text(detail)
          .font(.footnote)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      Spacer(minLength: 10)

      Toggle(title, isOn: $isOn)
        .labelsHidden()
        .toggleStyle(.switch)
        .controlSize(.regular)
    }
    .padding(.vertical, 11)
    .contentShape(Rectangle())
  }
}
