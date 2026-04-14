import XCTest
@testable import Notifly

/// Asserts the status-item menu reflects the current update state.
/// Complements the live orange-dot screenshot — this is the deterministic
/// closure test for the "Install Update" branch that can't be visually
/// inspected without clicking the menu.
@MainActor
final class MenuBarControllerTests: XCTestCase {

  override func setUp() async throws {
    try await super.setUp()
    AppState.shared.availableUpdate = nil
    AppState.shared.isInstallingUpdate = false
    AppState.shared.updateProgress = 0
  }

  override func tearDown() async throws {
    AppState.shared.availableUpdate = nil
    AppState.shared.isInstallingUpdate = false
    try await super.tearDown()
  }

  func test_menu_shows_check_for_updates_when_no_update_available() {
    MenuBarController.shared.install()
    let titles = MenuBarController.shared.menuItemTitlesForTesting
    XCTAssertTrue(titles.contains("Check for Updates…"),
                  "menu must offer 'Check for Updates…' when availableUpdate is nil, got \(titles)")
    XCTAssertFalse(titles.contains("Install Update"),
                   "menu must NOT offer 'Install Update' when availableUpdate is nil")
  }

  func test_menu_shows_install_update_when_release_is_available() {
    MenuBarController.shared.install()
    AppState.shared.availableUpdate = .init(
      tagName: "v0.1.3",
      name: "v0.1.3",
      assets: [.init(id: 1, name: "Notifly-0.1.3.zip", browserDownloadURL: "https://example.test/notifly.zip")]
    )
    let titles = MenuBarController.shared.menuItemTitlesForTesting
    XCTAssertTrue(titles.contains("Install Update"),
                  "menu must offer 'Install Update' when availableUpdate is set, got \(titles)")
    XCTAssertFalse(titles.contains("Check for Updates…"),
                   "menu must NOT offer 'Check for Updates…' when an update is already available")
  }

  func test_menu_shows_installing_when_install_in_progress() {
    MenuBarController.shared.install()
    AppState.shared.availableUpdate = .init(
      tagName: "v0.1.3",
      name: "v0.1.3",
      assets: [.init(id: 1, name: "Notifly-0.1.3.zip", browserDownloadURL: "https://example.test/notifly.zip")]
    )
    AppState.shared.isInstallingUpdate = true
    let titles = MenuBarController.shared.menuItemTitlesForTesting
    XCTAssertTrue(titles.contains("Installing update…"),
                  "menu must show 'Installing update…' while install is running, got \(titles)")
    XCTAssertFalse(titles.contains("Install Update"),
                   "menu must NOT offer a second 'Install Update' while one is already running")
  }

  func test_menu_always_includes_version_and_quit() {
    MenuBarController.shared.install()
    let titles = MenuBarController.shared.menuItemTitlesForTesting
    XCTAssertTrue(titles.contains(where: { $0.hasPrefix("Notifly ") }),
                  "menu must include a version header starting with 'Notifly ', got \(titles)")
    XCTAssertTrue(titles.contains("Quit Notifly"),
                  "menu must always include 'Quit Notifly'")
  }
}
