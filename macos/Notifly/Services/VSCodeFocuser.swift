import AppKit

/// Brings a VS Code window to the foreground when the user clicks a notification.
/// VS Code window titles look like "filename — projectFolderName" so we match on suffix.
enum VSCodeFocuser {

  static func focusWindow(forProject project: String) {
    let bundleIDs = ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders"]
    for bundleID in bundleIDs {
      guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
        continue
      }
      app.activate(options: [.activateIgnoringOtherApps])
      // TODO: Use Accessibility API (AXUIElement) to pick the specific window matching the project.
      // For v0.1 we just bring the app forward — sufficient when only one workspace is open.
      _ = project
      return
    }
  }
}
