import SwiftUI
import AppKit

@main
struct NotiflyApp: App {

  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  var body: some Scene {
    Settings {
      EmptyView()
    }
  }
}

final class AppDelegate: NSObject, NSApplicationDelegate {

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSSetUncaughtExceptionHandler { exception in
      NSLog("[Notifly FATAL] \(exception.name.rawValue) — \(exception.reason ?? "no reason")")
      NSLog("[Notifly FATAL] \(exception.callStackSymbols.joined(separator: "\n"))")
    }
    enforceSingleInstance()
    MenuBarController.shared.install()
    NotificationStackManager.shared.start()
    IPCServer.shared.start()
    Task { AppState.shared.startDailyUpdateCheck() }
  }

  private func enforceSingleInstance() {
    let bundleID = Bundle.main.bundleIdentifier ?? ""
    let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
      .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
    if !others.isEmpty {
      others.forEach { $0.forceTerminate() }
      Thread.sleep(forTimeInterval: 0.5)
    }
  }
}
