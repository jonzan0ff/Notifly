import AppKit
import Combine

@MainActor
final class MenuBarController: NSObject {
  static let shared = MenuBarController()

  private var statusItem: NSStatusItem?
  private var cancellables = Set<AnyCancellable>()

  private override init() { super.init() }

  func install() {
    guard statusItem == nil else { return }
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    self.statusItem = item
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

  // MARK: - Menu (rebuilt each click so the version + update label are fresh)

  func attachMenu() {
    statusItem?.menu = buildMenu()
  }

  private func buildMenu() -> NSMenu {
    let menu = NSMenu()
    menu.delegate = self

    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    let versionItem = NSMenuItem(title: "Notifly \(version)", action: nil, keyEquivalent: "")
    versionItem.isEnabled = false
    menu.addItem(versionItem)

    menu.addItem(NSMenuItem.separator())

    if AppState.shared.availableUpdate != nil && !AppState.shared.isInstallingUpdate {
      let install = NSMenuItem(title: "Install Update", action: #selector(installUpdate), keyEquivalent: "")
      install.target = self
      menu.addItem(install)
    } else if AppState.shared.isInstallingUpdate {
      let installing = NSMenuItem(title: "Installing update…", action: nil, keyEquivalent: "")
      installing.isEnabled = false
      menu.addItem(installing)
    } else {
      let check = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
      check.target = self
      menu.addItem(check)
    }

    menu.addItem(NSMenuItem.separator())

    let quit = NSMenuItem(title: "Quit Notifly", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    menu.addItem(quit)

    return menu
  }

  // MARK: - Test hooks

  /// Titles of the current menu items, rebuilt from the current AppState. Used
  /// by `NotiflyMenuBarControllerTests` to verify the "Install Update" branch
  /// appears when an available update is set — the install-flow test closure
  /// that complements the visual orange-dot screenshot.
  var menuItemTitlesForTesting: [String] {
    buildMenu().items.map { $0.title }
  }

  @objc private func checkForUpdates() {
    Task { await AppState.shared.checkForUpdate() }
  }

  @objc private func installUpdate() {
    Task { await AppState.shared.installUpdate() }
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

    statusItem?.menu = buildMenu()
  }
}

extension MenuBarController: NSMenuDelegate {
  func menuWillOpen(_ menu: NSMenu) {
    statusItem?.menu = buildMenu()
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
