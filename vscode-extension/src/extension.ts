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
const DEBOUNCE_MS = 1500;
const HEARTBEAT_MS = 2000;

/**
 * Walk up from a file path until the parent directory is "Projects". The
 * basename of the directory directly under Projects is the project name. This
 * groups sub-repos (Camp Clintondale/admin, Camp Clintondale/guest) under the
 * top-level project name, matching ~/.claude/hooks/notify-desktop.sh.
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

function log(msg: string): void {
  try {
    const ts = new Date().toISOString();
    fs.appendFileSync(LOG_PATH, `[${ts}] ${msg}\n`);
  } catch {
    // best effort
  }
}

/**
 * True if the active tab in any tab group is a Claude Code webview.
 * Matches by viewType (authoritative) with a label fallback.
 */
function isClaudeTabActive(): boolean {
  try {
    const tab = vscode.window.tabGroups.activeTabGroup.activeTab;
    if (!tab) return false;
    const input = tab.input as { viewType?: string } | undefined;
    const viewType = input && typeof input.viewType === "string" ? input.viewType : "";
    if (viewType.indexOf("claudeVSCodePanel") !== -1) return true;
    const label = tab.label || "";
    if (/claude/i.test(label)) return true;
    return false;
  } catch {
    return false;
  }
}

function currentWorkspaceProject(): string | undefined {
  const folder = vscode.workspace.workspaceFolders?.[0];
  if (!folder) return undefined;
  const viaRoot = projectRootForPath(folder.uri.fsPath + "/_");
  return viaRoot || folder.name;
}

export function activate(context: vscode.ExtensionContext) {
  log(`activate — socket=${SOCKET_PATH} debounce=${DEBOUNCE_MS}ms heartbeat=${HEARTBEAT_MS}ms`);

  const output = vscode.window.createOutputChannel("Notifly");
  output.appendLine(`[Notifly] extension activated at ${new Date().toISOString()}`);
  output.appendLine(`[Notifly] socket: ${SOCKET_PATH}`);

  const lastPingByProject = new Map<string, number>();

  const sendActive = (project: string, reason: string) => {
    const now = Date.now();
    const last = lastPingByProject.get(project) ?? 0;
    const elapsed = now - last;
    if (elapsed < DEBOUNCE_MS) {
      return;
    }
    lastPingByProject.set(project, now);

    if (!fs.existsSync(SOCKET_PATH)) {
      log(`socket missing — skipping ${project} (${reason})`);
      return;
    }

    const payload = JSON.stringify({ type: "active", project }) + "\n";
    log(`-> ${payload.trim()} (reason=${reason})`);

    const client = net.createConnection(SOCKET_PATH, () => {
      client.write(payload, () => {
        client.end();
      });
    });
    client.on("error", (err) => {
      log(`socket error writing ${project}: ${err.message}`);
      output.appendLine(`[Notifly] socket write failed: ${err.message}`);
    });
  };

  const pingIfEngaged = (reason: string) => {
    const project = currentWorkspaceProject();
    if (!project) return;
    const focused = vscode.window.state.focused;
    const claudeActive = isClaudeTabActive();
    if (focused && claudeActive) {
      sendActive(project, reason);
    }
  };

  // Signal 1: file typing (file-document change). Keeps the old behavior
  // working for users who are editing source files, not chatting.
  context.subscriptions.push(
    vscode.workspace.onDidChangeTextDocument((e) => {
      if (e.contentChanges.length === 0) return;
      if (e.document.uri.scheme !== "file") return;
      const project = projectRootForPath(e.document.uri.fsPath)
        || vscode.workspace.getWorkspaceFolder(e.document.uri)?.name;
      if (project) sendActive(project, "text-change");
    })
  );

  // Signal 2: VS Code window gains OS focus with a Claude tab already active.
  context.subscriptions.push(
    vscode.window.onDidChangeWindowState((e) => {
      if (e.focused) pingIfEngaged("window-focus");
    })
  );

  // Signal 3: active tab becomes a Claude webview (from another tab, or a new open).
  context.subscriptions.push(
    vscode.window.tabGroups.onDidChangeTabs(() => {
      pingIfEngaged("tab-change");
    })
  );
  context.subscriptions.push(
    vscode.window.tabGroups.onDidChangeTabGroups(() => {
      pingIfEngaged("tab-group-change");
    })
  );

  // Signal 4: heartbeat while the window is focused and the Claude tab is active.
  // Covers "user is already sitting in the prompt field when a card arrives".
  const heartbeat = setInterval(() => {
    pingIfEngaged("heartbeat");
  }, HEARTBEAT_MS);
  context.subscriptions.push({ dispose: () => clearInterval(heartbeat) });

  log(`handlers registered`);
}

export function deactivate() {}
