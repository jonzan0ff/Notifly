import XCTest
@testable import Notifly

/// End-to-end integration tests for `UpdateService.install(zipAt:)` — the
/// extract + replace + relaunch half of the auto-update flow. These close
/// the gap the user called out after v0.1.3 was proven only for the
/// orange-dot detection side.
///
/// Approach: build a minimal fixture `.app` bundle on disk, ditto it into a
/// zip, point `UpdateService.installDestination` at a temp path via env var,
/// and call `install(zipAt:)` directly. No network. No /Applications. No
/// sudo. No relaunch (NOTIFLY_SKIP_RELAUNCH=1 is set on the test host's
/// environment via Info.plist... actually via setenv at runtime).
final class UpdateServiceInstallTests: XCTestCase {

  var tempRoot: URL!
  var destination: URL!

  override func setUp() {
    super.setUp()
    // Unique temp root per test so parallel runs can't collide.
    tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("notifly-install-test-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    destination = tempRoot.appendingPathComponent("Notifly.app")

    setenv("NOTIFLY_INSTALL_DESTINATION", destination.path, 1)
    setenv("NOTIFLY_SKIP_RELAUNCH", "1", 1)
  }

  override func tearDown() {
    unsetenv("NOTIFLY_INSTALL_DESTINATION")
    unsetenv("NOTIFLY_SKIP_RELAUNCH")
    try? FileManager.default.removeItem(at: tempRoot)
    super.tearDown()
  }

  // MARK: - Fixture helpers

  /// Creates a minimal macOS .app bundle on disk with a marker Info.plist
  /// the tests can verify was preserved end-to-end.
  private func makeFixtureAppBundle(at location: URL, version: String, marker: String) throws {
    let macOSDir = location.appendingPathComponent("Contents/MacOS")
    try FileManager.default.createDirectory(at: macOSDir, withIntermediateDirectories: true)

    // A stub executable. Not runnable — just needs to exist to keep the
    // bundle shape valid.
    let exe = macOSDir.appendingPathComponent("Notifly")
    try "stub".data(using: .utf8)!.write(to: exe)

    // Info.plist with a recognizable marker so the test can confirm the
    // exact fixture bundle landed at the destination rather than some
    // leftover from a prior run.
    let plist: [String: Any] = [
      "CFBundleName": "Notifly",
      "CFBundleIdentifier": "com.Notiflyz.app",
      "CFBundleShortVersionString": version,
      "CFBundleVersion": "1",
      "CFBundleExecutable": "Notifly",
      "NotiflyTestMarker": marker,
    ]
    let plistURL = location.appendingPathComponent("Contents/Info.plist")
    let plistData = try PropertyListSerialization.data(
      fromPropertyList: plist, format: .xml, options: 0
    )
    try plistData.write(to: plistURL)
  }

  /// Ditto-zips a directory to a file path (matching the format gh release
  /// assets use in production).
  private func makeFixtureZip(of sourceAppPath: URL, at zipPath: URL) throws {
    let ditto = Process()
    ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
    ditto.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", sourceAppPath.path, zipPath.path]
    try ditto.run()
    ditto.waitUntilExit()
    guard ditto.terminationStatus == 0 else {
      throw NSError(domain: "test.zip", code: Int(ditto.terminationStatus))
    }
  }

  /// Reads the install destination's CFBundleShortVersionString so tests can
  /// verify which fixture bundle currently occupies the destination.
  private func destinationVersion() throws -> String {
    let plistURL = destination.appendingPathComponent("Contents/Info.plist")
    let data = try Data(contentsOf: plistURL)
    guard let plist = try PropertyListSerialization.propertyList(
      from: data, options: [], format: nil
    ) as? [String: Any] else {
      throw NSError(domain: "test.plist", code: 0)
    }
    return (plist["CFBundleShortVersionString"] as? String) ?? "?"
  }

  private func destinationMarker() throws -> String {
    let plistURL = destination.appendingPathComponent("Contents/Info.plist")
    let data = try Data(contentsOf: plistURL)
    let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
    return (plist?["NotiflyTestMarker"] as? String) ?? ""
  }

  // MARK: - Tests

  func test_install_places_bundle_at_destination_when_destination_is_empty() async throws {
    // Build fixture .app at a staging path, zip it, hand the zip to install()
    let staging = tempRoot.appendingPathComponent("staging/Notifly.app")
    try makeFixtureAppBundle(at: staging, version: "0.1.3", marker: "fresh-install")

    let zip = tempRoot.appendingPathComponent("Notifly-0.1.3.zip")
    try makeFixtureZip(of: staging, at: zip)

    XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path),
                   "precondition: destination must not exist before install")

    try await UpdateService.shared.install(zipAt: zip)

    XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path),
                  "destination .app must exist after install")
    XCTAssertEqual(try destinationVersion(), "0.1.3")
    XCTAssertEqual(try destinationMarker(), "fresh-install")
  }

  func test_install_replaces_existing_bundle_at_destination() async throws {
    // Pre-populate the destination with an "old" version bundle
    try makeFixtureAppBundle(at: destination, version: "0.1.0", marker: "old")
    XCTAssertEqual(try destinationVersion(), "0.1.0", "precondition: old build at destination")
    XCTAssertEqual(try destinationMarker(), "old")

    // Build a newer fixture .app and zip it
    let staging = tempRoot.appendingPathComponent("staging/Notifly.app")
    try makeFixtureAppBundle(at: staging, version: "0.1.3", marker: "new")
    let zip = tempRoot.appendingPathComponent("Notifly-0.1.3.zip")
    try makeFixtureZip(of: staging, at: zip)

    try await UpdateService.shared.install(zipAt: zip)

    XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
    XCTAssertEqual(try destinationVersion(), "0.1.3",
                   "install must replace the old 0.1.0 with the new 0.1.3 bundle")
    XCTAssertEqual(try destinationMarker(), "new",
                   "the NEW fixture's marker must be present — proves the bytes actually changed")
  }

  func test_install_throws_for_zip_with_no_dot_app_inside() async throws {
    // Build a zip of a non-.app directory — install should throw noAppInZip.
    let fakeDir = tempRoot.appendingPathComponent("not-an-app")
    try FileManager.default.createDirectory(at: fakeDir, withIntermediateDirectories: true)
    try "hello".data(using: .utf8)!.write(to: fakeDir.appendingPathComponent("README.txt"))

    let zip = tempRoot.appendingPathComponent("not-an-app.zip")
    try makeFixtureZip(of: fakeDir, at: zip)

    do {
      try await UpdateService.shared.install(zipAt: zip)
      XCTFail("expected install(zipAt:) to throw for a zip that contains no .app bundle")
    } catch let error as UpdateService.UpdateError {
      XCTAssertEqual(error.localizedDescription, UpdateService.UpdateError.noAppInZip.localizedDescription)
    }
  }

  func test_installDestination_reads_env_override() {
    // Verify the override mechanism itself — the env var set in setUp
    // must be what UpdateService reads at call time.
    XCTAssertEqual(
      UpdateService.installDestination.path,
      destination.path,
      "UpdateService.installDestination must read NOTIFLY_INSTALL_DESTINATION each time"
    )
  }

  func test_skipRelaunch_reads_env_override() {
    XCTAssertTrue(
      UpdateService.skipRelaunch,
      "UpdateService.skipRelaunch must read NOTIFLY_SKIP_RELAUNCH each time"
    )
    unsetenv("NOTIFLY_SKIP_RELAUNCH")
    XCTAssertFalse(
      UpdateService.skipRelaunch,
      "after unsetenv, skipRelaunch must be false (the production default)"
    )
    setenv("NOTIFLY_SKIP_RELAUNCH", "1", 1)
  }
}
