import Foundation
import Combine

@MainActor
final class AppState: ObservableObject {

  static let shared = AppState()

  @Published var availableUpdate: GitHubRelease?
  @Published var isInstallingUpdate: Bool = false
  @Published var updateProgress: Double = 0

  private init() {}

  // MARK: - Update checks

  func checkForUpdate() async {
    let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    NSLog("[AppState] checkForUpdate running — current=\(current)")
    let release = await UpdateService.shared.checkForUpdate()
    if let release {
      NSLog("[AppState] update AVAILABLE: \(release.tagName) (vs current \(current))")
    } else {
      NSLog("[AppState] no update (current=\(current))")
    }
    self.availableUpdate = release
  }

  func installUpdate() async {
    guard let release = availableUpdate else { return }
    isInstallingUpdate = true
    updateProgress = 0
    do {
      try await UpdateService.shared.downloadAndInstall(release: release) { [weak self] progress in
        Task { @MainActor in self?.updateProgress = progress }
      }
    } catch {
      NSLog("[AppState] update install failed: \(error)")
      isInstallingUpdate = false
      updateProgress = 0
    }
  }

  /// Checks for updates immediately on launch and then every 24h.
  func startDailyUpdateCheck() {
    Task {
      await checkForUpdate()
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 24 * 60 * 60 * 1_000_000_000)
        await checkForUpdate()
      }
    }
  }
}
