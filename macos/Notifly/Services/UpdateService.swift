import Foundation
import AppKit

// MARK: - GitHub Release model

struct GitHubRelease: Decodable, Equatable {
  let tagName: String
  let name: String?
  let assets: [GitHubAsset]

  var version: String { tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName }

  enum CodingKeys: String, CodingKey {
    case tagName = "tag_name"
    case name
    case assets
  }
}

struct GitHubAsset: Decodable, Equatable {
  let id: Int
  let name: String
  let browserDownloadURL: String

  enum CodingKeys: String, CodingKey {
    case id, name
    case browserDownloadURL = "browser_download_url"
  }
}

// MARK: - Update service

final class UpdateService: NSObject, @unchecked Sendable {

  static let shared = UpdateService()

  private let owner = "jonzan0ff"
  private let repo = "Notifly"

  private override init() { super.init() }

  // MARK: - Check

  /// Returns the latest release if it's newer than the running app, else nil.
  func checkForUpdate() async -> GitHubRelease? {
    guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest") else { return nil }
    var req = URLRequest(url: url)
    req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    guard let (data, response) = try? await URLSession.shared.data(for: req),
          (response as? HTTPURLResponse)?.statusCode == 200,
          let release = try? JSONDecoder().decode(GitHubRelease.self, from: data) else { return nil }

    let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    return isNewer(release.version, than: current) ? release : nil
  }

  // MARK: - Destination / relaunch overrides (for testing)

  /// Install destination path. Defaults to `/Applications/Notifly.app`.
  /// Overridable via `NOTIFLY_INSTALL_DESTINATION` env var so integration
  /// tests can target a temp path instead of the sudo-gated /Applications/.
  static var installDestination: URL {
    if let override = ProcessInfo.processInfo.environment["NOTIFLY_INSTALL_DESTINATION"] {
      return URL(fileURLWithPath: override)
    }
    return URL(fileURLWithPath: "/Applications/Notifly.app")
  }

  /// Whether to skip the `open` + `NSApplication.terminate` step at the end
  /// of install. Always off in production; set to `1` in tests so we don't
  /// bring up the new app and tear down the test host.
  static var skipRelaunch: Bool {
    ProcessInfo.processInfo.environment["NOTIFLY_SKIP_RELAUNCH"] == "1"
  }

  // MARK: - Download & install

  func downloadAndInstall(release: GitHubRelease, onProgress: @escaping (Double) -> Void) async throws {
    let zipURL = try await download(release: release, onProgress: onProgress)
    try await install(zipAt: zipURL)
  }

  /// Downloads the first `.zip` asset in the release to a stable temp path,
  /// returning its URL. Separated from `install(zipAt:)` so integration tests
  /// can exercise the extract + move + relaunch logic against a fixture zip
  /// without needing a live network.
  func download(release: GitHubRelease, onProgress: @escaping (Double) -> Void) async throws -> URL {
    guard let asset = release.assets.first(where: { $0.name.hasSuffix(".zip") }) else {
      throw UpdateError.noZipAsset
    }
    guard let url = URL(string: asset.browserDownloadURL) else {
      throw UpdateError.invalidURL
    }

    let delegate = DownloadDelegate(onProgress: onProgress)
    let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
    let (tempURL, response) = try await session.download(from: url)
    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
      throw UpdateError.downloadFailed
    }

    let zipPath = FileManager.default.temporaryDirectory.appendingPathComponent(asset.name)
    try? FileManager.default.removeItem(at: zipPath)
    try FileManager.default.moveItem(at: tempURL, to: zipPath)
    return zipPath
  }

  /// Extracts a downloaded zip, finds the `.app` bundle inside, replaces the
  /// install destination with it, then relaunches Notifly from the new
  /// location and terminates the current process.
  ///
  /// In test mode (NOTIFLY_SKIP_RELAUNCH=1) the relaunch + terminate steps
  /// are skipped so the test host isn't killed.
  func install(zipAt zipPath: URL) async throws {
    let extractDir = FileManager.default.temporaryDirectory.appendingPathComponent("Notifly-update-\(UUID().uuidString)")
    try? FileManager.default.removeItem(at: extractDir)
    try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: extractDir) }

    let ditto = Process()
    ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
    ditto.arguments = ["-xk", zipPath.path, extractDir.path]
    try ditto.run()
    ditto.waitUntilExit()
    guard ditto.terminationStatus == 0 else { throw UpdateError.extractFailed }

    let contents = try FileManager.default.contentsOfDirectory(at: extractDir, includingPropertiesForKeys: nil)
    guard let appBundle = contents.first(where: { $0.pathExtension == "app" }) else {
      throw UpdateError.noAppInZip
    }

    let destination = Self.installDestination
    // Ensure the destination directory exists (parent only — the .app itself
    // will be placed as a directory at the destination path).
    let parent = destination.deletingLastPathComponent()
    try? FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

    if FileManager.default.fileExists(atPath: destination.path) {
      try FileManager.default.removeItem(at: destination)
    }
    try FileManager.default.moveItem(at: appBundle, to: destination)

    if Self.skipRelaunch { return }

    let open = Process()
    open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    open.arguments = [destination.path]
    try open.run()

    await MainActor.run {
      NSApplication.shared.terminate(nil)
    }
  }

  // MARK: - Version comparison

  func isNewer(_ remote: String, than local: String) -> Bool {
    let r = remote.split(separator: ".").compactMap { Int($0) }
    let l = local.split(separator: ".").compactMap { Int($0) }
    for i in 0..<max(r.count, l.count) {
      let rv = i < r.count ? r[i] : 0
      let lv = i < l.count ? l[i] : 0
      if rv > lv { return true }
      if rv < lv { return false }
    }
    return false
  }

  // MARK: - Errors

  enum UpdateError: LocalizedError {
    case noZipAsset, invalidURL, downloadFailed, extractFailed, noAppInZip

    var errorDescription: String? {
      switch self {
      case .noZipAsset:     return "Release has no .zip asset"
      case .invalidURL:     return "Invalid download URL"
      case .downloadFailed: return "Download failed"
      case .extractFailed:  return "Failed to extract update"
      case .noAppInZip:     return "No .app found in archive"
      }
    }
  }
}

// MARK: - Download progress delegate

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
  let onProgress: (Double) -> Void

  init(onProgress: @escaping (Double) -> Void) {
    self.onProgress = onProgress
  }

  func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                  didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                  totalBytesExpectedToWrite: Int64) {
    guard totalBytesExpectedToWrite > 0 else { return }
    let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
    onProgress(progress)
  }

  func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                  didFinishDownloadingTo location: URL) {}
}
