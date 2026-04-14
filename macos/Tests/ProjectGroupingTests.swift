import XCTest
@testable import Notifly

/// Tests for the project grouping logic: paths under a `Projects/X/...` directory
/// must produce the project name "X", regardless of how deep the cwd is or which
/// sub-repo (admin, guest, etc.) is currently active.
///
/// The Swift side mirrors what `~/.claude/hooks/notify-desktop.sh` and
/// `vscode-extension/src/extension.ts` do, and we verify all three implementations
/// against the same fixture table so they can never drift.
final class ProjectGroupingTests: XCTestCase {

  // The shared fixture table — the source of truth for ALL three implementations
  // (Swift app, bash hook, TypeScript extension). If you add a row here, also
  // add it to the bash + TS test scripts.
  static let fixtures: [(input: String, expected: String)] = [
    // Camp Clintondale sub-repos all collapse to the parent project name
    ("/Users/jonzanoff/Documents/jonzan0ff/Projects/Camp Clintondale/admin",                  "Camp Clintondale"),
    ("/Users/jonzanoff/Documents/jonzan0ff/Projects/Camp Clintondale/guest",                  "Camp Clintondale"),
    ("/Users/jonzanoff/Documents/jonzan0ff/Projects/Camp Clintondale/admin/app/api/users",    "Camp Clintondale"),
    ("/Users/jonzanoff/Documents/jonzan0ff/Projects/Camp Clintondale/email-templates/booking","Camp Clintondale"),
    ("/Users/jonzanoff/Documents/jonzan0ff/Projects/Camp Clintondale",                        "Camp Clintondale"),

    // Single-folder projects
    ("/Users/jonzanoff/Documents/jonzan0ff/Projects/Notifly",                                  "Notifly"),
    ("/Users/jonzanoff/Documents/jonzan0ff/Projects/Notifly/macos/Notifly/Views",              "Notifly"),
    ("/Users/jonzanoff/Documents/jonzan0ff/Projects/Notifly/vscode-extension/src",             "Notifly"),

    // Other projects in the toolkit
    ("/Users/jonzanoff/Documents/jonzan0ff/Projects/Dorothy",                                  "Dorothy"),
    ("/Users/jonzanoff/Documents/jonzan0ff/Projects/Dorothy/server/api",                       "Dorothy"),
    ("/Users/jonzanoff/Documents/jonzan0ff/Projects/HomeTeam/macos/HomeTeamApp/Services",      "HomeTeam"),
    ("/Users/jonzanoff/Documents/jonzan0ff/Projects/SPAMASAURUS/lib/parsers",                  "SPAMASAURUS"),

    // Edge: path NOT under Projects/ — fall back to leaf basename
    ("/tmp/scratch/something",                                                                  "something"),
    ("/Users/jonzanoff/Desktop",                                                                "Desktop"),
  ]

  func test_every_fixture_resolves_to_expected_project() {
    for (input, expected) in Self.fixtures {
      let actual = ProjectGrouping.projectName(forPath: input)
      XCTAssertEqual(
        actual, expected,
        "ProjectGrouping.projectName('\(input)') returned '\(actual)', expected '\(expected)'"
      )
    }
  }

  func test_fixture_table_is_not_empty() {
    XCTAssertGreaterThanOrEqual(Self.fixtures.count, 10, "fixture table should be substantive")
  }

  // MARK: - Specific behaviors

  func test_admin_sub_repo_groups_under_camp_clintondale() {
    XCTAssertEqual(
      ProjectGrouping.projectName(forPath: "/Users/jonzanoff/Documents/jonzan0ff/Projects/Camp Clintondale/admin"),
      "Camp Clintondale"
    )
  }

  func test_guest_sub_repo_groups_under_camp_clintondale() {
    XCTAssertEqual(
      ProjectGrouping.projectName(forPath: "/Users/jonzanoff/Documents/jonzan0ff/Projects/Camp Clintondale/guest"),
      "Camp Clintondale"
    )
  }

  func test_deep_nested_path_still_resolves_to_top_project() {
    XCTAssertEqual(
      ProjectGrouping.projectName(forPath: "/Users/jonzanoff/Documents/jonzan0ff/Projects/Camp Clintondale/admin/app/api/v1/users/handlers/get.ts"),
      "Camp Clintondale"
    )
  }

  func test_path_outside_projects_falls_back_to_leaf() {
    XCTAssertEqual(
      ProjectGrouping.projectName(forPath: "/tmp/random/scratch"),
      "scratch"
    )
  }

  func test_root_path_does_not_loop_forever() {
    let result = ProjectGrouping.projectName(forPath: "/")
    // Just assert it returns *something* and doesn't hang.
    XCTAssertFalse(result.isEmpty)
  }
}
