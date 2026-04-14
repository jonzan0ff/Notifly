import XCTest
@testable import Notifly

final class ProjectIconTests: XCTestCase {

  // MARK: - Initials

  func test_initials_two_word_project() {
    XCTAssertEqual(ProjectIcon.initials(for: "Camp Clintondale"), "CC")
  }

  func test_initials_single_word() {
    XCTAssertEqual(ProjectIcon.initials(for: "Dorothy"), "DO")
  }

  func test_initials_all_caps() {
    XCTAssertEqual(ProjectIcon.initials(for: "SPAMASAURUS"), "SP")
  }

  func test_initials_three_word_uses_first_two() {
    XCTAssertEqual(ProjectIcon.initials(for: "What to Watch"), "WT")
  }

  func test_initials_single_letter() {
    XCTAssertEqual(ProjectIcon.initials(for: "X"), "X")
  }

  func test_initials_empty_string() {
    XCTAssertEqual(ProjectIcon.initials(for: ""), "")
  }

  func test_initials_whitespace_only() {
    XCTAssertEqual(ProjectIcon.initials(for: "   "), "")
  }

  func test_initials_numeric_project() {
    XCTAssertEqual(ProjectIcon.initials(for: "123"), "12")
  }

  func test_initials_unicode() {
    XCTAssertEqual(ProjectIcon.initials(for: "café"), "CA")
  }

  func test_initials_hyphenated_project_treats_hyphen_as_separator() {
    XCTAssertEqual(ProjectIcon.initials(for: "home-team"), "HT")
  }

  // MARK: - Palette index hash

  func test_paletteIndex_isDeterministic() {
    let a = ProjectIcon.paletteIndex(for: "Dorothy", paletteCount: 7)
    let b = ProjectIcon.paletteIndex(for: "Dorothy", paletteCount: 7)
    XCTAssertEqual(a, b)
  }

  func test_paletteIndex_isInRange() {
    let count = 7
    for name in ["Dorothy", "Camp Clintondale", "SPAMASAURUS", "What to Watch", "HomeTeam", "Print Status"] {
      let i = ProjectIcon.paletteIndex(for: name, paletteCount: count)
      XCTAssertGreaterThanOrEqual(i, 0)
      XCTAssertLessThan(i, count)
    }
  }

  func test_paletteIndex_zero_palette_returns_zero() {
    XCTAssertEqual(ProjectIcon.paletteIndex(for: "anything", paletteCount: 0), 0)
  }

  func test_paletteIndex_distinct_known_projects_are_diverse() {
    // For our 6 known fixtures across 7-color palette, expect at least 4 distinct buckets.
    // (Statistical sanity check, not pigeonhole guarantee.)
    let names = ["Dorothy", "Camp Clintondale", "SPAMASAURUS", "What to Watch", "HomeTeam", "Print Status"]
    let indices = Set(names.map { ProjectIcon.paletteIndex(for: $0, paletteCount: 7) })
    XCTAssertGreaterThanOrEqual(indices.count, 4, "expected diverse palette assignments, got \(indices)")
  }
}
