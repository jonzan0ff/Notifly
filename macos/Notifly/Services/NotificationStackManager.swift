import Foundation
import SwiftUI
import AppKit
import Combine

/// Source of truth for the currently visible notification stack.
/// One entry per project — a new event for an existing project replaces the old one.
final class NotificationStackManager: ObservableObject {

  static let shared = NotificationStackManager()

  @Published private(set) var events: [NotiflyEvent] = []

  private var windowController: NotificationStackWindowController?

  func start() {
    windowController = NotificationStackWindowController(manager: self)
    windowController?.showWindow(nil)
  }

  func submit(_ event: NotiflyEvent) {
    DispatchQueue.main.async {
      self.events.removeAll { $0.project == event.project }
      self.events.insert(event, at: 0)
    }
  }

  func clearProject(_ project: String) {
    DispatchQueue.main.async {
      self.events.removeAll { $0.project == project }
    }
  }

  func clearAll() {
    DispatchQueue.main.async {
      self.events.removeAll()
    }
  }

  func dismiss(_ event: NotiflyEvent) {
    DispatchQueue.main.async {
      self.events.removeAll { $0.id == event.id }
    }
  }
}
