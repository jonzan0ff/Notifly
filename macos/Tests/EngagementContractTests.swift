import XCTest

/// Contract tests for the Notifly VS Code extension's engagement signals.
///
/// The extension fires `active` pings to Notifly's IPC server, which uses
/// them to (a) clear existing cards for a project and (b) suppress incoming
/// cards for that project for a short window. Because suppression silences
/// notifications, the set of triggers MUST be limited to "user is actually
/// engaged with the Claude Code webview" — not "user is editing a file in
/// any project," which is the normal coding workflow during which Stop-event
/// cards are most useful and must NOT be suppressed.
///
/// These tests read `vscode-extension/src/extension.ts` directly and assert
/// the contract is upheld. They exist because v0.1.5 shipped with the file
/// editing trigger still wired up, which silently swallowed every Stop card
/// for any project the user was actively coding in. A unit test on the Swift
/// side can't simulate VS Code, but it can catch a forbidden subscription
/// being added back to the extension source.
final class EngagementContractTests: XCTestCase {

  /// The extension source must not subscribe to file-document edits.
  /// Editing a source file is not "engagement with Claude" — it's normal
  /// coding and must never suppress notifications.
  func test_extension_does_not_subscribe_to_file_edits() throws {
    let source = try loadExtensionSource()
    XCTAssertFalse(
      source.contains("onDidChangeTextDocument"),
      """
      vscode-extension/src/extension.ts subscribes to onDidChangeTextDocument.
      That is forbidden — file edits must not trigger Notifly active pings,
      because they would suppress Stop-event cards while the user is coding.
      Remove the subscription.
      """
    )
  }

  /// The extension source must declare the engagement signal contract in a
  /// comment that points at this test file. If somebody removes the comment,
  /// the chain of intent is broken and a future contributor may add file
  /// editing back — so we assert the comment is present and links here.
  func test_extension_declares_engagement_contract_comment() throws {
    let source = try loadExtensionSource()
    XCTAssertTrue(
      source.contains("ENGAGEMENT CONTRACT"),
      "extension.ts must contain an 'ENGAGEMENT CONTRACT' comment block"
    )
    XCTAssertTrue(
      source.contains("EngagementContractTests"),
      "extension.ts engagement contract comment must reference EngagementContractTests by name"
    )
  }

  /// Each of the four allowed engagement signals must remain wired up. If
  /// somebody deletes one accidentally, the test fails loudly.
  func test_extension_wires_all_four_engagement_signals() throws {
    let source = try loadExtensionSource()
    let required = [
      "onDidChangeWindowState",
      "tabGroups.onDidChangeTabs",
      "tabGroups.onDidChangeTabGroups",
      "setInterval",
    ]
    for symbol in required {
      XCTAssertTrue(
        source.contains(symbol),
        "extension.ts is missing required engagement signal source: \(symbol)"
      )
    }
  }

  // MARK: - Helpers

  private func loadExtensionSource() throws -> String {
    // Walk up from this test file's location to the repo root, then read
    // vscode-extension/src/extension.ts. Using #filePath keeps the test
    // robust against build product directories.
    let testFile = URL(fileURLWithPath: #filePath)
    let repoRoot = testFile
      .deletingLastPathComponent()  // Tests/
      .deletingLastPathComponent()  // macos/
      .deletingLastPathComponent()  // repo root
    let extPath = repoRoot
      .appendingPathComponent("vscode-extension")
      .appendingPathComponent("src")
      .appendingPathComponent("extension.ts")
    return try String(contentsOf: extPath, encoding: .utf8)
  }
}
