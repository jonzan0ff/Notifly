// Mocha test suite bootstrap — required by @vscode/test-electron. Loads all
// *.test.js files in this folder and runs them with a 30s per-test timeout.

const path = require("path");
const Mocha = require("mocha");
const fs = require("fs");

function run() {
  const mocha = new Mocha({
    ui: "tdd",
    color: true,
    timeout: 30000,
  });

  const testsRoot = __dirname;

  return new Promise((resolve, reject) => {
    const testFiles = fs
      .readdirSync(testsRoot)
      .filter((f) => f.endsWith(".test.js"));

    testFiles.forEach((f) => mocha.addFile(path.join(testsRoot, f)));

    try {
      mocha.run((failures) => {
        if (failures > 0) {
          reject(new Error(`${failures} test(s) failed.`));
        } else {
          resolve();
        }
      });
    } catch (err) {
      console.error(err);
      reject(err);
    }
  });
}

module.exports = { run };
