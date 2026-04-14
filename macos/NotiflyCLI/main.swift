import Foundation
import Darwin

// notifly — small CLI that talks to the running Notifly app over a Unix socket.
//
// Usage:
//   notifly send   --project <name> --event <done|attention|stopped> --message <text>
//   notifly active --project <name>
//
// If the Notifly app is not running, the CLI launches it silently and retries.

let socketPath: String = {
  let dir = ("~/Library/Application Support/Notifly" as NSString).expandingTildeInPath
  return (dir as NSString).appendingPathComponent("notifly.sock")
}()

let appBundleID = "com.Notiflyz.app"
let installedAppPath = "/Applications/Notifly.app"

// MARK: - Arg parsing

func argValue(_ name: String) -> String? {
  let args = CommandLine.arguments
  guard let idx = args.firstIndex(of: name), idx + 1 < args.count else { return nil }
  return args[idx + 1]
}

func die(_ message: String, code: Int32 = 1) -> Never {
  FileHandle.standardError.write(Data((message + "\n").utf8))
  exit(code)
}

func usage() -> Never {
  die("""
  usage:
    notifly send   --project <name> --event <done|attention|stopped> --message <text> [--icon <path>]
    notifly active --project <name>
    notifly clear
  """)
}

guard CommandLine.arguments.count >= 2 else { usage() }
let command = CommandLine.arguments[1]

var payload: [String: String] = [:]

switch command {
case "send":
  guard let project = argValue("--project"),
        let event = argValue("--event"),
        let message = argValue("--message") else { usage() }
  payload = ["type": "send", "project": project, "event": event, "message": message]
  if let icon = argValue("--icon"), FileManager.default.fileExists(atPath: icon) {
    payload["iconPath"] = icon
  }

case "active":
  guard let project = argValue("--project") else { usage() }
  payload = ["type": "active", "project": project]

case "clear":
  payload = ["type": "clear"]

default:
  usage()
}

// MARK: - Connect + send

func connectSocket() -> Int32 {
  let fd = socket(AF_UNIX, SOCK_STREAM, 0)
  guard fd >= 0 else { return -1 }

  var addr = sockaddr_un()
  addr.sun_family = sa_family_t(AF_UNIX)
  let pathData = Data(socketPath.utf8)
  withUnsafeMutableBytes(of: &addr.sun_path) { rawPtr in
    pathData.withUnsafeBytes { src in
      let count = min(pathData.count, rawPtr.count - 1)
      memcpy(rawPtr.baseAddress!, src.baseAddress!, count)
    }
  }

  let len = socklen_t(MemoryLayout<sockaddr_un>.size)
  let result = withUnsafePointer(to: &addr) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
      Darwin.connect(fd, sockPtr, len)
    }
  }
  if result != 0 {
    close(fd)
    return -1
  }
  return fd
}

func send(payload: [String: String]) -> Bool {
  signal(SIGPIPE, SIG_IGN)
  let fd = connectSocket()
  guard fd >= 0 else { return false }
  defer { close(fd) }

  guard let json = try? JSONSerialization.data(withJSONObject: payload) else { return false }
  var bytes = [UInt8](json)
  bytes.append(0x0a)
  let written = bytes.withUnsafeBufferPointer { buf in
    write(fd, buf.baseAddress, buf.count)
  }
  guard written == bytes.count else { return false }

  // Wait for the server's response so the handshake is complete before we close
  // our end. Without this, the server may still be writing when we exit, and
  // would hit SIGPIPE on a stricter peer.
  var response = [UInt8](repeating: 0, count: 256)
  _ = read(fd, &response, response.count)
  return true
}

func launchAppIfNeeded() {
  // Try the installed location first.
  if FileManager.default.fileExists(atPath: installedAppPath) {
    let proc = Process()
    proc.launchPath = "/usr/bin/open"
    proc.arguments = ["-g", "-b", appBundleID]
    try? proc.run()
    return
  }
  // Fallback: ask LaunchServices to open it by bundle ID.
  let proc = Process()
  proc.launchPath = "/usr/bin/open"
  proc.arguments = ["-g", "-b", appBundleID]
  try? proc.run()
}

// MARK: - Main

if send(payload: payload) {
  exit(0)
}

// Socket missing or refused — try launching the app and retrying for ~3s.
launchAppIfNeeded()

for _ in 0..<30 {
  usleep(100_000)
  if send(payload: payload) { exit(0) }
}

die("notifly: could not reach the Notifly app at \(socketPath)")
