// End-to-end integration test: proves that when a user types in a real file
// inside a VS Code editor, the Notifly extension observes the text-change
// event, resolves the correct project name, connects to the Unix socket,
// and writes the expected `{"type":"active","project":"..."}` payload.
//
// This is the test the user was right to demand. Earlier "auto-clear" coverage
// only exercised the server side by writing the exact bytes directly to the
// socket — it never proved the extension itself fires on keystrokes inside
// a real VS Code editor.

const assert = require("assert");
const net = require("net");
const fs = require("fs");
const path = require("path");

const vscode = require("vscode");

suite("Notifly auto-clear integration", () => {
  let server;
  let receivedMessages;
  let configFile;
  let mockSocketPath;
  let workspacePath;
  let liveMode;

  suiteSetup(async () => {
    // Read the test config written by runTest.js. It tells us where the mock
    // socket should live and where the fixture workspace is.
    configFile = process.env.NOTIFLY_TEST_CONFIG;
    assert.ok(configFile, "NOTIFLY_TEST_CONFIG env var must be set by runTest.js");
    const config = JSON.parse(fs.readFileSync(configFile, "utf8"));
    mockSocketPath = config.mockSocketPath;
    workspacePath = config.workspacePath;
    liveMode = config.liveMode === true;

    // LIVE mode — no mock, the extension writes to the real Notifly socket
    // and an external orchestration script verifies the card cleared via
    // screenshot diff. We still wait briefly for the extension to activate.
    if (liveMode) {
      receivedMessages = null;
      server = null;
      await sleep(500);
      return;
    }

    // Stand up a mock Unix socket server at the expected path. Every message
    // received gets pushed into `receivedMessages` for the test to inspect.
    receivedMessages = [];
    try {
      fs.unlinkSync(mockSocketPath);
    } catch (_) {}
    server = net.createServer((client) => {
      let buf = "";
      client.on("data", (chunk) => {
        buf += chunk.toString("utf8");
        // Messages are newline-delimited JSON. Consume full lines.
        let idx;
        while ((idx = buf.indexOf("\n")) !== -1) {
          const line = buf.slice(0, idx).trim();
          buf = buf.slice(idx + 1);
          if (line.length > 0) {
            try {
              receivedMessages.push(JSON.parse(line));
            } catch (e) {
              receivedMessages.push({ _raw: line, _parseError: e.message });
            }
          }
        }
        // The extension expects a single-line response so it can close
        // cleanly. Mirror what the real app sends.
        try {
          client.write('{"ok":true}\n');
        } catch (_) {}
      });
      client.on("error", () => {});
    });
    await new Promise((resolve, reject) => {
      server.listen(mockSocketPath, (err) => (err ? reject(err) : resolve()));
    });

    // Wait a moment for the extension to activate. onStartupFinished fires
    // ~immediately after VS Code launches; give the extension host time.
    await sleep(500);
  });

  suiteTeardown(async () => {
    if (server) {
      await new Promise((resolve) => server.close(resolve));
    }
    try {
      fs.unlinkSync(mockSocketPath);
    } catch (_) {}
  });

  test("extension is activated after VS Code launch", async () => {
    const ext = vscode.extensions.getExtension("notiflyz.notifly-vscode");
    assert.ok(ext, "notiflyz.notifly-vscode extension must be installed in test host");
    if (!ext.isActive) {
      await ext.activate();
    }
    assert.ok(ext.isActive, "notiflyz.notifly-vscode must be active after VS Code startup");
  });

  test("editing a file fires an active ping with the right project name", async () => {
    // Open the fixture file that lives under .../Projects/TestProject/
    const fileUri = vscode.Uri.file(path.join(workspacePath, "hello.txt"));
    const doc = await vscode.workspace.openTextDocument(fileUri);
    const editor = await vscode.window.showTextDocument(doc);

    if (!liveMode) {
      // Reset the message buffer so we only see edits from this test.
      receivedMessages.length = 0;
    }

    // Fire a REAL edit via the VS Code API. This is the same code path that
    // a user typing a character goes through — it produces an
    // onDidChangeTextDocument event. Importantly, the contentChanges array
    // will be non-empty, which is what the extension checks.
    const edited = await editor.edit((builder) => {
      builder.insert(new vscode.Position(0, 0), "x");
    });
    assert.ok(edited, "edit must apply");

    if (liveMode) {
      // In live mode we can't inspect the real Notifly app from inside this
      // process. Just give the debounce + socket write time to complete.
      // The external orchestration script will verify via screenshot diff.
      await sleep(900);
      return;
    }

    // Wait for the extension's 500ms debounce plus a buffer for the async
    // socket write.
    await waitFor(
      () => receivedMessages.length > 0,
      2000,
      "no message received on the mock socket within 2s"
    );

    assert.strictEqual(
      receivedMessages.length,
      1,
      `expected exactly 1 message, got ${receivedMessages.length}: ${JSON.stringify(receivedMessages)}`
    );
    const msg = receivedMessages[0];
    assert.strictEqual(msg.type, "active", `message type must be 'active', got ${msg.type}`);
    assert.strictEqual(
      msg.project,
      "TestProject",
      `project must resolve to 'TestProject' via the walk-up-to-Projects logic, got '${msg.project}'`
    );

    // Undo the edit to leave the fixture file clean.
    await vscode.commands.executeCommand("undo");
  });

  test("a second edit within debounce is suppressed, a later edit goes through", async function () {
    if (liveMode) {
      this.skip();
      return;
    }
    const fileUri = vscode.Uri.file(path.join(workspacePath, "hello.txt"));
    const doc = await vscode.workspace.openTextDocument(fileUri);
    const editor = await vscode.window.showTextDocument(doc);

    // Previous test's edit updated the extension's internal lastPingByProject
    // map. Wait past the debounce window so THIS test starts from a clean
    // slate and the first edit is guaranteed to fire.
    await sleep(600);
    receivedMessages.length = 0;

    // First edit — should fire
    await editor.edit((b) => b.insert(new vscode.Position(0, 0), "a"));
    await waitFor(() => receivedMessages.length === 1, 2000, "first edit didn't ping");

    // Second edit immediately — should be debounced away
    await editor.edit((b) => b.insert(new vscode.Position(0, 0), "b"));
    await sleep(100);
    assert.strictEqual(
      receivedMessages.length,
      1,
      "second edit within the debounce window should NOT produce a second ping"
    );

    // Wait past the debounce and edit again — should fire
    await sleep(600);
    await editor.edit((b) => b.insert(new vscode.Position(0, 0), "c"));
    await waitFor(() => receivedMessages.length === 2, 2000, "post-debounce edit didn't ping");

    // Cleanup
    for (let i = 0; i < 3; i++) {
      await vscode.commands.executeCommand("undo");
    }
  });
});

// ---- helpers ----

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function waitFor(predicate, timeoutMs, errMsg) {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    if (predicate()) return;
    await sleep(50);
  }
  throw new Error(errMsg);
}
