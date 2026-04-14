// Integration test launcher — boots a headless VS Code instance with the
// Notifly extension loaded, opens a test file inside a fake Projects/<name>
// workspace, fires a real edit through the VS Code API, and asserts that the
// extension wrote an "active" ping to a mock Unix socket.
//
// Run via: npm run test:integration

const path = require("path");
const os = require("os");
const fs = require("fs");

const { runTests } = require("@vscode/test-electron");

async function main() {
  const extensionDevelopmentPath = path.resolve(__dirname, "..", "..");
  const extensionTestsPath = path.resolve(__dirname, "suite", "index.js");

  // Use a temp socket path that's NOT the real one so we don't interfere with
  // the running Notifly app. The extension reads NOTIFLY_SOCKET_PATH at
  // activation time.
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "notifly-test-"));
  const mockSocketPath = path.join(tmpDir, "notifly.sock");

  // Workspace path — the test fixture lives under .../Projects/TestProject
  // so the extension's project-grouping logic resolves the file's project
  // name to "TestProject".
  const workspacePath = path.resolve(
    __dirname,
    "fixtures",
    "Projects",
    "TestProject"
  );

  // Write the mock socket path into a file the test suite can read, since
  // environment variables don't always propagate through @vscode/test-electron
  // reliably.
  const configFile = path.join(tmpDir, "test-config.json");
  fs.writeFileSync(
    configFile,
    JSON.stringify({ mockSocketPath, workspacePath })
  );

  process.env.NOTIFLY_SOCKET_PATH = mockSocketPath;
  process.env.NOTIFLY_TEST_CONFIG = configFile;

  try {
    const exitCode = await runTests({
      extensionDevelopmentPath,
      extensionTestsPath,
      // No launchArgs — we open the test file from inside the suite via
      // vscode.workspace.openTextDocument(). Passing a workspace path here
      // confuses Electron's raw arg parser on macOS.
      extensionTestsEnv: {
        NOTIFLY_SOCKET_PATH: mockSocketPath,
        NOTIFLY_TEST_CONFIG: configFile,
      },
    });
    process.exit(exitCode);
  } catch (err) {
    console.error("Integration test run failed:", err);
    process.exit(1);
  }
}

main();
