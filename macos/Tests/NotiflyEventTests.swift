import XCTest
@testable import Notifly

final class NotiflyEventTests: XCTestCase {

  func test_message_is_truncated_at_240_chars() {
    let long = String(repeating: "a", count: 500)
    let event = NotiflyEvent(project: "X", type: .done, message: long)
    XCTAssertEqual(event.message.count, 240)
    XCTAssertTrue(event.message.hasSuffix("…"))
  }

  func test_short_message_is_unchanged() {
    let event = NotiflyEvent(project: "X", type: .done, message: "hello")
    XCTAssertEqual(event.message, "hello")
  }

  func test_whitespace_is_trimmed() {
    let event = NotiflyEvent(project: "X", type: .done, message: "  hi\n")
    XCTAssertEqual(event.message, "hi")
  }
}
