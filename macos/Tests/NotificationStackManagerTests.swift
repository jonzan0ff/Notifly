import XCTest
@testable import Notifly

@MainActor
final class NotificationStackManagerTests: XCTestCase {

  /// The manager is a singleton and survives across tests, so reset it before each.
  override func setUp() async throws {
    try await super.setUp()
    NotificationStackManager.shared.clearAll()
    try await waitForMainQueue()
  }

  func test_submit_adds_event_to_stack() async throws {
    NotificationStackManager.shared.submit(.fixture(project: "Dorothy"))
    try await waitForMainQueue()
    XCTAssertEqual(NotificationStackManager.shared.events.count, 1)
    XCTAssertEqual(NotificationStackManager.shared.events.first?.project, "Dorothy")
  }

  func test_submit_inserts_newest_first() async throws {
    NotificationStackManager.shared.submit(.fixture(project: "First"))
    NotificationStackManager.shared.submit(.fixture(project: "Second"))
    NotificationStackManager.shared.submit(.fixture(project: "Third"))
    try await waitForMainQueue()
    let events = NotificationStackManager.shared.events
    XCTAssertEqual(events.count, 3)
    XCTAssertEqual(events.map(\.project), ["Third", "Second", "First"])
  }

  func test_submit_replaces_existing_for_same_project() async throws {
    NotificationStackManager.shared.submit(.fixture(project: "Dorothy", message: "first"))
    NotificationStackManager.shared.submit(.fixture(project: "Dorothy", message: "second"))
    try await waitForMainQueue()
    let events = NotificationStackManager.shared.events
    XCTAssertEqual(events.count, 1)
    XCTAssertEqual(events.first?.message, "second")
  }

  func test_submit_keeps_other_projects_when_replacing() async throws {
    NotificationStackManager.shared.submit(.fixture(project: "Dorothy"))
    NotificationStackManager.shared.submit(.fixture(project: "Camp"))
    NotificationStackManager.shared.submit(.fixture(project: "Dorothy", message: "updated"))
    try await waitForMainQueue()
    let projects = Set(NotificationStackManager.shared.events.map(\.project))
    XCTAssertEqual(projects, Set(["Dorothy", "Camp"]))
  }

  func test_clearProject_removes_only_matching() async throws {
    NotificationStackManager.shared.submit(.fixture(project: "Dorothy"))
    NotificationStackManager.shared.submit(.fixture(project: "Camp"))
    NotificationStackManager.shared.clearProject("Dorothy")
    try await waitForMainQueue()
    let projects = NotificationStackManager.shared.events.map(\.project)
    XCTAssertEqual(projects, ["Camp"])
  }

  func test_clearProject_unknown_is_noop() async throws {
    NotificationStackManager.shared.submit(.fixture(project: "Dorothy"))
    NotificationStackManager.shared.clearProject("Ghost")
    try await waitForMainQueue()
    XCTAssertEqual(NotificationStackManager.shared.events.count, 1)
  }

  func test_clearAll_empties_stack() async throws {
    NotificationStackManager.shared.submit(.fixture(project: "A"))
    NotificationStackManager.shared.submit(.fixture(project: "B"))
    NotificationStackManager.shared.submit(.fixture(project: "C"))
    NotificationStackManager.shared.clearAll()
    try await waitForMainQueue()
    XCTAssertTrue(NotificationStackManager.shared.events.isEmpty)
  }

  func test_submit_after_clearProject_is_suppressed_within_window() async throws {
    NotificationStackManager.shared.clearProject("Dorothy")
    try await waitForMainQueue()
    NotificationStackManager.shared.submit(.fixture(project: "Dorothy"))
    try await waitForMainQueue()
    XCTAssertTrue(
      NotificationStackManager.shared.events.isEmpty,
      "card submitted within suppression window after active ping must be dropped"
    )
  }

  func test_suppression_is_per_project() async throws {
    NotificationStackManager.shared.clearProject("Dorothy")
    try await waitForMainQueue()
    NotificationStackManager.shared.submit(.fixture(project: "Camp"))
    try await waitForMainQueue()
    XCTAssertEqual(
      NotificationStackManager.shared.events.map(\.project),
      ["Camp"],
      "suppression for Dorothy must not affect Camp"
    )
  }

  func test_dismiss_removes_specific_event_by_id() async throws {
    let target = NotiflyEvent.fixture(project: "Dorothy")
    NotificationStackManager.shared.submit(target)
    NotificationStackManager.shared.submit(.fixture(project: "Camp"))
    try await waitForMainQueue()
    let dorothyInStack = NotificationStackManager.shared.events.first { $0.project == "Dorothy" }!
    NotificationStackManager.shared.dismiss(dorothyInStack)
    try await waitForMainQueue()
    XCTAssertEqual(NotificationStackManager.shared.events.map(\.project), ["Camp"])
  }

  // MARK: - Helpers

  /// Yield to the main queue so DispatchQueue.main.async blocks complete.
  private func waitForMainQueue() async throws {
    let exp = expectation(description: "main queue tick")
    DispatchQueue.main.async { exp.fulfill() }
    await fulfillment(of: [exp], timeout: 1.0)
  }
}

extension NotiflyEvent {
  static func fixture(
    project: String = "TestProject",
    type: NotiflyEventType = .done,
    message: String = "test message"
  ) -> NotiflyEvent {
    NotiflyEvent(project: project, type: type, message: message)
  }
}
