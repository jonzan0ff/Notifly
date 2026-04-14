import AppKit
import SwiftUI

/// Borderless, non-activating floating panel pinned to the top-right of the
/// active screen, just below the menu bar. Hosts the SwiftUI notification stack.
///
/// Uses NSPanel with `.nonactivatingPanel` so SwiftUI buttons inside the cards
/// receive clicks WITHOUT the panel stealing focus from whatever app is in front.
/// (A regular NSWindow with `canBecomeKey=false` swallows mouse-up events on
/// SwiftUI buttons, which is why the action buttons appeared dead.)
final class NotificationStackWindowController: NSWindowController {

  private let manager: NotificationStackManager

  init(manager: NotificationStackManager) {
    self.manager = manager

    let panel = StackPanel(
      contentRect: NSRect(x: 0, y: 0, width: 420, height: 800),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.level = .statusBar
    panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
    panel.ignoresMouseEvents = false
    panel.isMovable = false
    panel.hidesOnDeactivate = false
    panel.isFloatingPanel = true
    // Only become key when a control actually needs keyboard input (none of ours
    // do). This routes mouse clicks to SwiftUI buttons without stealing keystrokes
    // from VS Code (or whatever app is currently in front).
    panel.becomesKeyOnlyIfNeeded = true

    let host = NSHostingView(rootView: NotificationStackView(manager: manager))
    host.frame = panel.contentView?.bounds ?? .zero
    host.autoresizingMask = [.width, .height]
    panel.contentView?.addSubview(host)

    super.init(window: panel)
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

/// NSPanel subclass that allows clicks on its content (SwiftUI buttons) without
/// becoming key. The `.nonactivatingPanel` style mask plus this override is the
/// idiomatic AppKit pattern for status-bar-level overlay UIs.
private final class StackPanel: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
}
