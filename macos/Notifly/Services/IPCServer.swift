import Foundation

/// Local Unix domain socket server. Accepts newline-delimited JSON messages from
/// the `notifly` CLI and the VS Code extension.
///
/// Message shape:
///   { "type": "send",   "project": "...", "event": "done|attention|stopped", "message": "..." }
///   { "type": "active", "project": "..." }
///   { "type": "clear" }
///
/// Response: a single line, either `{"ok":true}` or `{"ok":false,"error":"..."}`.
final class IPCServer {

  static let shared = IPCServer()

  static var socketPath: String {
    let dir = ("~/Library/Application Support/Notifly" as NSString).expandingTildeInPath
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    return (dir as NSString).appendingPathComponent("notifly.sock")
  }

  private var fd: Int32 = -1
  private var acceptSource: DispatchSourceRead?
  private let queue = DispatchQueue(label: "notifly.ipc")

  func start() {
    // Ignore SIGPIPE app-wide. Without this, writing to a socket whose peer has
    // already closed (e.g. a CLI that fired-and-forgot) terminates the whole process.
    signal(SIGPIPE, SIG_IGN)

    let path = Self.socketPath
    try? FileManager.default.removeItem(atPath: path)
    startPosixListener(at: path)
  }

  // MARK: - POSIX Unix socket listener

  private func startPosixListener(at path: String) {
    fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else {
      NSLog("[IPCServer] socket() failed: \(String(cString: strerror(errno)))")
      return
    }

    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let pathData = Data(path.utf8)
    withUnsafeMutableBytes(of: &addr.sun_path) { rawPtr in
      pathData.withUnsafeBytes { src in
        let count = min(pathData.count, rawPtr.count - 1)
        memcpy(rawPtr.baseAddress!, src.baseAddress!, count)
      }
    }

    let len = socklen_t(MemoryLayout<sockaddr_un>.size)
    let bindResult = withUnsafePointer(to: &addr) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
        bind(fd, sockPtr, len)
      }
    }
    guard bindResult == 0 else {
      NSLog("[IPCServer] bind() failed: \(String(cString: strerror(errno)))")
      close(fd); fd = -1
      return
    }

    guard listen(fd, 16) == 0 else {
      NSLog("[IPCServer] listen() failed: \(String(cString: strerror(errno)))")
      close(fd); fd = -1
      return
    }

    let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
    source.setEventHandler { [weak self] in self?.acceptOne() }
    source.resume()
    acceptSource = source

    NSLog("[IPCServer] listening at \(path)")
  }

  private func acceptOne() {
    var client: sockaddr = sockaddr()
    var len: socklen_t = socklen_t(MemoryLayout<sockaddr>.size)
    let clientFd = Darwin.accept(fd, &client, &len)
    guard clientFd >= 0 else { return }
    queue.async { [weak self] in self?.handleClient(fd: clientFd) }
  }

  private func handleClient(fd: Int32) {
    defer { close(fd) }
    var buffer = [UInt8](repeating: 0, count: 8192)
    let n = read(fd, &buffer, buffer.count)
    guard n > 0 else { return }
    let data = Data(buffer[0..<n])

    let response: String
    do {
      let msg = try JSONDecoder().decode(IPCMessage.self, from: data)
      try handle(msg)
      response = "{\"ok\":true}\n"
    } catch {
      NSLog("[IPCServer] handle error: \(error)")
      let safe = String(describing: error).replacingOccurrences(of: "\"", with: "'")
      response = "{\"ok\":false,\"error\":\"\(safe)\"}\n"
    }
    response.withCString { _ = write(fd, $0, strlen($0)) }
  }

  // MARK: - Message handling

  private func handle(_ msg: IPCMessage) throws {
    switch msg.type {
    case "send":
      guard let project = msg.project, !project.isEmpty,
            let eventStr = msg.event, let kind = NotiflyEventType(rawValue: eventStr),
            let message = msg.message else {
        throw IPCError.badRequest("send requires project, event, message")
      }
      let event = NotiflyEvent(project: project, type: kind, message: message, iconPath: msg.iconPath)
      NotificationStackManager.shared.submit(event)

    case "active":
      guard let project = msg.project, !project.isEmpty else {
        throw IPCError.badRequest("active requires project")
      }
      NotificationStackManager.shared.clearProject(project)

    case "clear":
      NotificationStackManager.shared.clearAll()

    default:
      throw IPCError.badRequest("unknown type: \(msg.type)")
    }
  }
}

enum IPCError: Error, CustomStringConvertible {
  case badRequest(String)
  var description: String {
    switch self {
    case .badRequest(let m): return "bad_request: \(m)"
    }
  }
}
