import Foundation

enum NotiflyEventType: String, Codable {
  case done
  case attention
  case stopped
}

struct NotiflyEvent: Identifiable, Equatable {
  let id: UUID
  let project: String
  let type: NotiflyEventType
  let message: String
  let receivedAt: Date
  /// Absolute path to a per-project icon.png, if the caller provided one.
  /// The card view loads it via NSImage and falls back to initials if nil
  /// or unreadable.
  let iconPath: String?

  init(project: String, type: NotiflyEventType, message: String, iconPath: String? = nil) {
    self.id = UUID()
    self.project = project
    self.type = type
    self.message = NotiflyEvent.truncate(message)
    self.receivedAt = Date()
    self.iconPath = iconPath
  }

  private static let maxLength = 240

  private static func truncate(_ s: String) -> String {
    let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.count <= maxLength { return trimmed }
    return String(trimmed.prefix(maxLength - 1)) + "…"
  }
}

struct IPCMessage: Codable {
  let type: String
  let project: String?
  let event: String?
  let message: String?
  let iconPath: String?
}
