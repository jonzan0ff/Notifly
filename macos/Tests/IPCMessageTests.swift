import XCTest
@testable import Notifly

final class IPCMessageTests: XCTestCase {

  // MARK: - Decoding

  func test_decode_send_with_all_fields() throws {
    let json = #"{"type":"send","project":"Dorothy","event":"done","message":"all green"}"#
    let msg = try decode(json)
    XCTAssertEqual(msg.type, "send")
    XCTAssertEqual(msg.project, "Dorothy")
    XCTAssertEqual(msg.event, "done")
    XCTAssertEqual(msg.message, "all green")
  }

  func test_decode_active_with_project() throws {
    let json = #"{"type":"active","project":"Dorothy"}"#
    let msg = try decode(json)
    XCTAssertEqual(msg.type, "active")
    XCTAssertEqual(msg.project, "Dorothy")
    XCTAssertNil(msg.event)
    XCTAssertNil(msg.message)
  }

  func test_decode_clear() throws {
    let json = #"{"type":"clear"}"#
    let msg = try decode(json)
    XCTAssertEqual(msg.type, "clear")
    XCTAssertNil(msg.project)
  }

  func test_decode_unknown_type_still_decodes() throws {
    // Validation happens at handle() time; the model itself accepts any string.
    let json = #"{"type":"explode"}"#
    let msg = try decode(json)
    XCTAssertEqual(msg.type, "explode")
  }

  func test_decode_missing_type_throws() {
    let json = #"{"project":"X"}"#
    XCTAssertThrowsError(try decode(json))
  }

  // MARK: - Helpers

  private func decode(_ json: String) throws -> IPCMessage {
    let data = json.data(using: .utf8)!
    return try JSONDecoder().decode(IPCMessage.self, from: data)
  }
}
