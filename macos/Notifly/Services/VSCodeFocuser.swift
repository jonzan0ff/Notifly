import AppKit
import ApplicationServices

/// Brings the VS Code window for a given project to the foreground.
///
/// VS Code window titles look like "<filename> — <projectFolderName>" so we
/// find the window whose title ends with the project name and raise it.
/// If no exact match is found, we fall back to activating the VS Code app
/// without specifying a window.
enum VSCodeFocuser {

  static func focusWindow(forProject project: String) {
    let bundleIDs = ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders"]

    for bundleID in bundleIDs {
      guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
        continue
      }

      // Try to raise the specific window via the Accessibility API. Requires
      // the user to have granted Notifly accessibility permission once.
      if let windowRef = findWindow(forApp: app, projectName: project) {
        AXUIElementPerformAction(windowRef, kAXRaiseAction as CFString)
      }

      // Activate the VS Code app itself. The deprecated `activateIgnoringOtherApps`
      // option is replaced by the no-arg `activate(options:)` form, which is the
      // current API for macOS 14+.
      app.activate(options: [])
      return
    }
  }

  /// Walks the AXUIElement window list of the given app, returning the first
  /// window whose title contains the project name. Nil if no match or if the
  /// accessibility permission hasn't been granted.
  private static func findWindow(forApp app: NSRunningApplication, projectName: String) -> AXUIElement? {
    let appRef = AXUIElementCreateApplication(app.processIdentifier)
    var value: AnyObject?
    let result = AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &value)
    guard result == .success, let windows = value as? [AXUIElement] else {
      return nil
    }

    for window in windows {
      var titleValue: AnyObject?
      AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue)
      if let title = titleValue as? String, title.contains(projectName) {
        return window
      }
    }
    return nil
  }
}
