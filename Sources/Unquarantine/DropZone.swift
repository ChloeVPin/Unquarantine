import SwiftUI

struct DropZone: View {
  let onDrop: ([URL]) -> Void
  let onClick: () -> Void
  @Binding var isTargeted: Bool
  @Binding var isHovered: Bool

  var body: some View {
    Color.clear
      .contentShape(Rectangle())
      .onTapGesture(perform: onClick)
      .onHover { hovering in
        isHovered = hovering
      }
      .dropDestination(for: URL.self) { urls, _ in
        guard !urls.isEmpty else { return false }
        onDrop(urls)
        return true
      } isTargeted: {
        isTargeted = $0
      }
      .accessibilityLabel("Drop or click to browse")
      .accessibilityHint("Choose an app or disk image to prepare")
      .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
