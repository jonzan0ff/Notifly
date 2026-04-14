import XCTest
@testable import Notifly

final class NotiflyEventTests: XCTestCase {

  func test_init_short_message_unchanged() {
    let event = NotiflyEvent(project: "X", type: .done, message: "hello")
    XCTAssertEqual(event.message, "hello")
  }

  func test_init_long_message_truncated_with_ellipsis() {
    let long = String(repeating: "a", count: 500)
    let event = NotiflyEvent(project: "X", type: .done, message: long)
    XCTAssertEqual(event.message.count, 240)
    XCTAssertTrue(event.message.hasSuffix("…"))
  }

  func test_init_whitespace_trimmed() {
    let event = NotiflyEvent(project: "X", type: .done, message: "  hi\n")
    XCTAssertEqual(event.message, "hi")
  }

  func test_init_assigns_unique_id() {
    let a = NotiflyEvent(project: "X", type: .done, message: "same")
    let b = NotiflyEvent(project: "X", type: .done, message: "same")
    XCTAssertNotEqual(a.id, b.id)
  }

  func test_init_receivedAt_is_now() {
    let event = NotiflyEvent(project: "X", type: .done, message: "")
    XCTAssertEqual(event.receivedAt.timeIntervalSinceNow, 0, accuracy: 1.0)
  }

  func test_event_types_have_string_raw_values() {
    XCTAssertEqual(NotiflyEventType.done.rawValue, "done")
    XCTAssertEqual(NotiflyEventType.attention.rawValue, "attention")
    XCTAssertEqual(NotiflyEventType.stopped.rawValue, "stopped")
  }
}
