import XCTest
import AppKit
@testable import Notifly

/// Regression tests for the "invisible clickable panel" incident (2026-04-13).
///
/// The panel MUST:
///   1. Be ordered out (invisible to the window server) when events is empty,
///      so it can't intercept clicks anywhere on screen
///   2. Be sized to exactly the SwiftUI stack height when events is non-empty,
///      so clicks landing outside the card stack pass through to the app
///      underneath
///
/// Failing these assertions means we've regressed to a v0.1.1-style full-height
/// click-hijacking panel, which blocks the user's entire right-column workflow.
@MainActor
final class NotificationStackWindowControllerTests: XCTestCase {

  override func setUp() async throws {
    try await super.setUp()
    NotificationStackManager.shared.clearAll()
    try await tickMain()
  }

  func test_panel_is_hidden_when_events_empty() async throws {
    let controller = NotificationStackWindowController(manager: NotificationStackManager.shared)
    try await tickMain()

    XCTAssertFalse(
      controller.isVisibleForTesting,
      "panel must be orderOut'd when there are zero events — otherwise it hijacks clicks across the screen"
    )
  }

  func test_panel_becomes_visible_after_submit() async throws {
    let controller = NotificationStackWindowController(manager: NotificationStackManager.shared)
    try await tickMain()
    XCTAssertFalse(controller.isVisibleForTesting)

    NotificationStackManager.shared.submit(.init(project: "Test", type: .done, message: "hello"))
    try await tickMain()

    XCTAssertTrue(
      controller.isVisibleForTesting,
      "panel must orderFront once at least one event is in the stack"
    )
  }

  func test_panel_frame_height_shrinks_back_to_nothing_when_stack_is_cleared() async throws {
    let controller = NotificationStackWindowController(manager: NotificationStackManager.shared)
    try await tickMain()

    NotificationStackManager.shared.submit(.init(project: "A", type: .done, message: "a"))
    NotificationStackManager.shared.submit(.init(project: "B", type: .attention, message: "b"))
    NotificationStackManager.shared.submit(.init(project: "C", type: .stopped, message: "c"))
    try await tickMain()

    // With three cards the frame must be finite and positive but nowhere
    // near the full screen height.
    let withCards = controller.currentFrameForTesting
    XCTAssertNotNil(withCards)
    if let frame = withCards {
      XCTAssertGreaterThan(frame.size.height, 0, "panel must have non-zero height with cards")
      let screenHeight = NSScreen.main?.visibleFrame.height ?? 1000
      XCTAssertLessThan(
        frame.size.height, screenHeight * 0.9,
        "panel must NOT span nearly the full screen — that's the click-hijack regression"
      )
    }

    NotificationStackManager.shared.clearAll()
    try await tickMain()

    XCTAssertFalse(
      controller.isVisibleForTesting,
      "clearing the stack must orderOut the panel"
    )
    if let emptyFrame = controller.currentFrameForTesting {
      XCTAssertLessThanOrEqual(
        emptyFrame.size.height, 1.0,
        "panel frame must collapse to ~0 height when empty (no accidental hit region)"
      )
    }
  }

  func test_panel_width_is_fixed_and_sane() async throws {
    let controller = NotificationStackWindowController(manager: NotificationStackManager.shared)
    NotificationStackManager.shared.submit(.init(project: "X", type: .done, message: "y"))
    try await tickMain()

    if let frame = controller.currentFrameForTesting {
      XCTAssertEqual(frame.size.width, 420, accuracy: 1, "panel width must be the fixed card-column width")
    } else {
      XCTFail("controller has no window frame after submit")
    }
  }

  // MARK: - Helpers

  private func tickMain() async throws {
    let exp = expectation(description: "main tick")
    DispatchQueue.main.async { exp.fulfill() }
    await fulfillment(of: [exp], timeout: 1.0)
    // Let SwiftUI layout / Combine sinks settle.
    try await Task.sleep(nanoseconds: 100_000_000)
  }
}
