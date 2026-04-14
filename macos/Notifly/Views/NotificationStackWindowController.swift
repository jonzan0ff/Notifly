import AppKit
import SwiftUI

/// Borderless, click-through-where-empty floating window pinned to the top-right
/// of the active screen, just below the menu bar. Hosts the notification stack.
final class NotificationStackWindowController: NSWindowController {

  private let manager: NotificationStackManager

  init(manager: NotificationStackManager) {
    self.manager = manager

    let window = StackWindow(
      contentRect: NSRect(x: 0, y: 0, width: 420, height: 800),
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = false
    window.level = .statusBar
    window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
    window.ignoresMouseEvents = false
    window.isMovable = false

    let host = NSHostingView(rootView: NotificationStackView(manager: manager))
    host.frame = window.contentView?.bounds ?? .zero
    host.autoresizingMask = [.width, .height]
    window.contentView?.addSubview(host)

    super.init(window: window)
    repositionToTopRight()
    NotificationCenter.default.addObserver(
      self, selector: #selector(repositionToTopRight),
      name: NSApplication.didChangeScreenParametersNotification, object: nil
    )
  }

  required init?(coder: NSCoder) { fatalError() }

  @objc private func repositionToTopRight() {
    guard let window, let screen = NSScreen.main else { return }
    let visible = screen.visibleFrame
    let size = NSSize(width: 420, height: visible.height - 20)
    let origin = NSPoint(x: visible.maxX - size.width, y: visible.maxY - size.height)
    window.setFrame(NSRect(origin: origin, size: size), display: true)
  }
}

/// Borderless window subclass that allows mouse pass-through over empty regions
/// so it doesn't steal clicks from whatever is behind it.
private final class StackWindow: NSWindow {
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}
