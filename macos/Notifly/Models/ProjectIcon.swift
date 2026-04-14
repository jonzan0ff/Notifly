import Foundation

/// Pure helpers for deriving project icon presentation from a project name.
/// Extracted from NotificationCardView so they're directly unit-testable.
enum ProjectIcon {

  /// Two-character initial glyph for a project name.
  /// - "Camp Clintondale" → "CC"
  /// - "Dorothy" → "DO"
  /// - "X" → "X"
  /// - "" → ""
  static func initials(for name: String) -> String {
    let words = name.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
    if words.count >= 2 {
      return String(words.prefix(2).compactMap { $0.first }).uppercased()
    }
    return String(name.prefix(2)).uppercased()
  }

  /// Deterministic hash of `name` into `[0, paletteCount)` for color selection.
  /// Same name always produces the same index for the same palette size.
  static func paletteIndex(for name: String, paletteCount: Int) -> Int {
    guard paletteCount > 0 else { return 0 }
    var hash: UInt64 = 5381
    for byte in name.utf8 {
      hash = ((hash << 5) &+ hash) &+ UInt64(byte)
    }
    return Int(hash % UInt64(paletteCount))
  }
}
