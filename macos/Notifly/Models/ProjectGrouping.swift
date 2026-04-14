import Foundation

/// Resolves a filesystem path to a Notifly project name. Sub-repos under a
/// `Projects/X/...` directory all collapse to "X" so that, for example,
/// `Camp Clintondale/admin` and `Camp Clintondale/guest` both produce a single
/// "Camp Clintondale" notification stack entry instead of two competing ones.
///
/// This logic must stay in lockstep with:
/// - `~/.claude/hooks/notify-desktop.sh`  (the bash hook that fires sends)
/// - `vscode-extension/src/extension.ts`  (the TS extension that fires actives)
///
/// The fixture table in `ProjectGroupingTests` is the shared contract — every
/// implementation is expected to produce identical results for it.
enum ProjectGrouping {

  /// Walks up from `path` until the parent directory's basename is "Projects",
  /// at which point the current directory's basename is the project name.
  /// Falls back to the leaf basename if no `Projects` ancestor is found.
  static func projectName(forPath path: String) -> String {
    var current = (path as NSString).standardizingPath
    // If the input path doesn't exist, treat it lexically — don't try to follow
    // symlinks or stat the filesystem.
    while current != "/" && !current.isEmpty {
      let parent = (current as NSString).deletingLastPathComponent
      if (parent as NSString).lastPathComponent == "Projects" {
        return (current as NSString).lastPathComponent
      }
      if parent == current { break } // safety against infinite loop on malformed input
      current = parent
    }
    return (path as NSString).lastPathComponent
  }
}
