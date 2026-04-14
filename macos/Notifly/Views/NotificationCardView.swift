import SwiftUI
import AppKit

struct NotificationCardView: View {
  let event: NotiflyEvent
  let onClick: () -> Void
  let onDismiss: () -> Void

  @State private var hovering = false

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      head
      message
      footer
    }
    .padding(.horizontal, 16)
    .padding(.top, 14)
    .padding(.bottom, 12)
    .frame(width: 392, alignment: .leading)
    .background(cardBackground)
    .overlay(topAccent, alignment: .top)
    .overlay(outerGlow)
    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    .shadow(color: .black.opacity(0.45), radius: 22, x: 0, y: 14)
    .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 3)
    .contentShape(Rectangle())
    .onHover { hovering = $0 }
    .onTapGesture { onClick() }
  }

  // MARK: - Head row

  private var head: some View {
    HStack(spacing: 12) {
      ProjectIconView(name: event.project)

      VStack(alignment: .leading, spacing: 3) {
        HStack(spacing: 8) {
          Text(event.project)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.white.opacity(0.97))
            .lineLimit(1)
            .truncationMode(.tail)
          Spacer(minLength: 4)
          Text(relativeTime)
            .font(.system(size: 11, weight: .regular))
            .foregroundColor(.white.opacity(0.38))
            .monospacedDigit()
        }
        eventPill
      }
    }
  }

  private var eventPill: some View {
    HStack(spacing: 5) {
      Image(systemName: pillIcon)
        .font(.system(size: 9, weight: .bold))
      Text(pillText.uppercased())
        .font(.system(size: 10.5, weight: .semibold))
        .tracking(0.4)
    }
    .foregroundColor(accentColor)
    .padding(.horizontal, 8)
    .padding(.vertical, 2.5)
    .background(
      Capsule().fill(accentColor.opacity(0.12))
    )
    .overlay(
      Capsule().stroke(.white.opacity(0.08), lineWidth: 0.5)
    )
  }

  // MARK: - Message

  private var message: some View {
    Text(event.message)
      .font(.system(size: 13.5))
      .foregroundColor(.white.opacity(0.97))
      .lineSpacing(2)
      .lineLimit(3)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .leading)
  }

  // MARK: - Footer

  private var footer: some View {
    HStack {
      Text(metaText)
        .font(.system(size: 10.5, design: .monospaced))
        .foregroundColor(.white.opacity(0.38))
        .lineLimit(1)
      Spacer()
      if hovering {
        HStack(spacing: 6) {
          actionButton(systemName: "arrow.up.left.and.arrow.down.right", action: onClick)
          actionButton(systemName: "doc.on.doc", action: copyMessage)
          actionButton(systemName: "xmark", action: onDismiss)
        }
        .transition(.opacity)
      }
    }
    .padding(.top, 8)
    .overlay(
      Rectangle()
        .fill(.white.opacity(0.06))
        .frame(height: 0.5),
      alignment: .top
    )
    .animation(.easeInOut(duration: 0.15), value: hovering)
  }

  private func actionButton(systemName: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: systemName)
        .font(.system(size: 11, weight: .semibold))
        .foregroundColor(.white.opacity(0.62))
        .frame(width: 22, height: 22)
        .background(
          RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.06))
        )
        .overlay(
          RoundedRectangle(cornerRadius: 6).stroke(.white.opacity(0.10), lineWidth: 0.5)
        )
    }
    .buttonStyle(.plain)
  }

  // MARK: - Background

  private var cardBackground: some View {
    ZStack {
      VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
      Color.black.opacity(0.35)
    }
  }

  private var topAccent: some View {
    LinearGradient(
      colors: [.clear, accentColor.opacity(0.7), .clear],
      startPoint: .leading,
      endPoint: .trailing
    )
    .frame(height: 1)
    .padding(.horizontal, 16)
  }

  private var outerGlow: some View {
    RoundedRectangle(cornerRadius: 18, style: .continuous)
      .stroke(accentColor.opacity(event.type == .attention ? 0.22 : 0), lineWidth: 1)
      .blur(radius: event.type == .attention ? 0.5 : 0)
  }

  // MARK: - Derived

  private var accentColor: Color {
    switch event.type {
    case .done:      return Color(red: 0.20, green: 0.84, blue: 0.30)
    case .attention: return Color(red: 1.00, green: 0.62, blue: 0.04)
    case .stopped:   return Color(red: 1.00, green: 0.27, blue: 0.23)
    }
  }

  private var pillIcon: String {
    switch event.type {
    case .done:      return "checkmark"
    case .attention: return "exclamationmark"
    case .stopped:   return "xmark"
    }
  }

  private var pillText: String {
    switch event.type {
    case .done:      return "done"
    case .attention: return "needs you"
    case .stopped:   return "stopped"
    }
  }

  private var relativeTime: String {
    let interval = Date().timeIntervalSince(event.receivedAt)
    if interval < 5 { return "just now" }
    if interval < 60 { return "\(Int(interval))s ago" }
    if interval < 3600 { return "\(Int(interval / 60))m ago" }
    return "\(Int(interval / 3600))h ago"
  }

  private var metaText: String {
    switch event.type {
    case .done:      return "claude · done"
    case .attention: return "claude · waiting"
    case .stopped:   return "claude · halted"
    }
  }

  private func copyMessage() {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(event.message, forType: .string)
  }
}

// MARK: - Project icon

struct ProjectIconView: View {
  let name: String

  var body: some View {
    RoundedRectangle(cornerRadius: 11, style: .continuous)
      .fill(LinearGradient(
        colors: gradientColors,
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      ))
      .frame(width: 40, height: 40)
      .overlay(
        Text(initials)
          .font(.system(size: 17, weight: .bold, design: .default))
          .foregroundColor(.white)
          .kerning(-0.4)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 11, style: .continuous)
          .stroke(.white.opacity(0.25), lineWidth: 0.5)
      )
      .shadow(color: .black.opacity(0.25), radius: 3, x: 0, y: 1)
  }

  private var initials: String {
    let words = name.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
    if words.count >= 2 {
      return String(words.prefix(2).compactMap { $0.first }).uppercased()
    }
    return String(name.prefix(2)).uppercased()
  }

  /// Deterministic color from project name — same project always gets the same color.
  private var gradientColors: [Color] {
    let palette: [(Color, Color)] = [
      (Color(red: 1.00, green: 0.36, blue: 0.54), Color(red: 0.82, green: 0.16, blue: 0.37)),
      (Color(red: 0.29, green: 0.87, blue: 0.50), Color(red: 0.09, green: 0.64, blue: 0.29)),
      (Color(red: 1.00, green: 0.66, blue: 0.30), Color(red: 0.91, green: 0.41, blue: 0.11)),
      (Color(red: 0.35, green: 0.65, blue: 1.00), Color(red: 0.13, green: 0.34, blue: 0.78)),
      (Color(red: 0.71, green: 0.40, blue: 0.99), Color(red: 0.45, green: 0.16, blue: 0.78)),
      (Color(red: 0.40, green: 0.82, blue: 1.00), Color(red: 0.13, green: 0.51, blue: 0.78)),
      (Color(red: 1.00, green: 0.50, blue: 0.50), Color(red: 0.78, green: 0.18, blue: 0.18))
    ]
    var hash: UInt64 = 5381
    for byte in name.utf8 { hash = ((hash << 5) &+ hash) &+ UInt64(byte) }
    let pair = palette[Int(hash % UInt64(palette.count))]
    return [pair.0, pair.1]
  }
}

// MARK: - Visual effect view

struct VisualEffectBlur: NSViewRepresentable {
  let material: NSVisualEffectView.Material
  let blendingMode: NSVisualEffectView.BlendingMode

  func makeNSView(context: Context) -> NSVisualEffectView {
    let view = NSVisualEffectView()
    view.material = material
    view.blendingMode = blendingMode
    view.state = .active
    return view
  }

  func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
