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
      // Notifly app not running — silently drop. The CLI will launch it on the next send.
    });
  };

  const projectFor = (uri: vscode.Uri): string | undefined => {
    const folder = vscode.workspace.getWorkspaceFolder(uri);
    return folder?.name;
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
