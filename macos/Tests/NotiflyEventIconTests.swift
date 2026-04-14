import XCTest
import AppKit
@testable import Notifly

/// Proves that when an NotiflyEvent is given an iconPath that points at a real
/// PNG, the path round-trips intact and the file is actually loadable as an
/// NSImage. This catches drift between the IPC layer, the model, and the view's
/// expectations.
final class NotiflyEventIconTests: XCTestCase {

  var tempIconPath: String!

  override func setUp() {
    super.setUp()
    // Generate a tiny throwaway PNG on disk that the test can read back.
    let dir = NSTemporaryDirectory() + "notifly-icon-test-\(UUID().uuidString)"
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    tempIconPath = dir + "/icon.png"

    let image = NSImage(size: NSSize(width: 64, height: 64))
    image.lockFocus()
    NSColor.systemTeal.setFill()
    NSRect(x: 0, y: 0, width: 64, height: 64).fill()
    image.unlockFocus()

    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
      XCTFail("could not generate fixture png"); return
    }
    try? png.write(to: URL(fileURLWithPath: tempIconPath))
  }

  override func tearDown() {
    try? FileManager.default.removeItem(atPath: (tempIconPath as NSString).deletingLastPathComponent)
    super.tearDown()
  }

  func test_event_stores_icon_path_when_given() {
    let event = NotiflyEvent(project: "Test", type: .done, message: "msg", iconPath: tempIconPath)
    XCTAssertEqual(event.iconPath, tempIconPath)
  }

  func test_event_icon_path_is_nil_when_omitted() {
    let event = NotiflyEvent(project: "Test", type: .done, message: "msg")
    XCTAssertNil(event.iconPath)
  }

  func test_icon_path_resolves_to_a_loadable_NSImage() {
    let event = NotiflyEvent(project: "Test", type: .done, message: "msg", iconPath: tempIconPath)
    guard let path = event.iconPath else {
      XCTFail("expected iconPath"); return
    }
    XCTAssertTrue(FileManager.default.fileExists(atPath: path))
    let image = NSImage(contentsOfFile: path)
    XCTAssertNotNil(image, "icon at \(path) should load as NSImage")
    XCTAssertEqual(image?.size.width, 64)
    XCTAssertEqual(image?.size.height, 64)
  }

  func test_missing_icon_path_does_not_crash_loader() {
    let event = NotiflyEvent(project: "Test", type: .done, message: "msg", iconPath: "/nonexistent/icon.png")
    XCTAssertEqual(event.iconPath, "/nonexistent/icon.png")
    XCTAssertNil(NSImage(contentsOfFile: event.iconPath!))
  }

  // MARK: - Real project icon files

  func test_camp_clintondale_icon_exists_and_loads() throws {
    let path = "/Users/jonzanoff/Documents/jonzan0ff/Projects/Camp Clintondale/.claude/icon.png"
    guard FileManager.default.fileExists(atPath: path) else {
      throw XCTSkip("Camp Clintondale icon not present on this machine — skipping")
    }
    let image = NSImage(contentsOfFile: path)
    XCTAssertNotNil(image)
    XCTAssertGreaterThanOrEqual(image?.size.width ?? 0, 256, "icon should be at least 256pt wide")
  }

  func test_notifly_icon_exists_and_loads() throws {
    let path = "/Users/jonzanoff/Documents/jonzan0ff/Projects/Notifly/.claude/icon.png"
    guard FileManager.default.fileExists(atPath: path) else {
      throw XCTSkip("Notifly icon not present — skipping")
    }
    let image = NSImage(contentsOfFile: path)
    XCTAssertNotNil(image)
    XCTAssertGreaterThanOrEqual(image?.size.width ?? 0, 256)
  }

  // MARK: - IPC plumbing

  func test_ipc_message_with_icon_path_round_trips() throws {
    let json = #"{"type":"send","project":"Camp Clintondale","event":"done","message":"ok","iconPath":"\#(tempIconPath!)"}"#
    let msg = try JSONDecoder().decode(IPCMessage.self, from: Data(json.utf8))
    XCTAssertEqual(msg.iconPath, tempIconPath)
  }

  func test_ipc_message_without_icon_path_decodes() throws {
    let json = #"{"type":"send","project":"X","event":"done","message":"ok"}"#
    let msg = try JSONDecoder().decode(IPCMessage.self, from: Data(json.utf8))
    XCTAssertNil(msg.iconPath)
  }
}
