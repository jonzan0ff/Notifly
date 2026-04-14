import AppKit
import Combine
import SwiftUI

@MainActor
final class MenuBarController: NSObject {
  static let shared = MenuBarController()

  private var statusItem: NSStatusItem?
  private var popover: NSPopover?
  private var escapeMonitor: Any?
  private var cancellables = Set<AnyCancellable>()

  private override init() { super.init() }

  func install() {
    guard statusItem == nil else { return }
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    self.statusItem = item
    configurePopover()
    rebuildButton()

    AppState.shared.$availableUpdate
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in self?.rebuildButton() }
      .store(in: &cancellables)

    AppState.shared.$isInstallingUpdate
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in self?.rebuildButton() }
      .store(in: &cancellables)

    AppState.shared.$updateProgress
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        guard AppState.shared.isInstallingUpdate else { return }
        self?.rebuildButton()
      }
      .store(in: &cancellables)
  }

  // MARK: - Popover

  private func configurePopover() {
    let popover = NSPopover()
    popover.contentSize = NSSize(width: 300, height: 140)
    popover.behavior = .transient
    popover.delegate = self
    popover.contentViewController = NSHostingController(rootView: MenuBarPopoverView())
    self.popover = popover
  }

  @objc private func statusItemClicked() {
    togglePopover()
  }

  private func togglePopover() {
    guard let popover, let button = statusItem?.button else { return }
    if popover.isShown {
      popover.performClose(nil)
    } else {
      popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
      NSApp.activate(ignoringOtherApps: true)
    }
  }

  // MARK: - Escape dismissal

  private func installEscapeMonitor() {
    guard escapeMonitor == nil else { return }
    escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      if event.keyCode == 53 { // Escape
        self?.popover?.performClose(nil)
        return nil
      }
      return event
    }
  }

  private func removeEscapeMonitor() {
    if let monitor = escapeMonitor {
      NSEvent.removeMonitor(monitor)
      escapeMonitor = nil
    }
  }

  // MARK: - Indicators (orange dot when update available, ring while installing)

  private func rebuildButton() {
    guard let button = statusItem?.button else { return }
    button.subviews.forEach { $0.removeFromSuperview() }

    let icon = NSImage(systemSymbolName: "bell.fill", accessibilityDescription: "Notifly")
    icon?.isTemplate = true
    button.image = icon
    let iconWidth: CGFloat = icon?.size.width ?? 18

    if AppState.shared.isInstallingUpdate {
      let ringSize: CGFloat = 10
      let gap: CGFloat = 2
      let ring = ProgressRingView(frame: NSRect(
        x: iconWidth + gap,
        y: (button.bounds.height - ringSize) / 2,
        width: ringSize, height: ringSize
      ))
      ring.progress = AppState.shared.updateProgress
      button.addSubview(ring)
      statusItem?.length = iconWidth + gap + ringSize + 6
    } else if AppState.shared.availableUpdate != nil {
      let dotSize: CGFloat = 6
      let dot = NSView(frame: NSRect(
        x: iconWidth - dotSize / 2,
        y: 14,
        width: dotSize, height: dotSize
      ))
      dot.wantsLayer = true
      dot.layer?.backgroundColor = NSColor.systemOrange.cgColor
      dot.layer?.cornerRadius = dotSize / 2
      button.addSubview(dot)
      statusItem?.length = iconWidth + dotSize / 2 + 2
    } else {
      statusItem?.length = NSStatusItem.variableLength
    }

    button.target = self
    button.action = #selector(statusItemClicked)
  }
}

// MARK: - NSPopoverDelegate

extension MenuBarController: NSPopoverDelegate {
  nonisolated func popoverDidShow(_ notification: Notification) {
    Task { @MainActor in self.installEscapeMonitor() }
  }

  nonisolated func popoverDidClose(_ notification: Notification) {
    Task { @MainActor in self.removeEscapeMonitor() }
  }
}

// MARK: - Progress Ring (mirrors the HomeTeam pattern)

final class ProgressRingView: NSView {
  var progress: Double = 0

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    let inset: CGFloat = 0.5
    let rect = bounds.insetBy(dx: inset, dy: inset)
    let center = NSPoint(x: rect.midX, y: rect.midY)
    let radius = min(rect.width, rect.height) / 2
    let lineWidth: CGFloat = 1.5

    let bgPath = NSBezierPath()
    bgPath.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
    bgPath.lineWidth = lineWidth
    NSColor.systemOrange.withAlphaComponent(0.3).setStroke()
    bgPath.stroke()

    guard progress > 0 else { return }
    let startAngle: CGFloat = 90
    let endAngle = startAngle - CGFloat(progress) * 360
    let arcPath = NSBezierPath()
    arcPath.appendArc(withCenter: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
    arcPath.lineWidth = lineWidth
    arcPath.lineCapStyle = .round
    NSColor.systemOrange.setStroke()
    arcPath.stroke()
  }
}

// MARK: - Popover Content (rev 2 spec)

// Test visibility
internal struct MenuBarPopoverView: View {
  @ObservedObject private var appState = AppState.shared

  private var version: String {
    (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "?"
  }

  var body: some View {
    VStack(spacing: 0) {
      // Header
      HStack {
        Text("Notifly")
          .font(.system(size: 14, weight: .semibold))
        Spacer()
        Text("v\(version)")
          .font(.system(size: 11))
          .monospacedDigit()
          .foregroundStyle(.secondary)
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 12)

      Divider()

      // Body
      VStack(spacing: 0) {
        if appState.isInstallingUpdate {
          HStack(spacing: 10) {
            ProgressView(value: appState.updateProgress)
              .progressViewStyle(.linear)
              .frame(maxWidth: .infinity)
            Text("Installing update\u{2026}")
              .font(.system(size: 13))
              .foregroundStyle(.secondary)
          }
          .padding(.horizontal, 14)
          .padding(.vertical, 10)
        } else {
          ActionRow(
            icon: "arrow.down.circle",
            label: appState.availableUpdate != nil ? "Install Update" : "Check for Updates"
          ) {
            if appState.availableUpdate != nil {
              Task { await AppState.shared.installUpdate() }
            } else {
              Task { await AppState.shared.checkForUpdate() }
            }
          }
        }

        ActionRow(icon: "power", label: "Quit") {
          NSApplication.shared.terminate(nil)
        }
      }
    }
    .frame(width: 300)
  }
}

private struct ActionRow: View {
  let icon: String
  let label: String
  let action: () -> Void

  @State private var isHovering = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        Image(systemName: icon)
          .font(.system(size: 18))
          .foregroundStyle(Color.white.opacity(0.7))
          .frame(width: 22, alignment: .center)
        Text(label)
          .font(.system(size: 13))
          .foregroundStyle(.primary)
        Spacer()
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 10)
      .contentShape(Rectangle())
      .background(isHovering ? Color.white.opacity(0.06) : Color.clear)
    }
    .buttonStyle(.plain)
    .onHover { isHovering = $0 }
  }
}
