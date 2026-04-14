import XCTest
@testable import Notifly

final class UpdateServiceTests: XCTestCase {

  func test_isNewer_patch_bump() {
    XCTAssertTrue(UpdateService.shared.isNewer("0.1.1", than: "0.1.0"))
  }

  func test_isNewer_minor_bump() {
    XCTAssertTrue(UpdateService.shared.isNewer("0.2.0", than: "0.1.9"))
  }

  func test_isNewer_major_bump() {
    XCTAssertTrue(UpdateService.shared.isNewer("1.0.0", than: "0.99.99"))
  }

  func test_equal_versions_not_newer() {
    XCTAssertFalse(UpdateService.shared.isNewer("0.1.0", than: "0.1.0"))
  }

  func test_remote_older_not_newer() {
    XCTAssertFalse(UpdateService.shared.isNewer("0.1.9", than: "0.2.0"))
  }

  func test_double_digit_minor() {
    XCTAssertTrue(UpdateService.shared.isNewer("0.10.0", than: "0.9.0"))
    XCTAssertFalse(UpdateService.shared.isNewer("0.9.0", than: "0.10.0"))
  }

  func test_extra_segment_treated_as_newer() {
    XCTAssertTrue(UpdateService.shared.isNewer("0.1.0.1", than: "0.1.0"))
  }

  func test_short_segment_padded_with_zero() {
    XCTAssertFalse(UpdateService.shared.isNewer("1.0", than: "1.0.0"))
  }
}
