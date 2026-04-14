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

  // LIVE_MODE (set via NOTIFLY_LIVE_MODE=1) makes the test suite use the
  // REAL socket path and skip its mock server setup. Used by the
  // test_auto_clear_live.sh orchestration which launches a real Notifly
  // app alongside the test and verifies end-to-end with screenshots.
  const liveMode = process.env.NOTIFLY_LIVE_MODE === "1";

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

  const configFile = path.join(tmpDir, "test-config.json");
  fs.writeFileSync(
    configFile,
    JSON.stringify({ mockSocketPath, workspacePath, liveMode })
  );

  const extensionTestsEnv = {
    NOTIFLY_TEST_CONFIG: configFile,
  };
  if (liveMode) {
    extensionTestsEnv.NOTIFLY_LIVE_MODE = "1";
    // In live mode the extension uses the DEFAULT socket path (the real
    // Notifly app is running and listening there). Do NOT set
    // NOTIFLY_SOCKET_PATH — we want the extension to behave exactly as it
    // does in production.
  } else {
    extensionTestsEnv.NOTIFLY_SOCKET_PATH = mockSocketPath;
  }

  try {
    const exitCode = await runTests({
      extensionDevelopmentPath,
      extensionTestsPath,
      extensionTestsEnv,
    });
    process.exit(exitCode);
  } catch (err) {
    console.error("Integration test run failed:", err);
    process.exit(1);
  }
}

main();
