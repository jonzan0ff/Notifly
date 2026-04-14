import XCTest
import AppKit
import SwiftUI
@testable import Notifly

@MainActor
final class MenuBarPopoverSnapshotTests: XCTestCase {

  private let width: CGFloat = 300

  override func setUp() async throws {
    try await super.setUp()
    resetAppState()
  }

  override func tearDown() async throws {
    resetAppState()
    try await super.tearDown()
  }

  // MARK: - Scenarios

  func test_snapshot_idle() throws {
    AppState.shared.availableUpdate = nil
    AppState.shared.isInstallingUpdate = false
    AppState.shared.updateProgress = 0
    try render(scenario: "idle")
  }

  func test_snapshot_update_available() throws {
    AppState.shared.availableUpdate = GitHubRelease(
      tagName: "v9.9.9",
      name: "v9.9.9",
      assets: []
    )
    AppState.shared.isInstallingUpdate = false
    AppState.shared.updateProgress = 0
    try render(scenario: "update_available")
  }

  func test_snapshot_installing_update() throws {
    AppState.shared.availableUpdate = GitHubRelease(
      tagName: "v9.9.9",
      name: "v9.9.9",
      assets: []
    )
    AppState.shared.isInstallingUpdate = true
    AppState.shared.updateProgress = 0.42
    try render(scenario: "installing_update")
  }

  // MARK: - Render helper

  private func render(scenario: String) throws {
    let view = MenuBarPopoverView()
    let hosting = NSHostingView(rootView: view)

    // Let SwiftUI pick its intrinsic height at the fixed 300pt width.
    let fitting = hosting.fittingSize
    let height = max(fitting.height, 1)
    hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
    hosting.layoutSubtreeIfNeeded()

    guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
      XCTFail("Could not create bitmap rep for \(scenario)")
      return
    }
    hosting.cacheDisplay(in: hosting.bounds, to: rep)

    guard let png = rep.representation(using: .png, properties: [:]) else {
      XCTFail("Could not encode PNG for \(scenario)")
      return
    }

    let outputURL = try snapshotURL(for: scenario)
    try png.write(to: outputURL)
  }

  private func snapshotURL(for scenario: String) throws -> URL {
    // This file lives at macos/Tests/MenuBarPopoverSnapshotTests.swift.
    // Write snapshots next to it under __PopoverSnapshots__/.
    let here = URL(fileURLWithPath: #filePath)
    let dir = here
      .deletingLastPathComponent()
      .appendingPathComponent("__PopoverSnapshots__", isDirectory: true)
    try FileManager.default.createDirectory(
      at: dir,
      withIntermediateDirectories: true
    )
    return dir.appendingPathComponent("\(scenario).png")
  }

  private func resetAppState() {
    AppState.shared.availableUpdate = nil
    AppState.shared.isInstallingUpdate = false
    AppState.shared.updateProgress = 0
  }
}
