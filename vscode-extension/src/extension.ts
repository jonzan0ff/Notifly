import * as vscode from "vscode";
import * as net from "net";
import * as os from "os";
import * as path from "path";
import * as fs from "fs";

const SOCKET_PATH = path.join(
  os.homedir(),
  "Library",
  "Application Support",
  "Notifly",
  "notifly.sock"
);

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

export function activate(context: vscode.ExtensionContext) {
  const lastPingByProject = new Map<string, number>();

  const sendActive = (project: string) => {
    const now = Date.now();
    const last = lastPingByProject.get(project) ?? 0;
    if (now - last < DEBOUNCE_MS) return;
    lastPingByProject.set(project, now);

    const payload = JSON.stringify({ type: "active", project }) + "\n";

    if (!fs.existsSync(SOCKET_PATH)) return;

    const client = net.createConnection(SOCKET_PATH, () => {
      client.write(payload, () => client.end());
    });
    client.on("error", () => {
      // Notifly app not running — silently drop. The CLI will launch it on the
      // next send.
    });
  };

  const projectFor = (uri: vscode.Uri): string | undefined => {
    // Try the workspace folder first — fast path when the workspace IS the
    // project root (e.g. opening Notifly directly).
    const folder = vscode.workspace.getWorkspaceFolder(uri);
    if (folder) {
      const folderRoot = projectRootForPath(folder.uri.fsPath + "/_");
      if (folderRoot) return folderRoot;
      return folder.name;
    }
    // No workspace — fall back to walking up from the file path itself.
    return projectRootForPath(uri.fsPath);
  };

  context.subscriptions.push(
    vscode.workspace.onDidChangeTextDocument((e) => {
      if (e.contentChanges.length === 0) return;
      const project = projectFor(e.document.uri);
      if (project) sendActive(project);
    })
  );
}

export function deactivate() {}
