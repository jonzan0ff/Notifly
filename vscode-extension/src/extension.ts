import * as vscode from "vscode";
import * as net from "net";
import * as os from "os";
import * as path from "path";
import * as fs from "fs";

const SOCKET_PATH = process.env.NOTIFLY_SOCKET_PATH || path.join(
  os.homedir(),
  "Library",
  "Application Support",
  "Notifly",
  "notifly.sock"
);

const LOG_PATH = "/tmp/notifly-vscode-extension.log";
const DEBOUNCE_MS = 500;

/**
 * Project grouping: walk up from a file path until the parent directory is
 * "Projects". The basename of the directory directly under Projects is the
 * project name. This matches the behavior of ~/.claude/hooks/notify-desktop.sh
 * so a sub-repo like Camp Clintondale/admin maps to "Camp Clintondale" — the
 * same name Notifly is tracking. Without this, the hook would tag a card
 * "Camp Clintondale" but the extension would ping "active" for "admin",
 * leaving the card forever.
 */
function projectRootForPath(filePath: string): string | undefined {
  let dir = path.dirname(filePath);
  while (dir && dir !== "/" && dir !== ".") {
    const parent = path.dirname(dir);
    if (path.basename(parent) === "Projects") {
      return path.basename(dir);
    }
    dir = parent;
  }
  return undefined;
}

/** Append a line to /tmp/notifly-vscode-extension.log with a timestamp. */
function log(msg: string): void {
  try {
    const ts = new Date().toISOString();
    fs.appendFileSync(LOG_PATH, `[${ts}] ${msg}\n`);
  } catch {
    // best-effort; we don't want logging failures to crash the extension
  }
}

export function activate(context: vscode.ExtensionContext) {
  log(`activate — socket=${SOCKET_PATH} debounce=${DEBOUNCE_MS}ms`);

  const output = vscode.window.createOutputChannel("Notifly");
  output.appendLine(`[Notifly] extension activated at ${new Date().toISOString()}`);
  output.appendLine(`[Notifly] socket: ${SOCKET_PATH}`);

  const lastPingByProject = new Map<string, number>();

  const sendActive = (project: string, reason: string) => {
    const now = Date.now();
    const last = lastPingByProject.get(project) ?? 0;
    const elapsed = now - last;
    if (elapsed < DEBOUNCE_MS) {
      log(`debounced ${project} (${elapsed}ms since last, reason=${reason})`);
      return;
    }
    lastPingByProject.set(project, now);

    if (!fs.existsSync(SOCKET_PATH)) {
      log(`socket missing at ${SOCKET_PATH} — skipping ${project}`);
      output.appendLine(`[Notifly] socket missing — is the Notifly app running?`);
      return;
    }

    const payload = JSON.stringify({ type: "active", project }) + "\n";
    log(`-> ${payload.trim()} (reason=${reason})`);

    const client = net.createConnection(SOCKET_PATH, () => {
      client.write(payload, () => {
        client.end();
        log(`ok wrote ${payload.trim()}`);
      });
    });
    client.on("error", (err) => {
      log(`socket error writing ${project}: ${err.message}`);
      output.appendLine(`[Notifly] socket write failed: ${err.message}`);
    });
  };

  const projectFor = (uri: vscode.Uri): string | undefined => {
    const folder = vscode.workspace.getWorkspaceFolder(uri);
    if (folder) {
      const folderRoot = projectRootForPath(folder.uri.fsPath + "/_");
      if (folderRoot) {
        log(`projectFor(${uri.fsPath}) via workspace → ${folderRoot}`);
        return folderRoot;
      }
      log(`projectFor(${uri.fsPath}) fallback to folder.name → ${folder.name}`);
      return folder.name;
    }
    const fallback = projectRootForPath(uri.fsPath);
    log(`projectFor(${uri.fsPath}) no workspace → ${fallback}`);
    return fallback;
  };

  context.subscriptions.push(
    vscode.workspace.onDidChangeTextDocument((e) => {
      if (e.contentChanges.length === 0) return;
      // Only handle real file documents — skip settings previews, output
      // panels, webviews, untitled scratch, etc.
      if (e.document.uri.scheme !== "file") {
        log(`skip non-file scheme: ${e.document.uri.scheme}`);
        return;
      }
      log(`onDidChangeTextDocument uri=${e.document.uri.fsPath} changes=${e.contentChanges.length}`);
      const project = projectFor(e.document.uri);
      if (project) sendActive(project, "onDidChangeTextDocument");
    })
  );

  log(`event handler registered`);
}

export function deactivate() {}
