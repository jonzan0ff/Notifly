import AppKit
import SwiftUI
import Combine

/// Borderless, non-activating floating panel pinned to the top-right of the
/// active screen, just below the menu bar. Hosts the SwiftUI notification stack.
///
/// **Critical rule:** the panel's frame is sized to exactly the current card
/// stack. When there are zero cards, the panel is `orderOut`'d from the window
/// server entirely so it can't intercept mouse events anywhere on screen.
///
/// Shipping a full-height transparent panel at `.statusBar` level with
/// `ignoresMouseEvents = false` caused a SEVERE bug in v0.1.1 where a ~420pt
/// × full-height column of the user's screen silently ate clicks and window
/// drags (see `.claude/incident-log.md`). This controller now observes
/// `manager.events` via Combine and recomputes the panel frame on every
/// change using `NSHostingView.fittingSize`, so the hit region matches the
/// pixels the user can see.
final class NotificationStackWindowController: NSWindowController {

  private let manager: NotificationStackManager
  private let host: NSHostingView<NotificationStackView>
  private var cancellables = Set<AnyCancellable>()

  init(manager: NotificationStackManager) {
    self.manager = manager
    self.host = NSHostingView(rootView: NotificationStackView(manager: manager))
    // Start at zero size — the first events update will grow the panel.
    host.frame = .zero

    let panel = StackPanel(
      contentRect: NSRect(x: 0, y: 0, width: 420, height: 1),
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
    panel.becomesKeyOnlyIfNeeded = true

    panel.contentView?.addSubview(host)

    super.init(window: panel)

    // Hidden at launch — only shown once there's at least one event to render.
    panel.orderOut(nil)

    // React to every events change: resize panel to fit, orderOut if empty.
    manager.$events
      .receive(on: DispatchQueue.main)
      .sink { [weak self] events in
        self?.updatePanel(forEvents: events)
      }
      .store(in: &cancellables)

    NotificationCenter.default.addObserver(
      self, selector: #selector(screenParamsChanged),
      name: NSApplication.didChangeScreenParametersNotification, object: nil
    )
  }

  required init?(coder: NSCoder) { fatalError() }

  @objc private func screenParamsChanged() {
    updatePanel(forEvents: manager.events)
  }

  /// Measures the SwiftUI stack's preferred size with the current event list
  /// and resizes the panel to match. Hides (`orderOut`) when empty.
  private func updatePanel(forEvents events: [NotiflyEvent]) {
    guard let window, let screen = NSScreen.main else { return }

    if events.isEmpty {
      window.orderOut(nil)
      // Collapse the frame so any accidental orderFront during this state
      // can't briefly paint a huge hit region.
      window.setFrame(NSRect(x: 0, y: 0, width: 1, height: 1), display: false)
      return
    }

    // Ask SwiftUI what size it wants for the current events. Width is fixed
    // (the card design is 392pt + 14pt trailing padding = 406, round to 420).
    let targetWidth: CGFloat = 420
    host.frame = NSRect(x: 0, y: 0, width: targetWidth, height: 10000)
    let fitting = host.fittingSize
    let height = max(1, fitting.height)

    let visible = screen.visibleFrame
    let frame = NSRect(
      x: visible.maxX - targetWidth,
      y: visible.maxY - height,
      width: targetWidth,
      height: height
    )
    host.frame = NSRect(x: 0, y: 0, width: targetWidth, height: height)
    window.setFrame(frame, display: true)
    window.orderFront(nil)
  }

  // MARK: - Test hooks
  //
  // Exposed for NotificationStackWindowControllerTests so the panel geometry
  // can be asserted directly (empty -> invisible, non-empty -> sized to
  // SwiftUI's fitting height).

  /// Current panel frame on screen. nil if the window was torn down.
  var currentFrameForTesting: NSRect? { window?.frame }

  /// Whether the panel is currently visible to the window server.
  var isVisibleForTesting: Bool { window?.isVisible ?? false }
}

/// NSPanel subclass. Uses `becomesKeyOnlyIfNeeded` on the panel config so
/// mouse clicks route to SwiftUI buttons without stealing keystrokes from
/// the user's active app (VS Code, etc.).
private final class StackPanel: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
}
