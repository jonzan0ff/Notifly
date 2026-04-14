import Foundation
import SwiftUI
import AppKit
import Combine

/// Source of truth for the currently visible notification stack.
/// One entry per project — a new event for an existing project replaces the old one.
final class NotificationStackManager: ObservableObject {

  static let shared = NotificationStackManager()

  /// How long after the last `active` ping for a project we should suppress
  /// new cards for that project. Heartbeat pings fire every 2s from the VS
  /// Code extension while the user is engaged, so 4s gives one ping of slack.
  static let suppressionWindow: TimeInterval = 4.0

  @Published private(set) var events: [NotiflyEvent] = []

  /// Last time each project fired an `active` ping. Used to drop cards that
  /// arrive while the user is already engaged with the project.
  private var lastActivePingByProject: [String: Date] = [:]

  private var windowController: NotificationStackWindowController?

  func start() {
    windowController = NotificationStackWindowController(manager: self)
    windowController?.showWindow(nil)
  }

  func submit(_ event: NotiflyEvent) {
    DispatchQueue.main.async {
      if let last = self.lastActivePingByProject[event.project],
         Date().timeIntervalSince(last) < Self.suppressionWindow {
        NSLog("[NotificationStackManager] suppressing card for \(event.project) — active within \(Self.suppressionWindow)s")
        return
      }
      self.events.removeAll { $0.project == event.project }
      self.events.insert(event, at: 0)
    }
  }

  func clearProject(_ project: String) {
    DispatchQueue.main.async {
      self.lastActivePingByProject[project] = Date()
      self.events.removeAll { $0.project == project }
    }
  }

  func clearAll() {
    DispatchQueue.main.async {
      self.events.removeAll()
      self.lastActivePingByProject.removeAll()
    }
  }

  func dismiss(_ event: NotiflyEvent) {
    DispatchQueue.main.async {
      self.events.removeAll { $0.id == event.id }
    }
  }
}
