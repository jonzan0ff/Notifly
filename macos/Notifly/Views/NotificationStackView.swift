import SwiftUI
import AppKit

struct NotificationStackView: View {
  @ObservedObject var manager: NotificationStackManager

  var body: some View {
    VStack(alignment: .trailing, spacing: 10) {
      ForEach(manager.events.prefix(3)) { event in
        NotificationCardView(
          event: event,
          onClick: { handleClick(event) },
          onDismiss: { manager.dismiss(event) }
        )
        .transition(
          .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .trailing).combined(with: .opacity)
          )
        )
      }

      if manager.events.count > 3 {
        moreChip
      }
    }
    .padding(.trailing, 14)
    .padding(.top, 10)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    .animation(.spring(response: 0.45, dampingFraction: 0.85), value: manager.events)
  }

  private var moreChip: some View {
    let extras = manager.events.dropFirst(3).map(\.project).joined(separator: ", ")
    return Text("\(manager.events.count - 3) more · \(extras)")
      .font(.system(size: 11.5, weight: .medium))
      .foregroundColor(.white.opacity(0.42))
      .padding(.horizontal, 14)
      .padding(.vertical, 7)
      .background(
        ZStack {
          VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
          Color.black.opacity(0.4)
        }
      )
      .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .stroke(.white.opacity(0.06), lineWidth: 0.5)
      )
      .frame(width: 392)
  }

  private func handleClick(_ event: NotiflyEvent) {
    manager.dismiss(event)
    VSCodeFocuser.focusWindow(forProject: event.project)
  }
}
